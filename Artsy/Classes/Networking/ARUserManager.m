#import "ARUserManager.h"
#import "NSDate+Util.h"
#import "ARRouter.h"
#import <ISO8601DateFormatter/ISO8601DateFormatter.h>
#import <UICKeyChainStore/UICKeyChainStore.h>
#import <Mixpanel/Mixpanel.h>
#import "ARFileUtils.h"
#import "ArtsyAPI+Private.h"
#import "NSKeyedUnarchiver+ErrorLogging.h"
#import <ARAnalytics/ARAnalytics.h>
#import "ARAnalyticsConstants.h"

NSString *ARTrialUserNameKey = @"ARTrialUserName";
NSString *ARTrialUserEmailKey = @"ARTrialUserEmail";
NSString *ARTrialUserUUID = @"ARTrialUserUUID";

@interface ARUserManager()
@property (nonatomic, strong) User *currentUser;
@end

@implementation ARUserManager

+ (ARUserManager *)sharedManager
{
    static ARUserManager *_sharedManager = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedManager = [[self alloc] init];
    });
    return _sharedManager;
}

+ (void)identifyAnalyticsUser
{
    NSString *analyticsUserID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    [ARAnalytics identifyUserWithID:analyticsUserID andEmailAddress:nil];

    User *user = [User currentUser];
    if (user) {
        [ARAnalytics setUserProperty:@"$email" toValue:user.email];
        [ARAnalytics setUserProperty:@"user_id" toValue:user.userID];
        [ARAnalytics setUserProperty:@"user_uuid" toValue:[ARUserManager sharedManager].trialUserUUID];
        [[Mixpanel sharedInstance] registerSuperProperties: @{
            @"user_id" : user.userID ?: @"",
            @"user_uuid" : [ARUserManager sharedManager].trialUserUUID
        }];
    } else {
        [ARAnalytics setUserProperty:@"user_uuid" toValue:[ARUserManager sharedManager].trialUserUUID];
        [[Mixpanel sharedInstance] registerSuperProperties: @{
            @"user_uuid" : [ARUserManager sharedManager].trialUserUUID
        }];
    }
}

- (instancetype)init
{
    self = [super init];
    if (!self) { return nil; }

    NSString *userDataFolderPath = [self userDataPath];
    NSString *userDataPath = [userDataFolderPath stringByAppendingPathComponent:@"User.data"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:userDataPath]) {
        _currentUser = [NSKeyedUnarchiver unarchiveObjectWithFile:userDataPath
            exceptionBlock:^id(NSException *exception) {
                ARErrorLog(@"%@", exception.reason);
                [[NSFileManager defaultManager] removeItemAtPath:userDataPath error:nil];
                return nil;
            }
        ];

        // safeguard
        if (!self.currentUser.userID) {
            ARErrorLog(@"Deserialized user %@ does not have an ID.", self.currentUser);
            _currentUser = nil;
        }
    }

    return self;
}

- (BOOL)hasExistingAccount
{
    return ( _currentUser && [self hasValidAuthenticationToken] ) || [self hasValidXAppToken];
}

- (BOOL)hasValidAuthenticationToken
{
    NSString *authToken = [UICKeyChainStore stringForKey:AROAuthTokenDefault];
    NSDate *expiryDate  = [[NSUserDefaults standardUserDefaults] objectForKey:AROAuthTokenExpiryDateDefault];

    BOOL tokenValid = expiryDate && [[[ARSystemTime date] GMTDate] earlierDate:expiryDate] != expiryDate;
    return authToken && tokenValid;
}

- (BOOL)hasValidXAppToken
{
    NSString *xapp = [UICKeyChainStore stringForKey:ARXAppTokenDefault];
    NSDate *expiryDate  = [[NSUserDefaults standardUserDefaults] objectForKey:ARXAppTokenExpiryDateDefault];

    BOOL tokenValid = expiryDate && [[[ARSystemTime date] GMTDate] earlierDate:expiryDate] != expiryDate;
    return xapp && tokenValid;
}

- (void)loginWithUsername:(NSString *)username password:(NSString *)password
   successWithCredentials:(void(^)(NSString *accessToken, NSDate *expirationDate))credentials
                  gotUser:(void(^)(User *currentUser))gotUser
    authenticationFailure:(void (^)(NSError *error))authenticationFailure
           networkFailure:(void (^)(NSError *error))networkFailure {

    NSURLRequest *request = [ARRouter newOAuthRequestWithUsername:username password:password];

    AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
         success:^(NSURLRequest *oauthRequest, NSHTTPURLResponse *response, id JSON) {

             NSString *token = JSON[AROAuthTokenKey];
             NSString *expiryDateString = JSON[AROExpiryDateKey];

             [ARRouter setAuthToken:token];

             // Create an Expiration Date
             ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
             NSDate *expiryDate = [dateFormatter dateFromString:expiryDateString];

             // Let clients perform any actions once we've got the tokens sorted
             if (credentials) {
                 credentials(token, expiryDate);
             }

             NSURLRequest *userRequest = [ARRouter newUserInfoRequest];
             AFJSONRequestOperation *userOp = [AFJSONRequestOperation JSONRequestOperationWithRequest:userRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

                 User *user = [User modelWithJSON:JSON];

                 self.currentUser = user;
                 [self storeUserData];
                 [user updateProfile:^{
                     [self storeUserData];
                 }];

                 // Store the credentials for next app launch
                 [UICKeyChainStore setString:token forKey:AROAuthTokenDefault];
                 [UICKeyChainStore removeItemForKey:ARXAppTokenDefault];

                 [[NSUserDefaults standardUserDefaults] removeObjectForKey:ARXAppTokenExpiryDateDefault];
                 [[NSUserDefaults standardUserDefaults] setObject:expiryDate forKey:AROAuthTokenExpiryDateDefault];
                 [[NSUserDefaults standardUserDefaults] synchronize];
                 gotUser(user);

             } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                 if (authenticationFailure) {
                     authenticationFailure(error);
                 }
             }];
             [userOp start];
         }
         failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             if (JSON) {
                 if (authenticationFailure) {
                     authenticationFailure(error);
                 }
             } else {
                 if (networkFailure) {
                     networkFailure(error);
                 }
             }
         }
    ];
    [op start];
}

- (void)loginWithFacebookToken:(NSString *)token
        successWithCredentials:(void (^)(NSString *, NSDate *))credentials
                       gotUser:(void (^)(User *))gotUser
         authenticationFailure:(void (^)(NSError *error))authenticationFailure
                networkFailure:(void (^)(NSError *))networkFailure
{
    NSURLRequest *request = [ARRouter newFacebookOAuthRequestWithToken:token];
    AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
                                                                                 success:^(NSURLRequest *oauthRequest, NSHTTPURLResponse *response, id JSON) {

         NSString *token = JSON[AROAuthTokenKey];
         NSString *expiryDateString = JSON[AROExpiryDateKey];

         [ARRouter setAuthToken:token];

         // Create an Expiration Date
         ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
         NSDate *expiryDate = [dateFormatter dateFromString:expiryDateString];

         // Let clients perform any actions once we've got the tokens sorted
         if (credentials) {
             credentials(token, expiryDate);
         }

         NSURLRequest *userRequest = [ARRouter newUserInfoRequest];
         AFJSONRequestOperation *userOp = [AFJSONRequestOperation JSONRequestOperationWithRequest:userRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

             User *user = [User modelWithJSON:JSON];

             self.currentUser = user;
             [self storeUserData];
             [user updateProfile:^{
                 [self storeUserData];
             }];

             // Store the credentials for next app launch
             [UICKeyChainStore setString:token forKey:AROAuthTokenDefault];
             [UICKeyChainStore removeItemForKey:ARXAppTokenDefault];

             [[NSUserDefaults standardUserDefaults] removeObjectForKey:ARXAppTokenExpiryDateDefault];
             [[NSUserDefaults standardUserDefaults] setObject:expiryDate forKey:AROAuthTokenExpiryDateDefault];
             [[NSUserDefaults standardUserDefaults] synchronize];
             gotUser(user);

         } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             if (authenticationFailure) {
                 authenticationFailure(error);
             }
         }];
         [userOp start];
     }
     failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         if (JSON) {
             if (authenticationFailure) {
                 authenticationFailure(error);
             }
         } else {
             if (networkFailure) {
                 networkFailure(error);
            }
         }

    }];
    [op start];

}

- (void)loginWithTwitterToken:(NSString *)token secret:(NSString *)secret
       successWithCredentials:(void (^)(NSString *, NSDate *))credentials
                      gotUser:(void (^)(User *))gotUser
        authenticationFailure:(void (^)(NSError *error))authenticationFailure
               networkFailure:(void (^)(NSError *))networkFailure
{
    NSURLRequest *request = [ARRouter newTwitterOAuthRequestWithToken:token andSecret:secret];
    AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
                                                                                 success:^(NSURLRequest *oauthRequest, NSHTTPURLResponse *response, id JSON) {

             NSString *token = JSON[AROAuthTokenKey];
             NSString *expiryDateString = JSON[AROExpiryDateKey];

             [ARRouter setAuthToken:token];

             // Create an Expiration Date
             ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
             NSDate *expiryDate = [dateFormatter dateFromString:expiryDateString];

             // Let clients perform any actions once we've got the tokens sorted
             if (credentials) {
                 credentials(token, expiryDate);
             }

             NSURLRequest *userRequest = [ARRouter newUserInfoRequest];
             AFJSONRequestOperation *userOp = [AFJSONRequestOperation JSONRequestOperationWithRequest:userRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

                 User *user = [User modelWithJSON:JSON];

                 self.currentUser = user;
                 [self storeUserData];
                 [user updateProfile:^{
                     [self storeUserData];
                 }];

                 // Store the credentials for next app launch
                 [UICKeyChainStore setString:token forKey:AROAuthTokenDefault];
                 [UICKeyChainStore removeItemForKey:ARXAppTokenDefault];

                 [[NSUserDefaults standardUserDefaults] removeObjectForKey:ARXAppTokenExpiryDateDefault];
                 [[NSUserDefaults standardUserDefaults] setObject:expiryDate forKey:AROAuthTokenExpiryDateDefault];
                 [[NSUserDefaults standardUserDefaults] synchronize];
                 gotUser(user);

             } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                 if (authenticationFailure) {
                     authenticationFailure(error);
                 }
             }];
             [userOp start];
         }
         failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             if (JSON) {
                 if (authenticationFailure) {
                     authenticationFailure(error);
                 }
             } else {
                 networkFailure(error);
             }
         }];

    [op start];

}

- (void)startTrial:(void(^)())callback failure:(void (^)(NSError *error))failure
{
    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {
        [UICKeyChainStore setString:xappToken forKey:ARXAppTokenDefault];
        [[NSUserDefaults standardUserDefaults] setObject:expirationDate forKey:ARXAppTokenExpiryDateDefault];
        callback();
    } failure:failure];
}

- (void)createUserWithName:(NSString *)name email:(NSString *)email password:(NSString *)password success:(void (^)(User *))success failure:(void (^)(NSError *error, id JSON))failure
{
    [ARAnalytics event:ARAnalyticsUserCreationStarted  withProperties:@{
        @"context" : ARAnalyticsUserContextEmail
    }];

    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {

        ARActionLog(@"Got Xapp. Creating a new user account.");

        NSURLRequest *request = [ARRouter newCreateUserRequestWithName:name email:email password:password];
        AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            NSError *error;
            User *user = [User modelWithJSON:JSON error:&error];
            if (error) {
                 ARErrorLog(@"Couldn't create user model from fresh user. Error: %@,\nJSON: %@", error.localizedDescription, JSON);
                 [ARAnalytics event:ARAnalyticsUserCreationUnknownError];
                 failure(error, JSON);
                 return;
            }

            self.currentUser = user;
            [self storeUserData];

            if(success) success(user);
            [ARAnalytics event:ARAnalyticsUserCreationCompleted];

        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            ARErrorLog(@"Creating a new user account failed. Error: %@,\nJSON: %@", error.localizedDescription, JSON);
            failure(error, JSON);
            [ARAnalytics event:ARAnalyticsUserCreationUnknownError];
        }];

        [op start];

    }];
}

- (void)createUserViaFacebookWithToken:(NSString *)token email:(NSString *)email name:(NSString *)name success:(void (^)(User *))success failure:(void (^)(NSError *, id))failure
{
    [ARAnalytics event:ARAnalyticsUserCreationStarted withProperties:@{
        @"context" : ARAnalyticsUserContextFacebook
    }];

    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {
        NSURLRequest *request = [ARRouter newCreateUserViaFacebookRequestWithToken:token email:email name:name];
        AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
         success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
             NSError *error;
             User *user = [User modelWithJSON:JSON error:&error];
             if (error) {
                 ARErrorLog(@"Couldn't create user model from fresh Facebook user. Error: %@,\nJSON: %@", error.localizedDescription, JSON);
                 [ARAnalytics event:ARAnalyticsUserCreationUnknownError];
                 failure(error, JSON);
                 return;
             }
             self.currentUser = user;
             [self storeUserData];

             if (success) { success(user); }

             [ARAnalytics event:ARAnalyticsUserCreationCompleted];

         } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             failure(error, JSON);
             [ARAnalytics event:ARAnalyticsUserCreationUnknownError];

         }];
        [op start];
    }];
}

- (void)createUserViaTwitterWithToken:(NSString *)token secret:(NSString *)secret email:(NSString *)email name:(NSString *)name success:(void (^)(User *))success failure:(void (^)(NSError *, id))failure
{
    [ARAnalytics event:ARAnalyticsUserCreationStarted withProperties:@{
        @"context" : ARAnalyticsUserContextTwitter
    }];

    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {
        NSURLRequest *request = [ARRouter newCreateUserViaTwitterRequestWithToken:token secret:secret email:email name:name];
        AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
         success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
             NSError *error;
             User *user = [User modelWithJSON:JSON error:&error];
             if (error) {
                 ARErrorLog(@"Couldn't create user model from fresh Twitter user. Error: %@,\nJSON: %@", error.localizedDescription, JSON);
                 [ARAnalytics event:ARAnalyticsUserCreationUnknownError];
                 failure(error, JSON);
                 return;
             }
             self.currentUser = user;
             [self storeUserData];

             if(success) success(user);

             [ARAnalytics event:ARAnalyticsUserCreationCompleted];

         } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             failure(error, JSON);
             [ARAnalytics event:ARAnalyticsUserCreationUnknownError];
         }];
        [op start];
    }];
}

- (void)sendPasswordResetForEmail:(NSString *)email success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {
        NSURLRequest *request = [ARRouter newForgotPasswordRequestWithEmail:email];
        AFJSONRequestOperation *op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            if (success) {
                success();
            }
        }
        failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            if (failure) {
                failure(error);
            }
        }];
        [op start];
    }];
}

- (void)storeUserData
{
    NSString *userDataPath = [ARFileUtils userDocumentsPathWithFile:@"User.data"];
    if (userDataPath) {
        [NSKeyedArchiver archiveRootObject:self.currentUser toFile:userDataPath];

        [ARUserManager identifyAnalyticsUser];

        [[NSUserDefaults standardUserDefaults] setObject:self.currentUser.userID forKey:ARUserIdentifierDefault];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

+ (void)logout
{
    [self.class clearUserData];
    exit(0);
}

+ (void)logoutAndSetUseStaging:(BOOL)useStaging
{
    [self.class clearUserDataAndSetUseStaging:useStaging];
    exit(0);
}

+ (void)clearUserData
{
    BOOL useStaging = [AROptions boolForOption:ARUseStagingDefault];
    [self clearUserDataAndSetUseStaging:useStaging];
}

+ (void)clearUserDataAndSetUseStaging:(BOOL)useStaging
{
    NSLog(@"clear user data param %d", useStaging);
    NSLog(@"clear user data before clear %d", [AROptions boolForOption:ARUseStagingDefault]);

    ARUserManager *sharedManager = [self.class sharedManager];

    [sharedManager deleteUserData];
    [ARDefaults resetDefaults];

    [AROptions setBool:useStaging forOption:ARUseStagingDefault];

    [UICKeyChainStore removeItemForKey:AROAuthTokenDefault];
    [UICKeyChainStore removeItemForKey:ARXAppTokenDefault];

    [sharedManager deleteHTTPCookies];
    NSLog(@"clear user data after clear %d", [AROptions boolForOption:ARUseStagingDefault]);

}

- (void)deleteHTTPCookies
{
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in cookieStorage.cookies) {
        if ([ARRouter.artsyHosts containsObject:cookie.domain]) {
            [cookieStorage deleteCookie:cookie];
        }
    }
}

- (void)deleteUserData
{
    // Delete the user data
    NSString * userDataPath = [self userDataPath];
    if (userDataPath) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:userDataPath error:&error];
        if (error) {
            ARErrorLog(@"Error Deleting User Data %@", error.localizedDescription);
        }
    }
}

#pragma mark -
#pragma mark Utilities

- (NSString *)userDataPath {
    NSString *userID = [[NSUserDefaults standardUserDefaults] objectForKey:ARUserIdentifierDefault];
    if (!userID) { return nil; }

    NSArray *directories =[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSString *documentsPath = [[directories lastObject] relativePath];
    return [documentsPath stringByAppendingPathComponent:userID];
}

#pragma mark -
#pragma mark Trial User

- (void)setTrialUserName:(NSString *)trialUserName
{
    if (trialUserName) {
        [UICKeyChainStore setString:trialUserName forKey:ARTrialUserNameKey];
    } else {
        [UICKeyChainStore removeItemForKey:ARTrialUserNameKey];
    }
}

- (void)setTrialUserEmail:(NSString *)trialUserEmail
{
    if (trialUserEmail) {
        [UICKeyChainStore setString:trialUserEmail forKey:ARTrialUserEmailKey];
    } else {
        [UICKeyChainStore removeItemForKey:ARTrialUserEmailKey];
    }
}

- (NSString *)trialUserName
{
    return [UICKeyChainStore stringForKey:ARTrialUserNameKey];
}

- (NSString *)trialUserEmail
{
    return [UICKeyChainStore stringForKey:ARTrialUserEmailKey];
}

- (NSString *)trialUserUUID
{
    NSString *uuid = [UICKeyChainStore stringForKey:ARTrialUserUUID];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [UICKeyChainStore setString:uuid forKey:ARTrialUserUUID];
    }
    return uuid;
}

- (void)resetTrialUserUUID
{
    [UICKeyChainStore removeItemForKey:ARTrialUserUUID];
}

@end

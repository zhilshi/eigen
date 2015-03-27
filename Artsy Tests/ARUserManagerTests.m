#import "ARUserManager.h"
#import "ARUserManager+Stubs.h"
#import "ARRouter.h"
#import "ARNetworkConstants.h"
#import "ARDefaults.h"

@interface ARUserManager (Testing)
+ (void)clearUserDataAndSetUseStaging:(id)useStaging;
@end

SpecBegin(ARUserManager)

beforeEach(^{
    [ARUserManager clearUserData];
});

afterEach(^{
    [OHHTTPStubs removeAllStubs];
});

describe(@"login", ^{

    sharedExamplesFor(@"success", ^(NSDictionary *data) {
        it(@"stores user data after login", ^{
            NSString *userDataPath = [ARUserManager userDataPath];
            expect([[NSFileManager defaultManager] fileExistsAtPath:userDataPath]).to.beTruthy();
            User *storedUser = [NSKeyedUnarchiver unarchiveObjectWithFile:userDataPath];
            expect(storedUser).toNot.beNil();
            expect(storedUser.userID).to.equal(ARUserManager.stubUserID);
            expect(storedUser.email).to.equal(ARUserManager.stubUserEmail);
            expect(storedUser.name).to.equal(ARUserManager.stubUserName);
        });

        it(@"remembers access token", ^{
            expect([[ARUserManager sharedManager] hasValidAuthenticationToken]).to.beTruthy();
            expect([ARUserManager stubAccessToken]).to.equal([UICKeyChainStore stringForKey:AROAuthTokenDefault]);
        });

        it(@"remembers access token expiry date", ^{
            ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
            NSDate *expiryDate = [dateFormatter dateFromString:[ARUserManager stubAccessTokenExpiresIn]];
            expect([expiryDate isEqualToDate:[[NSUserDefaults standardUserDefaults] objectForKey:AROAuthTokenExpiryDateDefault]]).to.beTruthy();
        });

        it(@"sets current user", ^{
            User *currentUser = [[ARUserManager sharedManager] currentUser];
            expect(currentUser).toNot.beNil();
            expect(currentUser.userID).to.equal(ARUserManager.stubUserID);
            expect(currentUser.email).to.equal(ARUserManager.stubUserEmail);
            expect(currentUser.name).to.equal(ARUserManager.stubUserName);
        });
        
        it(@"sets router auth token", ^{
            NSURLRequest *request = [ARRouter requestForURL:[NSURL URLWithString:@"http://m.artsy.net"]];
            expect([request valueForHTTPHeaderField:ARAuthHeader]).toNot.beNil();
        });
    });

    describe(@"with username and password", ^{
        beforeEach(^{
            [ARUserManager stubAndLoginWithUsername];
        });
        itBehavesLike(@"success", nil);
    });

    describe(@"with a Facebook token", ^{
        beforeEach(^{
            [ARUserManager stubAndLoginWithFacebookToken];
        });
        itBehavesLike(@"success", nil);
    });

    describe(@"with a Twitter token", ^{
        beforeEach(^{
            [ARUserManager stubAndLoginWithTwitterToken];
        });
        itBehavesLike(@"success", nil);
    });

    it(@"fails with a missing client id", ^{
        [OHHTTPStubs stubJSONResponseAtPath:@"/oauth2/access_token" withResponse:@{ @"error": @"invalid_client", @"error_description": @"missing client_id" } andStatusCode:401];

        [ARUserManager stubbedLoginWithUsername:[ARUserManager stubUserEmail] password:[ARUserManager stubUserPassword]
            successWithCredentials:^(NSString *accessToken, NSDate *tokenExpiryDate) {
                XCTFail(@"Expected API failure.");
            } gotUser:^(User *currentUser) {
                XCTFail(@"Expected API failure.");
            } authenticationFailure:^(NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *) error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
                expect(response.statusCode).to.equal(401);
                NSDictionary *recoverySuggestion = [NSJSONSerialization JSONObjectWithData:[error.userInfo[NSLocalizedRecoverySuggestionErrorKey] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                expect(recoverySuggestion).to.equal(@{ @"error_description" : @"missing client_id", @"error" : @"invalid_client" });
            } networkFailure:^(NSError *error){
                XCTFail(@"Expected API failure.");
            }];
    });

    it(@"fails with an expired token", ^{
        NSDate *yesterday = [NSDate dateWithTimeIntervalSinceNow: -(60.0f*60.0f*24.0f)];
        ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
        NSString *expiryDate = [dateFormatter stringFromDate:yesterday];

        [ARUserManager stubAccessToken:[ARUserManager stubAccessToken] expiresIn:expiryDate];
        [ARUserManager stubMe:[ARUserManager stubUserID] email:[ARUserManager stubUserEmail] name:[ARUserManager stubUserName]];

        [ARUserManager stubbedLoginWithUsername:[ARUserManager stubUserEmail]
                                       password:[ARUserManager stubUserPassword]
                         successWithCredentials:nil
                                        gotUser:nil
                          authenticationFailure:nil
                                 networkFailure:nil];

        expect([[ARUserManager sharedManager] hasValidAuthenticationToken]).to.beFalsy();
    });
});

describe(@"clearUserData", ^{
    describe(@"unsetting user defaults", ^{
        before(^{
            [[NSUserDefaults standardUserDefaults] setValue:@"test value" forKey:@"TestKey"];
        });

        after(^{
            [ARDefaults resetDefaults];
        });

        it(@"sets use staging to previous YES value", ^{
            [[NSUserDefaults standardUserDefaults] setValue:@(YES) forKey:ARUseStagingDefault];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beTruthy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserData];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beTruthy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });

        it(@"sets use staging to previous NO value", ^{
            [[NSUserDefaults standardUserDefaults] setValue:@(NO) forKey:ARUseStagingDefault];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beFalsy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserData];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beFalsy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });

        it(@"does not set use staging if it was not set before", ^{
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserData];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });
    });

    describe(@"clearUserDAtaAndSetUserStaging", ^{
        before(^{
            [[NSUserDefaults standardUserDefaults] setValue:@"test value" forKey:@"TestKey"];
        });

        after(^{
            [ARDefaults resetDefaults];
        });

        it(@"explicitly sets staging default to yes", ^{
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserDataAndSetUseStaging:@(YES)];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beTruthy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });
        
        it(@"explicitly sets staging default to no", ^{
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserDataAndSetUseStaging:@(NO)];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beFalsy();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });

        it(@"does not set staging value passed is nil", ^{
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.equal(@"test value");
            [ARUserManager clearUserDataAndSetUseStaging:nil];
            expect([[NSUserDefaults standardUserDefaults] valueForKey:ARUseStagingDefault]).to.beNil();
            expect([[NSUserDefaults standardUserDefaults] valueForKey:@"TestKey"]).to.beNil();
        });
        
    });

    describe(@"with email and password", ^{
        __block NSString * _userDataPath;
        
        beforeEach(^{
            [ARUserManager stubAndLoginWithUsername];
            _userDataPath = [ARUserManager userDataPath];
            [ARUserManager clearUserData];
        });
        
        it(@"resets currentUser", ^{
            expect([[ARUserManager sharedManager] currentUser]).to.beNil();
        });
        
        it(@"destroys stored user data", ^{
            expect([[NSFileManager defaultManager] fileExistsAtPath:_userDataPath]).to.beFalsy();
        });
        
        it(@"unsets router auth token", ^{
            NSURLRequest *request = [ARRouter requestForURL:[NSURL URLWithString:@"http://m.artsy.net"]];
            expect([request valueForHTTPHeaderField:ARAuthHeader]).to.beNil();
        });
    });
    
    it(@"clears artsy.net cookies", ^{
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        [cookieStorage setCookieAcceptPolicy:NSHTTPCookieAcceptPolicyAlways];
        for(NSHTTPCookie *cookie in [cookieStorage cookiesForURL:[NSURL URLWithString:@"http://artsy.net"]]) {
            [cookieStorage deleteCookie:cookie];
        }
        NSInteger cookieCount = cookieStorage.cookies.count;
        NSMutableDictionary *cookieProperties = [NSMutableDictionary dictionary];
        [cookieProperties setObject:@"name" forKey:NSHTTPCookieName];
        [cookieProperties setObject:@"value" forKey:NSHTTPCookieValue];
        [cookieProperties setObject:@"/" forKey:NSHTTPCookiePath];
        [cookieProperties setObject:@"0" forKey:NSHTTPCookieVersion];
        // will delete a cookie in any of the artsy.net domains
        for(NSString *artsyHost in ARRouter.artsyHosts) {
            [cookieProperties setObject:artsyHost forKey:NSHTTPCookieDomain];
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:[NSHTTPCookie cookieWithProperties:cookieProperties]];
        }
        // don't touch a cookie in a different domain
        [cookieProperties setObject:@"example.com" forKey:NSHTTPCookieDomain];
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:[NSHTTPCookie cookieWithProperties:cookieProperties]];
        expect(cookieStorage.cookies.count).to.equal(cookieCount + ARRouter.artsyHosts.count + 1);
        expect([cookieStorage cookiesForURL:[NSURL URLWithString:@"http://artsy.net"]].count).to.equal(1);
        [ARUserManager clearUserData];
        expect(cookieStorage.cookies.count).to.equal(cookieCount + 1);
        expect([cookieStorage cookiesForURL:[NSURL URLWithString:@"http://artsy.net"]].count).to.equal(0);
    });
});

describe(@"startTrial", ^{
    beforeEach(^{
        [ARUserManager stubXappToken:[ARUserManager stubXappToken] expiresIn:[ARUserManager stubXappTokenExpiresIn]];

        __block BOOL done = NO;
        [[ARUserManager sharedManager] startTrial:^{
            done = YES;
        } failure:^(NSError *error) {
            XCTFail(@"startTrial: %@", error);
            done = YES;
        }];

        while(!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    it(@"sets an xapp token", ^{
        expect([[ARUserManager stubXappToken] isEqualToString:[UICKeyChainStore stringForKey:ARXAppTokenDefault]]).to.beTruthy();
    });

    it(@"sets expiry date", ^{
        ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
        NSDate *expiryDate = [dateFormatter dateFromString:[ARUserManager stubXappTokenExpiresIn]];
        expect([expiryDate isEqualToDate:[[NSUserDefaults standardUserDefaults] objectForKey:ARXAppTokenExpiryDateDefault]]).to.beTruthy();
    });
});

describe(@"createUserWithName", ^{
    beforeEach(^{
        [ARUserManager stubXappToken:[ARUserManager stubXappToken] expiresIn:[ARUserManager stubXappTokenExpiresIn]];
        [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/user" withResponse:@{ @"id": [ARUserManager stubUserID], @"email": [ARUserManager stubUserEmail], @"name": [ARUserManager stubUserName] } andStatusCode:201];

        __block BOOL done = NO;
        [[ARUserManager sharedManager] createUserWithName:[ARUserManager stubUserName] email:[ARUserManager stubUserEmail] password:[ARUserManager stubUserPassword] success:^(User *user) {
            done = YES;
        } failure:^(NSError *error, id JSON) {
            XCTFail(@"createUserWithName: %@", error);
            done = YES;
        }];

        while(!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    it(@"sets current user", ^{
        User *currentUser = [[ARUserManager sharedManager] currentUser];
        expect(currentUser).toNot.beNil();
        expect(currentUser.userID).to.equal(ARUserManager.stubUserID);
        expect(currentUser.email).to.equal(ARUserManager.stubUserEmail);
        expect(currentUser.name).to.equal(ARUserManager.stubUserName);
    });
});

describe(@"createUserViaFacebookWithToken", ^{
    beforeEach(^{
        [ARUserManager stubXappToken:[ARUserManager stubXappToken] expiresIn:[ARUserManager stubXappTokenExpiresIn]];
        [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/user" withResponse:@{ @"id": [ARUserManager stubUserID], @"email": [ARUserManager stubUserEmail], @"name": [ARUserManager stubUserName] } andStatusCode:201];

        __block BOOL done = NO;
        [[ARUserManager sharedManager] createUserViaFacebookWithToken:@"facebook token" email:[ARUserManager stubUserEmail] name:[ARUserManager stubUserName] success:^(User *user) {
            done = YES;
        } failure:^(NSError *error, id JSON) {
            XCTFail(@"createUserWithFacebookToken: %@", error);
            done = YES;
        }];

        while(!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    it(@"sets current user", ^{
        User *currentUser = [[ARUserManager sharedManager] currentUser];
        expect(currentUser).toNot.beNil();
        expect(currentUser.userID).to.equal(ARUserManager.stubUserID);
        expect(currentUser.email).to.equal(ARUserManager.stubUserEmail);
        expect(currentUser.name).to.equal(ARUserManager.stubUserName);
    });
});

describe(@"createUserViaTwitterWithToken", ^{
    beforeEach(^{
        [ARUserManager stubXappToken:[ARUserManager stubXappToken] expiresIn:[ARUserManager stubXappTokenExpiresIn]];
        [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/user" withResponse:@{ @"id": [ARUserManager stubUserID], @"email": [ARUserManager stubUserEmail], @"name": [ARUserManager stubUserName] } andStatusCode:201];

        __block BOOL done = NO;
        [[ARUserManager sharedManager] createUserViaTwitterWithToken:@"twitter token" secret:@"twitter secret" email:[ARUserManager stubUserEmail] name:[ARUserManager stubUserName] success:^(User *user) {
            done = YES;
        } failure:^(NSError *error, id JSON) {
            XCTFail(@"createUserWithFacebookToken: %@", error);
            done = YES;
        }];

        while(!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });

    it(@"sets current user", ^{
        User *currentUser = [[ARUserManager sharedManager] currentUser];
        expect(currentUser).toNot.beNil();
        expect(currentUser.userID).to.equal(ARUserManager.stubUserID);
        expect(currentUser.email).to.equal(ARUserManager.stubUserEmail);
        expect(currentUser.name).to.equal(ARUserManager.stubUserName);
    });
});

describe(@"trialUserEmail", ^{
    beforeEach(^{
        [ARUserManager sharedManager].trialUserEmail = nil;
    });

    afterEach(^{
        [ARUserManager sharedManager].trialUserEmail = nil;
    });

    it(@"is nil", ^{
        expect([ARUserManager sharedManager].trialUserEmail).to.beNil();
    });

    it(@"sets and reads value", ^{
        [ARUserManager sharedManager].trialUserEmail = @"trial@example.com";
        expect([ARUserManager sharedManager].trialUserEmail).to.equal(@"trial@example.com");
    });
});

describe(@"trialUserName", ^{
    beforeEach(^{
        [ARUserManager sharedManager].trialUserName = nil;
    });

    afterEach(^{
        [ARUserManager sharedManager].trialUserName = nil;
    });

    it(@"is nil", ^{
        expect([ARUserManager sharedManager].trialUserName).to.beNil();
    });

    it(@"sets and reads value", ^{
        [ARUserManager sharedManager].trialUserName = @"Name";
        expect([ARUserManager sharedManager].trialUserName).to.equal(@"Name");
    });
});

describe(@"trialUserUUID", ^{
    beforeEach(^{
        [[ARUserManager sharedManager] resetTrialUserUUID];
    });

    afterEach(^{
        [[ARUserManager sharedManager] resetTrialUserUUID];
    });

    it(@"is not", ^{
        expect([ARUserManager sharedManager].trialUserUUID).notTo.beNil();
    });
    
    it(@"is persisted", ^{
        NSString *uuid = [ARUserManager sharedManager].trialUserUUID;
        expect([ARUserManager sharedManager].trialUserUUID).to.equal(uuid);
    });
});

SpecEnd


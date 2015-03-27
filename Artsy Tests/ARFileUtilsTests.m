#import "ARFileUtils.h"
#import "ARUserManager.h"
#import "ARUserManager+Stubs.h"

SpecBegin(ARFileUtilsTests)

describe(@"caches", ^{
    it(@"cachesFolder", ^{
        expect([[ARFileUtils cachesFolder] hasSuffix:@"/Caches"]).to.beTruthy();
    });

    it(@"cachesFolder creates a folder", ^{
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSString *uuidPath = [ARFileUtils cachesPathWithFolder:uuid filename:@"test.filename"];
        NSString *uuidFolder = NSStringWithFormat(@"%@/%@", [ARFileUtils cachesFolder], uuid);
        // path has been created
        expect([[NSFileManager defaultManager] fileExistsAtPath:uuidFolder]).to.beTruthy();
        // file doesn't exist
        expect([[NSFileManager defaultManager] fileExistsAtPath:uuidPath]).to.beFalsy();
        [[NSFileManager defaultManager] removeItemAtPath:uuidFolder error:nil];
    });
});


describe(@"logged out user documents folder", ^{
    beforeEach(^{
        [ARUserManager clearUserData];
    });

    it(@"userDocumentsFolder", ^{
        expect([ARFileUtils userDocumentsFolder]).to.beNil();
        expect([ARFileUtils userDocumentsPathWithFile:@"folder"]).to.beNil();
        expect([ARFileUtils userDocumentsPathWithFolder:@"folder" filename:@"filename"]).to.beNil();
    });
});

describe(@"logged in user documents folder", ^{
    beforeEach(^{
        [ARUserManager stubAndLoginWithUsername];
        XCTAssert([User currentUser] != nil, @"Current user is nil even after stubbing. ");
    });

    afterEach(^{
        [[NSFileManager defaultManager] removeItemAtPath:[ARFileUtils userDocumentsFolder] error:nil];
    });

    it(@"userDocumentsFolder", ^{
        expect([[ARFileUtils userDocumentsFolder] hasSuffix:NSStringWithFormat(@"/Documents/%@", [User currentUser].userID)]).to.beTruthy();
    });

    it(@"userDocumentsFilename", ^{
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSString *uuidFilePath = [ARFileUtils userDocumentsPathWithFile:uuid];
        expect([uuidFilePath hasSuffix:NSStringWithFormat(@"/Documents/%@/%@", [User currentUser].userID, uuid)]).to.beTruthy();
    });

    it(@"userDocumentsFolderFilename", ^{
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSString *uuidPath = [ARFileUtils userDocumentsPathWithFolder:uuid filename:@"filename"];
        expect([uuidPath hasSuffix:NSStringWithFormat(@"/Documents/%@/%@/filename", [User currentUser].userID, uuid)]).to.beTruthy();
    });
});

SpecEnd

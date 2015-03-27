#import "ARInquireForArtworkViewController.h"
#import "ARUserManager+Stubs.h"

@interface ARInquireForArtworkViewController (Testing)

@property (nonatomic, assign, readwrite) BOOL shouldAnimate;

@property (nonatomic, strong, readonly) UITextField *emailInput;
@property (nonatomic, strong, readonly) UITextField *nameInput;

@property (nonatomic, strong, readonly) UILabel *messageTitleLabel;
@property (nonatomic, strong, readonly) UILabel *messageBodyLabel;

@property (nonatomic, strong, readonly) UIButton *failureDismissButton;
@property (nonatomic, strong, readonly) UIButton *failureTryAgainButton;
@property (nonatomic, strong, readonly) ARModalMenuButton *sendButton;

- (void)sendButtonTapped:(UIButton *)sender;
- (void)cancelButtonTapped:(UIButton *)sender;
- (void)emailInputHasChanged:(id)sender;
- (void)removeFromHostViewController;
- (void)sendInquiry;
@end

SpecBegin(ARInquireForArtworkViewController)

__block Artwork *galleryArtwork, *museumGallery;

beforeEach(^{
    galleryArtwork = [Artwork modelWithJSON:@{
        @"id" : @"cory-arcangel-photoshop-cs",
        @"title" : @"Photoshop CS",
        @"artist" : @{
               @"id": @"cory-arcangel",
               @"name": @"Cory Arcangel"
        },
        @"partner" : @{
               @"id" : @"partner_id",
               @"type" : @"Gallery",
               @"name" : @"Lisson Gallery"
        }
    }];
    
    museumGallery = [Artwork modelWithJSON:@{
        @"id" : @"cory-arcangel-photoshop-cs",
        @"title" : @"Photoshop CS",
        @"artist" : @{
             @"id": @"cory-arcangel",
             @"name": @"Cory Arcangel"
        },
        @"partner" : @{
             @"id" : @"partner_id",
             @"type" : @"Museum",
             @"name" : @"Guggenheim Museum"
        }
    }];

    [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/admins/available_representatives" withResponse:@[]];
});

afterEach(^{
    [OHHTTPStubs removeAllStubs];
});

describe(@"logged in", ^{
    beforeEach(^{
        [ARUserManager stubAndLoginWithUsername];
    });

    afterEach(^{
        [ARUserManager clearUserData];
    });

    itHasAsyncronousSnapshotsForDevices(@"displays Contact Gallery when seller is a gallery", ^{
        ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithPartnerInquiryForArtwork:galleryArtwork fair:nil];
        vc.shouldAnimate = NO;
        [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
        return vc;
    });

    itHasAsyncronousSnapshotsForDevices(@"displays Contact Seller when seller is not a gallery", ^{
        ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithPartnerInquiryForArtwork:museumGallery fair:nil];
        vc.shouldAnimate = NO;
        [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
        return vc;
    });

    itHasAsyncronousSnapshotsForDevices(@"logged out, displays artsy specialist", ^{
        ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
        vc.shouldAnimate = NO;
        [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
        return vc;
    });
});

describe(@"logged out", ^{
    describe(@"contact information", ^{
        beforeEach(^{
            [ARUserManager clearUserData];
            [ARUserManager sharedManager].trialUserName = @"Trial User";
            [ARUserManager sharedManager].trialUserEmail = @"trial@example.com";
        });

        afterEach(^{
            [ARUserManager sharedManager].trialUserName = nil;
            [ARUserManager sharedManager].trialUserEmail = nil;
        });

        itHasAsyncronousSnapshotsForDevices(@"displays contact gallery", ^{
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithPartnerInquiryForArtwork:galleryArtwork fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });

        itHasAsyncronousSnapshotsForDevices(@"displays artsy specialist", ^{
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });
        
        itHasAsyncronousSnapshotsForDevices(@"works for an artwork without a title", ^{
            museumGallery.title = nil;
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithPartnerInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });
    });

    describe(@"send button", ^{
        __block Artwork *artwork;
        
        beforeEach(^{
            [ARUserManager clearUserData];
            [ARUserManager sharedManager].trialUserName = @"Trial User";
        });

        afterEach(^{
            [ARUserManager sharedManager].trialUserName = nil;
            [ARUserManager sharedManager].trialUserEmail = nil;
            artwork = nil;
        });

        itHasAsyncronousSnapshotsForDevices(@"does not initially enable send if stored email is invalid", ^{
            [ARUserManager sharedManager].trialUserEmail = @"invalidEmail";
            
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });

        itHasAsyncronousSnapshotsForDevices(@"does initially enables send if stored email is valid", ^{
            [ARUserManager sharedManager].trialUserEmail = @"validemail@gmail.com";

            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });
        
        itHasAsyncronousSnapshotsForDevices(@"toggles the send button with empty email", ^{
            [ARUserManager sharedManager].trialUserEmail = nil;
            
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            return vc;
        });
        
        itHasAsyncronousSnapshotsForDevices(@"toggles the send button when email becomes valid", ^{
            [ARUserManager sharedManager].trialUserEmail = nil;
            
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            
            vc.emailInput.text = @"validemail@gmail.com";
            [vc emailInputHasChanged:vc.emailInput];
            return vc;
        });
        
        itHasAsyncronousSnapshotsForDevices(@"toggles the send button when valid email becomes invalid", ^{
            [ARUserManager sharedManager].trialUserEmail = nil;
            
            ARInquireForArtworkViewController *vc = [[ARInquireForArtworkViewController alloc] initWithAdminInquiryForArtwork:museumGallery fair:nil];
            vc.shouldAnimate = NO;
            [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
            
            vc.emailInput.text = @"validemail@gmail.com";
            [vc emailInputHasChanged:vc.emailInput];
            vc.emailInput.text = @"invalidEmail";
            [vc emailInputHasChanged:vc.emailInput];
            return vc;
        });
    });
});

describe(@"sending", ^{
    __block ARInquireForArtworkViewController *vc;
    __block id userMock;

    beforeEach(^{
        [ARUserManager clearUserData];
        [ARUserManager sharedManager].trialUserName = @"Trial User";
        [ARUserManager sharedManager].trialUserEmail = @"trial@example.com";
        userMock = [OCMockObject mockForClass:[User class]];
        [[[[userMock stub] classMethod] andReturnValue:OCMOCK_VALUE(YES)] isTrialUser];

        vc = [[ARInquireForArtworkViewController alloc] initWithPartnerInquiryForArtwork:galleryArtwork fair:nil];
        vc.shouldAnimate = NO;
        [vc ar_presentWithFrame:[[UIScreen mainScreen] bounds]];
    });
    
    afterEach(^{
        [userMock stopMocking];
        [ARUserManager sharedManager].trialUserName = nil;
        [ARUserManager sharedManager].trialUserEmail = nil;
    });

    it(@"displays sending message", ^{
        [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/me/artwork_inquiry_request" withResponse:@{}];
        [vc sendButtonTapped:vc.sendButton];
        expect(vc.messageTitleLabel.hidden).to.beFalsy();
        expect(vc.messageTitleLabel.text).to.equal(@"SENDING…");
        expect(vc.messageBodyLabel.hidden).to.beFalsy();
        expect(vc.messageBodyLabel.text).to.equal(@"");
        expect(vc.failureTryAgainButton.hidden).to.beTruthy();
        expect(vc.failureDismissButton.hidden).to.beTruthy();
    });

    it(@"displays success message", ^{
        [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/me/artwork_inquiry_request" withResponse:@{}];
        [vc sendButtonTapped:vc.sendButton];
        expect(vc.messageTitleLabel.hidden).to.beFalsy();
        expect(vc.messageTitleLabel.text).will.equal(@"THANK YOU");
        expect(vc.messageBodyLabel.hidden).to.beFalsy();
        expect(vc.messageBodyLabel.text).will.equal(@"Your message has been sent");
        expect(vc.failureTryAgainButton.hidden).to.beTruthy();
        expect(vc.failureDismissButton.hidden).to.beTruthy();
    });

    describe(@"general failure", ^{
        before(^{
            [OHHTTPStubs stubJSONResponseAtPath:@"/api/v1/me/artwork_inquiry_request" withResponse:@{} andStatusCode:400];
            [vc sendButtonTapped:vc.sendButton];
        });

        it(@"displays failure message", ^{
            expect(vc.messageTitleLabel.hidden).to.beFalsy();
            expect(vc.messageTitleLabel.text).will.equal(@"ERROR SENDING MESSAGE");
            expect(vc.messageBodyLabel.hidden).to.beFalsy();
            expect(vc.messageBodyLabel.text).will.equal(@"Please try again or email\nsupport@artsy.net if the issue persists");
            expect(vc.failureTryAgainButton.hidden).to.beFalsy();
            expect(vc.failureDismissButton.hidden).to.beFalsy();
        });

        it(@"can be dismissed", ^{
            id vcMock = [OCMockObject partialMockForObject:vc];
            [[vcMock expect] removeFromHostViewController];
            [[vcMock reject] sendInquiry];
            [vc cancelButtonTapped:vc.failureDismissButton];
            [vcMock verify];
            [vcMock stopMocking];
        });

        it(@"can resend request", ^{
            id vcMock = [OCMockObject partialMockForObject:vc];
            [[vcMock reject] removeFromHostViewController];
            [[vcMock expect] sendInquiry];
            [vc sendButtonTapped:vc.failureTryAgainButton];
            [vcMock verify];
            [vcMock stopMocking];
        });
    });
});

SpecEnd

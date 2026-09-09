#import "GBMenu.h"
#import "GBStore.h"
#import <WebKit/WebKit.h>
#import <Security/Security.h>

#pragma mark - Data wipe helpers

static void GBRemoveDirContents(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
}

static void GBWipeKeychain(void) {
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword,
                          (__bridge id)kSecClassCertificate,
                          (__bridge id)kSecClassKey,
                          (__bridge id)kSecClassIdentity ];
    for (id cls in classes) {
        // kSecAttrSynchronizableAny also removes iCloud-Keychain-synced items, so a saved login
        // cannot be pulled back from the cloud after the wipe.
        SecItemDelete((__bridge CFDictionaryRef)@{
            (__bridge id)kSecClass: cls,
            (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny
        });
    }
}

/// Factory-reset the host app so it comes up as a brand-new install with no previous accounts:
/// sandbox (Documents/Library/tmp), NSUserDefaults domain, cookies, WebKit data and keychain
/// (including iCloud-synced items). iCloud key-value + ubiquity access is blocked by the tweak's
/// hooks while spoofing is on, so nothing syncs the old accounts back.
static void GBClearAppData(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    NSString *home = NSHomeDirectory();
    GBRemoveDirContents([home stringByAppendingPathComponent:@"Documents"]);
    GBRemoveDirContents([home stringByAppendingPathComponent:@"Library"]);
    GBRemoveDirContents([home stringByAppendingPathComponent:@"tmp"]);

    NSHTTPCookieStorage *cookies = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in [cookies.cookies copy]) { [cookies deleteCookie:c]; }

    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                               modifiedSince:[NSDate distantPast]
                                           completionHandler:^{}];
    GBWipeKeychain();
}

static void GBQuit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

#pragma mark - Heavenzy panel

@interface GBPanelViewController : UIViewController
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *deviceValue;
@property (nonatomic, strong) UISwitch *enableSwitch;
@end

@implementation GBPanelViewController

static UIColor *GBAccent(void)  { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; } // heavenzy violet
static UIColor *GBCardBG(void)  { return [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0]; }
static UIColor *GBFieldBG(void) { return [UIColor colorWithRed:0.17 green:0.17 blue:0.21 alpha:1.0]; }
static UIColor *GBSubtle(void)  { return [UIColor colorWithWhite:0.64 alpha:1.0]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];

    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTapped:)];
    [self.view addGestureRecognizer:bgTap];

    GBStore *store = [GBStore shared];

    self.card = [UIView new];
    self.card.backgroundColor = GBCardBG();
    self.card.layer.cornerRadius = 18;
    self.card.layer.masksToBounds = YES;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.card];

    UIView *strip = [UIView new];
    strip.backgroundColor = GBAccent();
    strip.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:strip];

    UILabel *title = [self label:@"Heavenzy" size:20 weight:UIFontWeightBold color:UIColor.whiteColor];
    UILabel *subtitle = [self label:([[NSBundle mainBundle] bundleIdentifier] ?: @"") size:12 weight:UIFontWeightRegular color:GBSubtle()];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:GBSubtle() forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *deviceLabel = [self label:@"SPOOFED DEVICE" size:11 weight:UIFontWeightSemibold color:GBSubtle()];
    self.deviceValue = [self label:store.summary size:16 weight:UIFontWeightSemibold color:UIColor.whiteColor];
    self.deviceValue.numberOfLines = 2;
    UIButton *randomize = [self pillButton:@"Randomize"];
    [randomize addTarget:self action:@selector(randomizeTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *enableLabel = [self label:@"Spoof this app" size:16 weight:UIFontWeightMedium color:UIColor.whiteColor];
    self.enableSwitch = [UISwitch new];
    self.enableSwitch.onTintColor = GBAccent();
    self.enableSwitch.on = store.enabled;
    [self.enableSwitch addTarget:self action:@selector(enableChanged) forControlEvents:UIControlEventValueChanged];

    UIButton *apply = [self wideButton:@"Apply & Reopen" color:GBAccent() textColor:UIColor.whiteColor];
    [apply addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *wipe = [self wideButton:@"Wipe data + re-spoof" color:[UIColor colorWithRed:0.22 green:0.13 blue:0.13 alpha:1.0]
                            textColor:[UIColor colorWithRed:1.0 green:0.42 blue:0.4 alpha:1.0]];
    [wipe addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *foot = [self label:@"“Wipe + re-spoof” deletes this app's data, saved logins, cookies and keychain (incl. iCloud) and rolls a new device. iCloud is blocked while spoofing is on, so old accounts can't sync back. Changes apply when the app reopens."
                           size:11 weight:UIFontWeightRegular color:GBSubtle()];
    foot.numberOfLines = 0;

    UIStackView *deviceRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.deviceValue, randomize]];
    deviceRow.axis = UILayoutConstraintAxisHorizontal; deviceRow.spacing = 10; deviceRow.alignment = UIStackViewAlignmentCenter;
    [randomize setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIView *enableSpacer = [UIView new];
    UIStackView *enableRow = [[UIStackView alloc] initWithArrangedSubviews:@[enableLabel, enableSpacer, self.enableSwitch]];
    enableRow.axis = UILayoutConstraintAxisHorizontal; enableRow.spacing = 8; enableRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:@[
        deviceLabel, deviceRow,
        [self spacer:8],
        enableRow,
        [self spacer:4],
        apply, wipe, foot
    ]];
    body.axis = UILayoutConstraintAxisVertical;
    body.spacing = 8;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [body setCustomSpacing:16 afterView:deviceRow];
    [self.card addSubview:body];

    title.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:title];
    [self.card addSubview:subtitle];
    [self.card addSubview:close];

    CGFloat cardW = MIN(360, UIScreen.mainScreen.bounds.size.width - 32);
    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.card.widthAnchor constraintEqualToConstant:cardW],

        [strip.topAnchor constraintEqualToAnchor:self.card.topAnchor],
        [strip.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [strip.heightAnchor constraintEqualToConstant:4],

        [title.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:18],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8],

        [close.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:14],
        [close.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],

        [body.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:16],
        [body.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:18],
        [body.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-18],
        [body.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-18],

        [apply.heightAnchor constraintEqualToConstant:46],
        [wipe.heightAnchor constraintEqualToConstant:46],
    ]];
}

#pragma mark Builders

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.text = text; l.textColor = color; l.font = [UIFont systemFontOfSize:size weight:weight];
    return l;
}

- (UIView *)spacer:(CGFloat)h {
    UIView *v = [UIView new];
    [v.heightAnchor constraintEqualToConstant:h].active = YES;
    return v;
}

- (UIButton *)pillButton:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [b setTitleColor:GBAccent() forState:UIControlStateNormal];
    b.backgroundColor = GBFieldBG();
    b.layer.cornerRadius = 8;
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    return b;
}

- (UIButton *)wideButton:(NSString *)title color:(UIColor *)color textColor:(UIColor *)textColor {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [b setTitleColor:textColor forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 12;
    return b;
}

#pragma mark Actions

- (void)bgTapped:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (!CGRectContainsPoint(self.card.frame, p)) { [self closeTapped]; }
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)randomizeTapped {
    [[GBStore shared] regenerateIdentity];
    self.deviceValue.text = [GBStore shared].summary;
}

- (void)enableChanged {
    GBStore *store = [GBStore shared];
    if (self.enableSwitch.on && !store.hasIdentity) { [store regenerateIdentity]; self.deviceValue.text = store.summary; }
    store.enabled = self.enableSwitch.on;
}

- (void)applyTapped {
    [self dismissViewControllerAnimated:YES completion:^{ GBQuit(); }];
}

- (void)wipeTapped {
    UIAlertController *c = [UIAlertController alertControllerWithTitle:@"Wipe this app?"
        message:@"Deletes this app's data, saved logins, cookies, web data and keychain (including iCloud-synced items), then rolls a brand-new device. The app closes — reopen it as a fresh, spoofed install with no previous accounts."
        preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Wipe + re-spoof" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        GBStore *store = [GBStore shared];
        store.enabled = YES;              // stay opted-in after the wipe
        GBClearAppData();
        [store regenerateIdentity];       // rewrites the identity plist (enabled + new device)
        GBQuit();
    }]];
    [self presentViewController:c animated:YES completion:nil];
}

@end

#pragma mark - Presentation

@implementation GBMenu

+ (UIViewController *)topVCForWindow:(UIWindow *)window {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)presentFromWindow:(UIWindow *)window {
    UIViewController *host = [self topVCForWindow:window];
    if (!host || [host isKindOfClass:GBPanelViewController.class]) return;
    GBPanelViewController *panel = [GBPanelViewController new];
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    panel.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [host presentViewController:panel animated:YES completion:nil];
}

@end

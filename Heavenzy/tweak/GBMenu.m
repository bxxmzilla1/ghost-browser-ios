#import "GBMenu.h"
#import "GBStore.h"
#import "GBTokens.h"
#import "GBBundleSocial.h"
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

#pragma mark - Style

static UIColor *GBAccent(void)  { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; } // heavenzy violet
static UIColor *GBCardBG(void)  { return [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0]; }
static UIColor *GBFieldBG(void) { return [UIColor colorWithRed:0.17 green:0.17 blue:0.21 alpha:1.0]; }
static UIColor *GBSubtle(void)  { return [UIColor colorWithWhite:0.64 alpha:1.0]; }

static UILabel *GBLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *l = [UILabel new];
    l.text = text; l.textColor = color; l.font = [UIFont systemFontOfSize:size weight:weight];
    return l;
}

static UIView *GBSpacer(CGFloat h) {
    UIView *v = [UIView new];
    [v.heightAnchor constraintEqualToConstant:h].active = YES;
    return v;
}

static UIButton *GBPill(NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [b setTitleColor:GBAccent() forState:UIControlStateNormal];
    b.backgroundColor = GBFieldBG();
    b.layer.cornerRadius = 8;
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return b;
}

static UIButton *GBWide(NSString *title, UIColor *bg, UIColor *fg) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [b setTitleColor:fg forState:UIControlStateNormal];
    b.backgroundColor = bg;
    b.layer.cornerRadius = 12;
    [b.heightAnchor constraintEqualToConstant:46].active = YES;
    return b;
}

#pragma mark - Heavenzy panel

@interface GBPanelViewController : UIViewController
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *deviceValue;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UIButton *connectButton;
@end

@implementation GBPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTapped:)]];
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

    UILabel *title = GBLabel(@"Heavenzy", 20, UIFontWeightBold, UIColor.whiteColor);
    UILabel *subtitle = GBLabel(([[NSBundle mainBundle] bundleIdentifier] ?: @""), 12, UIFontWeightRegular, GBSubtle());
    title.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:title];
    [self.card addSubview:subtitle];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:GBSubtle() forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:close];

    self.deviceValue = GBLabel(store.summary, 16, UIFontWeightSemibold, UIColor.whiteColor);
    self.deviceValue.numberOfLines = 2;
    UIButton *randomize = GBPill(@"Randomize");
    [randomize addTarget:self action:@selector(randomizeTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *deviceRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.deviceValue, randomize]];
    deviceRow.axis = UILayoutConstraintAxisHorizontal; deviceRow.spacing = 10; deviceRow.alignment = UIStackViewAlignmentCenter;

    self.detail = GBLabel([self detailText], 11, UIFontWeightRegular, GBSubtle());
    self.detail.numberOfLines = 0;

    self.enableSwitch = [UISwitch new];
    self.enableSwitch.onTintColor = GBAccent();
    self.enableSwitch.on = store.enabled;
    [self.enableSwitch addTarget:self action:@selector(enableChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *enableRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        GBLabel(@"Spoof this app", 16, UIFontWeightMedium, UIColor.whiteColor), [UIView new], self.enableSwitch]];
    enableRow.axis = UILayoutConstraintAxisHorizontal; enableRow.spacing = 8; enableRow.alignment = UIStackViewAlignmentCenter;

    UIButton *wipe = GBWide(@"Wipe data + re-spoof", GBAccent(), UIColor.whiteColor);
    [wipe addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *foot = GBLabel(@"Keeps your real iPhone model but resets the identity (serial, UDID, IDFV, IDFA, Wi-Fi/Bluetooth MAC, IMEI). Deletes this app's data, saved logins, cookies and keychain (incl. iCloud) and reopens it as a fresh install with the identity above. Tap Randomize to roll a new one. iCloud + returning-device checks are blocked while on, so the app can't tell it was installed here before.",
                            11, UIFontWeightRegular, GBSubtle());
    foot.numberOfLines = 0;

    NSMutableArray *rows;
    BOOL igOnly = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.burbn.instagram"];
    if (igOnly) {
        // Inside Instagram the panel is just the Bundle.social connect button (per request).
        self.connectButton = GBWide(@"Connect via Bundle.social", GBAccent(), UIColor.whiteColor);
        [self.connectButton addTarget:self action:@selector(connectBundleTapped) forControlEvents:UIControlEventTouchUpInside];
        UILabel *igFoot = GBLabel(@"Opens the Bundle.social hosted page to connect this Instagram account. "
                                  @"Add your API key in the Heavenzy app → Settings first.",
                                  11, UIFontWeightRegular, GBSubtle());
        igFoot.numberOfLines = 0;
        rows = [@[ self.connectButton, igFoot ] mutableCopy];
    } else {
        rows = [@[
            GBLabel(@"DEVICE IDENTITY", 11, UIFontWeightSemibold, GBSubtle()), deviceRow, self.detail,
            GBSpacer(8), enableRow, GBSpacer(4), wipe, foot ] mutableCopy];
    }
    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:rows];
    body.axis = UILayoutConstraintAxisVertical; body.spacing = 8;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    if (!igOnly) [body setCustomSpacing:16 afterView:self.detail];
    [self.card addSubview:body];

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
    ]];
}

- (NSString *)detailText {
    GBStore *s = [GBStore shared];
    if (!s.hasIdentity) return @"";
    // Same real iPhone — only these identifiers are reset.
    return [NSString stringWithFormat:@"Serial %@\nUDID %@\nIDFV %@\nIDFA %@\nWi-Fi %@ · BT %@\nIMEI %@",
            s.serialNumber ?: @"—", s.udid ?: @"—", s.idfv ?: @"—", s.idfa ?: @"—",
            s.wifiAddress ?: @"—", s.bluetoothAddress ?: @"—", s.imei ?: @"—"];
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
    self.detail.text = [self detailText];
}

- (void)enableChanged {
    GBStore *store = [GBStore shared];
    if (self.enableSwitch.on && !store.hasIdentity) {
        [store regenerateIdentity];
        self.deviceValue.text = store.summary;
        self.detail.text = [self detailText];
    }
    store.enabled = self.enableSwitch.on;
}

- (void)copyTokenTapped {
    NSString *blob = [GBTokens instagramTokenBlob];
    if (blob.length == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No token data"
            message:@"There's no Instagram token stored right now — log in first, then try again."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    UIPasteboard.generalPasteboard.string = blob;
    NSInteger accounts = [blob componentsSeparatedByString:@"\n"].count;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Copied"
        message:[NSString stringWithFormat:@"%ld account%@ copied to the clipboard (Authorization, IG-U-DS-USER-ID, X-MID, X-IG-WWW-Claim).",
                 (long)accounts, accounts == 1 ? @"" : @"s"]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)connectBundleTapped {
    GBStore *s = [GBStore shared];
    if (s.bundleKey.length == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No API key"
            message:@"Open the Heavenzy app, tap the gear (Settings) and paste your Bundle.social API key first."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    self.connectButton.enabled = NO;
    [self.connectButton setTitle:@"Connecting…" forState:UIControlStateNormal];
    [GBBundleSocial instagramPortalWithKey:s.bundleKey team:s.bundleTeam completion:^(NSURL *url, NSString *error) {
        self.connectButton.enabled = YES;
        [self.connectButton setTitle:@"Connect via Bundle.social" forState:UIControlStateNormal];
        if (url) {
            [self dismissViewControllerAnimated:YES completion:^{
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }];
        } else {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Couldn't connect"
                message:error ?: @"Unknown error." preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    }];
}

- (void)wipeTapped {
    GBStore *store = [GBStore shared];
    if (!store.hasIdentity) { [store regenerateIdentity]; self.deviceValue.text = store.summary; self.detail.text = [self detailText]; }

    UIAlertController *c = [UIAlertController alertControllerWithTitle:@"Wipe + re-spoof?"
        message:[NSString stringWithFormat:@"Deletes this app's data, saved logins, cookies, web data and keychain (including iCloud-synced items), applies “%@” and reopens the app as a fresh install with no previous accounts. Your real iPhone model is unchanged.", store.summary]
        preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Wipe + re-spoof" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        store.enabled = YES;   // stay opted-in after the wipe
        GBClearAppData();      // this also deletes our own plist inside the app container…
        [store save];          // …so rewrite it (device shown above + bubble position)
        GBQuit();              // reopen → fresh install with that identity
    }]];
    [self presentViewController:c animated:YES completion:nil];
}

@end

#pragma mark - Presentation

@implementation GBMenu

+ (void)clearAppData { GBClearAppData(); }

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

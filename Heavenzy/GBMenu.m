#import "GBMenu.h"
#import "GBStore.h"
#import "GBBundle.h"
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <SafariServices/SafariServices.h>

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

#pragma mark - Shared style

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
    [b setTitleColor:[fg colorWithAlphaComponent:0.4] forState:UIControlStateDisabled];
    b.backgroundColor = bg;
    b.layer.cornerRadius = 12;
    [b.heightAnchor constraintEqualToConstant:46].active = YES;
    return b;
}

static UITextField *GBField(NSString *placeholder) {
    UITextField *f = [UITextField new];
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.45 alpha:1] }];
    f.textColor = UIColor.whiteColor;
    f.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    f.backgroundColor = GBFieldBG();
    f.layer.cornerRadius = 10;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.keyboardAppearance = UIKeyboardAppearanceDark;
    f.returnKeyType = UIReturnKeyDone;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
    f.leftView = pad; f.leftViewMode = UITextFieldViewModeAlways;
    [f.heightAnchor constraintEqualToConstant:44].active = YES;
    return f;
}

/// Dark dimmed backdrop + centered card. Subclasses fill `body` and set the header title.
@interface GBCardViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *body;
@property (nonatomic, strong) UIStackView *headerAccessories;   // buttons left of the ✕
- (void)buildCardWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)addHeaderButton:(UIButton *)b;
- (void)closeTapped;
@end

@implementation GBCardViewController

- (void)buildCardWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTapped:)]];

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

    UILabel *titleL = GBLabel(title, 20, UIFontWeightBold, UIColor.whiteColor);
    UILabel *subL = GBLabel(subtitle ?: @"", 12, UIFontWeightRegular, GBSubtle());
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    subL.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:titleL];
    [self.card addSubview:subL];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:GBSubtle() forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [close.widthAnchor constraintEqualToConstant:28].active = YES;
    [close.heightAnchor constraintEqualToConstant:28].active = YES;

    self.headerAccessories = [[UIStackView alloc] initWithArrangedSubviews:@[close]];
    self.headerAccessories.axis = UILayoutConstraintAxisHorizontal;
    self.headerAccessories.spacing = 8;
    self.headerAccessories.alignment = UIStackViewAlignmentCenter;
    self.headerAccessories.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.headerAccessories];

    self.body = [UIStackView new];
    self.body.axis = UILayoutConstraintAxisVertical;
    self.body.spacing = 8;
    self.body.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.body];

    CGFloat cardW = MIN(360, UIScreen.mainScreen.bounds.size.width - 32);
    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.card.widthAnchor constraintEqualToConstant:cardW],

        [strip.topAnchor constraintEqualToAnchor:self.card.topAnchor],
        [strip.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [strip.heightAnchor constraintEqualToConstant:4],

        [titleL.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:16],
        [titleL.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:18],
        [subL.topAnchor constraintEqualToAnchor:titleL.bottomAnchor constant:2],
        [subL.leadingAnchor constraintEqualToAnchor:titleL.leadingAnchor],
        [subL.trailingAnchor constraintLessThanOrEqualToAnchor:self.headerAccessories.leadingAnchor constant:-8],

        [self.headerAccessories.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:14],
        [self.headerAccessories.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],

        [self.body.topAnchor constraintEqualToAnchor:subL.bottomAnchor constant:16],
        [self.body.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:18],
        [self.body.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-18],
        [self.body.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-18],
    ]];
}

- (void)addHeaderButton:(UIButton *)b {
    [self.headerAccessories insertArrangedSubview:b atIndex:0];
}

- (void)bgTapped:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (!CGRectContainsPoint(self.card.frame, p)) {
        [self.view endEditing:YES];
        [self closeTapped];
    }
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

// Keep the card visible above the keyboard.
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kb:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)kb:(NSNotification *)n {
    CGRect kbEnd = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetMaxY(self.card.frame) + 12 - kbEnd.origin.y;
    CGFloat dy = (kbEnd.origin.y >= UIScreen.mainScreen.bounds.size.height || overlap <= 0) ? 0 : -overlap;
    [UIView animateWithDuration:0.25 animations:^{ self.card.transform = CGAffineTransformMakeTranslation(0, dy); }];
}

@end

#pragma mark - Settings (Bundle.social API key)

@interface GBSettingsViewController : GBCardViewController
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *teamField;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, copy) void (^onSaved)(void);
@end

@implementation GBSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildCardWithTitle:@"Settings" subtitle:@"Bundle.social"];
    GBStore *store = [GBStore shared];

    self.keyField = GBField(@"Bundle.social API key");
    self.keyField.text = store.bundleAPIKey;
    self.keyField.delegate = self;
    UIButton *paste = GBPill(@"Paste");
    [paste addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *keyRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.keyField, paste]];
    keyRow.axis = UILayoutConstraintAxisHorizontal; keyRow.spacing = 8; keyRow.alignment = UIStackViewAlignmentCenter;

    self.teamField = GBField(@"Team ID (optional — first team if empty)");
    self.teamField.text = store.bundleTeamId;
    self.teamField.delegate = self;

    self.status = GBLabel(@"Get the key from bundle.social → Organization → API keys.", 11, UIFontWeightRegular, GBSubtle());
    self.status.numberOfLines = 0;

    UIButton *test = GBWide(@"Test key", GBFieldBG(), GBAccent());
    [test addTarget:self action:@selector(testTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *save = GBWide(@"Save", GBAccent(), UIColor.whiteColor);
    [save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[ GBLabel(@"API KEY", 11, UIFontWeightSemibold, GBSubtle()), keyRow,
                         GBSpacer(4),
                         GBLabel(@"TEAM", 11, UIFontWeightSemibold, GBSubtle()), self.teamField,
                         self.status, GBSpacer(4), test, save ]) {
        [self.body addArrangedSubview:v];
    }
}

- (void)pasteTapped {
    NSString *s = [UIPasteboard.generalPasteboard.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length) { self.keyField.text = s; self.status.text = @"Pasted. Tap Test key to verify."; }
    else { self.status.text = @"Clipboard is empty."; }
}

- (NSString *)trimmed:(UITextField *)f {
    return [f.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)testTapped {
    [self.view endEditing:YES];
    self.status.text = @"Checking…";
    [GBBundle organizationWithKey:[self trimmed:self.keyField] completion:^(NSString *orgName, NSArray<NSDictionary *> *teams, NSError *error) {
        if (error) { self.status.text = error.localizedDescription; return; }
        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *t in teams) { if (t[@"name"]) [names addObject:t[@"name"]]; }
        self.status.text = [NSString stringWithFormat:@"✓ %@ · %lu team%@%@", orgName, (unsigned long)teams.count,
                            teams.count == 1 ? @"" : @"s",
                            names.count ? [NSString stringWithFormat:@": %@", [names componentsJoinedByString:@", "]] : @""];
    }];
}

- (void)saveTapped {
    [self.view endEditing:YES];
    GBStore *store = [GBStore shared];
    store.bundleAPIKey = [self trimmed:self.keyField];
    store.bundleTeamId = [self trimmed:self.teamField];
    [store save];
    if (self.onSaved) self.onSaved();
    [self closeTapped];
}

@end

#pragma mark - Heavenzy panel

@interface GBPanelViewController : GBCardViewController
@property (nonatomic, strong) UILabel *deviceValue;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UILabel *connectStatus;
@end

@implementation GBPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildCardWithTitle:@"Heavenzy" subtitle:([[NSBundle mainBundle] bundleIdentifier] ?: @"")];
    GBStore *store = [GBStore shared];

    UIButton *settings = GBPill(@"Settings");
    [settings addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addHeaderButton:settings];

    self.deviceValue = GBLabel(store.summary, 16, UIFontWeightSemibold, UIColor.whiteColor);
    self.deviceValue.numberOfLines = 2;
    UIButton *randomize = GBPill(@"Randomize");
    [randomize addTarget:self action:@selector(randomizeTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *deviceRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.deviceValue, randomize]];
    deviceRow.axis = UILayoutConstraintAxisHorizontal; deviceRow.spacing = 10; deviceRow.alignment = UIStackViewAlignmentCenter;

    self.enableSwitch = [UISwitch new];
    self.enableSwitch.onTintColor = GBAccent();
    self.enableSwitch.on = store.enabled;
    [self.enableSwitch addTarget:self action:@selector(enableChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *enableRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        GBLabel(@"Spoof this app", 16, UIFontWeightMedium, UIColor.whiteColor), [UIView new], self.enableSwitch]];
    enableRow.axis = UILayoutConstraintAxisHorizontal; enableRow.spacing = 8; enableRow.alignment = UIStackViewAlignmentCenter;

    self.connectButton = GBWide(@"Connect Instagram to Bundle.social", GBFieldBG(), GBAccent());
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    self.connectStatus = GBLabel(@"", 11, UIFontWeightRegular, GBSubtle());
    self.connectStatus.numberOfLines = 0;
    [self refreshConnectStatus];

    UIButton *wipe = GBWide(@"Wipe data + re-spoof", GBAccent(), UIColor.whiteColor);
    [wipe addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *foot = GBLabel(@"Deletes this app's data, saved logins, cookies and keychain (incl. iCloud), applies the device shown above and reopens the app as a fresh install. Tap Randomize first to roll a different device. iCloud is blocked while spoofing is on, so old accounts can't sync back.",
                            11, UIFontWeightRegular, GBSubtle());
    foot.numberOfLines = 0;

    for (UIView *v in @[ GBLabel(@"SPOOFED DEVICE", 11, UIFontWeightSemibold, GBSubtle()), deviceRow,
                         GBSpacer(8), enableRow, GBSpacer(4),
                         self.connectButton, self.connectStatus,
                         GBSpacer(4), wipe, foot ]) {
        [self.body addArrangedSubview:v];
    }
    [self.body setCustomSpacing:16 afterView:deviceRow];
}

- (void)refreshConnectStatus {
    GBStore *store = [GBStore shared];
    self.connectStatus.text = store.bundleAPIKey.length
        ? (store.bundleTeamId.length ? [NSString stringWithFormat:@"Bundle.social key set · team %@", store.bundleTeamId]
                                     : @"Bundle.social key set · first team in your organization")
        : @"No Bundle.social API key yet — add it in Settings.";
}

#pragma mark Actions

- (void)settingsTapped {
    GBSettingsViewController *s = [GBSettingsViewController new];
    s.modalPresentationStyle = UIModalPresentationOverFullScreen;
    s.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    __weak typeof(self) weakSelf = self;
    s.onSaved = ^{ [weakSelf refreshConnectStatus]; };
    [self presentViewController:s animated:YES completion:nil];
}

- (void)randomizeTapped {
    [[GBStore shared] regenerateIdentity];
    self.deviceValue.text = [GBStore shared].summary;
}

- (void)enableChanged {
    GBStore *store = [GBStore shared];
    if (self.enableSwitch.on && !store.hasIdentity) { [store regenerateIdentity]; self.deviceValue.text = store.summary; }
    store.enabled = self.enableSwitch.on;
}

- (void)connectTapped {
    GBStore *store = [GBStore shared];
    if (store.bundleAPIKey.length == 0) { [self settingsTapped]; return; }
    self.connectButton.enabled = NO;
    self.connectStatus.text = @"Contacting bundle.social…";
    [GBBundle instagramConnectURLWithKey:store.bundleAPIKey teamId:store.bundleTeamId
                              completion:^(NSURL *url, NSString *teamName, NSError *error) {
        self.connectButton.enabled = YES;
        if (error) { self.connectStatus.text = [@"✕ " stringByAppendingString:error.localizedDescription]; return; }
        self.connectStatus.text = [NSString stringWithFormat:@"Log in to Instagram in the sheet to link it to team “%@”. Close the sheet when it says connected.", teamName];
        SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
        svc.preferredBarTintColor = GBCardBG();
        svc.preferredControlTintColor = GBAccent();
        svc.dismissButtonStyle = SFSafariViewControllerDismissButtonStyleClose;
        [self presentViewController:svc animated:YES completion:nil];
    }];
}

- (void)wipeTapped {
    GBStore *store = [GBStore shared];
    if (!store.hasIdentity) { [store regenerateIdentity]; self.deviceValue.text = store.summary; }

    UIAlertController *c = [UIAlertController alertControllerWithTitle:@"Wipe + re-spoof?"
        message:[NSString stringWithFormat:@"Deletes this app's data, saved logins, cookies, web data and keychain (including iCloud-synced items), applies “%@” and reopens the app as a fresh install with no previous accounts.", store.summary]
        preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Wipe + re-spoof" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        store.enabled = YES;   // stay opted-in after the wipe
        GBClearAppData();      // this also deletes our own plist inside the app container…
        [store save];          // …so rewrite it (device shown above, Bundle.social key, bubble position)
        GBQuit();              // reopen → fresh install with that identity
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
    if (!host || [host isKindOfClass:GBCardViewController.class] || [host isKindOfClass:SFSafariViewController.class]) return;
    GBPanelViewController *panel = [GBPanelViewController new];
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    panel.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [host presentViewController:panel animated:YES completion:nil];
}

@end

#import "GBOverlay.h"
#import "GBStore.h"
#import "GBScanner.h"

#pragma mark - Style

static UIColor *GBAccent(void) { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; }
static UIColor *GBCardBG(void) { return [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:0.98]; }
static UIColor *GBFieldBG(void){ return [UIColor colorWithRed:0.17 green:0.17 blue:0.21 alpha:1.0]; }
static UIColor *GBSubtle(void) { return [UIColor colorWithWhite:0.64 alpha:1.0]; }

static UILabel *GBLabel(NSString *t, CGFloat size, UIFontWeight w, UIColor *c) {
    UILabel *l = [UILabel new]; l.text = t; l.font = [UIFont systemFontOfSize:size weight:w]; l.textColor = c; return l;
}

#pragma mark - Panel controller

@interface GBOverlayController : UIViewController
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) NSLayoutConstraint *cardLeading;
@property (nonatomic, strong) NSLayoutConstraint *cardTop;
@property (nonatomic, assign) BOOL positioned;
@property (nonatomic, assign) CGPoint dragStart;

@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UILabel *scanHintLabel;
@property (nonatomic, strong) UIButton *listToggle;          // "N usernames" row — expands/collapses the list
@property (nonatomic, strong) UIImageView *listChevron;     // chevron pinned to the right of listToggle
@property (nonatomic, strong) UITextView *usernamesView;
@property (nonatomic, assign) BOOL listExpanded;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *collectedUsernames;
@property (nonatomic, strong) NSTimer *autoTimer;
@property (nonatomic, assign) BOOL autoRunning;   // auto loop active in this panel session (toggled by Scan)
@property (nonatomic, assign) BOOL scanInFlight;

- (void)refreshState;
- (void)panelDidShow;
- (BOOL)isInstagramHost;
@end

static BOOL GBIsInstagramBundle(void) {
    NSBundle *b = [NSBundle mainBundle];
    if ([b.bundleIdentifier.lowercaseString containsString:@"instagram"]) return YES;   // com.burbn.instagram + duplicates
    NSString *name = b.infoDictionary[@"CFBundleDisplayName"] ?: b.infoDictionary[@"CFBundleName"];
    return [name.lowercaseString containsString:@"instagram"];
}

@implementation GBOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    self.card = [UIView new];
    self.card.backgroundColor = GBCardBG();
    self.card.layer.cornerRadius = 16;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = 0.5; self.card.layer.shadowRadius = 12; self.card.layer.shadowOffset = CGSizeMake(0, 4);
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.card];

    // Accent grip strip (also the drag handle hint).
    UIView *strip = [UIView new]; strip.backgroundColor = GBAccent();
    strip.layer.cornerRadius = 2; strip.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:strip];

    UILabel *title = GBLabel(@"Kairos", 15, UIFontWeightBold, UIColor.whiteColor);
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:GBSubtle() forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [close.widthAnchor constraintEqualToConstant:30].active = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[ title, [UIView new], close ]];
    header.alignment = UIStackViewAlignmentCenter;

    self.collectedUsernames = [NSMutableOrderedSet orderedSet];

    self.scanHintLabel = GBLabel(@"", 13, UIFontWeightSemibold, GBSubtle());
    self.scanHintLabel.numberOfLines = 1;
    self.scanHintLabel.textAlignment = NSTextAlignmentCenter;

    // Collapsible list: a one-line summary row (label left, chevron pinned right) toggling the list.
    self.listToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    self.listToggle.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.listToggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.listToggle.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.listToggle.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 34);   // leave room for the chevron
    self.listToggle.backgroundColor = GBFieldBG();
    self.listToggle.layer.cornerRadius = 10;
    [self.listToggle addTarget:self action:@selector(toggleList) forControlEvents:UIControlEventTouchUpInside];
    [self.listToggle.heightAnchor constraintEqualToConstant:36].active = YES;
    self.listToggle.hidden = YES;

    self.listChevron = [[UIImageView alloc] init];
    self.listChevron.tintColor = GBSubtle();
    self.listChevron.contentMode = UIViewContentModeScaleAspectFit;
    self.listChevron.translatesAutoresizingMaskIntoConstraints = NO;
    [self.listToggle addSubview:self.listChevron];
    [NSLayoutConstraint activateConstraints:@[
        [self.listChevron.trailingAnchor constraintEqualToAnchor:self.listToggle.trailingAnchor constant:-14],
        [self.listChevron.centerYAnchor constraintEqualToAnchor:self.listToggle.centerYAnchor],
        [self.listChevron.widthAnchor constraintEqualToConstant:14],
        [self.listChevron.heightAnchor constraintEqualToConstant:14],
    ]];

    self.usernamesView = [UITextView new];
    self.usernamesView.backgroundColor = GBFieldBG();
    self.usernamesView.textColor = UIColor.whiteColor;
    self.usernamesView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.usernamesView.editable = NO;
    self.usernamesView.selectable = YES;
    self.usernamesView.layer.cornerRadius = 8;
    self.usernamesView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.usernamesView.hidden = YES;
    [self.usernamesView.heightAnchor constraintEqualToConstant:140].active = YES;

    // Copy · Clear · Scan on one row, Scan pinned to the right and always the primary action.
    self.exportButton = [self wideButton:@"Copy" bg:GBFieldBG() fg:GBAccent()];
    [self.exportButton addTarget:self action:@selector(copyUsernames) forControlEvents:UIControlEventTouchUpInside];
    self.clearButton = [self wideButton:@"Clear" bg:GBFieldBG() fg:GBSubtle()];
    [self.clearButton addTarget:self action:@selector(clearUsernames) forControlEvents:UIControlEventTouchUpInside];
    self.scanButton = [self wideButton:@"Scan" bg:GBAccent() fg:UIColor.whiteColor];
    self.scanButton.layer.shadowColor = GBAccent().CGColor;   // accent glow used by the auto pulse
    self.scanButton.layer.shadowOffset = CGSizeZero;
    self.scanButton.layer.shadowRadius = 0;
    self.scanButton.layer.shadowOpacity = 0;
    [self.scanButton addTarget:self action:@selector(scanPressed) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[ self.exportButton, self.clearButton, self.scanButton ]];
    actions.axis = UILayoutConstraintAxisHorizontal; actions.spacing = 8; actions.distribution = UIStackViewDistributionFillEqually;

    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, self.scanHintLabel, self.listToggle, self.usernamesView, actions ]];
    body.axis = UILayoutConstraintAxisVertical; body.spacing = 8;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:body];

    self.cardLeading = [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20];
    self.cardTop = [self.card.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:400];
    [NSLayoutConstraint activateConstraints:@[
        [self.card.widthAnchor constraintEqualToConstant:300], self.cardLeading, self.cardTop,
        [strip.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:8],
        [strip.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [strip.widthAnchor constraintEqualToConstant:40],
        [strip.heightAnchor constraintEqualToConstant:4],
        [body.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:16],
        [body.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [body.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],
        [body.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-16],
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.card addGestureRecognizer:pan];

    [self refreshState];
    // The control app can change Auto / approved names while we're in the background; re-read on return.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [self.autoTimer invalidate]; }

- (void)appBecameActive {
    if (self.view.window.hidden) return;
    [[GBStore shared] reloadPanelSettings];
    [self refreshState];
}

- (BOOL)isInstagramHost { return GBIsInstagramBundle(); }

// Sync button state with the host app + the control app's Auto setting.
- (void)refreshState {
    BOOL ig = [self isInstagramHost];
    self.scanButton.enabled = ig && !self.scanInFlight;
    self.scanButton.alpha = ig ? 1 : 0.5;
    if (!ig && !self.collectedUsernames.count)
        self.scanHintLabel.text = @"Works inside Instagram.";
    if (![GBStore shared].autoScan) self.autoRunning = NO;   // setting off => never auto
    [self refreshUsernameList];
    [self updateAutoScan];
    [self updateScanButtonAppearance];
}

// Called when the panel is (re)shown: start the auto loop if Auto is enabled.
- (void)panelDidShow {
    [self refreshState];
    if ([GBStore shared].autoScan) self.autoRunning = YES;
    [self updateAutoScan];
    [self updateScanButtonAppearance];
}

// Start/stop the once-a-second auto scanner based on local running state + visibility.
- (void)updateAutoScan {
    BOOL want = self.autoRunning && [self isInstagramHost] && self.view.window && !self.view.window.hidden;
    if (want && !self.autoTimer) {
        self.autoTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            [self autoTick];
        }];
        [self autoTick];   // fire immediately so the first second isn't wasted
    } else if (!want && self.autoTimer) {
        [self.autoTimer invalidate]; self.autoTimer = nil;
    }
}

- (void)autoTick {
    if (self.scanInFlight) return;          // don't stack scans
    if (self.view.window.hidden) { [self updateAutoScan]; return; }
    [self scanTapped];
}

// While Auto is running the Scan button glows/pulses; pressing it toggles the loop.
- (void)updateScanButtonAppearance {
    if (self.autoRunning) [self startScanPulse]; else [self stopScanPulse];
}

- (void)startScanPulse {
    if ([self.scanButton.layer animationForKey:@"glow"]) return;
    CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    op.fromValue = @0.25; op.toValue = @0.95;
    CABasicAnimation *rad = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    rad.fromValue = @3; rad.toValue = @13;
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @1.0; scale.toValue = @1.03;
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[ op, rad, scale ];
    g.duration = 0.85; g.autoreverses = YES; g.repeatCount = HUGE_VALF;
    g.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.scanButton.layer addAnimation:g forKey:@"glow"];
}

- (void)stopScanPulse {
    [self.scanButton.layer removeAnimationForKey:@"glow"];
    self.scanButton.layer.shadowOpacity = 0;
    self.scanButton.layer.shadowRadius = 0;
}

- (void)scanPressed {
    if ([GBStore shared].autoScan) {       // Auto mode: the Scan button toggles the loop on/off
        self.autoRunning = !self.autoRunning;
        [self updateAutoScan];
        [self updateScanButtonAppearance];
        self.scanHintLabel.text = self.autoRunning ? @"Auto on — scroll to collect." : @"Auto paused.";
    } else {
        [self scanTapped];
    }
}

- (void)refreshUsernameList {
    NSUInteger n = self.collectedUsernames.count;
    BOOL any = n > 0;
    self.listToggle.hidden = !any;
    self.usernamesView.hidden = !(any && self.listExpanded);
    self.exportButton.enabled = any; self.exportButton.alpha = any ? 1 : 0.5;
    self.clearButton.enabled  = any; self.clearButton.alpha  = any ? 1 : 0.5;
    if (any) {
        NSString *title = [NSString stringWithFormat:@"%lu username%@", (unsigned long)n, n == 1 ? @"" : @"s"];
        [self.listToggle setTitle:title forState:UIControlStateNormal];
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
        self.listChevron.image = [UIImage systemImageNamed:self.listExpanded ? @"chevron.up" : @"chevron.down" withConfiguration:c];
        NSMutableString *lines = [NSMutableString new];
        for (NSString *u in self.collectedUsernames) [lines appendFormat:@"@%@\n", u];
        self.usernamesView.text = lines;
    }
}

- (void)toggleList {
    self.listExpanded = !self.listExpanded;
    [self refreshUsernameList];
    [self relayoutCard];
}

- (void)clearUsernames {
    [self.collectedUsernames removeAllObjects];
    self.listExpanded = NO;
    self.scanHintLabel.text = @"";
    [self refreshUsernameList];
    [self relayoutCard];
}

- (UIButton *)wideButton:(NSString *)t bg:(UIColor *)bg fg:(UIColor *)fg {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b setTitleColor:fg forState:UIControlStateNormal];
    b.backgroundColor = bg; b.layer.cornerRadius = 10;
    [b.heightAnchor constraintEqualToConstant:42].active = YES;
    return b;
}

#pragma mark Placement

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.positioned || self.card.frame.size.height <= 0) return;
    self.positioned = YES;
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGPoint saved = [GBStore shared].floatingOrigin;
    if (saved.x >= 0 && saved.y >= 0) {
        self.cardLeading.constant = saved.x;
        self.cardTop.constant = saved.y;
    } else {
        self.cardLeading.constant = (b.size.width - self.card.frame.size.width) / 2;               // centered
        self.cardTop.constant = b.size.height - self.card.frame.size.height - safe.bottom - 24;    // near the bottom
    }
    [self clampConstants];
}

- (void)clampConstants {
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat w = self.card.frame.size.width, h = self.card.frame.size.height;
    CGFloat maxX = b.size.width - w - 8, maxY = b.size.height - h - MAX(8, safe.bottom);
    self.cardLeading.constant = MIN(MAX(self.cardLeading.constant, 8), MAX(8, maxX));
    self.cardTop.constant = MIN(MAX(self.cardTop.constant, MAX(8, safe.top)), MAX(8, maxY));
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    if (g.state == UIGestureRecognizerStateBegan) {
        self.dragStart = CGPointMake(self.cardLeading.constant, self.cardTop.constant);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        self.cardLeading.constant = self.dragStart.x + t.x;
        self.cardTop.constant = self.dragStart.y + t.y;
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self clampConstants];
        [UIView animateWithDuration:0.15 animations:^{ [self.view layoutIfNeeded]; }];
        GBStore *s = [GBStore shared];
        s.floatingOrigin = CGPointMake(self.cardLeading.constant, self.cardTop.constant);
        [s save];
    }
}

#pragma mark Actions

- (void)closeTapped {
    self.view.window.hidden = YES;
    [self updateAutoScan];   // stop the auto timer while hidden
}

// Parse the control app's approved-names list (one per line, "#" comments) into lowercased names.
- (NSSet<NSString *> *)approvedNameSet {
    NSString *raw = [GBStore shared].approvedNames;
    if (!raw.length) return nil;
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *line in [raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!t.length || [t hasPrefix:@"#"]) continue;
        [set addObject:t.lowercaseString];
    }
    return set.count ? set : nil;
}

- (void)scanTapped {
    if (![self isInstagramHost] || self.scanInFlight) return;
    UIWindowScene *scene = self.view.window.windowScene;
    if (!scene) return;
    [[GBStore shared] reloadPanelSettings];   // pick up a fresh approved-names list from the control app
    NSSet *approved = [self approvedNameSet];
    self.scanInFlight = YES;
    self.scanButton.enabled = NO;
    if (!self.autoRunning) [self.scanButton setTitle:@"…" forState:UIControlStateNormal];
    __weak typeof(self) w = self;
    [GBScanner scanScene:scene excludingWindow:self.view.window approvedNames:approved completion:^(NSArray<NSString *> *usernames, NSString *method) {
        __strong typeof(w) s = w; if (!s) return;
        s.scanInFlight = NO;
        s.scanButton.enabled = YES;
        if (!s.autoRunning) [s.scanButton setTitle:@"Scan" forState:UIControlStateNormal];
        NSUInteger before = s.collectedUsernames.count;
        for (NSString *u in usernames) [s.collectedUsernames addObject:u];
        NSUInteger added = s.collectedUsernames.count - before;
        s.scanHintLabel.text = [NSString stringWithFormat:@"+%lu New", (unsigned long)added];
        [s refreshUsernameList];
        [s relayoutCard];
    }];
}

// The card grows when results appear; keep it fully on screen.
- (void)relayoutCard {
    [self.view layoutIfNeeded];
    [self clampConstants];
    [UIView animateWithDuration:0.15 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)copyUsernames {
    if (!self.collectedUsernames.count) return;
    NSMutableString *lines = [NSMutableString new];
    for (NSString *u in self.collectedUsernames) [lines appendFormat:@"@%@\n", u];
    UIPasteboard.generalPasteboard.string = lines;
    [self flash:self.scanHintLabel text:[NSString stringWithFormat:@"%lu usernames copied.", (unsigned long)self.collectedUsernames.count]];
}

- (void)flash:(UILabel *)l text:(NSString *)t {
    l.hidden = NO; NSString *prev = l.text; l.text = t;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if ([l.text isEqualToString:t]) l.text = prev; });
}

@end

#pragma mark - Window

@implementation GBOverlay

static NSMapTable<UIWindowScene *, GBOverlay *> *gOverlays;

+ (void)showInScene:(UIWindowScene *)scene {
    if (!scene) return;
    if (!gOverlays) gOverlays = [NSMapTable weakToStrongObjectsMapTable];
    GBOverlay *w = [gOverlays objectForKey:scene];
    if (!w) {
        w = [[GBOverlay alloc] initWithWindowScene:scene];
        w.frame = scene.coordinateSpace.bounds;
        w.windowLevel = UIWindowLevelAlert + 5;
        w.backgroundColor = UIColor.clearColor;
        w.rootViewController = [GBOverlayController new];
        [gOverlays setObject:w forKey:scene];
        NSLog(@"[Heavenzy] panel created");
    }
    [w present];
}

// Show without permanently stealing key focus (so the app keeps its keyboard). Force an initial
// render once via makeKeyAndVisible, then hand key back to the app.
- (void)present {
    // Pick up Auto / approved-names changes made in the Heavenzy app since launch.
    [[GBStore shared] reloadPanelSettings];
    self.hidden = NO;
    [(GBOverlayController *)self.rootViewController panelDidShow];   // after unhide so auto-scan can start
    static BOOL forcedOnce = NO;
    if (!forcedOnce) {
        forcedOnce = YES;
        UIWindow *prev = nil;
        for (UIWindow *win in self.windowScene.windows) { if (win != self && win.isKeyWindow) { prev = win; break; } }
        [self makeKeyAndVisible];
        [prev makeKeyWindow];
    }
}

// Pass every touch through to the app except those landing on the panel card.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}

@end

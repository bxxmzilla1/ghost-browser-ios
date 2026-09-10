#import "GBOverlay.h"
#import "GBSMS.h"
#import "GBStore.h"

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

@property (nonatomic, strong) UILabel *serviceLabel;
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UILabel *phoneLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UIButton *againButton;

@property (nonatomic, copy)   NSString *orderId;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger pollTicks;
@end

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

    UILabel *title = GBLabel(@"Heavenzy SMS", 15, UIFontWeightBold, UIColor.whiteColor);
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:GBSubtle() forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [close.widthAnchor constraintEqualToConstant:30].active = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[ title, [UIView new], close ]];
    header.alignment = UIStackViewAlignmentCenter;

    self.serviceLabel = GBLabel([self serviceLine], 12, UIFontWeightRegular, GBSubtle());
    self.serviceLabel.numberOfLines = 2;

    self.getButton = [self wideButton:@"Get Number" bg:GBAccent() fg:UIColor.whiteColor];
    [self.getButton addTarget:self action:@selector(getTapped) forControlEvents:UIControlEventTouchUpInside];

    self.phoneLabel = GBLabel(@"", 20, UIFontWeightBold, UIColor.whiteColor);
    self.phoneLabel.textAlignment = NSTextAlignmentCenter;
    self.phoneLabel.userInteractionEnabled = YES;
    [self.phoneLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyPhone)]];
    self.phoneLabel.hidden = YES;

    self.statusLabel = GBLabel(@"", 12, UIFontWeightRegular, GBSubtle());
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.hidden = YES;

    self.codeLabel = GBLabel(@"", 30, UIFontWeightHeavy, GBAccent());
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.userInteractionEnabled = YES;
    [self.codeLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyCode)]];
    self.codeLabel.hidden = YES;

    self.againButton = [self wideButton:@"New Number" bg:GBFieldBG() fg:GBAccent()];
    [self.againButton addTarget:self action:@selector(newTapped) forControlEvents:UIControlEventTouchUpInside];
    self.againButton.hidden = YES;

    UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, self.serviceLabel, self.getButton, self.phoneLabel, self.codeLabel, self.statusLabel, self.againButton ]];
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
}

- (NSString *)serviceLine {
    return [NSString stringWithFormat:@"%@ · %@ · USA", [GBSMS providerLabel], [GBSMS serviceLabel]];
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

- (void)closeTapped { self.view.window.hidden = YES; }

- (void)getTapped {
    [self.pollTimer invalidate]; self.pollTimer = nil;
    self.getButton.enabled = NO;
    [self.getButton setTitle:@"Requesting…" forState:UIControlStateNormal];
    self.phoneLabel.hidden = YES; self.codeLabel.hidden = YES; self.againButton.hidden = YES;
    self.statusLabel.hidden = NO; self.statusLabel.textColor = GBSubtle();
    self.statusLabel.text = @"Requesting a number…";
    __weak typeof(self) w = self;
    [GBSMS requestNumberWithCompletion:^(NSString *phone, NSString *orderId, NSString *service, NSString *error) {
        __strong typeof(w) s = w; if (!s) return;
        s.getButton.enabled = YES;
        [s.getButton setTitle:@"Get Number" forState:UIControlStateNormal];
        if (error) { s.statusLabel.textColor = [UIColor systemRedColor]; s.statusLabel.text = error; return; }
        s.orderId = orderId;
        s.getButton.hidden = YES;
        s.phoneLabel.hidden = NO; s.phoneLabel.text = [s prettyPhone:phone];
        s.againButton.hidden = NO;
        s.statusLabel.textColor = GBSubtle();
        s.statusLabel.text = @"Waiting for the code… (tap the number to copy)";
        UIPasteboard.generalPasteboard.string = phone;
        [s startPolling];
    }];
}

- (NSString *)prettyPhone:(NSString *)p {
    if (p.length == 11 && [p hasPrefix:@"1"]) {
        return [NSString stringWithFormat:@"+1 (%@) %@-%@", [p substringWithRange:NSMakeRange(1,3)],
                [p substringWithRange:NSMakeRange(4,3)], [p substringWithRange:NSMakeRange(7,4)]];
    }
    return p.length ? [@"+" stringByAppendingString:p] : p;
}

- (void)startPolling {
    self.pollTicks = 0;
    __weak typeof(self) w = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
        __strong typeof(w) s = w; if (!s) { [t invalidate]; return; }
        s.pollTicks++;
        if (s.pollTicks > 80) {   // ~4 minutes
            [t invalidate]; s.pollTimer = nil;
            s.statusLabel.text = @"Timed out — tap New Number to try again.";
            return;
        }
        [GBSMS pollOrder:s.orderId completion:^(NSString *code, NSString *error) {
            __strong typeof(w) s2 = w; if (!s2) return;
            if (error) { return; }   // transient; keep polling
            if (code.length) {
                [s2.pollTimer invalidate]; s2.pollTimer = nil;
                s2.codeLabel.hidden = NO; s2.codeLabel.text = code;
                UIPasteboard.generalPasteboard.string = code;
                s2.statusLabel.textColor = GBAccent();
                s2.statusLabel.text = @"Code received & copied (tap to copy again).";
            }
        }];
    }];
}

- (void)newTapped {
    [self.pollTimer invalidate]; self.pollTimer = nil;
    if (self.orderId) [GBSMS cancelOrder:self.orderId];
    self.orderId = nil;
    self.phoneLabel.hidden = YES; self.codeLabel.hidden = YES; self.againButton.hidden = YES;
    self.statusLabel.hidden = YES;
    self.getButton.hidden = NO; self.getButton.enabled = YES;
    self.serviceLabel.text = [self serviceLine];
    [self getTapped];
}

- (void)copyPhone { if (self.phoneLabel.text.length) { UIPasteboard.generalPasteboard.string = [self digits:self.phoneLabel.text]; [self flash:self.statusLabel text:@"Number copied."]; } }
- (void)copyCode  { if (self.codeLabel.text.length)  { UIPasteboard.generalPasteboard.string = self.codeLabel.text; [self flash:self.statusLabel text:@"Code copied."]; } }

- (NSString *)digits:(NSString *)s {
    NSCharacterSet *non = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    return [[s componentsSeparatedByCharactersInSet:non] componentsJoinedByString:@""];
}

- (void)flash:(UILabel *)l text:(NSString *)t {
    l.hidden = NO; NSString *prev = l.text; l.text = t;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if ([l.text isEqualToString:t]) l.text = prev; });
}

@end

#pragma mark - Window

@implementation GBOverlay

static NSMapTable<UIWindowScene *, GBOverlay *> *gOverlays;

+ (void)installInScene:(UIWindowScene *)scene {
    if (!scene) return;
    if (scene.activationState != UISceneActivationStateForegroundActive &&
        scene.activationState != UISceneActivationStateForegroundInactive) return;
    if (!gOverlays) gOverlays = [NSMapTable weakToStrongObjectsMapTable];
    // Already installed for this scene: leave it as the user left it (closed stays closed until the
    // two-finger long-press brings it back).
    if ([gOverlays objectForKey:scene]) return;

    GBOverlay *w = [[GBOverlay alloc] initWithWindowScene:scene];
    w.frame = scene.coordinateSpace.bounds;
    w.windowLevel = UIWindowLevelAlert + 5;
    w.backgroundColor = UIColor.clearColor;
    w.rootViewController = [GBOverlayController new];
    [gOverlays setObject:w forKey:scene];
    [w present];
    NSLog(@"[Heavenzy] SMS panel installed (scene state %ld)", (long)scene.activationState);
}

+ (void)toggle {
    for (UIWindowScene *s in [[gOverlays keyEnumerator] allObjects]) {
        GBOverlay *w = [gOverlays objectForKey:s];
        if (w.hidden) [w present]; else w.hidden = YES;
    }
}

// Show without permanently stealing key focus (so the app keeps its keyboard). Force an initial
// render once via makeKeyAndVisible, then hand key back to the app.
- (void)present {
    self.hidden = NO;
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

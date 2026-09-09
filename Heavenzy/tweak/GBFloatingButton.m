#import "GBFloatingButton.h"
#import "GBStore.h"
#import "GBMenu.h"

static const CGFloat GBBubbleSize = 44;

@interface GBFloatingButton ()
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) BOOL dragging;
@end

@implementation GBFloatingButton

static NSMapTable<UIWindowScene *, GBFloatingButton *> *gBubbles;

+ (void)installInScene:(UIWindowScene *)scene {
    if (!scene) return;
    if (!gBubbles) gBubbles = [NSMapTable weakToStrongObjectsMapTable];
    GBFloatingButton *existing = [gBubbles objectForKey:scene];
    if (existing) { existing.hidden = NO; return; }

    GBFloatingButton *w = [[GBFloatingButton alloc] initWithWindowScene:scene];
    [gBubbles setObject:w forKey:scene];
    w.hidden = NO;
}

- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (!self) return nil;

    self.windowLevel = UIWindowLevelAlert + 10;   // above the app *and* its alerts, so it's always reachable
    self.backgroundColor = UIColor.clearColor;
    self.frame = [self initialFrame];

    // A window wants a root view controller; keep it inert and transparent.
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.rootViewController = root;

    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(0, 0, GBBubbleSize, GBBubbleSize)];
    bubble.backgroundColor = [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:0.92];
    bubble.layer.cornerRadius = GBBubbleSize / 2;
    bubble.layer.shadowColor = UIColor.blackColor.CGColor;
    bubble.layer.shadowOpacity = 0.35;
    bubble.layer.shadowRadius = 6;
    bubble.layer.shadowOffset = CGSizeMake(0, 3);
    bubble.layer.borderWidth = 1.5;
    bubble.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    bubble.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UILabel *glyph = [[UILabel alloc] initWithFrame:bubble.bounds];
    glyph.text = @"H";
    glyph.textColor = UIColor.whiteColor;
    glyph.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    glyph.textAlignment = NSTextAlignmentCenter;
    glyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bubble addSubview:glyph];

    [root.view addSubview:bubble];
    self.bubble = bubble;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [bubble addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [bubble addGestureRecognizer:tap];
    return self;
}

#pragma mark Placement

- (CGRect)initialFrame {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGPoint saved = [GBStore shared].floatingOrigin;
    CGPoint origin;
    if (saved.x >= 0 && saved.y >= 0) {
        origin = saved;
    } else {
        // Default: hugging the right edge, a bit above the middle — out of the way of tab bars and headers.
        origin = CGPointMake(screen.size.width - GBBubbleSize - 8, screen.size.height * 0.38);
    }
    return [self clamp:CGRectMake(origin.x, origin.y, GBBubbleSize, GBBubbleSize)];
}

- (CGRect)clamp:(CGRect)f {
    CGRect screen = UIScreen.mainScreen.bounds;
    UIEdgeInsets safe = UIEdgeInsetsZero;
    UIWindow *appWindow = [self appWindow];
    if (appWindow) safe = appWindow.safeAreaInsets;
    CGFloat minX = 4, minY = MAX(4, safe.top);
    CGFloat maxX = screen.size.width - GBBubbleSize - 4;
    CGFloat maxY = screen.size.height - GBBubbleSize - MAX(4, safe.bottom);
    f.origin.x = MIN(MAX(f.origin.x, minX), maxX);
    f.origin.y = MIN(MAX(f.origin.y, minY), maxY);
    return f;
}

- (UIWindow *)appWindow {
    UIWindow *key = nil, *fallback = nil;
    for (UIWindow *w in self.windowScene.windows) {
        if (w == self || [w isKindOfClass:GBFloatingButton.class] || w.hidden) continue;
        if (!w.rootViewController) continue;
        if (w.isKeyWindow) { key = w; break; }
        if (!fallback || w.windowLevel <= fallback.windowLevel) fallback = w;   // prefer the normal-level window
    }
    return key ?: fallback;
}

#pragma mark Gestures

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:nil];
    UIGestureRecognizerState st = g.state;
    if (st == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.dragStart = self.frame.origin;
        [UIView animateWithDuration:0.12 animations:^{ self.bubble.transform = CGAffineTransformMakeScale(1.12, 1.12); }];
    } else if (st == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(self.dragStart.x + t.x, self.dragStart.y + t.y);
        self.frame = f;   // no clamp while moving so it follows the finger; clamped on release
    } else if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled || st == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        CGRect target = [self clamp:self.frame];
        [UIView animateWithDuration:0.2 animations:^{
            self.frame = target;
            self.bubble.transform = CGAffineTransformIdentity;
        }];
        GBStore *store = [GBStore shared];
        store.floatingOrigin = target.origin;
        [store save];
    }
}

- (void)tap:(UITapGestureRecognizer *)g {
    if (self.dragging) return;
    UIWindow *w = [self appWindow];
    if (!w) return;
    [UIView animateWithDuration:0.08 animations:^{ self.bubble.transform = CGAffineTransformMakeScale(0.9, 0.9); }
                     completion:^(BOOL fin) {
        [UIView animateWithDuration:0.12 animations:^{ self.bubble.transform = CGAffineTransformIdentity; }];
    }];
    [GBMenu presentFromWindow:w];
}

@end

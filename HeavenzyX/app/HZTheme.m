#import "HZTheme.h"

#pragma mark - Palette

UIColor *HZBG(void)           { return [UIColor colorWithRed:0.043 green:0.043 blue:0.062 alpha:1.0]; }
UIColor *HZCard(void)         { return [UIColor colorWithRed:0.094 green:0.094 blue:0.130 alpha:1.0]; }
UIColor *HZCardElevated(void) { return [UIColor colorWithRed:0.150 green:0.150 blue:0.205 alpha:1.0]; }
UIColor *HZAccent(void)       { return [UIColor colorWithRed:0.560 green:0.420 blue:1.000 alpha:1.0]; }
UIColor *HZAccentDeep(void)   { return [UIColor colorWithRed:0.380 green:0.200 blue:0.860 alpha:1.0]; }
UIColor *HZTextDim(void)      { return [UIColor colorWithWhite:0.66 alpha:1.0]; }
UIColor *HZTextMuted(void)    { return [UIColor colorWithWhite:0.44 alpha:1.0]; }
UIColor *HZDanger(void)       { return [UIColor colorWithRed:1.00 green:0.36 blue:0.42 alpha:1.0]; }
UIColor *HZSuccess(void)      { return [UIColor colorWithRed:0.30 green:0.86 blue:0.55 alpha:1.0]; }
UIColor *HZHairline(void)     { return [UIColor colorWithWhite:1.0 alpha:0.07]; }

#pragma mark - Assets

UIImage *HZLogo(void) {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"HZLogo" ofType:@"png"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

// Private UIKit helper that returns the masked home-screen icon for any installed bundle id.
@interface UIImage (HZPrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

static UIImage *HZPlaceholderIcon(NSString *bundleId) {
    CGFloat s = 60;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    NSString *letter = bundleId.length ? [[bundleId componentsSeparatedByString:@"."].lastObject substringToIndex:1].uppercaseString : @"?";
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:13.5];
        [HZCardElevated() setFill]; [p fill];
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightBold],
                                 NSForegroundColorAttributeName: HZAccent() };
        CGSize sz = [letter sizeWithAttributes:attrs];
        [letter drawAtPoint:CGPointMake((s - sz.width) / 2, (s - sz.height) / 2) withAttributes:attrs];
    }];
}

UIImage *HZAppIcon(NSString *bundleId) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    UIImage *img = [cache objectForKey:bundleId ?: @""];
    if (img) return img;
    @try {
        if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
            img = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:2 scale:UIScreen.mainScreen.scale];
        }
    } @catch (__unused NSException *e) { img = nil; }
    if (!img) img = HZPlaceholderIcon(bundleId);
    [cache setObject:img forKey:bundleId ?: @""];
    return img;
}

#pragma mark - Chrome

void HZStyleNavigation(UINavigationController *nav) {
    UINavigationBarAppearance *a = [UINavigationBarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundColor = HZBG();
    a.shadowColor = UIColor.clearColor;
    a.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                               NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] };
    a.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                                    NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold] };
    nav.navigationBar.standardAppearance = a;
    nav.navigationBar.scrollEdgeAppearance = a;
    nav.navigationBar.compactAppearance = a;
    nav.navigationBar.tintColor = HZAccent();
    nav.navigationBar.prefersLargeTitles = YES;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

void HZStyleTable(UITableView *table) {
    table.backgroundColor = HZBG();
    table.separatorColor = HZHairline();
    table.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    table.sectionHeaderTopPadding = 18;
    table.showsVerticalScrollIndicator = NO;
}

void HZStyleHeaderFooter(UIView *view) {
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UILabel *l = ((UITableViewHeaderFooterView *)view).textLabel;
    l.textColor = HZTextMuted();
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
}

#pragma mark - Building blocks

UIView *HZPill(NSString *text, UIColor *color) {
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:@"  %@  ", text.uppercaseString];
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    l.textColor = color;
    l.backgroundColor = [color colorWithAlphaComponent:0.16];
    l.layer.cornerRadius = 10; l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [l.heightAnchor constraintEqualToConstant:20].active = YES;
    return l;
}

UIView *HZHeroHeader(CGFloat width, UIImage *image, BOOL ring, NSString *title, NSString *subtitle, UIView *pill) {
    CGFloat imgSize = ring ? 96 : 84;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, imgSize + 96 + (pill ? 28 : 0))];

    // Soft violet glow behind the image.
    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.type = kCAGradientLayerRadial;
    glow.colors = @[ (id)[HZAccent() colorWithAlphaComponent:0.28].CGColor, (id)UIColor.clearColor.CGColor ];
    glow.startPoint = CGPointMake(0.5, 0.5); glow.endPoint = CGPointMake(1, 1);
    glow.frame = CGRectMake(width / 2 - 130, imgSize / 2 - 110, 260, 260);
    [v.layer addSublayer:glow];

    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    if (!ring) {
        iv.layer.cornerRadius = imgSize * 0.225; iv.clipsToBounds = YES;
        iv.layer.borderWidth = 1; iv.layer.borderColor = HZHairline().CGColor;
    }
    UILabel *t = [UILabel new];
    t.text = title; t.textColor = UIColor.whiteColor; t.textAlignment = NSTextAlignmentCenter;
    t.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *s = [UILabel new];
    s.text = subtitle; s.textColor = HZTextDim(); s.textAlignment = NSTextAlignmentCenter; s.numberOfLines = 2;
    s.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:iv]; [v addSubview:t]; [v addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:v.topAnchor constant:4],
        [iv.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [iv.widthAnchor constraintEqualToConstant:imgSize], [iv.heightAnchor constraintEqualToConstant:imgSize],
        [t.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:16],
        [t.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
        [t.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:4],
        [s.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
        [s.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
    ]];
    if (pill) {
        [v addSubview:pill];
        [NSLayoutConstraint activateConstraints:@[
            [pill.topAnchor constraintEqualToAnchor:s.bottomAnchor constant:12],
            [pill.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        ]];
    }
    return v;
}

UIView *HZCompactHeader(CGFloat width, UIImage *image, NSString *title, UIView *pill) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 66)];

    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.backgroundColor = HZCard();
    iv.layer.cornerRadius = 11; iv.clipsToBounds = YES;
    iv.layer.borderWidth = 1; iv.layer.borderColor = HZHairline().CGColor;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *t = [UILabel new];
    t.text = title; t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    t.translatesAutoresizingMaskIntoConstraints = NO;

    [v addSubview:iv]; [v addSubview:t];
    [NSLayoutConstraint activateConstraints:@[
        [iv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20],
        [iv.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:42], [iv.heightAnchor constraintEqualToConstant:42],
        [t.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:12],
        [t.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
    ]];
    if (pill) {
        [v addSubview:pill];
        [NSLayoutConstraint activateConstraints:@[
            [pill.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-20],
            [pill.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
            [pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:t.trailingAnchor constant:12],
        ]];
    } else {
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-20].active = YES;
    }
    return v;
}

#pragma mark - Buttons

@interface HZGradientButton () { CAGradientLayer *_grad; }
@end
@implementation HZGradientButton
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbolName {
    HZGradientButton *b = [HZGradientButton buttonWithType:UIButtonTypeCustom];
    b->_grad = [CAGradientLayer layer];
    b->_grad.colors = @[ (id)HZAccent().CGColor, (id)HZAccentDeep().CGColor ];
    b->_grad.startPoint = CGPointMake(0, 0); b->_grad.endPoint = CGPointMake(1, 1);
    b->_grad.cornerRadius = 14;
    [b.layer insertSublayer:b->_grad atIndex:0];
    b.layer.shadowColor = HZAccentDeep().CGColor; b.layer.shadowOpacity = 0.45;
    b.layer.shadowRadius = 12; b.layer.shadowOffset = CGSizeMake(0, 6);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    if (symbolName) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        [b setImage:[[UIImage systemImageNamed:symbolName withConfiguration:c] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
        b.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    }
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}
- (void)layoutSubviews { [super layoutSubviews]; _grad.frame = self.bounds; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; self.alpha = h ? 0.8 : 1.0; }
@end

@implementation HZOutlineButton
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbolName color:(UIColor *)color {
    HZOutlineButton *b = [HZOutlineButton buttonWithType:UIButtonTypeCustom];
    b.layer.cornerRadius = 14; b.layer.borderWidth = 1.5;
    b.layer.borderColor = [color colorWithAlphaComponent:0.7].CGColor;
    b.backgroundColor = [color colorWithAlphaComponent:0.08];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:color forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    if (symbolName) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        [b setImage:[[UIImage systemImageNamed:symbolName withConfiguration:c] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        b.tintColor = color;
        b.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    }
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; self.alpha = h ? 0.7 : 1.0; }
@end

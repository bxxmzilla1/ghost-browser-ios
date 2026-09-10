#import <UIKit/UIKit.h>

// Palette
UIColor *HZBG(void);            // window background
UIColor *HZCard(void);          // grouped cell / card
UIColor *HZCardElevated(void);  // raised control on a card
UIColor *HZAccent(void);        // violet
UIColor *HZAccentDeep(void);    // darker violet (gradient end)
UIColor *HZTextDim(void);
UIColor *HZTextMuted(void);
UIColor *HZDanger(void);
UIColor *HZSuccess(void);
UIColor *HZHairline(void);

// Assets
UIImage *HZLogo(void);                          // Sessions X ring logo bundled as HZLogo.png
UIImage *HZAppIcon(NSString *bundleId);         // home-screen icon of an installed app (or a placeholder)

// Chrome
void HZStyleNavigation(UINavigationController *nav);
void HZStyleTable(UITableView *table);
void HZStyleHeaderFooter(UIView *view);          // call from willDisplayHeaderView / FooterView

// Building blocks
UIView *HZPill(NSString *text, UIColor *color);
/// Hero header for a table: big image (circular ring if `ring`), bold title, dim subtitle and an
/// optional trailing pill. Sized for `width`, ready for `tableHeaderView`.
UIView *HZHeroHeader(CGFloat width, UIImage *image, BOOL ring, NSString *title, NSString *subtitle, UIView *pill);

/// Full-width violet gradient call-to-action.
@interface HZGradientButton : UIButton
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbolName;
@end

/// Full-width outlined (destructive) action.
@interface HZOutlineButton : UIButton
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbolName color:(UIColor *)color;
@end

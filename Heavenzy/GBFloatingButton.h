#import <UIKit/UIKit.h>

/// Small always-on-top bubble (its own UIWindow) that opens the Heavenzy panel when tapped and can be
/// dragged anywhere on screen. Position is remembered per app.
@interface GBFloatingButton : UIWindow

/// Creates (once per scene) and shows the bubble in the given scene.
+ (void)installInScene:(UIWindowScene *)scene;

@end

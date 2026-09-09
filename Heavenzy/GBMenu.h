#import <UIKit/UIKit.h>

/// The in-app control panel (Blaze-style). Presented by a two-finger long-press on the key window.
@interface GBMenu : NSObject

/// Present the panel from the given window's top-most view controller.
+ (void)presentFromWindow:(UIWindow *)window;

@end

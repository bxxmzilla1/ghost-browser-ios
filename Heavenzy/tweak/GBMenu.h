#import <UIKit/UIKit.h>

/// The in-app control panel (Blaze-style). Presented by a two-finger long-press on the key window.
@interface GBMenu : NSObject

/// Present the panel from the given window's top-most view controller.
+ (void)presentFromWindow:(UIWindow *)window;

/// InstagramJailed-style reset: wipe this app's data, cookies, WebKit data and keychain (incl.
/// iCloud-synced items). Used by the panel's wipe button and by a control-app "Erase" request.
+ (void)clearAppData;

@end

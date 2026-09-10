#import <UIKit/UIKit.h>

/// Persistent, draggable SMS panel shown over the host app. It lives in its own full-screen window
/// but only the card intercepts touches (everything else passes through), so the app stays fully
/// usable while the panel floats on top. It appears near the bottom and is dismissed with its X.
@interface GBOverlay : UIWindow

/// Create (once per scene) and show the panel.
+ (void)installInScene:(UIWindowScene *)scene;

/// Show the panel if it was closed (used by the two-finger long-press fallback).
+ (void)toggle;

@end

#import <UIKit/UIKit.h>

/// Persistent, draggable SMS panel shown over the host app. It lives in its own full-screen window
/// but only the card intercepts touches (everything else passes through), so the app stays fully
/// usable while the panel floats on top. It appears near the bottom and is dismissed with its X.
@interface GBOverlay : UIWindow

/// Show the panel for this scene (creating it on first use). Called from the two-finger long-press;
/// the panel is never shown automatically. If it is already visible this is a no-op.
+ (void)showInScene:(UIWindowScene *)scene;

@end

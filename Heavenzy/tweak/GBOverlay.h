#import <UIKit/UIKit.h>

/// Persistent, draggable panel shown over the host app. It lives in its own full-screen window
/// but only the card intercepts touches (everything else passes through), so the app stays fully
/// usable while the panel floats on top. It appears near the bottom and is dismissed with its X.
/// Shows one function at a time — SMS number/code or the Instagram username scraper — chosen by
/// the Panel Mode switch in the Heavenzy app; the panel re-reads the mode whenever it is shown or
/// the app comes back to the foreground.
@interface GBOverlay : UIWindow

/// Show the panel for this scene (creating it on first use). Called from the two-finger long-press;
/// the panel is never shown automatically. If it is already visible this is a no-op.
+ (void)showInScene:(UIWindowScene *)scene;

@end

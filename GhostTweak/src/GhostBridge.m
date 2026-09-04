#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GhostTokenStore.h"

extern void GhostInjectCookies(void);
extern void GhostCloseApp(void);

// Must match GhostBrowser's InstagramBridge.bridgeMarker exactly.
static NSString *const kGhostBridgeMarker = @"GHOSTBRIDGE/1";
// Remember the last pasteboard change we looked at so we only read (and only trigger the iOS
// paste banner) when the clipboard actually changed since the previous foreground.
static NSString *const kGhostBridgeSeenCount = @"ghost.bridge.seenChangeCount";

static void GhostBridgePresentResult(NSString *user) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *key = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        UIViewController *root = key.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if (!root) return;

        NSString *msg = user.length
            ? [NSString stringWithFormat:@"Login for user %@ received from GhostBrowser and injected.\n\nRestart Instagram to apply it?", user]
            : @"Login received from GhostBrowser and injected.\n\nRestart Instagram to apply it?";
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GhostBrowser login imported"
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *act) { GhostCloseApp(); }]];
        [root presentViewController:a animated:YES completion:nil];
    });
}

/// Reads the general pasteboard for a GhostBrowser hand-off, gated on changeCount so we only touch
/// it (and only surface the iOS paste banner) when new content arrived. Imports the token block,
/// injects cookies, and clears the payload so it isn't re-imported on the next foreground.
/// When `force` is YES the changeCount gate is skipped (used by the manual menu action).
BOOL GhostConsumeBridgeForced(BOOL force) {
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

    NSInteger current = pb.changeCount;
    if (!force && [d objectForKey:kGhostBridgeSeenCount] &&
        [d integerForKey:kGhostBridgeSeenCount] == current) {
        return NO; // nothing new since we last looked — don't read, don't trigger the banner
    }
    [d setInteger:current forKey:kGhostBridgeSeenCount];

    if (!pb.hasStrings) return NO;
    NSString *s = pb.string;
    if (![s hasPrefix:kGhostBridgeMarker]) return NO;

    NSRange nl = [s rangeOfString:@"\n"];
    NSString *block = nl.location == NSNotFound ? @"" : [s substringFromIndex:nl.location + 1];

    GhostTokenStore *t = [GhostTokenStore shared];
    [t applyTextBlock:block];
    GhostInjectCookies();

    // Clear our payload so a later foreground doesn't re-import it, and record the new count.
    pb.string = @"";
    [d setInteger:pb.changeCount forKey:kGhostBridgeSeenCount];

    NSLog(@"[GhostTweak] Imported bridge login from GhostBrowser (user=%@)", t.igUserID ?: @"-");
    GhostBridgePresentResult(t.igUserID);
    return YES;
}

void GhostConsumeBridge(void) { GhostConsumeBridgeForced(NO); }

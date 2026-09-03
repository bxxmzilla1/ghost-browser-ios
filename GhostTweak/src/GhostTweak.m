#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GhostTokenStore.h"

extern void GhostInstallHooks(void);
extern void GhostInjectCookies(void);
extern void GhostInstallSettingsGesture(void);

static void GhostSetup(void) {
    @try {
        [[GhostTokenStore shared] reload];
        GhostInstallHooks();
        GhostInjectCookies();
        GhostInstallSettingsGesture();
        NSLog(@"[GhostTweak] Setup complete");
    } @catch (NSException *e) {
        NSLog(@"[GhostTweak] Setup failed (ignored): %@", e);
    }
}

__attribute__((constructor))
static void GhostTweakInit(void) {
    @autoreleasepool {
        NSLog(@"[GhostTweak] Loaded v1.0 — deferring setup to app launch");

        // Do NOTHING risky at load time. Wait until the app has finished launching so
        // UIKit / networking are up; if the app is already active, run on next runloop.
        __block id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            GhostSetup();
            if (token) { [[NSNotificationCenter defaultCenter] removeObserver:token]; token = nil; }
        }];

        // Re-inject cookies each time the app comes to the foreground.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            @try { GhostInjectCookies(); } @catch (NSException *e) {}
        }];

        // Fallback: if for some reason the launch notification already fired, set up shortly.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            static BOOL done = NO;
            if (!done && UIApplication.sharedApplication) { done = YES; GhostSetup(); }
        });
    }
}

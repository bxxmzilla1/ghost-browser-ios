#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GhostTokenStore.h"

extern void GhostInstallHooks(void);
extern void GhostInjectCookies(void);
extern void GhostInstallSettingsGesture(void);
extern void GhostConsumeBridge(void);

__attribute__((constructor))
static void GhostTweakInit(void) {
    @autoreleasepool {
        NSLog(@"[GhostTweak] Loading v1.0");
        [[GhostTokenStore shared] reload];
        GhostInstallHooks();
        GhostInjectCookies();

        dispatch_async(dispatch_get_main_queue(), ^{
            GhostInstallSettingsGesture();
        });

        // Pick up a login handed over from GhostBrowser shortly after launch.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ GhostConsumeBridge(); });

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(__unused NSNotification *n) {
            GhostConsumeBridge();
            GhostInjectCookies();
        }];
    }
}

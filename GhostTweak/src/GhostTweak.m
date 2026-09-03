#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GhostTokenStore.h"

extern void GhostInstallHooks(void);
extern void GhostInjectCookies(void);
extern void GhostInstallSettingsGesture(void);

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

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(__unused NSNotification *n) {
            GhostInjectCookies();
        }];
    }
}

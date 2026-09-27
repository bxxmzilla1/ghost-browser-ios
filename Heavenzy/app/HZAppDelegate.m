#import "HZAppDelegate.h"
#import "HZAppListViewController.h"
#import "HZAccountViewController.h"
#import "HZContainerSync.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZCloud.h"

@implementation HZAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Make sure we can reach the shared config directory even before touching it.
    [HZConfig grantSandboxAccess];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = HZBG();
    self.window.tintColor = HZAccent();

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged)
                                                 name:HZCloudSessionDidChangeNotification object:nil];
    [self installRootAnimated:NO];
    [self.window makeKeyAndVisible];

    if ([HZCloud shared].signedIn) {
        // Keep the tweak's account stamp current (covers upgrades from builds without the gate) and
        // make sure the account still exists; a revoked one drops us back to the sign-in screen.
        [self syncAccountStamp];
        [[HZCloud shared] validateSession:^(BOOL valid, NSError *error) {
            if (!valid && error) NSLog(@"[Heavenzy] session check: %@", error.localizedDescription);
        }];
    }
    return YES;
}

/// Signed in → the app list. Signed out → the sign-in / create-account wall; nothing else is reachable.
- (void)installRootAnimated:(BOOL)animated {
    UIViewController *root;
    if ([HZCloud shared].signedIn) {
        root = [[UINavigationController alloc] initWithRootViewController:[HZAppListViewController new]];
    } else {
        HZAccountViewController *gate = [HZAccountViewController new];
        gate.gateMode = YES;
        root = [[UINavigationController alloc] initWithRootViewController:gate];
    }
    HZStyleNavigation((UINavigationController *)root);
    if (!animated || !self.window.rootViewController) { self.window.rootViewController = root; return; }
    [UIView transitionWithView:self.window duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.window.rootViewController = root;
    } completion:nil];
}

- (void)sessionChanged {
    [self syncAccountStamp];
    [self installRootAnimated:YES];
}

/// Mirror the signed-in account id into every app's container config (or strip it on sign-out) so
/// the tweak activates only while someone is signed in.
- (void)syncAccountStamp {
    [HZConfig setCloudAccountId:[HZCloud shared].userId];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSInteger n = [HZContainerSync writePanelSettingsToAllApps];
        NSLog(@"[Heavenzy] account stamp (%@) written to %ld app container(s)", [HZCloud shared].userId ?: @"none", (long)n);
    });
}

@end

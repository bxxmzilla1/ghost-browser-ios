#import "HZAppDelegate.h"
#import "HZAppListViewController.h"
#import "HZConfig.h"

@implementation HZAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Make sure we can reach the shared config directory even before touching it.
    [HZConfig grantSandboxAccess];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    HZAppListViewController *list = [HZAppListViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.navigationBar.prefersLargeTitles = YES;
    if (@available(iOS 13.0, *)) {
        nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

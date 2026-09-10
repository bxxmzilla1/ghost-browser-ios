#import "HZAppDelegate.h"
#import "HZAppListViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"

@implementation HZAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Make sure we can reach the shared config directory even before touching it.
    [HZConfig grantSandboxAccess];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = HZBG();
    self.window.tintColor = HZAccent();

    HZAppListViewController *list = [HZAppListViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    HZStyleNavigation(nav);

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

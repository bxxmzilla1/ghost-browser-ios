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

    UINavigationController *root = [[UINavigationController alloc] initWithRootViewController:[HZAppListViewController new]];
    HZStyleNavigation(root);
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

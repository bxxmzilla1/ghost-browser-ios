#import <UIKit/UIKit.h>

/// AppData-style inspector + maintenance tools for one installed app. Pushed from the app's detail
/// screen. Shows version / size / containers, lets you rename the home-screen icon, set a badge, open
/// containers in Filza, clear caches, reset data / permissions, offload, and open the App Store page.
@interface HZAppToolsViewController : UITableViewController
- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name;
@end

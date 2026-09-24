#import <UIKit/UIKit.h>

/// Saved logins (container snapshots) for one app. Lets you snapshot the current logged-in state and
/// later restore any snapshot to get straight back into that account. The heavy lifting (files +
/// keychain) is done by the tweak the next time the app launches; this screen manages the list and
/// queues the save/restore.
@interface HZContainersViewController : UITableViewController
- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name;
@end

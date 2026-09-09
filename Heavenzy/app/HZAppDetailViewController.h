#import <UIKit/UIKit.h>

/// Per-app device modules (Ghost-style): enable, the chosen iPhone + identifiers + battery + carrier +
/// locale/timezone, a "Generate New Identity" button, and an "Erase App Data" action.
@interface HZAppDetailViewController : UITableViewController
- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name;
@end

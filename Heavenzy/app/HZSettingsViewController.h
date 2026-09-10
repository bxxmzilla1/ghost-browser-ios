#import <UIKit/UIKit.h>

/// Settings screen: SMS-verification provider (DiddySMS / GrizzlySMS) and API keys. Every change is
/// saved to the central config and mirrored into all installed apps' containers so the in-app
/// Heavenzy SMS panel can use it immediately.
@interface HZSettingsViewController : UITableViewController
@end

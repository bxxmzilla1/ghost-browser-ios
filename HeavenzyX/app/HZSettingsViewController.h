#import <UIKit/UIKit.h>

/// Settings screen: account + username-scraper options (auto scan, approved names). Every change is
/// saved to the central config and mirrored into all installed apps' containers so the in-app
/// Heavenzy panel can use it immediately.
@interface HZSettingsViewController : UITableViewController
@end

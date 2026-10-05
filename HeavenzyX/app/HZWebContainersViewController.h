#import <UIKit/UIKit.h>

/// Web Containers: turn one website into N Home Screen web apps, each with its own storage and its
/// own Heavenzy web identity (applied by the tweak inside the web-app host process).
@interface HZWebContainersViewController : UITableViewController

/// Action sheet for one container (reset identity & data / copy seed / delete), presentable from any
/// screen. `onChange` runs after the container list changed.
+ (void)presentActionsForContainer:(NSDictionary *)c from:(UIViewController *)host onChange:(void (^)(void))onChange;

/// One-line status for a container row: "instagram.com · seed 1A2B3C4D · spoofed".
+ (NSString *)statusLineForContainer:(NSDictionary *)c;

@end

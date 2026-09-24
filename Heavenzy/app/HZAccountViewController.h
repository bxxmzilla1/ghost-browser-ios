#import <UIKit/UIKit.h>

/// Settings → Account. Enter the Supabase project (URL + anon key), then sign in or create an account.
/// While signed in, every saved login is uploaded to that account and removed from the iPhone; the
/// Saved Logins screens list what's in the account and download on restore.
@interface HZAccountViewController : UITableViewController
@end

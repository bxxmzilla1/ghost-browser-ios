#import <Foundation/Foundation.h>

/// App-data reset used by the wipe-on-next-launch flow (queued from the Heavenzy control app).
@interface GBMenu : NSObject

/// InstagramJailed-style reset: wipe this app's data, cookies, WebKit data and keychain (incl.
/// iCloud-synced items) so it comes up as a fresh install.
+ (void)clearAppData;

@end

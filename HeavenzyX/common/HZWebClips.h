#import <Foundation/Foundation.h>

/// Spoofed Home Screen web-app containers. Every Home Screen web app (a full-screen web clip) already
/// gets its own cookies / cache / IndexedDB / localStorage from iOS; Heavenzy adds a per-container web
/// identity on top, injected by the tweak inside the web-app host process (com.apple.webapp).
///
/// Shared between the control app (creates / resets / deletes) and the tweak (reads, links data stores):
///   /var/mobile/Library/Preferences/Heavenzy/webclips.plist
///   { "site": <last site>, "prefix": <last name prefix>, "upload": <bool>,
///     "containers": [ { "id", "name", "url", "clipId", "seed", "upload", "createdAt",
///                       "wipePending"?, "stores": [ <website data store key>, … ] }, … ] }
///
/// Each icon's URL carries "#hzc=<id>" so the tweak can tell which container a web view belongs to on
/// its first load; it strips the tag before the page sees it and remembers the web view's data store
/// so later launches are recognised even when the tag is gone.
@interface HZWebClips : NSObject

+ (NSString *)plistPath;
+ (NSString *)webClipsDirectory;   // /var/mobile/Library/WebClips

+ (NSArray<NSDictionary *> *)containers;
+ (NSDictionary *)containerWithId:(NSString *)cid;
+ (NSDictionary *)containerForStoreKey:(NSString *)key;
/// Newer iOS registers every Home Screen web app as its own application whose bundle identifier ends
/// with the web clip's identifier ("com.apple.WebKit.…<clipId>"). nil when `bundleId` isn't one of ours.
+ (NSDictionary *)containerForBundleId:(NSString *)bundleId;

+ (NSString *)lastSite;
+ (NSString *)lastPrefix;
+ (BOOL)uploadSpoofDefault;
+ (void)setUploadSpoofDefault:(BOOL)on;

#pragma mark URL tag

+ (NSString *)containerIdInURL:(NSURL *)url;
+ (NSURL *)URLByRemovingTag:(NSURL *)url;

#pragma mark Tweak side

+ (void)linkStoreKey:(NSString *)key toContainer:(NSString *)cid;
+ (void)clearWipePendingForContainer:(NSString *)cid;

#pragma mark Control app side

/// "instagram.com" → "https://instagram.com/". nil when it isn't an http(s) URL with a host.
+ (NSString *)normalizedSite:(NSString *)input;

/// Creates `count` containers for `site`, each with its own web clip bundle on disk (icon from
/// `iconForNumber`). Numbering continues after the containers that already exist for that site.
/// Returns the created entries. The Home Screen shows them after a respring.
+ (NSArray<NSDictionary *> *)createContainers:(NSInteger)count site:(NSString *)site prefix:(NSString *)prefix
                                       upload:(BOOL)upload iconForNumber:(NSData *(^)(NSInteger number))iconForNumber;

/// New fingerprint seed + wipe the container's website data the next time its icon is opened.
+ (void)resetContainer:(NSString *)cid;
/// Deletes the container's web clip bundle and its entry.
+ (void)removeContainer:(NSString *)cid;

+ (BOOL)iconExistsForContainer:(NSDictionary *)c;
/// Path of the container's Home Screen icon (icon.png inside its web clip bundle), nil if gone.
+ (NSString *)iconPathForContainer:(NSDictionary *)c;
+ (NSString *)seedLabel:(NSDictionary *)c;

@end

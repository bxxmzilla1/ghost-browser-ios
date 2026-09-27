#import <Foundation/Foundation.h>

/// Reads the logged-in Instagram web session (sessionid + ds_user_id + csrftoken, plus mid / ig_did
/// when present) straight out of the host app's cookie jars. Only meaningful inside the Instagram app.
@interface GBSession : NSObject

/// Collect Instagram cookies from both NSHTTPCookieStorage (native networking) and the default
/// WKWebsiteDataStore (embedded web views), merged. Completion runs on the main queue.
+ (void)collectInstagramSession:(void (^)(NSDictionary<NSString *, NSString *> *cookies))completion;

/// A ready-to-paste Cookie header, e.g. "sessionid=…; ds_user_id=…; csrftoken=…" (empty if no session).
+ (NSString *)cookieStringFrom:(NSDictionary<NSString *, NSString *> *)cookies;

@end

#import <Foundation/Foundation.h>

/// Minimal on-device client for the Bundle.social REST API (base https://api.bundle.social, auth via
/// the `x-api-key` header). Used by the in-app Instagram button to create a hosted connect portal.
@interface GBBundleSocial : NSObject

/// Create an Instagram connect-portal link for the given org API key. When `team` is nil/empty the
/// team id is resolved from the organization automatically. The completion runs on the main queue
/// with either a portal `url` or a human-readable `error` (never both).
+ (void)instagramPortalWithKey:(NSString *)key
                          team:(NSString *)team
                    completion:(void (^)(NSURL *url, NSString *error))completion;

@end

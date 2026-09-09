#import <Foundation/Foundation.h>

/// Reads the host Instagram app's saved auth headers (the way the "InstagramJailed" tweak does) and
/// formats them as a token blob you can paste elsewhere:
///   Authorization=…; IG-U-DS-USER-ID=…; X-MID=…; X-IG-WWW-Claim=…;
/// One line per logged-in account. Returns nil when nothing is stored (logged out).
@interface GBTokens : NSObject
+ (NSString *)instagramTokenBlob;
@end

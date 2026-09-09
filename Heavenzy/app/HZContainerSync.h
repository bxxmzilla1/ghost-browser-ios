#import <Foundation/Foundation.h>

/// Writes a target app's Heavenzy config straight into that app's own data container
/// (…/Library/Preferences/com.heavenzy.plist), in the key schema the tweak's GBStore reads. Because
/// the Heavenzy control app runs unsandboxed (platform-application), it can reach other containers —
/// so we don't need libSandy or a central store for the tweak to pick up settings.
@interface HZContainerSync : NSObject

/// Mirror enabled + identity (+ optional erase request) into the app's container. Returns NO if the
/// container can't be located (e.g. the app has never been launched yet). The current global
/// Bundle.social key/team (from HZConfig) is mirrored in too.
+ (BOOL)writeForApp:(NSString *)bundleId
           identity:(NSDictionary *)identity
            enabled:(BOOL)enabled
        wipePending:(BOOL)wipePending;

/// Push the Bundle.social key/team into *every* installed user app's container (merging, without
/// touching identity/enabled), so the in-app button can reach it even in apps that aren't spoofed.
/// Returns how many containers were updated.
+ (NSInteger)writeBundleKey:(NSString *)key team:(NSString *)team;

@end

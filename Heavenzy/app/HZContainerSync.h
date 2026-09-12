#import <Foundation/Foundation.h>

/// Writes a target app's Heavenzy config straight into that app's own data container
/// (…/Library/Preferences/com.heavenzy.plist), in the key schema the tweak's GBStore reads. Because
/// the Heavenzy control app runs unsandboxed (platform-application), it can reach other containers —
/// so we don't need libSandy or a central store for the tweak to pick up settings.
@interface HZContainerSync : NSObject

/// Mirror enabled + identity (+ optional erase request) into the app's container. Returns NO if the
/// container can't be located (e.g. the app has never been launched yet). The current global SMS
/// settings (from HZConfig) are mirrored in too.
+ (BOOL)writeForApp:(NSString *)bundleId
           identity:(NSDictionary *)identity
            enabled:(BOOL)enabled
        wipePending:(BOOL)wipePending;

/// Push the current SMS settings (from HZConfig) into *every* installed user app's container, so the
/// in-app SMS panel can reach them even in apps that aren't spoofed. Returns how many were updated.
+ (NSInteger)writeSmsSettingsToAllApps;

/// Mark a clone's container so the Heavenzy tweak stays inert inside it. NO until the app has a
/// data container (call right after install; retry briefly).
+ (BOOL)markTweakFreeForApp:(NSString *)bundleId;

/// TRUE if an erase is still queued in the app's own container. The tweak clears this flag from the
/// container the moment it performs the wipe, so this reflects the real, post-launch state (unlike
/// the central HZConfig copy, which the sandboxed tweak can't reach without libSandy).
+ (BOOL)wipePendingForApp:(NSString *)bundleId;

@end

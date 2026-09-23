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

/// TRUE if an erase is still queued in the app's own container. The tweak clears this flag from the
/// container the moment it performs the wipe, so this reflects the real, post-launch state (unlike
/// the central HZConfig copy, which the sandboxed tweak can't reach without libSandy).
+ (BOOL)wipePendingForApp:(NSString *)bundleId;

/// Queue a container-snapshot save or restore in the app's own container (the reliable channel the
/// sandboxed tweak reads on next launch). Pass exactly one name; the other must be nil. Passing both
/// nil clears any queued op. Returns NO if the container can't be located.
+ (BOOL)queueSnapshotSave:(NSString *)saveName load:(NSString *)loadName forApp:(NSString *)bundleId;

/// The real, post-launch snapshot state from the app's own container (the tweak clears the flags
/// there the moment it runs, even when libSandy is unavailable). Keys: snapSave, snapLoad,
/// snapLastError (all optional NSStrings). Empty dict if the app has no container yet.
+ (NSDictionary *)snapshotStateForApp:(NSString *)bundleId;

@end

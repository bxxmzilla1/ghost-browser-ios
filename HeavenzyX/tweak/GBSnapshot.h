#import <Foundation/Foundation.h>

/// Save / restore a complete logged-in state for the host app, from *inside* that app (the only
/// process that can read its keychain). A snapshot captures the three things an app login actually
/// lives in — the data container files, the shared app-group containers, and the keychain items —
/// plus the Heavenzy device identity that was active, so restoring puts the account back on the same
/// spoofed device it was created on.
///
/// Snapshots are stored outside the app's own container (under HZConfig's Containers dir, reachable
/// via the bundled libSandy profile) so a data wipe never deletes them.
@interface GBSnapshot : NSObject

/// Capture the current logged-in state into a snapshot folder named `name`. Overwrites a snapshot of
/// the same name. Returns nil on success, or a short human-readable reason on failure (e.g. the
/// store dir is unreachable because libSandy isn't working).
+ (NSString *)saveSnapshotNamed:(NSString *)name;

/// Restore a snapshot: wipe the current state, copy the snapshot's files + group containers back,
/// re-import its keychain items, and return the saved identity dict (so the caller can re-apply it to
/// GBStore). On failure returns nil and sets *error to a short reason; nothing is wiped in that case.
+ (NSDictionary *)loadSnapshotNamed:(NSString *)name error:(NSString **)error;

@end

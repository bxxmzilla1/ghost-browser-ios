#import <Foundation/Foundation.h>

/// Central per-app configuration shared between the Heavenzy control app and the tweak, the way
/// Ghost keeps its settings in /var/mobile/Library/Preferences/Ghost. Stored at:
///   /var/mobile/Library/Preferences/Heavenzy/apps.plist
///   { "<bundleId>": { "enabled": <bool>, "identity": { …HZGenerateIdentity… } }, … }
///
/// The control app (a platform application) reads/writes it directly. The tweak, sandboxed inside a
/// target app, gains read access through the bundled libSandy profile.
@interface HZConfig : NSObject

/// The directory + file paths (created on demand).
+ (NSString *)directory;
+ (NSString *)appsPlistPath;

/// libSandy: grant this (sandboxed) process access to the central directory. No-op / harmless when
/// libSandy is missing or already granted. Call once early in the tweak.
+ (void)grantSandboxAccess;

/// Whole config, or a single app's entry ({ enabled, identity }).
+ (NSDictionary *)all;
+ (NSDictionary *)entryForApp:(NSString *)bundleId;
+ (BOOL)isEnabledForApp:(NSString *)bundleId;
+ (NSDictionary *)identityForApp:(NSString *)bundleId;

/// Mutations (control app side).
+ (void)setEnabled:(BOOL)enabled forApp:(NSString *)bundleId;
+ (void)setIdentity:(NSDictionary *)identity forApp:(NSString *)bundleId;
+ (void)removeApp:(NSString *)bundleId;

/// Erase-on-next-launch flag. The control app can't reach another app's sandbox directly, so it
/// sets this; the tweak performs the InstagramJailed-style keychain + app-data reset when that app
/// next launches, then clears it.
+ (BOOL)wipePendingForApp:(NSString *)bundleId;
+ (void)setWipePending:(BOOL)pending forApp:(NSString *)bundleId;

/// Global SMS-verification settings (provider + API keys), shared by every app. Stored once (not
/// per-bundle) and mirrored into each app container so the in-app SMS panel can reach them.
+ (NSString *)smsProvider;   // "diddy" | "grizzly"
+ (void)setSmsProvider:(NSString *)provider;
+ (NSString *)diddyKey;
+ (void)setDiddyKey:(NSString *)key;
+ (NSString *)grizzlyKey;
+ (void)setGrizzlyKey:(NSString *)key;
+ (NSString *)grizzlyMaxPrice;
+ (void)setGrizzlyMaxPrice:(NSString *)price;
/// GrizzlySMS US pool: "usa" (real carrier numbers, country 187) or "virtual" (USA virtual, country 12).
+ (NSString *)grizzlyCountry;
+ (void)setGrizzlyCountry:(NSString *)country;

/// What the in-app panel shows: "sms" (number + code) or "scraper" (Instagram username scanner).
+ (NSString *)panelMode;
+ (void)setPanelMode:(NSString *)mode;

/// Approved first-names list for the scraper, as the user typed it (one name per line). Empty = no filter.
+ (NSString *)approvedNames;
+ (void)setApprovedNames:(NSString *)names;

/// Auto-scan: when on, the scraper panel taps Scan once a second so the user only has to scroll.
+ (BOOL)autoScan;
+ (void)setAutoScan:(BOOL)on;

#pragma mark - SpringBoard overrides (AppData-style icon renames + badge counts)

/// These live in a separate file (springboard.plist) that SpringBoard reads directly, and are applied
/// by the tweak's SpringBoard hooks. Changing one posts a Darwin notification so SpringBoard reloads.
///   /var/mobile/Library/Preferences/Heavenzy/springboard.plist
///   { "names": { "<bundleId>": "<custom name>" }, "badges": { "<bundleId>": <int> } }
+ (NSString *)springboardPlistPath;

/// Custom home-screen name for an app. nil / empty removes the override (real name shows again).
+ (NSString *)customNameForApp:(NSString *)bundleId;
+ (void)setCustomName:(NSString *)name forApp:(NSString *)bundleId;
+ (NSDictionary<NSString *, NSString *> *)allCustomNames;

/// Badge override for an app. nil = no override (leave the app's own badge alone). @0 clears the badge.
+ (NSNumber *)badgeForApp:(NSString *)bundleId;
+ (void)setBadge:(NSNumber *)badge forApp:(NSString *)bundleId;
+ (NSDictionary<NSString *, NSNumber *> *)allBadges;

/// Tell the SpringBoard side (tweak) to re-read springboard.plist and re-apply names + badges.
+ (void)notifySpringBoard;

#pragma mark - Container snapshots (save / restore a logged-in state)

/// Saved app states live outside every app's own container (so a wipe can't delete them):
///   /var/mobile/Library/Preferences/Heavenzy/Containers/<bundleId>/<snapshot>/
///     data/      → the app's Library (minus Caches) + Documents
///     groups/    → each shared app-group container (minus Caches)
///     keychain.plist  → the app's keychain items (the part a plain folder-copy misses)
///     identity.plist  → the Heavenzy device identity active when it was saved
///     meta.plist      → { name, date, appShortVersion, appBuild, schema }
/// The control app manages the list here; the tweak does the in-app save/restore (files + keychain).
+ (NSString *)containersRoot;                          // …/Heavenzy/Containers
+ (NSString *)snapshotsDirForApp:(NSString *)bundleId; // …/Containers/<bundleId>

/// Metadata for every saved snapshot of an app, newest first. Each entry:
///   { name, path, date (NSDate|nil), version, build, bytes (NSNumber) }
+ (NSArray<NSDictionary *> *)snapshotsForApp:(NSString *)bundleId;
+ (BOOL)deleteSnapshotNamed:(NSString *)name forApp:(NSString *)bundleId;
+ (BOOL)renameSnapshotNamed:(NSString *)name to:(NSString *)newName forApp:(NSString *)bundleId;
/// A filesystem-safe folder name for a user-typed snapshot title.
+ (NSString *)sanitizeSnapshotName:(NSString *)name;

/// Queue a save/restore for the next launch of the app (the tweak performs it, then clears the flag).
/// Only one op can be pending at a time; queuing one clears the other. Pass nil to clear.
+ (NSString *)snapshotSavePendingForApp:(NSString *)bundleId;
+ (void)setSnapshotSavePending:(NSString *)name forApp:(NSString *)bundleId;
+ (NSString *)snapshotLoadPendingForApp:(NSString *)bundleId;
+ (void)setSnapshotLoadPending:(NSString *)name forApp:(NSString *)bundleId;

@end

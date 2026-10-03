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
/// Whether grantSandboxAccess actually succeeded in this process (libSandy present + profile applied).
+ (BOOL)sandboxAccessGranted;
+ (NSString *)sandboxAccessDescription;   // human-readable reason when not granted

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

/// Global panel settings, shared by every app. Stored once (not per-bundle) and mirrored into each
/// app container so the in-app panel can reach them.
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

@end

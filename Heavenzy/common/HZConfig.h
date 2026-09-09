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

/// Global Bundle.social credentials (org-level API key + optional team id), shared by every app.
/// Stored once (not per-bundle) and mirrored into each app container so the in-app button can reach
/// it. Team id is optional — the tweak resolves it from the organization when left blank.
+ (NSString *)bundleKey;
+ (void)setBundleKey:(NSString *)key;
+ (NSString *)bundleTeam;
+ (void)setBundleTeam:(NSString *)team;

@end

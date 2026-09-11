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

/// What the in-app panel shows: "sms" (number + code) or "scraper" (Instagram username scanner).
+ (NSString *)panelMode;
+ (void)setPanelMode:(NSString *)mode;

@end

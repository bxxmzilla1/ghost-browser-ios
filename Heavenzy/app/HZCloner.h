#import <Foundation/Foundation.h>

/// A decrypted IPA that has been extracted and inspected, ready to be cloned.
@interface HZCloneSource : NSObject
@property (nonatomic, copy) NSString *workDir;     // extraction root (contains Payload/)
@property (nonatomic, copy) NSString *appDir;      // …/Payload/<Name>.app
@property (nonatomic, copy) NSString *name;        // CFBundleDisplayName ?: CFBundleName
@property (nonatomic, copy) NSString *bundleId;    // CFBundleIdentifier
@property (nonatomic, copy) NSString *version;     // CFBundleShortVersionString
@property (nonatomic, copy) NSString *executable;  // CFBundleExecutable
@property (nonatomic, assign) BOOL encrypted;      // main binary still FairPlay-encrypted (can't clone)
@property (nonatomic, assign) BOOL hasExtensions;  // PlugIns/ or Watch/ present
@end

/// On-device IPA cloner (ModMyIPA's idea, done natively): unzip → rewrite Info.plist (new bundle id +
/// name) → strip extensions/iTunes metadata → re-sign the main binary with per-clone entitlements
/// (unique application-identifier, keychain groups and app groups, no iCloud) → zip → install via
/// LSApplicationWorkspace (AppSync Unified) → enable Heavenzy spoofing for the new bundle id.
///
/// Needs the Procursus `unzip`, `zip` and `ldid` packages (declared as dependencies) and, for the
/// one-tap install, AppSync Unified. Without AppSync the finished .ipa is kept in
/// /var/mobile/Documents/Heavenzy so it can be handed to TrollStore / Filza instead.
@interface HZCloner : NSObject

/// nil when unzip, zip and ldid are all available; otherwise a human-readable list of what's missing.
+ (NSString *)missingTools;

/// Extract + inspect an IPA on a background queue. Completion runs on the main queue.
+ (void)inspectIPA:(NSURL *)ipaURL completion:(void (^)(HZCloneSource *source, NSString *error))completion;

/// Next free "<bundleId>2", "<bundleId>3", … that is not installed.
+ (NSString *)suggestedBundleIdFor:(NSString *)bundleId;
+ (BOOL)isAppInstalled:(NSString *)bundleId;

/// Build the clone .ipa. `progress` and `completion` run on the main queue; completion gives the
/// finished .ipa path (kept under /var/mobile/Documents/Heavenzy) or an error.
+ (void)buildClone:(HZCloneSource *)source
          bundleId:(NSString *)newBundleId
       displayName:(NSString *)newName
  removeExtensions:(BOOL)removeExtensions
          progress:(void (^)(NSString *step))progress
        completion:(void (^)(NSString *ipaPath, NSString *error))completion;

/// Install an .ipa through LSApplicationWorkspace (requires AppSync Unified). Main-queue completion.
+ (void)installIPA:(NSString *)ipaPath bundleId:(NSString *)bundleId completion:(void (^)(BOOL ok, NSString *error))completion;

/// Make the clone completely tweak-free: configures Choicy to block all tweak injection for this
/// bundle id (so no dylib is even mapped) and, as a fallback, flags the clone's own container so the
/// Heavenzy tweak stays inert. Retries the container write briefly while installd creates it.
+ (void)disableTweaksForApp:(NSString *)bundleId;

/// Whether Choicy / AppSync Unified are present (used for guidance in the UI).
+ (BOOL)isChoicyInstalled;
+ (BOOL)isAppSyncInstalled;

/// Remove a source's extraction directory.
+ (void)cleanup:(HZCloneSource *)source;

@end

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Per-account tokens in the "Key: value" block format (Blaze / account-tool compatible).
@interface GhostTokenStore : NSObject

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *androidID;
@property (nonatomic, copy) NSString *deviceID;
@property (nonatomic, copy) NSString *idfv;
@property (nonatomic, copy) NSString *idfa;
@property (nonatomic, copy) NSString *authorization;
@property (nonatomic, copy) NSString *igUserID;
@property (nonatomic, copy) NSString *igIntendedUserID;
@property (nonatomic, copy) NSString *xMID;
@property (nonatomic, copy) NSString *xIGWWWClaim;
@property (nonatomic, copy) NSString *sessionid;
@property (nonatomic, copy) NSString *csrftoken;
@property (nonatomic, copy) NSString *rur;

// Spoofed device identity (what Instagram sees as the hardware).
@property (nonatomic, copy) NSString *deviceModel;      // hw.machine, e.g. "iPhone16,1"
@property (nonatomic, copy) NSString *deviceModelName;  // marketing, e.g. "iPhone 15 Pro"
@property (nonatomic, copy) NSString *deviceName;       // [UIDevice name], e.g. "iPhone"
@property (nonatomic, copy) NSString *systemVersion;    // e.g. "18.5"

@property (nonatomic, assign) BOOL injectHeaders;
@property (nonatomic, assign) BOOL injectCookies;
@property (nonatomic, copy) NSString *proxyHost;
@property (nonatomic, assign) NSInteger proxyPort;
@property (nonatomic, copy) NSString *proxyUser;
@property (nonatomic, copy) NSString *proxyPass;

+ (instancetype)shared;

- (void)reload;
- (void)save;
- (BOOL)isEmpty;

/// Parse "Key: value" lines; "No data available" clears a field.
- (void)applyTextBlock:(NSString *)block;

/// Export in the standard block format.
- (NSString *)textBlock;

/// Header name -> value for non-empty header tokens.
- (NSDictionary<NSString *, NSString *> *)requestHeaders;

/// Rebuild mobile Authorization from sessionid + ds_user_id when missing.
- (NSString *)effectiveAuthorization;

- (void)fillMissingGeneratedIDs;

/// True once a spoofed hardware identity has been chosen.
- (BOOL)hasDeviceProfile;
/// Pick a brand-new random iPhone (model + iOS) and fresh IDFV/IDFA/androidID/ig_did/MID.
/// This is the "new device" the app will report after the next launch.
- (void)regenerateDeviceProfile;
/// Short human label for the current spoofed device, e.g. "iPhone 15 Pro · iOS 18.5".
- (NSString *)deviceSummary;

- (NSString *)generateAndroidID;
- (NSString *)generateUUIDUpper;
- (NSString *)generateUUIDLower;
- (NSString *)generateXMID;

@end

NS_ASSUME_NONNULL_END

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
- (NSString *)generateAndroidID;
- (NSString *)generateUUIDUpper;
- (NSString *)generateUUIDLower;
- (NSString *)generateXMID;

@end

NS_ASSUME_NONNULL_END

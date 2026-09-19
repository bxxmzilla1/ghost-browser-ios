#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// AppData-style inspector for a single installed app, resolved from the Heavenzy control app (a
/// platform application). Mirrors the useful parts of FouadRaheb/AppData without hooking SpringBoard:
/// everything here runs in-process using LSApplicationProxy (via LSApplicationWorkspace, resolved at
/// runtime) plus direct file access to the app's containers, which the control app already has.
///
/// Icon-name and badge overrides are the two SpringBoard-only features — those are stored in
/// HZConfig's springboard.plist and applied by the tweak's SpringBoard hooks, not here.
@interface HZAppData : NSObject

+ (instancetype)dataForBundleId:(NSString *)bundleId;

@property (nonatomic, copy, readonly) NSString *bundleId;

// Metadata (best-effort; "N/A" / nil when the proxy doesn't expose it).
@property (nonatomic, copy, readonly) NSString *shortVersion;     // CFBundleShortVersionString
@property (nonatomic, copy, readonly) NSString *buildVersion;     // CFBundleVersion
@property (nonatomic, copy, readonly) NSString *minimumOSVersion;
@property (nonatomic, copy, readonly) NSString *diskUsageString;  // static (bundle) size, formatted
@property (nonatomic, copy, readonly) NSNumber *appStoreItemID;   // iTunes item id, or nil
@property (nonatomic, copy, readonly) NSArray<NSString *> *urlSchemes;

@property (nonatomic, strong, readonly) NSURL *bundleURL;
@property (nonatomic, strong, readonly) NSURL *dataContainerURL;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSURL *> *groupContainerURLs;

// Async folder sizing (formatted with NSByteCountFormatter, delivered on the main thread).
- (void)cacheSize:(void (^)(NSString *formatted))completion;   // Library/Caches + tmp
- (void)dataSize:(void (^)(NSString *formatted))completion;    // Library + tmp + Documents

// Destructive maintenance (all run off-main, completion on main). `ok` reports whether it did work.
- (void)clearCache:(void (^)(BOOL ok))completion;
- (void)resetData:(void (^)(BOOL ok))completion;               // wipes Library/tmp/Documents contents
- (void)resetPermissions:(void (^)(BOOL ok))completion;        // TCC reset (best-effort)
- (void)offload:(void (^)(BOOL ok))completion;                 // demote to placeholder (best-effort)

// Navigation.
- (BOOL)openInAppStore;
- (BOOL)openContainerInFilza:(NSURL *)container;   // filza://view/<path>

@end

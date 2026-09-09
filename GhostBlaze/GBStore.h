#import <Foundation/Foundation.h>

/// Per-app spoofed device identity. Persisted inside the *host app's own* container
/// (Library/Preferences/com.ghost.blaze.plist) so it is stable across normal relaunches and
/// disappears on a full data wipe — at which point "wipe + re-spoof" writes a fresh one.
@interface GBStore : NSObject

@property (class, nonatomic, readonly) GBStore *shared;

/// Master gate for this process: the tweak only spoofs when the host app is opted in.
@property (nonatomic, assign) BOOL enabled;

// Spoofed hardware the app sees.
@property (nonatomic, copy) NSString *deviceModel;     // hw.machine, e.g. "iPhone16,1"
@property (nonatomic, copy) NSString *marketingName;   // e.g. "iPhone 15 Pro"
@property (nonatomic, copy) NSString *systemVersion;   // e.g. "18.5"
@property (nonatomic, copy) NSString *deviceName;      // [UIDevice name]

// Spoofed identifiers.
@property (nonatomic, copy) NSString *idfv;            // identifierForVendor (UPPERCASE UUID)
@property (nonatomic, copy) NSString *idfa;            // advertisingIdentifier (UPPERCASE UUID)

/// Proxy the app's traffic is routed through. Part of the pinned identity — kept across a
/// data wipe + re-spoof so the fresh install comes up already behind the same proxy.
@property (nonatomic, copy) NSString *proxyLink;       // raw, as pasted (empty = direct)
@property (nonatomic, readonly) BOOL hasProxy;
@property (nonatomic, readonly) NSString *proxySummary; // "socks5 host:port (auth)" / "Direct"

/// Store a proxy link (any of: socks5://user:pass@host:port · http://host:port · host:port:user:pass).
/// Empty string clears it. Returns NO if the text is non-empty but unparseable.
- (BOOL)setProxyFromLink:(NSString *)link;

/// connectionProxyDictionary / CFNetwork system-proxy form for the stored proxy (nil if none).
- (NSDictionary *)proxyDictionary;

/// Seed the shared credential storage with the proxy's user/pass for its protection space, so
/// CFNetwork answers the proxy's 407 auth challenge automatically instead of prompting in Settings.
- (void)installProxyCredential;

/// YES once a device identity has been chosen.
@property (nonatomic, readonly) BOOL hasIdentity;

/// Short label, e.g. "iPhone 15 Pro · iOS 18.5".
@property (nonatomic, readonly) NSString *summary;

/// Load prefs from the host app container.
- (void)reload;
/// Persist current values.
- (void)save;

/// Roll a brand-new random iPhone (model + iOS) and fresh IDFV/IDFA. Saves.
- (void)regenerateIdentity;

@end

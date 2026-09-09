#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Per-app spoofed device identity. Persisted inside the *host app's own* container
/// (Library/Preferences/com.heavenzy.plist) so it is stable across normal relaunches and
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

// Bundle.social (Settings). Survives "wipe + re-spoof" because the store is re-saved after the wipe.
@property (nonatomic, copy) NSString *bundleAPIKey;     // x-api-key
@property (nonatomic, copy) NSString *bundleTeamId;     // optional; empty = first team in the organization

// Floating button position (points, top-left of the 44pt bubble). Negative = not set yet.
@property (nonatomic, assign) CGPoint floatingOrigin;

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

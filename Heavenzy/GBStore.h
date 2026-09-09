#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Per-app spoofed device identity, modelled after Sessions X: every attribute (screen, scale,
/// CPU cores, memory) is bound to the chosen device so nothing contradicts the model string.
/// Persisted inside the *host app's own* container (Library/Preferences/com.heavenzy.plist) so it is
/// stable across normal relaunches and disappears on a full data wipe — at which point
/// "wipe + re-spoof" writes a fresh one.
@interface GBStore : NSObject

@property (class, nonatomic, readonly) GBStore *shared;

/// Master gate for this process: the tweak only spoofs when the host app is opted in.
@property (nonatomic, assign) BOOL enabled;

// Spoofed hardware the app sees (all mutually consistent, picked together from the device pool).
@property (nonatomic, copy) NSString *deviceModel;     // hw.machine, e.g. "iPhone16,1"
@property (nonatomic, copy) NSString *marketingName;   // e.g. "iPhone 15 Pro"
@property (nonatomic, copy) NSString *systemVersion;   // e.g. "18.6.1"
@property (nonatomic, copy) NSString *deviceName;      // [UIDevice name]
@property (nonatomic, assign) NSInteger screenPointsW; // logical points (portrait)
@property (nonatomic, assign) NSInteger screenPointsH;
@property (nonatomic, assign) NSInteger scaleFactor;   // 2 or 3
@property (nonatomic, assign) NSInteger cpuCores;      // hw.ncpu / processorCount
@property (nonatomic, assign) NSInteger memoryGB;      // physical RAM in GB

// Spoofed identifiers.
@property (nonatomic, copy) NSString *idfv;            // identifierForVendor (UPPERCASE UUID)
@property (nonatomic, copy) NSString *idfa;            // advertisingIdentifier (UPPERCASE UUID)

// Floating button position (points, top-left of the 44pt bubble). Negative = not set yet.
@property (nonatomic, assign) CGPoint floatingOrigin;

/// Native pixel dimensions (points * scale) — what UIScreen.nativeBounds should report.
@property (nonatomic, readonly) NSInteger nativePixelsW;
@property (nonatomic, readonly) NSInteger nativePixelsH;
/// Physical memory in bytes (memoryGB * 1024^3) — what hw.memsize / physicalMemory should report.
@property (nonatomic, readonly) unsigned long long memoryBytes;

/// YES once a device identity has been chosen.
@property (nonatomic, readonly) BOOL hasIdentity;

/// Short label, e.g. "iPhone 15 Pro · iOS 18.6.1".
@property (nonatomic, readonly) NSString *summary;

/// Load prefs from the host app container.
- (void)reload;
/// Persist current values.
- (void)save;

/// Roll a brand-new random iPhone (model + iOS + screen + cores + memory) and fresh IDFV/IDFA. Saves.
- (void)regenerateIdentity;

@end

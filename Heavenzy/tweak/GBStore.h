#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Per-app device *identity* (Blaze-style): the real iPhone is kept, but the identifiers apps use to
/// recognise a device / a returning install are reset so the app sees a brand-new phone.
/// Persisted inside the *host app's own* container (Library/Preferences/com.heavenzy.plist) so it is
/// stable across normal relaunches and disappears on a full data wipe — at which point
/// "wipe + re-spoof" writes a fresh one.
@interface GBStore : NSObject

@property (class, nonatomic, readonly) GBStore *shared;

/// Master gate for this process: the tweak only spoofs when the host app is opted in.
@property (nonatomic, assign) BOOL enabled;

/// Erase-on-next-launch flag written into this app's container by the Heavenzy control app. The
/// tweak performs the data wipe on launch, then clears it.
@property (nonatomic, assign) BOOL wipePending;

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

// Reset identifiers — the only things Heavenzy changes (the real hardware above is left alone).
@property (nonatomic, copy) NSString *idfv;            // identifierForVendor (UPPERCASE UUID)
@property (nonatomic, copy) NSString *idfa;            // advertisingIdentifier (UPPERCASE UUID)
@property (nonatomic, copy) NSString *udid;            // MobileGestalt UniqueDeviceID
@property (nonatomic, copy) NSString *serialNumber;    // MobileGestalt SerialNumber
@property (nonatomic, copy) NSString *wifiAddress;     // MobileGestalt WifiAddress (lowercase MAC)
@property (nonatomic, copy) NSString *bluetoothAddress;// MobileGestalt BluetoothAddress (lowercase MAC)
@property (nonatomic, copy) NSString *imei;            // MobileGestalt InternationalMobileEquipmentIdentity

// Extended device signals (Ghost-style), each consistent with the chosen identity / region.
@property (nonatomic, assign) double  batteryLevel;    // 0.0–1.0
@property (nonatomic, assign) BOOL    batteryCharging; // charging vs unplugged
@property (nonatomic, copy) NSString *carrierName;     // e.g. "AT&T"
@property (nonatomic, copy) NSString *mcc;             // mobile country code, e.g. "310"
@property (nonatomic, copy) NSString *mnc;             // mobile network code, e.g. "410"
@property (nonatomic, copy) NSString *isoCountryCode;  // e.g. "us"
@property (nonatomic, copy) NSString *timeZoneName;    // IANA, e.g. "America/New_York"
@property (nonatomic, copy) NSString *localeId;        // e.g. "en_US" (NSLocale)

// Saved SMS-panel position (top-left of the card, points). Negative = not set yet.
@property (nonatomic, assign) CGPoint floatingOrigin;

// SMS provider settings mirrored in by the control app (used by the in-app SMS panel).
@property (nonatomic, copy) NSString *smsProvider;      // "diddy" | "grizzly"
@property (nonatomic, copy) NSString *diddyKey;
@property (nonatomic, copy) NSString *grizzlyKey;
@property (nonatomic, copy) NSString *grizzlyMaxPrice;

/// Native pixel dimensions (points * scale) — what UIScreen.nativeBounds should report.
@property (nonatomic, readonly) NSInteger nativePixelsW;
@property (nonatomic, readonly) NSInteger nativePixelsH;
/// Physical memory in bytes (memoryGB * 1024^3) — what hw.memsize / physicalMemory should report.
@property (nonatomic, readonly) unsigned long long memoryBytes;

/// YES once a fresh identity has been generated.
@property (nonatomic, readonly) BOOL hasIdentity;

/// Short label, e.g. "New identity · SN F2LX…".
@property (nonatomic, readonly) NSString *summary;

/// Load prefs from the host app container.
- (void)reload;
/// Persist current values.
- (void)save;

/// Roll a brand-new identity (fresh IDFV/IDFA/UDID/serial/MACs/IMEI). Real hardware is untouched. Saves.
- (void)regenerateIdentity;

/// Apply an identity dictionary in the shared HZDevice schema (idfv,idfa,udid,serial,wifi,bluetooth,imei).
- (void)applyIdentityDict:(NSDictionary *)identity;

@end

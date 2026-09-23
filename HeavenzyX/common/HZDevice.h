#import <Foundation/Foundation.h>

/// Shared identity model used by BOTH the Heavenzy control app and the tweak. Blaze-style: the real
/// iPhone is kept (model, screen, CPU, RAM, iOS, carrier, time zone all stay real) and only the
/// per-device *identity* is reset, so an app sees a brand-new phone with a first-time install.
///
/// The identity dictionary keys (stable, used on disk):
///   idfv,idfa   — identifierForVendor / advertisingIdentifier (UPPERCASE UUIDs)
///   udid,serial — MobileGestalt UniqueDeviceID / SerialNumber
///   wifi,bluetooth — MobileGestalt WifiAddress / BluetoothAddress (lowercase MACs)
///   imei        — MobileGestalt InternationalMobileEquipmentIdentity (15-digit, valid Luhn)
FOUNDATION_EXPORT NSDictionary *HZGenerateIdentity(void);

/// Human summary, e.g. "New identity · SN F2LX…".
FOUNDATION_EXPORT NSString *HZIdentitySummary(NSDictionary *identity);

/// Legacy device pool (now empty; kept for source compatibility).
FOUNDATION_EXPORT NSArray<NSDictionary *> *HZDevicePool(void);

#import <Foundation/Foundation.h>

/// Shared device-fingerprint model used by BOTH the Heavenzy control app and the tweak, so the two
/// never disagree on what a "device" looks like. Mirrors Ghost's module set (iPhone, Identifiers,
/// Battery, Carrier, Locale/TimeZone) with every attribute bound to the chosen model / region.
///
/// The identity dictionary keys (stable, used on disk):
///   model,name,ios (strings) · w,h,scale,cores,mem (numbers)
///   idfv,idfa,udid,serial (strings)
///   batteryLevel (number 0..1) · batteryCharging (bool)
///   carrierName,mcc,mnc,iso,timeZone,localeId (strings)
FOUNDATION_EXPORT NSDictionary *HZGenerateIdentity(void);

/// Human summary "iPhone 15 Pro · iOS 18.6.1".
FOUNDATION_EXPORT NSString *HZIdentitySummary(NSDictionary *identity);

/// The device pool (array of dicts, same keys as above minus identifiers/battery/region).
FOUNDATION_EXPORT NSArray<NSDictionary *> *HZDevicePool(void);

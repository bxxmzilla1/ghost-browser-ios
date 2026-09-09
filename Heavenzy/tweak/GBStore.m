#import "GBStore.h"
#import "HZDevice.h"
#import "HZConfig.h"
#import <string.h>

static NSString *GBPrefsPath(void) {
    // Inside the host app's sandbox — always writable, no cross-container sandbox issue.
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.heavenzy.plist"];
}

@implementation GBStore

+ (GBStore *)shared {
    static GBStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GBStore new]; [s reload]; });
    return s;
}

- (void)reload {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:GBPrefsPath()];
    _enabled       = [d[@"enabled"] boolValue];
    _wipePending   = [d[@"wipePending"] boolValue];
    _deviceModel   = [d[@"deviceModel"] copy];
    _marketingName = [d[@"marketingName"] copy];
    _systemVersion = [d[@"systemVersion"] copy];
    _deviceName    = [d[@"deviceName"] copy] ?: @"iPhone";
    _screenPointsW = [d[@"screenPointsW"] integerValue];
    _screenPointsH = [d[@"screenPointsH"] integerValue];
    _scaleFactor   = [d[@"scaleFactor"] integerValue];
    _cpuCores      = [d[@"cpuCores"] integerValue];
    _memoryGB      = [d[@"memoryGB"] integerValue];
    _idfv          = [d[@"idfv"] copy];
    _idfa          = [d[@"idfa"] copy];
    _udid          = [d[@"udid"] copy];
    _serialNumber  = [d[@"serial"] copy];
    _wifiAddress   = [d[@"wifi"] copy];
    _bluetoothAddress = [d[@"bluetooth"] copy];
    _imei          = [d[@"imei"] copy];
    _batteryLevel    = d[@"batteryLevel"] ? [d[@"batteryLevel"] doubleValue] : 0.72;
    _batteryCharging = [d[@"batteryCharging"] boolValue];
    _carrierName   = [d[@"carrierName"] copy];
    _mcc           = [d[@"mcc"] copy];
    _mnc           = [d[@"mnc"] copy];
    _isoCountryCode = [d[@"iso"] copy];
    _timeZoneName  = [d[@"timeZone"] copy];
    _localeId      = [d[@"localeId"] copy];
    _floatingOrigin = CGPointMake(d[@"floatX"] ? [d[@"floatX"] doubleValue] : -1,
                                  d[@"floatY"] ? [d[@"floatY"] doubleValue] : -1);

    // If the in-app panel never configured this app, fall back to what the Heavenzy control app set
    // centrally for this bundle id (Ghost model). Adopted into the local container so it sticks even
    // if libSandy access is unavailable next launch.
    if (!self.hasIdentity) {
        [HZConfig grantSandboxAccess];
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if ([HZConfig isEnabledForApp:bid]) {
            NSDictionary *identity = [HZConfig identityForApp:bid];
            if (identity) {
                [self applyIdentityDict:identity];
                _enabled = YES;
                [self save];
            }
        }
    }
}

// Maps the shared HZDevice-schema identity onto this store's fields. Only identifiers are applied —
// the real hardware is kept — and any stale hardware fields from an older build are cleared so they
// can never spoof the model again.
- (void)applyIdentityDict:(NSDictionary *)i {
    if (![i isKindOfClass:NSDictionary.class]) return;
    _idfv          = [i[@"idfv"] copy];
    _idfa          = [i[@"idfa"] copy];
    _udid          = [i[@"udid"] copy];
    _serialNumber  = [i[@"serial"] copy];
    _wifiAddress   = [i[@"wifi"] copy];
    _bluetoothAddress = [i[@"bluetooth"] copy];
    _imei          = [i[@"imei"] copy];
    // Explicitly drop any legacy hardware-profile spoofing.
    _deviceModel = nil; _marketingName = nil; _systemVersion = nil;
    _screenPointsW = 0; _screenPointsH = 0; _scaleFactor = 0; _cpuCores = 0; _memoryGB = 0;
    _carrierName = nil; _mcc = nil; _mnc = nil; _isoCountryCode = nil; _timeZoneName = nil; _localeId = nil;
    _deviceName    = @"iPhone";   // default fresh-device name (drops "<user>'s iPhone")
}

- (void)save {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"]       = @(_enabled);
    if (_wipePending)   d[@"wipePending"]   = @YES;
    if (_deviceModel)   d[@"deviceModel"]   = _deviceModel;
    if (_marketingName) d[@"marketingName"] = _marketingName;
    if (_systemVersion) d[@"systemVersion"] = _systemVersion;
    if (_deviceName)    d[@"deviceName"]    = _deviceName;
    if (_screenPointsW) d[@"screenPointsW"] = @(_screenPointsW);
    if (_screenPointsH) d[@"screenPointsH"] = @(_screenPointsH);
    if (_scaleFactor)   d[@"scaleFactor"]   = @(_scaleFactor);
    if (_cpuCores)      d[@"cpuCores"]      = @(_cpuCores);
    if (_memoryGB)      d[@"memoryGB"]      = @(_memoryGB);
    if (_idfv)          d[@"idfv"]          = _idfv;
    if (_idfa)          d[@"idfa"]          = _idfa;
    if (_udid)          d[@"udid"]          = _udid;
    if (_serialNumber)  d[@"serial"]        = _serialNumber;
    if (_wifiAddress)   d[@"wifi"]          = _wifiAddress;
    if (_bluetoothAddress) d[@"bluetooth"]  = _bluetoothAddress;
    if (_imei)          d[@"imei"]          = _imei;
    d[@"batteryLevel"]    = @(_batteryLevel);
    d[@"batteryCharging"] = @(_batteryCharging);
    if (_carrierName)   d[@"carrierName"]   = _carrierName;
    if (_mcc)           d[@"mcc"]           = _mcc;
    if (_mnc)           d[@"mnc"]           = _mnc;
    if (_isoCountryCode) d[@"iso"]          = _isoCountryCode;
    if (_timeZoneName)  d[@"timeZone"]      = _timeZoneName;
    if (_localeId)      d[@"localeId"]      = _localeId;
    if (_floatingOrigin.x >= 0 && _floatingOrigin.y >= 0) {
        d[@"floatX"] = @(_floatingOrigin.x);
        d[@"floatY"] = @(_floatingOrigin.y);
    }
    NSString *path = GBPrefsPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:path atomically:YES];
}

- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [self save]; }

- (BOOL)hasIdentity { return _serialNumber.length > 0 || _udid.length > 0 || _idfv.length > 0; }

- (NSInteger)nativePixelsW { return _screenPointsW * (_scaleFactor ?: 1); }
- (NSInteger)nativePixelsH { return _screenPointsH * (_scaleFactor ?: 1); }
- (unsigned long long)memoryBytes { return (unsigned long long)_memoryGB * 1024ULL * 1024ULL * 1024ULL; }

- (NSString *)summary {
    if (!self.hasIdentity) return @"No new identity yet";
    return [NSString stringWithFormat:@"New identity · SN %@", _serialNumber.length ? _serialNumber : @"?"];
}

- (void)regenerateIdentity {
    // Shared HZDevice generator (same one the control app uses) so the tweak and app agree.
    [self applyIdentityDict:HZGenerateIdentity()];
    [self save];
    NSLog(@"[Heavenzy] New identity: SN %@ · UDID %@ · IDFV %@ · IDFA %@ · Wi-Fi %@ · BT %@ · IMEI %@",
          _serialNumber, _udid, _idfv, _idfa, _wifiAddress, _bluetoothAddress, _imei);
}

@end

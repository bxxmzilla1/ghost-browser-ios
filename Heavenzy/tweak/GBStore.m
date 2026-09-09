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

// Maps the shared HZDevice-schema identity onto this store's fields.
- (void)applyIdentityDict:(NSDictionary *)i {
    if (![i isKindOfClass:NSDictionary.class]) return;
    _deviceModel   = [i[@"model"] copy];
    _marketingName = [i[@"name"] copy];
    _systemVersion = [i[@"ios"] copy];
    _screenPointsW = [i[@"w"] integerValue];
    _screenPointsH = [i[@"h"] integerValue];
    _scaleFactor   = [i[@"scale"] integerValue];
    _cpuCores      = [i[@"cores"] integerValue];
    _memoryGB      = [i[@"mem"] integerValue];
    _idfv          = [i[@"idfv"] copy];
    _idfa          = [i[@"idfa"] copy];
    _udid          = [i[@"udid"] copy];
    _serialNumber  = [i[@"serial"] copy];
    if (i[@"batteryLevel"])    _batteryLevel = [i[@"batteryLevel"] doubleValue];
    _batteryCharging = [i[@"batteryCharging"] boolValue];
    _carrierName   = [i[@"carrierName"] copy];
    _mcc           = [i[@"mcc"] copy];
    _mnc           = [i[@"mnc"] copy];
    _isoCountryCode = [i[@"iso"] copy];
    _timeZoneName  = [i[@"timeZone"] copy];
    _localeId      = [i[@"localeId"] copy];
    if (!_deviceName.length) _deviceName = @"iPhone";
}

- (void)save {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"]       = @(_enabled);
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

- (BOOL)hasIdentity { return _deviceModel.length > 0; }

- (NSInteger)nativePixelsW { return _screenPointsW * (_scaleFactor ?: 1); }
- (NSInteger)nativePixelsH { return _screenPointsH * (_scaleFactor ?: 1); }
- (unsigned long long)memoryBytes { return (unsigned long long)_memoryGB * 1024ULL * 1024ULL * 1024ULL; }

- (NSString *)summary {
    if (!self.hasIdentity) return @"Not spoofed yet";
    return [NSString stringWithFormat:@"%@ · iOS %@",
            _marketingName.length ? _marketingName : _deviceModel,
            _systemVersion.length ? _systemVersion : @"?"];
}

- (void)regenerateIdentity {
    // Uses the shared HZDevice generator (same pool the control app uses) so the tweak and app agree.
    [self applyIdentityDict:HZGenerateIdentity()];
    [self save];
    NSLog(@"[Heavenzy] New spoofed device: %@ (%@) iOS %@ · %ldx%ld@%ldx · %ld cores · %ld GB · %@ · %@ · UDID %@",
          _marketingName, _deviceModel, _systemVersion,
          (long)self.nativePixelsW, (long)self.nativePixelsH, (long)_scaleFactor, (long)_cpuCores, (long)_memoryGB,
          _carrierName, _timeZoneName, _udid);
}

@end

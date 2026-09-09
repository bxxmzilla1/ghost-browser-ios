#import "GBStore.h"
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
    _floatingOrigin = CGPointMake(d[@"floatX"] ? [d[@"floatX"] doubleValue] : -1,
                                  d[@"floatY"] ? [d[@"floatY"] doubleValue] : -1);
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

// Sessions X pattern: one row per device with every dependent attribute bound to it, so the
// spoofed model never contradicts screen size, scale, core count or RAM. hw.machine is the primary
// fingerprint; the rest keep the story consistent (Instagram builds "…; 1179x2556; scale=3.00; …").
// Keys: model, marketing name, iOS, points W, points H, scale, cores, RAM GB.
+ (NSArray<NSDictionary *> *)devicePool {
    static NSArray *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSArray *> *rows = @[
            //  model         marketing              iOS         W    H  scale cores mem
            @[@"iPhone12,1", @"iPhone 11",          @"16.7.10", @414, @896, @2, @6, @4],
            @[@"iPhone12,3", @"iPhone 11 Pro",      @"16.7.10", @375, @812, @3, @6, @4],
            @[@"iPhone12,5", @"iPhone 11 Pro Max",  @"16.7.10", @414, @896, @3, @6, @4],
            @[@"iPhone13,1", @"iPhone 12 mini",     @"17.6.1",  @375, @812, @3, @6, @4],
            @[@"iPhone13,2", @"iPhone 12",          @"17.6.1",  @390, @844, @3, @6, @4],
            @[@"iPhone13,3", @"iPhone 12 Pro",      @"17.6.1",  @390, @844, @3, @6, @6],
            @[@"iPhone13,4", @"iPhone 12 Pro Max",  @"17.6.1",  @428, @926, @3, @6, @6],
            @[@"iPhone14,4", @"iPhone 13 mini",     @"17.6.1",  @375, @812, @3, @6, @4],
            @[@"iPhone14,5", @"iPhone 13",          @"17.7.2",  @390, @844, @3, @6, @4],
            @[@"iPhone14,2", @"iPhone 13 Pro",      @"17.7.2",  @390, @844, @3, @6, @6],
            @[@"iPhone14,3", @"iPhone 13 Pro Max",  @"18.3.2",  @428, @926, @3, @6, @6],
            @[@"iPhone14,7", @"iPhone 14",          @"18.5",    @390, @844, @3, @6, @6],
            @[@"iPhone14,8", @"iPhone 14 Plus",     @"18.5",    @428, @926, @3, @6, @6],
            @[@"iPhone15,2", @"iPhone 14 Pro",      @"18.5",    @393, @852, @3, @6, @6],
            @[@"iPhone15,3", @"iPhone 14 Pro Max",  @"18.6",    @430, @932, @3, @6, @6],
            @[@"iPhone15,4", @"iPhone 15",          @"18.6",    @393, @852, @3, @6, @6],
            @[@"iPhone15,5", @"iPhone 15 Plus",     @"18.6",    @430, @932, @3, @6, @6],
            @[@"iPhone16,1", @"iPhone 15 Pro",      @"18.6.1",  @393, @852, @3, @6, @8],
            @[@"iPhone16,2", @"iPhone 15 Pro Max",  @"18.6.1",  @430, @932, @3, @6, @8],
            @[@"iPhone17,3", @"iPhone 16",          @"18.6.1",  @393, @852, @3, @6, @8],
            @[@"iPhone17,4", @"iPhone 16 Plus",     @"18.6.1",  @430, @932, @3, @6, @8],
            @[@"iPhone17,1", @"iPhone 16 Pro",      @"18.6.1",  @402, @874, @3, @6, @8],
            @[@"iPhone17,2", @"iPhone 16 Pro Max",  @"18.6.1",  @440, @956, @3, @6, @8],
        ];
        NSMutableArray *out = [NSMutableArray array];
        for (NSArray *r in rows) {
            [out addObject:@{
                @"model": r[0], @"name": r[1], @"ios": r[2],
                @"w": r[3], @"h": r[4], @"scale": r[5], @"cores": r[6], @"mem": r[7]
            }];
        }
        pool = [out copy];
    });
    return pool;
}

static NSString *GBUUIDUpper(void) { return [[NSUUID UUID] UUIDString]; }

static NSString *GBHex(NSUInteger n) {
    const char *hex = "0123456789ABCDEF";
    NSMutableString *s = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%c", hex[arc4random_uniform(16)]];
    return s;
}

static NSString *GBAlnum(NSUInteger n) {
    const char *set = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"; // Apple serials avoid I/O
    NSMutableString *s = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%c", set[arc4random_uniform((uint32_t)strlen(set))]];
    return s;
}

// Region rows keep carrier + timezone + ISO country coherent (a US carrier never pairs with a
// European clock). Kept US-only so the app's language is never flipped.
// Keys: IANA time zone, carrier name, MCC, MNC, ISO country.
+ (NSArray<NSArray<NSString *> *> *)regionPool {
    static NSArray *pool; static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            @[@"America/New_York",    @"AT&T",     @"310", @"410", @"us"],
            @[@"America/Chicago",     @"T-Mobile", @"310", @"260", @"us"],
            @[@"America/Los_Angeles", @"Verizon",  @"311", @"480", @"us"],
            @[@"America/Denver",      @"AT&T",     @"310", @"410", @"us"],
            @[@"America/Phoenix",     @"T-Mobile", @"310", @"260", @"us"],
        ];
    });
    return pool;
}

- (void)regenerateIdentity {
    NSArray<NSDictionary *> *pool = [GBStore devicePool];
    NSDictionary *pick = pool[arc4random_uniform((uint32_t)pool.count)];
    _deviceModel   = pick[@"model"];
    _marketingName = pick[@"name"];
    _systemVersion = pick[@"ios"];
    _screenPointsW = [pick[@"w"] integerValue];
    _screenPointsH = [pick[@"h"] integerValue];
    _scaleFactor   = [pick[@"scale"] integerValue];
    _cpuCores      = [pick[@"cores"] integerValue];
    _memoryGB      = [pick[@"mem"] integerValue];
    _deviceName    = @"iPhone";
    _idfv = GBUUIDUpper();
    _idfa = GBUUIDUpper();

    // MobileGestalt identifiers (survive uninstall/iCloud for real devices — spoofing breaks the link).
    _udid   = [NSString stringWithFormat:@"%@-%@", GBHex(8), GBHex(16)]; // modern A12+ UDID form
    _serialNumber = GBAlnum(12);

    // Battery: a believable non-round level, usually on battery (not charging).
    _batteryLevel = (double)(arc4random_uniform(69) + 28) / 100.0;       // 0.28–0.96
    _batteryCharging = (arc4random_uniform(4) == 0);                     // ~25% charging

    // Region-coherent carrier + time zone.
    NSArray<NSString *> *region = [GBStore regionPool][arc4random_uniform((uint32_t)[GBStore regionPool].count)];
    _timeZoneName  = region[0];
    _carrierName   = region[1];
    _mcc           = region[2];
    _mnc           = region[3];
    _isoCountryCode = region[4];

    [self save];
    NSLog(@"[Heavenzy] New spoofed device: %@ (%@) iOS %@ · %ldx%ld@%ldx · %ld cores · %ld GB · %@ · %@ · UDID %@",
          _marketingName, _deviceModel, _systemVersion,
          (long)self.nativePixelsW, (long)self.nativePixelsH, (long)_scaleFactor, (long)_cpuCores, (long)_memoryGB,
          _carrierName, _timeZoneName, _udid);
}

@end

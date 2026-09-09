#import "GBStore.h"

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
    _idfv          = [d[@"idfv"] copy];
    _idfa          = [d[@"idfa"] copy];
    _bundleAPIKey  = [d[@"bundleAPIKey"] copy] ?: @"";
    _bundleTeamId  = [d[@"bundleTeamId"] copy] ?: @"";
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
    if (_idfv)          d[@"idfv"]          = _idfv;
    if (_idfa)          d[@"idfa"]          = _idfa;
    if (_bundleAPIKey.length) d[@"bundleAPIKey"] = _bundleAPIKey;
    if (_bundleTeamId.length) d[@"bundleTeamId"] = _bundleTeamId;
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

- (NSString *)summary {
    if (!self.hasIdentity) return @"Not spoofed yet";
    return [NSString stringWithFormat:@"%@ · iOS %@",
            _marketingName.length ? _marketingName : _deviceModel,
            _systemVersion.length ? _systemVersion : @"?"];
}

// Plausible modern iPhones paired with a sensible iOS. hw.machine is the primary fingerprint.
+ (NSArray<NSArray<NSString *> *> *)devicePool {
    static NSArray *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            @[@"iPhone12,1", @"iPhone 11",          @"16.7.10"],
            @[@"iPhone12,3", @"iPhone 11 Pro",      @"16.7.10"],
            @[@"iPhone12,5", @"iPhone 11 Pro Max",  @"16.7.10"],
            @[@"iPhone13,1", @"iPhone 12 mini",     @"17.6.1"],
            @[@"iPhone13,2", @"iPhone 12",          @"17.6.1"],
            @[@"iPhone13,3", @"iPhone 12 Pro",      @"17.6.1"],
            @[@"iPhone13,4", @"iPhone 12 Pro Max",  @"17.6.1"],
            @[@"iPhone14,4", @"iPhone 13 mini",     @"17.6.1"],
            @[@"iPhone14,5", @"iPhone 13",          @"17.7.2"],
            @[@"iPhone14,2", @"iPhone 13 Pro",      @"17.7.2"],
            @[@"iPhone14,3", @"iPhone 13 Pro Max",  @"18.3.2"],
            @[@"iPhone14,7", @"iPhone 14",          @"18.5"],
            @[@"iPhone14,8", @"iPhone 14 Plus",     @"18.5"],
            @[@"iPhone15,2", @"iPhone 14 Pro",      @"18.5"],
            @[@"iPhone15,3", @"iPhone 14 Pro Max",  @"18.6"],
            @[@"iPhone15,4", @"iPhone 15",          @"18.6"],
            @[@"iPhone15,5", @"iPhone 15 Plus",     @"18.6"],
            @[@"iPhone16,1", @"iPhone 15 Pro",      @"18.6.1"],
            @[@"iPhone16,2", @"iPhone 15 Pro Max",  @"18.6.1"],
            @[@"iPhone17,3", @"iPhone 16",          @"18.6.1"],
            @[@"iPhone17,4", @"iPhone 16 Plus",     @"18.6.1"],
            @[@"iPhone17,1", @"iPhone 16 Pro",      @"18.6.1"],
            @[@"iPhone17,2", @"iPhone 16 Pro Max",  @"18.6.1"],
        ];
    });
    return pool;
}

static NSString *GBUUIDUpper(void) { return [[NSUUID UUID] UUIDString]; }

- (void)regenerateIdentity {
    NSArray<NSArray<NSString *> *> *pool = [GBStore devicePool];
    NSArray<NSString *> *pick = pool[arc4random_uniform((uint32_t)pool.count)];
    _deviceModel   = pick[0];
    _marketingName = pick[1];
    _systemVersion = pick[2];
    _deviceName    = @"iPhone";
    _idfv = GBUUIDUpper();
    _idfa = GBUUIDUpper();
    [self save];
    NSLog(@"[Heavenzy] New spoofed device: %@ (%@) iOS %@", _marketingName, _deviceModel, _systemVersion);
}

@end

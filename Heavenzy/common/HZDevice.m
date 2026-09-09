#import "HZDevice.h"
#import <string.h>

NSArray<NSDictionary *> *HZDevicePool(void) {
    static NSArray *pool; static dispatch_once_t once;
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
            [out addObject:@{ @"model": r[0], @"name": r[1], @"ios": r[2],
                              @"w": r[3], @"h": r[4], @"scale": r[5], @"cores": r[6], @"mem": r[7] }];
        }
        pool = [out copy];
    });
    return pool;
}

// Region rows keep carrier + timezone + ISO coherent. US-only so app language never flips.
static NSArray<NSArray<NSString *> *> *HZRegionPool(void) {
    static NSArray *pool; static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            //  IANA tz            carrier      MCC    MNC    ISO   locale
            @[@"America/New_York",    @"AT&T",     @"310", @"410", @"us", @"en_US"],
            @[@"America/Chicago",     @"T-Mobile", @"310", @"260", @"us", @"en_US"],
            @[@"America/Los_Angeles", @"Verizon",  @"311", @"480", @"us", @"en_US"],
            @[@"America/Denver",      @"AT&T",     @"310", @"410", @"us", @"en_US"],
            @[@"America/Phoenix",     @"T-Mobile", @"310", @"260", @"us", @"en_US"],
        ];
    });
    return pool;
}

static NSString *HZUUIDUpper(void) { return [[NSUUID UUID] UUIDString]; }

static NSString *HZHex(NSUInteger n) {
    const char *hex = "0123456789ABCDEF";
    NSMutableString *s = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%c", hex[arc4random_uniform(16)]];
    return s;
}

static NSString *HZAlnum(NSUInteger n) {
    const char *set = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"; // Apple serials skip I/O
    NSMutableString *s = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%c", set[arc4random_uniform((uint32_t)strlen(set))]];
    return s;
}

NSDictionary *HZGenerateIdentity(void) {
    NSArray<NSDictionary *> *pool = HZDevicePool();
    NSDictionary *dev = pool[arc4random_uniform((uint32_t)pool.count)];
    NSArray<NSString *> *region = HZRegionPool()[arc4random_uniform((uint32_t)HZRegionPool().count)];

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"model"] = dev[@"model"]; d[@"name"] = dev[@"name"]; d[@"ios"] = dev[@"ios"];
    d[@"w"] = dev[@"w"]; d[@"h"] = dev[@"h"]; d[@"scale"] = dev[@"scale"];
    d[@"cores"] = dev[@"cores"]; d[@"mem"] = dev[@"mem"];
    d[@"idfv"] = HZUUIDUpper();
    d[@"idfa"] = HZUUIDUpper();
    d[@"udid"] = [NSString stringWithFormat:@"%@-%@", HZHex(8), HZHex(16)]; // modern A12+ UDID form
    d[@"serial"] = HZAlnum(12);
    d[@"batteryLevel"] = @((double)(arc4random_uniform(69) + 28) / 100.0); // 0.28–0.96
    d[@"batteryCharging"] = @(arc4random_uniform(4) == 0);                 // ~25% charging
    d[@"timeZone"]   = region[0];
    d[@"carrierName"] = region[1];
    d[@"mcc"] = region[2]; d[@"mnc"] = region[3]; d[@"iso"] = region[4];
    d[@"localeId"] = region[5];
    return [d copy];
}

NSString *HZIdentitySummary(NSDictionary *i) {
    if (![i isKindOfClass:NSDictionary.class] || !i[@"name"]) return @"Not spoofed yet";
    return [NSString stringWithFormat:@"%@ · iOS %@", i[@"name"], i[@"ios"] ?: @"?"];
}

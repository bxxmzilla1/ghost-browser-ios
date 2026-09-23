#import "HZDevice.h"
#import <string.h>

// The device pool is retained for reference/compat but is NOT used to change the model any more:
// Heavenzy keeps the real iPhone and only resets the per-device identity (Blaze-style).
NSArray<NSDictionary *> *HZDevicePool(void) {
    static NSArray *pool; static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = @[]; });
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

// A believable Wi-Fi/Bluetooth MAC: a real Apple OUI prefix + three random bytes, lowercase, colon-
// separated (the form apps read back from MGCopyAnswer("WifiAddress")/"BluetoothAddress").
static NSString *HZRandomMAC(void) {
    static const char *ouis[] = { "f0:18:98", "a4:83:e7", "dc:2b:2a", "3c:15:c2", "b8:e8:56", "ac:bc:32" };
    const char *oui = ouis[arc4random_uniform(sizeof(ouis)/sizeof(ouis[0]))];
    return [NSString stringWithFormat:@"%s:%02x:%02x:%02x",
            oui, arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)];
}

#pragma mark - iPhone X (A11, iPhone10,3 / iPhone10,6) consistent identifiers
//
// Heavenzy X keeps the real hardware but every generated identifier must decode as an iPhone X, the
// way the pre-2021 Apple formats do:
//   • Serial  (12 chars, PPP Y W SSS CCCC): Foxconn iPhone factory code, a year/week inside the X's
//     production window (Sept 2017 – Sept 2018), a unique part, and an iPhone X configuration code.
//   • UDID    (40 hex, lowercase): A11 and earlier report the legacy SHA-1-style UDID, not the
//     "XXXXXXXX-XXXXXXXXXXXXXXXX" form introduced with A12.
//   • IMEI    (15 digits): a real iPhone X Type Allocation Code + 6-digit serial + Luhn check digit.

// Foxconn iPhone assembly codes (first two chars = plant, third = line): F1/FK Zhengzhou, C3/G6
// Shenzhen, DN Chengdu — the plants that built the iPhone X.
static NSString *HZXFactoryCode(void) {
    static NSString *const codes[] = { @"F17", @"F18", @"F1L", @"FK1", @"FK2", @"DNP", @"DNQ", @"C39", @"C3C", @"G6T", @"G6V" };
    return codes[arc4random_uniform(sizeof(codes) / sizeof(codes[0]))];
}

// Year (4th char) + week (5th char). Year codes: T/V = 2017 H1/H2, W/X = 2018 H1/H2. Week codes run
// 1-9,C,D,F,G,H,J,K,L,M,N,P,Q,R,T,V,W,X,Y for weeks 1-27 of the half (Y unused in H2).
// The iPhone X shipped from week 37 of 2017 (Nov 3 launch, mass production from Sept) until it was
// discontinued in Sept 2018, so only draw dates inside that window.
static NSString *HZXYearWeek(void) {
    static const char *weeks = "123456789CDFGHJKLMNPQRTVWXY";
    struct { char year; int lo, hi; } windows[] = {
        { 'V', 9,  25 },   // 2017 H2: weeks 37–53  → index 9..25
        { 'W', 0,  26 },   // 2018 H1: weeks 1–27   → index 0..26
        { 'X', 0,  10 },   // 2018 H2: weeks 28–38  → index 0..10 (built until the Sept 2018 cut-off)
    };
    // Weight towards 2017 H2 / 2018 H1, when the bulk of iPhone X units were made.
    int pick = (int)arc4random_uniform(10);
    int w = pick < 4 ? 0 : (pick < 9 ? 1 : 2);
    int idx = windows[w].lo + (int)arc4random_uniform((uint32_t)(windows[w].hi - windows[w].lo + 1));
    return [NSString stringWithFormat:@"%c%c", windows[w].year, weeks[idx]];
}

// iPhone X configuration codes (last 4 serial chars encode model + colour + capacity). JCLJ is a
// verified Silver 64 GB unit; the rest are the JCL* family Apple assigned to the X's variants.
static NSString *HZXConfigCode(void) {
    static NSString *const codes[] = { @"JCLJ", @"JCL6", @"JCL7", @"JCL8", @"JCL9", @"JCLD", @"JCLF", @"JCLG", @"JCLH", @"JCLK", @"JCLL", @"JCLM" };
    return codes[arc4random_uniform(sizeof(codes) / sizeof(codes[0]))];
}

static NSString *HZXSerial(void) {
    return [NSString stringWithFormat:@"%@%@%@%@", HZXFactoryCode(), HZXYearWeek(), HZAlnum(3), HZXConfigCode()];
}

// Legacy 40-hex UDID (lowercase) as reported by A11 devices.
static NSString *HZXUDID(void) { return [HZHex(40) lowercaseString]; }

// Type Allocation Codes registered to the iPhone X (fccid.io / GSMA TAC DB):
//   35304409  A1901 (Intel XMM 7480)    35305309 / 35305609  A1865 (Qualcomm X16)
static NSString *HZXTAC(void) {
    static NSString *const tacs[] = { @"35304409", @"35305309", @"35305609" };
    return tacs[arc4random_uniform(sizeof(tacs) / sizeof(tacs[0]))];
}

// A 15-digit IMEI with a valid Luhn check digit (so validators accept it), built from a real
// iPhone X TAC so the model decodes correctly.
static NSString *HZRandomIMEI(void) {
    int digits[14];
    NSString *tac = HZXTAC();
    for (int i = 0; i < 8; i++) digits[i] = [tac characterAtIndex:i] - '0';
    for (int i = 8; i < 14; i++) digits[i] = (int)arc4random_uniform(10);

    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int d = digits[i];
        int overallPosFromRight = (13 - i) + 1;                 // account for appended check digit
        if (overallPosFromRight % 2 == 1) { d *= 2; if (d > 9) d -= 9; }
        sum += d;
    }
    int check = (10 - (sum % 10)) % 10;

    NSMutableString *s = [NSMutableString stringWithCapacity:15];
    for (int i = 0; i < 14; i++) [s appendFormat:@"%d", digits[i]];
    [s appendFormat:@"%d", check];
    return s;
}

// Blaze-style: same phone, brand-new identity. Only the per-device identifiers change — nothing that
// would contradict the real model (screen, CPU, RAM, iOS, carrier, time zone all stay real) — and
// every identifier is generated in the form an iPhone X actually has.
NSDictionary *HZGenerateIdentity(void) {
    return @{
        @"idfv":      HZUUIDUpper(),   // identifierForVendor
        @"idfa":      HZUUIDUpper(),   // advertisingIdentifier
        @"udid":      HZXUDID(),       // MG UniqueDeviceID — 40-hex legacy form (A11)
        @"serial":    HZXSerial(),     // MG SerialNumber — Foxconn plant + 2017/18 date + JCL* config
        @"wifi":      HZRandomMAC(),   // MG WifiAddress
        @"bluetooth": HZRandomMAC(),   // MG BluetoothAddress
        @"imei":      HZRandomIMEI(),  // MG InternationalMobileEquipmentIdentity — iPhone X TAC
    };
}

NSString *HZIdentitySummary(NSDictionary *i) {
    if (![i isKindOfClass:NSDictionary.class] || (!i[@"serial"] && !i[@"udid"])) return @"No new identity yet";
    NSString *serial = i[@"serial"] ?: @"?";
    return [NSString stringWithFormat:@"New iPhone X identity · SN %@", serial];
}

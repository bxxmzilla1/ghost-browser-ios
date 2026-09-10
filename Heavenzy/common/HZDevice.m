#import "HZDevice.h"
#import <string.h>
#import <sys/sysctl.h>

// The device pool is retained for reference/compat but is NOT used to change the model any more:
// Heavenzy keeps the real iPhone and only resets the per-device identity (Blaze-style).
NSArray<NSDictionary *> *HZDevicePool(void) {
    static NSArray *pool; static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = @[]; });
    return pool;
}

static NSString *HZUUIDUpper(void) { return [[NSUUID UUID] UUIDString]; }

static NSString *HZHexCase(NSUInteger n, BOOL upper) {
    const char *hex = upper ? "0123456789ABCDEF" : "0123456789abcdef";
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

#pragma mark - Real model detection

// The physical device model, e.g. "iPhone10,4" (iPhone 8). Heavenzy keeps the real hardware, so every
// generated identifier is shaped to match *this* model — the app never sees a contradiction.
static NSString *HZRealMachine(void) {
    char buf[64] = {0}; size_t len = sizeof(buf);
    if (sysctlbyname("hw.machine", buf, &len, NULL, 0) != 0 || len == 0) return @"";
    return [NSString stringWithUTF8String:buf];
}

// Major generation from "iPhoneN,M" → N. Returns -1 for non-iPhone, 0 if unparseable.
static int HZiPhoneGen(NSString *machine) {
    if (![machine hasPrefix:@"iPhone"]) return -1;
    int n = 0; NSScanner *sc = [NSScanner scannerWithString:[machine substringFromIndex:6]];
    return [sc scanInt:&n] ? n : 0;
}

#pragma mark - Model-consistent generators

// UDID: iPhone X/8 (A11) and earlier use a 40-char lowercase-hex UDID; iPhone XS (A12) and later use
// the "0000<ChipID>-<16-hex ECID>" form (uppercase). ChipID by SoC: A12 8020, A13 8030, A14 8101,
// A15 8110, A16 8120, A17 8130, A18 8140.
static NSString *HZChipIDForGen(int gen) {
    switch (gen) {
        case 11: return @"8020";  // A12  (iPhone XS/XR)
        case 12: return @"8030";  // A13  (iPhone 11)
        case 13: return @"8101";  // A14  (iPhone 12)
        case 14: return @"8110";  // A15  (iPhone 13 / 14 / SE3)
        case 15: return @"8120";  // A16  (iPhone 14 Pro / 15)
        case 16: return @"8130";  // A17  (iPhone 15 Pro)
        default: return gen >= 17 ? @"8140" : nil;   // A18+; nil = legacy 40-hex form (A11 & older)
    }
}

static NSString *HZGenerateUDID(NSString *machine) {
    NSString *chip = HZChipIDForGen(HZiPhoneGen(machine));
    if (chip) return [NSString stringWithFormat:@"0000%@-%@", chip, HZHexCase(16, YES)];  // A12+
    return HZHexCase(40, NO);                                                             // iPhone 8/X & earlier
}

// Serial: legacy 12-char (encodes factory/date/config) up to iPhone 12; Apple switched to a random
// 10-char alphanumeric with the iPhone 13 generation (2021). We can't reproduce Apple's exact config
// code, so we randomise the whole thing at the right length for the era.
static NSString *HZGenerateSerial(NSString *machine) {
    int gen = HZiPhoneGen(machine);
    return HZAlnum(gen >= 14 ? 10 : 12);   // iPhone14,x == iPhone 13 → 10-char randomized era
}

// A believable Apple MAC pair: a real Apple OUI + three random bytes, lowercase & colon-separated,
// with the Bluetooth address one greater than the Wi-Fi address (as real iPhones report them).
static void HZGenerateMACs(NSString **wifi, NSString **bluetooth) {
    static const char *ouis[] = { "f0:18:98", "a4:83:e7", "dc:2b:2a", "3c:15:c2", "b8:e8:56", "ac:bc:32" };
    const char *oui = ouis[arc4random_uniform(sizeof(ouis)/sizeof(ouis[0]))];
    unsigned b4 = arc4random_uniform(256), b5 = arc4random_uniform(256), b6 = arc4random_uniform(256);
    *wifi = [NSString stringWithFormat:@"%s:%02x:%02x:%02x", oui, b4, b5, b6];
    *bluetooth = [NSString stringWithFormat:@"%s:%02x:%02x:%02x", oui, b4, b5, (b6 + 1) & 0xFF];
}

// Real Apple iPhone TAC (first 8 IMEI digits, model-specific). The current device's model is exact;
// unrecognised models fall back to a real Apple iPhone TAC so lookups still resolve to Apple.
static NSString *HZTACForModel(NSString *machine) {
    static NSDictionary *map; static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"iPhone10,1": @"35299209", @"iPhone10,4": @"35299209",   // iPhone 8
            @"iPhone10,2": @"35299209", @"iPhone10,5": @"35299209",   // iPhone 8 Plus
            @"iPhone10,3": @"35300109", @"iPhone10,6": @"35300109",   // iPhone X
            @"iPhone12,1": @"35875110",                               // iPhone 11
            @"iPhone14,6": @"35407115",                               // iPhone SE (3rd gen)
            @"iPhone15,2": @"35695917", @"iPhone15,3": @"35695917",   // iPhone 14 Pro / Pro Max
            @"iPhone16,2": @"35332510",                               // iPhone 15 Pro Max
        };
    });
    NSString *t = map[machine];
    return t ?: @"35875110";   // generic real Apple iPhone TAC fallback
}

// Build a 15-digit IMEI: model TAC (8) + random serial (6) + Luhn check digit (so validators pass).
static NSString *HZGenerateIMEI(NSString *machine) {
    NSString *tac = HZTACForModel(machine);
    int digits[14];
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

// Blaze-style: same phone, brand-new identity. Every identifier is shaped to the *real* model so an
// app can't spot a mismatch — UDID format & chip, serial length, and IMEI TAC all track this device.
NSDictionary *HZGenerateIdentity(void) {
    NSString *machine = HZRealMachine();
    NSString *wifi = nil, *bluetooth = nil;
    HZGenerateMACs(&wifi, &bluetooth);
    return @{
        @"idfv":      HZUUIDUpper(),            // identifierForVendor  (per-vendor UUID, model-independent)
        @"idfa":      HZUUIDUpper(),            // advertisingIdentifier (UUID, model-independent)
        @"udid":      HZGenerateUDID(machine),  // MG UniqueDeviceID     (format/chip match this model)
        @"serial":    HZGenerateSerial(machine),// MG SerialNumber       (length matches the era)
        @"wifi":      wifi,                      // MG WifiAddress        (Apple OUI)
        @"bluetooth": bluetooth,                 // MG BluetoothAddress   (Wi-Fi + 1, as on real iPhones)
        @"imei":      HZGenerateIMEI(machine),  // MG IMEI               (real Apple TAC for this model)
    };
}

NSString *HZIdentitySummary(NSDictionary *i) {
    if (![i isKindOfClass:NSDictionary.class] || (!i[@"serial"] && !i[@"udid"])) return @"No new identity yet";
    NSString *serial = i[@"serial"] ?: @"?";
    return [NSString stringWithFormat:@"New identity · SN %@", serial];
}

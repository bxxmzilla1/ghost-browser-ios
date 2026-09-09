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

// A 15-digit IMEI with a valid Luhn check digit (so validators accept it).
static NSString *HZRandomIMEI(void) {
    int digits[14];
    digits[0] = 1 + (int)arc4random_uniform(9);                 // no leading zero
    for (int i = 1; i < 14; i++) digits[i] = (int)arc4random_uniform(10);

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
// would contradict the real model (screen, CPU, RAM, iOS, carrier, time zone all stay real).
NSDictionary *HZGenerateIdentity(void) {
    return @{
        @"idfv":      HZUUIDUpper(),   // identifierForVendor
        @"idfa":      HZUUIDUpper(),   // advertisingIdentifier
        @"udid":      [NSString stringWithFormat:@"%@-%@", HZHex(8), HZHex(16)], // MG UniqueDeviceID (A12+ form)
        @"serial":    HZAlnum(12),     // MG SerialNumber
        @"wifi":      HZRandomMAC(),   // MG WifiAddress
        @"bluetooth": HZRandomMAC(),   // MG BluetoothAddress
        @"imei":      HZRandomIMEI(),  // MG InternationalMobileEquipmentIdentity
    };
}

NSString *HZIdentitySummary(NSDictionary *i) {
    if (![i isKindOfClass:NSDictionary.class] || (!i[@"serial"] && !i[@"udid"])) return @"No new identity yet";
    NSString *serial = i[@"serial"] ?: @"?";
    return [NSString stringWithFormat:@"New identity · SN %@", serial];
}

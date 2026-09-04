#import "GhostTokenStore.h"

static NSString *const kGhostPrefsDomain = @"com.ghost.tweak.instagram";
static NSString *const kNoData = @"No data available";

@implementation GhostTokenStore

+ (instancetype)shared {
    static GhostTokenStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[GhostTokenStore alloc] init]; [s reload]; });
    return s;
}

- (void)reload {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGhostPrefsDomain];
    if (!d) d = [NSUserDefaults standardUserDefaults];
#define G(k) _ ## k = [d stringForKey:@ #k] ?: @""
    G(username); G(androidID); G(deviceID); G(idfv); G(idfa);
    G(authorization); G(igUserID); G(igIntendedUserID); G(xMID); G(xIGWWWClaim);
    G(sessionid); G(csrftoken); G(rur);
    G(deviceModel); G(deviceModelName); G(deviceName); G(systemVersion);
    G(proxyHost); G(proxyUser); G(proxyPass);
#undef G
    _injectHeaders = [d boolForKey:@"injectHeaders"] ?: YES;
    _injectCookies = [d boolForKey:@"injectCookies"] ?: YES;
    _proxyPort = [d integerForKey:@"proxyPort"];
    if (!_igUserID.length && _sessionid.length) {
        // ds_user_id sometimes only in session cookie context — keep igUserID as canonical.
    }
}

- (void)save {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGhostPrefsDomain];
    if (!d) d = [NSUserDefaults standardUserDefaults];
#define S(k) [d setObject:self.k ?: @"" forKey:@ #k]
    S(username); S(androidID); S(deviceID); S(idfv); S(idfa);
    S(authorization); S(igUserID); S(igIntendedUserID); S(xMID); S(xIGWWWClaim);
    S(sessionid); S(csrftoken); S(rur);
    S(deviceModel); S(deviceModelName); S(deviceName); S(systemVersion);
    S(proxyHost); S(proxyUser); S(proxyPass);
#undef S
    [d setBool:_injectHeaders forKey:@"injectHeaders"];
    [d setBool:_injectCookies forKey:@"injectCookies"];
    [d setInteger:_proxyPort forKey:@"proxyPort"];
    [d synchronize];
}

- (BOOL)isEmpty {
    return !(_sessionid.length || _authorization.length || _igUserID.length ||
             _idfa.length || _idfv.length || _androidID.length);
}

static NSString *NormalizeKey(NSString *s) {
    NSCharacterSet *keep = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ([keep characterIsMember:c]) [m appendFormat:@"%C", c];
    }
    return m.lowercaseString;
}

- (void)setField:(NSString *)normKey value:(NSString *)value {
    if ([value.lowercaseString isEqualToString:@"no data available"] ||
        [value isEqualToString:@"-"] || [value.lowercaseString isEqualToString:@"null"]) {
        value = @"";
    }
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([normKey isEqualToString:@"username"]) _username = value;
    else if ([normKey isEqualToString:@"androidid"]) _androidID = value;
    else if ([normKey isEqualToString:@"deviceid"]) _deviceID = value;
    else if ([normKey isEqualToString:@"idfv"]) _idfv = value;
    else if ([normKey isEqualToString:@"idfa"]) _idfa = value;
    else if ([normKey isEqualToString:@"authorization"]) _authorization = value;
    else if ([normKey isEqualToString:@"igudsuserid"] || [normKey isEqualToString:@"iguserid"]) _igUserID = value;
    else if ([normKey isEqualToString:@"igintendeduserid"]) _igIntendedUserID = value;
    else if ([normKey isEqualToString:@"xmid"]) _xMID = value;
    else if ([normKey isEqualToString:@"xigwwwclaim"]) _xIGWWWClaim = value;
    else if ([normKey isEqualToString:@"sessionid"]) _sessionid = value;
    else if ([normKey isEqualToString:@"csrftoken"]) _csrftoken = value;
    else if ([normKey isEqualToString:@"rur"]) _rur = value;
}

- (void)applyTextBlock:(NSString *)block {
    for (NSString *line in [block componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:colon.location];
        NSString *val = [line substringFromIndex:colon.location + 1];
        [self setField:NormalizeKey(key) value:val];
    }
    if (!_igIntendedUserID.length && _igUserID.length) _igIntendedUserID = _igUserID;
    if (!_deviceID.length && _sessionid.length) { /* ig_did may come separately */ }
    [self save];
}

- (NSString *)textBlock {
    NSString *(^v)(NSString *) = ^(NSString *s) {
        return s.length ? s : kNoData;
    };
    return [NSString stringWithFormat:
            @"Username: %@\n"
            @"Android ID: %@\n"
            @"Device ID: %@\n"
            @"IDFV: %@\n"
            @"IDFA: %@\n"
            @"Authorization: %@\n"
            @"IG-U-DS-USER-ID: %@\n"
            @"IG-INTENDED-USER-ID: %@\n"
            @"X-MID: %@\n"
            @"X-IG-WWW-Claim: %@\n"
            @"sessionid: %@\n"
            @"csrftoken: %@\n"
            @"rur: %@",
            v(_username), v(_androidID), v(_deviceID), v(_idfv), v(_idfa),
            v([self effectiveAuthorization]), v(_igUserID), v(_igIntendedUserID),
            v(_xMID), v(_xIGWWWClaim), v(_sessionid), v(_csrftoken), v(_rur)];
}

- (NSString *)effectiveAuthorization {
    if (_authorization.length) return _authorization;
    if (!_sessionid.length || !_igUserID.length) return @"";
    NSString *sid = [_sessionid stringByRemovingPercentEncoding] ?: _sessionid;
    NSDictionary *payload = @{
        @"ds_user_id": _igUserID,
        @"sessionid": sid,
        @"should_use_header_over_cookies": @YES
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
    if (!json) return @"";
    return [NSString stringWithFormat:@"Bearer IGT:2:%@", [json base64EncodedStringWithOptions:0]];
}

- (NSDictionary<NSString *, NSString *> *)requestHeaders {
    if (!_injectHeaders) return @{};
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    NSString *auth = [self effectiveAuthorization];
    if (auth.length) h[@"Authorization"] = auth;
    if (_igUserID.length) h[@"IG-U-DS-USER-ID"] = _igUserID;
    if (_igIntendedUserID.length) h[@"IG-INTENDED-USER-ID"] = _igIntendedUserID;
    if (_xMID.length) h[@"X-MID"] = _xMID;
    if (_xIGWWWClaim.length) h[@"X-IG-WWW-Claim"] = _xIGWWWClaim;
    return h;
}

- (void)fillMissingGeneratedIDs {
    if (!_androidID.length) _androidID = [self generateAndroidID];
    if (!_idfv.length) _idfv = [self generateUUIDUpper];
    if (!_idfa.length) _idfa = [self generateUUIDUpper];
    if (!_deviceID.length) _deviceID = [self generateUUIDLower];
    if (!_xMID.length) _xMID = [self generateXMID];
    if (![self hasDeviceProfile]) [self regenerateDeviceProfile];
    [self save];
}

#pragma mark - Spoofed device identity

// Plausible modern iPhones with a sensible iOS pairing. hw.machine is what Instagram
// fingerprints; the marketing name + iOS are for display and secondary signals.
+ (NSArray<NSArray<NSString *> *> *)devicePool {
    static NSArray *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            @[@"iPhone12,1", @"iPhone 11",         @"17.6.1"],
            @[@"iPhone12,3", @"iPhone 11 Pro",     @"17.7.2"],
            @[@"iPhone13,1", @"iPhone 12 mini",    @"17.6.1"],
            @[@"iPhone13,2", @"iPhone 12",         @"18.3.2"],
            @[@"iPhone13,3", @"iPhone 12 Pro",     @"18.5"],
            @[@"iPhone13,4", @"iPhone 12 Pro Max", @"18.6.1"],
            @[@"iPhone14,4", @"iPhone 13 mini",    @"18.5"],
            @[@"iPhone14,5", @"iPhone 13",         @"18.6.1"],
            @[@"iPhone14,2", @"iPhone 13 Pro",     @"18.6.1"],
            @[@"iPhone14,3", @"iPhone 13 Pro Max", @"18.6.1"],
            @[@"iPhone14,7", @"iPhone 14",         @"18.6.1"],
            @[@"iPhone14,8", @"iPhone 14 Plus",    @"18.6.1"],
            @[@"iPhone15,2", @"iPhone 14 Pro",     @"18.6.1"],
            @[@"iPhone15,3", @"iPhone 14 Pro Max", @"26.0"],
            @[@"iPhone15,4", @"iPhone 15",         @"26.0"],
            @[@"iPhone15,5", @"iPhone 15 Plus",    @"26.0"],
            @[@"iPhone16,1", @"iPhone 15 Pro",     @"26.0.1"],
            @[@"iPhone16,2", @"iPhone 15 Pro Max", @"26.0.1"],
            @[@"iPhone17,3", @"iPhone 16",         @"26.0.1"],
            @[@"iPhone17,4", @"iPhone 16 Plus",    @"26.0.1"],
            @[@"iPhone17,1", @"iPhone 16 Pro",     @"26.0.1"],
            @[@"iPhone17,2", @"iPhone 16 Pro Max", @"26.0.1"],
        ];
    });
    return pool;
}

- (BOOL)hasDeviceProfile {
    return _deviceModel.length > 0;
}

- (void)regenerateDeviceProfile {
    NSArray<NSArray<NSString *> *> *pool = [GhostTokenStore devicePool];
    NSArray<NSString *> *pick = pool[arc4random_uniform((uint32_t)pool.count)];
    _deviceModel     = pick[0];
    _deviceModelName = pick[1];
    _systemVersion   = pick[2];
    _deviceName      = @"iPhone"; // iOS returns a generic name to unentitled apps anyway

    // Fresh per-device identifiers so nothing links back to the previous identity.
    _idfv      = [self generateUUIDUpper];
    _idfa      = [self generateUUIDUpper];
    _androidID = [self generateAndroidID];
    _deviceID  = [self generateUUIDLower]; // ig_did
    _xMID      = [self generateXMID];
    [self save];
    NSLog(@"[GhostTweak] New spoofed device: %@ (%@) iOS %@", _deviceModelName, _deviceModel, _systemVersion);
}

- (NSString *)deviceSummary {
    if (![self hasDeviceProfile]) return @"Not spoofed yet";
    return [NSString stringWithFormat:@"%@ · iOS %@",
            _deviceModelName.length ? _deviceModelName : _deviceModel,
            _systemVersion.length ? _systemVersion : @"?"];
}

- (NSString *)generateAndroidID {
    static NSString *hex = @"0123456789abcdef";
    NSMutableString *m = [NSMutableString stringWithString:@"android-"];
    for (int i = 0; i < 16; i++) {
        [m appendFormat:@"%C", [hex characterAtIndex:arc4random_uniform(16)]];
    }
    return m;
}

- (NSString *)generateUUIDUpper {
    return [[NSUUID UUID].UUIDString uppercaseString];
}

- (NSString *)generateUUIDLower {
    return [[NSUUID UUID].UUIDString lowercaseString];
}

- (NSString *)generateXMID {
    static NSString *abc = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSMutableString *m = [NSMutableString string];
    for (int i = 0; i < 28; i++) {
        [m appendFormat:@"%C", [abc characterAtIndex:arc4random_uniform((uint32_t)abc.length)]];
    }
    return m;
}

@end

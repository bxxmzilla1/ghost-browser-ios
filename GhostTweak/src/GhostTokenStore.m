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
    [self save];
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

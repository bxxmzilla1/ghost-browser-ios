#import "GBTokens.h"
#import <Security/Security.h>

@implementation GBTokens

static NSString *GBStr(id v) {
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [v stringValue];
    return nil;
}

// Pulls Authorization / IG-U-DS-USER-ID / X-IG-WWW-Claim out of one account's header dictionary,
// tolerating the header-name casing Instagram has used across versions.
static NSDictionary *GBHeaders(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSString *(^get)(NSArray *) = ^NSString *(NSArray *keys) {
        for (NSString *k in keys) {
            for (id kk in d) {
                if ([kk isKindOfClass:NSString.class] && [kk caseInsensitiveCompare:k] == NSOrderedSame) {
                    NSString *s = GBStr(d[kk]);
                    if (s.length) return s;
                }
            }
        }
        return nil;
    };
    NSString *auth  = get(@[@"Authorization", @"authorization"]);
    NSString *dsid  = get(@[@"IG-U-DS-USER-ID", @"ig-u-ds-user-id", @"ds_user_id"]);
    NSString *claim = get(@[@"X-IG-WWW-Claim", @"x-ig-www-claim"]);
    if (!auth && !dsid && !claim) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (auth)  out[@"auth"]  = auth;
    if (dsid)  out[@"dsid"]  = dsid;
    if (claim) out[@"claim"] = claim;
    return out;
}

+ (NSString *)deviceMid {
    id mid = [[NSUserDefaults standardUserDefaults] objectForKey:@"com.instagram.device.midheader"];
    NSString *s = GBStr(mid);
    if (s.length) return s;
    if ([mid isKindOfClass:NSDictionary.class]) {
        for (id v in [(NSDictionary *)mid allValues]) { NSString *vs = GBStr(v); if (vs.length) return vs; }
    }
    return nil;
}

+ (NSString *)instagramTokenBlob {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *mid = [self deviceMid] ?: @"";

    // Instagram keeps a userId → { headers } map under this key.
    id authObj = [ud objectForKey:@"com.instagram.users.authheaders"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    if ([authObj isKindOfClass:NSDictionary.class]) {
        NSDictionary *byUser = authObj;
        for (id userId in byUser) {
            NSDictionary *h = GBHeaders(byUser[userId]);
            if (!h) continue;
            NSString *dsid = h[@"dsid"] ?: GBStr(userId) ?: @"";
            [lines addObject:[NSString stringWithFormat:@"Authorization=%@; IG-U-DS-USER-ID=%@; X-MID=%@; X-IG-WWW-Claim=%@;",
                              h[@"auth"] ?: @"", dsid, mid, h[@"claim"] ?: @""]];
        }
        // Some builds store a single flat header dictionary rather than a per-user map.
        if (lines.count == 0) {
            NSDictionary *h = GBHeaders(byUser);
            if (h) [lines addObject:[NSString stringWithFormat:@"Authorization=%@; IG-U-DS-USER-ID=%@; X-MID=%@; X-IG-WWW-Claim=%@;",
                                     h[@"auth"] ?: @"", h[@"dsid"] ?: @"", mid, h[@"claim"] ?: @""]];
        }
    }

    if (lines.count == 0) {
        NSString *kc = [self keychainScan:mid];
        if (kc) [lines addObject:kc];
    }

    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

// Fallback: sweep the keychain for an Instagram Bearer token when it isn't in NSUserDefaults.
+ (NSString *)keychainScan:(NSString *)mid {
    NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                         (__bridge id)kSecReturnData: @YES,
                         (__bridge id)kSecReturnAttributes: @YES,
                         (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                         (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny };
    CFTypeRef res = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &res) != errSecSuccess || !res) return nil;
    NSArray *items = (__bridge_transfer NSArray *)res;

    NSMutableString *hay = [NSMutableString string];
    for (NSDictionary *it in items) {
        NSData *data = it[(__bridge id)kSecValueData];
        if (data.length) {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (s) [hay appendFormat:@"%@\n", s];
        }
    }
    if (hay.length == 0) return nil;

    NSString *auth = [self match:@"(Bearer\\s+IGT:2:[^\"'\\\\;\\s]+)" in:hay]
                  ?: [self match:@"(IGT:2:[^\"'\\\\;\\s]+)" in:hay];
    NSString *dsid = [self match:@"ds_user_id[\"'=:\\s]+([0-9]{3,})" in:hay]
                  ?: [self match:@"IG-U-DS-USER-ID[\"'=:\\s]+([0-9]{3,})" in:hay];
    NSString *claim = [self match:@"X-IG-WWW-Claim[\"'=:\\s]+(hmac[^\"'\\\\;\\s]+)" in:hay];
    if (!auth && !dsid) return nil;
    return [NSString stringWithFormat:@"Authorization=%@; IG-U-DS-USER-ID=%@; X-MID=%@; X-IG-WWW-Claim=%@;",
            auth ?: @"", dsid ?: @"", mid ?: @"", claim ?: @""];
}

+ (NSString *)match:(NSString *)pattern in:(NSString *)s {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    return [s substringWithRange:r];
}

@end

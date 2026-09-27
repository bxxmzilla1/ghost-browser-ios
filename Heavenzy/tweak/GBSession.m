#import "GBSession.h"
#import <WebKit/WebKit.h>

// Cookies that make up a usable Instagram web session. sessionid + ds_user_id + csrftoken are the
// essentials; mid / ig_did / rur round the header out and are harmless to include.
static NSArray<NSString *> *GBWantedCookies(void) {
    return @[ @"sessionid", @"ds_user_id", @"csrftoken", @"mid", @"ig_did", @"rur" ];
}

static BOOL GBIsInstagramDomain(NSString *domain) {
    NSString *d = domain.lowercaseString;
    return [d containsString:@"instagram.com"];
}

// Keep the wanted cookie with the longest value when the same name shows up for several domains
// (e.g. .instagram.com vs i.instagram.com) — the real session value is the non-empty, longer one.
static void GBMergeCookie(NSMutableDictionary *out, NSString *name, NSString *value) {
    if (!name || !value.length) return;
    NSString *lower = name.lowercaseString;
    if (![GBWantedCookies() containsObject:lower]) return;
    NSString *existing = out[lower];
    if (!existing || value.length > existing.length) out[lower] = value;
}

@implementation GBSession

+ (void)collectInstagramSession:(void (^)(NSDictionary<NSString *, NSString *> *))completion {
    NSMutableDictionary<NSString *, NSString *> *found = [NSMutableDictionary dictionary];

    // 1) Native networking cookies (what the Instagram app itself uses).
    for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies) {
        if (GBIsInstagramDomain(c.domain)) GBMergeCookie(found, c.name, c.value);
    }

    // 2) Embedded web-view cookies (WKWebView), which is async — merge then report on the main queue.
    void (^report)(void) = ^{
        NSMutableDictionary *result = [found mutableCopy];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    };

    WKHTTPCookieStore *store = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
    if (!store) { report(); return; }
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *c in cookies) if (GBIsInstagramDomain(c.domain)) GBMergeCookie(found, c.name, c.value);
        report();
    }];
}

+ (NSString *)cookieStringFrom:(NSDictionary<NSString *, NSString *> *)cookies {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name in GBWantedCookies()) {
        NSString *v = cookies[name];
        if (v.length) [parts addObject:[NSString stringWithFormat:@"%@=%@", name, v]];
    }
    return [parts componentsJoinedByString:@"; "];
}

@end

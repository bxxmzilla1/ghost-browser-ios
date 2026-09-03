#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <objc/runtime.h>
#import "GhostTokenStore.h"

static BOOL GhostHostMatches(NSString *host) {
    if (!host.length) return NO;
    host = host.lowercaseString;
    return [host isEqualToString:@"instagram.com"] || [host hasSuffix:@".instagram.com"] ||
           [host isEqualToString:@"i.instagram.com"] || [host hasSuffix:@".cdninstagram.com"];
}

#pragma mark - Cookie injection

void GhostInjectCookies(void) {
    GhostTokenStore *t = [GhostTokenStore shared];
    if (!t.injectCookies) return;

    NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    void (^set)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
        if (!value.length) return;
        NSDictionary *props = @{
            NSHTTPCookieName: name,
            NSHTTPCookieValue: value,
            NSHTTPCookieDomain: @".instagram.com",
            NSHTTPCookiePath: @"/",
            NSHTTPCookieSecure: @YES,
            NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow:60 * 60 * 24 * 365]
        };
        NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:props];
        if (c) [store setCookie:c];
    };

    set(@"sessionid", t.sessionid);
    set(@"ds_user_id", t.igUserID);
    set(@"csrftoken", t.csrftoken);
    set(@"mid", t.xMID);
    set(@"ig_did", t.deviceID);
    set(@"rur", t.rur);

    NSLog(@"[GhostTweak] Cookies injected (sessionid=%@ user=%@)",
          t.sessionid.length ? @"yes" : @"no", t.igUserID ?: @"-");
}

#pragma mark - Swizzle helper

static void GhostSwizzle(Class cls, SEL sel, IMP newImp, IMP *orig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

#pragma mark - NSMutableURLRequest

static void (*orig_setValue)(id, SEL, id, id);

static void hook_setValue(id self, SEL _cmd, id value, id field) {
    orig_setValue(self, _cmd, value, field);
    if (![self isKindOfClass:[NSMutableURLRequest class]]) return;
    NSMutableURLRequest *req = (NSMutableURLRequest *)self;
    if (!GhostHostMatches(req.URL.host)) return;
    GhostTokenStore *t = [GhostTokenStore shared];
    for (NSString *key in [t requestHeaders]) {
        if (![req valueForHTTPHeaderField:key].length) {
            [req setValue:t.requestHeaders[key] forHTTPHeaderField:key];
        }
    }
}

#pragma mark - IDFA / IDFV

static NSUUID *(*orig_adID)(id, SEL);
static NSUUID *hook_adID(id self, SEL _cmd) {
    NSString *idfa = [GhostTokenStore shared].idfa;
    if (idfa.length) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:idfa];
        if (u) return u;
    }
    return orig_adID ? orig_adID(self, _cmd) : [[NSUUID UUID] init];
}

static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *hook_idfv(id self, SEL _cmd) {
    NSString *idfv = [GhostTokenStore shared].idfv;
    if (idfv.length) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:idfv];
        if (u) return u;
    }
    return orig_idfv(self, _cmd);
}

void GhostInstallHooks(void) {
    GhostSwizzle([NSMutableURLRequest class], @selector(setValue:forHTTPHeaderField:),
                 (IMP)hook_setValue, (IMP *)&orig_setValue);

    Class asim = NSClassFromString(@"ASIdentifierManager");
    if (asim) {
        GhostSwizzle(asim, @selector(advertisingIdentifier), (IMP)hook_adID, (IMP *)&orig_adID);
    }
    GhostSwizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);

    NSLog(@"[GhostTweak] Hooks installed (runtime swizzle)");
}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CFNetwork/CFNetwork.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>
#import <errno.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
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

#pragma mark - UIDevice model / name / system version

static NSString *(*orig_sysVersion)(id, SEL);
static NSString *hook_sysVersion(id self, SEL _cmd) {
    NSString *v = [GhostTokenStore shared].systemVersion;
    return v.length ? v : (orig_sysVersion ? orig_sysVersion(self, _cmd) : @"18.0");
}

static NSString *(*orig_devName)(id, SEL);
static NSString *hook_devName(id self, SEL _cmd) {
    NSString *v = [GhostTokenStore shared].deviceName;
    return v.length ? v : (orig_devName ? orig_devName(self, _cmd) : @"iPhone");
}

#pragma mark - C-level hardware model (sysctlbyname / uname) via dyld interpose

// Instagram reads the hardware string ("iPhone16,1") through the C sysctl/uname APIs, not
// Obj-C, so those are interposed here. Calls for hw.machine/hw.model are answered from the
// spoofed profile; everything else is forwarded to the real implementation via RTLD_NEXT.

static BOOL GhostSpoofSysctlName(const char *name) {
    return name && (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0);
}

static int GhostFillBuf(const char *val, void *oldp, size_t *oldlenp) {
    size_t len = strlen(val) + 1;
    if (oldlenp && !oldp) { *oldlenp = len; return 0; }   // size query
    if (oldp && oldlenp) {
        if (*oldlenp < len) { errno = ENOMEM; return -1; }
        memcpy(oldp, val, len);
        *oldlenp = len;
        return 0;
    }
    return 0;
}

int ghost_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    static int (*real)(const char *, void *, size_t *, void *, size_t);
    if (!real) real = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_NEXT, "sysctlbyname");
    if (GhostSpoofSysctlName(name)) {
        NSString *model = [GhostTokenStore shared].deviceModel;
        if (model.length) return GhostFillBuf(model.UTF8String, oldp, oldlenp);
    }
    return real(name, oldp, oldlenp, newp, newlen);
}

int ghost_uname(struct utsname *buf) {
    static int (*real)(struct utsname *);
    if (!real) real = (int (*)(struct utsname *))dlsym(RTLD_NEXT, "uname");
    int r = real(buf);
    NSString *model = [GhostTokenStore shared].deviceModel;
    if (r == 0 && buf && model.length) {
        strlcpy(buf->machine, model.UTF8String, sizeof(buf->machine));
    }
    return r;
}

__attribute__((used)) static struct { const void *replacement; const void *replacee; }
_ghost_interpose_sysctlbyname __attribute__((section("__DATA,__interpose"))) =
    { (const void *)ghost_sysctlbyname, (const void *)sysctlbyname };

__attribute__((used)) static struct { const void *replacement; const void *replacee; }
_ghost_interpose_uname __attribute__((section("__DATA,__interpose"))) =
    { (const void *)ghost_uname, (const void *)uname };

void GhostInstallHooks(void) {
    GhostSwizzle([NSMutableURLRequest class], @selector(setValue:forHTTPHeaderField:),
                 (IMP)hook_setValue, (IMP *)&orig_setValue);

    Class asim = NSClassFromString(@"ASIdentifierManager");
    if (asim) {
        GhostSwizzle(asim, @selector(advertisingIdentifier), (IMP)hook_adID, (IMP *)&orig_adID);
    }
    GhostSwizzle([UIDevice class], @selector(identifierForVendor), (IMP)hook_idfv, (IMP *)&orig_idfv);
    GhostSwizzle([UIDevice class], @selector(systemVersion), (IMP)hook_sysVersion, (IMP *)&orig_sysVersion);
    GhostSwizzle([UIDevice class], @selector(name), (IMP)hook_devName, (IMP *)&orig_devName);

    NSLog(@"[GhostTweak] Hooks installed (device spoof active: %@)",
          [GhostTokenStore shared].deviceSummary);
}

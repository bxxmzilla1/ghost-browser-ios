#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <string.h>
#import <errno.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <substrate.h>
#import "GBStore.h"
#import "GBMenu.h"
#import "GBFloatingButton.h"
#import "HZConfig.h"

// Plain-C mirror of the state, read by the ultra-early sysctl/uname/MGCopyAnswer hooks. These run
// before/around libSystem init and MUST NOT touch Objective-C (a dispatch_once re-entry there
// deadlocks), so the spoofed values are copied into C buffers once in the constructor.
static int                gEnabled = 0;
static char               gModel[64] = {0};
static char               gUDID[64] = {0};
static char               gSerial[32] = {0};
static int32_t            gCores = 0;     // hw.ncpu / processorCount
static int64_t            gMem   = 0;     // hw.memsize (bytes)

#pragma mark - C-level hardware (hw.machine / hw.model / hw.ncpu / hw.memsize)

// Copies a fixed-width integer sysctl value out (matching sysctlbyname's contract for size queries
// and short buffers). Returns 1 if it handled the call.
static int GBCopyInt(void *oldp, size_t *oldlenp, const void *val, size_t vlen) {
    if (oldlenp && !oldp) { *oldlenp = vlen; return 1; }             // size query
    if (oldp && oldlenp) {
        if (*oldlenp < vlen) { errno = ENOMEM; return 1; }
        memcpy(oldp, val, vlen);
        *oldlenp = vlen;
        return 1;
    }
    return 0;
}

%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (gEnabled && name && !newp) {
        if (gModel[0] && (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0)) {
            size_t len = strlen(gModel) + 1;
            if (oldlenp && !oldp) { *oldlenp = len; return 0; }      // size query
            if (oldp && oldlenp) {
                if (*oldlenp < len) { errno = ENOMEM; return -1; }
                memcpy(oldp, gModel, len);
                *oldlenp = len;
                return 0;
            }
        }
        // CPU counts (all report the spoofed core count so nothing contradicts the model).
        if (gCores > 0 && (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0 ||
                           strcmp(name, "hw.physicalcpu") == 0 || strcmp(name, "hw.physicalcpu_max") == 0 ||
                           strcmp(name, "hw.logicalcpu") == 0 || strcmp(name, "hw.logicalcpu_max") == 0)) {
            if (GBCopyInt(oldp, oldlenp, &gCores, sizeof(gCores))) return 0;
        }
        // Physical memory.
        if (gMem > 0 && strcmp(name, "hw.memsize") == 0) {
            if (GBCopyInt(oldp, oldlenp, &gMem, sizeof(gMem))) return 0;
        }
    }
    return %orig;
}

%hookf(int, uname, struct utsname *buf) {
    int r = %orig;
    if (r == 0 && buf && gEnabled && gModel[0]) {
        strlcpy(buf->machine, gModel, sizeof(buf->machine));
    }
    return r;
}

#pragma mark - MobileGestalt (UDID + serial — the cross-install hardware identifiers)

// libMobileGestalt is where UniqueDeviceID (UDID) and SerialNumber really come from; they persist
// across app deletes and iCloud restores, so spoofing them here is what breaks a "we've seen this
// hardware before" match. Hooked with MSHookFunction because MGCopyAnswer is a private symbol.
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef gb_MGCopyAnswer(CFStringRef key) {
    if (gEnabled && key) {
        if (gUDID[0] && CFStringCompare(key, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gUDID, kCFStringEncodingUTF8);   // +1, caller releases
        if (gSerial[0] && CFStringCompare(key, CFSTR("SerialNumber"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gSerial, kCFStringEncodingUTF8);
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
}

#pragma mark - Block iCloud (so wiped accounts can't be restored from the cloud)

// Instagram's "saved accounts" come back because they are mirrored to the iCloud key-value store
// and iCloud Keychain. While spoofing is on we make the cloud store look permanently empty and
// swallow writes, so a wiped device stays wiped and nothing syncs back.
%hook NSUbiquitousKeyValueStore

- (id)objectForKey:(NSString *)key {
    if (gEnabled) return nil;
    return %orig;
}
- (NSString *)stringForKey:(NSString *)key {
    if (gEnabled) return nil;
    return %orig;
}
- (NSArray *)arrayForKey:(NSString *)key {
    if (gEnabled) return nil;
    return %orig;
}
- (NSDictionary *)dictionaryForKey:(NSString *)key {
    if (gEnabled) return nil;
    return %orig;
}
- (NSData *)dataForKey:(NSString *)key {
    if (gEnabled) return nil;
    return %orig;
}
- (NSDictionary *)dictionaryRepresentation {
    if (gEnabled) return @{};
    return %orig;
}
- (void)setObject:(id)obj forKey:(NSString *)key {
    if (gEnabled) return;
    %orig;
}
- (void)setString:(NSString *)s forKey:(NSString *)key {
    if (gEnabled) return;
    %orig;
}
- (void)setData:(NSData *)d forKey:(NSString *)key {
    if (gEnabled) return;
    %orig;
}
- (void)setArray:(NSArray *)a forKey:(NSString *)key {
    if (gEnabled) return;
    %orig;
}
- (void)setDictionary:(NSDictionary *)d forKey:(NSString *)key {
    if (gEnabled) return;
    %orig;
}
- (BOOL)synchronize {
    if (gEnabled) return YES;
    return %orig;
}

%end

// Hide the iCloud (ubiquity) container entirely, so file-based iCloud state is invisible too.
%hook NSFileManager
- (NSURL *)URLForUbiquityContainerIdentifier:(NSString *)identifier {
    if (gEnabled) return nil;
    return %orig;
}
%end

#pragma mark - UIDevice

%hook UIDevice

- (NSString *)systemVersion {
    if (!gEnabled) return %orig;
    NSString *v = [GBStore shared].systemVersion;
    return v.length ? v : %orig;
}

- (NSString *)name {
    if (!gEnabled) return %orig;
    NSString *v = [GBStore shared].deviceName;
    return v.length ? v : %orig;
}

- (NSUUID *)identifierForVendor {
    if (!gEnabled) return %orig;
    NSString *s = [GBStore shared].idfv;
    NSUUID *u = s.length ? [[NSUUID alloc] initWithUUIDString:s] : nil;
    return u ?: %orig;
}

- (float)batteryLevel {
    if (gEnabled) return (float)[GBStore shared].batteryLevel;
    return %orig;
}
- (long long)batteryState {
    // UIDeviceBatteryState: 1 = unplugged, 2 = charging.
    if (gEnabled) return [GBStore shared].batteryCharging ? 2 : 1;
    return %orig;
}

%end

#pragma mark - IDFA (AdSupport, weak-linked)

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (!gEnabled) return %orig;
    NSString *s = [GBStore shared].idfa;
    NSUUID *u = s.length ? [[NSUUID alloc] initWithUUIDString:s] : nil;
    return u ?: %orig;
}

%end

#pragma mark - CPU / memory (NSProcessInfo, bound to the spoofed device)

%hook NSProcessInfo

- (NSUInteger)processorCount {
    if (gEnabled && gCores > 0) return (NSUInteger)gCores;
    return %orig;
}
- (NSUInteger)activeProcessorCount {
    if (gEnabled && gCores > 0) return (NSUInteger)gCores;
    return %orig;
}
- (unsigned long long)physicalMemory {
    if (gEnabled && gMem > 0) return (unsigned long long)gMem;
    return %orig;
}

// operatingSystemVersion / …String leak the real iOS otherwise. Keep them aligned with UIDevice.
- (NSOperatingSystemVersion)operatingSystemVersion {
    if (gEnabled) {
        NSString *v = [GBStore shared].systemVersion;
        NSArray<NSString *> *parts = [v componentsSeparatedByString:@"."];
        if (parts.count >= 1) {
            NSOperatingSystemVersion o;
            o.majorVersion = parts.count > 0 ? parts[0].integerValue : 0;
            o.minorVersion = parts.count > 1 ? parts[1].integerValue : 0;
            o.patchVersion = parts.count > 2 ? parts[2].integerValue : 0;
            return o;
        }
    }
    return %orig;
}

%end

#pragma mark - Carrier (CoreTelephony, weak-linked)

%hook CTCarrier
- (NSString *)carrierName {
    if (gEnabled) { NSString *v = [GBStore shared].carrierName; if (v.length) return v; }
    return %orig;
}
- (NSString *)mobileCountryCode {
    if (gEnabled) { NSString *v = [GBStore shared].mcc; if (v.length) return v; }
    return %orig;
}
- (NSString *)mobileNetworkCode {
    if (gEnabled) { NSString *v = [GBStore shared].mnc; if (v.length) return v; }
    return %orig;
}
- (NSString *)isoCountryCode {
    if (gEnabled) { NSString *v = [GBStore shared].isoCountryCode; if (v.length) return v; }
    return %orig;
}
%end

#pragma mark - Time zone (kept region-coherent with the carrier; never changes app language)

%hook NSTimeZone
+ (NSTimeZone *)systemTimeZone {
    if (gEnabled) { NSString *n = [GBStore shared].timeZoneName; NSTimeZone *z = n.length ? [NSTimeZone timeZoneWithName:n] : nil; if (z) return z; }
    return %orig;
}
+ (NSTimeZone *)localTimeZone {
    if (gEnabled) { NSString *n = [GBStore shared].timeZoneName; NSTimeZone *z = n.length ? [NSTimeZone timeZoneWithName:n] : nil; if (z) return z; }
    return %orig;
}
+ (NSTimeZone *)defaultTimeZone {
    if (gEnabled) { NSString *n = [GBStore shared].timeZoneName; NSTimeZone *z = n.length ? [NSTimeZone timeZoneWithName:n] : nil; if (z) return z; }
    return %orig;
}
%end

#pragma mark - Locale (region-coherent; pool is en_* so app language is unchanged)

%hook NSLocale
+ (NSLocale *)currentLocale {
    if (gEnabled) { NSString *l = [GBStore shared].localeId; if (l.length) return [NSLocale localeWithLocaleIdentifier:l]; }
    return %orig;
}
+ (NSLocale *)autoupdatingCurrentLocale {
    if (gEnabled) { NSString *l = [GBStore shared].localeId; if (l.length) return [NSLocale localeWithLocaleIdentifier:l]; }
    return %orig;
}
%end

#pragma mark - Screen (native pixel size + scale, so it matches the spoofed model)

// Only the *pixel-space* getters are spoofed (nativeBounds/nativeScale). The point-space bounds and
// scale that UIKit lays the app out with are left untouched, so nothing misrenders — but the values
// apps read to build "1179x2556 scale=3.00" style device strings now agree with the model.
%hook UIScreen

- (CGRect)nativeBounds {
    if (gEnabled) {
        GBStore *s = [GBStore shared];
        if (s.nativePixelsW > 0 && s.nativePixelsH > 0)
            return CGRectMake(0, 0, s.nativePixelsW, s.nativePixelsH);
    }
    return %orig;
}
- (CGFloat)nativeScale {
    if (gEnabled) {
        NSInteger sc = [GBStore shared].scaleFactor;
        if (sc > 0) return (CGFloat)sc;
    }
    return %orig;
}

%end

#pragma mark - "Previously downloaded" / returning-device signals

// Some apps can tell a device installed the app before — even after a delete + reinstall from the
// user's Apple ID / iCloud — because DeviceCheck (2 persistent bits per device per developer) and
// App Attest survive uninstall and iCloud restore. There is no way to mint a *valid but different*
// DeviceCheck token on-device, so when spoofing is on we make these services report "unsupported"
// and fail token generation. The app then falls back to signals we already spoof (IDFV, keychain,
// iCloud KV — all reset by wipe), and can't recognise the device as one it has seen.

%hook DCDevice
- (BOOL)isSupported {
    if (gEnabled) return NO;
    return %orig;
}
- (void)generateTokenWithCompletionHandler:(void (^)(NSData *, NSError *))completion {
    if (gEnabled) {
        if (completion) completion(nil, [NSError errorWithDomain:@"com.apple.devicecheck.error" code:1 userInfo:nil]);
        return;
    }
    %orig;
}
%end

%hook DCAppAttestService
- (BOOL)isSupported {
    if (gEnabled) return NO;
    return %orig;
}
%end

#pragma mark - In-app menu gesture (two-finger long-press on the key window)

@interface GBGestureTarget : NSObject
+ (instancetype)shared;
- (void)handle:(UILongPressGestureRecognizer *)g;
@end

@implementation GBGestureTarget
+ (instancetype)shared {
    static GBGestureTarget *t; static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [GBGestureTarget new]; });
    return t;
}
- (void)handle:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [GBMenu presentFromWindow:(UIWindow *)g.view];
}
@end

static void GBInstallGesture(void) {
    UIWindow *key = nil, *anyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!anyWindow) anyWindow = w;
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) key = anyWindow;
    if (!key) return;
    // Always-on-top draggable bubble that opens the panel with one tap.
    [GBFloatingButton installInScene:key.windowScene];
    // Avoid stacking recognizers if the window becomes active repeatedly.
    for (UIGestureRecognizer *r in key.gestureRecognizers) {
        if ([r.name isEqualToString:@"HeavenzyMenu"]) return;
    }
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[GBGestureTarget shared] action:@selector(handle:)];
    lp.numberOfTouchesRequired = 2;
    lp.minimumPressDuration = 0.8;
    lp.name = @"HeavenzyMenu";
    lp.cancelsTouchesInView = NO;
    [key addGestureRecognizer:lp];
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        NSLog(@"[Heavenzy] Loading v1.0");
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Never touch system processes (SpringBoard, Preferences, daemons using UIKit) or our own
        // control app (which links UIKit and would otherwise match the filter).
        if (!bundleID || [bundleID hasPrefix:@"com.apple."] || [bundleID isEqualToString:@"com.heavenzy.app"]) return;

        // Honour an "Erase App Data" request queued by the Heavenzy control app for this bundle.
        [HZConfig grantSandboxAccess];
        if ([HZConfig wipePendingForApp:bundleID]) {
            [GBMenu clearAppData];
            [HZConfig setWipePending:NO forApp:bundleID];
        }

        GBStore *store = [GBStore shared];
        gEnabled = store.enabled ? 1 : 0;
        if (gEnabled) {
            if (!store.hasIdentity) [store regenerateIdentity];
            const char *m = store.deviceModel.UTF8String;
            if (m) strlcpy(gModel, m, sizeof(gModel));
            const char *u = store.udid.UTF8String;
            if (u) strlcpy(gUDID, u, sizeof(gUDID));
            const char *s = store.serialNumber.UTF8String;
            if (s) strlcpy(gSerial, s, sizeof(gSerial));
            gCores = (int32_t)store.cpuCores;
            gMem   = (int64_t)store.memoryBytes;
            NSLog(@"[Heavenzy] Active in %@ → %@", bundleID, store.summary);
        }

        %init;

        // MobileGestalt is only worth hooking when we actually have spoofed values to serve.
        if (gEnabled && (gUDID[0] || gSerial[0])) {
            void *mg = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
            if (mg) MSHookFunction(mg, (void *)gb_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
        }

        // The menu is always available (even when spoofing is off) so the user can opt this app in.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            GBInstallGesture();
        }];
        // In case the app is already active by the time we load.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GBInstallGesture();
        });
    }
}

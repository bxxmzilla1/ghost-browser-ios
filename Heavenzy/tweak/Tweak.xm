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

// Plain-C mirror of the identity, read by the ultra-early MGCopyAnswer hook. It runs before/around
// libSystem init and MUST NOT touch Objective-C (a dispatch_once re-entry there deadlocks), so the
// values are copied into C buffers once in the constructor.
//
// Heavenzy keeps the REAL iPhone (model, screen, CPU, RAM, iOS, carrier, time zone are all left
// alone) and only resets the per-device identity below, so an app sees a brand-new phone.
static int                gEnabled = 0;
static char               gUDID[64] = {0};
static char               gSerial[32] = {0};
static char               gWifi[24] = {0};
static char               gBluetooth[24] = {0};
static char               gIMEI[20] = {0};

#pragma mark - MobileGestalt (the cross-install hardware identifiers)

// libMobileGestalt is where UniqueDeviceID (UDID), SerialNumber, WifiAddress, BluetoothAddress and
// the IMEI really come from; they persist across app deletes and iCloud restores, so resetting them
// here is what makes the phone look brand new. Hooked with MSHookFunction (MGCopyAnswer is private).
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef gb_MGCopyAnswer(CFStringRef key) {
    if (gEnabled && key) {
        if (gUDID[0] && CFStringCompare(key, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gUDID, kCFStringEncodingUTF8);   // +1, caller releases
        if (gSerial[0] && CFStringCompare(key, CFSTR("SerialNumber"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gSerial, kCFStringEncodingUTF8);
        if (gWifi[0] && CFStringCompare(key, CFSTR("WifiAddress"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gWifi, kCFStringEncodingUTF8);
        if (gBluetooth[0] && CFStringCompare(key, CFSTR("BluetoothAddress"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gBluetooth, kCFStringEncodingUTF8);
        if (gIMEI[0] && CFStringCompare(key, CFSTR("InternationalMobileEquipmentIdentity"), 0) == kCFCompareEqualTo)
            return CFStringCreateWithCString(NULL, gIMEI, kCFStringEncodingUTF8);
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

#pragma mark - UIDevice (identity only — real hardware is left alone)

%hook UIDevice

- (NSString *)name {
    // A brand-new phone is just "iPhone" (drops an identifying "<user>'s iPhone").
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

        // Try to reach the central store too (only works if libSandy happens to be installed); the
        // primary path is the per-app config the control app writes straight into this container.
        [HZConfig grantSandboxAccess];

        GBStore *store = [GBStore shared];

        // Honour an "Erase App Data" request queued by the Heavenzy control app — either written into
        // this app's own container (store.wipePending) or in the central plist (libSandy).
        if (store.wipePending || [HZConfig wipePendingForApp:bundleID]) {
            [GBMenu clearAppData];               // deletes our container plist too…
            store.wipePending = NO;
            [store save];                        // …so rewrite it (keeps identity + enabled)
            [HZConfig setWipePending:NO forApp:bundleID];
        }
        gEnabled = store.enabled ? 1 : 0;
        if (gEnabled) {
            if (!store.hasIdentity) [store regenerateIdentity];
            const char *u = store.udid.UTF8String;         if (u) strlcpy(gUDID, u, sizeof(gUDID));
            const char *s = store.serialNumber.UTF8String; if (s) strlcpy(gSerial, s, sizeof(gSerial));
            const char *w = store.wifiAddress.UTF8String;  if (w) strlcpy(gWifi, w, sizeof(gWifi));
            const char *b = store.bluetoothAddress.UTF8String; if (b) strlcpy(gBluetooth, b, sizeof(gBluetooth));
            const char *im = store.imei.UTF8String;        if (im) strlcpy(gIMEI, im, sizeof(gIMEI));
            NSLog(@"[Heavenzy] Active in %@ → %@", bundleID, store.summary);
        }

        %init;

        // MobileGestalt is only worth hooking when we actually have identifiers to serve.
        if (gEnabled && (gUDID[0] || gSerial[0] || gWifi[0] || gBluetooth[0] || gIMEI[0])) {
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

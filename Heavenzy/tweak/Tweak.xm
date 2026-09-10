#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>
#import "GBStore.h"
#import "GBMenu.h"
#import "GBOverlay.h"
#import "HZConfig.h"

// Heavenzy keeps the REAL iPhone (model, screen, CPU, RAM, iOS, carrier, time zone are all left
// alone) and only resets the per-device identity, so an app sees a brand-new phone.
//
// NOTE: we do NOT hook the private C function MGCopyAnswer. Doing so requires an inline (function)
// hook, which activates ellekit's Mach exception handler; in apps that ship their own crash reporter
// (Instagram/Facebook use Breakpad) the two exception handlers collide and the kernel kills the app
// with EXC_GUARD (ILLEGAL_MOVE on a mach port) on launch. It's also unnecessary: on stock iOS the
// serial / UDID / Wi-Fi MAC / IMEI MobileGestalt keys are entitlement-gated and already return null
// to sandboxed apps, so a normal phone never exposes them. IDFV/IDFA (below, plain Obj-C swizzles)
// plus the data wipe are what actually make an app treat the device as brand new.
static int gEnabled = 0;

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

#pragma mark - SMS panel + re-show gesture (two-finger long-press on the key window)

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
// Brings the SMS panel back after it was closed with its X.
- (void)handle:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [GBOverlay toggle];
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
    // Persistent draggable SMS panel (bottom of the screen, touches outside it pass through).
    [GBOverlay installInScene:key.windowScene];
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
            NSLog(@"[Heavenzy] Active in %@ → %@", bundleID, store.summary);
        }

        // Only Objective-C method swizzles below (IDFV/IDFA/name/DeviceCheck/iCloud). No inline C
        // hooks — that's what avoids ellekit's exception handler colliding with the app's crash
        // reporter (the EXC_GUARD launch crash on Instagram/Facebook).
        %init;

        // The SMS panel is available in every app (even when spoofing is off). Re-assert on every
        // activation (the panel itself is only created once per scene)…
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            GBInstallGesture();
        }];
        // …and retry a few times after launch, because the app's key window/scene often isn't ready
        // the instant the tweak loads.
        for (NSNumber *delay in @[ @0.5, @1.5, @3.0, @5.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                GBInstallGesture();
            });
        }
    }
}

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

// DIAGNOSTIC: log every DeviceCheck / App Attest call so we can see whether the host app (e.g.
// Instagram) actually uses these APIs during signup / SMS verification. Grep the device log for
// "[Heavenzy][DeviceCheck]". If nothing appears while requesting an SMS code, DeviceCheck/App Attest
// is NOT involved and can be ruled out as the reason codes don't arrive.
%hook DCDevice
- (BOOL)isSupported {
    BOOL orig = %orig;
    NSLog(@"[Heavenzy][DeviceCheck] DCDevice.isSupported called (real=%d, spoofing=%d → returning %d)",
          orig, gEnabled, gEnabled ? 0 : orig);
    if (gEnabled) return NO;
    return orig;
}
- (void)generateTokenWithCompletionHandler:(void (^)(NSData *, NSError *))completion {
    NSLog(@"[Heavenzy][DeviceCheck] DCDevice.generateToken called (spoofing=%d → %@)",
          gEnabled, gEnabled ? @"failing token" : @"passing through");
    if (gEnabled) {
        if (completion) completion(nil, [NSError errorWithDomain:@"com.apple.devicecheck.error" code:1 userInfo:nil]);
        return;
    }
    %orig;
}
%end

%hook DCAppAttestService
- (BOOL)isSupported {
    BOOL orig = %orig;
    NSLog(@"[Heavenzy][DeviceCheck] DCAppAttestService.isSupported called (real=%d, spoofing=%d → returning %d)",
          orig, gEnabled, gEnabled ? 0 : orig);
    if (gEnabled) return NO;
    return orig;
}
- (void)generateKeyWithCompletionHandler:(void (^)(NSString *, NSError *))completion {
    NSLog(@"[Heavenzy][DeviceCheck] DCAppAttestService.generateKey called (spoofing=%d, pass-through)", gEnabled);
    %orig;
}
- (void)attestKey:(NSString *)keyId clientDataHash:(NSData *)hash completionHandler:(void (^)(NSData *, NSError *))completion {
    NSLog(@"[Heavenzy][DeviceCheck] DCAppAttestService.attestKey called (spoofing=%d, pass-through)", gEnabled);
    %orig;
}
- (void)generateAssertion:(NSString *)keyId clientDataHash:(NSData *)hash completionHandler:(void (^)(NSData *, NSError *))completion {
    NSLog(@"[Heavenzy][DeviceCheck] DCAppAttestService.generateAssertion called (spoofing=%d, pass-through)", gEnabled);
    %orig;
}
%end

#pragma mark - SpringBoard: AppData-style icon renames + badge overrides

// The Heavenzy control app can't touch SpringBoard's UI, so it records custom home-screen names and
// badge counts in springboard.plist and pings us. These hooks are only %init'd inside SpringBoard
// (see %ctor), and are plain Obj-C method swizzles — no inline C hooks — so they can't trigger the
// ellekit/crash-reporter collision that plagued MGCopyAnswer.

// Minimal private interfaces (resolved at runtime; never linked).
@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)displayName;
@end
@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bid;
@end

// Push every badge override in springboard.plist onto its SBApplication.
static void HZApplyBadges(void) {
    @try {
        Class ctrlClass = NSClassFromString(@"SBApplicationController");
        id ctrl = [ctrlClass respondsToSelector:@selector(sharedInstance)] ? [ctrlClass sharedInstance] : nil;
        if (!ctrl) return;
        NSDictionary<NSString *, NSNumber *> *badges = [HZConfig allBadges];
        for (NSString *bid in badges) {
            NSNumber *val = badges[bid];
            if (![val isKindOfClass:NSNumber.class]) continue;
            id app = [ctrl applicationWithBundleIdentifier:bid];
            if (!app) continue;
            if ([app respondsToSelector:@selector(setBadgeValue:)])
                [app performSelector:@selector(setBadgeValue:) withObject:val];
            else if ([app respondsToSelector:@selector(setBadge:)])
                [app performSelector:@selector(setBadge:) withObject:(val.integerValue ? val.stringValue : nil)];
            else if ([app respondsToSelector:@selector(setBadgeNumberOrString:)])
                [app performSelector:@selector(setBadgeNumberOrString:) withObject:val];
        }
    } @catch (__unused NSException *e) {}
}

// Force visible icon labels to re-query displayName so a rename shows without a full respring.
static void HZReloadIconLabels(void) {
    @try {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count) {
                    UIView *v = stack.lastObject; [stack removeLastObject];
                    if ([v respondsToSelector:@selector(_updateLabel)]) [v performSelector:@selector(_updateLabel)];
                    [stack addObjectsFromArray:v.subviews];
                }
            }
        }
    } @catch (__unused NSException *e) {}
}

%group SpringBoardHooks

%hook SBApplication
- (NSString *)displayName {
    @try {
        if ([self respondsToSelector:@selector(bundleIdentifier)]) {
            NSString *custom = [HZConfig customNameForApp:[self bundleIdentifier]];
            if (custom.length) return custom;
        }
    } @catch (__unused NSException *e) {}
    return %orig;
}
%end

%end   // SpringBoardHooks

// Darwin callback: control app changed a name/badge → re-read and re-apply on the main thread.
static void HZSpringBoardReload(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef ui) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HZApplyBadges();
        HZReloadIconLabels();
    });
}

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
// Two-finger long-press is the only way the SMS panel appears; its X closes it again.
- (void)handle:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIWindowScene *scene = g.view.window.windowScene ?: ((UIWindow *)g.view).windowScene;
    [GBOverlay showInScene:scene];
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

        // SpringBoard gets its own, separate set of hooks (AppData-style icon renames + badge counts).
        // Nothing else here (identity spoofing / SMS panel) should run in SpringBoard.
        if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            [HZConfig grantSandboxAccess];
            %init(SpringBoardHooks);
            // Apply any pending badges shortly after launch (once the icon model is up)…
            for (NSNumber *delay in @[ @2.0, @5.0 ]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    HZApplyBadges();
                });
            }
            // …and re-apply whenever the control app pings us.
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, HZSpringBoardReload,
                                            CFSTR("com.heavenzy.springboard.reload"), NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
            return;
        }

        // Never touch other system processes (Preferences, daemons using UIKit) or our own control
        // app (which links UIKit and would otherwise match the filter).
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

        // The two-finger long-press (opens the SMS panel) is armed in every app, even when spoofing
        // is off. Re-arm on every activation…
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

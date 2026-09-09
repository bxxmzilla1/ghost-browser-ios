#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string.h>
#import <errno.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import "GBStore.h"
#import "GBMenu.h"

// Plain-C mirror of the state, read by the ultra-early sysctl/uname hooks. These run before/around
// libSystem init and MUST NOT touch Objective-C (a dispatch_once re-entry there deadlocks), so the
// spoofed model is copied into a C buffer once in the constructor and the hooks only read it.
static int  gEnabled = 0;
static char gModel[64] = {0};

#pragma mark - C-level hardware model (hw.machine / hw.model)

%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (gEnabled && gModel[0] && name &&
        (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0)) {
        size_t len = strlen(gModel) + 1;
        if (oldlenp && !oldp) { *oldlenp = len; return 0; }          // size query
        if (oldp && oldlenp) {
            if (*oldlenp < len) { errno = ENOMEM; return -1; }
            memcpy(oldp, gModel, len);
            *oldlenp = len;
            return 0;
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
        // Never touch system processes (SpringBoard, Preferences, daemons using UIKit).
        if (!bundleID || [bundleID hasPrefix:@"com.apple."]) return;

        GBStore *store = [GBStore shared];
        gEnabled = store.enabled ? 1 : 0;
        if (gEnabled) {
            if (!store.hasIdentity) [store regenerateIdentity];
            const char *m = store.deviceModel.UTF8String;
            if (m) strlcpy(gModel, m, sizeof(gModel));
            NSLog(@"[Heavenzy] Active in %@ → %@", bundleID, store.summary);
        }

        %init;

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

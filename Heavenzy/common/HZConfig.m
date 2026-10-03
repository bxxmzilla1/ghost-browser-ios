#import "HZConfig.h"
#import <dlfcn.h>

@implementation HZConfig

+ (NSString *)directory { return @"/var/mobile/Library/Preferences/Heavenzy"; }
+ (NSString *)appsPlistPath { return [[self directory] stringByAppendingPathComponent:@"apps.plist"]; }

static int gHZSandyStatus = -1;   // -1 = libSandy not loaded, else libSandy_applyProfile's return (0 = success)

+ (void)grantSandboxAccess {
    // libSandy_applyProfile("Heavenzy") — resolved at runtime so a missing libSandy never breaks load.
    static dispatch_once_t once; dispatch_once(&once, ^{
        void *h = dlopen("/var/jb/usr/lib/libSandy.dylib", RTLD_LAZY) ?: dlopen("libSandy.dylib", RTLD_LAZY);
        if (!h) { NSLog(@"[Heavenzy][libSandy] libSandy.dylib not found — cross-sandbox access unavailable"); return; }
        int (*applyProfile)(const char *) = (int (*)(const char *))dlsym(h, "libSandy_applyProfile");
        if (!applyProfile) return;
        gHZSandyStatus = applyProfile("Heavenzy");
        // 0 = success, 1 = XPC failure (sandyd not reachable), 2 = restricted (profile missing/denied)
        NSLog(@"[Heavenzy][libSandy] applyProfile(\"Heavenzy\") → %d (%@)", gHZSandyStatus,
              gHZSandyStatus == 0 ? @"granted" : gHZSandyStatus == 1 ? @"sandyd unreachable" : @"profile not found or not allowed");
    });
}

+ (BOOL)sandboxAccessGranted { return gHZSandyStatus == 0; }

+ (NSString *)sandboxAccessDescription {
    switch (gHZSandyStatus) {
        case 0:  return @"granted";
        case 1:  return @"libSandy daemon (sandyd) not reachable";
        case 2:  return @"libSandy profile missing or not allowed";
        default: return @"libSandy not installed";
    }
}

+ (NSDictionary *)all {
    return [NSDictionary dictionaryWithContentsOfFile:[self appsPlistPath]] ?: @{};
}

+ (NSDictionary *)entryForApp:(NSString *)bundleId {
    if (bundleId.length == 0) return nil;
    id e = [self all][bundleId];
    return [e isKindOfClass:NSDictionary.class] ? e : nil;
}

+ (BOOL)isEnabledForApp:(NSString *)bundleId {
    return [[self entryForApp:bundleId][@"enabled"] boolValue];
}

+ (NSDictionary *)identityForApp:(NSString *)bundleId {
    id i = [self entryForApp:bundleId][@"identity"];
    return [i isKindOfClass:NSDictionary.class] ? i : nil;
}

#pragma mark Mutations (control app)

+ (void)write:(NSDictionary *)cfg {
    [[NSFileManager defaultManager] createDirectoryAtPath:[self directory]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [cfg writeToFile:[self appsPlistPath] atomically:YES];
}

+ (NSMutableDictionary *)mutableEntry:(NSString *)bundleId in:(NSMutableDictionary *)cfg {
    NSMutableDictionary *e = [[cfg[bundleId] isKindOfClass:NSDictionary.class] ? cfg[bundleId] : @{} mutableCopy];
    cfg[bundleId] = e;
    return e;
}

+ (void)setEnabled:(BOOL)enabled forApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:bundleId in:cfg];
    e[@"enabled"] = @(enabled);
    [self write:cfg];
}

+ (void)setIdentity:(NSDictionary *)identity forApp:(NSString *)bundleId {
    if (bundleId.length == 0 || !identity) return;
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:bundleId in:cfg];
    e[@"identity"] = identity;
    [self write:cfg];
}

+ (void)removeApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    [cfg removeObjectForKey:bundleId];
    [self write:cfg];
}

+ (BOOL)wipePendingForApp:(NSString *)bundleId {
    return [[self entryForApp:bundleId][@"wipePending"] boolValue];
}

+ (void)setWipePending:(BOOL)pending forApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:bundleId in:cfg];
    if (pending) e[@"wipePending"] = @YES; else [e removeObjectForKey:@"wipePending"];
    [self write:cfg];
}

#pragma mark Panel settings (global, reserved __sms key)

// Stored under a top-level key that can never collide with a real bundle id (those never start "__").
// The key name is historical; kept so existing approved-names / auto-scan values survive the upgrade.
+ (id)panelField:(NSString *)k { id d = [self all][@"__sms"]; return [d isKindOfClass:NSDictionary.class] ? d[k] : nil; }

+ (void)setPanelField:(NSString *)k value:(NSString *)v {
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:@"__sms" in:cfg];
    if (v.length) e[k] = v; else [e removeObjectForKey:k];
    [self write:cfg];
}

+ (NSString *)approvedNames { return [self panelField:@"approvedNames"]; }
+ (void)setApprovedNames:(NSString *)names { [self setPanelField:@"approvedNames" value:names ?: @""]; }

+ (BOOL)autoScan { return [[self panelField:@"autoScan"] isEqualToString:@"1"]; }
+ (void)setAutoScan:(BOOL)on { [self setPanelField:@"autoScan" value:on ? @"1" : @"0"]; }

#pragma mark SpringBoard overrides (icon names + badges)

+ (NSString *)springboardPlistPath { return [[self directory] stringByAppendingPathComponent:@"springboard.plist"]; }

+ (NSMutableDictionary *)springboardRoot {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self springboardPlistPath]];
    return [d isKindOfClass:NSDictionary.class] ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)writeSpringboard:(NSDictionary *)root {
    [[NSFileManager defaultManager] createDirectoryAtPath:[self directory]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [root writeToFile:[self springboardPlistPath] atomically:YES];
}

+ (NSDictionary<NSString *, NSString *> *)allCustomNames {
    id d = [self springboardRoot][@"names"];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

+ (NSDictionary<NSString *, NSNumber *> *)allBadges {
    id d = [self springboardRoot][@"badges"];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

+ (NSString *)customNameForApp:(NSString *)bundleId {
    if (bundleId.length == 0) return nil;
    id v = [self allCustomNames][bundleId];
    return [v isKindOfClass:NSString.class] && [v length] ? v : nil;
}

+ (void)setCustomName:(NSString *)name forApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *root = [self springboardRoot];
    NSMutableDictionary *names = [[root[@"names"] isKindOfClass:NSDictionary.class] ? root[@"names"] : @{} mutableCopy];
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length) names[bundleId] = trimmed; else [names removeObjectForKey:bundleId];
    root[@"names"] = names;
    [self writeSpringboard:root];
}

+ (NSNumber *)badgeForApp:(NSString *)bundleId {
    if (bundleId.length == 0) return nil;
    id v = [self allBadges][bundleId];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)setBadge:(NSNumber *)badge forApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *root = [self springboardRoot];
    NSMutableDictionary *badges = [[root[@"badges"] isKindOfClass:NSDictionary.class] ? root[@"badges"] : @{} mutableCopy];
    if (badge) badges[bundleId] = badge; else [badges removeObjectForKey:bundleId];
    root[@"badges"] = badges;
    [self writeSpringboard:root];
}

+ (void)notifySpringBoard {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.heavenzy.springboard.reload"), NULL, NULL, YES);
}

@end

#import "HZConfig.h"
#import <dlfcn.h>

@implementation HZConfig

+ (NSString *)directory { return @"/var/mobile/Library/Preferences/Heavenzy"; }
+ (NSString *)appsPlistPath { return [[self directory] stringByAppendingPathComponent:@"apps.plist"]; }

+ (void)grantSandboxAccess {
    // libSandy_applyProfile("Heavenzy") — resolved at runtime so a missing libSandy never breaks load.
    static dispatch_once_t once; dispatch_once(&once, ^{
        void *h = dlopen("/var/jb/usr/lib/libSandy.dylib", RTLD_LAZY) ?: dlopen("libSandy.dylib", RTLD_LAZY);
        if (!h) return;
        int (*applyProfile)(const char *) = (int (*)(const char *))dlsym(h, "libSandy_applyProfile");
        if (applyProfile) applyProfile("Heavenzy");
    });
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

#pragma mark SMS settings (global, reserved __sms key)

// Stored under a top-level key that can never collide with a real bundle id (those never start "__").
+ (id)smsField:(NSString *)k { id d = [self all][@"__sms"]; return [d isKindOfClass:NSDictionary.class] ? d[k] : nil; }

+ (void)setSmsField:(NSString *)k value:(NSString *)v {
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:@"__sms" in:cfg];
    if (v.length) e[k] = v; else [e removeObjectForKey:k];
    [self write:cfg];
}

+ (NSString *)smsProvider     { NSString *p = [self smsField:@"provider"]; return p.length ? p : @"diddy"; }
+ (NSString *)diddyKey        { return [self smsField:@"diddyKey"]; }
+ (NSString *)grizzlyKey      { return [self smsField:@"grizzlyKey"]; }
+ (NSString *)grizzlyMaxPrice { return [self smsField:@"grizzlyMaxPrice"]; }

+ (void)setSmsProvider:(NSString *)provider { [self setSmsField:@"provider" value:[provider isEqualToString:@"grizzly"] ? @"grizzly" : @"diddy"]; }
+ (void)setDiddyKey:(NSString *)key         { [self setSmsField:@"diddyKey" value:key]; }
+ (void)setGrizzlyKey:(NSString *)key       { [self setSmsField:@"grizzlyKey" value:key]; }
+ (void)setGrizzlyMaxPrice:(NSString *)price{ [self setSmsField:@"grizzlyMaxPrice" value:price]; }

+ (NSString *)panelMode { NSString *m = [self smsField:@"panelMode"]; return [m isEqualToString:@"scraper"] ? @"scraper" : @"sms"; }
+ (void)setPanelMode:(NSString *)mode { [self setSmsField:@"panelMode" value:[mode isEqualToString:@"scraper"] ? @"scraper" : @"sms"]; }

@end

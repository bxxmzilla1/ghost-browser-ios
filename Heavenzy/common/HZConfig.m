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

#pragma mark Bundle.social credentials (global, reserved __bundlesocial key)

// Stored under a top-level key that can never collide with a real bundle id (those never start "__").
+ (NSString *)bundleKey  { id d = [self all][@"__bundlesocial"]; return [d isKindOfClass:NSDictionary.class] ? d[@"key"]  : nil; }
+ (NSString *)bundleTeam { id d = [self all][@"__bundlesocial"]; return [d isKindOfClass:NSDictionary.class] ? d[@"team"] : nil; }

+ (void)setBundleKey:(NSString *)key {
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:@"__bundlesocial" in:cfg];
    if (key.length) e[@"key"] = key; else [e removeObjectForKey:@"key"];
    [self write:cfg];
}

+ (void)setBundleTeam:(NSString *)team {
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:@"__bundlesocial" in:cfg];
    if (team.length) e[@"team"] = team; else [e removeObjectForKey:@"team"];
    [self write:cfg];
}

@end

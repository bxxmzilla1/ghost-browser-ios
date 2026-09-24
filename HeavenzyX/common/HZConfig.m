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

+ (NSString *)grizzlyCountry { return [[self smsField:@"grizzlyCountry"] isEqualToString:@"virtual"] ? @"virtual" : @"usa"; }
+ (void)setGrizzlyCountry:(NSString *)country { [self setSmsField:@"grizzlyCountry" value:[country isEqualToString:@"virtual"] ? @"virtual" : @"usa"]; }

+ (NSString *)panelMode { NSString *m = [self smsField:@"panelMode"]; return [m isEqualToString:@"scraper"] ? @"scraper" : @"sms"; }
+ (void)setPanelMode:(NSString *)mode { [self setSmsField:@"panelMode" value:[mode isEqualToString:@"scraper"] ? @"scraper" : @"sms"]; }

+ (NSString *)approvedNames { return [self smsField:@"approvedNames"]; }
+ (void)setApprovedNames:(NSString *)names { [self setSmsField:@"approvedNames" value:names ?: @""]; }

+ (BOOL)autoScan { return [[self smsField:@"autoScan"] isEqualToString:@"1"]; }
+ (void)setAutoScan:(BOOL)on { [self setSmsField:@"autoScan" value:on ? @"1" : @"0"]; }

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

#pragma mark Cloud account

+ (id)cloudField:(NSString *)k { id d = [self all][@"__cloud"]; return [d isKindOfClass:NSDictionary.class] ? d[k] : nil; }
+ (void)setCloudField:(NSString *)k value:(NSString *)v {
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:@"__cloud" in:cfg];
    if (v.length) e[k] = v; else [e removeObjectForKey:k];
    [self write:cfg];
}

// Built-in project. The anon key is a public, RLS-restricted key by design; it grants nothing on its
// own — every row and object is scoped to the signed-in user by the policies in supabase/schema.sql.
// A value stored via Settings (setCloudURL: / setCloudAnonKey:) overrides these.
static NSString *const HZDefaultCloudURL = @"https://ubslmdrisqurfriqisoa.supabase.co";
static NSString *const HZDefaultCloudAnonKey = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVic2xtZHJpc3F1cmZyaXFpc29hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNzU3NjcsImV4cCI6MjEwNTg1MTc2N30.0cShCnPQxy3dpGuzHzvK7dBV5KhOrIz91ncfcrs9kZs";

+ (BOOL)cloudHasBuiltInProject { return HZDefaultCloudURL.length > 0 && HZDefaultCloudAnonKey.length > 0; }

+ (NSString *)cloudURL {
    NSString *u = [[self cloudField:@"url"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!u.length) u = HZDefaultCloudURL;
    while ([u hasSuffix:@"/"]) u = [u substringToIndex:u.length - 1];
    return u ?: @"";
}
+ (void)setCloudURL:(NSString *)url { [self setCloudField:@"url" value:url]; }
+ (NSString *)cloudAnonKey {
    NSString *k = [[self cloudField:@"anonKey"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return k.length ? k : HZDefaultCloudAnonKey;
}
+ (void)setCloudAnonKey:(NSString *)key { [self setCloudField:@"anonKey" value:key]; }
+ (NSString *)cloudAccountId { id v = [self cloudField:@"accountId"]; return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
+ (void)setCloudAccountId:(NSString *)userId { [self setCloudField:@"accountId" value:userId]; }

#pragma mark Container snapshots

+ (NSString *)containersRoot { return [[self directory] stringByAppendingPathComponent:@"Containers"]; }

+ (NSString *)snapshotsDirForApp:(NSString *)bundleId {
    if (bundleId.length == 0) return nil;
    return [[self containersRoot] stringByAppendingPathComponent:bundleId];
}

+ (NSString *)sanitizeSnapshotName:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString *safe = [[trimmed componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    if ([safe hasPrefix:@"."]) safe = [@"_" stringByAppendingString:safe];   // no hidden dirs
    return safe.length ? [safe substringToIndex:MIN(safe.length, 60u)] : nil;
}

+ (unsigned long long)sizeOfDir:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
    unsigned long long total = 0;
    while ([en nextObject]) total += [en.fileAttributes fileSize];
    return total;
}

+ (NSArray<NSDictionary *> *)snapshotsForApp:(NSString *)bundleId {
    NSString *dir = [self snapshotsDirForApp:bundleId];
    if (!dir) return @[];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) continue;
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"meta.plist"]] ?: @{};
        NSMutableDictionary *e = [NSMutableDictionary dictionary];
        e[@"name"]    = meta[@"name"] ?: name;
        e[@"path"]    = path;
        if (meta[@"date"])    e[@"date"]    = meta[@"date"];
        if (meta[@"version"]) e[@"version"] = meta[@"version"];
        if (meta[@"build"])   e[@"build"]   = meta[@"build"];
        e[@"bytes"] = @([self sizeOfDir:path]);
        [out addObject:e];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDate *da = a[@"date"], *db = b[@"date"];
        if (da && db) return [db compare:da];   // newest first
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return out;
}

+ (BOOL)deleteSnapshotNamed:(NSString *)name forApp:(NSString *)bundleId {
    NSString *dir = [self snapshotsDirForApp:bundleId];
    NSString *safe = [self sanitizeSnapshotName:name];
    if (!dir || !safe) return NO;
    return [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:safe] error:nil];
}

+ (BOOL)renameSnapshotNamed:(NSString *)name to:(NSString *)newName forApp:(NSString *)bundleId {
    NSString *dir = [self snapshotsDirForApp:bundleId];
    NSString *from = [self sanitizeSnapshotName:name];
    NSString *to   = [self sanitizeSnapshotName:newName];
    if (!dir || !from || !to || [from isEqualToString:to]) return NO;
    NSString *fromPath = [dir stringByAppendingPathComponent:from];
    NSString *toPath   = [dir stringByAppendingPathComponent:to];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:toPath]) return NO;
    if (![fm moveItemAtPath:fromPath toPath:toPath error:nil]) return NO;
    // Keep the display name in meta.plist in sync with the folder.
    NSString *metaPath = [toPath stringByAppendingPathComponent:@"meta.plist"];
    NSMutableDictionary *meta = [[NSDictionary dictionaryWithContentsOfFile:metaPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    meta[@"name"] = to;
    [meta writeToFile:metaPath atomically:YES];
    return YES;
}

+ (void)setSnapshotEntry:(NSString *)key value:(NSString *)value forApp:(NSString *)bundleId {
    if (bundleId.length == 0) return;
    NSMutableDictionary *cfg = [[self all] mutableCopy];
    NSMutableDictionary *e = [self mutableEntry:bundleId in:cfg];
    // Save and load are mutually exclusive.
    [e removeObjectForKey:@"snapSave"];
    [e removeObjectForKey:@"snapLoad"];
    if (value.length) e[key] = value;
    [self write:cfg];
}

+ (NSString *)snapshotSavePendingForApp:(NSString *)bundleId {
    id v = [self entryForApp:bundleId][@"snapSave"];
    return [v isKindOfClass:NSString.class] ? v : nil;
}
+ (void)setSnapshotSavePending:(NSString *)name forApp:(NSString *)bundleId {
    [self setSnapshotEntry:@"snapSave" value:name forApp:bundleId];
}
+ (NSString *)snapshotLoadPendingForApp:(NSString *)bundleId {
    id v = [self entryForApp:bundleId][@"snapLoad"];
    return [v isKindOfClass:NSString.class] ? v : nil;
}
+ (void)setSnapshotLoadPending:(NSString *)name forApp:(NSString *)bundleId {
    [self setSnapshotEntry:@"snapLoad" value:name forApp:bundleId];
}

@end

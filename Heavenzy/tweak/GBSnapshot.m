#import "GBSnapshot.h"
#import "GBMenu.h"
#import "HZConfig.h"
#import <Security/Security.h>
#import <UIKit/UIKit.h>

// SecTask entitlement lookup lives in a private header not shipped in the iOS SDK; the symbols exist
// in the Security framework, so declare what we use. (Signatures match the real ones, so this is a
// no-op if the SDK ever does include SecTask.h.)
#if !__has_include(<Security/SecTask.h>)
typedef struct __SecTask *SecTaskRef;
#endif
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

#pragma mark - Paths

static NSString *GBHome(void) { return NSHomeDirectory(); }

static NSString *GBSnapshotDir(NSString *name) {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *safe = [HZConfig sanitizeSnapshotName:name];
    NSString *appDir = [HZConfig snapshotsDirForApp:bundleId];
    if (!safe || !appDir) return nil;
    return [appDir stringByAppendingPathComponent:safe];
}

#pragma mark - File helpers

static void GBEnsureDir(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

// Copy every child of `src` into `dst`, skipping any names in `skip` (case-insensitive). Returns the
// number of top-level items copied.
static NSInteger GBCopyContents(NSString *src, NSString *dst, NSArray<NSString *> *skip) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) return 0;
    GBEnsureDir(dst);
    NSInteger n = 0;
    for (NSString *name in [fm contentsOfDirectoryAtPath:src error:nil]) {
        BOOL skipIt = NO;
        for (NSString *s in skip) if ([name caseInsensitiveCompare:s] == NSOrderedSame) { skipIt = YES; break; }
        if (skipIt) continue;
        NSString *from = [src stringByAppendingPathComponent:name];
        NSString *to   = [dst stringByAppendingPathComponent:name];
        [fm removeItemAtPath:to error:nil];
        if ([fm copyItemAtPath:from toPath:to error:nil]) n++;
    }
    return n;
}

// Remove everything under `dir` (but keep `dir` itself).
static void GBWipeContents(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil])
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
}

// The parts of the data container that hold login state. Caches/tmp are volatile and huge, so they're
// left out; com.heavenzy.plist is our own control file and must not travel inside a snapshot.
static NSArray<NSString *> *GBDataSkip(void) { return @[ @"Caches" ]; }

#pragma mark - App-group containers

// Group ids from this app's own entitlements (com.apple.security.application-groups), read at runtime.
static NSArray<NSString *> *GBAppGroupIds(void) {
    NSMutableArray *ids = [NSMutableArray array];
    @try {
        SecTaskRef task = SecTaskCreateFromSelf(NULL);
        if (task) {
            CFTypeRef val = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
            if (val) {
                if (CFGetTypeID(val) == CFArrayGetTypeID())
                    for (id g in (__bridge NSArray *)val) if ([g isKindOfClass:NSString.class]) [ids addObject:g];
                CFRelease(val);
            }
            CFRelease(task);
        }
    } @catch (__unused NSException *e) {}
    return ids;
}

static NSString *GBGroupContainerPath(NSString *groupId) {
    NSURL *url = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupId];
    return url.path;
}

#pragma mark - Keychain

// Short attribute keys (as returned by SecItemCopyMatching) → the kSec* constants SecItemAdd expects.
static NSDictionary *GBKeychainAttrMap(void) {
    return @{ @"acct": (__bridge id)kSecAttrAccount,
              @"svce": (__bridge id)kSecAttrService,
              @"agrp": (__bridge id)kSecAttrAccessGroup,
              @"gena": (__bridge id)kSecAttrGeneric,
              @"desc": (__bridge id)kSecAttrDescription,
              @"icmt": (__bridge id)kSecAttrComment,
              @"crtr": (__bridge id)kSecAttrCreator,
              @"type": (__bridge id)kSecAttrType,
              @"labl": (__bridge id)kSecAttrLabel,
              @"invi": (__bridge id)kSecAttrIsInvisible,
              @"nega": (__bridge id)kSecAttrIsNegative,
              @"sdmn": (__bridge id)kSecAttrSecurityDomain,
              @"srvr": (__bridge id)kSecAttrServer,
              @"ptcl": (__bridge id)kSecAttrProtocol,
              @"atyp": (__bridge id)kSecAttrAuthenticationType,
              @"port": (__bridge id)kSecAttrPort,
              @"path": (__bridge id)kSecAttrPath };
}

// pdmn accessibility short code → kSecAttrAccessible constant.
static id GBAccessibleForCode(NSString *code) {
    static NSDictionary *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = @{ @"ak":  (__bridge id)kSecAttrAccessibleWhenUnlocked,
                                   @"ck":  (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
                                   @"dk":  (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
                                   @"aku": (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                   @"cku": (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   @"dku": (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   @"akpu":(__bridge id)kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly }; });
    return m[code] ?: (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
}

static NSArray<NSString *> *GBKeychainClasses(void) {
    return @[ (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecClassInternetPassword,
              (__bridge id)kSecClassKey,
              (__bridge id)kSecClassCertificate,
              (__bridge id)kSecClassIdentity ];
}

// Dump every keychain item this app can see into a serialisable array of { class, attrs, data }.
static NSArray *GBDumpKeychain(void) {
    NSMutableArray *items = [NSMutableArray array];
    NSDictionary *map = GBKeychainAttrMap();
    for (id cls in GBKeychainClasses()) {
        NSDictionary *query = @{ (__bridge id)kSecClass: cls,
                                 (__bridge id)kSecReturnAttributes: @YES,
                                 (__bridge id)kSecReturnData: @YES,
                                 (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                                 (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny };
        CFTypeRef result = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (st != errSecSuccess || !result) { if (result) CFRelease(result); continue; }
        NSArray *found = (CFGetTypeID(result) == CFArrayGetTypeID()) ? (__bridge NSArray *)result : @[ (__bridge id)result ];
        for (NSDictionary *raw in found) {
            if (![raw isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
            for (NSString *shortKey in map) if (raw[shortKey] != nil) attrs[shortKey] = raw[shortKey];
            id pdmn = raw[@"pdmn"]; if ([pdmn isKindOfClass:NSString.class]) attrs[@"pdmn"] = pdmn;
            id sync = raw[@"sync"]; if (sync) attrs[@"sync"] = sync;
            id data = raw[(__bridge id)kSecValueData];
            NSMutableDictionary *item = [NSMutableDictionary dictionary];
            item[@"class"] = cls;
            item[@"attrs"] = attrs;
            if ([data isKindOfClass:NSData.class]) item[@"data"] = data;
            [items addObject:item];
        }
        CFRelease(result);
    }
    return items;
}

// Re-add saved keychain items. Existing duplicates are deleted first so the restore always wins.
static NSInteger GBRestoreKeychain(NSArray *items) {
    if (![items isKindOfClass:NSArray.class]) return 0;
    NSDictionary *map = GBKeychainAttrMap();
    NSInteger n = 0;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id cls = item[@"class"];
        NSDictionary *attrs = item[@"attrs"];
        if (!cls || ![attrs isKindOfClass:NSDictionary.class]) continue;

        NSMutableDictionary *add = [NSMutableDictionary dictionary];
        add[(__bridge id)kSecClass] = cls;
        for (NSString *shortKey in attrs) {
            id kSecKey = map[shortKey];
            if (kSecKey) add[kSecKey] = attrs[shortKey];
        }
        if (attrs[@"pdmn"]) add[(__bridge id)kSecAttrAccessible] = GBAccessibleForCode(attrs[@"pdmn"]);
        id sync = attrs[@"sync"];
        if (sync) add[(__bridge id)kSecAttrSynchronizable] = [sync boolValue] ? @YES : @NO;
        id data = item[@"data"];
        if ([data isKindOfClass:NSData.class]) add[(__bridge id)kSecValueData] = data;

        OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        if (st == errSecDuplicateItem) {
            // Build a match query from the identifying attributes and delete, then re-add.
            NSMutableDictionary *del = [NSMutableDictionary dictionary];
            del[(__bridge id)kSecClass] = cls;
            for (NSString *idKey in @[ @"acct", @"svce", @"agrp", @"srvr", @"path", @"port", @"ptcl" ])
                if (attrs[idKey] && map[idKey]) del[map[idKey]] = attrs[idKey];
            del[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kSecAttrSynchronizableAny;
            SecItemDelete((__bridge CFDictionaryRef)del);
            st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        }
        if (st == errSecSuccess) n++;
    }
    return n;
}

#pragma mark - Identity capture

// The Heavenzy identity currently in this app's container plist, so it can be restored with the login.
static NSDictionary *GBCurrentIdentity(void) {
    NSString *path = [GBHome() stringByAppendingPathComponent:@"Library/Preferences/com.heavenzy.plist"];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![d isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *i = [NSMutableDictionary dictionary];
    for (NSString *k in @[ @"idfv", @"idfa", @"udid", @"serial", @"wifi", @"bluetooth", @"imei", @"deviceName" ])
        if (d[k]) i[k] = d[k];
    return i;
}

#pragma mark - Save / Load

@implementation GBSnapshot

// Can this process actually create files in the shared snapshot store? Probe once, with a real write.
static NSString *GBStoreProbe(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err] && ![fm fileExistsAtPath:dir]) {
        return [NSString stringWithFormat:@"can't create snapshot folder (%@; sandbox access %@)",
                err.localizedDescription ?: @"unknown", [HZConfig sandboxAccessDescription]];
    }
    NSString *probe = [dir stringByAppendingPathComponent:@".probe"];
    if (![@"ok" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        return [NSString stringWithFormat:@"snapshot store not writable (%@; sandbox access %@)",
                err.localizedDescription ?: @"unknown", [HZConfig sandboxAccessDescription]];
    }
    [fm removeItemAtPath:probe error:nil];
    return nil;
}

+ (NSString *)saveSnapshotNamed:(NSString *)name {
    NSString *dir = GBSnapshotDir(name);
    if (!dir) return @"invalid snapshot name";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dir error:nil];
    NSString *probeErr = GBStoreProbe(dir);
    if (probeErr) { NSLog(@"[Heavenzy][Snapshot] save failed: %@", probeErr); [fm removeItemAtPath:dir error:nil]; return probeErr; }

    NSString *home = GBHome();
    NSString *dataDst = [dir stringByAppendingPathComponent:@"data"];

    // Library (minus Caches) and Documents hold the session DB, cookies and prefs. Our own control
    // file must not be baked into the snapshot, so drop it after the copy.
    GBCopyContents([home stringByAppendingPathComponent:@"Library"],
                   [dataDst stringByAppendingPathComponent:@"Library"], GBDataSkip());
    GBCopyContents([home stringByAppendingPathComponent:@"Documents"],
                   [dataDst stringByAppendingPathComponent:@"Documents"], nil);
    [fm removeItemAtPath:[dataDst stringByAppendingPathComponent:@"Library/Preferences/com.heavenzy.plist"] error:nil];

    // Shared app-group containers (e.g. group.com.burbn.instagram).
    NSArray *groupIds = GBAppGroupIds();
    if (groupIds.count) {
        NSString *groupsDst = [dir stringByAppendingPathComponent:@"groups"];
        for (NSString *gid in groupIds) {
            NSString *gpath = GBGroupContainerPath(gid);
            if (gpath) GBCopyContents(gpath, [groupsDst stringByAppendingPathComponent:gid], GBDataSkip());
        }
    }

    // Keychain — the part a plain folder copy can never capture.
    NSArray *kc = GBDumpKeychain();
    [kc writeToFile:[dir stringByAppendingPathComponent:@"keychain.plist"] atomically:YES];

    // Identity active right now, so a restore lands the account on the same spoofed device.
    [GBCurrentIdentity() writeToFile:[dir stringByAppendingPathComponent:@"identity.plist"] atomically:YES];

    NSBundle *mb = [NSBundle mainBundle];
    NSDictionary *meta = @{ @"name":    [HZConfig sanitizeSnapshotName:name] ?: name,
                            @"date":    [NSDate date],
                            @"version": [mb objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
                            @"build":   [mb objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
                            @"schema":  @1,
                            @"keychainItems": @(kc.count) };
    if (![meta writeToFile:[dir stringByAppendingPathComponent:@"meta.plist"] atomically:YES]) {
        NSLog(@"[Heavenzy][Snapshot] save failed: couldn't write meta.plist");
        [fm removeItemAtPath:dir error:nil];
        return @"couldn't finish writing the snapshot";
    }

    NSLog(@"[Heavenzy][Snapshot] saved \"%@\" (%lu keychain items) for %@", name,
          (unsigned long)kc.count, [mb bundleIdentifier]);
    return nil;
}

+ (NSDictionary *)loadSnapshotNamed:(NSString *)name error:(NSString **)error {
    NSString *dir = GBSnapshotDir(name);
    NSFileManager *fm = [NSFileManager defaultManager];
    // Check the snapshot is readable *before* wiping anything.
    if (!dir || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"meta.plist"]]) {
        NSString *why = [fm fileExistsAtPath:[HZConfig containersRoot]]
            ? [NSString stringWithFormat:@"snapshot \"%@\" not found", name]
            : [NSString stringWithFormat:@"snapshot store unreachable (sandbox access %@)", [HZConfig sandboxAccessDescription]];
        NSLog(@"[Heavenzy][Snapshot] load failed: %@", why);
        if (error) *error = why;
        return nil;
    }

    NSString *home = GBHome();

    // 1) Wipe the current state (files + keychain + cookies + web data), same as an erase.
    [GBMenu clearAppData];

    // 2) Restore the data container files.
    NSString *dataSrc = [dir stringByAppendingPathComponent:@"data"];
    GBCopyContents([dataSrc stringByAppendingPathComponent:@"Library"],
                   [home stringByAppendingPathComponent:@"Library"], nil);
    GBCopyContents([dataSrc stringByAppendingPathComponent:@"Documents"],
                   [home stringByAppendingPathComponent:@"Documents"], nil);

    // 3) Restore shared app-group containers into their live locations.
    NSString *groupsSrc = [dir stringByAppendingPathComponent:@"groups"];
    for (NSString *gid in [fm contentsOfDirectoryAtPath:groupsSrc error:nil]) {
        NSString *gpath = GBGroupContainerPath(gid);
        if (gpath) {
            GBWipeContents(gpath);
            GBCopyContents([groupsSrc stringByAppendingPathComponent:gid], gpath, nil);
        }
    }

    // 4) Re-import the keychain items.
    NSArray *kc = [NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:@"keychain.plist"]];
    NSInteger restored = GBRestoreKeychain(kc);

    // 5) Hand the saved identity back so the caller re-applies it to GBStore.
    NSDictionary *identity = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"identity.plist"]];

    NSLog(@"[Heavenzy][Snapshot] loaded \"%@\" (%ld keychain items restored) for %@", name,
          (long)restored, [[NSBundle mainBundle] bundleIdentifier]);
    return identity ?: @{};
}

@end

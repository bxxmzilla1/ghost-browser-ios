#import "HZWebClips.h"
#import "HZConfig.h"

static NSString *const kHZTagPrefix = @"hzc=";

@implementation HZWebClips

+ (NSString *)plistPath { return [[HZConfig directory] stringByAppendingPathComponent:@"webclips.plist"]; }
+ (NSString *)webClipsDirectory { return @"/var/mobile/Library/WebClips"; }

#pragma mark Storage

+ (NSMutableDictionary *)root {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self plistPath]];
    return [d isKindOfClass:NSDictionary.class] ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)writeRoot:(NSDictionary *)root {
    [[NSFileManager defaultManager] createDirectoryAtPath:[HZConfig directory]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [root writeToFile:[self plistPath] atomically:YES];
}

+ (NSArray<NSDictionary *> *)containersIn:(NSDictionary *)root {
    id a = root[@"containers"];
    if (![a isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id c in a) if ([c isKindOfClass:NSDictionary.class] && [c[@"id"] length]) [out addObject:c];
    return out;
}

+ (NSArray<NSDictionary *> *)containers { return [self containersIn:[self root]]; }

+ (NSDictionary *)containerWithId:(NSString *)cid {
    if (cid.length == 0) return nil;
    for (NSDictionary *c in [self containers]) if ([c[@"id"] isEqualToString:cid]) return c;
    return nil;
}

+ (NSDictionary *)containerForStoreKey:(NSString *)key {
    if (key.length == 0) return nil;
    for (NSDictionary *c in [self containers]) {
        id stores = c[@"stores"];
        if ([stores isKindOfClass:NSArray.class] && [stores containsObject:key]) return c;
    }
    return nil;
}

+ (NSDictionary *)containerForBundleId:(NSString *)bundleId {
    if (![bundleId hasPrefix:@"com.apple."]) return nil;
    NSString *upper = bundleId.uppercaseString;
    for (NSDictionary *c in [self containers]) {
        NSString *clipId = [c[@"clipId"] uppercaseString];
        if (clipId.length >= 8 && [upper rangeOfString:clipId].location != NSNotFound) return c;
    }
    return nil;
}

/// Read-modify-write a single container entry.
+ (void)updateContainer:(NSString *)cid with:(void (^)(NSMutableDictionary *c))block {
    if (cid.length == 0) return;
    NSMutableDictionary *root = [self root];
    NSMutableArray *list = [[self containersIn:root] mutableCopy];
    for (NSUInteger i = 0; i < list.count; i++) {
        if (![list[i][@"id"] isEqualToString:cid]) continue;
        NSMutableDictionary *c = [list[i] mutableCopy];
        block(c);
        list[i] = c;
        root[@"containers"] = list;
        [self writeRoot:root];
        return;
    }
}

+ (NSString *)lastSite { id v = [self root][@"site"]; return [v isKindOfClass:NSString.class] ? v : nil; }
+ (NSString *)lastPrefix { id v = [self root][@"prefix"]; return [v isKindOfClass:NSString.class] ? v : nil; }

+ (BOOL)uploadSpoofDefault {
    id v = [self root][@"upload"];
    return v ? [v boolValue] : YES;
}

+ (void)setUploadSpoofDefault:(BOOL)on {
    NSMutableDictionary *root = [self root];
    root[@"upload"] = @(on);
    [self writeRoot:root];
}

#pragma mark URL tag

+ (NSString *)containerIdInURL:(NSURL *)url {
    NSString *f = url.fragment;
    if (![f hasPrefix:kHZTagPrefix]) return nil;
    NSString *cid = [f substringFromIndex:kHZTagPrefix.length];
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    return (cid.length && [cid rangeOfCharacterFromSet:bad].location == NSNotFound) ? cid : nil;
}

+ (NSURL *)URLByRemovingTag:(NSURL *)url {
    if (![self containerIdInURL:url]) return url;
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    c.fragment = nil;
    return c.URL ?: url;
}

+ (NSString *)taggedURL:(NSString *)site container:(NSString *)cid {
    NSURLComponents *c = [NSURLComponents componentsWithString:site];
    c.fragment = [kHZTagPrefix stringByAppendingString:cid];
    return c.string ?: site;
}

#pragma mark Tweak side

+ (void)linkStoreKey:(NSString *)key toContainer:(NSString *)cid {
    if (key.length == 0) return;
    NSDictionary *existing = [self containerForStoreKey:key];
    if ([existing[@"id"] isEqualToString:cid]) return;
    // A data store belongs to exactly one container; drop a stale link left by a deleted icon.
    if (existing) {
        [self updateContainer:existing[@"id"] with:^(NSMutableDictionary *c) {
            NSMutableArray *s = [c[@"stores"] mutableCopy];
            [s removeObject:key];
            c[@"stores"] = s;
        }];
    }
    [self updateContainer:cid with:^(NSMutableDictionary *c) {
        NSMutableArray *s = [[c[@"stores"] isKindOfClass:NSArray.class] ? c[@"stores"] : @[] mutableCopy];
        [s addObject:key];
        c[@"stores"] = s;
    }];
}

+ (void)clearWipePendingForContainer:(NSString *)cid {
    [self updateContainer:cid with:^(NSMutableDictionary *c) { [c removeObjectForKey:@"wipePending"]; }];
}

#pragma mark Control app side

+ (NSString *)normalizedSite:(NSString *)input {
    NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) return nil;
    if ([s rangeOfString:@"://"].location == NSNotFound) s = [@"https://" stringByAppendingString:s];
    NSURLComponents *c = [NSURLComponents componentsWithString:s];
    NSString *scheme = c.scheme.lowercaseString;
    if (!c || c.host.length == 0 || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return nil;
    c.scheme = scheme;
    c.fragment = nil;
    if (c.path.length == 0) c.path = @"/";
    return c.string;
}

+ (NSString *)newContainerIdAvoiding:(NSSet<NSString *> *)used {
    NSString *cid;
    do { cid = [NSString stringWithFormat:@"%08x", arc4random()]; } while ([used containsObject:cid]);
    return cid;
}

+ (NSString *)bundlePathForClipId:(NSString *)clipId {
    return [[self webClipsDirectory] stringByAppendingPathComponent:[clipId stringByAppendingString:@".webclip"]];
}

+ (NSArray<NSDictionary *> *)createContainers:(NSInteger)count site:(NSString *)site prefix:(NSString *)prefix
                                       upload:(BOOL)upload iconForNumber:(NSData *(^)(NSInteger number))iconForNumber {
    if (count <= 0 || site.length == 0) return @[];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[self webClipsDirectory] withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableDictionary *root = [self root];
    NSMutableArray *list = [[self containersIn:root] mutableCopy];
    NSMutableSet *used = [NSMutableSet set];
    NSInteger number = 0;
    for (NSDictionary *c in list) {
        [used addObject:c[@"id"]];
        if ([c[@"url"] isEqualToString:site]) number = MAX(number, [c[@"number"] integerValue]);
    }

    NSMutableArray *created = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        number++;
        NSString *cid = [self newContainerIdAvoiding:used];
        [used addObject:cid];
        NSString *clipId = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
        NSString *name = [NSString stringWithFormat:@"%@ %ld", prefix, (long)number];
        NSString *dir = [self bundlePathForClipId:clipId];
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) continue;

        NSDictionary *info = @{
            @"Title": name,
            @"URL": [self taggedURL:site container:cid],
            @"FullScreen": @YES,              // standalone web app → its own cookies + storage
            @"IgnoreManifestScope": @YES,     // logins that bounce through other domains stay inside the container
            @"ClassicMode": @NO,
            @"IconIsPrecomposed": @YES,
            @"IconIsScreenShotBased": @NO,
            @"RemovalDisallowed": @NO,
            @"Scale": @1.0,
        };
        if (![info writeToFile:[dir stringByAppendingPathComponent:@"Info.plist"] atomically:YES]) {
            [fm removeItemAtPath:dir error:nil];
            continue;
        }
        NSData *png = iconForNumber ? iconForNumber(number) : nil;
        if (png) [png writeToFile:[dir stringByAppendingPathComponent:@"icon.png"] atomically:YES];

        NSDictionary *entry = @{
            @"id": cid, @"name": name, @"url": site, @"number": @(number), @"clipId": clipId,
            @"seed": @(arc4random() | 1u), @"upload": @(upload), @"createdAt": [NSDate date], @"stores": @[],
        };
        [list addObject:entry];
        [created addObject:entry];
    }
    root[@"containers"] = list;
    root[@"site"] = site;
    root[@"prefix"] = prefix;
    root[@"upload"] = @(upload);
    [self writeRoot:root];
    return created;
}

+ (void)resetContainer:(NSString *)cid {
    [self updateContainer:cid with:^(NSMutableDictionary *c) {
        c[@"seed"] = @(arc4random() | 1u);
        c[@"wipePending"] = @YES;
    }];
}

+ (void)removeContainer:(NSString *)cid {
    NSDictionary *c = [self containerWithId:cid];
    if (!c) return;
    if ([c[@"clipId"] length]) [[NSFileManager defaultManager] removeItemAtPath:[self bundlePathForClipId:c[@"clipId"]] error:nil];
    NSMutableDictionary *root = [self root];
    NSMutableArray *list = [[self containersIn:root] mutableCopy];
    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, __unused id b) {
        return ![e[@"id"] isEqualToString:cid];
    }]];
    root[@"containers"] = list;
    [self writeRoot:root];
}

+ (BOOL)iconExistsForContainer:(NSDictionary *)c {
    NSString *clipId = c[@"clipId"];
    return clipId.length && [[NSFileManager defaultManager] fileExistsAtPath:[self bundlePathForClipId:clipId]];
}

+ (NSString *)iconPathForContainer:(NSDictionary *)c {
    if (![self iconExistsForContainer:c]) return nil;
    NSString *p = [[self bundlePathForClipId:c[@"clipId"]] stringByAppendingPathComponent:@"icon.png"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}

+ (NSString *)seedLabel:(NSDictionary *)c {
    return [NSString stringWithFormat:@"%08X", (unsigned)[c[@"seed"] unsignedIntValue]];
}

@end

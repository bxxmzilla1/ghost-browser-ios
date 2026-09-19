#import "HZAppData.h"
#import <dlfcn.h>

#pragma mark - Private framework glue (resolved at runtime, nothing linked)

// TCC.framework — reset an app's privacy permissions.
static NSString *const kHZTCCServiceAll = @"kTCCServiceAll";
static int (*HZTCCAccessResetForBundle)(NSString *, CFBundleRef);

static void HZLoadTCC(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY);
        if (h) HZTCCAccessResetForBundle = dlsym(h, "TCCAccessResetForBundle");
    });
}

@interface HZAppData ()
@property (nonatomic, strong) id proxy;   // LSApplicationProxy
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *shortVersion;
@property (nonatomic, copy) NSString *buildVersion;
@property (nonatomic, copy) NSString *minimumOSVersion;
@property (nonatomic, copy) NSString *diskUsageString;
@property (nonatomic, copy) NSNumber *appStoreItemID;
@property (nonatomic, copy) NSArray<NSString *> *urlSchemes;
@property (nonatomic, strong) NSURL *bundleURL;
@property (nonatomic, strong) NSURL *dataContainerURL;
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *groupContainerURLs;
@end

@implementation HZAppData

+ (instancetype)dataForBundleId:(NSString *)bundleId {
    HZAppData *d = [HZAppData new];
    d.bundleId = bundleId;
    [d load];
    return d;
}

// Safe KVC read off the LSApplicationProxy (private properties, no header).
- (id)val:(NSString *)key {
    @try { return [self.proxy valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

- (void)load {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if ([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
            self.proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:self.bundleId];
        }
    } @catch (__unused NSException *e) {}
    if (!self.proxy) return;

    NSString *sv = [self val:@"shortVersionString"];
    self.shortVersion = sv.length ? sv : @"N/A";
    NSString *bv = [self val:@"bundleVersion"];
    self.buildVersion = bv.length ? bv : @"N/A";

    id bundleURL = [self val:@"bundleURL"] ?: [self val:@"bundleContainerURL"];
    if ([bundleURL isKindOfClass:NSURL.class]) self.bundleURL = bundleURL;
    id dataURL = [self val:@"dataContainerURL"];
    if ([dataURL isKindOfClass:NSURL.class]) self.dataContainerURL = dataURL;

    id groups = [self val:@"groupContainerURLs"];
    if ([groups isKindOfClass:NSDictionary.class]) self.groupContainerURLs = groups;

    id disk = [self val:@"staticDiskUsage"];
    if ([disk isKindOfClass:NSNumber.class])
        self.diskUsageString = [NSByteCountFormatter stringFromByteCount:[disk longLongValue]
                                                               countStyle:NSByteCountFormatterCountStyleFile];

    id itemID = [self val:@"itemID"];
    if ([itemID isKindOfClass:NSNumber.class] && [itemID integerValue] != 0) self.appStoreItemID = itemID;

    // Info.plist derived bits (min OS + URL schemes).
    @try {
        NSURL *infoURL = [self.bundleURL URLByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = infoURL ? [NSDictionary dictionaryWithContentsOfURL:infoURL] : nil;
        self.minimumOSVersion = info[@"MinimumOSVersion"];
        NSArray *types = info[@"CFBundleURLTypes"];
        if ([types isKindOfClass:NSArray.class]) {
            NSMutableArray *schemes = [NSMutableArray array];
            for (id t in types) {
                id s = [t isKindOfClass:NSDictionary.class] ? t[@"CFBundleURLSchemes"] : nil;
                if ([s isKindOfClass:NSArray.class]) [schemes addObjectsFromArray:s];
            }
            if (schemes.count) self.urlSchemes = schemes;
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Directory sizing

// Sum the allocated size of everything under `url` (recursively), like AppData's NRFileManager helper.
static unsigned long long HZDirectorySize(NSURL *url) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!url || ![fm fileExistsAtPath:url.path]) return 0;
    unsigned long long total = 0;
    NSArray<NSURLResourceKey> *keys = @[ NSURLTotalFileAllocatedSizeKey, NSURLFileAllocatedSizeKey, NSURLIsRegularFileKey ];
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:url includingPropertiesForKeys:keys
                                            options:0 errorHandler:nil];
    for (NSURL *child in en) {
        NSDictionary *vals = [child resourceValuesForKeys:keys error:nil];
        if (![vals[NSURLIsRegularFileKey] boolValue]) continue;
        NSNumber *size = vals[NSURLTotalFileAllocatedSizeKey] ?: vals[NSURLFileAllocatedSizeKey];
        total += size.unsignedLongLongValue;
    }
    return total;
}

- (NSArray<NSURL *> *)cacheDirs {
    NSMutableArray *a = [NSMutableArray array];
    if (self.dataContainerURL) {
        [a addObject:[self.dataContainerURL URLByAppendingPathComponent:@"Library/Caches"]];
        [a addObject:[self.dataContainerURL URLByAppendingPathComponent:@"tmp"]];
    }
    return a;
}

- (NSArray<NSURL *> *)dataDirs {
    NSMutableArray *a = [NSMutableArray array];
    if (self.dataContainerURL) {
        [a addObject:[self.dataContainerURL URLByAppendingPathComponent:@"Library"]];
        [a addObject:[self.dataContainerURL URLByAppendingPathComponent:@"tmp"]];
        [a addObject:[self.dataContainerURL URLByAppendingPathComponent:@"Documents"]];
    }
    return a;
}

- (void)sizeOf:(NSArray<NSURL *> *)dirs completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long total = 0;
        for (NSURL *u in dirs) total += HZDirectorySize(u);
        NSString *s = [NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(s); });
    });
}

- (void)cacheSize:(void (^)(NSString *))completion { [self sizeOf:[self cacheDirs] completion:completion]; }
- (void)dataSize:(void (^)(NSString *))completion  { [self sizeOf:[self dataDirs]  completion:completion]; }

#pragma mark - Destructive maintenance

+ (void)emptyDirectory:(NSURL *)url {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *kids = [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *child in kids) [fm removeItemAtURL:child error:NULL];
}

- (void)wipeDirs:(NSArray<NSURL *> *)dirs recreatePrefs:(BOOL)recreatePrefs completion:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL ok = NO;
        for (NSURL *u in dirs) {
            if (u && [[NSFileManager defaultManager] fileExistsAtPath:u.path]) { [HZAppData emptyDirectory:u]; ok = YES; }
        }
        if (recreatePrefs && self.dataContainerURL) {
            NSURL *prefs = [self.dataContainerURL URLByAppendingPathComponent:@"Library/Preferences" isDirectory:YES];
            [[NSFileManager defaultManager] createDirectoryAtURL:prefs withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok); });
    });
}

- (void)clearCache:(void (^)(BOOL))completion { [self wipeDirs:[self cacheDirs] recreatePrefs:NO completion:completion]; }
- (void)resetData:(void (^)(BOOL))completion  { [self wipeDirs:[self dataDirs] recreatePrefs:YES completion:completion]; }

- (void)resetPermissions:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL ok = NO;
        @try {
            HZLoadTCC();
            if (HZTCCAccessResetForBundle && self.bundleURL) {
                CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)self.bundleURL);
                if (bundle) {
                    ok = (HZTCCAccessResetForBundle(kHZTCCServiceAll, bundle) == 0);
                    CFRelease(bundle);
                }
            }
        } @catch (__unused NSException *e) { ok = NO; }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok); });
    });
}

- (void)offload:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block BOOL ok = NO;
        @try {
            Class coord = NSClassFromString(@"IXAppInstallCoordinator");
            SEL sel = @selector(demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:completion:);
            if ([coord respondsToSelector:sel]) {
                // demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:completion:
                void (^done)(void) = ^{ ok = YES; };
                NSMethodSignature *ms = [coord methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:ms];
                inv.target = coord; inv.selector = sel;
                NSString *bid = self.bundleId; NSInteger reason = 1; BOOL wait = YES;
                [inv setArgument:&bid atIndex:2];
                [inv setArgument:&reason atIndex:3];
                [inv setArgument:&wait atIndex:4];
                [inv setArgument:&done atIndex:5];
                [inv invoke];
            }
        } @catch (__unused NSException *e) { ok = NO; }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok); });
    });
}

#pragma mark - Navigation

- (BOOL)openInAppStore {
    if (!self.appStoreItemID) return NO;
    NSString *link = [NSString stringWithFormat:@"itms-apps://apps.apple.com/app/id%@", self.appStoreItemID];
    NSURL *url = [NSURL URLWithString:link];
    if (![UIApplication.sharedApplication canOpenURL:url]) return NO;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    return YES;
}

- (BOOL)openContainerInFilza:(NSURL *)container {
    if (!container.path.length) return NO;
    NSString *encoded = [container.path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view%@", encoded]];
    if (![UIApplication.sharedApplication canOpenURL:url]) return NO;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    return YES;
}

@end

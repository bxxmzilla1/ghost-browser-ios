#import "HZCloner.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"
#import <objc/message.h>
#import <spawn.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>

@implementation HZCloneSource @end

#pragma mark - Process helpers

static NSString *HZToolPath(NSString *name) {
    for (NSString *dir in @[ @"/var/jb/usr/bin", @"/var/jb/bin", @"/usr/bin", @"/bin", @"/usr/local/bin" ]) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

// Run a tool synchronously, capturing stdout+stderr. Returns the exit status (-1 if it couldn't spawn).
static int HZRun(NSString *tool, NSArray<NSString *> *args, NSString *cwd, NSString **output) {
    int fds[2];
    if (pipe(fds) != 0) return -1;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa, fds[0]);
    if (cwd.length) posix_spawn_file_actions_addchdir_np(&fa, cwd.fileSystemRepresentation);

    NSMutableArray *all = [NSMutableArray arrayWithObject:tool];
    [all addObjectsFromArray:args];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i++) argv[i] = strdup([all[i] fileSystemRepresentation]);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, tool.fileSystemRepresentation, &fa, NULL, argv, NULL);
    posix_spawn_file_actions_destroy(&fa);
    for (NSUInteger i = 0; i < all.count; i++) free(argv[i]);
    free(argv);
    close(fds[1]);

    NSMutableData *buf = [NSMutableData data];
    if (rc == 0) {
        char chunk[4096]; ssize_t n;
        while ((n = read(fds[0], chunk, sizeof chunk)) > 0) [buf appendBytes:chunk length:(NSUInteger)n];
    }
    close(fds[0]);
    if (output) *output = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding] ?: @"";
    if (rc != 0) return -1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

#pragma mark - Mach-O encryption check

// LC_ENCRYPTION_INFO(_64).cryptid != 0 means the App Store FairPlay wrapper is still on the binary.
static BOOL HZBinaryIsEncrypted(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (d.length < sizeof(struct mach_header_64)) return NO;
    const uint8_t *base = d.bytes;
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithObject:@0];
    uint32_t magic = *(const uint32_t *)base;
    if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        const struct fat_header *fh = (const struct fat_header *)base;
        uint32_t n = OSSwapBigToHostInt32(fh->nfat_arch);
        [offsets removeAllObjects];
        const struct fat_arch *fa = (const struct fat_arch *)(base + sizeof *fh);
        for (uint32_t i = 0; i < n && (const uint8_t *)(fa + i + 1) <= base + d.length; i++)
            [offsets addObject:@(OSSwapBigToHostInt32(fa[i].offset))];
    }
    for (NSNumber *off in offsets) {
        NSUInteger o = off.unsignedIntegerValue;
        if (o + sizeof(struct mach_header_64) > d.length) continue;
        const struct mach_header_64 *mh = (const struct mach_header_64 *)(base + o);
        if (mh->magic != MH_MAGIC_64 && mh->magic != MH_MAGIC) continue;
        BOOL is64 = mh->magic == MH_MAGIC_64;
        const uint8_t *lc = base + o + (is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
        uint32_t ncmds = mh->ncmds;
        for (uint32_t i = 0; i < ncmds && lc + sizeof(struct load_command) <= base + d.length; i++) {
            const struct load_command *cmd = (const struct load_command *)lc;
            if (cmd->cmd == LC_ENCRYPTION_INFO_64 || cmd->cmd == LC_ENCRYPTION_INFO) {
                const struct encryption_info_command *e = (const struct encryption_info_command *)lc;   // same layout prefix
                if (e->cryptid != 0) return YES;
            }
            if (cmd->cmdsize == 0) break;
            lc += cmd->cmdsize;
        }
    }
    return NO;
}

#pragma mark - Paths

static NSString *HZWorkRoot(void)  { return @"/var/mobile/Library/Heavenzy/clone-work"; }
static NSString *HZOutputDir(void) { return @"/var/mobile/Documents/Heavenzy"; }

static void HZMain(dispatch_block_t b) { dispatch_async(dispatch_get_main_queue(), b); }

@implementation HZCloner

+ (NSString *)missingTools {
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *t in @[ @"unzip", @"zip", @"ldid" ]) if (!HZToolPath(t)) [missing addObject:t];
    if (!missing.count) return nil;
    return [NSString stringWithFormat:@"Missing on this device: %@. Install the %@ package%@ from Procursus in Sileo.",
            [missing componentsJoinedByString:@", "], [missing componentsJoinedByString:@", "], missing.count > 1 ? @"s" : @""];
}

#pragma mark Inspect

+ (void)inspectIPA:(NSURL *)ipaURL completion:(void (^)(HZCloneSource *, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        HZCloneSource *src = [self inspectSync:ipaURL error:&err];
        HZMain(^{ completion(src, err); });
    });
}

+ (HZCloneSource *)inspectSync:(NSURL *)ipaURL error:(NSString **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *unzip = HZToolPath(@"unzip");
    if (!unzip) { *error = [self missingTools]; return nil; }

    BOOL scoped = [ipaURL startAccessingSecurityScopedResource];
    NSString *work = [HZWorkRoot() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *localIPA = [work stringByAppendingPathComponent:@"source.ipa"];
    NSError *copyErr = nil;
    [fm copyItemAtURL:ipaURL toURL:[NSURL fileURLWithPath:localIPA] error:&copyErr];
    if (scoped) [ipaURL stopAccessingSecurityScopedResource];
    if (copyErr) { *error = [NSString stringWithFormat:@"Couldn't read the IPA: %@", copyErr.localizedDescription]; return nil; }

    NSString *out = nil;
    int rc = HZRun(unzip, @[ @"-q", @"-o", localIPA, @"-d", work ], nil, &out);
    [fm removeItemAtPath:localIPA error:nil];
    if (rc != 0) { *error = [NSString stringWithFormat:@"unzip failed (%d): %@", rc, out]; return nil; }

    NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
    NSString *appDir = nil;
    for (NSString *item in [fm contentsOfDirectoryAtPath:payload error:nil] ?: @[])
        if ([item.pathExtension isEqualToString:@"app"]) { appDir = [payload stringByAppendingPathComponent:item]; break; }
    if (!appDir) { *error = @"Not a valid IPA: no Payload/*.app inside."; return nil; }

    NSMutableDictionary *info = [[NSDictionary dictionaryWithContentsOfFile:[appDir stringByAppendingPathComponent:@"Info.plist"]] mutableCopy];
    if (!info[@"CFBundleIdentifier"] || !info[@"CFBundleExecutable"]) { *error = @"Info.plist is missing CFBundleIdentifier / CFBundleExecutable."; return nil; }

    HZCloneSource *s = [HZCloneSource new];
    s.workDir = work; s.appDir = appDir;
    s.bundleId = info[@"CFBundleIdentifier"];
    s.executable = info[@"CFBundleExecutable"];
    s.name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: s.executable;
    s.version = info[@"CFBundleShortVersionString"] ?: info[@"CFBundleVersion"] ?: @"?";
    s.encrypted = HZBinaryIsEncrypted([appDir stringByAppendingPathComponent:s.executable]);
    s.hasExtensions = [fm fileExistsAtPath:[appDir stringByAppendingPathComponent:@"PlugIns"]]
                   || [fm fileExistsAtPath:[appDir stringByAppendingPathComponent:@"Watch"]];
    return s;
}

+ (void)cleanup:(HZCloneSource *)source {
    if (source.workDir.length) [[NSFileManager defaultManager] removeItemAtPath:source.workDir error:nil];
}

#pragma mark Installed apps

+ (BOOL)isAppInstalled:(NSString *)bundleId {
    @try {
        id ws = [NSClassFromString(@"LSApplicationWorkspace") valueForKey:@"defaultWorkspace"];
        for (id p in [ws valueForKey:@"allApplications"])
            if ([[p valueForKey:@"applicationIdentifier"] isEqualToString:bundleId]) return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

+ (NSString *)suggestedBundleIdFor:(NSString *)bundleId {
    for (int n = 2; n < 100; n++) {
        NSString *c = [NSString stringWithFormat:@"%@%d", bundleId, n];
        if (![self isAppInstalled:c]) return c;
    }
    return [bundleId stringByAppendingString:@".clone"];
}

#pragma mark Build

// Rewrite one entitlement identifier so the clone can never share it with the original or another clone.
static NSString *HZIsolate(NSString *s, NSString *oldBid, NSString *newBid) {
    if (![s isKindOfClass:NSString.class]) return s;
    if ([s containsString:oldBid]) return [s stringByReplacingOccurrencesOfString:oldBid withString:newBid];
    if ([s hasSuffix:@"*"]) return [[s substringToIndex:s.length - 1] stringByAppendingString:newBid];   // TEAM.* wildcard
    return [s stringByAppendingFormat:@".%@", newBid];   // shared group (e.g. a company-wide SSO group) → private copy
}

+ (NSDictionary *)isolatedEntitlements:(NSDictionary *)ents oldBid:(NSString *)oldBid newBid:(NSString *)newBid {
    NSMutableDictionary *e = [ents mutableCopy] ?: [NSMutableDictionary new];
    if (e[@"application-identifier"]) e[@"application-identifier"] = HZIsolate(e[@"application-identifier"], oldBid, newBid);
    for (NSString *listKey in @[ @"keychain-access-groups", @"com.apple.security.application-groups" ]) {
        NSArray *list = e[listKey];
        if (![list isKindOfClass:NSArray.class]) continue;
        NSMutableArray *fixed = [NSMutableArray new];
        for (id g in list) [fixed addObject:HZIsolate(g, oldBid, newBid)];
        e[listKey] = fixed;
    }
    // No iCloud of any kind: a clone must never restore or sync the original's state.
    for (NSString *k in @[ @"com.apple.developer.ubiquity-kvstore-identifier", @"com.apple.developer.ubiquity-container-identifiers",
                           @"com.apple.developer.icloud-container-identifiers", @"com.apple.developer.icloud-services",
                           @"com.apple.developer.icloud-container-environment", @"com.apple.developer.icloud-container-development-container-identifiers" ]) {
        [e removeObjectForKey:k];
    }
    return e;
}

+ (void)buildClone:(HZCloneSource *)src bundleId:(NSString *)newBid displayName:(NSString *)newName
  removeExtensions:(BOOL)removeExtensions progress:(void (^)(NSString *))progress
        completion:(void (^)(NSString *, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSString *ipa = [self buildSync:src bundleId:newBid displayName:newName removeExtensions:removeExtensions
                               progress:^(NSString *s) { HZMain(^{ progress(s); }); } error:&err];
        HZMain(^{ completion(ipa, err); });
    });
}

+ (NSString *)buildSync:(HZCloneSource *)src bundleId:(NSString *)newBid displayName:(NSString *)newName
       removeExtensions:(BOOL)removeExtensions progress:(void (^)(NSString *))progress error:(NSString **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *zip = HZToolPath(@"zip"), *ldid = HZToolPath(@"ldid");
    if (!zip || !ldid) { *error = [self missingTools]; return nil; }
    if (src.encrypted) { *error = @"This IPA is still FairPlay-encrypted. Heavenzy only clones decrypted IPAs."; return nil; }
    NSString *oldBid = src.bundleId;
    if (!newBid.length || [newBid isEqualToString:oldBid]) { *error = @"Pick a new bundle ID that differs from the original."; return nil; }
    if ([self isAppInstalled:newBid]) { *error = [NSString stringWithFormat:@"%@ is already installed. Choose another bundle ID.", newBid]; return nil; }

    // 1. Info.plist — new identity for the app.
    progress(@"Rewriting Info.plist…");
    NSString *infoPath = [src.appDir stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [[NSDictionary dictionaryWithContentsOfFile:infoPath] mutableCopy];
    info[@"CFBundleIdentifier"] = newBid;
    if (newName.length) { info[@"CFBundleDisplayName"] = newName; info[@"CFBundleName"] = newName; }
    // Clones must not claim the original's URL scheme name or iCloud KVS key.
    [info removeObjectForKey:@"NSUbiquitousContainers"];
    if (![info writeToFile:infoPath atomically:YES]) { *error = @"Couldn't write Info.plist."; return nil; }

    // 2. Strip things that would tie the clone back to the original install.
    progress(@"Stripping extensions & metadata…");
    if (removeExtensions) {
        for (NSString *sub in @[ @"PlugIns", @"Watch", @"com.apple.WatchPlaceholder", @"Extensions" ])
            [fm removeItemAtPath:[src.appDir stringByAppendingPathComponent:sub] error:nil];
    }
    [fm removeItemAtPath:[src.appDir stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
    [fm removeItemAtPath:[src.workDir stringByAppendingPathComponent:@"iTunesMetadata.plist"] error:nil];   // has the buyer's Apple ID
    [fm removeItemAtPath:[src.workDir stringByAppendingPathComponent:@"iTunesArtwork"] error:nil];
    [fm removeItemAtPath:[src.workDir stringByAppendingPathComponent:@"META-INF"] error:nil];

    // 3. Entitlements — read from the binary, isolate, and re-sign.
    progress(@"Isolating keychain / app groups…");
    NSString *binary = [src.appDir stringByAppendingPathComponent:src.executable];
    NSString *entsXML = nil;
    HZRun(ldid, @[ @"-e", binary ], nil, &entsXML);
    NSDictionary *ents = nil;
    if (entsXML.length) {
        NSRange start = [entsXML rangeOfString:@"<?xml"];
        if (start.location != NSNotFound) entsXML = [entsXML substringFromIndex:start.location];
        ents = [NSPropertyListSerialization propertyListWithData:[entsXML dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0 format:NULL error:nil];
    }
    NSDictionary *isolated = [self isolatedEntitlements:[ents isKindOfClass:NSDictionary.class] ? ents : @{} oldBid:oldBid newBid:newBid];
    NSString *entsPath = [src.workDir stringByAppendingPathComponent:@"clone-entitlements.plist"];
    if (![isolated writeToFile:entsPath atomically:YES]) { *error = @"Couldn't write entitlements."; return nil; }

    progress(@"Re-signing binary…");
    NSString *signOut = nil;
    int rc = HZRun(ldid, @[ [@"-S" stringByAppendingString:entsPath], binary ], nil, &signOut);
    if (rc != 0) { *error = [NSString stringWithFormat:@"ldid failed (%d): %@", rc, signOut]; return nil; }
    chmod(binary.fileSystemRepresentation, 0755);

    // 4. Zip back into an .ipa.
    progress(@"Packing .ipa…");
    [fm createDirectoryAtPath:HZOutputDir() withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *safeName = [[newName ?: src.name] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *outPath = [HZOutputDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%@).ipa", safeName, newBid]];
    [fm removeItemAtPath:outPath error:nil];
    NSString *zipOut = nil;
    rc = HZRun(zip, @[ @"-q", @"-r", @"-y", outPath, @"Payload" ], src.workDir, &zipOut);
    if (rc != 0 || ![fm fileExistsAtPath:outPath]) { *error = [NSString stringWithFormat:@"zip failed (%d): %@", rc, zipOut]; return nil; }
    return outPath;
}

#pragma mark Install

+ (void)installIPA:(NSString *)ipaPath bundleId:(NSString *)bundleId completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        BOOL ok = NO;
        @try {
            id ws = [NSClassFromString(@"LSApplicationWorkspace") valueForKey:@"defaultWorkspace"];
            NSURL *url = [NSURL fileURLWithPath:ipaPath];
            NSDictionary *opts = @{ @"CFBundleIdentifier": bundleId, @"PackageType": @"Developer", @"AllowInstallLocalProvisioned": @YES };
            SEL sel3 = NSSelectorFromString(@"installApplication:withOptions:error:");
            SEL sel2 = NSSelectorFromString(@"installApplication:withOptions:");
            NSError *nsErr = nil;
            if ([ws respondsToSelector:sel3]) {
                ok = ((BOOL (*)(id, SEL, NSURL *, NSDictionary *, NSError **))objc_msgSend)(ws, sel3, url, opts, &nsErr);
            } else if ([ws respondsToSelector:sel2]) {
                ok = ((BOOL (*)(id, SEL, NSURL *, NSDictionary *))objc_msgSend)(ws, sel2, url, opts);
            } else {
                err = @"LSApplicationWorkspace install API unavailable.";
            }
            if (!ok && !err) {
                err = nsErr ? nsErr.localizedDescription : @"installd refused the package.";
                err = [err stringByAppendingString:@"\nDirect install needs AppSync Unified. The .ipa was saved to Documents/Heavenzy — open it with TrollStore or Filza instead."];
            }
        } @catch (NSException *e) {
            err = [NSString stringWithFormat:@"Install crashed: %@", e.reason];
        }
        // Give installd a moment to register the app, then confirm.
        if (ok) {
            for (int i = 0; i < 20 && ![self isAppInstalled:bundleId]; i++) usleep(250 * 1000);
            if (![self isAppInstalled:bundleId]) { ok = NO; err = @"Install reported success but the app never appeared."; }
        }
        HZMain(^{ completion(ok, err); });
    });
}

+ (BOOL)enableSpoofingForApp:(NSString *)bundleId {
    NSDictionary *identity = HZGenerateIdentity();
    [HZConfig setIdentity:identity forApp:bundleId];
    [HZConfig setEnabled:YES forApp:bundleId];
    [HZConfig setWipePending:NO forApp:bundleId];
    // installd creates the data container asynchronously; retry a few times before giving up.
    for (int i = 0; i < 20; i++) {
        if ([HZContainerSync writeForApp:bundleId identity:identity enabled:YES wipePending:NO]) return YES;
        usleep(250 * 1000);
    }
    return NO;
}

@end

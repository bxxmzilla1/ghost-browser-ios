#import "HZCloud.h"
#import "HZConfig.h"
#import "HZArchive.h"
#import <UIKit/UIKit.h>

NSString *const HZCloudSessionDidChangeNotification = @"HZCloudSessionDidChange";

static NSString *const kSessionKey = @"HZCloudSession";   // NSUserDefaults (control app's own prefs,
                                                         // outside the libSandy-shared Heavenzy dir)
static NSString *const kBucket = @"containers";
static NSString *const kTable  = @"containers";
static NSString *const HZCloudErrorDomain = @"com.heavenzy.cloud";

static NSError *HZCloudError(NSInteger code, NSString *msg) {
    return [NSError errorWithDomain:HZCloudErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: msg ?: @"unknown error" }];
}

static void HZMain(dispatch_block_t b) { if (NSThread.isMainThread) b(); else dispatch_async(dispatch_get_main_queue(), b); }

@interface HZCloud () <NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(double)> *progressBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(NSURL *, NSURLResponse *, NSError *)> *downloadBlocks;
// Session
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *refreshToken;
@property (nonatomic, assign) NSTimeInterval expiresAt;   // unix time
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, strong) dispatch_queue_t authQueue;
- (NSError *)notConfiguredError;
@end

@implementation HZCloud

+ (instancetype)shared {
    static HZCloud *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HZCloud new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;
        cfg.timeoutIntervalForResource = 60 * 60;   // big archives over slow links
        cfg.waitsForConnectivity = YES;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
        _progressBlocks = [NSMutableDictionary dictionary];
        _downloadBlocks = [NSMutableDictionary dictionary];
        _authQueue = dispatch_queue_create("com.heavenzy.cloud.auth", DISPATCH_QUEUE_SERIAL);
        [self loadSession];
    }
    return self;
}

#pragma mark - Config / session persistence

- (NSString *)baseURL { return [HZConfig cloudURL]; }
- (NSString *)anonKey { return [HZConfig cloudAnonKey]; }
- (BOOL)configured { return self.baseURL.length > 8 && self.anonKey.length > 20; }
- (BOOL)signedIn { return self.accessToken.length > 0 && self.refreshToken.length > 0; }

- (void)loadSession {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSessionKey];
    self.accessToken  = d[@"access"];
    self.refreshToken = d[@"refresh"];
    self.expiresAt    = [d[@"expiresAt"] doubleValue];
    self.email        = d[@"email"];
    self.userId       = d[@"userId"];
}

- (void)storeSession:(NSDictionary *)auth {
    // GoTrue session: { access_token, refresh_token, expires_in, expires_at?, user: { id, email } }
    NSString *access = auth[@"access_token"], *refresh = auth[@"refresh_token"];
    if (![access isKindOfClass:NSString.class] || ![refresh isKindOfClass:NSString.class]) return;
    NSDictionary *user = [auth[@"user"] isKindOfClass:NSDictionary.class] ? auth[@"user"] : @{};
    NSTimeInterval expiresAt = [auth[@"expires_at"] doubleValue];
    if (expiresAt <= 0) expiresAt = [NSDate date].timeIntervalSince1970 + MAX(60.0, [auth[@"expires_in"] doubleValue] ?: 3600);
    self.accessToken = access; self.refreshToken = refresh; self.expiresAt = expiresAt;
    if ([user[@"email"] isKindOfClass:NSString.class]) self.email = user[@"email"];
    if ([user[@"id"] isKindOfClass:NSString.class]) self.userId = user[@"id"];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"access"] = access; d[@"refresh"] = refresh; d[@"expiresAt"] = @(expiresAt);
    if (self.email) d[@"email"] = self.email;
    if (self.userId) d[@"userId"] = self.userId;
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kSessionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HZMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:HZCloudSessionDidChangeNotification object:self]; });
}

- (void)clearSession {
    self.accessToken = nil; self.refreshToken = nil; self.expiresAt = 0; self.email = nil; self.userId = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSessionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HZMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:HZCloudSessionDidChangeNotification object:self]; });
}

#pragma mark - HTTP plumbing

// plist → JSON: dates become ISO strings, data becomes base64, anything else is described.
static id HZJSONSafe(id v) {
    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class] || v == NSNull.null) return v;
    if ([v isKindOfClass:NSDate.class]) return [[NSISO8601DateFormatter new] stringFromDate:v];
    if ([v isKindOfClass:NSData.class]) return [(NSData *)v base64EncodedStringWithOptions:0];
    if ([v isKindOfClass:NSArray.class]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id x in v) [a addObject:HZJSONSafe(x)];
        return a;
    }
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k, id x, BOOL *stop) { d[[k description]] = HZJSONSafe(x); }];
        return d;
    }
    return [v description] ?: NSNull.null;
}

// Pull a human-readable message out of a GoTrue / PostgREST / Storage error body.
static NSString *HZErrorMessage(NSData *data, NSInteger status) {
    id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([json isKindOfClass:NSDictionary.class]) {
        for (NSString *k in @[ @"msg", @"message", @"error_description", @"error", @"hint", @"details" ]) {
            id v = json[k];
            if ([v isKindOfClass:NSString.class] && [v length]) return v;
        }
    }
    NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (raw.length && raw.length < 200) return raw;
    return [NSString stringWithFormat:@"HTTP %ld", (long)status];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path {
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:path]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = method;
    r.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [r setValue:self.anonKey forHTTPHeaderField:@"apikey"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    return r;
}

- (void)setJSONBody:(id)obj on:(NSMutableURLRequest *)r {
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

// Plain data request; completion on an arbitrary queue.
- (void)send:(NSURLRequest *)r completion:(void (^)(NSInteger status, NSData *data, NSError *err))completion {
    if (!r.URL || !self.configured) { completion(0, nil, [self notConfiguredError]); return; }
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        if (err) { completion(0, nil, err); return; }
        completion(status, data, nil);
    }] resume];
}

// Make sure the access token is fresh (refreshing if within 60 s of expiry), then call `then`.
// Serialised so parallel callers don't race two refreshes with the same refresh token.
- (void)withFreshToken:(void (^)(NSError *err))then {
    dispatch_async(self.authQueue, ^{
        if (!self.signedIn) { then(HZCloudError(401, @"Not signed in.")); return; }
        if ([NSDate date].timeIntervalSince1970 < self.expiresAt - 60) { then(nil); return; }
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSError *result = nil;
        NSMutableURLRequest *r = [self requestWithMethod:@"POST" path:@"/auth/v1/token?grant_type=refresh_token"];
        [self setJSONBody:@{ @"refresh_token": self.refreshToken ?: @"" } on:r];
        [self send:r completion:^(NSInteger status, NSData *data, NSError *err) {
            if (err) result = err;
            else if (status >= 200 && status < 300) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json isKindOfClass:NSDictionary.class]) [self storeSession:json];
                else result = HZCloudError(status, @"Unexpected refresh response.");
            } else {
                // Refresh token revoked / expired → the user has to sign in again.
                [self clearSession];
                result = HZCloudError(status, [NSString stringWithFormat:@"Session expired (%@). Please sign in again.", HZErrorMessage(data, status)]);
            }
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
        then(result);
    });
}

// Authenticated request with automatic token refresh; retries once on 401.
- (void)authed:(NSMutableURLRequest *)r completion:(void (^)(NSInteger status, NSData *data, NSError *err))completion {
    [self withFreshToken:^(NSError *err) {
        if (err) { completion(0, nil, err); return; }
        [r setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
        [self send:r completion:^(NSInteger status, NSData *data, NSError *e2) {
            if (status != 401) { completion(status, data, e2); return; }
            self.expiresAt = 0;   // force a refresh, then one retry
            [self withFreshToken:^(NSError *e3) {
                if (e3) { completion(0, nil, e3); return; }
                [r setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
                [self send:r completion:completion];
            }];
        }];
    }];
}

#pragma mark - Auth

- (NSError *)notConfiguredError {
    return HZCloudError(0, @"Add your Supabase project URL and anon key first (Settings → Account).");
}

- (void)signUpWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(BOOL, NSError *))completion {
    if (!self.configured) { HZMain(^{ completion(NO, [self notConfiguredError]); }); return; }
    NSMutableURLRequest *r = [self requestWithMethod:@"POST" path:@"/auth/v1/signup"];
    [self setJSONBody:@{ @"email": email ?: @"", @"password": password ?: @"" } on:r];
    [self send:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { HZMain(^{ completion(NO, err); }); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil];
        if (status < 200 || status >= 300 || ![json isKindOfClass:NSDictionary.class]) {
            HZMain(^{ completion(NO, HZCloudError(status, HZErrorMessage(data, status))); });
            return;
        }
        // With "Confirm email" off, signup returns a full session. With it on, it returns just the
        // user and the account can't sign in until the link in the email is tapped.
        if (json[@"access_token"]) { [self storeSession:json]; HZMain(^{ completion(NO, nil); }); }
        else HZMain(^{ completion(YES, nil); });
    }];
}

- (void)signInWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(NSError *))completion {
    if (!self.configured) { HZMain(^{ completion([self notConfiguredError]); }); return; }
    NSMutableURLRequest *r = [self requestWithMethod:@"POST" path:@"/auth/v1/token?grant_type=password"];
    [self setJSONBody:@{ @"email": email ?: @"", @"password": password ?: @"" } on:r];
    [self send:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { HZMain(^{ completion(err); }); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil];
        if (status >= 200 && status < 300 && [json isKindOfClass:NSDictionary.class] && json[@"access_token"]) {
            [self storeSession:json];
            HZMain(^{ completion(nil); });
        } else {
            HZMain(^{ completion(HZCloudError(status, HZErrorMessage(data, status))); });
        }
    }];
}

- (void)signOut:(void (^)(void))completion {
    if (self.signedIn) {
        NSMutableURLRequest *r = [self requestWithMethod:@"POST" path:@"/auth/v1/logout"];
        [r setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
        [self send:r completion:^(NSInteger s, NSData *d, NSError *e) {}];   // best-effort revoke
    }
    [self clearSession];
    HZMain(^{ if (completion) completion(); });
}

#pragma mark - Containers table

static NSString *HZEnc(NSString *s) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+,/?:;#"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

- (void)listContainersForApp:(NSString *)bundleId completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSMutableString *path = [NSMutableString stringWithFormat:@"/rest/v1/%@?select=*&order=saved_at.desc.nullslast,created_at.desc", kTable];
    if (bundleId.length) [path appendFormat:@"&bundle_id=eq.%@", HZEnc(bundleId)];
    NSMutableURLRequest *r = [self requestWithMethod:@"GET" path:path];
    [self authed:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { HZMain(^{ completion(nil, err); }); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil];
        if (status >= 200 && status < 300 && [json isKindOfClass:NSArray.class]) {
            NSMutableArray *rows = [NSMutableArray array];
            for (id row in json) if ([row isKindOfClass:NSDictionary.class]) [rows addObject:row];
            HZMain(^{ completion(rows, nil); });
        } else {
            HZMain(^{ completion(nil, HZCloudError(status, HZErrorMessage(data, status))); });
        }
    }];
}

// Find the row for (bundleId, name), if one exists — an upload with the same name replaces it.
- (void)findContainerForApp:(NSString *)bundleId name:(NSString *)name completion:(void (^)(NSDictionary *row, NSError *err))completion {
    NSString *path = [NSString stringWithFormat:@"/rest/v1/%@?select=*&bundle_id=eq.%@&name=eq.%@&limit=1",
                      kTable, HZEnc(bundleId), HZEnc(name)];
    NSMutableURLRequest *r = [self requestWithMethod:@"GET" path:path];
    [self authed:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { completion(nil, err); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil];
        if (status >= 200 && status < 300 && [json isKindOfClass:NSArray.class]) completion([json firstObject], nil);
        else completion(nil, HZCloudError(status, HZErrorMessage(data, status)));
    }];
}

- (void)upsertRow:(NSDictionary *)row existingId:(NSString *)existingId completion:(void (^)(NSDictionary *saved, NSError *err))completion {
    NSMutableURLRequest *r;
    if (existingId.length) {
        r = [self requestWithMethod:@"PATCH" path:[NSString stringWithFormat:@"/rest/v1/%@?id=eq.%@", kTable, HZEnc(existingId)]];
    } else {
        r = [self requestWithMethod:@"POST" path:[NSString stringWithFormat:@"/rest/v1/%@", kTable]];
    }
    [r setValue:@"return=representation" forHTTPHeaderField:@"Prefer"];
    [self setJSONBody:row on:r];
    [self authed:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { completion(nil, err); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil];
        NSDictionary *saved = [json isKindOfClass:NSArray.class] ? [json firstObject] : ([json isKindOfClass:NSDictionary.class] ? json : nil);
        if (status >= 200 && status < 300) completion(saved ?: row, nil);
        else completion(nil, HZCloudError(status, HZErrorMessage(data, status)));
    }];
}

#pragma mark - Storage

- (NSString *)objectPathFor:(NSString *)bundleId id:(NSString *)rowId {
    // First folder = auth.uid() so the bucket policy can scope every user to their own tree.
    return [NSString stringWithFormat:@"%@/%@/%@.tar.gz", self.userId ?: @"anon", bundleId, rowId];
}

- (NSString *)encodedObjectPath:(NSString *)objectPath {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [objectPath componentsSeparatedByString:@"/"]) [parts addObject:HZEnc(p)];
    return [parts componentsJoinedByString:@"/"];
}

- (void)uploadFile:(NSString *)filePath toObject:(NSString *)objectPath
          progress:(void (^)(double))progress completion:(void (^)(NSError *err))completion {
    [self withFreshToken:^(NSError *err) {
        if (err) { completion(err); return; }
        NSString *path = [NSString stringWithFormat:@"/storage/v1/object/%@/%@", kBucket, [self encodedObjectPath:objectPath]];
        NSMutableURLRequest *r = [self requestWithMethod:@"POST" path:path];
        [r setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
        [r setValue:@"application/gzip" forHTTPHeaderField:@"Content-Type"];
        [r setValue:@"true" forHTTPHeaderField:@"x-upsert"];
        [r setValue:@"3600" forHTTPHeaderField:@"cache-control"];
        NSURLSessionUploadTask *task = [self.session uploadTaskWithRequest:r fromFile:[NSURL fileURLWithPath:filePath]
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
                NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
                if (e) { completion(e); return; }
                if (status >= 200 && status < 300) { completion(nil); return; }
                NSString *msg = HZErrorMessage(data, status);
                if (status == 413 || [msg.lowercaseString containsString:@"maximum allowed size"] || [msg.lowercaseString containsString:@"too large"])
                    msg = [NSString stringWithFormat:@"Archive is larger than your Supabase upload limit (%@). Raise the file size limit in Storage settings.", msg];
                completion(HZCloudError(status, msg));
            }];
        if (progress) { @synchronized (self.progressBlocks) { self.progressBlocks[@(task.taskIdentifier)] = progress; } }
        [task resume];
    }];
}

- (void)downloadObject:(NSString *)objectPath toFile:(NSString *)filePath
              progress:(void (^)(double))progress completion:(void (^)(NSError *err))completion {
    [self withFreshToken:^(NSError *err) {
        if (err) { completion(err); return; }
        NSString *path = [NSString stringWithFormat:@"/storage/v1/object/authenticated/%@/%@", kBucket, [self encodedObjectPath:objectPath]];
        NSMutableURLRequest *r = [self requestWithMethod:@"GET" path:path];
        [r setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
        [r setValue:@"*/*" forHTTPHeaderField:@"Accept"];
        NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:r];
        void (^done)(NSURL *, NSURLResponse *, NSError *) = ^(NSURL *tmp, NSURLResponse *resp, NSError *e) {
            NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
            if (e) { completion(e); return; }
            NSFileManager *fm = [NSFileManager defaultManager];
            if (status < 200 || status >= 300) {
                NSData *body = tmp ? [NSData dataWithContentsOfURL:tmp] : nil;
                completion(HZCloudError(status, HZErrorMessage(body, status)));
                return;
            }
            [fm removeItemAtPath:filePath error:nil];
            NSError *mv = nil;
            if (!tmp || ![fm moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:filePath] error:&mv]) {
                completion(HZCloudError(0, mv.localizedDescription ?: @"couldn't store the download"));
                return;
            }
            completion(nil);
        };
        @synchronized (self.downloadBlocks) { self.downloadBlocks[@(task.taskIdentifier)] = done; }
        if (progress) { @synchronized (self.progressBlocks) { self.progressBlocks[@(task.taskIdentifier)] = progress; } }
        [task resume];
    }];
}

- (void)deleteObject:(NSString *)objectPath completion:(void (^)(NSError *err))completion {
    NSMutableURLRequest *r = [self requestWithMethod:@"DELETE" path:[NSString stringWithFormat:@"/storage/v1/object/%@", kBucket]];
    [self setJSONBody:@{ @"prefixes": @[ objectPath ?: @"" ] } on:r];
    [self authed:r completion:^(NSInteger status, NSData *data, NSError *err) {
        if (err) { completion(err); return; }
        // 404 = already gone; treat as success so a half-deleted row can be cleaned up.
        if ((status >= 200 && status < 300) || status == 404) completion(nil);
        else completion(HZCloudError(status, HZErrorMessage(data, status)));
    }];
}

#pragma mark NSURLSession delegate (progress + download completion)

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didSendBodyData:(int64_t)sent
    totalBytesSent:(int64_t)total totalBytesExpectedToSend:(int64_t)expected {
    void (^p)(double); @synchronized (self.progressBlocks) { p = self.progressBlocks[@(task.taskIdentifier)]; }
    if (p && expected > 0) { double f = (double)total / (double)expected; HZMain(^{ p(f); }); }
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)w
    totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    void (^p)(double); @synchronized (self.progressBlocks) { p = self.progressBlocks[@(task.taskIdentifier)]; }
    if (p && expected > 0) { double f = (double)total / (double)expected; HZMain(^{ p(f); }); }
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    void (^done)(NSURL *, NSURLResponse *, NSError *);
    @synchronized (self.downloadBlocks) { done = self.downloadBlocks[@(task.taskIdentifier)]; [self.downloadBlocks removeObjectForKey:@(task.taskIdentifier)]; }
    // The temp file is deleted when this returns, so move it synchronously here.
    if (done) done(location, task.response, nil);
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @synchronized (self.progressBlocks) { [self.progressBlocks removeObjectForKey:@(task.taskIdentifier)]; }
    void (^done)(NSURL *, NSURLResponse *, NSError *);
    @synchronized (self.downloadBlocks) { done = self.downloadBlocks[@(task.taskIdentifier)]; [self.downloadBlocks removeObjectForKey:@(task.taskIdentifier)]; }
    if (done) done(nil, task.response, error ?: HZCloudError(0, @"download did not complete"));   // only reached on failure
}

#pragma mark - High-level container ops

static NSString *HZISO(NSDate *d) {
    if (![d isKindOfClass:NSDate.class]) return nil;
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    return [f stringFromDate:d];
}

static NSString *HZDeviceLabel(void) {
    return [NSString stringWithFormat:@"%@ · iOS %@", UIDevice.currentDevice.name, UIDevice.currentDevice.systemVersion];
}

- (void)uploadSnapshotAtPath:(NSString *)dir meta:(NSDictionary *)meta forApp:(NSString *)bundleId appName:(NSString *)appName
                    progress:(void (^)(double))progress completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!self.signedIn) { HZMain(^{ completion(nil, HZCloudError(401, @"Not signed in.")); }); return; }
    NSString *name = meta[@"name"] ?: dir.lastPathComponent;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // 1) Pack.
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"hz-up-%@.tar.gz", NSUUID.UUID.UUIDString]];
        NSError *packErr = nil;
        if (![HZArchive packDirectory:dir toFile:tmp error:&packErr]) { HZMain(^{ completion(nil, packErr); }); return; }
        unsigned long long archiveBytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:tmp error:nil] fileSize];
        NSDictionary *identity = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"identity.plist"]] ?: @{};
        NSDictionary *snapMeta = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"meta.plist"]] ?: @{};

        // 2) Reuse the row (and object) if this app already has a snapshot of this name.
        [self findContainerForApp:bundleId name:name completion:^(NSDictionary *existing, NSError *findErr) {
            if (findErr) { [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil]; HZMain(^{ completion(nil, findErr); }); return; }
            NSString *rowId = [existing[@"id"] isKindOfClass:NSString.class] ? existing[@"id"] : [NSUUID.UUID.UUIDString lowercaseString];
            NSString *objectPath = [existing[@"storage_path"] isKindOfClass:NSString.class] && [existing[@"storage_path"] length]
                ? existing[@"storage_path"] : [self objectPathFor:bundleId id:rowId];

            // 3) Upload the archive.
            [self uploadFile:tmp toObject:objectPath progress:progress completion:^(NSError *upErr) {
                [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
                if (upErr) { HZMain(^{ completion(nil, upErr); }); return; }

                // 4) Write the metadata row.
                NSMutableDictionary *row = [NSMutableDictionary dictionary];
                row[@"id"] = rowId;
                row[@"bundle_id"] = bundleId;
                row[@"app_name"] = appName ?: bundleId;
                row[@"name"] = name;
                NSString *saved = HZISO(meta[@"date"] ?: snapMeta[@"date"]);
                if (saved) row[@"saved_at"] = saved;
                if ([meta[@"version"] isKindOfClass:NSString.class]) row[@"app_version"] = meta[@"version"];
                if ([meta[@"build"] isKindOfClass:NSString.class])   row[@"app_build"] = meta[@"build"];
                row[@"bytes"] = @(archiveBytes);
                row[@"storage_path"] = objectPath;
                row[@"identity"] = HZJSONSafe(identity);
                row[@"device"] = HZDeviceLabel();
                if (self.userId) row[@"user_id"] = self.userId;
                [self upsertRow:row existingId:existing ? rowId : nil completion:^(NSDictionary *savedRow, NSError *rowErr) {
                    HZMain(^{ completion(rowErr ? nil : (savedRow ?: row), rowErr); });
                }];
            }];
        }];
    });
}

- (void)downloadContainer:(NSDictionary *)row toSnapshotsDir:(NSString *)appDir
                 progress:(void (^)(double))progress completion:(void (^)(NSString *, NSError *))completion {
    NSString *objectPath = row[@"storage_path"];
    NSString *name = [HZConfig sanitizeSnapshotName:row[@"name"]];
    if (![objectPath isKindOfClass:NSString.class] || !name) { HZMain(^{ completion(nil, HZCloudError(0, @"This saved login has no archive attached.")); }); return; }
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"hz-dl-%@.tar.gz", NSUUID.UUID.UUIDString]];
    [self downloadObject:objectPath toFile:tmp progress:progress completion:^(NSError *dlErr) {
        if (dlErr) { HZMain(^{ completion(nil, dlErr); }); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dest = [appDir stringByAppendingPathComponent:name];
            NSString *staging = [appDir stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.partial", name]];
            [fm removeItemAtPath:staging error:nil];
            NSError *unErr = nil;
            BOOL ok = [HZArchive unpackFile:tmp toDirectory:staging error:&unErr];
            [fm removeItemAtPath:tmp error:nil];
            if (!ok) { [fm removeItemAtPath:staging error:nil]; HZMain(^{ completion(nil, unErr); }); return; }
            // Make sure the tweak can trust it: meta.plist is what loadSnapshotNamed: checks for.
            if (![fm fileExistsAtPath:[staging stringByAppendingPathComponent:@"meta.plist"]]) {
                NSMutableDictionary *meta = [NSMutableDictionary dictionary];
                meta[@"name"] = name; meta[@"schema"] = @1;
                if ([row[@"app_version"] isKindOfClass:NSString.class]) meta[@"version"] = row[@"app_version"];
                if ([row[@"app_build"] isKindOfClass:NSString.class])   meta[@"build"] = row[@"app_build"];
                [meta writeToFile:[staging stringByAppendingPathComponent:@"meta.plist"] atomically:YES];
            }
            [fm removeItemAtPath:dest error:nil];
            NSError *mvErr = nil;
            if (![fm moveItemAtPath:staging toPath:dest error:&mvErr]) {
                [fm removeItemAtPath:staging error:nil];
                HZMain(^{ completion(nil, HZCloudError(0, mvErr.localizedDescription ?: @"couldn't place the snapshot")); });
                return;
            }
            HZMain(^{ completion(dest, nil); });
        });
    }];
}

- (void)renameContainer:(NSDictionary *)row to:(NSString *)name completion:(void (^)(NSError *))completion {
    NSString *rowId = row[@"id"];
    NSString *clean = [HZConfig sanitizeSnapshotName:name];
    if (![rowId isKindOfClass:NSString.class] || !clean) { HZMain(^{ completion(HZCloudError(0, @"Invalid name.")); }); return; }
    [self upsertRow:@{ @"name": clean } existingId:rowId completion:^(NSDictionary *saved, NSError *err) {
        HZMain(^{ completion(err); });
    }];
}

- (void)deleteContainer:(NSDictionary *)row completion:(void (^)(NSError *))completion {
    NSString *rowId = row[@"id"];
    NSString *objectPath = [row[@"storage_path"] isKindOfClass:NSString.class] ? row[@"storage_path"] : nil;
    if (![rowId isKindOfClass:NSString.class]) { HZMain(^{ completion(HZCloudError(0, @"Invalid row.")); }); return; }
    void (^deleteRow)(void) = ^{
        NSMutableURLRequest *r = [self requestWithMethod:@"DELETE" path:[NSString stringWithFormat:@"/rest/v1/%@?id=eq.%@", kTable, HZEnc(rowId)]];
        [self authed:r completion:^(NSInteger status, NSData *data, NSError *err) {
            if (err) { HZMain(^{ completion(err); }); return; }
            if (status >= 200 && status < 300) HZMain(^{ completion(nil); });
            else HZMain(^{ completion(HZCloudError(status, HZErrorMessage(data, status))); });
        }];
    };
    if (objectPath.length) [self deleteObject:objectPath completion:^(NSError *err) { if (err) HZMain(^{ completion(err); }); else deleteRow(); }];
    else deleteRow();
}

@end

#import "GBStore.h"

static NSString *GBPrefsPath(void) {
    // Inside the host app's sandbox — always writable, no cross-container sandbox issue.
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.ghost.blaze.plist"];
}

@implementation GBStore

+ (GBStore *)shared {
    static GBStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GBStore new]; [s reload]; });
    return s;
}

- (void)reload {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:GBPrefsPath()];
    _enabled       = [d[@"enabled"] boolValue];
    _deviceModel   = [d[@"deviceModel"] copy];
    _marketingName = [d[@"marketingName"] copy];
    _systemVersion = [d[@"systemVersion"] copy];
    _deviceName    = [d[@"deviceName"] copy] ?: @"iPhone";
    _idfv          = [d[@"idfv"] copy];
    _idfa          = [d[@"idfa"] copy];
    _proxyLink     = [d[@"proxyLink"] copy];
}

- (void)save {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"]       = @(_enabled);
    if (_deviceModel)   d[@"deviceModel"]   = _deviceModel;
    if (_marketingName) d[@"marketingName"] = _marketingName;
    if (_systemVersion) d[@"systemVersion"] = _systemVersion;
    if (_deviceName)    d[@"deviceName"]    = _deviceName;
    if (_idfv)          d[@"idfv"]          = _idfv;
    if (_idfa)          d[@"idfa"]          = _idfa;
    if (_proxyLink)     d[@"proxyLink"]     = _proxyLink;
    NSString *path = GBPrefsPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:path atomically:YES];
}

- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [self save]; }

- (BOOL)hasIdentity { return _deviceModel.length > 0; }

- (NSString *)summary {
    if (!self.hasIdentity) return @"Not spoofed yet";
    return [NSString stringWithFormat:@"%@ · iOS %@",
            _marketingName.length ? _marketingName : _deviceModel,
            _systemVersion.length ? _systemVersion : @"?"];
}

#pragma mark - Proxy

/// Parses socks5://user:pass@host:port · http://user:pass@host:port · host:port:user:pass · host:port.
/// Returns @{scheme,host,port,user,pass} or nil.
+ (NSDictionary *)parseProxy:(NSString *)raw {
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"|> \t"]];
    if (s.length == 0) return nil;

    NSString *scheme = @"http";
    NSString *rest = s;
    NSString *lower = s.lowercaseString;
    NSArray *pairs = @[ @[@"socks5://", @"socks5"], @[@"socks4://", @"socks5"], @[@"https://", @"http"], @[@"http://", @"http"] ];
    for (NSArray *p in pairs) {
        if ([lower hasPrefix:p[0]]) { scheme = p[1]; rest = [s substringFromIndex:[p[0] length]]; break; }
    }

    NSString *host = nil, *user = @"", *pass = @"";
    NSInteger port = 0;

    NSRange at = [rest rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound) {
        NSString *cred = [rest substringToIndex:at.location];
        NSString *hp = [rest substringFromIndex:at.location + 1];
        NSArray *hpP = [hp componentsSeparatedByString:@":"];
        if (hpP.count != 2) return nil;
        host = hpP[0]; port = [hpP[1] integerValue];
        NSRange c = [cred rangeOfString:@":"];
        if (c.location != NSNotFound) { user = [cred substringToIndex:c.location]; pass = [cred substringFromIndex:c.location + 1]; }
        else user = cred;
    } else {
        NSArray *parts = [rest componentsSeparatedByString:@":"];
        if (parts.count >= 4) { host = parts[0]; port = [parts[1] integerValue]; user = parts[2];
            pass = [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@":"]; }
        else if (parts.count == 2) { host = parts[0]; port = [parts[1] integerValue]; }
        else return nil;
    }
    if (host.length == 0 || port <= 0 || port > 65535) return nil;
    return @{ @"scheme": scheme, @"host": host, @"port": @(port), @"user": user ?: @"", @"pass": pass ?: @"" };
}

- (BOOL)setProxyFromLink:(NSString *)link {
    NSString *trimmed = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) { _proxyLink = @""; [self save]; return YES; }
    if (![GBStore parseProxy:trimmed]) return NO;
    _proxyLink = [trimmed copy];
    [self save];
    return YES;
}

- (BOOL)hasProxy { return [GBStore parseProxy:_proxyLink] != nil; }

- (NSString *)proxySummary {
    NSDictionary *p = [GBStore parseProxy:_proxyLink];
    if (!p) return @"Direct (no proxy)";
    BOOL auth = [p[@"user"] length] > 0;
    return [NSString stringWithFormat:@"%@ %@:%@%@", p[@"scheme"], p[@"host"], p[@"port"], auth ? @" (auth)" : @""];
}

- (NSDictionary *)proxyDictionary {
    NSDictionary *p = [GBStore parseProxy:_proxyLink];
    if (!p) return nil;
    NSString *host = p[@"host"]; NSNumber *port = p[@"port"];
    NSString *user = p[@"user"]; NSString *pass = p[@"pass"];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    // connectionProxyDictionary / CFNetwork string keys (portable across iOS versions).
    if ([p[@"scheme"] isEqualToString:@"socks5"]) {
        d[@"SOCKSEnable"] = @1; d[@"SOCKSProxy"] = host; d[@"SOCKSPort"] = port;
        if (user.length) d[@"SOCKSUser"] = user;
        if (pass.length) d[@"SOCKSPassword"] = pass;
    } else {
        d[@"HTTPEnable"] = @1;  d[@"HTTPProxy"] = host;  d[@"HTTPPort"] = port;
        d[@"HTTPSEnable"] = @1; d[@"HTTPSProxy"] = host; d[@"HTTPSPort"] = port;
    }
    if (user.length) d[@"kCFProxyUsername"] = user;
    if (pass.length) d[@"kCFProxyPassword"] = pass;
    return d;
}

- (void)installProxyCredential {
    NSDictionary *p = [GBStore parseProxy:_proxyLink];
    if (!p) return;
    NSString *user = p[@"user"], *pass = p[@"pass"];
    if (user.length == 0) return;   // no auth on this proxy
    NSString *host = p[@"host"];
    NSInteger port = [p[@"port"] integerValue];
    BOOL socks = [p[@"scheme"] isEqualToString:@"socks5"];

    NSURLCredential *cred = [NSURLCredential credentialWithUser:user password:pass
                                                    persistence:NSURLCredentialPersistenceForSession];
    NSMutableArray<NSURLProtectionSpace *> *spaces = [NSMutableArray array];
    if (socks) {
        [spaces addObject:[[NSURLProtectionSpace alloc] initWithProxyHost:host port:port
            type:NSURLProtectionSpaceSOCKSProxy realm:nil authenticationMethod:nil]];
    } else {
        [spaces addObject:[[NSURLProtectionSpace alloc] initWithProxyHost:host port:port
            type:NSURLProtectionSpaceHTTPProxy realm:nil authenticationMethod:nil]];
        [spaces addObject:[[NSURLProtectionSpace alloc] initWithProxyHost:host port:port
            type:NSURLProtectionSpaceHTTPSProxy realm:nil authenticationMethod:nil]];
    }
    NSURLCredentialStorage *storage = [NSURLCredentialStorage sharedCredentialStorage];
    for (NSURLProtectionSpace *ps in spaces) {
        [storage setDefaultCredential:cred forProtectionSpace:ps];
        [storage setCredential:cred forProtectionSpace:ps];
    }
}

// Plausible modern iPhones paired with a sensible iOS. hw.machine is the primary fingerprint.
+ (NSArray<NSArray<NSString *> *> *)devicePool {
    static NSArray *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            @[@"iPhone12,1", @"iPhone 11",          @"16.7.10"],
            @[@"iPhone12,3", @"iPhone 11 Pro",      @"16.7.10"],
            @[@"iPhone12,5", @"iPhone 11 Pro Max",  @"16.7.10"],
            @[@"iPhone13,1", @"iPhone 12 mini",     @"17.6.1"],
            @[@"iPhone13,2", @"iPhone 12",          @"17.6.1"],
            @[@"iPhone13,3", @"iPhone 12 Pro",      @"17.6.1"],
            @[@"iPhone13,4", @"iPhone 12 Pro Max",  @"17.6.1"],
            @[@"iPhone14,4", @"iPhone 13 mini",     @"17.6.1"],
            @[@"iPhone14,5", @"iPhone 13",          @"17.7.2"],
            @[@"iPhone14,2", @"iPhone 13 Pro",      @"17.7.2"],
            @[@"iPhone14,3", @"iPhone 13 Pro Max",  @"18.3.2"],
            @[@"iPhone14,7", @"iPhone 14",          @"18.5"],
            @[@"iPhone14,8", @"iPhone 14 Plus",     @"18.5"],
            @[@"iPhone15,2", @"iPhone 14 Pro",      @"18.5"],
            @[@"iPhone15,3", @"iPhone 14 Pro Max",  @"18.6"],
            @[@"iPhone15,4", @"iPhone 15",          @"18.6"],
            @[@"iPhone15,5", @"iPhone 15 Plus",     @"18.6"],
            @[@"iPhone16,1", @"iPhone 15 Pro",      @"18.6.1"],
            @[@"iPhone16,2", @"iPhone 15 Pro Max",  @"18.6.1"],
            @[@"iPhone17,3", @"iPhone 16",          @"18.6.1"],
            @[@"iPhone17,4", @"iPhone 16 Plus",     @"18.6.1"],
            @[@"iPhone17,1", @"iPhone 16 Pro",      @"18.6.1"],
            @[@"iPhone17,2", @"iPhone 16 Pro Max",  @"18.6.1"],
        ];
    });
    return pool;
}

static NSString *GBUUIDUpper(void) { return [[NSUUID UUID] UUIDString]; }

- (void)regenerateIdentity {
    NSArray<NSArray<NSString *> *> *pool = [GBStore devicePool];
    NSArray<NSString *> *pick = pool[arc4random_uniform((uint32_t)pool.count)];
    _deviceModel   = pick[0];
    _marketingName = pick[1];
    _systemVersion = pick[2];
    _deviceName    = @"iPhone";
    _idfv = GBUUIDUpper();
    _idfa = GBUUIDUpper();
    [self save];
    NSLog(@"[GhostBlaze] New spoofed device: %@ (%@) iOS %@", _marketingName, _deviceModel, _systemVersion);
}

@end

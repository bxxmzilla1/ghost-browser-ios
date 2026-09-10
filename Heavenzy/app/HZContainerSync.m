#import "HZContainerSync.h"
#import "HZConfig.h"

@implementation HZContainerSync

// Locate an app's data-container URL via LSApplicationWorkspace (resolved at runtime, no linking).
+ (NSURL *)dataContainerForApp:(NSString *)bundleId {
    if (bundleId.length == 0) return nil;
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id ws = [wsClass valueForKey:@"defaultWorkspace"];
        for (id p in [ws valueForKey:@"allApplications"]) {
            if ([[p valueForKey:@"applicationIdentifier"] isEqualToString:bundleId]) {
                id url = [p valueForKey:@"dataContainerURL"];   // NSURL of …/Data/Application/<uuid>
                return [url isKindOfClass:NSURL.class] ? url : nil;
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

// Container plist path for a bundle id, creating the Preferences dir. nil if the app has no container.
+ (NSString *)plistPathForApp:(NSString *)bundleId {
    NSURL *container = [self dataContainerForApp:bundleId];
    if (!container) return nil;
    NSString *prefsDir = [container.path stringByAppendingPathComponent:@"Library/Preferences"];
    [[NSFileManager defaultManager] createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:nil];
    return [prefsDir stringByAppendingPathComponent:@"com.heavenzy.plist"];
}

// Merge the current global SMS settings into a mutable container dict.
+ (void)applySmsSettingsInto:(NSMutableDictionary *)d {
    NSString *provider = [HZConfig smsProvider], *dk = [HZConfig diddyKey],
             *gk = [HZConfig grizzlyKey], *mp = [HZConfig grizzlyMaxPrice];
    d[@"smsProvider"] = provider.length ? provider : @"diddy";
    if (dk.length) d[@"diddyKey"]        = dk; else [d removeObjectForKey:@"diddyKey"];
    if (gk.length) d[@"grizzlyKey"]      = gk; else [d removeObjectForKey:@"grizzlyKey"];
    if (mp.length) d[@"grizzlyMaxPrice"] = mp; else [d removeObjectForKey:@"grizzlyMaxPrice"];
}

+ (NSInteger)writeSmsSettingsToAllApps {
    NSInteger n = 0;
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id ws = [wsClass valueForKey:@"defaultWorkspace"];
        for (id p in [ws valueForKey:@"allApplications"]) {
            if (![[p valueForKey:@"applicationType"] isEqualToString:@"User"]) continue;
            NSString *bid = [p valueForKey:@"applicationIdentifier"];
            if (bid.length == 0 || [bid isEqualToString:@"com.heavenzy.app"]) continue;
            NSString *path = [self plistPathForApp:bid];
            if (!path) continue;
            NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
            [self applySmsSettingsInto:d];
            if ([d writeToFile:path atomically:YES]) n++;
        }
    } @catch (__unused NSException *e) {}
    return n;
}

+ (BOOL)wipePendingForApp:(NSString *)bundleId {
    NSURL *container = [self dataContainerForApp:bundleId];
    if (!container) return [HZConfig wipePendingForApp:bundleId];   // never launched → central copy
    NSString *path = [container.path stringByAppendingPathComponent:@"Library/Preferences/com.heavenzy.plist"];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    return [d[@"wipePending"] boolValue];
}

+ (BOOL)writeForApp:(NSString *)bundleId
           identity:(NSDictionary *)identity
            enabled:(BOOL)enabled
        wipePending:(BOOL)wipePending {
    NSURL *container = [self dataContainerForApp:bundleId];
    if (!container) return NO;

    NSString *prefsDir = [container.path stringByAppendingPathComponent:@"Library/Preferences"];
    NSString *path = [prefsDir stringByAppendingPathComponent:@"com.heavenzy.plist"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Merge onto whatever is already there (keeps the floating-button position the in-app panel saved).
    NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];

    d[@"enabled"] = @(enabled);
    if (wipePending) d[@"wipePending"] = @YES; else [d removeObjectForKey:@"wipePending"];

    // Strip any legacy hardware-profile keys a previous version may have written — Heavenzy no longer
    // changes the model, so these must never linger.
    for (NSString *legacy in @[@"deviceModel", @"marketingName", @"systemVersion", @"screenPointsW",
                               @"screenPointsH", @"scaleFactor", @"cpuCores", @"memoryGB",
                               @"batteryLevel", @"batteryCharging", @"carrierName", @"mcc", @"mnc",
                               @"iso", @"timeZone", @"localeId"]) {
        [d removeObjectForKey:legacy];
    }

    // Map the shared HZDevice identity schema → the GBStore container keys the tweak reads.
    NSDictionary *i = [identity isKindOfClass:NSDictionary.class] ? identity : @{};
    void (^set)(NSString *, id) = ^(NSString *k, id v) { if (v) d[k] = v; };
    set(@"idfv",      i[@"idfv"]);
    set(@"idfa",      i[@"idfa"]);
    set(@"udid",      i[@"udid"]);
    set(@"serial",    i[@"serial"]);
    set(@"wifi",      i[@"wifi"]);
    set(@"bluetooth", i[@"bluetooth"]);
    set(@"imei",      i[@"imei"]);
    d[@"deviceName"] = @"iPhone";

    [self applySmsSettingsInto:d];   // keep the app's copy of the SMS provider settings fresh

    return [d writeToFile:path atomically:YES];
}

@end

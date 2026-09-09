#import "HZContainerSync.h"

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

    // Map the shared HZDevice identity schema → the GBStore container keys the tweak reads.
    NSDictionary *i = [identity isKindOfClass:NSDictionary.class] ? identity : @{};
    void (^set)(NSString *, id) = ^(NSString *k, id v) { if (v) d[k] = v; };
    set(@"deviceModel",   i[@"model"]);
    set(@"marketingName", i[@"name"]);
    set(@"systemVersion", i[@"ios"]);
    set(@"screenPointsW", i[@"w"]);
    set(@"screenPointsH", i[@"h"]);
    set(@"scaleFactor",   i[@"scale"]);
    set(@"cpuCores",      i[@"cores"]);
    set(@"memoryGB",      i[@"mem"]);
    set(@"idfv",          i[@"idfv"]);
    set(@"idfa",          i[@"idfa"]);
    set(@"udid",          i[@"udid"]);
    set(@"serial",        i[@"serial"]);
    if (i[@"batteryLevel"])    d[@"batteryLevel"]    = i[@"batteryLevel"];
    if (i[@"batteryCharging"]) d[@"batteryCharging"] = i[@"batteryCharging"];
    set(@"carrierName",   i[@"carrierName"]);
    set(@"mcc",           i[@"mcc"]);
    set(@"mnc",           i[@"mnc"]);
    set(@"iso",           i[@"iso"]);
    set(@"timeZone",      i[@"timeZone"]);
    set(@"localeId",      i[@"localeId"]);
    if (!d[@"deviceName"]) d[@"deviceName"] = @"iPhone";

    return [d writeToFile:path atomically:YES];
}

@end

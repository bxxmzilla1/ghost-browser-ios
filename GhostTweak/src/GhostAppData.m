#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>

// The tweak's own prefs plist — preserved across a reset so your device IDs / tokens / toggles
// survive a "Clear app data" (this mirrors Blaze keeping its own settings after a reset).
static NSString *const kGhostPrefsPlist = @"com.ghost.tweak.instagram.plist";

static void GhostRemoveDirContents(NSString *dir, NSArray<NSString *> *keep) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([keep containsObject:name]) continue;
        NSError *e = nil;
        NSString *p = [dir stringByAppendingPathComponent:name];
        if (![fm removeItemAtPath:p error:&e]) {
            NSLog(@"[GhostTweak] keep %@ (%@)", name, e.localizedDescription);
        }
    }
}

static void GhostWipeKeychain(void) {
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword,
                          (__bridge id)kSecClassCertificate,
                          (__bridge id)kSecClassKey,
                          (__bridge id)kSecClassIdentity ];
    for (id cls in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass: cls,
                             (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny };
        SecItemDelete((__bridge CFDictionaryRef)q);
    }
}

/// Blaze-style factory reset of the sideloaded app's own sandbox container. Wipes login state,
/// caches, cookies, web data and (optionally) keychain so the app behaves like a fresh install.
/// Returns a short human summary. Only ever touches THIS app's container — it cannot reach other
/// apps or the system on a non-jailbroken device.
NSString *GhostClearAppData(BOOL includeKeychain) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *home = NSHomeDirectory();

    // Documents and tmp: wipe entirely.
    GhostRemoveDirContents([home stringByAppendingPathComponent:@"Documents"], @[]);
    GhostRemoveDirContents([home stringByAppendingPathComponent:@"tmp"], @[]);

    // Library: wipe every subtree, but keep our own prefs plist inside Library/Preferences.
    NSString *lib = [home stringByAppendingPathComponent:@"Library"];
    for (NSString *sub in [fm contentsOfDirectoryAtPath:lib error:nil]) {
        NSString *subPath = [lib stringByAppendingPathComponent:sub];
        if ([sub isEqualToString:@"Preferences"]) {
            GhostRemoveDirContents(subPath, @[ kGhostPrefsPlist ]);
        } else {
            NSError *e = nil;
            if (![fm removeItemAtPath:subPath error:&e]) {
                NSLog(@"[GhostTweak] keep Library/%@ (%@)", sub, e.localizedDescription);
            }
        }
    }

    // In-memory / shared stores that may not be flushed to disk yet.
    NSHTTPCookieStorage *cs = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    for (NSHTTPCookie *c in [cs.cookies copy]) [cs deleteCookie:c];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                              modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
                                          completionHandler:^{}];

    if (includeKeychain) GhostWipeKeychain();

    NSLog(@"[GhostTweak] App data cleared (keychain=%d)", includeKeychain);
    return includeKeychain
        ? @"Instagram data + keychain cleared."
        : @"Instagram data cleared.";
}

/// There is no public "relaunch" API. Suspending first makes iOS treat the next cold launch as a
/// clean start, then we terminate so nothing rewrites the container on the way out.
void GhostCloseApp(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIApplication *app = UIApplication.sharedApplication;
        if ([app respondsToSelector:@selector(performSelector:withObject:)]) {
            @try { [app performSelector:@selector(suspend)]; } @catch (__unused id e) {}
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });
}

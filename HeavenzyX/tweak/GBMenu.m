#import "GBMenu.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>

#pragma mark - Data wipe helpers

static void GBRemoveDirContents(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
}

static void GBWipeKeychain(void) {
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword,
                          (__bridge id)kSecClassCertificate,
                          (__bridge id)kSecClassKey,
                          (__bridge id)kSecClassIdentity ];
    for (id cls in classes) {
        // kSecAttrSynchronizableAny also removes iCloud-Keychain-synced items, so a saved login
        // cannot be pulled back from the cloud after the wipe.
        SecItemDelete((__bridge CFDictionaryRef)@{
            (__bridge id)kSecClass: cls,
            (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny
        });
    }
}

/// Factory-reset the host app so it comes up as a brand-new install with no previous accounts:
/// sandbox (Documents/Library/tmp), NSUserDefaults domain, cookies, WebKit data and keychain
/// (including iCloud-synced items).
static void GBClearAppData(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    NSString *home = NSHomeDirectory();
    GBRemoveDirContents([home stringByAppendingPathComponent:@"Documents"]);
    GBRemoveDirContents([home stringByAppendingPathComponent:@"Library"]);
    GBRemoveDirContents([home stringByAppendingPathComponent:@"tmp"]);

    NSHTTPCookieStorage *cookies = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in [cookies.cookies copy]) { [cookies deleteCookie:c]; }

    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                               modifiedSince:[NSDate distantPast]
                                           completionHandler:^{}];
    GBWipeKeychain();
}

@implementation GBMenu
+ (void)clearAppData { GBClearAppData(); }
@end

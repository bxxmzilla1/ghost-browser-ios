#import "GBMenu.h"
#import "GBStore.h"
#import <WebKit/WebKit.h>
#import <Security/Security.h>

#pragma mark - Data wipe helpers

static void GBRemoveDirContents(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        // Keep our own identity file so "wipe" preserves the app's opt-in + fresh device we write next.
        if ([name isEqualToString:@"com.ghost.blaze.plist"]) continue;
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
        SecItemDelete((__bridge CFDictionaryRef)@{ (__bridge id)kSecClass: cls });
    }
}

/// Factory-reset the host app: sandbox (Documents/Library/tmp), cookies, WebKit data, keychain.
static void GBClearAppData(void) {
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

/// There is no public relaunch API; quitting cleanly makes the next open a fresh cold launch,
/// at which point the constructor re-reads the new identity and spoofs from the first frame.
static void GBQuit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

#pragma mark - Presentation

@implementation GBMenu

+ (UIViewController *)topVCForWindow:(UIWindow *)window {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)presentFromWindow:(UIWindow *)window {
    UIViewController *host = [self topVCForWindow:window];
    if (!host) return;
    GBStore *store = [GBStore shared];

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"this app";
    NSString *state = store.enabled ? @"ON" : @"OFF";
    NSString *msg = [NSString stringWithFormat:@"%@\n\nSpoofing: %@\nDevice: %@",
                     bundleID, state, store.summary];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"GhostBlaze"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    // Toggle opt-in for this app (takes effect on next launch, since IDs are read at startup).
    NSString *toggleTitle = store.enabled ? @"Disable spoofing for this app" : @"Enable spoofing for this app";
    [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle
                                              style:(store.enabled ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault)
                                            handler:^(UIAlertAction *a) {
        if (!store.enabled && !store.hasIdentity) [store regenerateIdentity];
        store.enabled = !store.enabled;
        [self confirm:host
                title:store.enabled ? @"Spoofing enabled" : @"Spoofing disabled"
              message:[NSString stringWithFormat:@"%@\nReopen the app to apply.", store.summary]
             thenQuit:YES];
    }]];

    if (store.enabled) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Randomize device"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [store regenerateIdentity];
            [self confirm:host title:@"New device"
                  message:[NSString stringWithFormat:@"%@\nReopen the app to apply.", store.summary]
                 thenQuit:YES];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"Wipe app data + re-spoof"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) {
            UIAlertController *c = [UIAlertController alertControllerWithTitle:@"Wipe this app?"
                message:@"Deletes this app's data, cookies, web data and keychain, then rolls a brand-new device. The app closes — reopen it as a fresh, spoofed install."
                preferredStyle:UIAlertControllerStyleAlert];
            [c addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [c addAction:[UIAlertAction actionWithTitle:@"Wipe + re-spoof" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                GBClearAppData();
                [store regenerateIdentity];   // rewrites com.ghost.blaze.plist with enabled=YES + new device
                GBQuit();
            }]];
            [host presentViewController:c animated:YES completion:nil];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];

    // iPad / action-sheet anchoring.
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = host.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(host.view.bounds.size.width / 2,
                                                                    host.view.bounds.size.height - 40, 1, 1);
        sheet.popoverPresentationController.permittedArrowDirections = 0;
    }
    [host presentViewController:sheet animated:YES completion:nil];
}

+ (void)confirm:(UIViewController *)host title:(NSString *)title message:(NSString *)message thenQuit:(BOOL)quit {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:(quit ? @"Close app" : @"OK")
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { if (quit) GBQuit(); }]];
    [host presentViewController:a animated:YES completion:nil];
}

@end

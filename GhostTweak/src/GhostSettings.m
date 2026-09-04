#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "GhostTokenStore.h"

#pragma mark - App data wipe (Blaze-style "Delete app data")

/// Resets the app's data container to a fresh-install state: cookies, URL cache, credentials,
/// WKWebView storage, the app's own NSUserDefaults, and everything under the container's
/// Documents/Library/tmp. The tweak's own token settings are re-saved afterwards so the panel
/// keeps its configuration across the wipe (like Blaze keeping its settings). The .app bundle and
/// the injected dylib live outside this container, so the tweak itself survives.
static void GhostWipeAppData(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Cookies (covers sessionid / ds_user_id / csrftoken → logged out).
    NSHTTPCookieStorage *cs = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in [cs.cookies copy]) { [cs deleteCookie:c]; }

    // HTTP cache + saved credentials.
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSURLCredentialStorage *cred = [NSURLCredentialStorage sharedCredentialStorage];
    NSDictionary *all = [cred.allCredentials copy];
    for (NSURLProtectionSpace *space in all) {
        NSDictionary *forSpace = all[space];
        for (NSString *user in forSpace) { [cred removeCredential:forSpace[user] forProtectionSpace:space]; }
    }

    // The app's own preferences.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length) { [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID]; }

    // WKWebView storage (async, best effort).
    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                              modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
                                          completionHandler:^{}];

    // Container directories — delete everything inside the standard folders.
    NSString *home = NSHomeDirectory();
    for (NSString *sub in @[@"Documents", @"Library", @"tmp", @"SystemData"]) {
        NSString *dir = [home stringByAppendingPathComponent:sub];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        for (NSString *child in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:child] error:nil];
        }
    }

    // Recreate the folders IG expects to exist immediately on next launch.
    for (NSString *sub in @[@"Documents", @"Library/Caches", @"Library/Preferences", @"tmp"]) {
        [fm createDirectoryAtPath:[home stringByAppendingPathComponent:sub]
      withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Persist the tweak's own tokens again so the panel keeps its configuration.
    [[GhostTokenStore shared] save];

    NSLog(@"[GhostTweak] App data wiped (fresh-install reset)");
}

@interface GhostSettingsController : UITableViewController
@property (nonatomic, strong) UITextView *pasteView;
@end

@implementation GhostSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ghost Tweak";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(done)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 4;
        case 2: return 1;
        case 3: return 1;
        case 4: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Injection";
        case 1: return @"Actions";
        case 2: return @"Paste token block";
        case 3: return @"Status";
        case 4: return @"Danger zone";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return @"Paste the Key: value block from GhostBrowser → Instagram bridge. Import injects cookies immediately; force-quit Instagram if the feed stays logged out.";
    }
    if (section == 4) {
        return @"Wipes cookies, caches and all app data so Instagram reopens as a fresh install (logged out). Your tweak tokens above are kept. Instagram will close when done — reopen it manually.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GhostTokenStore *t = [GhostTokenStore shared];
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] init];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Inject request headers";
            sw.on = t.injectHeaders;
            [sw addTarget:self action:@selector(toggleHeaders:) forControlEvents:UIControlEventValueChanged];
        } else {
            cell.textLabel.text = @"Inject login cookies";
            sw.on = t.injectCookies;
            [sw addTarget:self action:@selector(toggleCookies:) forControlEvents:UIControlEventValueChanged];
        }
        cell.accessoryView = sw;
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        if (indexPath.row == 0) cell.textLabel.text = @"Import from paste field";
        else if (indexPath.row == 1) cell.textLabel.text = @"Paste from clipboard";
        else if (indexPath.row == 2) cell.textLabel.text = @"Copy token block";
        else cell.textLabel.text = @"Generate missing device IDs";
        if (indexPath.row == 0) cell.textLabel.textColor = self.view.tintColor;
        return cell;
    }
    if (indexPath.section == 4) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Delete app data (fresh install)";
        cell.textLabel.textColor = [UIColor systemRedColor];
        return cell;
    }
    if (indexPath.section == 2) {
        static NSString *rid = @"paste";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
            self.pasteView = [[UITextView alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 8, 8)];
            self.pasteView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.pasteView.font = [UIFont fontWithName:@"Menlo" size:11];
            self.pasteView.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.pasteView.autocorrectionType = UITextAutocorrectionTypeNo;
            [cell.contentView addSubview:self.pasteView];
        }
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = t.sessionid.length ? @"Login tokens loaded" : @"No login tokens";
    cell.detailTextLabel.text = t.igUserID.length ?
        [NSString stringWithFormat:@"User %@ · %lu headers", t.igUserID, (unsigned long)t.requestHeaders.count] :
        @"Need sessionid + IG-U-DS-USER-ID";
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 2 ? 170 : UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    GhostTokenStore *t = [GhostTokenStore shared];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [t applyTextBlock:self.pasteView.text ?: @""];
            extern void GhostInjectCookies(void);
            GhostInjectCookies();
            [self alert:@"Imported" msg:@"Tokens saved and cookies injected."];
        } else if (indexPath.row == 1) {
            self.pasteView.text = [UIPasteboard generalPasteboard].string ?: @"";
        } else if (indexPath.row == 2) {
            [UIPasteboard generalPasteboard].string = [t textBlock];
            [self alert:@"Copied" msg:@"Token block on clipboard."];
        } else {
            [t fillMissingGeneratedIDs];
            [self alert:@"Generated" msg:@"Empty device IDs filled."];
        }
        [self.tableView reloadData];
    } else if (indexPath.section == 4) {
        [self confirmWipe];
    }
}

- (void)confirmWipe {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete app data?"
        message:@"Instagram will be logged out and reset to a fresh install. Your tweak tokens are kept. The app will close afterward."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete & Close" style:UIAlertActionStyleDestructive
                                        handler:^(__unused UIAlertAction *act) {
        GhostWipeAppData();
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"App data cleared"
            message:@"Instagram will now close. Reopen it for a fresh, logged-out session."
            preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"Close now" style:UIAlertActionStyleDefault
                                              handler:^(__unused UIAlertAction *a2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ exit(0); });
        }]];
        [self presentViewController:done animated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toggleHeaders:(UISwitch *)sw {
    [GhostTokenStore shared].injectHeaders = sw.on;
    [[GhostTokenStore shared] save];
}

- (void)toggleCookies:(UISwitch *)sw {
    [GhostTokenStore shared].injectCookies = sw.on;
    [[GhostTokenStore shared] save];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

@interface GhostSettingsOpener : NSObject
@end
@implementation GhostSettingsOpener
- (void)open:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateRecognized) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *key = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (!key) return;
        UIViewController *root = key.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if ([root isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)root viewControllers].firstObject isKindOfClass:[GhostSettingsController class]]) {
            return;
        }
        GhostSettingsController *vc = [[GhostSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [root presentViewController:nav animated:YES completion:nil];
    });
}
@end

void GhostInstallSettingsGesture(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *key = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (!key) return;
        static GhostSettingsOpener *opener;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            opener = [[GhostSettingsOpener alloc] init];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:opener action:@selector(open:)];
            tap.numberOfTouchesRequired = 3;
            tap.numberOfTapsRequired = 2;
            [key addGestureRecognizer:tap];
        });
        NSLog(@"[GhostTweak] Open settings: 3-finger double-tap anywhere");
    });
}

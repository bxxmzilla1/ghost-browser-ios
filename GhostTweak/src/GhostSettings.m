#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "GhostTokenStore.h"

extern NSString *GhostClearAppData(BOOL includeKeychain);
extern NSString *GhostWipeAndRespoof(BOOL includeKeychain);
extern void GhostCloseApp(void);
extern BOOL GhostConsumeBridgeForced(BOOL force);

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 5;
        case 2: return 1;
        case 3: return 2;   // Device: current device / randomize now
        case 4: return 3;   // Reset: clear data / clear data + keychain / new device
        case 5: return 1;   // Status
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Injection";
        case 1: return @"Actions";
        case 2: return @"Paste token block";
        case 3: return @"Spoofed device";
        case 4: return @"Reset";
        case 5: return @"Status";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return @"Paste the Key: value block from GhostBrowser → Instagram bridge. Import injects cookies immediately; force-quit Instagram if the feed stays logged out.";
    }
    if (section == 3) {
        return @"Instagram sees this hardware (model, iOS, IDFV/IDFA, ig_did). \"Randomize now\" picks a new device and relaunches. Nothing links back to the previous identity.";
    }
    if (section == 4) {
        return @"\"New spoofed device\" wipes Instagram to a fresh install AND rolls a new device — the app reopens as a brand-new, spoofed phone. \"Clear app data\" resets without changing the device. Your Ghost Tweak settings are kept; only this app is affected. The app closes afterwards — reopen it.";
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
        else if (indexPath.row == 3) cell.textLabel.text = @"Generate missing device IDs";
        else cell.textLabel.text = @"Import login from GhostBrowser";
        if (indexPath.row == 0 || indexPath.row == 4) cell.textLabel.textColor = self.view.tintColor;
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
    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = [t deviceSummary];
            cell.detailTextLabel.text = t.deviceModel.length ?
                [NSString stringWithFormat:@"%@ · IDFV %@", t.deviceModel,
                 t.idfv.length >= 8 ? [t.idfv substringToIndex:8] : t.idfv] :
                @"Tap Randomize to spoof";
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        }
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Randomize device now";
        cell.textLabel.textColor = self.view.tintColor;
        return cell;
    }
    if (indexPath.section == 4) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        if (indexPath.row == 0) cell.textLabel.text = @"Clear app data";
        else if (indexPath.row == 1) cell.textLabel.text = @"Clear app data + keychain";
        else cell.textLabel.text = @"New spoofed device (wipe + re-spoof)";
        cell.textLabel.textColor = [UIColor systemRedColor];
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
        } else if (indexPath.row == 3) {
            [t fillMissingGeneratedIDs];
            [self alert:@"Generated" msg:@"Empty device IDs filled."];
        } else {
            if (!GhostConsumeBridgeForced(YES)) {
                [self alert:@"Nothing to import"
                        msg:@"No GhostBrowser login on the clipboard. In GhostBrowser: Instagram bridge → Send login to Instagram app, then return here."];
            }
        }
        [self.tableView reloadData];
    } else if (indexPath.section == 3) {
        if (indexPath.row == 1) [self confirmRandomizeDevice];
    } else if (indexPath.section == 4) {
        if (indexPath.row == 2) [self confirmNewDevice];
        else [self confirmClearIncludingKeychain:(indexPath.row == 1)];
    }
}

- (void)confirmRandomizeDevice {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Randomize device?"
        message:@"Instagram will report a new iPhone model, iOS version and fresh IDFV/IDFA/ig_did. Your login and data are kept. The app relaunches to apply it."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Randomize" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [[GhostTokenStore shared] regenerateDeviceProfile];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"New device"
            message:[[[GhostTokenStore shared] deviceSummary] stringByAppendingString:@"\nRelaunching…"]
            preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:done animated:YES completion:^{ GhostCloseApp(); }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmNewDevice {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"New spoofed device?"
        message:@"Wipes Instagram to a fresh install (data, cookies, keychain) AND rolls a brand-new device identity. Ghost Tweak settings are kept. The app closes — reopen it as a new phone."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Wipe + re-spoof" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        NSString *summary = GhostWipeAndRespoof(YES);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
            message:[summary stringByAppendingString:@"\nClosing…"] preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:done animated:YES completion:^{ GhostCloseApp(); }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmClearIncludingKeychain:(BOOL)includeKeychain {
    NSString *title = includeKeychain ? @"Clear app data + keychain?" : @"Clear app data?";
    NSString *msg = includeKeychain
        ? @"Instagram will be reset to a fresh install and saved logins removed. Ghost Tweak tokens are kept. The app will close."
        : @"Instagram will be reset to a fresh install. Ghost Tweak tokens are kept. The app will close.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        NSString *summary = GhostClearAppData(includeKeychain);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
            message:[summary stringByAppendingString:@"\nClosing…"] preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:done animated:YES completion:^{ GhostCloseApp(); }];
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

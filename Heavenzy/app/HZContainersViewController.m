#import "HZContainersViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZContainerSync.h"

typedef NS_ENUM(NSInteger, HZContainersSection) {
    HZContainersPending,   // (only shown when a save/restore is queued)
    HZContainersError,     // (only shown when the last op failed)
    HZContainersSave,      // "Save current login" button
    HZContainersList,      // saved snapshots
    HZContainersCount
};

@interface HZContainersViewController ()
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSArray<NSDictionary *> *snapshots;   // from HZConfig
@property (nonatomic, copy) NSString *pendingSave;
@property (nonatomic, copy) NSString *pendingLoad;
@property (nonatomic, copy) NSString *lastError;
@end

@implementation HZContainersViewController

- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _bundleId = [bundleId copy];
        _appName = [name copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Saved Logins";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (void)reload {
    self.snapshots = [HZConfig snapshotsForApp:self.bundleId];
    // The app's own container is the source of truth: the tweak clears the flag there the moment it
    // runs. The central copy can lag behind when libSandy isn't working, so never trust it alone —
    // if the container says nothing is queued, also clear the stale central flag.
    NSDictionary *state = [HZContainerSync snapshotStateForApp:self.bundleId];
    self.pendingSave = state[@"snapSave"];
    self.pendingLoad = state[@"snapLoad"];
    self.lastError   = state[@"snapLastError"];
    if (!self.pendingSave && [HZConfig snapshotSavePendingForApp:self.bundleId]) [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
    if (!self.pendingLoad && [HZConfig snapshotLoadPendingForApp:self.bundleId]) [HZConfig setSnapshotLoadPending:nil forApp:self.bundleId];
    [self.tableView reloadData];
}

- (void)cancelPending {
    [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
    [HZContainerSync queueSnapshotSave:nil load:nil forApp:self.bundleId];
    [self reload];
}

- (BOOL)hasPending { return self.pendingSave.length || self.pendingLoad.length; }

#pragma mark - Formatting

- (NSString *)subtitleFor:(NSDictionary *)snap {
    NSMutableArray *bits = [NSMutableArray array];
    NSDate *date = snap[@"date"];
    if ([date isKindOfClass:NSDate.class]) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateStyle = NSDateFormatterMediumStyle; f.timeStyle = NSDateFormatterShortStyle;
        [bits addObject:[f stringFromDate:date]];
    }
    NSNumber *bytes = snap[@"bytes"];
    if ([bytes isKindOfClass:NSNumber.class] && bytes.unsignedLongLongValue)
        [bits addObject:[NSByteCountFormatter stringFromByteCount:bytes.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    NSString *ver = snap[@"version"];
    if ([ver isKindOfClass:NSString.class] && ver.length) [bits addObject:[NSString stringWithFormat:@"v%@", ver]];
    return [bits componentsJoinedByString:@"  ·  "];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZContainersCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case HZContainersPending: return [self hasPending] ? 1 : 0;
        case HZContainersError:   return (self.lastError.length && ![self hasPending]) ? 1 : 0;
        case HZContainersSave:    return 1;
        case HZContainersList:    return self.snapshots.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == HZContainersList && self.snapshots.count) return @"SAVED LOGINS";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == HZContainersPending && [self hasPending])
        return @"Tap to cancel. A queued save doesn't change anything in the app; it's captured — and cleared — "
               @"the moment the app next launches.";
    if (s == HZContainersError && self.lastError.length && ![self hasPending])
        return @"The tweak ran but couldn't complete the last request. If it mentions libSandy, make sure the "
               @"libSandy package is installed and reboot once, then try again.";
    if (s == HZContainersSave)
        return @"Saves the current account exactly as it is now — files, cookies and keychain — plus the "
               @"spoofed identity it runs on. The save finishes the next time you open the app.";
    if (s == HZContainersList) {
        if (self.snapshots.count == 0) return @"No saved logins yet. Log into an account, then tap Save current login.";
        return @"Tap a saved login to restore it and get back into that account on next launch. Swipe a row "
               @"to rename or delete it. Restoring replaces whatever is currently in the app.";
    }
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = HZTextMuted();
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;
    cell.tintColor = HZAccent();

    if (ip.section == HZContainersPending) {
        BOOL saving = self.pendingSave.length > 0;
        cell.textLabel.text = saving ? @"Save queued" : @"Restore queued";
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = HZAccent();
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.text = saving
            ? [NSString stringWithFormat:@"Open %@ to finish saving \"%@\".", self.appName, self.pendingSave]
            : [NSString stringWithFormat:@"Open %@ to finish restoring \"%@\".", self.appName, self.pendingLoad];
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.imageView.tintColor = HZAccent();
        UIImageView *x = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]];
        x.tintColor = HZTextMuted();
        cell.accessoryView = x;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    if (ip.section == HZContainersError) {
        cell.textLabel.text = @"Last request failed";
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = HZDanger();
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.text = self.lastError;
        cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        cell.imageView.tintColor = HZDanger();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (ip.section == HZContainersSave) {
        cell.textLabel.text = @"Save current login";
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = HZAccent();
        cell.detailTextLabel.text = @"Snapshot the account that's logged in now";
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down.fill"];
        cell.imageView.tintColor = HZAccent();
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    NSDictionary *snap = self.snapshots[ip.row];
    cell.textLabel.text = snap[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text = [self subtitleFor:snap];
    cell.imageView.image = [UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"];
    cell.imageView.tintColor = HZAccent();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == HZContainersPending) { [self confirmCancel]; return; }
    if (ip.section == HZContainersSave) { [self promptSave]; return; }
    if (ip.section == HZContainersList) { [self confirmLoad:self.snapshots[ip.row][@"name"]]; return; }
}

#pragma mark - Swipe actions (rename / delete)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != HZContainersList) return nil;
    NSString *name = self.snapshots[ip.row][@"name"];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self confirmDelete:name]; done(YES); }];
    UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self promptRename:name]; done(YES); }];
    ren.backgroundColor = HZAccent();
    return [UISwipeActionsConfiguration configurationWithActions:@[ del, ren ]];
}

#pragma mark - Actions

- (void)confirmCancel {
    BOOL saving = self.pendingSave.length > 0;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:saving ? @"Cancel Queued Save?" : @"Cancel Queued Restore?"
        message:saving ? @"The current login won't be saved." : @"The current state of the app will be left as is."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Keep" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel Request" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) { [self cancelPending]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptSave {
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"MMM d, h:mm a";
    NSString *suggested = [f stringFromDate:[NSDate date]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Save Current Login"
        message:[NSString stringWithFormat:@"Name this snapshot of %@'s current account. It's captured the next time you open the app.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"e.g. main account"; tf.text = suggested; tf.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Queue Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *name = [HZConfig sanitizeSnapshotName:a.textFields.firstObject.text];
        if (!name) { [self toast:@"Enter a name"]; return; }
        [self queueSave:name];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)queueSave:(NSString *)name {
    // Overwrite warning if a snapshot of this name already exists.
    BOOL exists = NO;
    for (NSDictionary *s in self.snapshots) if ([s[@"name"] isEqualToString:name]) { exists = YES; break; }
    void (^go)(void) = ^{
        [HZConfig setSnapshotSavePending:name forApp:self.bundleId];
        if (![HZContainerSync queueSnapshotSave:name load:nil forApp:self.bundleId]) {
            [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
            [self openAppAlert:@"Couldn't reach the app's container. Open the app once, then try again."];
            [self reload];
            return;
        }
        [self reload];
        [self openAppAlert:[NSString stringWithFormat:@"Now open %@ to finish saving \"%@\".", self.appName, name]];
    };
    if (!exists) { go(); return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Overwrite?"
        message:[NSString stringWithFormat:@"A saved login named \"%@\" already exists. Saving will replace it.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Overwrite" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) { go(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmLoad:(NSString *)name {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Restore This Login?"
        message:[NSString stringWithFormat:@"Restoring \"%@\" replaces whatever is currently in %@ (its files, cookies and keychain) and puts back the saved account and its spoofed identity. This happens the next time you open the app.", name, self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [HZConfig setSnapshotLoadPending:name forApp:self.bundleId];
        if (![HZContainerSync queueSnapshotSave:nil load:name forApp:self.bundleId]) {
            [HZConfig setSnapshotLoadPending:nil forApp:self.bundleId];
            [self openAppAlert:@"Couldn't reach the app's container. Open the app once, then try again."];
            [self reload];
            return;
        }
        [self reload];
        [self openAppAlert:[NSString stringWithFormat:@"Now open %@ to finish restoring \"%@\".", self.appName, name]];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptRename:(NSString *)name {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = name; tf.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *newName = a.textFields.firstObject.text;
        if ([HZConfig renameSnapshotNamed:name to:newName forApp:self.bundleId]) [self reload];
        else [self toast:@"Couldn't rename (name in use?)"];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(NSString *)name {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete Saved Login?"
        message:[NSString stringWithFormat:@"\"%@\" will be permanently deleted. This can't be undone.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [HZConfig deleteSnapshotNamed:name forApp:self.bundleId];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Small helpers

- (void)openAppAlert:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Queued" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

@end

#import "HZContainersViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZContainerSync.h"
#import "HZCloud.h"

typedef NS_ENUM(NSInteger, HZContainersSection) {
    HZContainersPending,   // (only shown when a save/restore is queued)
    HZContainersError,     // (only shown when the last op failed)
    HZContainersSave,      // "Save current login" button
    HZContainersList,      // saved logins (local ∪ account)
    HZContainersCount
};

/// One row of the list. A login can live on the iPhone (`local`), in the account (`cloud`), or both
/// (briefly, while it's being uploaded or right after it was downloaded for a restore).
@interface HZContainerItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDictionary *local;    // entry from +[HZConfig snapshotsForApp:]
@property (nonatomic, copy) NSDictionary *cloud;    // row from HZCloud
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) unsigned long long bytes;
@property (nonatomic, copy) NSString *version;
@end
@implementation HZContainerItem
@end

static NSDate *HZParseISO(id v) {
    if (![v isKindOfClass:NSString.class]) return nil;
    NSString *s = v;
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    NSDate *d = [f dateFromString:s];
    if (d) return d;
    f.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    // Postgres may emit more than 3 fractional digits; trim to milliseconds.
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\.\\d{3})\\d+" options:0 error:nil];
    s = [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1"];
    if ([s hasSuffix:@"+00:00"]) s = [[s substringToIndex:s.length - 6] stringByAppendingString:@"Z"];
    return [f dateFromString:s];
}

@interface HZContainersViewController ()
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSArray<NSDictionary *> *localSnapshots;
@property (nonatomic, copy) NSArray<NSDictionary *> *cloudRows;      // nil until fetched
@property (nonatomic, copy) NSArray<HZContainerItem *> *items;
@property (nonatomic, copy) NSString *pendingSave;
@property (nonatomic, copy) NSString *pendingLoad;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, copy) NSString *cloudError;

// Transfer state (one at a time), keyed by login name.
@property (nonatomic, copy) NSString *uploading;
@property (nonatomic, copy) NSString *downloading;
@property (nonatomic, assign) double transferFraction;
@property (nonatomic, assign) BOOL fetchingCloud;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged)
                                                 name:HZCloudSessionDidChangeNotification object:nil];
    [self reload];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (void)sessionChanged { self.cloudRows = nil; self.cloudError = nil; [self reload]; }

- (BOOL)cloudOn { return [HZCloud shared].signedIn; }

#pragma mark - Loading / merging

- (void)reload {
    self.localSnapshots = [HZConfig snapshotsForApp:self.bundleId];
    // The app's own container is the source of truth: the tweak clears the flag there the moment it
    // runs. The central copy can lag behind when libSandy isn't working, so never trust it alone —
    // if the container says nothing is queued, also clear the stale central flag.
    NSDictionary *state = [HZContainerSync snapshotStateForApp:self.bundleId];
    self.pendingSave = state[@"snapSave"];
    self.pendingLoad = state[@"snapLoad"];
    self.lastError   = state[@"snapLastError"];
    if (!self.pendingSave && [HZConfig snapshotSavePendingForApp:self.bundleId]) [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
    if (!self.pendingLoad && [HZConfig snapshotLoadPendingForApp:self.bundleId]) [HZConfig setSnapshotLoadPending:nil forApp:self.bundleId];
    [self rebuildItems];
    if ([self cloudOn]) [self fetchCloud];
}

- (void)fetchCloud {
    if (self.fetchingCloud) return;
    self.fetchingCloud = YES;
    [[HZCloud shared] listContainersForApp:self.bundleId completion:^(NSArray<NSDictionary *> *rows, NSError *error) {
        self.fetchingCloud = NO;
        if (error) { self.cloudError = error.localizedDescription; }
        else { self.cloudError = nil; self.cloudRows = rows; }
        [self rebuildItems];
        if (!error) [self syncWithCloud];
    }];
}

- (void)rebuildItems {
    NSMutableDictionary<NSString *, HZContainerItem *> *byName = [NSMutableDictionary dictionary];
    for (NSDictionary *s in self.localSnapshots) {
        HZContainerItem *it = [HZContainerItem new];
        it.name = s[@"name"];
        it.local = s;
        it.date = [s[@"date"] isKindOfClass:NSDate.class] ? s[@"date"] : nil;
        it.bytes = [s[@"bytes"] unsignedLongLongValue];
        it.version = [s[@"version"] isKindOfClass:NSString.class] ? s[@"version"] : nil;
        if (it.name) byName[it.name] = it;
    }
    if ([self cloudOn]) {
        for (NSDictionary *r in self.cloudRows) {
            NSString *name = r[@"name"];
            if (![name isKindOfClass:NSString.class]) continue;
            HZContainerItem *it = byName[name] ?: [HZContainerItem new];
            it.name = name;
            it.cloud = r;
            NSDate *d = HZParseISO(r[@"saved_at"]);
            if (!it.date || (d && [d compare:it.date] == NSOrderedDescending)) it.date = d ?: it.date;
            if (!it.bytes) it.bytes = [r[@"bytes"] unsignedLongLongValue];
            if (!it.version && [r[@"app_version"] isKindOfClass:NSString.class]) it.version = r[@"app_version"];
            byName[name] = it;
        }
    }
    self.items = [byName.allValues sortedArrayUsingComparator:^NSComparisonResult(HZContainerItem *a, HZContainerItem *b) {
        NSDate *da = a.date ?: NSDate.distantPast, *db = b.date ?: NSDate.distantPast;
        NSComparisonResult r = [db compare:da];
        return r != NSOrderedSame ? r : [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    [self.tableView reloadData];
}

- (HZContainerItem *)itemNamed:(NSString *)name {
    for (HZContainerItem *it in self.items) if ([it.name isEqualToString:name]) return it;
    return nil;
}

/// Local copy is the same capture the account already has (downloaded for a restore, or uploaded).
- (BOOL)localMatchesCloud:(HZContainerItem *)it {
    if (!it.local || !it.cloud) return NO;
    NSDate *l = it.local[@"date"], *c = HZParseISO(it.cloud[@"saved_at"]);
    if (![l isKindOfClass:NSDate.class] || !c) return NO;
    return fabs([l timeIntervalSinceDate:c]) < 2.0;
}

- (BOOL)localNewerThanCloud:(HZContainerItem *)it {
    if (!it.local) return NO;
    if (!it.cloud) return YES;
    NSDate *l = it.local[@"date"], *c = HZParseISO(it.cloud[@"saved_at"]);
    if (![l isKindOfClass:NSDate.class]) return NO;
    if (!c) return YES;
    return [l timeIntervalSinceDate:c] >= 2.0;
}

- (BOOL)isBusyWith:(NSString *)name {
    return [self.pendingSave isEqualToString:name] || [self.pendingLoad isEqualToString:name]
        || [self.uploading isEqualToString:name] || [self.downloading isEqualToString:name];
}

/// Signed in: the account is the home of every saved login. Anything captured on this iPhone goes
/// up as soon as it's complete and is then removed from the phone; a copy downloaded for a restore
/// is removed once the restore has run. Runs one transfer at a time and re-enters itself when done.
- (void)syncWithCloud {
    if (![self cloudOn] || !self.cloudRows || self.uploading || self.downloading) return;
    for (HZContainerItem *it in self.items) {
        if (!it.local || [self isBusyWith:it.name]) continue;
        if ([self localNewerThanCloud:it]) { [self upload:it]; return; }
        if ([self localMatchesCloud:it] || it.cloud) {
            // Account copy is current (or newer, saved elsewhere) — free the space on the phone.
            [HZConfig deleteSnapshotNamed:it.name forApp:self.bundleId];
            self.localSnapshots = [HZConfig snapshotsForApp:self.bundleId];
            [self rebuildItems];
        }
    }
}

- (void)upload:(HZContainerItem *)it {
    self.uploading = it.name;
    self.transferFraction = 0;
    [self rebuildItems];
    [[HZCloud shared] uploadSnapshotAtPath:it.local[@"path"] meta:it.local forApp:self.bundleId appName:self.appName
        progress:^(double f) { self.transferFraction = f; [self refreshRowNamed:it.name]; }
        completion:^(NSDictionary *row, NSError *error) {
            self.uploading = nil;
            if (error) {
                self.cloudError = [NSString stringWithFormat:@"Upload of \"%@\" failed: %@", it.name, error.localizedDescription];
                [self rebuildItems];
                return;
            }
            self.cloudError = nil;
            NSMutableArray *rows = [NSMutableArray array];
            for (NSDictionary *r in self.cloudRows) if (![r[@"name"] isEqualToString:it.name]) [rows addObject:r];
            if (row) [rows insertObject:row atIndex:0];
            self.cloudRows = rows;
            // Now safely in the account → drop the local copy unless the tweak still needs it.
            if (![self.pendingLoad isEqualToString:it.name] && ![self.pendingSave isEqualToString:it.name])
                [HZConfig deleteSnapshotNamed:it.name forApp:self.bundleId];
            self.localSnapshots = [HZConfig snapshotsForApp:self.bundleId];
            [self rebuildItems];
            [self syncWithCloud];
        }];
}

/// Make sure a login exists on the phone (download it if it's only in the account), then `then(dir)`.
- (void)ensureLocal:(HZContainerItem *)it then:(void (^)(BOOL ok))then {
    if (it.local && ([self localMatchesCloud:it] || !it.cloud || [self localNewerThanCloud:it])) { then(YES); return; }
    if (!it.cloud) { then(NO); return; }
    self.downloading = it.name;
    self.transferFraction = 0;
    [self rebuildItems];
    [[HZCloud shared] downloadContainer:it.cloud toSnapshotsDir:[HZConfig snapshotsDirForApp:self.bundleId]
        progress:^(double f) { self.transferFraction = f; [self refreshRowNamed:it.name]; }
        completion:^(NSString *localDir, NSError *error) {
            self.downloading = nil;
            self.localSnapshots = [HZConfig snapshotsForApp:self.bundleId];
            if (error) self.cloudError = [NSString stringWithFormat:@"Download of \"%@\" failed: %@", it.name, error.localizedDescription];
            [self rebuildItems];
            then(error == nil);
        }];
}

- (void)refreshRowNamed:(NSString *)name {
    NSUInteger i = [self.items indexOfObjectPassingTest:^BOOL(HZContainerItem *it, NSUInteger idx, BOOL *stop) { return [it.name isEqualToString:name]; }];
    if (i == NSNotFound) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:HZContainersList];
    if ([self.tableView numberOfRowsInSection:HZContainersList] > (NSInteger)i)
        [self.tableView reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)cancelPending {
    [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
    [HZContainerSync queueSnapshotSave:nil load:nil forApp:self.bundleId];
    [self reload];
}

- (BOOL)hasPending { return self.pendingSave.length || self.pendingLoad.length; }

#pragma mark - Formatting

- (NSString *)subtitleFor:(HZContainerItem *)it {
    NSMutableArray *bits = [NSMutableArray array];
    if (it.date) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateStyle = NSDateFormatterMediumStyle; f.timeStyle = NSDateFormatterShortStyle;
        [bits addObject:[f stringFromDate:it.date]];
    }
    if (it.bytes) [bits addObject:[NSByteCountFormatter stringFromByteCount:(long long)it.bytes countStyle:NSByteCountFormatterCountStyleFile]];
    if (it.version.length) [bits addObject:[NSString stringWithFormat:@"v%@", it.version]];
    NSString *line = [bits componentsJoinedByString:@"  ·  "];
    if (![self cloudOn]) return line;

    NSString *status = nil;
    if ([self.uploading isEqualToString:it.name])        status = [NSString stringWithFormat:@"Uploading %.0f%%", self.transferFraction * 100];
    else if ([self.downloading isEqualToString:it.name]) status = [NSString stringWithFormat:@"Downloading %.0f%%", self.transferFraction * 100];
    else if (!it.cloud && self.cloudRows && ![self isBusyWith:it.name]) status = @"Waiting to upload";
    if (!status) return line;   // the cloud icon already says it's in your account
    return line.length ? [NSString stringWithFormat:@"%@  ·  %@", line, status] : status;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZContainersCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case HZContainersPending: return [self hasPending] ? 1 : 0;
        case HZContainersError:   return ((self.lastError.length && ![self hasPending]) || self.cloudError.length) ? 1 : 0;
        case HZContainersSave:    return 1;
        case HZContainersList:    return self.items.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == HZContainersList && self.items.count) return @"SAVED LOGINS";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == HZContainersPending && [self hasPending]) return @"Tap to cancel.";
    if (s == HZContainersError && self.cloudError.length) return @"Tap to retry.";
    if (s == HZContainersList) {
        if (self.items.count == 0) return ([self cloudOn] && !self.cloudRows && !self.cloudError) ? @"Loading…" : @"No saved logins yet.";
        return @"Tap to restore. Swipe to rename or delete.";
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
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Open %@ to finish", self.appName];
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.imageView.tintColor = HZAccent();
        UIImageView *x = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]];
        x.tintColor = HZTextMuted();
        cell.accessoryView = x;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    if (ip.section == HZContainersError) {
        BOOL cloud = self.cloudError.length > 0;
        cell.textLabel.text = cloud ? @"Account sync problem" : @"Last request failed";
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = HZDanger();
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.text = cloud ? self.cloudError : self.lastError;
        cell.imageView.image = [UIImage systemImageNamed:cloud ? @"exclamationmark.icloud.fill" : @"exclamationmark.triangle.fill"];
        cell.imageView.tintColor = HZDanger();
        cell.selectionStyle = cloud ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (ip.section == HZContainersSave) {
        cell.textLabel.text = @"Save current login";
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = HZAccent();
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:[self cloudOn] ? @"icloud.and.arrow.up.fill" : @"square.and.arrow.down.fill"];
        cell.imageView.tintColor = HZAccent();
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    HZContainerItem *it = self.items[ip.row];
    cell.textLabel.text = it.name;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = [self subtitleFor:it];
    BOOL transferring = [self.uploading isEqualToString:it.name] || [self.downloading isEqualToString:it.name];
    NSString *symbol = @"person.crop.circle.badge.checkmark";
    if ([self cloudOn]) {
        if ([self.uploading isEqualToString:it.name]) symbol = @"icloud.and.arrow.up";
        else if ([self.downloading isEqualToString:it.name]) symbol = @"icloud.and.arrow.down";
        else if (it.cloud) symbol = @"checkmark.icloud.fill";
        else symbol = @"iphone";
    }
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = transferring ? HZTextMuted() : HZAccent();
    if (transferring) {
        UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spin.color = HZAccent();
        [spin startAnimating];
        cell.accessoryView = spin;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == HZContainersPending) { [self confirmCancel]; return; }
    if (ip.section == HZContainersError) { if (self.cloudError.length) { self.cloudError = nil; [self reload]; } return; }
    if (ip.section == HZContainersSave) { [self promptSave]; return; }
    if (ip.section == HZContainersList) {
        HZContainerItem *it = self.items[ip.row];
        if ([self.uploading isEqualToString:it.name] || [self.downloading isEqualToString:it.name]) return;
        [self confirmLoad:it];
    }
}

#pragma mark - Swipe actions (rename / delete)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != HZContainersList) return nil;
    HZContainerItem *it = self.items[ip.row];
    if ([self.uploading isEqualToString:it.name] || [self.downloading isEqualToString:it.name]) return nil;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self confirmDelete:it]; done(YES); }];
    UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self promptRename:it]; done(YES); }];
    ren.backgroundColor = HZAccent();
    return [UISwipeActionsConfiguration configurationWithActions:@[ del, ren ]];
}

#pragma mark - Actions

- (void)confirmCancel {
    BOOL saving = self.pendingSave.length > 0;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:saving ? @"Cancel Save?" : @"Cancel Restore?"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Keep" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel Request" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) { [self cancelPending]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptSave {
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"MMM d, h:mm a";
    NSString *suggested = [f stringFromDate:[NSDate date]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Save Current Login" message:@"Name it."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Name"; tf.text = suggested; tf.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *name = [HZConfig sanitizeSnapshotName:a.textFields.firstObject.text];
        if (!name) { [self toast:@"Enter a name"]; return; }
        [self queueSave:name];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)queueSave:(NSString *)name {
    // Overwrite warning if a login of this name already exists (on the phone or in the account).
    BOOL exists = [self itemNamed:name] != nil;
    void (^go)(void) = ^{
        [HZConfig setSnapshotSavePending:name forApp:self.bundleId];
        if (![HZContainerSync queueSnapshotSave:name load:nil forApp:self.bundleId]) {
            [HZConfig setSnapshotSavePending:nil forApp:self.bundleId];
            [self openAppAlert:[NSString stringWithFormat:@"Open %@ once, then try again.", self.appName]];
            [self reload];
            return;
        }
        [self reload];
        [self openAppAlert:[NSString stringWithFormat:@"Open %@ to finish.", self.appName]];
    };
    if (!exists) { go(); return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Overwrite?"
        message:[NSString stringWithFormat:@"\"%@\" already exists.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Overwrite" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) { go(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmLoad:(HZContainerItem *)it {
    NSString *name = it.name;
    BOOL needsDownload = [self cloudOn] && it.cloud && !(it.local && ([self localMatchesCloud:it] || [self localNewerThanCloud:it]));
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Restore \"%@\"?", name]
        message:[NSString stringWithFormat:@"Replaces what's in %@ now.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:needsDownload ? @"Download & Restore" : @"Restore" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [self ensureLocal:it then:^(BOOL ok) {
            if (!ok) { if (!self.cloudError) [self toast:@"Couldn't download"]; return; }
            [HZConfig setSnapshotLoadPending:name forApp:self.bundleId];
            if (![HZContainerSync queueSnapshotSave:nil load:name forApp:self.bundleId]) {
                [HZConfig setSnapshotLoadPending:nil forApp:self.bundleId];
                [self openAppAlert:[NSString stringWithFormat:@"Open %@ once, then try again.", self.appName]];
                [self reload];
                return;
            }
            [self reload];
            [self openAppAlert:[NSString stringWithFormat:@"Open %@ to finish.", self.appName]];
        }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptRename:(HZContainerItem *)it {
    NSString *name = it.name;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = name; tf.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *newName = [HZConfig sanitizeSnapshotName:a.textFields.firstObject.text];
        if (!newName || [newName isEqualToString:name]) return;
        if ([self itemNamed:newName]) { [self toast:@"That name is already in use"]; return; }
        if (it.local && ![HZConfig renameSnapshotNamed:name to:newName forApp:self.bundleId]) { [self toast:@"Couldn't rename"]; return; }
        if ([self isBusyWith:name]) {
            // Keep the queued request pointing at the new folder name.
            if ([self.pendingSave isEqualToString:name]) { [HZConfig setSnapshotSavePending:newName forApp:self.bundleId]; [HZContainerSync queueSnapshotSave:newName load:nil forApp:self.bundleId]; }
            if ([self.pendingLoad isEqualToString:name]) { [HZConfig setSnapshotLoadPending:newName forApp:self.bundleId]; [HZContainerSync queueSnapshotSave:nil load:newName forApp:self.bundleId]; }
        }
        if ([self cloudOn] && it.cloud) {
            [[HZCloud shared] renameContainer:it.cloud to:newName completion:^(NSError *error) {
                if (error) self.cloudError = [NSString stringWithFormat:@"Rename in your account failed: %@", error.localizedDescription];
                self.cloudRows = nil;
                [self reload];
            }];
        }
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(HZContainerItem *)it {
    NSString *name = it.name;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete \"%@\"?", name]
        message:@"Can't be undone." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        if ([self.pendingLoad isEqualToString:name] || [self.pendingSave isEqualToString:name]) [self cancelPending];
        if (it.local) [HZConfig deleteSnapshotNamed:name forApp:self.bundleId];
        if ([self cloudOn] && it.cloud) {
            [[HZCloud shared] deleteContainer:it.cloud completion:^(NSError *error) {
                if (error) self.cloudError = [NSString stringWithFormat:@"Delete in your account failed: %@", error.localizedDescription];
                self.cloudRows = nil;
                [self reload];
            }];
        }
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Small helpers

- (void)openAppAlert:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
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

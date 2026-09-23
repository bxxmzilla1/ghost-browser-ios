#import "HZAppToolsViewController.h"
#import "HZAppData.h"
#import "HZTheme.h"
#import "HZConfig.h"

typedef NS_ENUM(NSInteger, HZToolsSection) {
    HZToolsInfo,        // version / build / min iOS / sizes
    HZToolsIdentifier,  // bundle id (tap to copy)
    HZToolsHome,        // custom icon name + badge count
    HZToolsContainers,  // open bundle / data / groups in Filza
    HZToolsActions,     // clear cache / reset data / reset perms / offload / app store
    HZToolsCount
};

@interface HZAppToolsViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, strong) HZAppData *data;

@property (nonatomic, copy) NSString *cacheSizeText;
@property (nonatomic, copy) NSString *dataSizeText;

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *badgeField;

@property (nonatomic, copy) NSArray<NSDictionary *> *infoRows;      // {title, value}
@property (nonatomic, copy) NSArray<NSDictionary *> *containerRows; // {title, symbol, url}
@property (nonatomic, copy) NSArray<NSDictionary *> *actionRows;    // {title, symbol, key, color}
@end

@implementation HZAppToolsViewController

- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _bundleId = [bundleId copy];
        _appName = [name copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"App Data";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.data = [HZAppData dataForBundleId:self.bundleId];
    self.cacheSizeText = @"Calculating…";
    self.dataSizeText = @"Calculating…";

    self.nameField = [self field:self.appName placeholder:@"Custom name (blank = real name)" keyboard:UIKeyboardTypeDefault];
    self.nameField.text = [HZConfig customNameForApp:self.bundleId] ?: @"";
    NSNumber *badge = [HZConfig badgeForApp:self.bundleId];
    self.badgeField = [self field:nil placeholder:@"Badge count (blank = leave alone)" keyboard:UIKeyboardTypeNumberPad];
    self.badgeField.text = badge ? badge.stringValue : @"";

    [self rebuildRows];
    [self loadSizes];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIView *pill = HZPill(self.data.diskUsageString ?: @"—", HZTextMuted());
        self.tableView.tableHeaderView = HZHeroHeader(self.tableView.bounds.size.width, HZAppIcon(self.bundleId), NO,
                                                      self.appName, self.bundleId, pill);
    }
}

- (UITextField *)field:(NSString *)text placeholder:(NSString *)ph keyboard:(UIKeyboardType)kb {
    UITextField *tf = [UITextField new];
    tf.text = text ?: @"";
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph
        attributes:@{ NSForegroundColorAttributeName: HZTextMuted() }];
    tf.textColor = UIColor.whiteColor;
    tf.tintColor = HZAccent();
    tf.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    tf.keyboardType = kb;
    tf.textAlignment = NSTextAlignmentRight;
    tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    return tf;
}

- (void)rebuildRows {
    NSMutableArray *info = [NSMutableArray array];
    [info addObject:@{ @"title": @"Version",   @"value": self.data.shortVersion ?: @"N/A" }];
    [info addObject:@{ @"title": @"Build",      @"value": self.data.buildVersion ?: @"N/A" }];
    if (self.data.minimumOSVersion.length) [info addObject:@{ @"title": @"Minimum iOS", @"value": self.data.minimumOSVersion }];
    [info addObject:@{ @"title": @"App size",   @"value": self.data.diskUsageString ?: @"—" }];
    [info addObject:@{ @"title": @"Data size",  @"value": self.dataSizeText ?: @"—" }];
    [info addObject:@{ @"title": @"Cache size", @"value": self.cacheSizeText ?: @"—" }];
    self.infoRows = info;

    NSMutableArray *containers = [NSMutableArray array];
    if (self.data.bundleURL)
        [containers addObject:@{ @"title": @"Open Bundle", @"symbol": @"shippingbox", @"url": self.data.bundleURL }];
    if (self.data.dataContainerURL)
        [containers addObject:@{ @"title": @"Open Data", @"symbol": @"folder", @"url": self.data.dataContainerURL }];
    for (NSString *gid in [self.data.groupContainerURLs.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSURL *u = self.data.groupContainerURLs[gid];
        if (u) [containers addObject:@{ @"title": [NSString stringWithFormat:@"Group · %@", gid], @"symbol": @"person.2.square.stack", @"url": u }];
    }
    self.containerRows = containers;

    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:@{ @"title": @"Clear Cache",       @"symbol": @"wind",              @"key": @"cache" }];
    [actions addObject:@{ @"title": @"Reset Data",        @"symbol": @"arrow.counterclockwise", @"key": @"data",  @"danger": @YES }];
    [actions addObject:@{ @"title": @"Reset Permissions", @"symbol": @"hand.raised",       @"key": @"perms" }];
    [actions addObject:@{ @"title": @"Offload App",       @"symbol": @"arrow.down.app",    @"key": @"offload" }];
    if (self.data.appStoreItemID)
        [actions addObject:@{ @"title": @"Open in App Store", @"symbol": @"bag", @"key": @"store" }];
    self.actionRows = actions;
}

- (void)loadSizes {
    __weak typeof(self) ws = self;
    [self.data cacheSize:^(NSString *f) {
        ws.cacheSizeText = f; [ws rebuildRows];
        [ws.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZToolsInfo] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [self.data dataSize:^(NSString *f) {
        ws.dataSizeText = f; [ws rebuildRows];
        [ws.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZToolsInfo] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZToolsCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case HZToolsInfo:       return self.infoRows.count;
        case HZToolsIdentifier: return 1;
        case HZToolsHome:       return 2;   // name + badge
        case HZToolsContainers: return self.containerRows.count;
        case HZToolsActions:    return self.actionRows.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case HZToolsInfo:       return @"INFO";
        case HZToolsIdentifier: return @"BUNDLE IDENTIFIER  ·  TAP TO COPY";
        case HZToolsHome:       return @"HOME SCREEN";
        case HZToolsContainers: return self.containerRows.count ? @"CONTAINERS  ·  OPENS IN FILZA" : nil;
        case HZToolsActions:    return @"TOOLS";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case HZToolsHome:
            return @"Rename the icon or set a badge, then tap Apply. Badges apply right away; a rename may "
                   @"need a respring to show. Clear the field and Apply to restore the real value.";
        case HZToolsActions:
            return @"Clear Cache frees space safely. Reset Data wipes the app's Library, Documents and tmp "
                   @"(like a fresh install). Reset Permissions and Offload are best-effort and may need the "
                   @"app closed first.";
    }
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = HZTextMuted();
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;
    cell.tintColor = HZAccent();

    switch (ip.section) {
        case HZToolsInfo: {
            NSDictionary *r = self.infoRows[ip.row];
            cell.textLabel.text = r[@"title"];
            cell.detailTextLabel.text = r[@"value"];
            break;
        }
        case HZToolsIdentifier: {
            cell.textLabel.text = self.bundleId;
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
            cell.textLabel.numberOfLines = 0;
            cell.imageView.image = [UIImage systemImageNamed:@"doc.on.doc"];
            cell.imageView.tintColor = HZAccent();
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case HZToolsHome: {
            UITextField *tf = ip.row == 0 ? self.nameField : self.badgeField;
            cell.textLabel.text = ip.row == 0 ? @"Name" : @"Badge";
            cell.imageView.image = [UIImage systemImageNamed:ip.row == 0 ? @"character.cursor.ibeam" : @"app.badge"];
            cell.imageView.tintColor = HZAccent();
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [tf removeFromSuperview];
            [cell.contentView addSubview:tf];
            // Fixed leading (clears the icon + short label) rather than anchoring to the system
            // textLabel, whose frame-based layout doesn't play well with Auto Layout.
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:96],
                [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [tf.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                [tf.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            ]];
            break;
        }
        case HZToolsContainers: {
            NSDictionary *r = self.containerRows[ip.row];
            cell.textLabel.text = r[@"title"];
            cell.imageView.image = [UIImage systemImageNamed:r[@"symbol"]];
            cell.imageView.tintColor = HZAccent();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case HZToolsActions: {
            NSDictionary *r = self.actionRows[ip.row];
            BOOL danger = [r[@"danger"] boolValue];
            cell.textLabel.text = r[@"title"];
            cell.textLabel.textColor = danger ? HZDanger() : UIColor.whiteColor;
            cell.imageView.image = [UIImage systemImageNamed:r[@"symbol"]];
            cell.imageView.tintColor = danger ? HZDanger() : HZAccent();
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
    }
    return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == HZToolsIdentifier) {
        UIPasteboard.generalPasteboard.string = self.bundleId;
        [self flash:@"Bundle identifier copied"];
    } else if (ip.section == HZToolsContainers) {
        NSURL *url = self.containerRows[ip.row][@"url"];
        if (![self.data openContainerInFilza:url])
            [self alert:@"Filza not found" message:@"Install Filza to browse this container, or copy the path below."
             copyPath:url.path];
    } else if (ip.section == HZToolsActions) {
        [self runAction:self.actionRows[ip.row][@"key"] title:self.actionRows[ip.row][@"title"]];
    }
}

#pragma mark - Home-screen overrides (Apply)

// A rename / badge change only takes effect when the user taps Apply — add a footer Apply button via
// the nav bar so it's always reachable.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyHome)];
}

- (void)applyHome {
    [self.view endEditing:YES];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [HZConfig setCustomName:name.length ? name : nil forApp:self.bundleId];

    NSString *badgeText = [self.badgeField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSNumber *badge = badgeText.length ? @(badgeText.integerValue) : nil;
    [HZConfig setBadge:badge forApp:self.bundleId];

    [HZConfig notifySpringBoard];
    [self flash:@"Applied  ·  respring if the name didn't change"];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

#pragma mark - Tools

- (void)runAction:(NSString *)key title:(NSString *)title {
    if ([key isEqualToString:@"store"]) {
        if (![self.data openInAppStore]) [self flash:@"No App Store page for this app"];
        return;
    }
    NSString *msg;
    if ([key isEqualToString:@"cache"])        msg = @"Delete this app's caches and temporary files?";
    else if ([key isEqualToString:@"data"])    msg = @"Wipe this app's Library, Documents and tmp? This is like a fresh install and can't be undone.";
    else if ([key isEqualToString:@"perms"])   msg = @"Reset this app's privacy permissions (photos, camera, location, etc.)?";
    else if ([key isEqualToString:@"offload"]) msg = @"Offload this app? The app is removed but its data is kept; tap its icon to reinstall.";
    else return;

    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:title
        style:[key isEqualToString:@"cache"] ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) { [self performAction:key]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)performAction:(NSString *)key {
    __weak typeof(self) ws = self;
    void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *okMsg) {
        [ws loadSizes];
        [ws flash:ok ? okMsg : @"Couldn't complete — try closing the app first"];
    };
    if ([key isEqualToString:@"cache"])
        [self.data clearCache:^(BOOL ok) { done(ok, @"Cache cleared"); }];
    else if ([key isEqualToString:@"data"])
        [self.data resetData:^(BOOL ok) { done(ok, @"Data reset"); }];
    else if ([key isEqualToString:@"perms"])
        [self.data resetPermissions:^(BOOL ok) { done(ok, @"Permissions reset"); }];
    else if ([key isEqualToString:@"offload"])
        [self.data offload:^(BOOL ok) { done(ok, @"App offloaded"); }];
}

#pragma mark - Feedback

- (void)flash:(NSString *)text {
    UILabel *toast = [UILabel new];
    toast.text = text;
    toast.textColor = UIColor.whiteColor;
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = HZCardElevated();
    toast.layer.cornerRadius = 12; toast.clipsToBounds = YES;
    toast.numberOfLines = 0;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [toast.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
        [toast.heightAnchor constraintGreaterThanOrEqualToConstant:40],
    ]];
    toast.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; } completion:^(BOOL d) { [toast removeFromSuperview]; }];
        });
    }];
}

- (void)alert:(NSString *)title message:(NSString *)message copyPath:(NSString *)path {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    if (path.length)
        [a addAction:[UIAlertAction actionWithTitle:@"Copy path" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *x) { UIPasteboard.generalPasteboard.string = path; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

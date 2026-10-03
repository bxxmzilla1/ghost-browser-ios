#import "HZAppDetailViewController.h"
#import "HZAppToolsViewController.h"
#import "HZAppData.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"

// Section indices.
enum { SEC_ENABLE, SEC_DETAILS, SEC_TOOLS, SEC_ACTIONS, SEC_COUNT };

@interface HZAppDetailViewController ()
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, strong) NSDictionary *identity;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *details;  // [label, value, sf-symbol]
@property (nonatomic, assign) BOOL identityExpanded;   // collapsible identity dropdown (collapsed = compact)
@property (nonatomic, assign) BOOL chainRunning;       // Spoof Chain in progress
@end

@implementation HZAppDetailViewController

- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _bundleId = [bundleId copy];
        _appName = [name copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.appName;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);

    self.enabled = [HZConfig isEnabledForApp:self.bundleId];
    self.identity = [HZConfig identityForApp:self.bundleId];
    if (!self.identity) {
        // Pick an identity so the rows populate; spoofing stays off until the switch is on.
        self.identity = HZGenerateIdentity();
        [HZConfig setIdentity:self.identity forApp:self.bundleId];
    }
    [self rebuildDetails];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) [self refreshHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Returning here after relaunching the target app: the tweak may have performed the queued wipe
    // and cleared the flag in the app's container, so re-read the real state and refresh the pill.
    self.enabled = [HZConfig isEnabledForApp:self.bundleId];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)refreshHeader {
    BOOL wipe = [HZContainerSync wipePendingForApp:self.bundleId];
    UIView *pill = wipe ? HZPill(@"erase queued", HZDanger())
                 : self.enabled ? HZPill(@"spoofing on", HZSuccess()) : HZPill(@"spoofing off", HZTextMuted());
    self.tableView.tableHeaderView = HZHeroHeader(self.tableView.bounds.size.width, HZAppIcon(self.bundleId), NO,
                                                  self.appName, self.bundleId, pill);
}

- (void)rebuildDetails {
    NSDictionary *i = self.identity ?: @{};
    // Only the reset identifiers — the real iPhone (model, screen, CPU, RAM, iOS, carrier) is kept.
    self.details = @[
        @[@"Serial Number", i[@"serial"]    ?: @"—", @"number"],
        @[@"UDID",          i[@"udid"]      ?: @"—", @"cpu"],
        @[@"IDFV",          i[@"idfv"]      ?: @"—", @"app.badge"],
        @[@"IDFA",          i[@"idfa"]      ?: @"—", @"megaphone"],
        @[@"Wi-Fi MAC",     i[@"wifi"]      ?: @"—", @"wifi"],
        @[@"Bluetooth MAC", i[@"bluetooth"] ?: @"—", @"dot.radiowaves.left.and.right"],
        @[@"IMEI",          i[@"imei"]      ?: @"—", @"simcard"],
    ];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SEC_COUNT; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SEC_ENABLE:  return 1;
        case SEC_DETAILS: return self.identityExpanded ? (1 + self.details.count) : 1;  // row 0 = dropdown toggle
        case SEC_TOOLS:   return 1;   // App Data & Tools →
        case SEC_ACTIONS: return 1;   // Spoof Chain
        default:          return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == SEC_DETAILS) return @"IDENTITY";
    if (s == SEC_TOOLS)   return @"APP DATA";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SEC_ACTIONS) return @"Clear cache → reset data → new identity → erase. Finishes on next launch.";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;

    switch (ip.section) {
        case SEC_ENABLE: {
            cell.textLabel.text = @"Spoof this app";
            cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
            cell.detailTextLabel.text = self.enabled ? @"Active on next launch" : @"Off";
            cell.detailTextLabel.textColor = HZTextMuted();
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.imageView.image = [UIImage systemImageNamed:@"shield.lefthalf.filled"];
            cell.imageView.tintColor = HZAccent();
            UISwitch *sw = [UISwitch new];
            sw.onTintColor = HZAccent();
            sw.on = self.enabled;
            [sw addTarget:self action:@selector(toggleEnable:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case SEC_DETAILS: {
            if (ip.row == 0) {   // dropdown toggle
                cell.textLabel.text = @"Device Identity";
                cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
                cell.detailTextLabel.text = self.identityExpanded ? @"iPhone X format" : @"iPhone X · Serial · UDID · IDFV · IDFA · MACs · IMEI";
                cell.detailTextLabel.textColor = HZTextMuted();
                cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
                cell.imageView.image = [UIImage systemImageNamed:@"list.bullet.rectangle"];
                cell.imageView.tintColor = HZAccent();
                UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.identityExpanded ? @"chevron.up" : @"chevron.down"]];
                chev.tintColor = HZTextMuted();
                cell.accessoryView = chev;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
            }
            NSArray<NSString *> *row = self.details[ip.row - 1];
            cell.textLabel.text = row[0];
            cell.textLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            cell.textLabel.textColor = HZTextMuted();
            cell.detailTextLabel.text = row[1];
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
            cell.detailTextLabel.textColor = UIColor.whiteColor;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            cell.imageView.image = [UIImage systemImageNamed:row[2]];
            cell.imageView.tintColor = HZAccent();
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case SEC_TOOLS: {
            cell.textLabel.text = @"App Data & Tools";
            cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
            cell.detailTextLabel.text = nil;
            cell.detailTextLabel.textColor = HZTextMuted();
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
            cell.imageView.tintColor = HZAccent();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case SEC_ACTIONS: {
            cell.backgroundColor = UIColor.clearColor;
            HZGradientButton *b = [HZGradientButton buttonWithTitle:self.chainRunning ? @"Running Spoof Chain…" : @"Spoof Chain"
                                                             symbol:self.chainRunning ? @"hourglass" : @"bolt.horizontal.fill"];
            b.enabled = !self.chainRunning;
            b.alpha = self.chainRunning ? 0.6 : 1.0;
            [b addTarget:self action:@selector(confirmSpoofChain) forControlEvents:UIControlEventTouchUpInside];
            b.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:b];
            [NSLayoutConstraint activateConstraints:@[
                [b.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [b.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [b.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
                [b.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
            ]];
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SEC_TOOLS) {
        HZAppToolsViewController *t = [[HZAppToolsViewController alloc] initWithBundleId:self.bundleId name:self.appName];
        [self.navigationController pushViewController:t animated:YES];
        return;
    }
    if (ip.section != SEC_DETAILS) return;
    if (ip.row == 0) {   // toggle the identity dropdown
        self.identityExpanded = !self.identityExpanded;
        [tv reloadSections:[NSIndexSet indexSetWithIndex:SEC_DETAILS] withRowAnimation:UITableViewRowAnimationAutomatic];
        return;
    }
    NSArray<NSString *> *row = self.details[ip.row - 1];
    UIPasteboard.generalPasteboard.string = row[1];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    NSString *prev = cell.textLabel.text;
    cell.textLabel.text = [NSString stringWithFormat:@"%@  ·  Copied", row[0]];
    cell.textLabel.textColor = HZSuccess();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        cell.textLabel.text = prev; cell.textLabel.textColor = HZTextMuted();
    });
}

// The action rows draw their own background, so hide the grouped card behind them.
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SEC_ACTIONS) {
        cell.backgroundColor = UIColor.clearColor; cell.backgroundView = nil;
        cell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);   // no hairline between the buttons
    }
}

#pragma mark - Actions

// Mirror the current state into the target app's own container so the tweak reads it without libSandy.
- (void)sync {
    // Preserve the app's real queued-erase state (from its container) so toggling spoof or rolling a
    // new identity never re-arms a wipe the tweak already performed.
    [HZContainerSync writeForApp:self.bundleId identity:self.identity
                         enabled:self.enabled wipePending:[HZContainerSync wipePendingForApp:self.bundleId]];
}

- (void)toggleEnable:(UISwitch *)sw {
    self.enabled = sw.on;
    [HZConfig setEnabled:sw.on forApp:self.bundleId];
    [self sync];
    [self refreshHeader];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SEC_ENABLE] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)generate {
    self.identity = HZGenerateIdentity();
    [HZConfig setIdentity:self.identity forApp:self.bundleId];
    [self sync];
    [self rebuildDetails];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SEC_DETAILS] withRowAnimation:UITableViewRowAnimationFade];
}

// Queue the wipe-on-next-launch (the "Erase App Data" step), without its own confirmation — the
// Spoof Chain confirms once up front.
- (void)queueErase {
    [HZConfig setWipePending:YES forApp:self.bundleId];
    if (!self.enabled) { self.enabled = YES; [HZConfig setEnabled:YES forApp:self.bundleId]; }
    [HZContainerSync writeForApp:self.bundleId identity:self.identity enabled:YES wipePending:YES];
}

#pragma mark - Spoof Chain

- (void)confirmSpoofChain {
    if (self.chainRunning) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Run Spoof Chain?"
        message:[NSString stringWithFormat:@"Wipes %@ and gives it a new identity. Can't be undone.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Run Spoof Chain" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) { [self runSpoofChain]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)setChainButtonRunning:(BOOL)running {
    self.chainRunning = running;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SEC_ACTIONS] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)runSpoofChain {
    [self setChainButtonRunning:YES];
    HZAppData *data = [HZAppData dataForBundleId:self.bundleId];

    // 1) Clear cache → 2) Reset data → 3) New identity → 4) Queue erase.
    [data clearCache:^(__unused BOOL cacheOk) {
        [data resetData:^(__unused BOOL dataOk) {
            [self generate];              // 3) fresh identity (also syncs + refreshes the identity section)
            [self queueErase];            // 4) wipe-on-next-launch
            [self setChainButtonRunning:NO];
            [self refreshHeader];
            [self.tableView reloadData];
            [self chainDoneAlert];
        }];
    }];
}

- (void)chainDoneAlert {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Spoof Chain Complete"
        message:[NSString stringWithFormat:@"Open %@ to finish.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

#import "HZAppDetailViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"

// Section indices.
enum { SEC_ENABLE, SEC_DETAILS, SEC_ACTIONS, SEC_COUNT };

@interface HZAppDetailViewController ()
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, strong) NSDictionary *identity;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *details;  // [label, value, sf-symbol]
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

- (void)refreshHeader {
    BOOL wipe = [HZConfig wipePendingForApp:self.bundleId];
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
        case SEC_DETAILS: return self.details.count;
        case SEC_ACTIONS: return 2;   // Generate, Erase
        default:          return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == SEC_DETAILS ? @"NEW IDENTITY  ·  TAP A VALUE TO COPY" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SEC_ENABLE)
        return @"Keeps your real iPhone model, but this app sees the identity below — like a fresh phone "
               @"with a first-time install.";
    if (s == SEC_ACTIONS)
        return @"Erase wipes this app's data, cookies, web data and keychain (incl. iCloud items) the next "
               @"time you open it, then it starts as a fresh install with the identity above.";
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
            NSArray<NSString *> *row = self.details[ip.row];
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
        case SEC_ACTIONS: {
            cell.backgroundColor = UIColor.clearColor;
            UIButton *b = ip.row == 0
                ? [HZGradientButton buttonWithTitle:@"Generate New Identity" symbol:@"sparkles"]
                : [HZOutlineButton buttonWithTitle:@"Erase App Data" symbol:@"trash" color:HZDanger()];
            [b addTarget:self action:(ip.row == 0 ? @selector(generate) : @selector(confirmErase))
                forControlEvents:UIControlEventTouchUpInside];
            b.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:b];
            [NSLayoutConstraint activateConstraints:@[
                [b.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [b.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [b.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:ip.row == 0 ? 4 : 6],
                [b.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
            ]];
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != SEC_DETAILS) return;
    NSArray<NSString *> *row = self.details[ip.row];
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
    [HZContainerSync writeForApp:self.bundleId identity:self.identity
                         enabled:self.enabled wipePending:[HZConfig wipePendingForApp:self.bundleId]];
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

- (void)confirmErase {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Erase App Data?"
        message:[NSString stringWithFormat:@"Next time you open %@ it will be wiped (data, cookies, web data "
                 @"and keychain, including iCloud-synced items) and start as a fresh install with the "
                 @"identity shown above.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Erase on next launch" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) {
            [HZConfig setWipePending:YES forApp:self.bundleId];
            if (!self.enabled) { self.enabled = YES; [HZConfig setEnabled:YES forApp:self.bundleId]; }
            [HZContainerSync writeForApp:self.bundleId identity:self.identity enabled:YES wipePending:YES];
            [self refreshHeader];
            [self.tableView reloadData];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

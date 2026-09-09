#import "HZAppDetailViewController.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"

static UIColor *HZAccent(void)  { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; }
static UIColor *HZCardBG(void)  { return [UIColor colorWithRed:0.11 green:0.11 blue:0.14 alpha:1.0]; }
static UIColor *HZDanger(void)  { return [UIColor colorWithRed:0.95 green:0.35 blue:0.35 alpha:1.0]; }

// Section indices.
enum { SEC_ENABLE, SEC_DEVICE, SEC_DETAILS, SEC_ERASE, SEC_COUNT };

@interface HZAppDetailViewController ()
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, strong) NSDictionary *identity;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *details;  // [label, value]
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
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.navigationController.navigationBar.tintColor = HZAccent();

    self.enabled = [HZConfig isEnabledForApp:self.bundleId];
    self.identity = [HZConfig identityForApp:self.bundleId];
    if (!self.identity) {
        // Pick a device so the modules populate; spoofing stays off until the switch is on.
        self.identity = HZGenerateIdentity();
        [HZConfig setIdentity:self.identity forApp:self.bundleId];
    }
    [self rebuildDetails];
}

- (void)rebuildDetails {
    NSDictionary *i = self.identity ?: @{};
    // Only the reset identifiers — the real iPhone (model, screen, CPU, RAM, iOS, carrier) is kept.
    self.details = @[
        @[@"Serial",       i[@"serial"] ?: @"—"],
        @[@"UDID",         i[@"udid"] ?: @"—"],
        @[@"IDFV",         i[@"idfv"] ?: @"—"],
        @[@"IDFA",         i[@"idfa"] ?: @"—"],
        @[@"Wi-Fi MAC",    i[@"wifi"] ?: @"—"],
        @[@"Bluetooth MAC",i[@"bluetooth"] ?: @"—"],
        @[@"IMEI",         i[@"imei"] ?: @"—"],
    ];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SEC_COUNT; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SEC_ENABLE:  return 1;
        case SEC_DEVICE:  return 2;                    // summary + Generate
        case SEC_DETAILS: return self.details.count;
        case SEC_ERASE:   return 1;
        default:          return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SEC_DEVICE:  return @"DEVICE IDENTITY";
        case SEC_DETAILS: return @"RESET IDENTIFIERS";
        default:          return nil;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SEC_ENABLE)
        return @"When on, this app keeps your real iPhone model but sees a brand-new identity "
               @"(serial, UDID, IDFV, IDFA, Wi-Fi/Bluetooth MAC, IMEI), so it looks like a fresh phone "
               @"with a first-time install.";
    if (s == SEC_ERASE)
        return @"Wipes this app's data, cookies, web data and keychain (incl. iCloud items) the next time "
               @"you open it — a fresh install with the identity above. A respring is not required.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = HZCardBG();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch (ip.section) {
        case SEC_ENABLE: {
            cell.textLabel.text = @"Spoof this app";
            UISwitch *sw = [UISwitch new];
            sw.onTintColor = HZAccent();
            sw.on = self.enabled;
            [sw addTarget:self action:@selector(toggleEnable:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case SEC_DEVICE: {
            if (ip.row == 0) {
                cell.textLabel.text = HZIdentitySummary(self.identity);
            } else {
                cell.textLabel.text = @"Generate New Identity";
                cell.textLabel.textColor = HZAccent();
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            break;
        }
        case SEC_DETAILS: {
            NSArray<NSString *> *row = self.details[ip.row];
            cell.textLabel.text = row[0];
            cell.detailTextLabel.text = row[1];
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            break;
        }
        case SEC_ERASE: {
            cell.textLabel.text = @"Erase App Data";
            cell.textLabel.textColor = HZDanger();
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SEC_DEVICE && ip.row == 1) { [self generate]; }
    else if (ip.section == SEC_ERASE) { [self confirmErase]; }
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
}

- (void)generate {
    self.identity = HZGenerateIdentity();
    [HZConfig setIdentity:self.identity forApp:self.bundleId];
    [self sync];
    [self rebuildDetails];
    [self.tableView reloadData];
}

- (void)confirmErase {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Erase App Data?"
        message:[NSString stringWithFormat:@"Next time you open %@ it will be wiped (data, cookies, web data "
                 @"and keychain, including iCloud-synced items) and reopened as a fresh install with the "
                 @"device shown above.", self.appName]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Erase on next launch" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *x) {
            [HZConfig setWipePending:YES forApp:self.bundleId];
            if (!self.enabled) { self.enabled = YES; [HZConfig setEnabled:YES forApp:self.bundleId]; }
            [HZContainerSync writeForApp:self.bundleId identity:self.identity enabled:YES wipePending:YES];
            UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Queued"
                message:[NSString stringWithFormat:@"Open %@ to complete the reset.", self.appName]
                preferredStyle:UIAlertControllerStyleAlert];
            [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ok animated:YES completion:nil];
            [self.tableView reloadData];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

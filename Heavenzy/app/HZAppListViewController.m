#import "HZAppListViewController.h"
#import "HZAppDetailViewController.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"

static UIColor *HZAccent(void) { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; }

@interface HZAppListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;   // {@"id", @"name"}
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation HZAppListViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Heavenzy";
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.navigationController.navigationBar.tintColor = HZAccent();

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = @"Search apps";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self loadApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];   // reflect enable/identity changes made in the detail screen
}

- (void)loadApps {
    NSMutableArray *out = [NSMutableArray array];
    @try {
        // Resolve LSApplicationWorkspace at runtime (private class) so we don't have to link the
        // private framework — that avoids an "Undefined symbols" link error.
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id ws = [wsClass valueForKey:@"defaultWorkspace"];   // +defaultWorkspace
        NSArray *all = [ws valueForKey:@"allApplications"];  // -allApplications
        for (id p in all) {
            NSString *type = [p valueForKey:@"applicationType"];
            if (![type isEqualToString:@"User"]) continue;                      // third-party only
            NSString *bid = [p valueForKey:@"applicationIdentifier"];
            if (bid.length == 0 || [bid isEqualToString:@"com.heavenzy.app"]) continue;
            NSString *name = [p valueForKey:@"localizedName"];
            if (name.length == 0) name = bid;
            [out addObject:@{ @"id": bid, @"name": name }];
        }
    } @catch (__unused NSException *e) {}
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    self.apps = out;
    self.filtered = out;
    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)rows { return self.filtered ?: self.apps; }

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    NSString *q = sc.searchBar.text;
    if (q.length == 0) { self.filtered = self.apps; }
    else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, __unused id b) {
            return [d[@"name"] localizedCaseInsensitiveContainsString:q] ||
                   [d[@"id"] localizedCaseInsensitiveContainsString:q];
        }];
        self.filtered = [self.apps filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.rows.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"APPLICATIONS (%lu)", (unsigned long)self.apps.count];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Turn on an app to spoof it, then open (or relaunch) that app to apply. Tap a row to choose "
           @"the device and erase its data.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *app = self.rows[ip.row];
    NSString *bid = app[@"id"];

    cell.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.14 alpha:1.0];
    cell.textLabel.text = app[@"name"];
    cell.textLabel.textColor = UIColor.whiteColor;

    BOOL enabled = [HZConfig isEnabledForApp:bid];
    NSDictionary *identity = [HZConfig identityForApp:bid];
    cell.detailTextLabel.text = enabled ? (identity ? HZIdentitySummary(identity) : @"On") : bid;
    cell.detailTextLabel.textColor = enabled ? HZAccent() : [UIColor colorWithWhite:0.55 alpha:1.0];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = HZAccent();
    sw.on = enabled;
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggle:(UISwitch *)sw {
    NSInteger row = sw.tag;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSString *bid = self.rows[row][@"id"];
    if (sw.on && ![HZConfig identityForApp:bid]) {
        [HZConfig setIdentity:HZGenerateIdentity() forApp:bid];   // roll one on first enable
    }
    [HZConfig setEnabled:sw.on forApp:bid];
    // Push straight into the app's container so the tweak sees it without libSandy.
    [HZContainerSync writeForApp:bid identity:[HZConfig identityForApp:bid]
                         enabled:sw.on wipePending:[HZConfig wipePendingForApp:bid]];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *app = self.rows[ip.row];
    HZAppDetailViewController *d = [[HZAppDetailViewController alloc] initWithBundleId:app[@"id"] name:app[@"name"]];
    [self.navigationController pushViewController:d animated:YES];
}

@end

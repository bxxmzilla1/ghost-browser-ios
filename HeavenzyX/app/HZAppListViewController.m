#import "HZAppListViewController.h"
#import "HZAppDetailViewController.h"
#import "HZSettingsViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZDevice.h"
#import "HZContainerSync.h"

#pragma mark - Row cell

@interface HZAppCell : UITableViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *subtitle;
@end

@implementation HZAppCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = HZCard();
        UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); self.selectedBackgroundView = sel;

        _icon = [UIImageView new];
        _icon.layer.cornerRadius = 11; _icon.clipsToBounds = YES;
        _icon.layer.borderWidth = 0.5; _icon.layer.borderColor = HZHairline().CGColor;
        _name = [UILabel new];
        _name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _name.textColor = UIColor.whiteColor;
        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _subtitle.textColor = HZTextMuted();
        _subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[ _name, _subtitle ]];
        text.axis = UILayoutConstraintAxisVertical; text.spacing = 2;
        for (UIView *v in @[ _icon, text ]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:46], [_icon.heightAnchor constraintEqualToConstant:46],
            [_icon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_icon.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [text.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:14],
            [text.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [text.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        ]];
    }
    return self;
}
@end

#pragma mark - List

@interface HZAppListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;   // {@"id", @"name"}
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation HZAppListViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    // The title lives in the compact header (logo + "Heavenzy"), not in the navigation bar.
    self.navigationItem.title = @"";
    self.navigationItem.backButtonTitle = @"Heavenzy X";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    [self.tableView registerClass:HZAppCell.class forCellReuseIdentifier:@"app"];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = @"Search apps";
    self.search.searchBar.tintColor = HZAccent();
    self.search.searchBar.searchTextField.backgroundColor = HZCard();
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:c]
                style:UIBarButtonItemStylePlain target:self action:@selector(showSettings)];

    [self loadApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshHeader];
    [self.tableView reloadData];   // reflect enable/identity changes made in the detail screen
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) [self refreshHeader];
}

- (void)refreshHeader {
    NSUInteger on = 0;
    for (NSDictionary *a in self.apps) if ([HZConfig isEnabledForApp:a[@"id"]]) on++;
    UIView *pill = HZPill(on ? [NSString stringWithFormat:@"%lu spoofed", (unsigned long)on] : @"nothing spoofed yet",
                          on ? HZSuccess() : HZTextMuted());
    self.tableView.tableHeaderView = HZCompactHeader(self.tableView.bounds.size.width, HZLogo(), @"Heavenzy X", pill);
}

- (void)showSettings {
    [self.navigationController pushViewController:[HZSettingsViewController new] animated:YES];
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
    [self refreshHeader];
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
    return [NSString stringWithFormat:@"APPLICATIONS · %lu", (unsigned long)self.rows.count];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Tap an app to spoof it, view or copy its identity, run the Spoof Chain, or open App Data & "
           @"Tools. Inside any app, hold two fingers to open the SMS panel.";
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    HZAppCell *cell = [tv dequeueReusableCellWithIdentifier:@"app" forIndexPath:ip];
    NSDictionary *app = self.rows[ip.row];
    NSString *bid = app[@"id"];
    BOOL enabled = [HZConfig isEnabledForApp:bid];
    NSDictionary *identity = [HZConfig identityForApp:bid];

    cell.icon.image = HZAppIcon(bid);
    cell.name.text = app[@"name"];
    cell.subtitle.text = enabled ? (identity ? HZIdentitySummary(identity) : @"Spoofing on") : bid;
    cell.subtitle.textColor = enabled ? HZAccent() : HZTextMuted();
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *app = self.rows[ip.row];
    HZAppDetailViewController *d = [[HZAppDetailViewController alloc] initWithBundleId:app[@"id"] name:app[@"name"]];
    [self.navigationController pushViewController:d animated:YES];
}

@end

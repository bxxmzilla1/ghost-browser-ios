#import "HZSettingsViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZContainerSync.h"

typedef NS_ENUM(NSInteger, HZSection) { HZSectionAuto, HZSectionNames, HZSectionCount };

@interface HZSettingsViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *namesView;
@property (nonatomic, strong) UILabel *namesPlaceholder;
@end

@implementation HZSettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    self.namesView = [UITextView new];
    self.namesView.backgroundColor = UIColor.clearColor;
    self.namesView.textColor = UIColor.whiteColor;
    self.namesView.tintColor = HZAccent();
    self.namesView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.namesView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.namesView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.namesView.text = [HZConfig approvedNames] ?: @"";
    self.namesView.delegate = self;
    self.namesView.scrollEnabled = YES;   // fixed height; scroll inside to edit a long list

    self.namesPlaceholder = [UILabel new];
    self.namesPlaceholder.text = @"Sandy\nJanet\nErin";
    self.namesPlaceholder.numberOfLines = 0;
    self.namesPlaceholder.textColor = HZTextMuted();
    self.namesPlaceholder.font = self.namesView.font;
    self.namesPlaceholder.hidden = self.namesView.text.length > 0;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:c]
                        imageWithTintColor:HZAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIView *h = HZHeroHeader(self.tableView.bounds.size.width, img, YES, @"Settings", nil, nil);
        self.tableView.tableHeaderView = h;
    }
}

#pragma mark - Persistence

- (void)pushToApps {
    NSInteger n = [HZContainerSync writePanelSettingsToAllApps];
    NSLog(@"[Heavenzy] Panel settings pushed to %ld app container(s)", (long)n);
}

- (void)textViewDidChange:(UITextView *)tv {
    self.namesPlaceholder.hidden = tv.text.length > 0;
    [HZConfig setApprovedNames:tv.text];
}
- (void)textViewDidEndEditing:(UITextView *)tv { [HZConfig setApprovedNames:tv.text]; [self pushToApps]; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [self pushToApps];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case HZSectionAuto:    return @"SCRAPER";
        case HZSectionNames:   return @"APPROVED NAMES";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == HZSectionNames) return @"One first name per line.";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = HZTextMuted();
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;
    cell.tintColor = HZAccent();

    if (ip.section == HZSectionAuto) {
        BOOL on = [HZConfig autoScan];
        cell.textLabel.text = @"Auto scan";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"timer"];
        cell.imageView.tintColor = HZAccent();
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = HZAccent();
        sw.on = on;
        [sw addTarget:self action:@selector(autoSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    // HZSectionNames
    for (UIView *v in @[ self.namesView, self.namesPlaceholder ]) {
        [v removeFromSuperview];
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.namesView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [self.namesView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [self.namesView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
        [self.namesView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        [self.namesView.heightAnchor constraintEqualToConstant:200],
        [self.namesPlaceholder.topAnchor constraintEqualToAnchor:self.namesView.topAnchor constant:8],
        [self.namesPlaceholder.leadingAnchor constraintEqualToAnchor:self.namesView.leadingAnchor constant:5],
    ]];
    return cell;
}

- (void)autoSwitched:(UISwitch *)sw {
    [HZConfig setAutoScan:sw.on];
    [self pushToApps];   // mirrored into every app container right away so an open panel can pick it up
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZSectionAuto] withRowAnimation:UITableViewRowAnimationNone];
}

@end

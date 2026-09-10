#import "HZSettingsViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZContainerSync.h"

typedef NS_ENUM(NSInteger, HZSection) { HZSectionProvider, HZSectionDiddy, HZSectionGrizzly, HZSectionCount };

@interface HZSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *diddyKeyField;
@property (nonatomic, strong) UITextField *grizzlyKeyField;
@property (nonatomic, strong) UITextField *grizzlyPriceField;
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

    self.diddyKeyField     = [self field:@"Paste your DiddySMS API key" text:[HZConfig diddyKey] secure:YES];
    self.grizzlyKeyField   = [self field:@"Paste your GrizzlySMS API key" text:[HZConfig grizzlyKey] secure:YES];
    self.grizzlyPriceField = [self field:@"Max price per number (optional, e.g. 0.50)" text:[HZConfig grizzlyMaxPrice] secure:NO];
    self.grizzlyPriceField.keyboardType = UIKeyboardTypeDecimalPad;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:@"message.fill" withConfiguration:c]
                        imageWithTintColor:HZAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIView *h = HZHeroHeader(self.tableView.bounds.size.width, img, YES, @"SMS Verification",
            @"Order a USA number and read the code from inside any app — hold two fingers on the screen to open the panel.", nil);
        self.tableView.tableHeaderView = h;
    }
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure {
    UITextField *tf = [UITextField new];
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{ NSForegroundColorAttributeName: HZTextMuted() }];
    tf.text = text ?: @"";
    tf.textColor = UIColor.whiteColor;
    tf.tintColor = HZAccent();
    tf.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    tf.secureTextEntry = secure;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    [tf addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    return tf;
}

#pragma mark - Persistence

- (void)fieldChanged:(UITextField *)tf {
    NSString *v = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tf == self.diddyKeyField)          [HZConfig setDiddyKey:v];
    else if (tf == self.grizzlyKeyField)   [HZConfig setGrizzlyKey:v];
    else if (tf == self.grizzlyPriceField) [HZConfig setGrizzlyMaxPrice:v];
}

- (void)pushToApps {
    NSInteger n = [HZContainerSync writeSmsSettingsToAllApps];
    NSLog(@"[Heavenzy] SMS settings pushed to %ld app container(s)", (long)n);
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { [self fieldChanged:tf]; [self pushToApps]; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [self pushToApps];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case HZSectionProvider: return 2;
        case HZSectionDiddy:    return 1;
        case HZSectionGrizzly:  return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case HZSectionProvider: return @"PROVIDER";
        case HZSectionDiddy:    return @"DIDDYSMS";
        case HZSectionGrizzly:  return @"GRIZZLYSMS";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case HZSectionProvider:
            return @"The service is detected from the app's name (Instagram → instagram / ig) and the country "
                   @"is always USA.";
        case HZSectionDiddy:
            return @"Bearer key from your DiddySMS dashboard. US numbers; carriers are tried automatically.";
        case HZSectionGrizzly:
            return @"API key from grizzlysms.com. Max price caps how much a single number may cost.";
    }
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

    if (ip.section == HZSectionProvider) {
        BOOL grizzly = [[HZConfig smsProvider] isEqualToString:@"grizzly"];
        BOOL isGrizzlyRow = ip.row == 1;
        BOOL selected = grizzly == isGrizzlyRow;
        cell.textLabel.text = isGrizzlyRow ? @"GrizzlySMS" : @"DiddySMS";
        cell.detailTextLabel.text = isGrizzlyRow ? @"sms-activate protocol · country 187 (USA)" : @"api.diddysms.com · US carriers";
        cell.imageView.image = [UIImage systemImageNamed:isGrizzlyRow ? @"pawprint.fill" : @"bolt.fill"];
        cell.imageView.tintColor = selected ? HZAccent() : HZTextMuted();
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle" withConfiguration:c]];
        check.tintColor = selected ? HZAccent() : HZTextMuted();
        cell.accessoryView = check;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    UITextField *tf = nil;
    if (ip.section == HZSectionDiddy) tf = self.diddyKeyField;
    else tf = ip.row == 0 ? self.grizzlyKeyField : self.grizzlyPriceField;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:
        (ip.section == HZSectionGrizzly && ip.row == 1) ? @"dollarsign.circle" : @"key.fill"]];
    icon.tintColor = HZAccent();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    for (UIView *v in @[ icon, tf ]) { v.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22], [icon.heightAnchor constraintEqualToConstant:22],
        [tf.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [tf.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [tf.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != HZSectionProvider) return;
    [HZConfig setSmsProvider:ip.row == 1 ? @"grizzly" : @"diddy"];
    [self pushToApps];
    [tv reloadSections:[NSIndexSet indexSetWithIndex:HZSectionProvider] withRowAnimation:UITableViewRowAnimationNone];
}

@end

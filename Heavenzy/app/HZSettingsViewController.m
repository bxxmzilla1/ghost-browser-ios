#import "HZSettingsViewController.h"
#import "HZConfig.h"
#import "HZContainerSync.h"

static UIColor *HZAccent(void) { return [UIColor colorWithRed:0.55 green:0.45 blue:0.98 alpha:1.0]; }
static UIColor *HZCellBG(void) { return [UIColor colorWithRed:0.11 green:0.11 blue:0.14 alpha:1.0]; }

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
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.diddyKeyField     = [self field:@"DiddySMS API key" text:[HZConfig diddyKey] secure:YES];
    self.grizzlyKeyField   = [self field:@"GrizzlySMS API key" text:[HZConfig grizzlyKey] secure:YES];
    self.grizzlyPriceField = [self field:@"Max price (optional, e.g. 0.50)" text:[HZConfig grizzlyMaxPrice] secure:NO];
    self.grizzlyPriceField.keyboardType = UIKeyboardTypeDecimalPad;
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure {
    UITextField *tf = [UITextField new];
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.45 alpha:1.0] }];
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
        case HZSectionProvider: return @"SMS PROVIDER";
        case HZSectionDiddy:    return @"DIDDYSMS";
        case HZSectionGrizzly:  return @"GRIZZLYSMS";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case HZSectionProvider:
            return @"The Heavenzy SMS panel inside each app uses this provider to order a number and read the "
                   @"verification code. The service is detected from the app's name (Instagram → instagram / ig) "
                   @"and the country is always USA.";
        case HZSectionDiddy:
            return @"Bearer API key from your DiddySMS dashboard. US numbers; carriers are tried automatically.";
        case HZSectionGrizzly:
            return @"API key from grizzlysms.com. Max price caps how much a single number may cost.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = HZCellBG();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.tintColor = HZAccent();

    if (ip.section == HZSectionProvider) {
        BOOL grizzly = [[HZConfig smsProvider] isEqualToString:@"grizzly"];
        BOOL isGrizzlyRow = ip.row == 1;
        cell.textLabel.text = isGrizzlyRow ? @"GrizzlySMS" : @"DiddySMS";
        cell.detailTextLabel.text = isGrizzlyRow ? @"sms-activate protocol · numeric country 187 (USA)" : @"api.diddysms.com · US numbers";
        cell.accessoryType = (grizzly == isGrizzlyRow) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    UITextField *tf = nil;
    if (ip.section == HZSectionDiddy) tf = self.diddyKeyField;
    else tf = ip.row == 0 ? self.grizzlyKeyField : self.grizzlyPriceField;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:tf];
    [NSLayoutConstraint activateConstraints:@[
        [tf.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [tf.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [tf.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
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

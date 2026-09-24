#import "HZAccountViewController.h"
#import "HZTheme.h"
#import "HZConfig.h"
#import "HZCloud.h"

typedef NS_ENUM(NSInteger, HZAccountSection) {
    HZAccountStatus,     // signed-in card (or "not signed in")
    HZAccountProject,    // Supabase URL + anon key (hidden while signed in)
    HZAccountCreds,      // email + password (hidden while signed in)
    HZAccountActions,    // Sign In / Create Account  or  Sign Out
    HZAccountCount
};

@interface HZAccountViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, copy) NSString *statusLine;      // e.g. "12 saved logins in your account"
@end

@implementation HZAccountViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Account";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.urlField = [self field:@"https://xxxx.supabase.co" text:[HZConfig cloudURL] secure:NO];
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.keyField = [self field:@"anon public key (eyJ…)" text:[HZConfig cloudAnonKey] secure:YES];
    self.emailField = [self field:@"Email" text:[HZCloud shared].email secure:NO];
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.passwordField = [self field:@"Password" text:@"" secure:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged)
                                                 name:HZCloudSessionDidChangeNotification object:nil];
    [self refreshStatus];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:@"icloud.and.arrow.up.fill" withConfiguration:c]
                        imageWithTintColor:HZAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        self.tableView.tableHeaderView = HZHeroHeader(self.tableView.bounds.size.width, img, YES, @"Your Account",
            @"Keep every saved login in your own Supabase project instead of on this iPhone, and restore them on any phone you sign in on.", nil);
    }
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure {
    UITextField *tf = [UITextField new];
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{ NSForegroundColorAttributeName: HZTextMuted() }];
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

- (void)fieldChanged:(UITextField *)tf {
    if (tf == self.urlField) [HZConfig setCloudURL:tf.text];
    else if (tf == self.keyField) [HZConfig setCloudAnonKey:tf.text];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (void)sessionChanged {
    self.emailField.text = [HZCloud shared].email ?: self.emailField.text;
    [self refreshStatus];
}

- (void)refreshStatus {
    [self.tableView reloadData];
    if (![HZCloud shared].signedIn) { self.statusLine = nil; return; }
    [[HZCloud shared] listContainersForApp:nil completion:^(NSArray<NSDictionary *> *rows, NSError *error) {
        if (error) self.statusLine = [NSString stringWithFormat:@"Couldn't reach your project: %@", error.localizedDescription];
        else {
            unsigned long long bytes = 0;
            NSMutableSet *apps = [NSMutableSet set];
            for (NSDictionary *r in rows) { bytes += [r[@"bytes"] unsignedLongLongValue]; if (r[@"bundle_id"]) [apps addObject:r[@"bundle_id"]]; }
            self.statusLine = rows.count
                ? [NSString stringWithFormat:@"%lu saved login%@ across %lu app%@ · %@ in your account",
                   (unsigned long)rows.count, rows.count == 1 ? @"" : @"s", (unsigned long)apps.count, apps.count == 1 ? @"" : @"s",
                   [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]]
                : @"No saved logins in your account yet";
        }
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZAccountStatus] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZAccountCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    BOOL in = [HZCloud shared].signedIn;
    switch (s) {
        case HZAccountStatus:  return 1;
        case HZAccountProject: return (in || [HZConfig cloudHasBuiltInProject]) ? 0 : 2;
        case HZAccountCreds:   return in ? 0 : 2;
        case HZAccountActions: return in ? 1 : 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    BOOL in = [HZCloud shared].signedIn;
    BOOL builtIn = [HZConfig cloudHasBuiltInProject];
    switch (s) {
        case HZAccountProject: return (in || builtIn) ? nil : @"SUPABASE PROJECT";
        case HZAccountCreds:   return in ? nil : @"SIGN IN";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    BOOL in = [HZCloud shared].signedIn;
    BOOL builtIn = [HZConfig cloudHasBuiltInProject];
    if (s == HZAccountStatus && in)
        return @"While signed in, each saved login is uploaded to your account as soon as it's captured and then "
               @"removed from this iPhone. Restoring downloads it again. Sign in on another phone to see the same list.";
    if (s == HZAccountCreds && !in && builtIn)
        return @"First time? Enter an email and password and tap Create Account. Afterwards, Sign In with the same "
               @"details on any phone to see your saved logins.";
    if (s == HZAccountProject && !in && !builtIn)
        return @"From your Supabase dashboard: Project Settings → API. Paste the Project URL and the anon public key. "
               @"Run the included supabase/schema.sql once in the SQL editor to create the containers table and bucket.";
    if (s == HZAccountActions && !in)
        return @"Create Account registers a new email + password in your project (if your project requires email "
               @"confirmation, tap the link in the email before signing in).";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)fieldCell:(UITextField *)tf symbol:(NSString *)symbol {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = HZAccent();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [tf removeFromSuperview];
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

- (UITableViewCell *)buttonCell:(UIButton *)b {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.enabled = !self.busy;
    b.alpha = self.busy ? 0.6 : 1.0;
    [cell.contentView addSubview:b];
    [NSLayoutConstraint activateConstraints:@[
        [b.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [b.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [b.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [b.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
    ]];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    HZCloud *cloud = [HZCloud shared];
    if (ip.section == HZAccountStatus) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.backgroundColor = HZCard();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.detailTextLabel.textColor = HZTextMuted();
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.numberOfLines = 0;
        if (cloud.signedIn) {
            cell.textLabel.text = cloud.email ?: @"Signed in";
            cell.detailTextLabel.text = self.statusLine ?: @"Checking your account…";
            cell.imageView.image = [UIImage systemImageNamed:@"checkmark.icloud.fill"];
            cell.imageView.tintColor = HZSuccess();
        } else {
            cell.textLabel.text = @"Not signed in";
            cell.detailTextLabel.text = cloud.configured
                ? @"Saved logins stay on this iPhone until you sign in or create an account below."
                : @"Add your Supabase project below, then sign in or create an account.";
            cell.imageView.image = [UIImage systemImageNamed:@"icloud.slash"];
            cell.imageView.tintColor = HZTextMuted();
        }
        return cell;
    }
    if (ip.section == HZAccountProject) return [self fieldCell:ip.row == 0 ? self.urlField : self.keyField symbol:ip.row == 0 ? @"link" : @"key.fill"];
    if (ip.section == HZAccountCreds)   return [self fieldCell:ip.row == 0 ? self.emailField : self.passwordField symbol:ip.row == 0 ? @"envelope.fill" : @"lock.fill"];

    // Actions
    if (cloud.signedIn) {
        HZOutlineButton *b = [HZOutlineButton buttonWithTitle:@"Sign Out" symbol:@"rectangle.portrait.and.arrow.right" color:HZDanger()];
        [b addTarget:self action:@selector(signOut) forControlEvents:UIControlEventTouchUpInside];
        return [self buttonCell:b];
    }
    if (ip.row == 0) {
        HZGradientButton *b = [HZGradientButton buttonWithTitle:self.busy ? @"Working…" : @"Sign In" symbol:@"person.crop.circle.badge.checkmark"];
        [b addTarget:self action:@selector(signIn) forControlEvents:UIControlEventTouchUpInside];
        return [self buttonCell:b];
    }
    HZOutlineButton *b = [HZOutlineButton buttonWithTitle:@"Create Account" symbol:@"person.badge.plus" color:HZAccent()];
    [b addTarget:self action:@selector(signUp) forControlEvents:UIControlEventTouchUpInside];
    return [self buttonCell:b];
}

#pragma mark - Actions

- (BOOL)validateCreds {
    [self.view endEditing:YES];
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![HZCloud shared].configured) { [self alert:@"Project Missing" message:@"Enter your Supabase project URL and anon key first."]; return NO; }
    if (![email containsString:@"@"]) { [self alert:@"Email" message:@"Enter a valid email address."]; return NO; }
    if (self.passwordField.text.length < 6) { [self alert:@"Password" message:@"Use at least 6 characters."]; return NO; }
    return YES;
}

- (void)setBusy:(BOOL)busy { _busy = busy; [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZAccountActions] withRowAnimation:UITableViewRowAnimationNone]; }

- (void)signIn {
    if (self.busy || ![self validateCreds]) return;
    self.busy = YES;
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [[HZCloud shared] signInWithEmail:email password:self.passwordField.text completion:^(NSError *error) {
        self.busy = NO;
        if (error) { [self alert:@"Sign In Failed" message:error.localizedDescription]; return; }
        self.passwordField.text = @"";
        [self refreshStatus];
    }];
}

- (void)signUp {
    if (self.busy || ![self validateCreds]) return;
    self.busy = YES;
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [[HZCloud shared] signUpWithEmail:email password:self.passwordField.text completion:^(BOOL needsConfirm, NSError *error) {
        self.busy = NO;
        if (error) { [self alert:@"Couldn't Create Account" message:error.localizedDescription]; return; }
        if (needsConfirm) {
            [self alert:@"Check Your Email" message:[NSString stringWithFormat:@"We sent a confirmation link to %@. Tap it, then come back and Sign In.", email]];
            return;
        }
        self.passwordField.text = @"";
        [self refreshStatus];
    }];
}

- (void)signOut {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sign Out?"
        message:@"Saved logins already in your account stay there. New saves will be kept on this iPhone until you sign in again."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Sign Out" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [[HZCloud shared] signOut:^{ [self refreshStatus]; }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

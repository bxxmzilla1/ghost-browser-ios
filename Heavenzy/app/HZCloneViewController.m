#import "HZCloneViewController.h"
#import "HZCloner.h"
#import "HZTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

enum { SEC_SOURCE, SEC_APP, SEC_CLONE, SEC_BUILD, SEC_STATUS, SEC_COUNT };

@interface HZCloneViewController () <UIDocumentPickerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) HZCloneSource *source;
@property (nonatomic, strong) UITextField *pathField;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *bundleField;
@property (nonatomic, strong) UISwitch *stripSwitch;
@property (nonatomic, strong) HZGradientButton *buildButton;
@property (nonatomic, strong) HZOutlineButton *shareButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy)   NSString *builtIPA;
@property (nonatomic, assign) BOOL busy;
@end

@implementation HZCloneViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Clone";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;

    self.pathField   = [self field:@"…or type a path, e.g. /var/mobile/Documents/app.ipa"];
    self.pathField.returnKeyType = UIReturnKeyGo;
    self.nameField   = [self field:@"Display name"];
    self.bundleField = [self field:@"Bundle ID"];
    self.bundleField.keyboardType = UIKeyboardTypeURL;

    self.stripSwitch = [UISwitch new];
    self.stripSwitch.onTintColor = HZAccent();
    self.stripSwitch.on = YES;

    self.buildButton = [HZGradientButton buttonWithTitle:@"Build & Install Clone" symbol:@"plus.square.on.square.fill"];
    [self.buildButton addTarget:self action:@selector(buildTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = [HZOutlineButton buttonWithTitle:@"Share .ipa (TrollStore / Filza)" symbol:@"square.and.arrow.up" color:HZAccent()];
    [self.shareButton addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.textColor = HZTextMuted();
    NSString *missing = [HZCloner missingTools];
    self.statusLabel.text = missing ?: @"Ready. Pick a decrypted IPA to start.";
    if (missing) self.statusLabel.textColor = HZDanger();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:@"plus.square.on.square.fill" withConfiguration:c]
                        imageWithTintColor:HZAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        self.tableView.tableHeaderView = HZHeroHeader(self.tableView.bounds.size.width, img, YES, @"Clone an app",
            @"Each clone gets its own bundle ID, sandbox, keychain and app groups, no iCloud — nothing is shared with the original or other clones. Clones are installed tweak-free so they're clean from tweak detection.", nil);
    }
}

- (UITextField *)field:(NSString *)placeholder {
    UITextField *tf = [UITextField new];
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{ NSForegroundColorAttributeName: HZTextMuted() }];
    tf.textColor = UIColor.whiteColor; tf.tintColor = HZAccent();
    tf.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    return tf;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    if (tf == self.pathField && tf.text.length) [self loadIPA:[NSURL fileURLWithPath:tf.text]];
    return YES;
}

#pragma mark - Source

- (void)pickTapped {
    NSMutableArray *types = [NSMutableArray new];
    UTType *ipa = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
    if (ipa) [types addObject:ipa];
    [types addObject:UTTypeZIP];
    [types addObject:UTTypeData];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.firstObject) [self loadIPA:urls.firstObject];
}

- (void)loadIPA:(NSURL *)url {
    if (self.busy) return;
    if (self.source) { [HZCloner cleanup:self.source]; self.source = nil; self.builtIPA = nil; }
    [self.tableView reloadData];   // source cleared → sections collapse
    [self setBusy:YES status:[NSString stringWithFormat:@"Extracting %@… (large IPAs take a minute)", url.lastPathComponent]];
    [HZCloner inspectIPA:url completion:^(HZCloneSource *source, NSString *error) {
        if (!source) { [self setBusy:NO status:nil]; [self setStatus:error ?: @"Couldn't read the IPA." error:YES]; return; }
        self.source = source;
        self.nameField.text = [NSString stringWithFormat:@"%@ 2", source.name];
        self.bundleField.text = [HZCloner suggestedBundleIdFor:source.bundleId];
        [self.tableView reloadData];   // new sections appear; must happen before any begin/endUpdates
        [self setBusy:NO status:nil];
        [self setStatus:source.encrypted
            ? @"This IPA is still encrypted (FairPlay). Heavenzy can only clone a decrypted IPA."
            : [NSString stringWithFormat:@"Loaded %@ %@ — decrypted, ready to clone.", source.name, source.version]
                  error:source.encrypted];
    }];
}

#pragma mark - Build

- (void)buildTapped {
    if (!self.source || self.busy) return;
    [self.view endEditing:YES];
    NSString *bid = [self.bundleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!bid.length || [bid rangeOfString:@" "].location != NSNotFound) { [self setStatus:@"Bundle ID can't be empty or contain spaces." error:YES]; return; }
    [self setBusy:YES status:@"Building clone…"];
    [HZCloner buildClone:self.source bundleId:bid displayName:name removeExtensions:self.stripSwitch.on
                progress:^(NSString *step) { [self setStatus:step error:NO]; }
              completion:^(NSString *ipaPath, NSString *error) {
        if (!ipaPath) { [self setBusy:NO status:nil]; [self setStatus:error error:YES]; return; }
        self.builtIPA = ipaPath;
        [self.tableView reloadData];   // share row appears
        // Configure Choicy up-front so the clone is tweak-free no matter how it ends up installed.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [HZCloner disableTweaksForApp:bid]; });
        [self setStatus:@"Installing…" error:NO];
        [HZCloner installIPA:ipaPath bundleId:bid completion:^(BOOL ok, NSString *installError) {
            if (!ok) {
                [self setBusy:NO status:nil];
                // The clone was built fine; only the one-tap install needs AppSync. Point to sideloading.
                [self setStatus:[NSString stringWithFormat:@"Clone built ✓  %@\nSaved to Documents/Heavenzy.\n\n%@\n\nTap “Share .ipa” below to install it with TrollStore or Filza.", ipaPath.lastPathComponent, installError] error:NO];
                [self.tableView reloadData];
                return;
            }
            [self setStatus:@"Installed. Making it tweak-free…" error:NO];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [HZCloner disableTweaksForApp:bid];   // now the container exists → set the inert flag too
                BOOL choicy = [HZCloner isChoicyInstalled];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setBusy:NO status:nil];
                    [self setStatus:choicy
                        ? [NSString stringWithFormat:@"Done. %@ (%@) is installed and Choicy is set to block all tweak injection for it — it runs clean, no Heavenzy panel, nothing to detect. Open it from the Home Screen.", name, bid]
                        : [NSString stringWithFormat:@"Done. %@ (%@) is installed and the Heavenzy panel is disabled inside it. For a fully undetectable clone, install Choicy (it's already configured to block injection for this app).", name, bid]
                          error:NO];
                    [self.tableView reloadData];
                });
            });
        }];
    }];
}

- (void)shareTapped {
    if (!self.builtIPA) return;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[ [NSURL fileURLWithPath:self.builtIPA] ] applicationActivities:nil];
    a.popoverPresentationController.sourceView = self.shareButton;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    self.busy = busy;
    self.buildButton.enabled = !busy;
    self.buildButton.alpha = busy ? 0.5 : 1;
    if (status) [self setStatus:status error:NO];
}

- (void)setStatus:(NSString *)text error:(BOOL)isError {
    self.statusLabel.text = text;
    self.statusLabel.textColor = isError ? HZDanger() : HZTextMuted();
    [self syncTable];
}

// Re-measure the status row. If the model changed the row counts since the last load (source picked,
// ipa built…) a plain begin/endUpdates would throw NSInternalInconsistencyException, so reload instead.
- (void)syncTable {
    UITableView *tv = self.tableView;
    if (!tv.window) return;
    BOOL mismatch = NO;
    for (NSInteger s = 0; s < SEC_COUNT && !mismatch; s++)
        if ([tv numberOfRowsInSection:s] != [self tableView:tv numberOfRowsInSection:s]) mismatch = YES;
    if (mismatch) [tv reloadData];
    else [UIView performWithoutAnimation:^{ [tv beginUpdates]; [tv endUpdates]; }];
}

- (void)dealloc { if (_source) [HZCloner cleanup:_source]; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SEC_COUNT; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SEC_SOURCE: return 2;
        case SEC_APP:    return self.source ? 4 : 0;
        case SEC_CLONE:  return self.source ? 3 : 0;
        case SEC_BUILD:  return (self.source ? 1 : 0) + (self.builtIPA ? 1 : 0);   // build, share
        case SEC_STATUS: return 1;
    }
    return 0;
}

// The button rows draw their own background, so hide the grouped card behind them.
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SEC_BUILD) {
        cell.backgroundColor = UIColor.clearColor; cell.backgroundView = nil;
        cell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SEC_SOURCE: return @"SOURCE IPA";
        case SEC_APP:    return self.source ? @"ORIGINAL APP" : nil;
        case SEC_CLONE:  return self.source ? @"CLONE" : nil;
        case SEC_STATUS: return @"STATUS";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case SEC_SOURCE: return @"Must be a decrypted IPA you're entitled to. Heavenzy never downloads or decrypts App Store apps.";
        case SEC_CLONE:  return self.source ? @"The clone gets its own bundle ID, sandbox, keychain and app groups, and no iCloud — it shares nothing with the original or other clones. Removing extensions (share sheet, widgets, notifications) is recommended — they break in clones." : nil;
        case SEC_STATUS: return @"Clones are made tweak-free: Choicy (recommended) is configured to block all tweak injection for the clone, so Heavenzy isn't loaded inside it and there's nothing to detect. One-tap install needs AppSync Unified; otherwise the .ipa is saved to /var/mobile/Documents/Heavenzy — share it to TrollStore or open it with Filza.";
    }
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)baseCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = HZTextMuted();
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;
    cell.tintColor = HZAccent();
    return cell;
}

- (void)embed:(UIView *)v in:(UITableViewCell *)cell inset:(CGFloat)inset { [self embed:v in:cell h:inset v:inset]; }

- (void)embed:(UIView *)v in:(UITableViewCell *)cell h:(CGFloat)h v:(CGFloat)vert {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:h],
        [v.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-h],
        [v.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:vert],
        [v.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-vert],
    ]];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [self baseCell];
    HZCloneSource *s = self.source;

    if (ip.section == SEC_SOURCE) {
        if (ip.row == 0) {
            cell.textLabel.text = @"Choose IPA from Files…";
            cell.textLabel.textColor = HZAccent();
            cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            [self.pathField removeFromSuperview];
            [self embed:self.pathField in:cell inset:14];
        }
        return cell;
    }

    if (ip.section == SEC_APP) {
        NSArray *rows = @[
            @[ @"Name",      s.name ?: @"—" ],
            @[ @"Bundle ID", s.bundleId ?: @"—" ],
            @[ @"Version",   s.version ?: @"—" ],
            @[ @"Binary",    s.encrypted ? @"encrypted ✕" : @"decrypted ✓" ],
        ];
        cell.textLabel.text = rows[ip.row][0];
        cell.detailTextLabel.text = rows[ip.row][1];
        if (ip.row == 3) cell.detailTextLabel.textColor = s.encrypted ? HZDanger() : HZSuccess();
        return cell;
    }

    if (ip.section == SEC_CLONE) {
        if (ip.row == 2) {
            cell.textLabel.text = @"Remove extensions";
            cell.detailTextLabel.text = s.hasExtensions ? @"found" : @"none";
            cell.accessoryView = self.stripSwitch;
            return cell;
        }
        UITextField *tf = ip.row == 0 ? self.nameField : self.bundleField;
        [tf removeFromSuperview];
        UILabel *l = [UILabel new];
        l.text = ip.row == 0 ? @"Name" : @"Bundle ID";
        l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [l.widthAnchor constraintEqualToConstant:84].active = YES;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ l, tf ]];
        row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 10; row.alignment = UIStackViewAlignmentCenter;
        [self embed:row in:cell inset:14];
        return cell;
    }

    if (ip.section == SEC_STATUS) {
        [self.statusLabel removeFromSuperview];
        [self embed:self.statusLabel in:cell inset:14];
        return cell;
    }

    // SEC_BUILD: row 0 build button, row 1 share button
    UIButton *b = ip.row == 0 ? self.buildButton : self.shareButton;
    [b removeFromSuperview];
    cell.backgroundColor = UIColor.clearColor;
    [self embed:b in:cell h:0 v:5];
    if (b == self.buildButton) {
        self.buildButton.enabled = !self.busy && !s.encrypted;
        self.buildButton.alpha = self.buildButton.enabled ? 1 : 0.5;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SEC_SOURCE && ip.row == 0) [self pickTapped];
}

@end

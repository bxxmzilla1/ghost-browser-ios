#import "HZWebContainersViewController.h"
#import "HZTheme.h"
#import "HZWebClips.h"
#import <spawn.h>
#import <crt_externs.h>

typedef NS_ENUM(NSInteger, HZWCSection) { HZWCSite, HZWCCreate, HZWCList, HZWCActions, HZWCSectionCount };
typedef NS_ENUM(NSInteger, HZWCCreateRow) { HZWCCreateCount, HZWCCreateUpload, HZWCCreateButton, HZWCCreateRowCount };

static const NSInteger kHZMaxBatch = 100;

#pragma mark - Helpers

/// Respring so SpringBoard picks up new / removed web clip bundles. YES if a known tool was launched.
static BOOL HZRespring(void) {
    NSArray<NSArray<NSString *> *> *candidates = @[
        @[ @"/var/jb/usr/bin/killall", @"-9", @"SpringBoard" ],
        @[ @"/var/jb/usr/bin/sbreload" ],
        @[ @"/usr/bin/killall", @"-9", @"SpringBoard" ],
    ];
    for (NSArray<NSString *> *argv in candidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:argv[0]]) continue;
        const char *cargv[4] = { 0 };
        for (NSUInteger i = 0; i < argv.count && i < 3; i++) cargv[i] = argv[i].UTF8String;
        pid_t pid = 0;
        if (posix_spawn(&pid, cargv[0], NULL, NULL, (char *const *)cargv, *_NSGetEnviron()) == 0) return YES;
    }
    return NO;
}

/// 180×180 opaque icon: the site's touch icon (or a violet tile with its initial) plus a number badge.
static NSData *HZContainerIconPNG(UIImage *base, NSString *initial, NSInteger number) {
    CGSize sz = CGSizeMake(180, 180);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
    f.scale = 1; f.opaque = YES;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:f];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect full = (CGRect){ CGPointZero, sz };
        if (base) {
            [base drawInRect:full];
        } else {
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CFArrayRef colors = (__bridge CFArrayRef)@[ (id)HZAccent().CGColor, (id)HZAccentDeep().CGColor ];
            CGGradientRef g = CGGradientCreateWithColors(cs, colors, NULL);
            CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(sz.width, sz.height), 0);
            CGGradientRelease(g); CGColorSpaceRelease(cs);
            NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:96 weight:UIFontWeightBold],
                                     NSForegroundColorAttributeName: UIColor.whiteColor };
            CGSize ts = [initial sizeWithAttributes:attrs];
            [initial drawAtPoint:CGPointMake((sz.width - ts.width) / 2, (sz.height - ts.height) / 2 - 6) withAttributes:attrs];
        }
        NSString *t = @(number).stringValue;
        UIFont *font = [UIFont systemFontOfSize:40 weight:UIFontWeightHeavy];
        NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor };
        CGSize ts = [t sizeWithAttributes:attrs];
        CGFloat h = 58, w = MAX(h, ts.width + 30);
        CGRect pill = CGRectMake(sz.width - w - 8, sz.height - h - 8, w, h);
        [[UIColor colorWithWhite:0 alpha:0.74] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:h / 2] fill];
        [t drawAtPoint:CGPointMake(CGRectGetMidX(pill) - ts.width / 2, CGRectGetMidY(pill) - ts.height / 2) withAttributes:attrs];
    }];
    return UIImagePNGRepresentation(img);
}

/// Best-effort fetch of the site's apple-touch-icon (a few seconds, background queue only).
static UIImage *HZFetchTouchIcon(NSString *site) {
    NSURL *base = [NSURL URLWithString:site];
    if (!base.host) return nil;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 6; cfg.timeoutIntervalForResource = 8;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    for (NSString *path in @[ @"/apple-touch-icon.png", @"/apple-touch-icon-precomposed.png" ]) {
        NSURL *u = [NSURL URLWithString:path relativeToURL:base].absoluteURL;
        if (!u) continue;
        __block UIImage *found = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [[session dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
            if (!err && status == 200 && data.length > 0) {
                UIImage *i = [UIImage imageWithData:data];
                if (i && i.size.width >= 57) found = i;
            }
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 9 * NSEC_PER_SEC));
        if (found) { [session invalidateAndCancel]; return found; }
    }
    [session invalidateAndCancel];
    return nil;
}

#pragma mark - Controller

@interface HZWebContainersViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *containers;
@property (nonatomic, strong) UITextField *siteField;
@property (nonatomic, strong) UITextField *prefixField;
@property (nonatomic, strong) UITextField *countField;
@property (nonatomic, assign) BOOL creating;
@end

@implementation HZWebContainersViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (UITextField *)makeField:(NSString *)placeholder text:(NSString *)text {
    UITextField *f = [UITextField new];
    f.textColor = UIColor.whiteColor;
    f.tintColor = HZAccent();
    f.font = [UIFont systemFontOfSize:15];
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                              attributes:@{ NSForegroundColorAttributeName: HZTextMuted() }];
    f.text = text;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Web Containers";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = HZBG();
    HZStyleTable(self.tableView);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;

    self.siteField = [self makeField:@"instagram.com" text:[HZWebClips lastSite] ?: @""];
    self.siteField.keyboardType = UIKeyboardTypeURL;
    self.prefixField = [self makeField:@"Instagram" text:[HZWebClips lastPrefix] ?: @""];
    self.prefixField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.countField = [self makeField:@"5" text:@""];
    self.countField.keyboardType = UIKeyboardTypeNumberPad;
    self.countField.textAlignment = NSTextAlignmentRight;

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView.tableHeaderView || self.tableView.tableHeaderView.frame.size.width != self.tableView.bounds.size.width) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:@"square.on.square" withConfiguration:c]
                        imageWithTintColor:HZAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        self.tableView.tableHeaderView = HZHeroHeader(self.tableView.bounds.size.width, img, YES, @"Web Containers",
                                                      @"One site, many Home Screen icons, each a new device", nil);
    }
}

- (void)reload {
    self.containers = [HZWebClips containers];
    [self.tableView reloadData];
}

#pragma mark - Text fields

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (void)textFieldDidEndEditing:(UITextField *)tf {
    if (tf != self.siteField) return;
    // Suggest a name from the host ("www.instagram.com" → "Instagram") when none was typed.
    NSString *site = [HZWebClips normalizedSite:tf.text];
    if (!site || self.prefixField.text.length) return;
    NSString *host = [NSURL URLWithString:site].host.lowercaseString;
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    NSString *name = [host componentsSeparatedByString:@"."].firstObject;
    if (name.length) self.prefixField.text = [name capitalizedString];
}

#pragma mark - Create

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)offerRespring:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        [self respring];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)respring {
    if (!HZRespring()) [self alert:@"Respring failed" message:@"killall / sbreload not found. Respring from your jailbreak app."];
}

- (void)create {
    [self.view endEditing:YES];
    if (self.creating) return;

    NSString *site = [HZWebClips normalizedSite:self.siteField.text];
    if (!site) { [self alert:@"Enter a website" message:@"For example instagram.com or https://www.tiktok.com/login"]; return; }
    NSString *prefix = [self.prefixField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (prefix.length == 0) { [self textFieldDidEndEditing:self.siteField]; prefix = self.prefixField.text ?: @"Web"; }
    NSInteger count = self.countField.text.integerValue;
    if (count < 1 || count > kHZMaxBatch) {
        [self alert:@"How many?" message:[NSString stringWithFormat:@"Enter a number from 1 to %ld.", (long)kHZMaxBatch]];
        return;
    }
    BOOL upload = [HZWebClips uploadSpoofDefault];
    NSString *host = [[NSURL URLWithString:site].host stringByReplacingOccurrencesOfString:@"www." withString:@""];
    NSString *initial = host.length ? [[host substringToIndex:1] uppercaseString] : @"W";

    self.creating = YES;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:HZWCCreate] withRowAnimation:UITableViewRowAnimationNone];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *touchIcon = HZFetchTouchIcon(site);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *made = [HZWebClips createContainers:count site:site prefix:prefix upload:upload
                                           iconForNumber:^NSData *(NSInteger number) {
                return HZContainerIconPNG(touchIcon, initial, number);
            }];
            self.creating = NO;
            self.countField.text = @"";
            [self reload];
            if (made.count == 0) {
                [self alert:@"Nothing created" message:@"Could not write to /var/mobile/Library/WebClips."];
                return;
            }
            [self offerRespring:[NSString stringWithFormat:@"%lu container%@ created", (unsigned long)made.count, made.count == 1 ? @"" : @"s"]
                        message:@"The icons appear on the Home Screen after a respring. Each one opens as its own device."];
        });
    });
}

#pragma mark - Per-container actions

- (void)showActionsFor:(NSDictionary *)c {
    BOOL iconThere = [HZWebClips iconExistsForContainer:c];
    BOOL linked = [c[@"stores"] count] > 0;
    NSString *msg = [NSString stringWithFormat:@"%@\nSeed %@ · %@%@", c[@"url"], [HZWebClips seedLabel:c],
                     linked ? @"opened" : @"not opened yet", iconThere ? @"" : @" · icon removed from Home Screen"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:c[@"name"] message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset identity & data" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        [self confirmReset:c];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy seed" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = [HZWebClips seedLabel:c];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete container" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [self confirmDelete:c];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmReset:(NSDictionary *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset container?"
        message:[NSString stringWithFormat:@"%@ gets a new fingerprint and all its cookies, logins and site data are erased the next time it opens. Close it in the App Switcher first.", c[@"name"]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [HZWebClips resetContainer:c[@"id"]];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(NSDictionary *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete container?"
        message:[NSString stringWithFormat:@"Removes the %@ icon and forgets its identity. Its site data is dropped by iOS once the icon is gone.", c[@"name"]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [HZWebClips removeContainer:c[@"id"]];
        [self reload];
        [self offerRespring:@"Container deleted" message:@"Respring to remove the icon from the Home Screen."];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDeleteAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete all containers?"
        message:[NSString stringWithFormat:@"Removes all %lu icons and their identities.", (unsigned long)self.containers.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        for (NSDictionary *c in self.containers) [HZWebClips removeContainer:c[@"id"]];
        [self reload];
        [self offerRespring:@"All containers deleted" message:@"Respring to remove the icons from the Home Screen."];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)uploadSwitched:(UISwitch *)sw { [HZWebClips setUploadSpoofDefault:sw.on]; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return HZWCSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case HZWCSite:    return 2;
        case HZWCCreate:  return HZWCCreateRowCount;
        case HZWCList:    return MAX(1, (NSInteger)self.containers.count);
        case HZWCActions: return self.containers.count ? 2 : 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case HZWCSite:   return @"WEBSITE";
        case HZWCCreate: return @"CREATE";
        case HZWCList:   return [NSString stringWithFormat:@"CONTAINERS · %lu", (unsigned long)self.containers.count];
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case HZWCCreate:
            return @"Each icon is a full-screen web app with its own cookies, cache, IndexedDB and localStorage. Heavenzy gives every one a unique canvas and audio fingerprint, hides your LAN address from WebRTC and, optionally, re-encodes photos you upload.";
        case HZWCList:
            return self.containers.count ? @"Tap a container to reset or delete it. Resets apply the next time the icon is opened." : nil;
    }
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { HZStyleHeaderFooter(v); }

- (UITableViewCell *)baseCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = HZCard();
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = HZTextMuted();
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIView *sel = [UIView new]; sel.backgroundColor = HZCardElevated(); cell.selectedBackgroundView = sel;
    cell.tintColor = HZAccent();
    return cell;
}

- (UITableViewCell *)fieldCell:(NSString *)label field:(UITextField *)field symbol:(NSString *)symbol {
    UITableViewCell *cell = [self baseCell];
    cell.textLabel.text = label;
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = HZAccent();
    [field removeFromSuperview];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:140],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:40],
    ]];
    return cell;
}

- (UITableViewCell *)buttonCell:(UIButton *)b {
    UITableViewCell *cell = [self baseCell];
    cell.backgroundColor = UIColor.clearColor;
    b.translatesAutoresizingMaskIntoConstraints = NO;
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
    switch (ip.section) {
        case HZWCSite:
            if (ip.row == 0) return [self fieldCell:@"Website" field:self.siteField symbol:@"globe"];
            return [self fieldCell:@"Icon name" field:self.prefixField symbol:@"textformat"];

        case HZWCCreate:
            if (ip.row == HZWCCreateCount) return [self fieldCell:@"How many" field:self.countField symbol:@"number"];
            if (ip.row == HZWCCreateUpload) {
                UITableViewCell *cell = [self baseCell];
                cell.textLabel.text = @"Re-encode uploaded photos";
                cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
                cell.imageView.tintColor = HZAccent();
                UISwitch *sw = [UISwitch new];
                sw.onTintColor = HZAccent();
                sw.on = [HZWebClips uploadSpoofDefault];
                [sw addTarget:self action:@selector(uploadSwitched:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                return cell;
            }
            {
                HZGradientButton *b = [HZGradientButton buttonWithTitle:self.creating ? @"Creating…" : @"Create Containers"
                                                                 symbol:self.creating ? @"hourglass" : @"plus.square.on.square"];
                b.enabled = !self.creating;
                b.alpha = self.creating ? 0.6 : 1.0;
                [b addTarget:self action:@selector(create) forControlEvents:UIControlEventTouchUpInside];
                return [self buttonCell:b];
            }

        case HZWCList: {
            UITableViewCell *cell = [self baseCell];
            if (self.containers.count == 0) {
                cell.textLabel.text = @"No containers yet";
                cell.textLabel.textColor = HZTextMuted();
                cell.detailTextLabel.text = @"Enter a website and a number above.";
                return cell;
            }
            NSDictionary *c = self.containers[ip.row];
            BOOL iconThere = [HZWebClips iconExistsForContainer:c];
            BOOL linked = [c[@"stores"] count] > 0;
            BOOL wipe = [c[@"wipePending"] boolValue];
            cell.textLabel.text = c[@"name"];
            NSString *host = [NSURL URLWithString:c[@"url"]].host ?: c[@"url"];
            NSString *state = !iconThere ? @"icon removed" : wipe ? @"reset on next open" : linked ? @"spoofed" : @"ready";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · seed %@ · %@", host, [HZWebClips seedLabel:c], state];
            cell.detailTextLabel.textColor = !iconThere ? HZDanger() : (linked || wipe) ? HZAccent() : HZTextMuted();
            cell.imageView.image = [UIImage systemImageNamed:iconThere ? @"app.badge.checkmark" : @"app.dashed"];
            cell.imageView.tintColor = iconThere ? HZAccent() : HZTextMuted();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }

        case HZWCActions: {
            UIButton *b;
            if (ip.row == 0) {
                b = [HZOutlineButton buttonWithTitle:@"Respring (show / hide icons)" symbol:@"arrow.clockwise" color:HZAccent()];
                [b addTarget:self action:@selector(respring) forControlEvents:UIControlEventTouchUpInside];
            } else {
                b = [HZOutlineButton buttonWithTitle:@"Delete All Containers" symbol:@"trash" color:HZDanger()];
                [b addTarget:self action:@selector(confirmDeleteAll) forControlEvents:UIControlEventTouchUpInside];
            }
            return [self buttonCell:b];
        }
    }
    return [self baseCell];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == HZWCList && self.containers.count) [self showActionsFor:self.containers[ip.row]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == HZWCList && self.containers.count > 0;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete || ip.section != HZWCList || ip.row >= (NSInteger)self.containers.count) return;
    [self confirmDelete:self.containers[ip.row]];
}

@end

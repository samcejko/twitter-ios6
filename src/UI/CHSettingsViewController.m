#import "CHSettingsViewController.h"
#import "CHLoginViewController.h"
#import "CHLinkRouter.h"
#import "CHExternalOpen.h"
#import "CHImageLoader.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

typedef enum { SecAccount, SecServer, SecTimeline, SecAppearance, SecNetwork, SecData, SecAbout, SecCount } CHSection;

@interface CHSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, copy) NSString *account;      // the signed-in @handle (from /me)
@end

@implementation CHSettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Settings");
    [[CHTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Done") style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    if ([CHTwitter configured]) [self loadAccount];
}

- (void)done
{
    [self saveFields];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];     // reflect a login/logout that happened in a sheet above
    [self loadAccount];
}

- (void)loadAccount
{
    if (![CHTwitter loggedIn]) return;
    self.account = [CHTwitter accountHandle];
    [CHTwitter fetchMe:^(CHUser *user, NSError *error) {
        if (user.handle.length) { self.account = user.handle; [self.tableView reloadData]; }
    }];
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return SecCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case SecAccount: return [CHTwitter loggedIn] ? 2 : 1;   // (@handle, log out) | (log in)
        case SecServer: return 4;       // address, key, test, stream-through
        case SecTimeline: return 2;     // autoplay, sensitive
        case SecAppearance: return 1;   // dark
        case SecNetwork: return 1;      // verify TLS
        case SecData: return 2;         // clear cache, clear bookmarks
        case SecAbout: return 3;        // version, about, support
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case SecAccount: return L(@"Account");
        case SecServer: return L(@"Server (your Raspberry Pi)");
        case SecTimeline: return L(@"Timeline");
        case SecAppearance: return L(@"Appearance");
        case SecNetwork: return L(@"Network");
        case SecData: return L(@"Data");
        case SecAbout: return L(@"About");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == SecServer) return L(@"The helper on your Pi signs in to X and fetches the tweets. Enter its address, e.g. https://chirpie.samcejko.eu, and the key if you set one. 'Stream through the server' routes media through the Pi too - slower, but needed away from home.");
    if (section == SecNetwork) return L(@"Turn verification off only to reach a server with a self-signed certificate.");
    return nil;
}

#pragma mark - Cells

- (UITableViewCell *)switchCell:(UITableView *)tv title:(NSString *)title on:(BOOL)on action:(SEL)action
{
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"switch"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
    [[CHTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (UITableViewCell *)fieldCell:(UITableView *)tv field:(UITextField *)field label:(NSString *)label
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[CHTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    field.frame = CGRectMake(16, 0, cell.contentView.bounds.size.width - 32, 44);
    field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    field.delegate = self;
    field.placeholder = label;
    field.textColor = [[CHTheme shared] primaryTextColor];
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [cell.contentView addSubview:field];
    return cell;
}

- (UITableViewCell *)plainCell:(UITableView *)tv title:(NSString *)title blue:(BOOL)blue
{
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"plain"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"plain"];
    [[CHTheme shared] styleCell:cell];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = blue ? [[CHTheme shared] linkColor] : [[CHTheme shared] primaryTextColor];
    cell.textLabel.textAlignment = blue ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHTheme *th = [CHTheme shared];
    switch (indexPath.section) {
        case SecAccount:
            if ([CHTwitter loggedIn]) {
                if (indexPath.row == 0) {
                    UITableViewCell *c = [self plainCell:tableView title:(self.account.length ? [@"@" stringByAppendingString:self.account] : L(@"My profile")) blue:NO];
                    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return c;
                }
                return [self plainCell:tableView title:L(@"Log out") blue:YES];
            }
            return [self plainCell:tableView title:L(@"Log in") blue:YES];
        case SecServer:
            if (indexPath.row == 0) {
                if (!self.addressField) { self.addressField = [[UITextField alloc] init]; self.addressField.keyboardType = UIKeyboardTypeURL; self.addressField.text = [CHSettings serverBaseURL]; }
                return [self fieldCell:tableView field:self.addressField label:L(@"Server address")];
            }
            if (indexPath.row == 1) {
                if (!self.keyField) { self.keyField = [[UITextField alloc] init]; self.keyField.secureTextEntry = YES; self.keyField.text = [CHSettings serverKey]; }
                return [self fieldCell:tableView field:self.keyField label:L(@"Server key")];
            }
            if (indexPath.row == 2) return [self plainCell:tableView title:L(@"Test connection") blue:YES];
            return [self switchCell:tableView title:L(@"Stream through the server") on:[CHSettings streamThroughServer] action:@selector(toggleStream:)];
        case SecTimeline:
            if (indexPath.row == 0) return [self switchCell:tableView title:L(@"Autoplay videos") on:[CHSettings autoplayVideos] action:@selector(toggleAutoplay:)];
            return [self switchCell:tableView title:L(@"Show sensitive media") on:[CHSettings showSensitive] action:@selector(toggleSensitive:)];
        case SecAppearance:
            return [self switchCell:tableView title:L(@"Dark theme") on:th.isDark action:@selector(toggleDark:)];
        case SecNetwork:
            return [self switchCell:tableView title:L(@"Verify certificates") on:[CHSettings verifyTLS] action:@selector(toggleTLS:)];
        case SecData:
            if (indexPath.row == 0) return [self plainCell:tableView title:L(@"Clear image cache") blue:NO];
            return [self plainCell:tableView title:L(@"Clear bookmarks") blue:NO];
        case SecAbout: {
            if (indexPath.row == 0) {
                UITableViewCell *c = [self plainCell:tableView title:L(@"Version") blue:NO];
                c.detailTextLabel.text = [CHUtils appVersion];
                return c;
            }
            if (indexPath.row == 1) {
                UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"about"];
                if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"about"];
                [th styleCell:c];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
                c.textLabel.numberOfLines = 0;
                c.textLabel.font = [th smallFont];
                c.textLabel.textColor = [th secondaryTextColor];
                c.textLabel.text = L(@"Chirpie is an unofficial reader for X / Twitter. It shows what your own account can see, through a helper on your server. Not affiliated with X Corp.");
                return c;
            }
            return [self plainCell:tableView title:L(@"Support the development") blue:YES];
        }
    }
    return [[UITableViewCell alloc] init];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == SecAbout && indexPath.row == 1) return 92;
    return 44;
}

#pragma mark - Actions

- (void)toggleStream:(UISwitch *)sw { [CHSettings setStreamThroughServer:sw.on]; }
- (void)toggleAutoplay:(UISwitch *)sw { [CHSettings setAutoplayVideos:sw.on]; }
- (void)toggleSensitive:(UISwitch *)sw { [CHSettings setShowSensitive:sw.on]; }
- (void)toggleTLS:(UISwitch *)sw { [CHSettings setVerifyTLS:sw.on]; [CHSettings save]; }
- (void)toggleDark:(UISwitch *)sw { [[CHTheme shared] setDark:sw.on]; [self.tableView reloadData]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SecAccount) {
        if (![CHTwitter loggedIn]) { [self logIn]; return; }
        if (indexPath.row == 0) [self openMyProfile];
        else [self logOut];
        return;
    }
    if (indexPath.section == SecServer && indexPath.row == 2) { [self testConnection]; return; }
    if (indexPath.section == SecData) {
        if (indexPath.row == 0) [self clearImageCache];
        else [self clearBookmarks];
        return;
    }
    if (indexPath.section == SecAbout && indexPath.row == 2)
        [CHExternalOpen presentShareSheetForURL:[NSURL URLWithString:@"https://ko-fi.com/samcejko"] from:self anchor:nil];
}

- (void)testConnection
{
    [self saveFields];
    if (![CHTwitter configured]) { [CHUtils alertWithTitle:L(@"Test connection") message:L(@"Set the server address first.")]; return; }
    [CHTwitter checkHealth:^(BOOL ok, NSString *info, NSError *error) {
        [CHUtils alertWithTitle:L(@"Test connection") message:(ok ? L(@"The server is up.") : (error.localizedDescription ?: L(@"The server did not answer.")))];
    }];
}

- (void)logIn
{
    [self saveFields];
    CHLoginViewController *login = [[CHLoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
    [[CHTheme shared] applyToNavigationBar:nav.navigationBar];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)logOut
{
    [CHSettings logOut];
    self.account = nil;
    [self.tableView reloadData];
}

- (void)openMyProfile
{
    NSString *h = [CHTwitter accountHandle] ?: self.account;
    if (h.length) { [self dismissViewControllerAnimated:YES completion:^{ [CHLinkRouter openProfile:h]; }]; return; }
    [CHTwitter fetchMe:^(CHUser *user, NSError *error) {
        if (user.handle.length) [self dismissViewControllerAnimated:YES completion:^{ [CHLinkRouter openProfile:user.handle]; }];
        else [CHUtils alertWithTitle:L(@"My profile") message:error.localizedDescription ?: L(@"Could not load your profile.")];
    }];
}

- (void)clearImageCache
{
    [[CHImageLoader shared] clearMemory];
    [[CHImageLoader shared] clearDiskWithCompletion:^{ [CHUtils alertWithTitle:L(@"Data") message:L(@"Image cache cleared.")]; }];
}

- (void)clearBookmarks
{
    UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:L(@"Clear bookmarks") message:L(@"Remove every bookmarked tweet?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Clear"), nil];
    [confirm show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    for (NSDictionary *d in [CHSettings savedTweets]) [CHSettings unsaveTweet:CHStr(d[@"id"])];
}

#pragma mark - Text fields

- (void)saveFields
{
    if (self.addressField) [CHSettings setServerBaseURL:self.addressField.text];
    if (self.keyField) [CHSettings setServerKey:self.keyField.text];
    [CHSettings save];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)textField { [self saveFields]; }

@end

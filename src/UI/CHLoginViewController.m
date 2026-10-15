#import "CHLoginViewController.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

typedef enum { CHLoginCookies, CHLoginPassword } CHLoginMode;

@interface CHLoginViewController () <UITextFieldDelegate>
@property (nonatomic) CHLoginMode mode;
@property (nonatomic, strong) UISegmentedControl *modeSwitch;
@property (nonatomic, strong) UITextField *authField;
@property (nonatomic, strong) UITextField *ct0Field;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passField;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *totpField;
@property (nonatomic, strong) UISwitch *consentSwitch;
@property (nonatomic, strong) UIBarButtonItem *loginItem;
@property (nonatomic) BOOL working;
@end

@implementation CHLoginViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Log in");
    [[CHTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.loginItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Log in") style:UIBarButtonItemStyleDone target:self action:@selector(logIn)];
    self.navigationItem.rightBarButtonItem = self.loginItem;

    self.modeSwitch = [[UISegmentedControl alloc] initWithItems:@[ L(@"Cookies"), L(@"Password") ]];
    self.modeSwitch.selectedSegmentIndex = 0;
    [self.modeSwitch addTarget:self action:@selector(switchMode) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.modeSwitch;

    self.authField = [self field:@"auth_token" text:[CHSettings xAuthToken] secure:NO];
    self.ct0Field = [self field:@"ct0" text:[CHSettings xCSRF] secure:NO];
    self.userField = [self field:L(@"@username or email") text:@"" secure:NO];
    self.passField = [self field:L(@"Password") text:@"" secure:YES];
    self.emailField = [self field:L(@"Email (if X asks)") text:@"" secure:NO];
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.totpField = [self field:L(@"2FA secret (optional)") text:@"" secure:NO];
    self.consentSwitch = [[UISwitch alloc] init];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)switchMode { self.mode = self.modeSwitch.selectedSegmentIndex; [self.tableView reloadData]; }

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure
{
    UITextField *f = [[UITextField alloc] init];
    f.placeholder = placeholder;
    f.text = text;
    f.delegate = self;
    f.secureTextEntry = secure;
    f.textColor = [[CHTheme shared] primaryTextColor];
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    return f;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.mode == CHLoginPassword ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.mode == CHLoginCookies) return 2;             // auth_token, ct0
    return section == 0 ? 4 : 1;                           // user/pass/email/totp ; consent
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.mode == CHLoginCookies) return L(@"Your X cookies");
    return section == 0 ? L(@"Your X account") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (self.mode == CHLoginCookies)
        return L(@"In a desktop browser signed in to x.com: open the developer tools → Application → Cookies → https://x.com, and copy the values of auth_token and ct0. They stay on this device and are sent with each request; nothing is stored on the server. On this device, a cookie-viewer tweak can read them too.");
    if (section == 1)
        return L(@"Your password is sent to the server (over HTTPS) and read there in plain text once, only to sign in to X for you. It is never stored or logged, and the operator does not keep it or touch your account - only the resulting cookies come back and are kept on this device. The Cookies tab is safer: there your password never leaves your device.");
    return nil;
}

- (UITableViewCell *)fieldCell:(UITableView *)tv field:(UITextField *)f
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[CHTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    f.frame = CGRectMake(16, 0, cell.contentView.bounds.size.width - 32, 44);
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:f];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.mode == CHLoginCookies)
        return [self fieldCell:tableView field:(indexPath.row == 0 ? self.authField : self.ct0Field)];
    if (indexPath.section == 0) {
        UITextField *f = @[ self.userField, self.passField, self.emailField, self.totpField ][(NSUInteger)indexPath.row];
        return [self fieldCell:tableView field:f];
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[CHTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = L(@"I understand and agree");
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [[CHTheme shared] bodyFont];
    cell.accessoryView = self.consentSwitch;
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return NO; }

#pragma mark - Log in

- (void)logIn
{
    if (self.working) return;
    [self.view endEditing:YES];
    if (![CHTwitter configured]) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Set the server address in Settings first.")]; return; }

    if (self.mode == CHLoginCookies) {
        NSString *auth = [self trim:self.authField.text], *ct0 = [self trim:self.ct0Field.text];
        if (!auth.length || !ct0.length) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Paste both auth_token and ct0.")]; return; }
        NSString *prevA = [CHSettings xAuthToken], *prevC = [CHSettings xCSRF];
        [CHSettings setXAuthToken:auth];
        [CHSettings setXCSRF:ct0];
        [self validateThen:^{ } onFail:^{ [CHSettings setXAuthToken:prevA]; [CHSettings setXCSRF:prevC]; }
               failMessage:L(@"Those cookies did not work. Check you copied auth_token and ct0 from x.com while signed in.")];
        return;
    }

    NSString *u = [self trim:self.userField.text], *p = self.passField.text ?: @"";
    if (!u.length || !p.length) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Enter your username and password.")]; return; }
    if (!self.consentSwitch.on) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Please agree to the note below the form first, or use the Cookies tab.")]; return; }
    [self begin];
    [CHTwitter logInWithUsername:u password:p email:[self trim:self.emailField.text] totp:[self trim:self.totpField.text] completion:^(CHUser *user, NSError *error) {
        [self end];
        if (user.handle.length) [self succeed];
        else [CHUtils alertWithTitle:L(@"Log in") message:error.localizedDescription ?: L(@"Those details did not work. Try the Cookies tab, which is more reliable.")];
    }];
}

- (void)validateThen:(dispatch_block_t)ok onFail:(dispatch_block_t)revert failMessage:(NSString *)msg
{
    [self begin];
    [CHTwitter fetchMe:^(CHUser *user, NSError *error) {
        [self end];
        if (user.handle.length) { if (ok) ok(); [self succeed]; }
        else { if (revert) revert(); [CHUtils alertWithTitle:L(@"Log in") message:error.localizedDescription ?: msg]; }
    }];
}

- (void)begin { self.working = YES; self.loginItem.enabled = NO; [UIApplication sharedApplication].networkActivityIndicatorVisible = YES; }
- (void)end { self.working = NO; self.loginItem.enabled = YES; [UIApplication sharedApplication].networkActivityIndicatorVisible = NO; }

- (void)succeed
{
    [CHSettings save];
    [[NSNotificationCenter defaultCenter] postNotificationName:CHSettingsDidChangeNotification object:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)trim:(NSString *)s { return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @""; }

@end

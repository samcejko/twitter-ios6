#import "CHLoginViewController.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

@interface CHLoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *authField;
@property (nonatomic, strong) UITextField *ct0Field;
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

    self.authField = [self field:@"auth_token" text:[CHSettings xAuthToken]];
    self.ct0Field = [self field:@"ct0" text:[CHSettings xCSRF]];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text
{
    UITextField *f = [[UITextField alloc] init];
    f.placeholder = placeholder;
    f.text = text;
    f.delegate = self;
    f.textColor = [[CHTheme shared] primaryTextColor];
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    return f;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return L(@"Your X cookies"); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return L(@"In a desktop browser signed in to x.com: open the developer tools → Application → Cookies → https://x.com, and copy the values of auth_token and ct0. They stay on this device and are sent with each request; nothing is stored on the server. On this device, a cookie-viewer tweak can read them too.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[CHTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UITextField *f = indexPath.row == 0 ? self.authField : self.ct0Field;
    f.frame = CGRectMake(16, 0, cell.contentView.bounds.size.width - 32, 44);
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:f];
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.authField) [self.ct0Field becomeFirstResponder]; else [self logIn];
    return NO;
}

- (void)logIn
{
    if (self.working) return;
    NSString *auth = [self.authField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *ct0 = [self.ct0Field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!auth.length || !ct0.length) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Paste both auth_token and ct0.")]; return; }
    if (![CHTwitter configured]) { [CHUtils alertWithTitle:L(@"Log in") message:L(@"Set the server address in Settings first.")]; return; }

    NSString *prevAuth = [CHSettings xAuthToken], *prevCt0 = [CHSettings xCSRF];
    [CHSettings setXAuthToken:auth];
    [CHSettings setXCSRF:ct0];
    self.working = YES;
    self.loginItem.enabled = NO;
    [[self.view viewWithTag:0] endEditing:YES];
    [self.view endEditing:YES];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [CHTwitter fetchMe:^(CHUser *user, NSError *error) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        self.working = NO;
        self.loginItem.enabled = YES;
        if (user.handle.length) {
            [CHSettings save];
            [[NSNotificationCenter defaultCenter] postNotificationName:CHSettingsDidChangeNotification object:nil];
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [CHSettings setXAuthToken:prevAuth];
            [CHSettings setXCSRF:prevCt0];
            [CHUtils alertWithTitle:L(@"Log in") message:error.localizedDescription ?: L(@"Those cookies did not work. Check you copied auth_token and ct0 from x.com while signed in.")];
        }
    }];
}

@end

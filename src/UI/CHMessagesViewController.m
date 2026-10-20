#import "CHMessagesViewController.h"
#import "CHConversationViewController.h"
#import "CHImageLoader.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#pragma mark - A conversation row

@interface CHConvoCell : UITableViewCell
@property (nonatomic, strong) CHImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *lastLabel;
- (void)setUser:(CHUser *)user last:(NSString *)last;
@end

@implementation CHConvoCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid
{
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        CHTheme *th = [CHTheme shared];
        self.backgroundColor = [th cardColor];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        _avatar = [[CHImageView alloc] init]; _avatar.contentMode = UIViewContentModeScaleAspectFill; _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = [th separatorColor];
        _nameLabel = [[UILabel alloc] init]; _nameLabel.font = [UIFont boldSystemFontOfSize:CHIsPad()?16:15]; _nameLabel.textColor = [th primaryTextColor]; _nameLabel.backgroundColor = [UIColor clearColor];
        _lastLabel = [[UILabel alloc] init]; _lastLabel.font = [th smallFont]; _lastLabel.textColor = [th secondaryTextColor]; _lastLabel.backgroundColor = [UIColor clearColor]; _lastLabel.numberOfLines = 1;
        for (UIView *v in @[ _avatar, _nameLabel, _lastLabel ]) [self.contentView addSubview:v];
    }
    return self;
}
- (void)setUser:(CHUser *)user last:(NSString *)last
{
    _avatar.maxPixels = 96;
    [_avatar setImageURL:user.avatarURL placeholder:[[CHTheme shared] avatarPlaceholderWithSize:48]];
    _nameLabel.text = [CHUtils displayText:user.name.length ? user.name : user.handle];
    _lastLabel.text = last.length ? [CHUtils displayText:last] : [@"@" stringByAppendingString:user.handle ?: @""];
    [self setNeedsLayout];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat pad = 12, av = 48;
    _avatar.frame = CGRectMake(pad, 8, av, av); _avatar.layer.cornerRadius = av/2;
    CGFloat x = pad + av + 10, w = self.contentView.bounds.size.width - x - pad;
    _nameLabel.frame = CGRectMake(x, 14, w, 20);
    _lastLabel.frame = CGRectMake(x, 36, w, 18);
}
@end

#pragma mark - Screen

@interface CHMessagesViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableArray *convos;   // NSDictionary {user,last,time}
@end

@implementation CHMessagesViewController

- (instancetype)init { if ((self = [super init])) { _convos = [NSMutableArray array]; self.title = L(@"Messages"); } return self; }

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th backgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self; self.tableView.rowHeight = 64;
    [th applyToTableView:self.tableView];
    [self.view addSubview:self.tableView];
    self.status = [[UILabel alloc] init];
    self.status.textAlignment = UITextAlignmentCenter; self.status.numberOfLines = 0;
    self.status.textColor = [th secondaryTextColor]; self.status.font = [th bodyFont]; self.status.hidden = YES;
    [self.view addSubview:self.status];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newMessage)];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self load]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.status.frame = CGRectInset(self.view.bounds, 28, 0); }

- (void)load
{
    if (![CHTwitter configured]) { self.status.text = L(@"Set the server address in Settings first."); self.status.hidden = NO; return; }
    [CHTwitter dmConversations:^(NSArray *items, BOOL supported, NSError *error) {
        [self.convos setArray:items ?: @[]];
        [self.tableView reloadData];
        if (!self.convos.count) {
            self.status.text = supported ? L(@"No conversations yet. Tap the compose button to start one.")
                                          : L(@"Open a conversation from someone's profile, or tap the compose button to message a @handle.");
            self.status.hidden = NO;
        } else self.status.hidden = YES;
    }];
}

- (void)newMessage
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"New message") message:L(@"Who do you want to message?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Open"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *f = [a textFieldAtIndex:0];
    f.placeholder = @"@handle";
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *h = [[[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByReplacingOccurrencesOfString:@"@" withString:@""];
    if (h.length) [self.navigationController pushViewController:[[CHConversationViewController alloc] initWithHandle:h userId:nil name:nil] animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.convos.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHConvoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[CHConvoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    NSDictionary *d = [self.convos objectAtIndex:(NSUInteger)indexPath.row];
    [cell setUser:[d objectForKey:@"user"] last:[d objectForKey:@"last"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CHUser *u = [[self.convos objectAtIndex:(NSUInteger)indexPath.row] objectForKey:@"user"];
    [self.navigationController pushViewController:[[CHConversationViewController alloc] initWithHandle:u.handle userId:u.userId name:u.name] animated:YES];
}

@end

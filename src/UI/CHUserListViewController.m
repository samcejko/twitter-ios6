#import "CHUserListViewController.h"
#import "CHUserCell.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHCommon.h"

@interface CHUserListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic) BOOL following;
@property (nonatomic, strong) NSMutableArray *users;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic) BOOL more;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIView *footerSpinner;
@end

@implementation CHUserListViewController

- (instancetype)initWithHandle:(NSString *)handle userId:(NSString *)userId following:(BOOL)following
{
    if ((self = [super init])) {
        _handle = handle; _userId = userId; _following = following;
        _users = [NSMutableArray array]; _more = YES;
        self.title = following ? L(@"Following") : L(@"Followers");
    }
    return self;
}

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th backgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = [CHUserCell height];
    [th applyToTableView:self.tableView];
    [self.view addSubview:self.tableView];
    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = [th secondaryTextColor];
    self.status.font = [th bodyFont];
    self.status.hidden = YES;
    [self.view addSubview:self.status];
    UIActivityIndicatorView *s = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[th spinnerStyle]];
    s.frame = CGRectMake(0, 0, 320, 44); [s startAnimating];
    self.footerSpinner = s;
}

- (void)viewDidLoad { [super viewDidLoad]; [self load:NO]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.status.frame = CGRectInset(self.view.bounds, 28, 0); }

- (void)load:(BOOL)more
{
    if (self.loading || (more && (!self.more || !self.cursor.length))) return;
    self.loading = YES;
    self.tableView.tableFooterView = more ? self.footerSpinner : nil;
    [CHTwitter followersOf:self.handle userId:self.userId following:self.following cursor:(more ? self.cursor : nil)
                completion:^(CHTweetPage *page, NSError *error) {
        self.loading = NO;
        self.tableView.tableFooterView = nil;
        if (page) {
            if (!more) [self.users removeAllObjects];
            NSMutableArray *ids = [NSMutableArray array];
            for (CHUser *u in self.users) if (u.userId) [ids addObject:u.userId];
            for (CHUser *u in page.users) if (!u.userId.length || ![ids containsObject:u.userId]) [self.users addObject:u];
            self.cursor = page.bottomCursor;
            self.more = page.hasMore;
            [self.tableView reloadData];
        }
        if (!self.users.count) { self.status.text = error.localizedDescription ?: L(@"Nothing to show."); self.status.hidden = NO; }
        else self.status.hidden = YES;
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.users.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHUserCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user"];
    if (!cell) cell = [[CHUserCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"user"];
    [cell setUser:self.users[(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [CHLinkRouter openProfile:[(CHUser *)self.users[(NSUInteger)indexPath.row] handle]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= (NSInteger)self.users.count - 3) [self load:YES];
}

@end

#import "CHTweetListViewController.h"
#import "CHTweetDetailViewController.h"
#import "CHMediaViewController.h"
#import "CHSettingsViewController.h"
#import "CHTweetActions.h"
#import "CHLinkRouter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

static NSString * const CHCellId = @"tweet";

@interface CHTweetListViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *footerSpinner;
@property (nonatomic, strong) UILabel *statusLabel;        // empty / error
@property (nonatomic, copy) NSString *bottomCursor;
@property (nonatomic) BOOL hasMore;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL loadedOnce;
@end

@implementation CHTweetListViewController

- (instancetype)init
{
    if ((self = [super init])) { _tweets = [NSMutableArray array]; _hasMore = YES; }
    return self;
}

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th backgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 120;
    [th applyToTableView:_tableView];
    [self.view addSubview:_tableView];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = UITextAlignmentCenter;
    _statusLabel.font = [th bodyFont];
    _statusLabel.textColor = [th secondaryTextColor];
    _statusLabel.hidden = YES;
    [self.view addSubview:_statusLabel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[CHTheme shared] spinnerStyle]];
    spin.frame = CGRectMake(0, 0, 320, 44);
    [spin startAnimating];
    self.footerSpinner = spin;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:CHThemeDidChangeNotification object:nil];

    if (!self.loadedOnce) [self reload];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.statusLabel.frame = CGRectInset(self.view.bounds, 28, 0);
}

- (void)themeChanged
{
    CHTheme *th = [CHTheme shared];
    self.view.backgroundColor = [th backgroundColor];
    [th applyToTableView:self.tableView];
    self.statusLabel.textColor = [th secondaryTextColor];
    [self.tableView reloadData];
}

#pragma mark - Loading

- (void)reload
{
    if (self.loading && !self.refreshControl.refreshing) return;
    self.loading = YES;
    self.loadedOnce = YES;
    [self showStatus:nil];
    __weak typeof(self) weakSelf = self;
    [self fetchWithCursor:nil completion:^(CHTweetPage *page, NSError *error) {
        typeof(self) self = weakSelf; if (!self) return;
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (error && !page) {
            if (!self.tweets.count) [self showStatus:error.localizedDescription ?: L(@"Could not load.")];
            return;
        }
        self.tweets = [page.tweets mutableCopy] ?: [NSMutableArray array];
        self.bottomCursor = page.bottomCursor;
        self.hasMore = page.hasMore;
        [self.tableView reloadData];
        [self updateFooter];
        if (!self.tweets.count) [self showStatus:self.emptyMessage ?: L(@"Nothing to show.")];
    }];
}

- (void)loadMore
{
    if (self.loading || !self.hasMore || !self.bottomCursor.length) return;
    self.loading = YES;
    [self updateFooter];
    __weak typeof(self) weakSelf = self;
    NSString *cursor = self.bottomCursor;
    [self fetchWithCursor:cursor completion:^(CHTweetPage *page, NSError *error) {
        typeof(self) self = weakSelf; if (!self) return;
        self.loading = NO;
        if (!error && page) {
            NSMutableArray *existing = [NSMutableArray array];
            for (CHTweet *t in self.tweets) if (t.tweetId) [existing addObject:t.tweetId];
            NSMutableArray *added = [NSMutableArray array];
            for (CHTweet *t in page.tweets) if (t.tweetId && ![existing containsObject:t.tweetId]) [added addObject:t];
            if (added.count) {
                NSMutableArray *ips = [NSMutableArray array];
                for (NSUInteger i = 0; i < added.count; i++) [ips addObject:[NSIndexPath indexPathForRow:(NSInteger)(self.tweets.count + i) inSection:0]];
                [self.tweets addObjectsFromArray:added];
                [self.tableView insertRowsAtIndexPaths:ips withRowAnimation:UITableViewRowAnimationNone];
            }
            self.bottomCursor = page.bottomCursor;
            self.hasMore = page.hasMore;
        } else {
            self.hasMore = NO;   // stop hammering a failing cursor; a pull-to-refresh retries
        }
        [self updateFooter];
    }];
}

- (void)setTweetsAndReloadTable:(NSArray *)tweets
{
    self.loadedOnce = YES;
    self.tweets = [tweets mutableCopy] ?: [NSMutableArray array];
    self.hasMore = NO;
    self.bottomCursor = nil;
    [self.tableView reloadData];
    [self updateFooter];
    [self showStatus:self.tweets.count ? nil : (self.emptyMessage ?: L(@"Nothing to show."))];
}

- (void)showStatus:(NSString *)message
{
    self.statusLabel.text = message;
    self.statusLabel.hidden = message == nil;
}

- (void)updateFooter
{
    self.tableView.tableFooterView = (self.hasMore && self.tweets.count) ? self.footerSpinner : [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)fetchWithCursor:(NSString *)cursor completion:(void (^)(CHTweetPage *, NSError *))completion
{
    // abstract; subclasses override
    if (completion) completion(nil, CHMakeError(CHErrorAPI, @"not implemented"));
}

#pragma mark - Settings

- (void)installSettingsButton
{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Settings") style:UIBarButtonItemStyleBordered target:self action:@selector(openSettings)];
}

- (void)openSettings
{
    CHSettingsViewController *settings = [[CHSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    [[CHTheme shared] applyToNavigationBar:nav.navigationBar];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.tweets.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHTweetCell *cell = [tableView dequeueReusableCellWithIdentifier:CHCellId];
    if (!cell) cell = [[CHTweetCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CHCellId];
    CHTweet *tweet = [self.tweets objectAtIndex:(NSUInteger)indexPath.row];
    cell.delegate = self;
    [cell setTweet:tweet];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHTweet *tweet = [self.tweets objectAtIndex:(NSUInteger)indexPath.row];
    return [CHTweetCell heightForTweet:tweet width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [CHLinkRouter openTweet:[self.tweets objectAtIndex:(NSUInteger)indexPath.row]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= (NSInteger)self.tweets.count - 3) [self loadMore];
}

#pragma mark - CHTweetCellDelegate

- (void)tweetCell:(CHTweetCell *)cell didTapUser:(CHUser *)user
{
    if (user.handle.length) [CHLinkRouter openProfile:user.handle];
}

- (void)tweetCell:(CHTweetCell *)cell didTapQuoted:(CHTweet *)quoted
{
    [CHLinkRouter openTweet:quoted];
}

- (void)tweetCell:(CHTweetCell *)cell didTapMediaAtIndex:(NSInteger)index
{
    if (!cell.tweet.media.count) return;
    CHMediaViewController *viewer = [[CHMediaViewController alloc] initWithMedia:cell.tweet.media startIndex:index];
    viewer.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)tweetCell:(CHTweetCell *)cell didTapAction:(NSString *)action
{
    [CHTweetActions handleAction:action tweet:cell.tweet cell:cell from:self];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end

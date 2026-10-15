#import "CHTweetDetailViewController.h"
#import "CHTweetCell.h"
#import "CHMediaViewController.h"
#import "CHTweetActions.h"
#import "CHComposeViewController.h"
#import "CHExternalOpen.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHCommon.h"

@interface CHTweetDetailViewController () <UITableViewDataSource, UITableViewDelegate, CHTweetCellDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *footerSpinner;
@property (nonatomic, copy) NSString *tweetId;
@property (nonatomic, strong) CHTweet *tweet;        // focal
@property (nonatomic, strong) NSMutableArray *ancestors;
@property (nonatomic, strong) NSMutableArray *replies;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic) BOOL more;
@property (nonatomic) BOOL loading;
@end

@implementation CHTweetDetailViewController

- (instancetype)initWithTweet:(CHTweet *)tweet
{
    if ((self = [super init])) {
        _tweet = tweet;
        _tweetId = tweet.tweetId;
        _ancestors = [NSMutableArray array];
        _replies = [NSMutableArray array];
        self.title = L(@"Tweet");
    }
    return self;
}

- (instancetype)initWithTweetId:(NSString *)tweetId
{
    if ((self = [super init])) {
        _tweetId = tweetId;
        _ancestors = [NSMutableArray array];
        _replies = [NSMutableArray array];
        self.title = L(@"Tweet");
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
    [th applyToTableView:self.tableView];
    [self.view addSubview:self.tableView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Share") style:UIBarButtonItemStyleBordered target:self action:@selector(share)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadThread) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[CHTheme shared] spinnerStyle]];
    spin.frame = CGRectMake(0, 0, 320, 44);
    [spin startAnimating];
    self.footerSpinner = spin;
    [self loadThread];
}

- (void)share
{
    NSString *url = self.tweet.shareURL;
    if (!url.length && self.tweetId.length) url = [NSString stringWithFormat:@"https://twitter.com/i/status/%@", self.tweetId];
    if (url.length) [CHExternalOpen presentShareSheetForURL:[NSURL URLWithString:url] from:self anchor:nil];
}

- (void)loadThread
{
    if (self.loading) return;
    self.loading = YES;
    [CHTwitter threadForTweet:self.tweetId cursor:nil completion:^(CHThread *thread, NSError *error) {
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (thread.tweet) {
            self.tweet = thread.tweet;
            self.ancestors = [thread.ancestors mutableCopy] ?: [NSMutableArray array];
            self.replies = [thread.replies mutableCopy] ?: [NSMutableArray array];
            self.cursor = thread.cursor;
            self.more = thread.hasMore;
        } else if (error && !self.tweet) {
            [[[UIAlertView alloc] initWithTitle:L(@"Tweet") message:error.localizedDescription ?: L(@"This tweet could not be loaded.") delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
        }
        [self.tableView reloadData];
        [self updateFooter];
    }];
}

- (void)loadMoreReplies
{
    if (self.loading || !self.more || !self.cursor.length) return;
    self.loading = YES;
    [self updateFooter];
    [CHTwitter threadForTweet:self.tweetId cursor:self.cursor completion:^(CHThread *thread, NSError *error) {
        self.loading = NO;
        if (!error && thread) {
            NSMutableArray *ids = [NSMutableArray array];
            for (CHTweet *t in self.replies) if (t.tweetId) [ids addObject:t.tweetId];
            for (CHTweet *t in thread.replies) if (t.tweetId && ![ids containsObject:t.tweetId]) [self.replies addObject:t];
            self.cursor = thread.cursor;
            self.more = thread.hasMore;
        } else {
            self.more = NO;
        }
        [self.tableView reloadData];
        [self updateFooter];
    }];
}

- (void)updateFooter
{
    self.tableView.tableFooterView = (self.more && self.replies.count) ? self.footerSpinner : [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return (NSInteger)self.ancestors.count;
    if (section == 1) return self.tweet ? 1 : 0;
    return (NSInteger)self.replies.count;
}

- (CHTweet *)tweetAt:(NSIndexPath *)ip
{
    if (ip.section == 0) return self.ancestors[(NSUInteger)ip.row];
    if (ip.section == 1) return self.tweet;
    return self.replies[(NSUInteger)ip.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL focal = indexPath.section == 1;
    NSString *rid = focal ? @"focal" : @"tweet";
    CHTweetCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
    if (!cell) { cell = [[CHTweetCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid]; cell.expanded = focal; }
    CHTweet *tweet = [self tweetAt:indexPath];
    cell.delegate = self;
    [cell setTweet:tweet];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [CHTweetCell heightForTweet:[self tweetAt:indexPath] width:tableView.bounds.size.width expanded:(indexPath.section == 1)];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) [CHLinkRouter openTweet:[self tweetAt:indexPath]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 2 && indexPath.row >= (NSInteger)self.replies.count - 3) [self loadMoreReplies];
}

#pragma mark - CHTweetCellDelegate

- (void)tweetCell:(CHTweetCell *)cell didTapUser:(CHUser *)user { if (user.handle.length) [CHLinkRouter openProfile:user.handle]; }
- (void)tweetCell:(CHTweetCell *)cell didTapQuoted:(CHTweet *)quoted { [CHLinkRouter openTweet:quoted]; }

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

@end

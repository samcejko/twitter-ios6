#import "CHSearchViewController.h"
#import "CHUserCell.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

typedef enum { CHSearchModeTrends, CHSearchModeTweets, CHSearchModePeople } CHSearchMode;

#pragma mark - Search

@interface CHSearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *kindSwitch;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) CHSearchMode mode;
@property (nonatomic, strong) NSMutableArray *users;     // CHUser
@property (nonatomic, strong) NSMutableArray *trends;    // CHTrend
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic) BOOL more;
@property (nonatomic) BOOL busy;
@end

@implementation CHSearchViewController

- (instancetype)initWithQuery:(NSString *)query
{
    if ((self = [super init])) {
        _query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _users = [NSMutableArray array];
        _trends = [NSMutableArray array];
        _mode = _query.length ? CHSearchModeTweets : CHSearchModeTrends;
        self.title = L(@"Explore");
    }
    return self;
}

- (void)viewDidLoad
{
    // build the bar UI before -[super viewDidLoad] runs the first reload (which uses the kind switch)
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 260, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = L(@"Search Twitter");
    self.searchBar.text = self.query;
    [[CHTheme shared] applyToSearchBar:self.searchBar];
    self.navigationItem.titleView = self.searchBar;

    self.kindSwitch = [[UISegmentedControl alloc] initWithItems:@[ L(@"Top"), L(@"Latest"), L(@"People") ]];
    self.kindSwitch.selectedSegmentIndex = 0;
    [self.kindSwitch addTarget:self action:@selector(switchKind:) forControlEvents:UIControlEventValueChanged];

    [super viewDidLoad];
    [self installSettingsButton];
}

- (void)updateHeader
{
    if (self.mode == CHSearchModeTrends) { self.tableView.tableHeaderView = nil; return; }
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 42)];
    wrap.backgroundColor = [[CHTheme shared] backgroundColor];
    self.kindSwitch.frame = CGRectMake(10, 6, wrap.bounds.size.width - 20, 30);
    self.kindSwitch.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [wrap addSubview:self.kindSwitch];
    self.tableView.tableHeaderView = wrap;
}

#pragma mark - Search bar

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    [self searchFor:searchBar.text];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)searchFor:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) { self.query = @""; self.mode = CHSearchModeTrends; self.searchBar.text = @""; [self reload]; return; }
    [CHSettings addSearch:q];
    [CHSettings save];
    self.query = q;
    self.searchBar.text = q;
    self.mode = self.kindSwitch.selectedSegmentIndex == 2 ? CHSearchModePeople : CHSearchModeTweets;
    [self reload];
}

- (void)switchKind:(UISegmentedControl *)sender
{
    if (!self.query.length) return;
    self.mode = sender.selectedSegmentIndex == 2 ? CHSearchModePeople : CHSearchModeTweets;
    [self reload];
}

- (NSString *)currentKind
{
    switch (self.kindSwitch.selectedSegmentIndex) { case 1: return @"latest"; case 2: return @"people"; default: return @"top"; }
}

#pragma mark - Loading (search manages its own state; it does not use the base's fetch)

- (void)reload
{
    [self.refreshControl endRefreshing];
    [self.tweets removeAllObjects];
    [self.users removeAllObjects];
    [self.trends removeAllObjects];
    self.cursor = nil;
    self.more = YES;
    [self updateHeader];
    [self showStatus:nil];
    [self.tableView reloadData];

    if (self.mode == CHSearchModeTrends) { [self loadTrends]; return; }
    [self loadResultsAppending:NO];
}

- (void)loadTrends
{
    if (![CHTwitter configured]) { [self showStatus:L(@"Set the server address in Settings first.")]; return; }
    self.busy = YES;
    [CHTwitter trends:^(NSArray *trends, NSError *error) {
        self.busy = NO;
        [self.trends setArray:trends ?: @[]];
        [self.tableView reloadData];
        if (!self.trends.count && [CHSettings searchHistory].count == 0)
            [self showStatus:error.localizedDescription ?: L(@"Search Twitter for tweets, people and hashtags.")];
        else [self showStatus:nil];
    }];
}

- (void)loadResultsAppending:(BOOL)appending
{
    if (self.busy || (appending && (!self.more || !self.cursor.length))) return;
    if (![CHTwitter configured]) { [self showStatus:L(@"Set the server address in Settings first.")]; return; }
    self.busy = YES;
    NSString *cursor = appending ? self.cursor : nil;
    [CHTwitter search:self.query kind:[self currentKind] cursor:cursor completion:^(CHTweetPage *page, NSError *error) {
        self.busy = NO;
        if (error && !page) { if (![self resultCount]) [self showStatus:error.localizedDescription]; return; }
        if (self.mode == CHSearchModePeople) {
            if (!appending) [self.users removeAllObjects];
            [self.users addObjectsFromArray:page.users];
        } else {
            if (!appending) [self.tweets removeAllObjects];
            [self.tweets addObjectsFromArray:page.tweets];
        }
        self.cursor = page.bottomCursor;
        self.more = page.hasMore;
        [self.tableView reloadData];
        [self showStatus:[self resultCount] ? nil : L(@"Nothing found.")];
    }];
}

- (NSUInteger)resultCount { return self.mode == CHSearchModePeople ? self.users.count : self.tweets.count; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.mode == CHSearchModeTrends) return section == 0 ? (NSInteger)[CHSettings searchHistory].count : (NSInteger)self.trends.count;
    if (self.mode == CHSearchModePeople) return (NSInteger)self.users.count;
    return (NSInteger)self.tweets.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.mode == CHSearchModeTrends ? 2 : 1; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.mode != CHSearchModeTrends) return nil;
    if (section == 0) return [CHSettings searchHistory].count ? L(@"Recent searches") : nil;
    return self.trends.count ? L(@"Trends") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHTheme *th = [CHTheme shared];
    if (self.mode == CHSearchModeTweets) return [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if (self.mode == CHSearchModePeople) {
        CHUserCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user"];
        if (!cell) cell = [[CHUserCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"user"];
        [cell setUser:[self.users objectAtIndex:(NSUInteger)indexPath.row]];
        return cell;
    }
    // trends mode: recent searches + trends
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"plain"];
    [th styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 0) {
        cell.textLabel.text = [[CHSettings searchHistory] objectAtIndex:(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = nil;
    } else {
        CHTrend *t = [self.trends objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = t.name;
        NSMutableArray *bits = [NSMutableArray array];
        if (t.context.length) [bits addObject:t.context];
        if (t.volume > 0) [bits addObject:[NSString stringWithFormat:L(@"%@ posts"), [CHUtils formatBigCount:t.volume]]];
        cell.detailTextLabel.text = [bits componentsJoinedByString:@" · "];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.mode == CHSearchModeTweets) return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    if (self.mode == CHSearchModePeople) return [CHUserCell height];
    return indexPath.section == 0 ? 44 : 58;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.mode == CHSearchModeTweets) { [CHLinkRouter openTweet:[self.tweets objectAtIndex:(NSUInteger)indexPath.row]]; return; }
    if (self.mode == CHSearchModePeople) { [CHLinkRouter openProfile:[(CHUser *)[self.users objectAtIndex:(NSUInteger)indexPath.row] handle]]; return; }
    if (indexPath.section == 0) [self searchFor:[[CHSettings searchHistory] objectAtIndex:(NSUInteger)indexPath.row]];
    else [self searchFor:[(CHTrend *)[self.trends objectAtIndex:(NSUInteger)indexPath.row] query]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.mode == CHSearchModeTrends) return;
    if (indexPath.row >= (NSInteger)[self resultCount] - 3) [self loadResultsAppending:YES];
}

@end

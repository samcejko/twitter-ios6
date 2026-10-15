#import "CHSearchViewController.h"
#import "CHImageLoader.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

typedef enum { CHSearchModeTrends, CHSearchModeTweets, CHSearchModePeople } CHSearchMode;

#pragma mark - A person row (People results, search history is plain)

@interface CHUserRow : UITableViewCell
@property (nonatomic, strong) CHImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *bioLabel;
- (void)setUser:(CHUser *)user;
@end

@implementation CHUserRow
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid
{
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        CHTheme *th = [CHTheme shared];
        self.backgroundColor = [th cardColor];
        _avatar = [[CHImageView alloc] init];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = [th separatorColor];
        _nameLabel = [self lbl:[UIFont boldSystemFontOfSize:CHIsPad() ? 16 : 15] color:[th primaryTextColor]];
        _handleLabel = [self lbl:[th smallFont] color:[th secondaryTextColor]];
        _bioLabel = [self lbl:[th smallFont] color:[th secondaryTextColor]];
        _bioLabel.numberOfLines = 2;
        for (UIView *v in @[ _avatar, _nameLabel, _handleLabel, _bioLabel ]) [self.contentView addSubview:v];
    }
    return self;
}
- (UILabel *)lbl:(UIFont *)f color:(UIColor *)c { UILabel *l = [[UILabel alloc] init]; l.font = f; l.textColor = c; l.backgroundColor = [UIColor clearColor]; return l; }
- (void)setUser:(CHUser *)user
{
    CHTheme *th = [CHTheme shared];
    _avatar.maxPixels = 96;
    [_avatar setImageURL:user.avatarURL placeholder:[th avatarPlaceholderWithSize:44]];
    _nameLabel.text = [CHUtils displayText:user.name.length ? user.name : user.handle];
    _handleLabel.text = [@"@" stringByAppendingString:user.handle ?: @""];
    _bioLabel.text = [CHUtils displayText:user.bio ?: @""];
    [self setNeedsLayout];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat pad = 12, av = 44;
    _avatar.frame = CGRectMake(pad, 10, av, av);
    _avatar.layer.cornerRadius = av / 2;
    CGFloat x = pad + av + 10, w = self.contentView.bounds.size.width - x - pad;
    _nameLabel.frame = CGRectMake(x, 9, w, 18);
    _handleLabel.frame = CGRectMake(x, 27, w, 16);
    _bioLabel.frame = CGRectMake(x, 44, w, 30);
}
@end

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
        CHUserRow *cell = [tableView dequeueReusableCellWithIdentifier:@"user"];
        if (!cell) cell = [[CHUserRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"user"];
        [cell setUser:self.users[(NSUInteger)indexPath.row]];
        return cell;
    }
    // trends mode: recent searches + trends
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"plain"];
    [th styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 0) {
        cell.textLabel.text = [CHSettings searchHistory][(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = nil;
    } else {
        CHTrend *t = self.trends[(NSUInteger)indexPath.row];
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
    if (self.mode == CHSearchModePeople) return 84;
    return indexPath.section == 0 ? 44 : 58;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.mode == CHSearchModeTweets) { [CHLinkRouter openTweet:self.tweets[(NSUInteger)indexPath.row]]; return; }
    if (self.mode == CHSearchModePeople) { [CHLinkRouter openProfile:[(CHUser *)self.users[(NSUInteger)indexPath.row] handle]]; return; }
    if (indexPath.section == 0) [self searchFor:[CHSettings searchHistory][(NSUInteger)indexPath.row]];
    else [self searchFor:[(CHTrend *)self.trends[(NSUInteger)indexPath.row] query]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.mode == CHSearchModeTrends) return;
    if (indexPath.row >= (NSInteger)[self resultCount] - 3) [self loadResultsAppending:YES];
}

@end

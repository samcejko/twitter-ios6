#import "CHNotificationsViewController.h"
#import "CHImageLoader.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#pragma mark - A notification row

@interface CHNotificationCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) CHImageView *avatar;
@property (nonatomic, strong) UILabel *textLabel2;
@property (nonatomic, strong) UILabel *timeLabel;
- (void)setNotification:(CHNotification *)n;
+ (CGFloat)heightFor:(CHNotification *)n width:(CGFloat)width;
@end

static UIImage *CHNotifIcon(NSString *type)
{
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = type ?: @"";
    UIImage *img = cache[key];
    if (img) return img;
    UIColor *color = [UIColor colorWithRed:0.4 green:0.55 blue:0.95 alpha:1];
    if ([type rangeOfString:@"heart"].location != NSNotFound) color = [UIColor colorWithRed:0.95 green:0.09 blue:0.46 alpha:1];
    else if ([type rangeOfString:@"retweet"].location != NSNotFound) color = [UIColor colorWithRed:0.0 green:0.72 blue:0.49 alpha:1];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 22), NO, 0);
    [color setFill]; [color setStroke];
    if ([type rangeOfString:@"heart"].location != NSNotFound) {
        UIBezierPath *h = [UIBezierPath bezierPath];
        [h moveToPoint:CGPointMake(11, 19)];
        [h addCurveToPoint:CGPointMake(3, 8.5) controlPoint1:CGPointMake(5.5, 14.5) controlPoint2:CGPointMake(3, 11.5)];
        [h addArcWithCenter:CGPointMake(6.4, 7.8) radius:3.4 startAngle:M_PI endAngle:0 clockwise:YES];
        [h addArcWithCenter:CGPointMake(13.2, 7.8) radius:3.4 startAngle:M_PI endAngle:0 clockwise:YES];
        [h addCurveToPoint:CGPointMake(11, 19) controlPoint1:CGPointMake(19, 11.5) controlPoint2:CGPointMake(16.5, 14.5)];
        [h closePath]; [h fill];
    } else if ([type rangeOfString:@"retweet"].location != NSNotFound) {
        UIBezierPath *p = [UIBezierPath bezierPath]; p.lineWidth = 2; p.lineCapStyle = kCGLineCapRound; p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(6, 8)]; [p addLineToPoint:CGPointMake(16, 8)]; [p addLineToPoint:CGPointMake(16, 14)];
        [p moveToPoint:CGPointMake(16, 15)]; [p addLineToPoint:CGPointMake(6, 15)]; [p addLineToPoint:CGPointMake(6, 9)];
        [p stroke];
        UIBezierPath *a = [UIBezierPath bezierPath]; [a moveToPoint:CGPointMake(3, 11)]; [a addLineToPoint:CGPointMake(6, 7)]; [a addLineToPoint:CGPointMake(9, 11)]; [a closePath]; [a fill];
        UIBezierPath *b = [UIBezierPath bezierPath]; [b moveToPoint:CGPointMake(13, 12)]; [b addLineToPoint:CGPointMake(16, 16)]; [b addLineToPoint:CGPointMake(19, 12)]; [b closePath]; [b fill];
    } else {
        // a person / bird: a filled dot head + body
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(8, 3, 6, 6)] fill];
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(5, 10, 12, 9) cornerRadius:5]; [body fill];
    }
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

@implementation CHNotificationCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid
{
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        CHTheme *th = [CHTheme shared];
        self.backgroundColor = [th cardColor];
        _iconView = [[UIImageView alloc] init];
        _avatar = [[CHImageView alloc] init];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = [th separatorColor];
        _textLabel2 = [[UILabel alloc] init];
        _textLabel2.numberOfLines = 0;
        _textLabel2.font = [th bodyFont];
        _textLabel2.textColor = [th primaryTextColor];
        _textLabel2.backgroundColor = [UIColor clearColor];
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [th smallFont];
        _timeLabel.textColor = [th secondaryTextColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.backgroundColor = [UIColor clearColor];
        for (UIView *v in @[ _iconView, _avatar, _textLabel2, _timeLabel ]) [self.contentView addSubview:v];
    }
    return self;
}

- (void)setNotification:(CHNotification *)n
{
    self.iconView.image = CHNotifIcon(n.iconType);
    CHUser *first = n.users.firstObject;
    self.avatar.maxPixels = 72;
    if (first.avatarURL.length) { self.avatar.hidden = NO; [self.avatar setImageURL:first.avatarURL placeholder:[[CHTheme shared] avatarPlaceholderWithSize:34]]; }
    else self.avatar.hidden = YES;
    NSString *text = n.text;
    if (!text.length && n.tweet) text = [CHUtils truncate:[CHUtils displayText:n.tweet.text] to:120];
    self.textLabel2.text = [CHUtils displayText:text];
    self.timeLabel.text = n.createdAt > 0 ? [CHUtils formatRelativeDate:[NSDate dateWithTimeIntervalSince1970:n.createdAt]] : @"";
    [self setNeedsLayout];
}

+ (CGFloat)heightFor:(CHNotification *)n width:(CGFloat)width
{
    NSString *text = n.text.length ? n.text : (n.tweet ? [CHUtils truncate:[CHUtils displayText:n.tweet.text] to:120] : @"");
    CGFloat tw = width - 52 - 12;
    CGFloat h = [[CHUtils displayText:text] sizeWithFont:[[CHTheme shared] bodyFont] constrainedToSize:CGSizeMake(tw, 400) lineBreakMode:NSLineBreakByWordWrapping].height;
    return MAX(64, ceilf((float)h) + 46);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat pad = 12;
    self.iconView.frame = CGRectMake(pad, 12, 22, 22);
    CGFloat x = pad + 28;
    self.avatar.frame = CGRectMake(x, 10, 34, 34);
    self.avatar.layer.cornerRadius = 17;
    CGFloat tx = x, tw = self.contentView.bounds.size.width - tx - pad;
    self.timeLabel.frame = CGRectMake(self.contentView.bounds.size.width - pad - 60, 10, 60, 18);
    self.textLabel2.frame = CGRectMake(tx, self.avatar.hidden ? 10 : 48, tw, self.contentView.bounds.size.height - (self.avatar.hidden ? 10 : 48) - 8);
    if (self.avatar.hidden) self.textLabel2.frame = CGRectMake(tx, 10, tw, self.contentView.bounds.size.height - 18);
}

@end

#pragma mark - The screen

@interface CHNotificationsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *kindSwitch;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIView *footerSpinner;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic) BOOL more;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL loadedOnce;
@end

@implementation CHNotificationsViewController

- (instancetype)init { if ((self = [super init])) { _items = [NSMutableArray array]; _more = YES; self.title = L(@"Notifications"); } return self; }

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th backgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    [th applyToTableView:self.tableView];
    [self.view addSubview:self.tableView];
    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 0;
    self.status.textColor = [th secondaryTextColor]; self.status.font = [th bodyFont]; self.status.hidden = YES;
    [self.view addSubview:self.status];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.kindSwitch = [[UISegmentedControl alloc] initWithItems:@[ L(@"All"), L(@"Mentions") ]];
    self.kindSwitch.selectedSegmentIndex = 0;
    [self.kindSwitch addTarget:self action:@selector(switchKind) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.kindSwitch;
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];
    UIActivityIndicatorView *s = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[CHTheme shared] spinnerStyle]];
    s.frame = CGRectMake(0, 0, 320, 44); [s startAnimating]; self.footerSpinner = s;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (!self.loadedOnce) [self reload]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.status.frame = CGRectInset(self.view.bounds, 28, 0); }

- (NSString *)kind { return self.kindSwitch.selectedSegmentIndex == 1 ? @"mentions" : @"all"; }
- (void)switchKind { [self reload]; }

- (void)reload { [self load:NO]; }

- (void)load:(BOOL)more
{
    if (self.loading || (more && (!self.more || !self.cursor.length))) return;
    if (![CHTwitter configured]) { self.status.text = L(@"Set the server address in Settings first."); self.status.hidden = NO; [self.refresh endRefreshing]; return; }
    self.loading = YES; self.loadedOnce = YES;
    if (more) self.tableView.tableFooterView = self.footerSpinner;
    [CHTwitter notifications:[self kind] cursor:(more ? self.cursor : nil) completion:^(NSArray *items, NSString *cursor, BOOL hasMore, NSError *error) {
        self.loading = NO;
        [self.refresh endRefreshing];
        self.tableView.tableFooterView = nil;
        if (!error) {
            if (!more) [self.items removeAllObjects];
            [self.items addObjectsFromArray:items];
            self.cursor = cursor; self.more = hasMore;
            [self.tableView reloadData];
        }
        if (!self.items.count) { self.status.text = error.localizedDescription ?: L(@"No notifications yet."); self.status.hidden = NO; }
        else self.status.hidden = YES;
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHNotificationCell *cell = [tableView dequeueReusableCellWithIdentifier:@"notif"];
    if (!cell) cell = [[CHNotificationCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"notif"];
    [cell setNotification:self.items[(NSUInteger)indexPath.row]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [CHNotificationCell heightFor:self.items[(NSUInteger)indexPath.row] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CHNotification *n = self.items[(NSUInteger)indexPath.row];
    if (n.tweet.tweetId.length) [CHLinkRouter openTweet:n.tweet];
    else if (n.users.count == 1) [CHLinkRouter openProfile:[(CHUser *)n.users[0] handle]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= (NSInteger)self.items.count - 3) [self load:YES];
}

@end

#import "CHProfileViewController.h"
#import "CHUserListViewController.h"
#import "CHConversationViewController.h"
#import "CHImageLoader.h"
#import "CHExternalOpen.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

@interface CHProfileViewController ()
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, strong) CHUser *user;
@property (nonatomic, copy) NSArray *kinds;              // "tweets","replies","media","likes"
@property (nonatomic) NSInteger kindIndex;
// persistent header pieces
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) CHImageView *banner;
@property (nonatomic, strong) UIView *avatarRing;
@property (nonatomic, strong) CHImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verified;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *protectedLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *followingButton;
@property (nonatomic, strong) UIButton *followersButton;
@property (nonatomic, strong) UIButton *followButton;
@property (nonatomic, strong) UIButton *messageButton;
@property (nonatomic, strong) UISegmentedControl *segments;
@property (nonatomic) CGFloat headerWidth;
@property (nonatomic) BOOL isMe;
@end

@implementation CHProfileViewController

- (instancetype)initWithHandle:(NSString *)handle
{
    if ((self = [super init])) {
        _handle = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
        _kinds = @[ @"tweets", @"replies", @"media", @"likes" ];
        self.title = [@"@" stringByAppendingString:_handle ?: @""];
        self.emptyMessage = L(@"No tweets to show.");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Share") style:UIBarButtonItemStyleBordered target:self action:@selector(share)];
    [self buildHeaderPieces];
    [self loadUser];
}

- (void)share
{
    if (!self.handle.length) return;
    NSURL *url = [NSURL URLWithString:[@"https://twitter.com/" stringByAppendingString:self.handle]];
    [CHExternalOpen presentShareSheetForURL:url from:self anchor:nil];
}

#pragma mark - Header

- (void)buildHeaderPieces
{
    CHTheme *th = [CHTheme shared];
    self.header = [[UIView alloc] init];
    self.header.backgroundColor = [th cardColor];

    self.banner = [[CHImageView alloc] init];
    self.banner.contentMode = UIViewContentModeScaleAspectFill;
    self.banner.clipsToBounds = YES;
    self.banner.backgroundColor = th.isDark ? [UIColor colorWithWhite:0.18 alpha:1] : [UIColor colorWithRed:0.60 green:0.72 blue:0.86 alpha:1];

    self.avatarRing = [[UIView alloc] init];
    self.avatarRing.backgroundColor = [th cardColor];

    self.avatar = [[CHImageView alloc] init];
    self.avatar.contentMode = UIViewContentModeScaleAspectFill;
    self.avatar.clipsToBounds = YES;
    self.avatar.backgroundColor = [th separatorColor];

    self.nameLabel = [self label:[UIFont boldSystemFontOfSize:CHIsPad() ? 20 : 18] color:[th primaryTextColor]];
    self.verified = [[UIImageView alloc] init];
    self.handleLabel = [self label:[UIFont systemFontOfSize:CHIsPad() ? 16 : 15] color:[th secondaryTextColor]];
    self.protectedLabel = [self label:[UIFont systemFontOfSize:12] color:[th secondaryTextColor]];
    self.bioLabel = [self label:[th bodyFont] color:[th primaryTextColor]];
    self.bioLabel.numberOfLines = 0;
    self.metaLabel = [self label:[th smallFont] color:[th secondaryTextColor]];
    self.metaLabel.numberOfLines = 0;
    self.followingButton = [self countButton];
    self.followersButton = [self countButton];
    [self.followingButton addTarget:self action:@selector(openFollowing) forControlEvents:UIControlEventTouchUpInside];
    [self.followersButton addTarget:self action:@selector(openFollowers) forControlEvents:UIControlEventTouchUpInside];

    self.followButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.followButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.followButton.layer.cornerRadius = 15;
    self.followButton.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    [self.followButton addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];
    self.messageButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.messageButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.messageButton.layer.cornerRadius = 15;
    self.messageButton.layer.borderWidth = 1;
    self.messageButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [self.messageButton setTitle:L(@"Message") forState:UIControlStateNormal];
    [self.messageButton addTarget:self action:@selector(message) forControlEvents:UIControlEventTouchUpInside];
    self.followButton.hidden = self.messageButton.hidden = YES;

    self.segments = [[UISegmentedControl alloc] initWithItems:@[ L(@"Tweets"), L(@"Replies"), L(@"Media"), L(@"Likes") ]];
    self.segments.selectedSegmentIndex = 0;
    [self.segments addTarget:self action:@selector(switchKind:) forControlEvents:UIControlEventValueChanged];

    for (UIView *v in @[ self.banner, self.avatarRing, self.avatar, self.nameLabel, self.verified, self.handleLabel,
                         self.protectedLabel, self.bioLabel, self.metaLabel, self.followingButton, self.followersButton,
                         self.messageButton, self.followButton, self.segments ])
        [self.header addSubview:v];
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] init];
    l.font = font; l.textColor = color; l.backgroundColor = [UIColor clearColor];
    return l;
}

- (UIButton *)countButton
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [[CHTheme shared] smallFont];
    return b;
}

- (NSAttributedString *)countTitle:(long long)n word:(NSString *)word
{
    CHTheme *th = [CHTheme shared];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:[CHUtils formatBigCount:n]
        attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:[th smallFont].pointSize + 1], NSForegroundColorAttributeName: [th primaryTextColor] }];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:word]
        attributes:@{ NSFontAttributeName: [th smallFont], NSForegroundColorAttributeName: [th secondaryTextColor] }]];
    return s;
}

#pragma mark - Follow / message / counts

- (void)openFollowing { [CHLinkRouter push:[[CHUserListViewController alloc] initWithHandle:self.handle userId:self.user.userId following:YES]]; }
- (void)openFollowers { [CHLinkRouter push:[[CHUserListViewController alloc] initWithHandle:self.handle userId:self.user.userId following:NO]]; }

- (void)toggleFollow
{
    if (!self.user.userId.length) return;
    BOOL was = self.user.isFollowing;
    self.user.isFollowing = !was;
    [self styleFollowButton];
    [CHTwitter performAction:(was ? @"unfollow" : @"follow") onId:self.user.userId completion:^(BOOL ok, NSError *error) {
        if (!ok) { self.user.isFollowing = was; [self styleFollowButton]; [CHUtils alertWithTitle:L(@"Follow") message:error.localizedDescription ?: L(@"That did not work.")]; }
    }];
}

- (void)message
{
    [CHLinkRouter push:[[CHConversationViewController alloc] initWithHandle:self.handle userId:self.user.userId name:self.user.name]];
}

- (void)styleFollowButton
{
    CHTheme *th = [CHTheme shared];
    BOOL following = self.user.isFollowing;
    [self.followButton setTitle:(following ? L(@"Following") : L(@"Follow")) forState:UIControlStateNormal];
    self.followButton.backgroundColor = following ? [UIColor clearColor] : [th accentColor];
    self.followButton.layer.borderWidth = following ? 1 : 0;
    self.followButton.layer.borderColor = [th separatorColor].CGColor;
    [self.followButton setTitleColor:(following ? [th primaryTextColor] : [UIColor whiteColor]) forState:UIControlStateNormal];
    self.messageButton.layer.borderColor = [th separatorColor].CGColor;
    [self.messageButton setTitleColor:[th primaryTextColor] forState:UIControlStateNormal];
}

- (void)fillHeaderFromUser
{
    CHUser *u = self.user;
    [self.banner setImageURL:u.bannerURL placeholder:nil];
    [self.avatar setImageURL:u.avatarURL placeholder:[[CHTheme shared] avatarPlaceholderWithSize:64]];
    self.nameLabel.text = [CHUtils displayText:u.name.length ? u.name : (self.handle ?: @"")];
    self.verified.hidden = !u.verified;
    if (u.verified) self.verified.image = [self verifiedBadge];
    self.handleLabel.text = [@"@" stringByAppendingString:u.handle ?: self.handle ?: @""];
    self.protectedLabel.hidden = !u.isProtected;
    self.protectedLabel.text = u.isProtected ? L(@"Protected") : @"";
    self.bioLabel.text = [CHUtils displayText:u.bio ?: @""];

    NSMutableArray *meta = [NSMutableArray array];
    if (u.location.length) [meta addObject:[CHUtils displayText:u.location]];
    if (u.website.length) [meta addObject:[CHUtils linkTitle:u.website length:40]];
    if (u.joined > 0) {
        static NSDateFormatter *fmt;
        if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"MMMM yyyy"; }
        [meta addObject:[NSString stringWithFormat:L(@"Joined %@"), [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:u.joined]]]];
    }
    self.metaLabel.text = [meta componentsJoinedByString:@"   ·   "];

    [self.followingButton setAttributedTitle:[self countTitle:u.following word:L(@"Following")] forState:UIControlStateNormal];
    [self.followersButton setAttributedTitle:[self countTitle:u.followers word:L(@"Followers")] forState:UIControlStateNormal];
    NSString *me = [CHTwitter accountHandle];
    self.isMe = me.length && [self.handle caseInsensitiveCompare:me] == NSOrderedSame;
    self.followButton.hidden = self.messageButton.hidden = self.isMe;
    if (!self.isMe) [self styleFollowButton];

    self.headerWidth = 0;   // force relayout
    [self layoutHeaderForWidth:self.tableView.bounds.size.width];
}

- (CGFloat)layoutHeaderForWidth:(CGFloat)width
{
    if (width < 1) return 0;
    CGFloat pad = 12;
    CGFloat bannerH = roundf(width / 3);
    CGFloat avatar = CHIsPad() ? 80 : 68, ring = 4;
    self.banner.frame = CGRectMake(0, 0, width, bannerH);
    self.avatarRing.frame = CGRectMake(pad - ring, bannerH - avatar / 2 - ring, avatar + 2 * ring, avatar + 2 * ring);
    self.avatarRing.layer.cornerRadius = (avatar + 2 * ring) / 2;
    self.avatar.frame = CGRectMake(pad, bannerH - avatar / 2, avatar, avatar);
    self.avatar.layer.cornerRadius = avatar / 2;

    if (!self.isMe) {
        CGFloat btnY = bannerH + 8;
        [self.followButton sizeToFit];
        CGFloat fw = MAX(80, self.followButton.frame.size.width);
        self.followButton.frame = CGRectMake(width - pad - fw, btnY, fw, 30);
        [self.messageButton sizeToFit];
        CGFloat mw = MAX(82, self.messageButton.frame.size.width);
        self.messageButton.frame = CGRectMake(width - pad - fw - 8 - mw, btnY, mw, 30);
    }

    CGFloat y = bannerH + avatar / 2 + 8;
    CGFloat w = width - 2 * pad;
    CGFloat nameH = ceilf((float)self.nameLabel.font.lineHeight);
    CGFloat nameTextW = ceilf((float)[self.nameLabel.text sizeWithFont:self.nameLabel.font].width);
    self.nameLabel.frame = CGRectMake(pad, y, MIN(nameTextW, w - 20), nameH);
    self.verified.frame = self.verified.hidden ? CGRectZero : CGRectMake(pad + MIN(nameTextW, w - 20) + 3, y + (nameH - 16) / 2, 16, 16);
    y += nameH + 1;
    CGFloat handleH = ceilf((float)self.handleLabel.font.lineHeight);
    self.handleLabel.frame = CGRectMake(pad, y, w, handleH);
    if (!self.protectedLabel.hidden) {
        CGFloat pw = ceilf((float)[self.protectedLabel.text sizeWithFont:self.protectedLabel.font].width) + 4;
        self.protectedLabel.frame = CGRectMake(width - pad - pw, y, pw, handleH);
    }
    y += handleH + 8;

    if (self.bioLabel.text.length) {
        CGFloat bh = ceilf((float)[self.bioLabel.text sizeWithFont:self.bioLabel.font constrainedToSize:CGSizeMake(w, 100000) lineBreakMode:NSLineBreakByWordWrapping].height);
        self.bioLabel.frame = CGRectMake(pad, y, w, bh);
        y += bh + 8;
    } else {
        self.bioLabel.frame = CGRectZero;
    }
    if (self.metaLabel.text.length) {
        CGFloat mh = ceilf((float)[self.metaLabel.text sizeWithFont:self.metaLabel.font constrainedToSize:CGSizeMake(w, 100000) lineBreakMode:NSLineBreakByWordWrapping].height);
        self.metaLabel.frame = CGRectMake(pad, y, w, mh);
        y += mh + 6;
    } else {
        self.metaLabel.frame = CGRectZero;
    }
    [self.followingButton sizeToFit];
    CGFloat fiW = self.followingButton.frame.size.width;
    self.followingButton.frame = CGRectMake(pad, y, fiW, 24);
    [self.followersButton sizeToFit];
    self.followersButton.frame = CGRectMake(pad + fiW + 18, y, self.followersButton.frame.size.width, 24);
    y += 24 + 10;

    self.segments.frame = CGRectMake(pad, y, w, 30);
    y += 30 + 8;

    self.header.frame = CGRectMake(0, 0, width, y);
    self.headerWidth = width;
    self.tableView.tableHeaderView = self.header;   // re-assign so the table picks up the new height
    return y;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (self.user && fabs(self.headerWidth - self.tableView.bounds.size.width) > 0.5)
        [self layoutHeaderForWidth:self.tableView.bounds.size.width];
}

- (UIImage *)verifiedBadge
{
    static UIImage *img;
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), NO, 0);
    [[UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 16, 16)] fill];
    UIBezierPath *check = [UIBezierPath bezierPath];
    [check moveToPoint:CGPointMake(4.5, 8.3)]; [check addLineToPoint:CGPointMake(7, 11)]; [check addLineToPoint:CGPointMake(11.8, 5)];
    check.lineWidth = 1.8; check.lineCapStyle = kCGLineCapRound; check.lineJoinStyle = kCGLineJoinRound;
    [[UIColor whiteColor] setStroke]; [check stroke];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Loading

- (void)loadUser
{
    [CHTwitter userWithHandle:self.handle completion:^(CHUser *user, NSError *error) {
        if (user) {
            self.user = user;
            if (user.handle.length) { self.handle = user.handle; self.title = [@"@" stringByAppendingString:user.handle]; }
            [self fillHeaderFromUser];
        }
    }];
}

- (void)switchKind:(UISegmentedControl *)sender
{
    self.kindIndex = sender.selectedSegmentIndex;
    [self reload];
}

- (void)fetchWithCursor:(NSString *)cursor completion:(void (^)(CHTweetPage *, NSError *))completion
{
    if (![CHTwitter configured]) { completion(nil, CHMakeError(CHErrorAPI, L(@"Set the server address in Settings first."))); return; }
    NSString *kind = self.kinds[(NSUInteger)self.kindIndex];
    [CHTwitter tweetsOfUser:self.handle userId:self.user.userId kind:kind cursor:cursor completion:completion];
}

@end

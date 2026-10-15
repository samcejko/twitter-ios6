#import "CHTweetCell.h"
#import "CHImageLoader.h"
#import "CHLinkLabel.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#pragma mark - Metrics

static CGFloat CHPad(void)      { return 10; }
static CGFloat CHAvatar(void)   { return CHIsPad() ? 48 : 44; }
static CGFloat CHGap(void)      { return 8; }
static CGFloat CHMediaGap(void) { return 3; }

static UIFont *CHNameFont(void) { return [UIFont boldSystemFontOfSize:CHIsPad() ? 16 : 15]; }
static UIFont *CHMetaFont(void) { return [UIFont systemFontOfSize:CHIsPad() ? 15 : 14]; }
static UIFont *CHTextFont(void) { return [UIFont systemFontOfSize:CHIsPad() ? 16 : 15]; }
static UIFont *CHBigTextFont(void) { return [UIFont systemFontOfSize:CHIsPad() ? 19 : 17]; }
static UIFont *CHSmallFont(void){ return [UIFont systemFontOfSize:CHIsPad() ? 13 : 12]; }

static NSString *CHFullDate(NSTimeInterval t)
{
    if (t <= 0) return @"";
    static NSDateFormatter *fmt;
    if (!fmt) {
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    }
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static CGFloat CHLineH(UIFont *f) { return ceilf((float)f.lineHeight); }

static CGFloat CHTextHeight(NSString *s, UIFont *font, CGFloat width)
{
    if (!s.length || width < 1) return 0;
    CGSize sz = [s sizeWithFont:font constrainedToSize:CGSizeMake(width, 100000) lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf((float)sz.height);
}

static CGFloat CHClamp(CGFloat v, CGFloat lo, CGFloat hi) { return v < lo ? lo : v > hi ? hi : v; }

// The quoted tweet's text, cut so the box stays small
static NSString *CHQuoteText(CHTweet *q)
{
    NSString *t = [CHUtils displayText:q.text ?: @""];
    return [CHUtils truncate:t to:200];
}

// Height of the quoted-tweet box for a given outer content width
static CGFloat CHQuoteHeight(CHTweet *q, CGFloat contentW)
{
    if (!q) return 0;
    CGFloat qp = 8;
    CGFloat innerW = contentW - 2 * qp;
    CGFloat thumb = q.media.count ? (CHIsPad() ? 72 : 60) : 0;
    CGFloat textW = innerW - (thumb ? thumb + 8 : 0);
    CGFloat y = qp;
    y += CHLineH(CHSmallFont());                               // name / @handle line
    CGFloat textH = CHTextHeight(CHQuoteText(q), CHMetaFont(), textW);
    textH = MIN(textH, CHLineH(CHMetaFont()) * 6);
    y += textH;
    y += qp;
    return MAX(y, thumb ? thumb + 2 * qp : y);
}

#pragma mark - Layout

typedef struct {
    CGFloat width;
    BOOL expanded;
    CGRect retweetContext;
    CGRect avatar;
    CGRect header;
    CGRect replyContext;
    CGRect text;
    CGRect mediaBlock;
    NSInteger mediaCount;
    CGRect mediaTiles[4];
    CGRect quote;
    CGRect dateLine;       // expanded only
    CGRect actions;
    CGFloat totalHeight;
} CHTweetLayout;

static void CHComputeMediaTiles(CHTweetLayout *L, CHTweet *tweet, CGFloat ox, CGFloat oy, CGFloat w)
{
    NSInteger n = MIN((NSInteger)tweet.media.count, 4);
    L->mediaCount = n;
    CGFloat g = CHMediaGap(), h;
    if (n == 1) {
        CHMedia *m = tweet.media[0];
        CGFloat ratio = (m.width > 0 && m.height > 0) ? (CGFloat)m.height / m.width : 0.5625f;
        h = roundf(w * CHClamp(ratio, 0.56f, 1.3f));
        L->mediaTiles[0] = CGRectMake(ox, oy, w, h);
    } else if (n == 2) {
        h = roundf(w * 0.56f);
        CGFloat tw = floorf((w - g) / 2);
        L->mediaTiles[0] = CGRectMake(ox, oy, tw, h);
        L->mediaTiles[1] = CGRectMake(ox + tw + g, oy, w - tw - g, h);
    } else if (n == 3) {
        h = roundf(w * 0.56f);
        CGFloat tw = floorf((w - g) / 2), th = floorf((h - g) / 2);
        L->mediaTiles[0] = CGRectMake(ox, oy, tw, h);
        L->mediaTiles[1] = CGRectMake(ox + tw + g, oy, w - tw - g, th);
        L->mediaTiles[2] = CGRectMake(ox + tw + g, oy + th + g, w - tw - g, h - th - g);
    } else {
        h = roundf(w * 0.75f);
        CGFloat tw = floorf((w - g) / 2), th = floorf((h - g) / 2);
        L->mediaTiles[0] = CGRectMake(ox, oy, tw, th);
        L->mediaTiles[1] = CGRectMake(ox + tw + g, oy, w - tw - g, th);
        L->mediaTiles[2] = CGRectMake(ox, oy + th + g, tw, h - th - g);
        L->mediaTiles[3] = CGRectMake(ox + tw + g, oy + th + g, w - tw - g, h - th - g);
    }
    L->mediaBlock = CGRectMake(ox, oy, w, h);
}

static CHTweetLayout CHComputeLayout(CHTweet *tweet, CGFloat width, BOOL expanded)
{
    CHTweetLayout L;
    memset(&L, 0, sizeof(L));
    L.width = width;
    L.expanded = expanded;
    CGFloat pad = CHPad(), avatar = CHAvatar(), gap = CHGap();
    CGFloat left = pad + avatar + gap;
    CGFloat contentW = width - left - pad;
    CGFloat y = 9;

    if (tweet.isRetweet) {
        L.retweetContext = CGRectMake(left, y, contentW, CHLineH(CHSmallFont()));
        y += CHLineH(CHSmallFont()) + 3;
    }

    CGFloat avatarTop = y;
    L.avatar = CGRectMake(pad, avatarTop, avatar, avatar);
    L.header = CGRectMake(left, y, contentW, CHLineH(CHNameFont()));
    y += CHLineH(CHNameFont()) + 1;

    if (tweet.replyToHandle.length) {
        L.replyContext = CGRectMake(left, y, contentW, CHLineH(CHSmallFont()));
        y += CHLineH(CHSmallFont()) + 2;
    }

    // the focal tweet reads full width (its big text starts under the avatar too, but the extra pixels are minor)
    UIFont *textFont = expanded ? CHBigTextFont() : CHTextFont();
    NSString *text = [CHUtils displayText:tweet.text ?: @""];
    if (text.length) {
        CGFloat th = CHTextHeight(text, textFont, contentW);
        L.text = CGRectMake(left, y, contentW, th);
        y += th;
    }

    if (tweet.media.count) {
        y += 8;
        CHComputeMediaTiles(&L, tweet, left, y, contentW);
        y += L.mediaBlock.size.height;
    }

    if (tweet.quoted) {
        y += 8;
        CGFloat qh = CHQuoteHeight(tweet.quoted, contentW);
        L.quote = CGRectMake(left, y, contentW, qh);
        y += qh;
    }

    if (expanded && tweet.createdAt > 0) {
        y += 8;
        L.dateLine = CGRectMake(left, y, contentW, CHLineH(CHSmallFont()) + 2);
        y += L.dateLine.size.height;
    }

    y += 8;
    L.actions = CGRectMake(left, y, contentW, CHLineH(CHSmallFont()) + 4);
    y += L.actions.size.height;

    y += 9;
    L.totalHeight = MAX(y, avatarTop + avatar + 9);
    return L;
}

#pragma mark - Small drawn icons (count row); iOS 6 has no emoji for these

static UIImage *CHActionIcon(NSString *name, UIColor *color)
{
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString *key = [NSString stringWithFormat:@"%@-%.2f-%.2f-%.2f", name, r, g, b];
    UIImage *img = cache[key];
    if (img) return img;
    CGSize size = CGSizeMake(18, 18);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [color setStroke];
    [color setFill];
    if ([name isEqualToString:@"reply"]) {
        UIBezierPath *b1 = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 2.5, 14, 10) cornerRadius:3];
        b1.lineWidth = 1.6;
        [b1 stroke];
        UIBezierPath *tail = [UIBezierPath bezierPath];
        [tail moveToPoint:CGPointMake(5, 12)];
        [tail addLineToPoint:CGPointMake(4, 16)];
        [tail addLineToPoint:CGPointMake(9, 12.4)];
        tail.lineWidth = 1.6;
        tail.lineJoinStyle = kCGLineJoinRound;
        [tail stroke];
    } else if ([name isEqualToString:@"retweet"]) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.6;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(5, 6)];
        [p addLineToPoint:CGPointMake(13, 6)];
        [p addLineToPoint:CGPointMake(13, 11)];
        [p moveToPoint:CGPointMake(13, 12)];
        [p addLineToPoint:CGPointMake(5, 12)];
        [p addLineToPoint:CGPointMake(5, 7)];
        [p stroke];
        UIBezierPath *a1 = [UIBezierPath bezierPath];   // arrow heads
        [a1 moveToPoint:CGPointMake(2.5, 8.5)]; [a1 addLineToPoint:CGPointMake(5, 5)]; [a1 addLineToPoint:CGPointMake(7.5, 8.5)]; [a1 closePath];
        [a1 fill];
        UIBezierPath *a2 = [UIBezierPath bezierPath];
        [a2 moveToPoint:CGPointMake(10.5, 9.5)]; [a2 addLineToPoint:CGPointMake(13, 13)]; [a2 addLineToPoint:CGPointMake(15.5, 9.5)]; [a2 closePath];
        [a2 fill];
    } else if ([name isEqualToString:@"like"]) {
        UIBezierPath *heart = [UIBezierPath bezierPath];
        [heart moveToPoint:CGPointMake(9, 15.5)];
        [heart addCurveToPoint:CGPointMake(2.5, 7) controlPoint1:CGPointMake(4.5, 12) controlPoint2:CGPointMake(2.5, 9.6)];
        [heart addArcWithCenter:CGPointMake(5.2, 6.4) radius:2.7 startAngle:M_PI endAngle:0 clockwise:YES];
        [heart addArcWithCenter:CGPointMake(10.6, 6.4) radius:2.7 startAngle:M_PI endAngle:0 clockwise:YES];
        [heart addCurveToPoint:CGPointMake(9, 15.5) controlPoint1:CGPointMake(15.5, 9.6) controlPoint2:CGPointMake(13.5, 12)];
        [heart closePath];
        heart.lineWidth = 1.6;
        [heart stroke];
    } else if ([name isEqualToString:@"views"]) {
        UIBezierPath *bars = [UIBezierPath bezierPath];
        bars.lineWidth = 1.8;
        bars.lineCapStyle = kCGLineCapRound;
        CGFloat xs[] = { 3, 7, 11, 15 }, hs[] = { 4, 8, 6, 12 };
        for (int i = 0; i < 4; i++) { [bars moveToPoint:CGPointMake(xs[i], 15)]; [bars addLineToPoint:CGPointMake(xs[i], 15 - hs[i])]; }
        [bars stroke];
    } else if ([name isEqualToString:@"like-filled"]) {
        UIBezierPath *heart = [UIBezierPath bezierPath];
        [heart moveToPoint:CGPointMake(9, 15.5)];
        [heart addCurveToPoint:CGPointMake(2.5, 7) controlPoint1:CGPointMake(4.5, 12) controlPoint2:CGPointMake(2.5, 9.6)];
        [heart addArcWithCenter:CGPointMake(5.2, 6.4) radius:2.7 startAngle:M_PI endAngle:0 clockwise:YES];
        [heart addArcWithCenter:CGPointMake(10.6, 6.4) radius:2.7 startAngle:M_PI endAngle:0 clockwise:YES];
        [heart addCurveToPoint:CGPointMake(9, 15.5) controlPoint1:CGPointMake(15.5, 9.6) controlPoint2:CGPointMake(13.5, 12)];
        [heart closePath];
        [heart fill];
    } else if ([name isEqualToString:@"bookmark"] || [name isEqualToString:@"bookmark-filled"]) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(4, 2.5)];
        [p addLineToPoint:CGPointMake(14, 2.5)];
        [p addLineToPoint:CGPointMake(14, 16)];
        [p addLineToPoint:CGPointMake(9, 11.5)];
        [p addLineToPoint:CGPointMake(4, 16)];
        [p closePath];
        if ([name hasSuffix:@"filled"]) { [p fill]; } else { p.lineWidth = 1.6; p.lineJoinStyle = kCGLineJoinRound; [p stroke]; }
    } else if ([name isEqualToString:@"more"]) {
        for (int i = 0; i < 3; i++) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2 + i * 6, 8, 2.6, 2.6)] fill];
    }
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

static UIImage *CHVerifiedBadge(void)
{
    static UIImage *img;
    if (img) return img;
    CGSize size = CGSizeMake(16, 16);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 16, 16)] fill];
    UIBezierPath *check = [UIBezierPath bezierPath];
    [check moveToPoint:CGPointMake(4.5, 8.3)];
    [check addLineToPoint:CGPointMake(7, 11)];
    [check addLineToPoint:CGPointMake(11.8, 5)];
    check.lineWidth = 1.8;
    check.lineCapStyle = kCGLineCapRound;
    check.lineJoinStyle = kCGLineJoinRound;
    [[UIColor whiteColor] setStroke];
    [check stroke];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Cell

@interface CHTweetCell ()
@property (nonatomic, strong) UILabel *retweetLabel;
@property (nonatomic, strong) UIImageView *retweetIcon;
@property (nonatomic, strong) CHImageView *avatarView;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UILabel *nameLabel;        // attributed: name + @handle
@property (nonatomic, strong) UIImageView *verifiedView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *headerButton;
@property (nonatomic, strong) UILabel *replyLabel;
@property (nonatomic, strong) CHLinkLabel *textLabel2;
@property (nonatomic, strong) UILabel *dateLabel;           // expanded only
@property (nonatomic, strong) NSMutableArray *mediaViews;   // CHImageView
@property (nonatomic, strong) NSMutableArray *playBadges;   // UIImageView over video tiles
@property (nonatomic, strong) UIView *quoteView;
@property (nonatomic, strong) CHImageView *quoteAvatar;
@property (nonatomic, strong) UILabel *quoteNameLabel;
@property (nonatomic, strong) UILabel *quoteTextLabel;
@property (nonatomic, strong) CHImageView *quoteThumb;
// action row
@property (nonatomic, strong) NSArray *countIcons;    // UIImageView reply/retweet/like/views
@property (nonatomic, strong) NSArray *countLabels;   // UILabel
@property (nonatomic, strong) NSArray *actionButtons; // invisible tap targets over reply/retweet/like
@property (nonatomic, strong) UIButton *bookmarkButton;
@property (nonatomic, strong) UIButton *moreButton;
@end

@implementation CHTweetCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        CHTheme *th = [CHTheme shared];
        self.backgroundColor = [th cardColor];
        self.contentView.backgroundColor = [th cardColor];
        self.selectionStyle = UITableViewCellSelectionStyleGray;

        _retweetIcon = [[UIImageView alloc] init];
        _retweetLabel = [self labelFont:CHSmallFont() color:[th secondaryTextColor]];
        _avatarView = [[CHImageView alloc] init];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.clipsToBounds = YES;
        _avatarView.backgroundColor = [th separatorColor];
        _avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_avatarButton addTarget:self action:@selector(tapUser) forControlEvents:UIControlEventTouchUpInside];
        _nameLabel = [self labelFont:CHNameFont() color:[th primaryTextColor]];
        _verifiedView = [[UIImageView alloc] initWithImage:CHVerifiedBadge()];
        _timeLabel = [self labelFont:CHMetaFont() color:[th secondaryTextColor]];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _headerButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_headerButton addTarget:self action:@selector(tapUser) forControlEvents:UIControlEventTouchUpInside];
        _replyLabel = [self labelFont:CHSmallFont() color:[th secondaryTextColor]];
        _textLabel2 = [[CHLinkLabel alloc] init];
        _textLabel2.font = CHTextFont();
        _textLabel2.textColor = [th primaryTextColor];
        _textLabel2.backgroundColor = [UIColor clearColor];
        _textLabel2.numberOfLines = 0;
        _dateLabel = [self labelFont:CHSmallFont() color:[th secondaryTextColor]];
        _dateLabel.hidden = YES;

        _mediaViews = [NSMutableArray array];
        _playBadges = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            CHImageView *v = [[CHImageView alloc] init];
            v.contentMode = UIViewContentModeScaleAspectFill;
            v.clipsToBounds = YES;
            v.backgroundColor = [th separatorColor];
            v.userInteractionEnabled = YES;
            v.tag = i;
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapMedia:)];
            [v addGestureRecognizer:tap];
            v.hidden = YES;
            [self.contentView addSubview:v];
            [_mediaViews addObject:v];
            UIImageView *badge = [[UIImageView alloc] initWithImage:[[CHTheme shared] roundButtonImageWithSize:44]];
            badge.hidden = YES;
            [self.contentView addSubview:badge];
            [_playBadges addObject:badge];
        }

        _quoteView = [[UIView alloc] init];
        _quoteView.layer.borderWidth = 1;
        _quoteView.layer.cornerRadius = 10;
        _quoteView.clipsToBounds = YES;
        _quoteView.userInteractionEnabled = YES;
        [_quoteView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapQuote)]];
        _quoteAvatar = [[CHImageView alloc] init];
        _quoteAvatar.contentMode = UIViewContentModeScaleAspectFill;
        _quoteAvatar.clipsToBounds = YES;
        _quoteNameLabel = [self labelFont:CHSmallFont() color:[th secondaryTextColor]];
        _quoteTextLabel = [self labelFont:CHMetaFont() color:[th primaryTextColor]];
        _quoteTextLabel.numberOfLines = 0;
        _quoteThumb = [[CHImageView alloc] init];
        _quoteThumb.contentMode = UIViewContentModeScaleAspectFill;
        _quoteThumb.clipsToBounds = YES;
        _quoteThumb.layer.cornerRadius = 6;
        [_quoteView addSubview:_quoteAvatar];
        [_quoteView addSubview:_quoteNameLabel];
        [_quoteView addSubview:_quoteTextLabel];
        [_quoteView addSubview:_quoteThumb];

        NSMutableArray *icons = [NSMutableArray array], *labels = [NSMutableArray array];
        for (NSString *n in @[ @"reply", @"retweet", @"like", @"views" ]) {
            UIImageView *iv = [[UIImageView alloc] initWithImage:CHActionIcon(n, [th secondaryTextColor])];
            [icons addObject:iv];
            UILabel *lb = [self labelFont:CHSmallFont() color:[th secondaryTextColor]];
            [labels addObject:lb];
        }
        _countIcons = icons;
        _countLabels = labels;
        NSMutableArray *abtns = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {   // reply / retweet / like are tappable; views is not
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = i;
            [b addTarget:self action:@selector(tapActionButton:) forControlEvents:UIControlEventTouchUpInside];
            [abtns addObject:b];
        }
        _actionButtons = abtns;
        _bookmarkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_bookmarkButton addTarget:self action:@selector(tapBookmark) forControlEvents:UIControlEventTouchUpInside];
        _moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_moreButton setImage:CHActionIcon(@"more", [th secondaryTextColor]) forState:UIControlStateNormal];
        [_moreButton addTarget:self action:@selector(tapMore) forControlEvents:UIControlEventTouchUpInside];

        for (UIView *v in @[ _retweetIcon, _retweetLabel, _avatarView, _nameLabel, _verifiedView, _timeLabel,
                             _replyLabel, _textLabel2, _dateLabel, _quoteView ])
            [self.contentView addSubview:v];
        for (UIImageView *iv in icons) [self.contentView addSubview:iv];
        for (UILabel *lb in labels) [self.contentView addSubview:lb];
        for (UIButton *b in abtns) [self.contentView addSubview:b];
        // tap targets above the content they cover
        for (UIView *v in @[ _bookmarkButton, _moreButton, _avatarButton, _headerButton ]) [self.contentView addSubview:v];
    }
    return self;
}

- (UILabel *)labelFont:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    return l;
}

+ (CGFloat)heightForTweet:(CHTweet *)tweet width:(CGFloat)width
{
    return CHComputeLayout(tweet, width, NO).totalHeight;
}

+ (CGFloat)heightForTweet:(CHTweet *)tweet width:(CGFloat)width expanded:(BOOL)expanded
{
    return CHComputeLayout(tweet, width, expanded).totalHeight;
}

- (void)setTweet:(CHTweet *)tweet
{
    _tweet = tweet;
    CHTheme *th = [CHTheme shared];

    // retweet context
    if (tweet.isRetweet) {
        self.retweetIcon.image = CHActionIcon(@"retweet", [th secondaryTextColor]);
        self.retweetIcon.hidden = NO;
        NSString *who = tweet.retweetedByName.length ? tweet.retweetedByName : tweet.retweetedByHandle;
        self.retweetLabel.text = [NSString stringWithFormat:L(@"%@ retweeted"), who];
        self.retweetLabel.hidden = NO;
    } else {
        self.retweetIcon.hidden = self.retweetLabel.hidden = YES;
    }

    CHUser *author = tweet.author;
    CGFloat avatarPix = CHAvatar() * 2;
    self.avatarView.maxPixels = avatarPix;
    self.avatarView.layer.cornerRadius = CHAvatar() / 2;
    self.avatarView.clipsToBounds = YES;
    [self.avatarView setImageURL:author.avatarURL placeholder:[th avatarPlaceholderWithSize:CHAvatar()]];

    // name + @handle (attributed, one line)
    NSString *name = [CHUtils displayText:author.name.length ? author.name : author.handle];
    NSString *handle = author.handle.length ? [@"  @" stringByAppendingString:author.handle] : @"";
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:name ?: @""
        attributes:@{ NSFontAttributeName: CHNameFont(), NSForegroundColorAttributeName: [th primaryTextColor] }];
    if (handle.length) [title appendAttributedString:[[NSAttributedString alloc] initWithString:handle
        attributes:@{ NSFontAttributeName: CHMetaFont(), NSForegroundColorAttributeName: [th secondaryTextColor] }]];
    self.nameLabel.attributedText = title;
    self.verifiedView.hidden = !author.verified;
    self.timeLabel.text = tweet.createdAt > 0 ? [CHUtils formatRelativeDate:[NSDate dateWithTimeIntervalSince1970:tweet.createdAt]] : @"";

    // reply context
    if (tweet.replyToHandle.length) {
        self.replyLabel.text = [NSString stringWithFormat:L(@"Replying to @%@"), tweet.replyToHandle];
        self.replyLabel.hidden = NO;
    } else {
        self.replyLabel.hidden = YES;
    }

    NSString *text = [CHUtils displayText:tweet.text ?: @""];
    self.textLabel2.font = self.expanded ? CHBigTextFont() : CHTextFont();   // CHLinkLabel wants the font before the text
    self.textLabel2.textColor = [th primaryTextColor];
    self.textLabel2.text = text;
    self.textLabel2.hidden = !text.length;

    if (self.expanded && tweet.createdAt > 0) {
        self.dateLabel.hidden = NO;
        NSString *date = CHFullDate(tweet.createdAt);
        self.dateLabel.text = tweet.viewCount > 0 ? [NSString stringWithFormat:@"%@  ·  %@", date, [NSString stringWithFormat:L(@"%@ Views"), [CHUtils formatBigCount:tweet.viewCount]]] : date;
    } else {
        self.dateLabel.hidden = YES;
    }

    // media
    for (NSInteger i = 0; i < 4; i++) {
        CHImageView *v = self.mediaViews[(NSUInteger)i];
        UIImageView *badge = self.playBadges[(NSUInteger)i];
        if (i < (NSInteger)tweet.media.count && i < 4) {
            CHMedia *m = tweet.media[(NSUInteger)i];
            v.hidden = NO;
            v.layer.cornerRadius = 8;
            v.maxPixels = 1024;
            [v setImageURL:(m.previewURL.length ? m.previewURL : m.url) placeholder:[th thumbnailPlaceholder]];
            badge.hidden = !m.isVideo;
        } else {
            v.hidden = badge.hidden = YES;
            [v setImageURL:nil placeholder:nil];
        }
    }

    // quoted
    if (tweet.quoted) {
        self.quoteView.hidden = NO;
        self.quoteView.layer.borderColor = [th separatorColor].CGColor;
        self.quoteView.backgroundColor = th.isDark ? [UIColor colorWithWhite:1 alpha:0.03] : [UIColor colorWithWhite:0 alpha:0.02];
        CHUser *qa = tweet.quoted.author;
        self.quoteAvatar.layer.cornerRadius = (CHIsPad() ? 18 : 16) / 2;
        self.quoteAvatar.maxPixels = 64;
        [self.quoteAvatar setImageURL:qa.avatarURL placeholder:[th avatarPlaceholderWithSize:16]];
        NSString *qname = [CHUtils displayText:qa.name.length ? qa.name : qa.handle];
        NSString *qh = qa.handle.length ? [@" @" stringByAppendingString:qa.handle] : @"";
        self.quoteNameLabel.text = [qname stringByAppendingString:qh];
        self.quoteTextLabel.text = CHQuoteText(tweet.quoted);
        if (tweet.quoted.media.count) {
            CHMedia *qm = tweet.quoted.media[0];
            self.quoteThumb.hidden = NO;
            self.quoteThumb.maxPixels = 256;
            [self.quoteThumb setImageURL:(qm.previewURL.length ? qm.previewURL : qm.url) placeholder:[th thumbnailPlaceholder]];
        } else {
            self.quoteThumb.hidden = YES;
        }
    } else {
        self.quoteView.hidden = YES;
    }

    // counts, coloured by the tweet's own action state
    UIColor *secondary = [th secondaryTextColor];
    UIColor *green = [UIColor colorWithRed:0.0 green:0.72 blue:0.49 alpha:1];
    UIColor *pink = [UIColor colorWithRed:0.95 green:0.09 blue:0.46 alpha:1];
    UIColor *blue = [th accentColor];
    long long counts[] = { tweet.replyCount, tweet.retweetCount, tweet.likeCount, tweet.viewCount };
    NSArray *names = @[ @"reply", @"retweet", tweet.favorited ? @"like-filled" : @"like", @"views" ];
    UIColor *colors[4] = { secondary, tweet.retweeted ? green : secondary, tweet.favorited ? pink : secondary, secondary };
    for (NSInteger i = 0; i < 4; i++) {
        ((UIImageView *)self.countIcons[(NSUInteger)i]).image = CHActionIcon(names[(NSUInteger)i], colors[i]);
        UILabel *lb = self.countLabels[(NSUInteger)i];
        lb.text = counts[i] > 0 ? [CHUtils formatBigCount:counts[i]] : @"";
        lb.textColor = colors[i];
    }
    [self.bookmarkButton setImage:CHActionIcon(tweet.bookmarked ? @"bookmark-filled" : @"bookmark", tweet.bookmarked ? blue : secondary) forState:UIControlStateNormal];

    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CHTweetLayout L = CHComputeLayout(self.tweet, width, self.expanded);

    if (!self.retweetLabel.hidden) {
        self.retweetLabel.frame = CGRectMake(L.retweetContext.origin.x + 20, L.retweetContext.origin.y,
                                             L.retweetContext.size.width - 20, L.retweetContext.size.height);
        self.retweetIcon.frame = CGRectMake(L.retweetContext.origin.x, L.retweetContext.origin.y + 1, 15, 15);
    }
    self.avatarView.frame = L.avatar;
    self.avatarButton.frame = L.avatar;

    // header: name/handle on the left (leaving room for time on the right), time right-aligned
    CGFloat timeW = 0;
    if (self.timeLabel.text.length) { timeW = ceilf((float)[self.timeLabel.text sizeWithFont:CHMetaFont()].width) + 4; }
    CGRect header = L.header;
    CGFloat nameW = header.size.width - timeW - 6;
    // verified badge sits right after the name text
    CGFloat nameTextW = ceilf((float)[self.nameLabel.attributedText size].width);
    if (!self.verifiedView.hidden) nameW -= 18;
    self.nameLabel.frame = CGRectMake(header.origin.x, header.origin.y, MAX(20, nameW), header.size.height);
    CGFloat vbx = header.origin.x + MIN(nameTextW, self.nameLabel.frame.size.width) + 2;
    self.verifiedView.frame = CGRectMake(vbx, header.origin.y + (header.size.height - 16) / 2, 16, 16);
    self.timeLabel.frame = CGRectMake(header.origin.x + header.size.width - timeW, header.origin.y, timeW, header.size.height);
    self.headerButton.frame = CGRectMake(header.origin.x, header.origin.y, header.size.width - timeW, header.size.height);

    self.replyLabel.frame = self.replyLabel.hidden ? CGRectZero : L.replyContext;
    self.textLabel2.frame = self.textLabel2.hidden ? CGRectZero : L.text;

    for (NSInteger i = 0; i < 4; i++) {
        CHImageView *v = self.mediaViews[(NSUInteger)i];
        UIImageView *badge = self.playBadges[(NSUInteger)i];
        if (i < L.mediaCount) {
            v.frame = L.mediaTiles[i];
            badge.frame = CGRectMake(CGRectGetMidX(v.frame) - 22, CGRectGetMidY(v.frame) - 22, 44, 44);
        }
    }

    if (!self.quoteView.hidden) {
        self.quoteView.frame = L.quote;
        [self layoutQuote:L.quote.size];
    }

    self.dateLabel.frame = self.dateLabel.hidden ? CGRectZero : L.dateLine;

    // action row: reply / retweet / like / views left-aligned; bookmark and more at the right
    CGFloat ax = L.actions.origin.x, ay = L.actions.origin.y, ah = L.actions.size.height;
    CGFloat rightEdge = ax + L.actions.size.width;
    self.moreButton.frame = CGRectMake(rightEdge - 28, ay + (ah - 28) / 2, 28, 28);
    self.bookmarkButton.frame = CGRectMake(rightEdge - 28 - 32, ay + (ah - 28) / 2, 28, 28);
    CGFloat cx = ax;
    CGFloat groupGap = CHIsPad() ? 30 : 22;
    CGFloat groupStart[4], groupWidth[4];
    for (NSInteger i = 0; i < 4; i++) {
        UIImageView *iv = self.countIcons[(NSUInteger)i];
        UILabel *lb = self.countLabels[(NSUInteger)i];
        iv.frame = CGRectMake(cx, ay + (ah - 18) / 2, 18, 18);
        CGFloat w = lb.text.length ? ceilf((float)[lb.text sizeWithFont:CHSmallFont()].width) + 4 : 0;
        lb.frame = CGRectMake(cx + 20, ay, w, ah);
        groupStart[i] = cx;
        groupWidth[i] = 20 + w;
        cx += 20 + w + groupGap;
    }
    for (NSInteger i = 0; i < 3; i++)
        ((UIButton *)self.actionButtons[(NSUInteger)i]).frame = CGRectMake(groupStart[i] - 4, ay - 4, groupWidth[i] + 12, ah + 8);
}

- (void)layoutQuote:(CGSize)size
{
    CGFloat qp = 8;
    CGFloat avatar = CHIsPad() ? 18 : 16;
    self.quoteAvatar.frame = CGRectMake(qp, qp, avatar, avatar);
    CGFloat thumb = self.quoteThumb.hidden ? 0 : (CHIsPad() ? 72 : 60);
    CGFloat nameX = qp + avatar + 5;
    self.quoteNameLabel.frame = CGRectMake(nameX, qp, size.width - nameX - qp - (thumb ? thumb + 8 : 0), avatar);
    CGFloat textY = qp + avatar;
    CGFloat textW = size.width - 2 * qp - (thumb ? thumb + 8 : 0);
    self.quoteTextLabel.frame = CGRectMake(qp, textY, textW, size.height - textY - qp);
    if (thumb) self.quoteThumb.frame = CGRectMake(size.width - thumb - qp, qp, thumb, size.height - 2 * qp);
}

#pragma mark - Taps

- (void)tapUser { if ([self.delegate respondsToSelector:@selector(tweetCell:didTapUser:)]) [self.delegate tweetCell:self didTapUser:self.tweet.author]; }
- (void)tapQuote { if (self.tweet.quoted && [self.delegate respondsToSelector:@selector(tweetCell:didTapQuoted:)]) [self.delegate tweetCell:self didTapQuoted:self.tweet.quoted]; }
- (void)tapMedia:(UITapGestureRecognizer *)g { if ([self.delegate respondsToSelector:@selector(tweetCell:didTapMediaAtIndex:)]) [self.delegate tweetCell:self didTapMediaAtIndex:g.view.tag]; }

- (void)action:(NSString *)name { if ([self.delegate respondsToSelector:@selector(tweetCell:didTapAction:)]) [self.delegate tweetCell:self didTapAction:name]; }
- (void)tapActionButton:(UIButton *)b { [self action:@[ @"reply", @"retweet", @"like" ][(NSUInteger)b.tag]]; }
- (void)tapBookmark { [self action:@"bookmark"]; }
- (void)tapMore { [self action:@"more"]; }

- (void)prepareForReuse
{
    [super prepareForReuse];
    for (CHImageView *v in self.mediaViews) [v setImageURL:nil placeholder:nil];
    [self.quoteThumb setImageURL:nil placeholder:nil];
    [self.quoteAvatar setImageURL:nil placeholder:nil];
}

@end

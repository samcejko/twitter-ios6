#import "CHUserCell.h"
#import "CHImageLoader.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

@interface CHUserCell ()
@property (nonatomic, strong) CHImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verified;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@end

@implementation CHUserCell

+ (CGFloat)height { return 84; }

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
        _verified = [[UIImageView alloc] init];
        _handleLabel = [self lbl:[th smallFont] color:[th secondaryTextColor]];
        _bioLabel = [self lbl:[th smallFont] color:[th secondaryTextColor]];
        _bioLabel.numberOfLines = 2;
        for (UIView *v in @[ _avatar, _nameLabel, _verified, _handleLabel, _bioLabel ]) [self.contentView addSubview:v];
    }
    return self;
}

- (UILabel *)lbl:(UIFont *)f color:(UIColor *)c { UILabel *l = [[UILabel alloc] init]; l.font = f; l.textColor = c; l.backgroundColor = [UIColor clearColor]; return l; }

- (void)setUser:(CHUser *)user
{
    CHTheme *th = [CHTheme shared];
    _avatar.maxPixels = 96;
    [_avatar setImageURL:user.avatarURL placeholder:[th avatarPlaceholderWithSize:48]];
    _nameLabel.text = [CHUtils displayText:user.name.length ? user.name : user.handle];
    _verified.hidden = !user.verified;
    if (user.verified && !_verified.image) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(15, 15), NO, 0);
        [[UIColor colorWithRed:0.11 green:0.63 blue:0.95 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 15, 15)] fill];
        UIBezierPath *ck = [UIBezierPath bezierPath];
        [ck moveToPoint:CGPointMake(4, 7.8)]; [ck addLineToPoint:CGPointMake(6.5, 10.3)]; [ck addLineToPoint:CGPointMake(11, 4.7)];
        ck.lineWidth = 1.7; ck.lineCapStyle = kCGLineCapRound; ck.lineJoinStyle = kCGLineJoinRound;
        [[UIColor whiteColor] setStroke]; [ck stroke];
        _verified.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    _handleLabel.text = [@"@" stringByAppendingString:user.handle ?: @""];
    _bioLabel.text = [CHUtils displayText:user.bio ?: @""];
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat pad = 12, av = 48;
    _avatar.frame = CGRectMake(pad, 10, av, av);
    _avatar.layer.cornerRadius = av / 2;
    CGFloat x = pad + av + 10, w = self.contentView.bounds.size.width - x - pad;
    CGFloat nameW = ceilf((float)[_nameLabel.text sizeWithFont:_nameLabel.font].width);
    _nameLabel.frame = CGRectMake(x, 9, MIN(nameW, w - 18), 18);
    _verified.frame = _verified.hidden ? CGRectZero : CGRectMake(x + MIN(nameW, w - 18) + 3, 10, 15, 15);
    _handleLabel.frame = CGRectMake(x, 28, w, 16);
    _bioLabel.frame = CGRectMake(x, 46, w, 30);
}

@end

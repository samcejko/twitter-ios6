#import "CHTweetListViewController.h"

// A person's page: a header (banner, avatar, bio, counts) and a segmented list of their Tweets / Replies / Media / Likes.
@interface CHProfileViewController : CHTweetListViewController
- (instancetype)initWithHandle:(NSString *)handle;
@property (nonatomic, copy, readonly) NSString *handle;
@end

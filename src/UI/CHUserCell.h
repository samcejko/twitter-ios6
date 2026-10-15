#import <UIKit/UIKit.h>
#import "CHModels.h"

// A person in a list (search People, followers, following): avatar, name, @handle, a two-line bio.
@interface CHUserCell : UITableViewCell
- (void)setUser:(CHUser *)user;
+ (CGFloat)height;
@end

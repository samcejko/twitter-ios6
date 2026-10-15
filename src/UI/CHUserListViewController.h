#import <UIKit/UIKit.h>

// A list of people: a profile's followers, or the people it follows.
@interface CHUserListViewController : UIViewController
- (instancetype)initWithHandle:(NSString *)handle userId:(NSString *)userId following:(BOOL)following;
@end

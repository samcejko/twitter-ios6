#import <UIKit/UIKit.h>

// The bottom tab bar: Home, Explore and Bookmarks (Settings is the gear in the bar of each).
@interface CHRootViewController : UITabBarController
- (void)selectTab:(NSInteger)index;
@end

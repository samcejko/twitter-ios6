#import <UIKit/UIKit.h>

// A full-screen viewer for a tweet's media: photos (pinch to zoom) and videos / GIFs (played through the app's media
// proxy, which does the TLS iOS 6 cannot). Swipe sideways between them.
@interface CHMediaViewController : UIViewController
- (instancetype)initWithMedia:(NSArray *)media startIndex:(NSInteger)index;   // CHMedia
@end

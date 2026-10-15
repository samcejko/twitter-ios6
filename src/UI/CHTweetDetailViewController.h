#import <UIKit/UIKit.h>
#import "CHModels.h"

// A tweet with its thread: the reply chain above it, the focal tweet (bigger), and the replies below.
@interface CHTweetDetailViewController : UIViewController
- (instancetype)initWithTweet:(CHTweet *)tweet;     // shown at once, the thread loads around it
- (instancetype)initWithTweetId:(NSString *)tweetId;
@end

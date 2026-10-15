#import <UIKit/UIKit.h>
#import "CHModels.h"

@class CHTweetCell;

// The shared handling of a tweet's action buttons (reply / retweet / like / bookmark / more), used by the timeline,
// the thread and anywhere else that shows a CHTweetCell. Likes, reposts and bookmarks update the tweet optimistically
// and tell the helper; a failure reverts and shows why.
@interface CHTweetActions : NSObject
+ (void)handleAction:(NSString *)action tweet:(CHTweet *)tweet cell:(CHTweetCell *)cell from:(UIViewController *)vc;
@end

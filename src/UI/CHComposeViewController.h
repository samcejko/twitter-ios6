#import <UIKit/UIKit.h>
#import "CHModels.h"

// Writing a post: a new tweet, a reply, or a quote. Text plus an optional single photo. Posts through the helper
// (which creates it as your account).
@interface CHComposeViewController : UIViewController
+ (instancetype)composeNew;
+ (instancetype)composeReplyTo:(CHTweet *)tweet;
+ (instancetype)composeQuoteOf:(CHTweet *)tweet;
@end

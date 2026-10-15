#import <UIKit/UIKit.h>
#import "CHModels.h"

// Opens links. A twitter.com / x.com link is handled inside the app (a tweet, a profile, a search); anything else
// goes to a sister app or a browser through CHExternalOpen. Web links in tweet text are routed here by CHLinkLabel.
@interface CHLinkRouter : NSObject

+ (UIViewController *)topController;
// Push a page onto the current navigation stack (a tab's, or a sliding page stack over the root when there is none)
+ (void)push:(UIViewController *)page;

// A twitter.com / x.com link, a bare tweet id or a bare @handle -> opens the right page; NO when it is not one of ours
+ (BOOL)openLink:(NSString *)link;

+ (void)openTweet:(CHTweet *)tweet;       // a tweet already in hand (shows at once, loads its thread)
+ (void)openTweetId:(NSString *)tweetId;
+ (void)openProfile:(NSString *)handle;
+ (void)openSearch:(NSString *)query;
+ (void)openHashtag:(NSString *)tag;

// A web link from a tweet: a Twitter link opens in the app, the rest through the chooser (sister apps / browser)
+ (void)openWebLink:(id)link from:(UIViewController *)controller anchor:(UIView *)anchor;
+ (void)openWebLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor;

@end

#import <Foundation/Foundation.h>
#import "CHModels.h"

@class CHHTTPTask;

// Talks to the Pi helper (the only server this app needs). The helper signs in to X once with your account and
// turns its answers into the small JSON these methods parse. All completions run on the main thread.
@interface CHTwitter : NSObject

+ (BOOL)configured;                          // a server base URL is set
+ (void)checkHealth:(void (^)(BOOL ok, NSString *info, NSError *error))completion;
+ (NSString *)accountHandle;                 // the signed-in @handle once /health has reported it, else nil

// The home timeline. `following` = the Following feed rather than For You. `cursor` is a page's bottomCursor (nil =
// the top).
+ (CHHTTPTask *)homeTimelineFollowing:(BOOL)following cursor:(NSString *)cursor
                           completion:(void (^)(CHTweetPage *page, NSError *error))completion;

// A person's profile (who they are; their tweets come from -tweetsOfUser…)
+ (CHHTTPTask *)userWithHandle:(NSString *)handle completion:(void (^)(CHUser *user, NSError *error))completion;

// A person's tweets. `kind`: "tweets" (and retweets), "replies", "media", "likes". Pass the handle; userId helps
// the helper skip a lookup when you have it.
+ (CHHTTPTask *)tweetsOfUser:(NSString *)handle userId:(NSString *)userId kind:(NSString *)kind cursor:(NSString *)cursor
                  completion:(void (^)(CHTweetPage *page, NSError *error))completion;

// One tweet with its thread: the reply chain above it and the replies below.
+ (CHHTTPTask *)threadForTweet:(NSString *)tweetId cursor:(NSString *)cursor
                    completion:(void (^)(CHThread *thread, NSError *error))completion;

// One tweet on its own (opening a link)
+ (CHHTTPTask *)tweetWithId:(NSString *)tweetId completion:(void (^)(CHTweet *tweet, NSError *error))completion;

// Search. `kind`: "top", "latest", "people". `cursor` = a page's bottomCursor.
+ (CHHTTPTask *)search:(NSString *)query kind:(NSString *)kind cursor:(NSString *)cursor
            completion:(void (^)(CHTweetPage *page, NSError *error))completion;

// What X suggests while typing a search
+ (CHHTTPTask *)suggestionsFor:(NSString *)text completion:(void (^)(NSArray *words, NSError *error))completion;

// Explore trends (CHTrend)
+ (CHHTTPTask *)trends:(void (^)(NSArray *trends, NSError *error))completion;

// The signed-in account's bookmarks (X server-side), newest first
+ (CHHTTPTask *)bookmarks:(NSString *)cursor completion:(void (^)(CHTweetPage *page, NSError *error))completion;

// Notifications. `kind`: "all", "mentions", "verified". Completion gets CHNotification items + the next cursor.
+ (CHHTTPTask *)notifications:(NSString *)kind cursor:(NSString *)cursor
                   completion:(void (^)(NSArray *items, NSString *cursor, BOOL hasMore, NSError *error))completion;

// A person's followers / the people they follow (page.users)
+ (CHHTTPTask *)followersOf:(NSString *)handle userId:(NSString *)userId following:(BOOL)following cursor:(NSString *)cursor
                 completion:(void (^)(CHTweetPage *page, NSError *error))completion;

#pragma mark - Actions (write; the helper performs them as your account)

// action: like, unlike, retweet, unretweet, bookmark, unbookmark, delete (a tweet id); follow, unfollow (a user id)
+ (CHHTTPTask *)performAction:(NSString *)action onId:(NSString *)objId completion:(void (^)(BOOL ok, NSError *error))completion;

// Post a tweet / reply / quote, with an optional single image. replyToId or quoteURL may be nil.
+ (void)postText:(NSString *)text replyTo:(NSString *)replyToId quoteURL:(NSString *)quoteURL
       imageData:(NSData *)imageData imageType:(NSString *)imageType completion:(void (^)(NSString *newId, NSError *error))completion;

#pragma mark - Direct messages

// The inbox (best effort; `supported` is NO when the helper cannot list conversations). Items are NSDictionary:
// @{ @"user": CHUser, @"last": NSString, @"time": NSNumber }.
+ (CHHTTPTask *)dmConversations:(void (^)(NSArray *items, BOOL supported, NSError *error))completion;

// The messages of one conversation (CHMessage), oldest or newest as X gives them
+ (CHHTTPTask *)dmHistoryWith:(NSString *)handle userId:(NSString *)userId cursor:(NSString *)cursor
                   completion:(void (^)(NSArray *messages, NSString *userId, NSString *cursor, BOOL hasMore, NSError *error))completion;

+ (void)sendDM:(NSString *)text to:(NSString *)handle userId:(NSString *)userId
    completion:(void (^)(CHMessage *message, NSString *userId, NSError *error))completion;

// The Pi /proxy URL that streams a media URL's bytes through the Pi (for TLS iOS 6 cannot do, and away from home)
+ (NSString *)proxyURLForMediaURL:(NSString *)url;

@end

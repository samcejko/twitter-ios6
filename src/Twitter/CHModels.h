#import <Foundation/Foundation.h>

// The data the Pi helper hands the app, as objects. IDs are kept as strings everywhere: a tweet or user id is a
// 19-digit snowflake that does not fit a 32-bit NSInteger (armv7). Counts are long long (a viral tweet's view count
// passes two billion).

@class CHUser;

// One photo, video or animated GIF attached to a tweet. For a video/GIF the helper has already chosen an MP4
// rendition iOS 6 can play (`url`); `preview` is the still shown before playback.
@interface CHMedia : NSObject
@property (nonatomic, copy) NSString *type;          // "photo", "video", "gif"
@property (nonatomic, copy) NSString *url;           // photo: the JPEG; video/gif: a playable MP4
@property (nonatomic, copy) NSString *previewURL;    // the still / thumbnail
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) NSTimeInterval duration;       // video/gif length in seconds, 0 for a photo
@property (nonatomic, copy) NSString *alt;           // the author's description, if any
@property (nonatomic, readonly) BOOL isPhoto;
@property (nonatomic, readonly) BOOL isVideo;        // a video or a GIF (both play)
+ (instancetype)mediaFromJSON:(NSDictionary *)json;
@end

// A person. Also a profile page (its tweets come from a separate call).
@interface CHUser : NSObject
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *handle;        // the @name without the @
@property (nonatomic, copy) NSString *name;          // display name
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *bannerURL;
@property (nonatomic) BOOL verified;
@property (nonatomic) BOOL isProtected;              // a locked account
@property (nonatomic) long long followers;
@property (nonatomic) long long following;
@property (nonatomic) long long tweetCount;
@property (nonatomic) long long likeCount;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, copy) NSString *website;       // the link in their bio, expanded
@property (nonatomic) NSTimeInterval joined;         // when the account was created (Unix), 0 = unknown
@property (nonatomic, copy) NSString *pinnedTweetId;
@property (nonatomic) BOOL isFollowing;              // the signed-in account follows them
@property (nonatomic) BOOL followsYou;               // they follow the signed-in account
+ (instancetype)userFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;
- (NSString *)shareURL;                               // https://twitter.com/<handle>
@end

// One tweet. A retweet is flattened: the fields are the original tweet's and `retweetedByName`/`retweetedByHandle`
// say who retweeted it. A quote tweet carries the quoted tweet in `quoted`.
@interface CHTweet : NSObject
@property (nonatomic, copy) NSString *tweetId;
@property (nonatomic, strong) CHUser *author;
@property (nonatomic, copy) NSString *text;          // t.co links expanded, trailing media/quote links removed
@property (nonatomic) NSTimeInterval createdAt;      // Unix time, 0 = unknown
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) long long replyCount;
@property (nonatomic) long long retweetCount;
@property (nonatomic) long long likeCount;
@property (nonatomic) long long quoteCount;
@property (nonatomic) long long viewCount;           // impressions, 0 = not given
@property (nonatomic) BOOL sensitive;
@property (nonatomic) BOOL pinned;                   // shown pinned on a profile
@property (nonatomic) BOOL favorited;                // the signed-in account liked it
@property (nonatomic) BOOL retweeted;                // ...reposted it
@property (nonatomic) BOOL bookmarked;               // ...bookmarked it
@property (nonatomic, copy) NSString *conversationId;
@property (nonatomic, copy) NSString *replyToId;     // the tweet this one replies to, if any
@property (nonatomic, copy) NSString *replyToHandle;
@property (nonatomic, copy) NSString *retweetedByName;
@property (nonatomic, copy) NSString *retweetedByHandle;
@property (nonatomic, copy) NSArray *media;          // CHMedia
@property (nonatomic, strong) CHTweet *quoted;       // the quoted tweet, or nil
// A link-preview card (a plain link, no media/quote): nil unless present
@property (nonatomic, copy) NSString *cardTitle;
@property (nonatomic, copy) NSString *cardDescription;
@property (nonatomic, copy) NSString *cardDomain;
@property (nonatomic, copy) NSString *cardImageURL;

@property (nonatomic, readonly) BOOL isRetweet;
@property (nonatomic, readonly) BOOL hasCard;
@property (nonatomic, readonly) NSString *shareURL;  // https://twitter.com/<handle>/status/<id>

+ (instancetype)tweetFromJSON:(NSDictionary *)json;
+ (NSArray *)tweetsFromArray:(NSArray *)array;
- (NSDictionary *)toJSON;                             // for the saved store
@end

// One page of a list: a timeline, a profile's tweets, search results. Cursors are opaque strings.
@interface CHTweetPage : NSObject
@property (nonatomic, copy) NSArray *tweets;          // CHTweet
@property (nonatomic, copy) NSArray *users;           // CHUser (people search)
@property (nonatomic, copy) NSString *topCursor;      // newer than these
@property (nonatomic, copy) NSString *bottomCursor;   // older than these (nil / empty = no more)
@property (nonatomic) BOOL hasMore;
+ (instancetype)pageFromJSON:(NSDictionary *)json;
@end

// A tweet with its context: the reply chain above it (oldest first) and the replies below it.
@interface CHThread : NSObject
@property (nonatomic, strong) CHTweet *tweet;
@property (nonatomic, copy) NSArray *ancestors;       // CHTweet, oldest first
@property (nonatomic, copy) NSArray *replies;         // CHTweet
@property (nonatomic, copy) NSString *cursor;         // more replies
@property (nonatomic) BOOL hasMore;
+ (instancetype)threadFromJSON:(NSDictionary *)json;
@end

// One notification (a like, a repost, a follow, a mention, a reply…)
@interface CHNotification : NSObject
@property (nonatomic, copy) NSString *notificationId;
@property (nonatomic, copy) NSString *iconType;       // "heart_icon", "retweet_icon", "person_icon", "bird_icon"…
@property (nonatomic, copy) NSString *text;           // "X and 3 others liked your tweet"
@property (nonatomic) NSTimeInterval createdAt;
@property (nonatomic, copy) NSArray *users;           // CHUser (who triggered it)
@property (nonatomic, strong) CHTweet *tweet;         // the tweet it is about, or nil (e.g. a follow)
+ (instancetype)notificationFromJSON:(NSDictionary *)json;
@end

// One direct message in a conversation
@interface CHMessage : NSObject
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSTimeInterval createdAt;
@property (nonatomic, copy) NSString *senderId;
@property (nonatomic) BOOL fromMe;
+ (instancetype)messageFromJSON:(NSDictionary *)json;
@end

// A trend in Explore
@interface CHTrend : NSObject
@property (nonatomic, copy) NSString *name;           // "#WorldCup" or a phrase
@property (nonatomic, copy) NSString *query;          // what to search for it
@property (nonatomic) long long volume;               // tweet count, 0 = not given
@property (nonatomic, copy) NSString *context;        // "Trending in Czechia", a category, …
+ (instancetype)trendFromJSON:(NSDictionary *)json;
@end

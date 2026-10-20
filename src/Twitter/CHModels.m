#import "CHLegacyCollections.h"
#import "CHModels.h"
#import "CHCommon.h"

// Counts can exceed a 32-bit NSInteger on armv7, so read them as double (exact for integers below 2^53) -> long long.
static long long CHLL(id value) { return (long long)CHDbl(value); }

@implementation CHMedia

+ (instancetype)mediaFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    if (!d.count) return nil;
    CHMedia *m = [[CHMedia alloc] init];
    m.type = CHStr([d objectForKey:@"type"]) ?: @"photo";
    m.url = CHStr([d objectForKey:@"url"]);
    m.previewURL = CHStr([d objectForKey:@"preview"]);
    m.width = CHInt([d objectForKey:@"w"]);
    m.height = CHInt([d objectForKey:@"h"]);
    m.duration = CHDbl([d objectForKey:@"duration"]);
    m.alt = CHStr([d objectForKey:@"alt"]);
    return m;
}

- (BOOL)isPhoto { return [self.type isEqualToString:@"photo"]; }
- (BOOL)isVideo { return [self.type isEqualToString:@"video"] || [self.type isEqualToString:@"gif"]; }

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    CHLegacyDictionarySet(d, @"type", self.type ?: @"photo");
    if (self.url) CHLegacyDictionarySet(d, @"url", self.url);
    if (self.previewURL) CHLegacyDictionarySet(d, @"preview", self.previewURL);
    CHLegacyDictionarySet(d, @"w", @(self.width));
    CHLegacyDictionarySet(d, @"h", @(self.height));
    if (self.duration > 0) CHLegacyDictionarySet(d, @"duration", @(self.duration));
    if (self.alt.length) CHLegacyDictionarySet(d, @"alt", self.alt);
    return d;
}

@end

@implementation CHUser

+ (instancetype)userFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    if (!d.count) return nil;
    CHUser *u = [[CHUser alloc] init];
    u.userId = CHStr([d objectForKey:@"id"]);
    u.handle = CHStr([d objectForKey:@"handle"]);
    u.name = CHStr([d objectForKey:@"name"]) ?: u.handle;
    u.bio = CHStr([d objectForKey:@"bio"]);
    u.avatarURL = CHStr([d objectForKey:@"avatar"]);
    u.bannerURL = CHStr([d objectForKey:@"banner"]);
    u.verified = CHBool([d objectForKey:@"verified"]);
    u.isProtected = CHBool([d objectForKey:@"protected"]);
    u.followers = CHLL([d objectForKey:@"followers"]);
    u.following = CHLL([d objectForKey:@"following"]);
    u.tweetCount = CHLL([d objectForKey:@"tweets"]);
    u.likeCount = CHLL([d objectForKey:@"likes"]);
    u.location = CHStr([d objectForKey:@"location"]);
    u.website = CHStr([d objectForKey:@"url"]);
    u.joined = CHDbl([d objectForKey:@"created"]);
    u.pinnedTweetId = CHStr([d objectForKey:@"pinnedId"]);
    u.isFollowing = CHBool([d objectForKey:@"isFollowing"]);
    u.followsYou = CHBool([d objectForKey:@"followsYou"]);
    return u.handle.length || u.name.length ? u : nil;
}

- (NSString *)shareURL
{
    return self.handle.length ? [@"https://twitter.com/" stringByAppendingString:self.handle] : @"";
}

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.userId) CHLegacyDictionarySet(d, @"id", self.userId);
    if (self.handle) CHLegacyDictionarySet(d, @"handle", self.handle);
    if (self.name) CHLegacyDictionarySet(d, @"name", self.name);
    if (self.bio) CHLegacyDictionarySet(d, @"bio", self.bio);
    if (self.avatarURL) CHLegacyDictionarySet(d, @"avatar", self.avatarURL);
    if (self.bannerURL) CHLegacyDictionarySet(d, @"banner", self.bannerURL);
    CHLegacyDictionarySet(d, @"verified", @(self.verified));
    CHLegacyDictionarySet(d, @"protected", @(self.isProtected));
    CHLegacyDictionarySet(d, @"followers", @(self.followers));
    CHLegacyDictionarySet(d, @"following", @(self.following));
    CHLegacyDictionarySet(d, @"tweets", @(self.tweetCount));
    CHLegacyDictionarySet(d, @"likes", @(self.likeCount));
    if (self.location) CHLegacyDictionarySet(d, @"location", self.location);
    if (self.website) CHLegacyDictionarySet(d, @"url", self.website);
    if (self.joined > 0) CHLegacyDictionarySet(d, @"created", @(self.joined));
    if (self.pinnedTweetId) CHLegacyDictionarySet(d, @"pinnedId", self.pinnedTweetId);
    return d;
}

@end

@implementation CHTweet

+ (instancetype)tweetFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    if (!CHStr([d objectForKey:@"id"]).length) return nil;
    CHTweet *t = [[CHTweet alloc] init];
    t.tweetId = CHStr([d objectForKey:@"id"]);
    t.author = [CHUser userFromJSON:[d objectForKey:@"author"]];
    t.text = CHStr([d objectForKey:@"text"]) ?: @"";
    t.createdAt = CHDbl([d objectForKey:@"created"]);
    t.lang = CHStr([d objectForKey:@"lang"]);
    t.replyCount = CHLL([d objectForKey:@"replies"]);
    t.retweetCount = CHLL([d objectForKey:@"retweets"]);
    t.likeCount = CHLL([d objectForKey:@"likes"]);
    t.quoteCount = CHLL([d objectForKey:@"quotes"]);
    t.viewCount = CHLL([d objectForKey:@"views"]);
    t.sensitive = CHBool([d objectForKey:@"sensitive"]);
    t.pinned = CHBool([d objectForKey:@"pinned"]);
    t.favorited = CHBool([d objectForKey:@"favorited"]);
    t.retweeted = CHBool([d objectForKey:@"retweeted"]);
    t.bookmarked = CHBool([d objectForKey:@"bookmarked"]);
    t.conversationId = CHStr([d objectForKey:@"conversationId"]);
    t.replyToId = CHStr([d objectForKey:@"replyToId"]);
    t.replyToHandle = CHStr([d objectForKey:@"replyToHandle"]);
    NSDictionary *rt = CHDict([d objectForKey:@"retweetedBy"]);
    if (rt.count) { t.retweetedByName = CHStr([rt objectForKey:@"name"]); t.retweetedByHandle = CHStr([rt objectForKey:@"handle"]); }
    NSMutableArray *media = [NSMutableArray array];
    for (id m in CHArr([d objectForKey:@"media"])) { CHMedia *mm = [CHMedia mediaFromJSON:m]; if (mm) [media addObject:mm]; }
    t.media = media;
    if (CHDict([d objectForKey:@"quoted"]).count) t.quoted = [CHTweet tweetFromJSON:[d objectForKey:@"quoted"]];
    NSDictionary *card = CHDict([d objectForKey:@"card"]);
    if (card.count) {
        t.cardTitle = CHStr([card objectForKey:@"title"]);
        t.cardDescription = CHStr([card objectForKey:@"desc"]);
        t.cardDomain = CHStr([card objectForKey:@"domain"]);
        t.cardImageURL = CHStr([card objectForKey:@"image"]);
    }
    return t;
}

+ (NSArray *)tweetsFromArray:(NSArray *)array
{
    NSMutableArray *out = [NSMutableArray array];
    for (id j in CHArr(array)) { CHTweet *t = [CHTweet tweetFromJSON:j]; if (t) [out addObject:t]; }
    return out;
}

- (BOOL)isRetweet { return self.retweetedByHandle.length > 0 || self.retweetedByName.length > 0; }
- (BOOL)hasCard { return self.cardTitle.length > 0 && !self.media.count && !self.quoted; }

- (NSString *)shareURL
{
    NSString *handle = self.author.handle.length ? self.author.handle : @"i";
    return self.tweetId.length ? [NSString stringWithFormat:@"https://twitter.com/%@/status/%@", handle, self.tweetId] : @"";
}

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    CHLegacyDictionarySet(d, @"id", self.tweetId ?: @"");
    if (self.author) CHLegacyDictionarySet(d, @"author", [self.author toJSON]);
    CHLegacyDictionarySet(d, @"text", self.text ?: @"");
    if (self.createdAt > 0) CHLegacyDictionarySet(d, @"created", @(self.createdAt));
    if (self.lang) CHLegacyDictionarySet(d, @"lang", self.lang);
    CHLegacyDictionarySet(d, @"replies", @(self.replyCount));
    CHLegacyDictionarySet(d, @"retweets", @(self.retweetCount));
    CHLegacyDictionarySet(d, @"likes", @(self.likeCount));
    CHLegacyDictionarySet(d, @"quotes", @(self.quoteCount));
    if (self.viewCount > 0) CHLegacyDictionarySet(d, @"views", @(self.viewCount));
    CHLegacyDictionarySet(d, @"sensitive", @(self.sensitive));
    if (self.conversationId) CHLegacyDictionarySet(d, @"conversationId", self.conversationId);
    if (self.replyToId) CHLegacyDictionarySet(d, @"replyToId", self.replyToId);
    if (self.replyToHandle) CHLegacyDictionarySet(d, @"replyToHandle", self.replyToHandle);
    if (self.isRetweet) CHLegacyDictionarySet(d, @"retweetedBy", @{ @"name": self.retweetedByName ?: @"", @"handle": self.retweetedByHandle ?: @"" });
    if (self.media.count) {
        NSMutableArray *media = [NSMutableArray array];
        for (CHMedia *m in self.media) [media addObject:[m toJSON]];
        CHLegacyDictionarySet(d, @"media", media);
    }
    if (self.quoted) CHLegacyDictionarySet(d, @"quoted", [self.quoted toJSON]);
    if (self.cardTitle.length) CHLegacyDictionarySet(d, @"card", @{ @"title": self.cardTitle ?: @"", @"desc": self.cardDescription ?: @"",
                                               @"domain": self.cardDomain ?: @"", @"image": self.cardImageURL ?: @"" });
    return d;
}

@end

@implementation CHTweetPage

+ (instancetype)pageFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHTweetPage *p = [[CHTweetPage alloc] init];
    p.tweets = [CHTweet tweetsFromArray:[d objectForKey:@"tweets"]];
    NSMutableArray *users = [NSMutableArray array];
    for (id u in CHArr([d objectForKey:@"users"])) { CHUser *uu = [CHUser userFromJSON:u]; if (uu) [users addObject:uu]; }
    p.users = users;
    p.topCursor = CHStr([d objectForKey:@"top"]);
    p.bottomCursor = CHStr([d objectForKey:@"bottom"]);
    p.hasMore = CHBool([d objectForKey:@"hasMore"]) && p.bottomCursor.length > 0;
    return p;
}

@end

@implementation CHThread

+ (instancetype)threadFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHThread *t = [[CHThread alloc] init];
    t.tweet = [CHTweet tweetFromJSON:[d objectForKey:@"tweet"]];
    t.ancestors = [CHTweet tweetsFromArray:[d objectForKey:@"ancestors"]];
    t.replies = [CHTweet tweetsFromArray:[d objectForKey:@"replies"]];
    t.cursor = CHStr([d objectForKey:@"cursor"]);
    t.hasMore = CHBool([d objectForKey:@"hasMore"]) && t.cursor.length > 0;
    return t;
}

@end

@implementation CHNotification

+ (instancetype)notificationFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHNotification *n = [[CHNotification alloc] init];
    n.notificationId = CHStr([d objectForKey:@"id"]);
    n.iconType = CHStr([d objectForKey:@"icon"]);
    n.text = CHStr([d objectForKey:@"text"]);
    n.createdAt = CHDbl([d objectForKey:@"time"]);
    NSMutableArray *users = [NSMutableArray array];
    for (id u in CHArr([d objectForKey:@"users"])) { CHUser *uu = [CHUser userFromJSON:u]; if (uu) [users addObject:uu]; }
    n.users = users;
    if (CHDict([d objectForKey:@"tweet"]).count) n.tweet = [CHTweet tweetFromJSON:[d objectForKey:@"tweet"]];
    return (n.text.length || n.tweet || n.users.count) ? n : nil;
}

@end

@implementation CHMessage

+ (instancetype)messageFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHMessage *m = [[CHMessage alloc] init];
    m.messageId = CHStr([d objectForKey:@"id"]);
    m.text = CHStr([d objectForKey:@"text"]);
    m.createdAt = CHDbl([d objectForKey:@"time"]);
    m.senderId = CHStr([d objectForKey:@"senderId"]);
    m.fromMe = CHBool([d objectForKey:@"fromMe"]);
    return m.messageId.length ? m : nil;
}

@end

@implementation CHTrend

+ (instancetype)trendFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    NSString *name = CHStr([d objectForKey:@"name"]);
    if (!name.length) return nil;
    CHTrend *t = [[CHTrend alloc] init];
    t.name = name;
    t.query = CHStr([d objectForKey:@"query"]) ?: name;
    t.volume = CHLL([d objectForKey:@"volume"]);
    t.context = CHStr([d objectForKey:@"context"]);
    return t;
}

@end

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
    m.type = CHStr(d[@"type"]) ?: @"photo";
    m.url = CHStr(d[@"url"]);
    m.previewURL = CHStr(d[@"preview"]);
    m.width = CHInt(d[@"w"]);
    m.height = CHInt(d[@"h"]);
    m.duration = CHDbl(d[@"duration"]);
    m.alt = CHStr(d[@"alt"]);
    return m;
}

- (BOOL)isPhoto { return [self.type isEqualToString:@"photo"]; }
- (BOOL)isVideo { return [self.type isEqualToString:@"video"] || [self.type isEqualToString:@"gif"]; }

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"type"] = self.type ?: @"photo";
    if (self.url) d[@"url"] = self.url;
    if (self.previewURL) d[@"preview"] = self.previewURL;
    d[@"w"] = @(self.width);
    d[@"h"] = @(self.height);
    if (self.duration > 0) d[@"duration"] = @(self.duration);
    if (self.alt.length) d[@"alt"] = self.alt;
    return d;
}

@end

@implementation CHUser

+ (instancetype)userFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    if (!d.count) return nil;
    CHUser *u = [[CHUser alloc] init];
    u.userId = CHStr(d[@"id"]);
    u.handle = CHStr(d[@"handle"]);
    u.name = CHStr(d[@"name"]) ?: u.handle;
    u.bio = CHStr(d[@"bio"]);
    u.avatarURL = CHStr(d[@"avatar"]);
    u.bannerURL = CHStr(d[@"banner"]);
    u.verified = CHBool(d[@"verified"]);
    u.isProtected = CHBool(d[@"protected"]);
    u.followers = CHLL(d[@"followers"]);
    u.following = CHLL(d[@"following"]);
    u.tweetCount = CHLL(d[@"tweets"]);
    u.likeCount = CHLL(d[@"likes"]);
    u.location = CHStr(d[@"location"]);
    u.website = CHStr(d[@"url"]);
    u.joined = CHDbl(d[@"created"]);
    u.pinnedTweetId = CHStr(d[@"pinnedId"]);
    return u.handle.length || u.name.length ? u : nil;
}

- (NSString *)shareURL
{
    return self.handle.length ? [@"https://twitter.com/" stringByAppendingString:self.handle] : @"";
}

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.userId) d[@"id"] = self.userId;
    if (self.handle) d[@"handle"] = self.handle;
    if (self.name) d[@"name"] = self.name;
    if (self.bio) d[@"bio"] = self.bio;
    if (self.avatarURL) d[@"avatar"] = self.avatarURL;
    if (self.bannerURL) d[@"banner"] = self.bannerURL;
    d[@"verified"] = @(self.verified);
    d[@"protected"] = @(self.isProtected);
    d[@"followers"] = @(self.followers);
    d[@"following"] = @(self.following);
    d[@"tweets"] = @(self.tweetCount);
    d[@"likes"] = @(self.likeCount);
    if (self.location) d[@"location"] = self.location;
    if (self.website) d[@"url"] = self.website;
    if (self.joined > 0) d[@"created"] = @(self.joined);
    if (self.pinnedTweetId) d[@"pinnedId"] = self.pinnedTweetId;
    return d;
}

@end

@implementation CHTweet

+ (instancetype)tweetFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    if (!CHStr(d[@"id"]).length) return nil;
    CHTweet *t = [[CHTweet alloc] init];
    t.tweetId = CHStr(d[@"id"]);
    t.author = [CHUser userFromJSON:d[@"author"]];
    t.text = CHStr(d[@"text"]) ?: @"";
    t.createdAt = CHDbl(d[@"created"]);
    t.lang = CHStr(d[@"lang"]);
    t.replyCount = CHLL(d[@"replies"]);
    t.retweetCount = CHLL(d[@"retweets"]);
    t.likeCount = CHLL(d[@"likes"]);
    t.quoteCount = CHLL(d[@"quotes"]);
    t.viewCount = CHLL(d[@"views"]);
    t.sensitive = CHBool(d[@"sensitive"]);
    t.pinned = CHBool(d[@"pinned"]);
    t.conversationId = CHStr(d[@"conversationId"]);
    t.replyToId = CHStr(d[@"replyToId"]);
    t.replyToHandle = CHStr(d[@"replyToHandle"]);
    NSDictionary *rt = CHDict(d[@"retweetedBy"]);
    if (rt.count) { t.retweetedByName = CHStr(rt[@"name"]); t.retweetedByHandle = CHStr(rt[@"handle"]); }
    NSMutableArray *media = [NSMutableArray array];
    for (id m in CHArr(d[@"media"])) { CHMedia *mm = [CHMedia mediaFromJSON:m]; if (mm) [media addObject:mm]; }
    t.media = media;
    if (CHDict(d[@"quoted"]).count) t.quoted = [CHTweet tweetFromJSON:d[@"quoted"]];
    NSDictionary *card = CHDict(d[@"card"]);
    if (card.count) {
        t.cardTitle = CHStr(card[@"title"]);
        t.cardDescription = CHStr(card[@"desc"]);
        t.cardDomain = CHStr(card[@"domain"]);
        t.cardImageURL = CHStr(card[@"image"]);
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
    d[@"id"] = self.tweetId ?: @"";
    if (self.author) d[@"author"] = [self.author toJSON];
    d[@"text"] = self.text ?: @"";
    if (self.createdAt > 0) d[@"created"] = @(self.createdAt);
    if (self.lang) d[@"lang"] = self.lang;
    d[@"replies"] = @(self.replyCount);
    d[@"retweets"] = @(self.retweetCount);
    d[@"likes"] = @(self.likeCount);
    d[@"quotes"] = @(self.quoteCount);
    if (self.viewCount > 0) d[@"views"] = @(self.viewCount);
    d[@"sensitive"] = @(self.sensitive);
    if (self.conversationId) d[@"conversationId"] = self.conversationId;
    if (self.replyToId) d[@"replyToId"] = self.replyToId;
    if (self.replyToHandle) d[@"replyToHandle"] = self.replyToHandle;
    if (self.isRetweet) d[@"retweetedBy"] = @{ @"name": self.retweetedByName ?: @"", @"handle": self.retweetedByHandle ?: @"" };
    if (self.media.count) {
        NSMutableArray *media = [NSMutableArray array];
        for (CHMedia *m in self.media) [media addObject:[m toJSON]];
        d[@"media"] = media;
    }
    if (self.quoted) d[@"quoted"] = [self.quoted toJSON];
    if (self.cardTitle.length) d[@"card"] = @{ @"title": self.cardTitle ?: @"", @"desc": self.cardDescription ?: @"",
                                               @"domain": self.cardDomain ?: @"", @"image": self.cardImageURL ?: @"" };
    return d;
}

@end

@implementation CHTweetPage

+ (instancetype)pageFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHTweetPage *p = [[CHTweetPage alloc] init];
    p.tweets = [CHTweet tweetsFromArray:d[@"tweets"]];
    NSMutableArray *users = [NSMutableArray array];
    for (id u in CHArr(d[@"users"])) { CHUser *uu = [CHUser userFromJSON:u]; if (uu) [users addObject:uu]; }
    p.users = users;
    p.topCursor = CHStr(d[@"top"]);
    p.bottomCursor = CHStr(d[@"bottom"]);
    p.hasMore = CHBool(d[@"hasMore"]) && p.bottomCursor.length > 0;
    return p;
}

@end

@implementation CHThread

+ (instancetype)threadFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    CHThread *t = [[CHThread alloc] init];
    t.tweet = [CHTweet tweetFromJSON:d[@"tweet"]];
    t.ancestors = [CHTweet tweetsFromArray:d[@"ancestors"]];
    t.replies = [CHTweet tweetsFromArray:d[@"replies"]];
    t.cursor = CHStr(d[@"cursor"]);
    t.hasMore = CHBool(d[@"hasMore"]) && t.cursor.length > 0;
    return t;
}

@end

@implementation CHTrend

+ (instancetype)trendFromJSON:(NSDictionary *)json
{
    NSDictionary *d = CHDict(json);
    NSString *name = CHStr(d[@"name"]);
    if (!name.length) return nil;
    CHTrend *t = [[CHTrend alloc] init];
    t.name = name;
    t.query = CHStr(d[@"query"]) ?: name;
    t.volume = CHLL(d[@"volume"]);
    t.context = CHStr(d[@"context"]);
    return t;
}

@end

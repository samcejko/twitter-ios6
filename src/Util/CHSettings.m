#import "CHSettings.h"
#import "CHKeychain.h"
#import "CHCommon.h"

#define DEF [NSUserDefaults standardUserDefaults]
static NSString * const CHServerKeyName = @"chirpie.serverKey";
static NSString * const CHAuthName = @"chirpie.xAuthToken";
static NSString * const CHCSRFName = @"chirpie.xCSRF";
static const NSUInteger CHMaxSaved = 1000;

@implementation CHSettings

+ (void)registerDefaults
{
    [DEF registerDefaults:@{
        @"serverBaseURL": @"",
        @"streamThroughServer": @NO,
        @"followingTimeline": @NO,
        @"autoplayVideos": @NO,
        @"showSensitive": @NO,
        @"darkTheme": @NO,
        @"verifyTLS": @YES,
        @"searchHistory": @[],
        @"savedTweets": @[],
    }];
}

+ (void)save { [DEF synchronize]; }

+ (void)notify
{
    CHMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:CHSettingsDidChangeNotification object:nil]; });
}

+ (void)notifyLibrary
{
    CHMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:CHLibraryDidChangeNotification object:nil]; });
}

#pragma mark - Server

+ (NSString *)serverBaseURL
{
    NSString *s = [DEF stringForKey:@"serverBaseURL"] ?: @"";
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

+ (void)setServerBaseURL:(NSString *)value
{
    NSString *s = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (s.length && ![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) s = [@"https://" stringByAppendingString:s];
    [DEF setObject:s forKey:@"serverBaseURL"];
    [self notify];
}

+ (NSString *)serverKey { return [CHKeychain stringForKey:CHServerKeyName] ?: @""; }
+ (void)setServerKey:(NSString *)value { [CHKeychain setString:value forKey:CHServerKeyName]; }

+ (BOOL)serverConfigured { return [self serverBaseURL].length > 0; }

+ (NSString *)xAuthToken { return [CHKeychain stringForKey:CHAuthName] ?: @""; }
+ (void)setXAuthToken:(NSString *)value { [CHKeychain setString:value forKey:CHAuthName]; }
+ (NSString *)xCSRF { return [CHKeychain stringForKey:CHCSRFName] ?: @""; }
+ (void)setXCSRF:(NSString *)value { [CHKeychain setString:value forKey:CHCSRFName]; }
+ (BOOL)loggedIn { return [self xAuthToken].length > 0 && [self xCSRF].length > 0; }
+ (void)logOut { [self setXAuthToken:@""]; [self setXCSRF:@""]; [self notify]; }

+ (BOOL)streamThroughServer { return [DEF boolForKey:@"streamThroughServer"]; }
+ (void)setStreamThroughServer:(BOOL)value { [DEF setBool:value forKey:@"streamThroughServer"]; [self notify]; }

#pragma mark - Timeline / playback

+ (BOOL)followingTimeline { return [DEF boolForKey:@"followingTimeline"]; }
+ (void)setFollowingTimeline:(BOOL)value { [DEF setBool:value forKey:@"followingTimeline"]; [self save]; [self notify]; }
+ (BOOL)autoplayVideos { return [DEF boolForKey:@"autoplayVideos"]; }
+ (void)setAutoplayVideos:(BOOL)value { [DEF setBool:value forKey:@"autoplayVideos"]; [self notify]; }
+ (BOOL)showSensitive { return [DEF boolForKey:@"showSensitive"]; }
+ (void)setShowSensitive:(BOOL)value { [DEF setBool:value forKey:@"showSensitive"]; [self notify]; }

#pragma mark - Appearance / network

+ (BOOL)darkTheme { return [DEF boolForKey:@"darkTheme"]; }
+ (void)setDarkTheme:(BOOL)value { [DEF setBool:value forKey:@"darkTheme"]; }
+ (BOOL)verifyTLS { return [DEF boolForKey:@"verifyTLS"]; }
+ (void)setVerifyTLS:(BOOL)value { [DEF setBool:value forKey:@"verifyTLS"]; [self notify]; }

#pragma mark - Search history

+ (NSArray *)searchHistory
{
    NSMutableArray *out = [NSMutableArray array];
    for (id q in CHArr([DEF objectForKey:@"searchHistory"])) if (CHStr(q).length) [out addObject:CHStr(q)];
    return out;
}

+ (void)addSearch:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    NSMutableArray *list = [[self searchHistory] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--)
        if ([list[(NSUInteger)i] caseInsensitiveCompare:q] == NSOrderedSame) [list removeObjectAtIndex:(NSUInteger)i];
    [list insertObject:q atIndex:0];
    while (list.count > 20) [list removeLastObject];
    [DEF setObject:list forKey:@"searchHistory"];
}

+ (void)clearSearchHistory { [DEF setObject:@[] forKey:@"searchHistory"]; }

#pragma mark - Saved (bookmarked) tweets

+ (NSArray *)savedTweets { return [DEF arrayForKey:@"savedTweets"] ?: @[]; }

+ (BOOL)isSaved:(NSString *)tweetId
{
    if (!tweetId.length) return NO;
    for (NSDictionary *d in [self savedTweets]) if ([CHStr(d[@"id"]) isEqualToString:tweetId]) return YES;
    return NO;
}

+ (void)saveTweetJSON:(NSDictionary *)json
{
    NSString *tid = CHStr(json[@"id"]);
    if (!tid.length) return;
    NSMutableArray *list = [[self savedTweets] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--)
        if ([CHStr(list[(NSUInteger)i][@"id"]) isEqualToString:tid]) [list removeObjectAtIndex:(NSUInteger)i];
    [list insertObject:json atIndex:0];
    while (list.count > CHMaxSaved) [list removeLastObject];
    [DEF setObject:list forKey:@"savedTweets"];
    [self save];
    [self notifyLibrary];
}

+ (void)unsaveTweet:(NSString *)tweetId
{
    NSMutableArray *list = [[self savedTweets] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--)
        if ([CHStr(list[(NSUInteger)i][@"id"]) isEqualToString:tweetId]) [list removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:list forKey:@"savedTweets"];
    [self save];
    [self notifyLibrary];
}

@end

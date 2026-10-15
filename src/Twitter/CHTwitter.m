#import "CHTwitter.h"
#import "CHHTTP.h"
#import "CHSettings.h"
#import "CHUtils.h"
#import "CHCommon.h"

NSString * const CHNeedsLoginNotification = @"CHNeedsLoginNotification";

static NSString *g_account;

@implementation CHTwitter

+ (BOOL)configured { return [CHSettings serverConfigured]; }
+ (BOOL)loggedIn { return [CHSettings serverConfigured] && [CHSettings loggedIn]; }
+ (NSString *)accountHandle { return g_account.length ? g_account : nil; }

// The user's X cookies travel in headers (never in the URL); the server key stays a query param (in urlForPath)
+ (NSDictionary *)authHeaders
{
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    NSString *auth = [CHSettings xAuthToken], *ct0 = [CHSettings xCSRF];
    if (auth.length) h[@"X-Chirpie-Auth"] = auth;
    if (ct0.length) h[@"X-Chirpie-CT0"] = ct0;
    return h;
}

+ (void)noteIfNeedsLogin:(NSDictionary *)json status:(NSInteger)status
{
    if (status == 401 || CHBool(json[@"needsLogin"]))
        CHMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:CHNeedsLoginNotification object:nil]; });
}

// base URL + path + query (the server key goes on every call as ?k=)
+ (NSString *)urlForPath:(NSString *)path params:(NSDictionary *)params
{
    NSString *base = [CHSettings serverBaseURL];
    if (!base.length) return nil;
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in params) {
        id value = params[key];
        if (value == nil || value == [NSNull null]) continue;
        NSString *s = [value isKindOfClass:[NSString class]] ? value : [value description];
        if (!s.length) continue;
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, [CHUtils urlEncode:s]]];
    }
    NSString *url = [base stringByAppendingString:path];
    if (pairs.count) url = [url stringByAppendingFormat:@"?%@", [pairs componentsJoinedByString:@"&"]];
    return url;
}

// A GET to the helper. `error` is already set for network failures and for a helper error (code = HTTP status,
// message from the body's "error"); `json` is the parsed body (a dictionary) when there was one.
+ (CHHTTPTask *)get:(NSString *)path params:(NSDictionary *)params completion:(void (^)(NSDictionary *json, NSError *error))completion
{
    NSString *url = [self urlForPath:path params:params];
    if (!url) {
        CHMain(^{ if (completion) completion(nil, CHMakeError(CHErrorAPI, L(@"Set the server address in Settings first."))); });
        return nil;
    }
    if (![path isEqualToString:@"/health"] && ![CHSettings loggedIn]) {
        [self noteIfNeedsLogin:nil status:401];
        CHMain(^{ if (completion) completion(nil, CHMakeError(CHErrorAuth, L(@"Log in with your X account to continue."))); });
        return nil;
    }
    return [CHHTTP getJSON:url headers:[self authHeaders] completion:^(id json, NSInteger status, NSError *error) {
        NSDictionary *d = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        [self noteIfNeedsLogin:d status:status];
        NSError *err = error;
        if (!err && d[@"error"]) err = CHMakeError(status ?: CHErrorAPI, CHStr(d[@"error"]));
        if (completion) completion(d, err);
    }];
}

+ (void)checkHealth:(void (^)(BOOL ok, NSString *info, NSError *error))completion
{
    [self get:@"/health" params:nil completion:^(NSDictionary *json, NSError *error) {
        BOOL ok = !error && CHBool(json[@"ok"]);
        if (completion) completion(ok, nil, error);
    }];
}

+ (void)fetchMe:(void (^)(CHUser *user, NSError *error))completion
{
    [self get:@"/me" params:nil completion:^(NSDictionary *json, NSError *error) {
        CHUser *user = error ? nil : [CHUser userFromJSON:json[@"user"]];
        if (user.handle.length) g_account = user.handle;
        if (completion) completion(user, error);
    }];
}

+ (void)logInWithUsername:(NSString *)username password:(NSString *)password email:(NSString *)email totp:(NSString *)totp
               completion:(void (^)(CHUser *user, NSError *error))completion
{
    // POST /login directly (it needs no cookies yet, so it bypasses the usual logged-in guard)
    NSString *url = [self urlForPath:@"/login" params:nil];
    if (!url) { CHMain(^{ if (completion) completion(nil, CHMakeError(CHErrorAPI, L(@"Set the server address in Settings first."))); }); return; }
    NSDictionary *body = @{ @"username": username ?: @"", @"password": password ?: @"", @"email": email ?: @"", @"totp": totp ?: @"" };
    [CHHTTP postJSON:url headers:[self authHeaders] object:body retries:0 completion:^(id json, NSInteger status, NSError *error) {
        NSDictionary *d = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        NSString *auth = CHStr(d[@"auth_token"]), *ct0 = CHStr(d[@"ct0"]);
        if (auth.length && ct0.length) {
            [CHSettings setXAuthToken:auth];
            [CHSettings setXCSRF:ct0];
            [CHSettings save];
            CHUser *user = [CHUser userFromJSON:d[@"user"]];
            if (user.handle.length) g_account = user.handle;
            if (completion) completion(user, nil);
        } else {
            NSError *err = error ?: CHMakeError(status ?: CHErrorAuth, CHStr(d[@"error"]) ?: L(@"Those details did not work."));
            if (completion) completion(nil, err);
        }
    }];
}

#pragma mark - Timelines

+ (CHHTTPTask *)homeTimelineFollowing:(BOOL)following cursor:(NSString *)cursor
                           completion:(void (^)(CHTweetPage *, NSError *))completion
{
    NSDictionary *params = @{ @"feed": following ? @"following" : @"foryou", @"cursor": cursor ?: @"" };
    return [self get:@"/timeline" params:params completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(error ? nil : [CHTweetPage pageFromJSON:json], error);
    }];
}

+ (CHHTTPTask *)userWithHandle:(NSString *)handle completion:(void (^)(CHUser *, NSError *))completion
{
    NSString *name = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    return [self get:@"/user" params:@{ @"name": name ?: @"" } completion:^(NSDictionary *json, NSError *error) {
        CHUser *user = error ? nil : [CHUser userFromJSON:json[@"user"] ?: json];
        if (!error && !user) error = CHMakeError(CHErrorAPI, L(@"This profile could not be loaded."));
        if (completion) completion(user, error);
    }];
}

+ (CHHTTPTask *)tweetsOfUser:(NSString *)handle userId:(NSString *)userId kind:(NSString *)kind cursor:(NSString *)cursor
                  completion:(void (^)(CHTweetPage *, NSError *))completion
{
    NSString *name = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSDictionary *params = @{ @"name": name ?: @"", @"id": userId ?: @"", @"kind": kind ?: @"tweets", @"cursor": cursor ?: @"" };
    return [self get:@"/tweets" params:params completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(error ? nil : [CHTweetPage pageFromJSON:json], error);
    }];
}

#pragma mark - A tweet and its thread

+ (CHHTTPTask *)threadForTweet:(NSString *)tweetId cursor:(NSString *)cursor
                    completion:(void (^)(CHThread *, NSError *))completion
{
    NSDictionary *params = @{ @"id": tweetId ?: @"", @"cursor": cursor ?: @"" };
    return [self get:@"/tweet" params:params completion:^(NSDictionary *json, NSError *error) {
        CHThread *thread = error ? nil : [CHThread threadFromJSON:json];
        if (!error && !thread.tweet) error = CHMakeError(CHErrorAPI, L(@"This tweet could not be loaded."));
        if (completion) completion(thread, error);
    }];
}

+ (CHHTTPTask *)tweetWithId:(NSString *)tweetId completion:(void (^)(CHTweet *, NSError *))completion
{
    return [self threadForTweet:tweetId cursor:nil completion:^(CHThread *thread, NSError *error) {
        if (completion) completion(thread.tweet, error);
    }];
}

#pragma mark - Search

+ (CHHTTPTask *)search:(NSString *)query kind:(NSString *)kind cursor:(NSString *)cursor
            completion:(void (^)(CHTweetPage *, NSError *))completion
{
    NSDictionary *params = @{ @"q": query ?: @"", @"kind": kind ?: @"top", @"cursor": cursor ?: @"" };
    return [self get:@"/search" params:params completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(error ? nil : [CHTweetPage pageFromJSON:json], error);
    }];
}

+ (CHHTTPTask *)suggestionsFor:(NSString *)text completion:(void (^)(NSArray *, NSError *))completion
{
    return [self get:@"/suggest" params:@{ @"q": text ?: @"" } completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *words = [NSMutableArray array];
        for (id w in CHArr(json[@"items"])) if (CHStr(w).length) [words addObject:CHStr(w)];
        if (completion) completion(words, error);
    }];
}

#pragma mark - Explore

+ (CHHTTPTask *)trends:(void (^)(NSArray *, NSError *))completion
{
    return [self get:@"/trends" params:nil completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *trends = [NSMutableArray array];
        for (id t in CHArr(json[@"items"])) { CHTrend *tr = [CHTrend trendFromJSON:t]; if (tr) [trends addObject:tr]; }
        if (completion) completion(trends, error);
    }];
}

+ (CHHTTPTask *)bookmarks:(NSString *)cursor completion:(void (^)(CHTweetPage *, NSError *))completion
{
    return [self get:@"/bookmarks" params:@{ @"cursor": cursor ?: @"" } completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(error ? nil : [CHTweetPage pageFromJSON:json], error);
    }];
}

+ (CHHTTPTask *)notifications:(NSString *)kind cursor:(NSString *)cursor
                   completion:(void (^)(NSArray *, NSString *, BOOL, NSError *))completion
{
    NSDictionary *params = @{ @"kind": kind ?: @"all", @"cursor": cursor ?: @"" };
    return [self get:@"/notifications" params:params completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *items = [NSMutableArray array];
        for (id n in CHArr(json[@"items"])) { CHNotification *nn = [CHNotification notificationFromJSON:n]; if (nn) [items addObject:nn]; }
        NSString *c = CHStr(json[@"bottom"]);
        if (completion) completion(items, c, CHBool(json[@"hasMore"]) && c.length > 0, error);
    }];
}

+ (CHHTTPTask *)followersOf:(NSString *)handle userId:(NSString *)userId following:(BOOL)following cursor:(NSString *)cursor
                 completion:(void (^)(CHTweetPage *, NSError *))completion
{
    NSString *name = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSDictionary *params = @{ @"name": name ?: @"", @"id": userId ?: @"", @"cursor": cursor ?: @"" };
    return [self get:(following ? @"/following" : @"/followers") params:params completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(error ? nil : [CHTweetPage pageFromJSON:json], error);
    }];
}

#pragma mark - Actions

+ (CHHTTPTask *)performAction:(NSString *)action onId:(NSString *)objId completion:(void (^)(BOOL, NSError *))completion
{
    return [self get:@"/action" params:@{ @"do": action ?: @"", @"id": objId ?: @"" } completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(!error && CHBool(json[@"ok"]), error);
    }];
}

+ (void)postJSON:(NSString *)path object:(NSDictionary *)object completion:(void (^)(NSDictionary *json, NSError *error))completion
{
    NSString *url = [self urlForPath:path params:nil];
    if (!url) { CHMain(^{ if (completion) completion(nil, CHMakeError(CHErrorAPI, L(@"Set the server address in Settings first."))); }); return; }
    if (![CHSettings loggedIn]) {
        [self noteIfNeedsLogin:nil status:401];
        CHMain(^{ if (completion) completion(nil, CHMakeError(CHErrorAuth, L(@"Log in with your X account to continue."))); });
        return;
    }
    [CHHTTP postJSON:url headers:[self authHeaders] object:object retries:0 completion:^(id json, NSInteger status, NSError *error) {
        NSDictionary *d = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        [self noteIfNeedsLogin:d status:status];
        NSError *err = error;
        if (!err && d[@"error"]) err = CHMakeError(status ?: CHErrorAPI, CHStr(d[@"error"]));
        if (completion) completion(d, err);
    }];
}

+ (void)postText:(NSString *)text replyTo:(NSString *)replyToId quoteURL:(NSString *)quoteURL
       imageData:(NSData *)imageData imageType:(NSString *)imageType completion:(void (^)(NSString *, NSError *))completion
{
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"text"] = text ?: @"";
    if (replyToId.length) body[@"replyTo"] = replyToId;
    if (quoteURL.length) body[@"quoteUrl"] = quoteURL;
    if (imageData.length) {
        body[@"imageB64"] = [CHUtils base64Encode:imageData];
        body[@"imageType"] = imageType ?: @"jpg";
    }
    [self postJSON:@"/post" object:body completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion(CHStr(json[@"id"]), error);
    }];
}

#pragma mark - Direct messages

+ (CHHTTPTask *)dmConversations:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [self get:@"/dm/list" params:nil completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *items = [NSMutableArray array];
        for (id c in CHArr(json[@"items"])) {
            NSDictionary *cd = CHDict(c);
            CHUser *u = [CHUser userFromJSON:cd[@"user"]];
            if (u) [items addObject:@{ @"user": u, @"last": CHStr(cd[@"last"]) ?: @"", @"time": @(CHDbl(cd[@"time"])) }];
        }
        if (completion) completion(items, CHBool(json[@"supported"]), error);
    }];
}

+ (CHHTTPTask *)dmHistoryWith:(NSString *)handle userId:(NSString *)userId cursor:(NSString *)cursor
                   completion:(void (^)(NSArray *, NSString *, NSString *, BOOL, NSError *))completion
{
    NSString *name = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSDictionary *params = @{ @"name": name ?: @"", @"id": userId ?: @"", @"cursor": cursor ?: @"" };
    return [self get:@"/dm/history" params:params completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *msgs = [NSMutableArray array];
        for (id m in CHArr(json[@"items"])) { CHMessage *mm = [CHMessage messageFromJSON:m]; if (mm) [msgs addObject:mm]; }
        if (completion) completion(msgs, CHStr(json[@"uid"]), CHStr(json[@"cursor"]), CHBool(json[@"hasMore"]), error);
    }];
}

+ (void)sendDM:(NSString *)text to:(NSString *)handle userId:(NSString *)userId
    completion:(void (^)(CHMessage *, NSString *, NSError *))completion
{
    NSString *name = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSDictionary *body = @{ @"text": text ?: @"", @"name": name ?: @"", @"id": userId ?: @"" };
    [self postJSON:@"/dm/send" object:body completion:^(NSDictionary *json, NSError *error) {
        if (completion) completion([CHMessage messageFromJSON:json[@"message"]], CHStr(json[@"uid"]), error);
    }];
}

#pragma mark - Media

+ (NSString *)proxyURLForMediaURL:(NSString *)url
{
    if (!url.length) return nil;
    return [self urlForPath:@"/proxy" params:@{ @"u": url }];
}

@end

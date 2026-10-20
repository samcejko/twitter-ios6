#import "CHLegacyCollections.h"
#import "CHHTTP.h"
#import "CHHTTPRequest.h"
#import "CHSettings.h"
#import "CHUtils.h"
#import "CHCommon.h"

static const NSInteger CHMaxRedirects = 5;

@interface CHHTTPTask ()
@property (atomic, strong) CHHTTPRequest *request;
@property (atomic) BOOL isCancelled;
@end

@implementation CHHTTPTask

- (void)cancel
{
    if (self.isCancelled) return;
    self.isCancelled = YES;
    [self.request cancel];
    dispatch_block_t block = self.cancelBlock;
    self.cancelBlock = nil;
    if (block) block();
}

@end

@implementation CHHTTP

+ (void)run:(CHHTTPTask *)task method:(NSString *)method url:(NSURL *)url headers:(NSDictionary *)headers body:(NSData *)body
       hops:(NSInteger)hops retries:(NSInteger)retries completion:(CHHTTPCompletion)completion
{
    CHHTTPRequest *r = [[CHHTTPRequest alloc] initWithMethod:method URL:url];
    r.headers = headers;
    r.body = body;
    r.connectTimeout = 15;
    r.readTimeout = 30;
    r.verifyTLS = [CHSettings verifyTLS];
    __weak CHHTTPRequest *weakRequest = r;
    r.onComplete = ^(NSError *error) {
        CHHTTPRequest *request = weakRequest;
        if (task.isCancelled) return;
        NSInteger status = request.statusCode;
        NSDictionary *responseHeaders = request.responseHeaders;
        if (!error && status >= 300 && status < 400 && status != 304 && hops < CHMaxRedirects) {
            NSString *location = [responseHeaders objectForKey:@"location"];
            NSURL *next = location.length ? [[NSURL URLWithString:location relativeToURL:url] absoluteURL] : nil;
            if (next.host.length) {
                BOOL safe = [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
                BOOL toGet = status == 303 || ((status == 301 || status == 302) && !safe);
                NSDictionary *nextHeaders = headers;
                if (![[next.host lowercaseString] isEqualToString:[url.host lowercaseString]]) {
                    // credentials stay with the host they were meant for
                    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
                    for (NSString *key in headers) {
                        NSString *lower = [key lowercaseString];
                        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"client-id"]) continue;
                        CHLegacyDictionarySet(trimmed, key, [headers objectForKey:key]);
                    }
                    nextHeaders = trimmed;
                }
                [self run:task method:toGet ? @"GET" : method url:next headers:nextHeaders body:toGet ? nil : body
                     hops:hops + 1 retries:retries completion:completion];
                return;
            }
        }
        if (error && retries > 0 && error.code != CHErrorCancelled && error.code != CHErrorCertificate) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (task.isCancelled) return;
                [self run:task method:method url:url headers:headers body:body hops:hops retries:retries - 1 completion:completion];
            });
            return;
        }
        NSData *responseBody = request.responseBody;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(error ? 0 : status, responseBody, responseHeaders, error);
        });
    };
    task.request = r;
    if (task.isCancelled) return;
    [r start];
}

+ (CHHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(CHHTTPCompletion)completion
{
    CHHTTPTask *task = [[CHHTTPTask alloc] init];
    NSURL *u = url.length ? [NSURL URLWithString:url] : nil;
    if (!u.host.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(0, nil, nil, CHMakeError(CHErrorNetwork, [NSString stringWithFormat:@"Bad address: %@", url ?: @""]));
        });
        return task;
    }
    [self run:task method:method.length ? [method uppercaseString] : @"GET" url:u headers:headers body:body hops:0 retries:retries completion:completion];
    return task;
}

+ (CHHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(CHHTTPCompletion)completion
{
    return [self request:@"GET" url:url headers:headers body:nil retries:1 completion:completion];
}

// What an error body says: {"message": ...}, {"error": ..., "message": ...}, {"error_description": ...}, {"errors": [{"message": ...}]}
+ (NSString *)messageFromErrorJSON:(id)json
{
    NSDictionary *d = CHDict(json);
    if (!d) {
        NSDictionary *first = CHDict([CHArr(json) firstObject]);
        return CHStr([first objectForKey:@"error"]) ?: CHStr([first objectForKey:@"message"]);
    }
    NSString *message = CHStr([d objectForKey:@"message"]);
    if (!message.length) message = CHStr([d objectForKey:@"error_description"]);
    if (!message.length) message = CHStr([CHDict([CHArr([d objectForKey:@"errors"]) firstObject]) objectForKey:@"message"]);
    if (!message.length && [[d objectForKey:@"error"] isKindOfClass:[NSString class]]) message = [d objectForKey:@"error"];
    return message.length ? message : nil;
}

+ (CHHTTPCompletion)jsonHandler:(CHJSONCompletion)completion
{
    return ^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (!completion) return;
        if (error) { completion(nil, 0, error); return; }
        id json = [CHUtils JSONObjectFromData:body];
        if (status >= 400) {
            NSString *message = [self messageFromErrorJSON:json] ?: [NSString stringWithFormat:L(@"Request failed (HTTP %ld)."), (long)status];
            completion(json, status, CHMakeError(status, message));
            return;
        }
        if (!json && body.length) {
            completion(nil, status, CHMakeError(CHErrorBadResponse, L(@"Unexpected response format.")));
            return;
        }
        completion(json, status, nil);
    };
}

+ (CHHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(CHJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (![h objectForKey:@"Accept"]) CHLegacyDictionarySet(h, @"Accept", @"application/json");
    return [self request:@"GET" url:url headers:h body:nil retries:1 completion:[self jsonHandler:completion]];
}

+ (CHHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(CHJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (![h objectForKey:@"Accept"]) CHLegacyDictionarySet(h, @"Accept", @"application/json");
    if (![h objectForKey:@"Content-Type"]) CHLegacyDictionarySet(h, @"Content-Type", @"application/json");
    NSData *body = [CHUtils JSONDataFromObject:object] ?: [NSData data];
    return [self request:@"POST" url:url headers:h body:body retries:retries completion:[self jsonHandler:completion]];
}

+ (CHHTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(CHJSONCompletion)completion
{
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in fields) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [CHUtils urlEncode:key], [CHUtils urlEncode:[[fields objectForKey:key] description]]]];
    }
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (![h objectForKey:@"Content-Type"]) CHLegacyDictionarySet(h, @"Content-Type", @"application/x-www-form-urlencoded");
    if (![h objectForKey:@"Accept"]) CHLegacyDictionarySet(h, @"Accept", @"application/json");
    return [self request:@"POST" url:url headers:h body:body retries:0 completion:[self jsonHandler:completion]];
}

+ (CHHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(CHJSONCompletion)completion
{
    return [self postForm:url headers:nil fields:fields completion:completion];
}

@end

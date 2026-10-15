#import <Foundation/Foundation.h>

typedef void (^CHHTTPCompletion)(NSInteger status, NSData *body, NSDictionary *headers, NSError *error);
typedef void (^CHJSONCompletion)(id json, NSInteger status, NSError *error);

// A running request of CHHTTP. After -cancel the completion block is never called.
@interface CHHTTPTask : NSObject
@property (atomic, readonly) BOOL isCancelled;
@property (atomic, copy) dispatch_block_t cancelBlock;   // for chained requests: called by -cancel (once)
- (void)cancel;
@end

// Convenience layer over CHHTTPRequest for API calls: redirects are followed, GET requests are tried a second
// time after a network error, completion blocks run on the main thread.
@interface CHHTTP : NSObject

+ (CHHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(CHHTTPCompletion)completion;

+ (CHHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(CHHTTPCompletion)completion;

// JSON answers. `error` is set for network errors, for statuses >= 400 (code = the status, message from the body
// when it has one) and for bodies that are not JSON; `json` is passed even with an error when the body parsed.
+ (CHHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(CHJSONCompletion)completion;
+ (CHHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(CHJSONCompletion)completion;
+ (CHHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(CHJSONCompletion)completion;
+ (CHHTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(CHJSONCompletion)completion;

@end

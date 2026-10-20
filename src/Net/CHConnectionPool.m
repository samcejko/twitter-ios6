#import "CHLegacyCollections.h"
#import "CHConnectionPool.h"
#import "CHTLSSocket.h"
#import "CHCommon.h"

static const NSTimeInterval CHIdleTimeout = 25;     // most servers drop idle connections after 5 to 60 s
static const NSUInteger CHMaxIdlePerKey = 6;
static const NSUInteger CHMaxIdleTotal = 24;

@interface CHPooledConnection : NSObject
@property (nonatomic, strong) CHTLSSocket *socket;
@property (nonatomic) NSTimeInterval lastUsed;
@end

@implementation CHPooledConnection
@end

@implementation CHConnectionPool {
    NSMutableDictionary *_idle;     // key -> NSMutableArray<CHPooledConnection>
    NSUInteger _count;
    NSUInteger _reuses;
}

+ (instancetype)shared
{
    static CHConnectionPool *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [[CHConnectionPool alloc] init]; });
    return pool;
}

- (instancetype)init
{
    self = [super init];
    if (self) _idle = [NSMutableDictionary dictionary];
    return self;
}

// Must be called with the lock held. Moves expired connections into `dead`.
- (void)pruneLocked:(NSMutableArray *)dead
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *emptyKeys = [NSMutableArray array];
    for (NSString *key in _idle) {
        NSMutableArray *list = [_idle objectForKey:key];
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            CHPooledConnection *c = [list objectAtIndex:(NSUInteger)i];
            if (now - c.lastUsed > CHIdleTimeout) {
                [dead addObject:c.socket];
                [list removeObjectAtIndex:(NSUInteger)i];
                _count--;
            }
        }
        if (!list.count) [emptyKeys addObject:key];
    }
    [_idle removeObjectsForKeys:emptyKeys];
}

- (CHTLSSocket *)checkoutSocketForKey:(NSString *)key
{
    if (!key) return nil;
    NSMutableArray *dead = [NSMutableArray array];
    CHTLSSocket *result = nil;
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = [_idle objectForKey:key];
        while (list.count && !result) {
            CHPooledConnection *c = [list lastObject];
            [list removeLastObject];
            _count--;
            if ([c.socket isLikelyAlive]) result = c.socket;
            else [dead addObject:c.socket];
        }
        if (result) _reuses++;
    }
    for (CHTLSSocket *s in dead) [s close];
    return result;
}

- (void)checkinSocket:(CHTLSSocket *)socket forKey:(NSString *)key
{
    if (!socket || !key) return;
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = [_idle objectForKey:key];
        if (!list) {
            list = [NSMutableArray array];
            CHLegacyDictionarySet(_idle, key, list);
        }
        if (list.count >= CHMaxIdlePerKey || _count >= CHMaxIdleTotal) {
            [dead addObject:socket];
        } else {
            CHPooledConnection *c = [[CHPooledConnection alloc] init];
            c.socket = socket;
            c.lastUsed = [NSDate timeIntervalSinceReferenceDate];
            [list addObject:c];
            _count++;
        }
    }
    for (CHTLSSocket *s in dead) [s close];
}

- (void)drain
{
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *key in _idle) {
            for (CHPooledConnection *c in [_idle objectForKey:key]) [dead addObject:c.socket];
        }
        [_idle removeAllObjects];
        _count = 0;
    }
    for (CHTLSSocket *s in dead) [s close];
    if (dead.count) CHLog(@"Connection pool drained (%lu closed)", (unsigned long)dead.count);
}

- (NSUInteger)idleCount
{
    @synchronized (self) { return _count; }
}

- (NSUInteger)reuseCount
{
    @synchronized (self) { return _reuses; }
}

@end

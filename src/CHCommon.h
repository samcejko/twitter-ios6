// Shared macros and constants. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define CHIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define CHLog(fmt, ...) NSLog((@"[Chirpie] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void CHMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const CHErrorDomain;
extern NSString * const CHThemeDidChangeNotification;
extern NSString * const CHSettingsDidChangeNotification;
extern NSString * const CHLibraryDidChangeNotification;     // the local library changed (bookmarks, muted words…)

// NSError codes in CHErrorDomain (HTTP errors use the HTTP status as code)
enum {
    CHErrorNetwork        = -1,
    CHErrorTLS            = -2,
    CHErrorCertificate    = -3,
    CHErrorTimeout        = -4,
    CHErrorCancelled      = -5,
    CHErrorBadResponse    = -6,
    CHErrorDNS            = -7,
    CHErrorConnect        = -8,
    CHErrorConnectionLost = -9,
    CHErrorAPI            = -10,   // the server answered, but with an error
    CHErrorOffline        = -11,   // nothing to show yet
    CHErrorAuth           = -12,   // the helper is not signed in to X
    CHErrorRestricted     = -13,   // protected, blocked or suspended account
};

NSError *CHMakeError(NSInteger code, NSString *message);

// JSON values as the type the caller expects, nil/0 for anything else (NSNull, wrong type)
NSString *CHStr(id value);         // numbers become their decimal string
NSDictionary *CHDict(id value);
NSArray *CHArr(id value);
NSInteger CHInt(id value);
double CHDbl(id value);
BOOL CHBool(id value);

// "2026-10-02T17:31:00Z" and "2026-10-02T17:31:05.042684Z"
NSDate *CHDateFromISO(NSString *string);

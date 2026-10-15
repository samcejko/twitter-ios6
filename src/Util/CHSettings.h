#import <Foundation/Foundation.h>

// Everything the app remembers between launches. Small values live in NSUserDefaults; the server key lives in the
// keychain. Changing most of them posts CHSettingsDidChangeNotification; the saved tweets post
// CHLibraryDidChangeNotification.
@interface CHSettings : NSObject

+ (void)registerDefaults;
+ (void)save;

#pragma mark - The helper (your own server)

+ (NSString *)serverBaseURL;                 // trimmed, no trailing slash, "https://" added when missing
+ (void)setServerBaseURL:(NSString *)value;
+ (NSString *)serverKey;                      // kept in the keychain
+ (void)setServerKey:(NSString *)value;
+ (BOOL)serverConfigured;

#pragma mark - The signed-in X account (cookies live only here, in the keychain)

+ (NSString *)xAuthToken;                      // the auth_token cookie
+ (void)setXAuthToken:(NSString *)value;
+ (NSString *)xCSRF;                           // the ct0 cookie
+ (void)setXCSRF:(NSString *)value;
+ (BOOL)loggedIn;                              // both cookies present
+ (void)logOut;                                // forget the cookies
+ (BOOL)streamThroughServer;                  // route media through the Pi too (slower, needed away from home)
+ (void)setStreamThroughServer:(BOOL)value;

#pragma mark - Timeline / playback

+ (BOOL)followingTimeline;                    // home shows Following rather than For You
+ (void)setFollowingTimeline:(BOOL)value;
+ (BOOL)autoplayVideos;                       // a tweet's video starts on its own in the detail view
+ (void)setAutoplayVideos:(BOOL)value;
+ (BOOL)showSensitive;                        // show media marked sensitive without a tap-to-reveal
+ (void)setShowSensitive:(BOOL)value;

#pragma mark - Appearance / network

+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)value;
+ (BOOL)verifyTLS;
+ (void)setVerifyTLS:(BOOL)value;

#pragma mark - Search history

+ (NSArray *)searchHistory;                   // newest first
+ (void)addSearch:(NSString *)query;
+ (void)clearSearchHistory;

#pragma mark - Saved (bookmarked) tweets, kept on the device

+ (NSArray *)savedTweets;                      // NSDictionary (CHTweet toJSON), newest first
+ (BOOL)isSaved:(NSString *)tweetId;
+ (void)saveTweetJSON:(NSDictionary *)json;
+ (void)unsaveTweet:(NSString *)tweetId;

@end

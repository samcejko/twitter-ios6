#import "CHLinkRouter.h"
#import "CHTweetDetailViewController.h"
#import "CHProfileViewController.h"
#import "CHSearchViewController.h"
#import "CHPageNavigationController.h"
#import "CHExternalOpen.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#pragma mark - The sheet that lists the links of a text

@interface CHLinkChoice : NSObject <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *links;
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIView *anchor;
@property (nonatomic) NSInteger chosen;        // -1: none
@end

static NSMutableArray *g_choices;

@implementation CHLinkChoice

- (instancetype)init { if ((self = [super init])) _chosen = -1; return self; }

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    self.chosen = (index >= 0 && index != sheet.cancelButtonIndex && index < (NSInteger)self.links.count) ? index : -1;
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index
{
    sheet.delegate = nil;
    if (self.chosen >= 0) [CHLinkRouter openWebLink:[self.links objectAtIndex:(NSUInteger)self.chosen] from:self.controller anchor:self.anchor];
    CHLinkChoice *me = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [g_choices removeObject:me]; });
}

@end

// Paths under twitter.com / x.com that are not a @handle
static NSArray *CHReservedHandles(void)
{
    return @[ @"home", @"explore", @"search", @"notifications", @"messages", @"settings", @"i", @"compose", @"intent",
              @"share", @"hashtag", @"login", @"logout", @"signup", @"account", @"tos", @"privacy", @"about",
              @"download", @"bookmarks", @"lists", @"topics", @"following", @"followers", @"status" ];
}

@implementation CHLinkRouter

+ (UIViewController *)topController
{
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// The navigation controller a new page should push onto: the selected tab's, a presented stack's, whatever is on top
+ (UINavigationController *)topNav
{
    UIViewController *top = [self topController];
    if ([top isKindOfClass:[UITabBarController class]]) top = [(UITabBarController *)top selectedViewController];
    if ([top isKindOfClass:[UINavigationController class]]) return (UINavigationController *)top;
    return top.navigationController;
}

// Push a page onto the current navigation stack, or open a sliding page stack over the root when there is none
+ (void)push:(UIViewController *)page
{
    if (!page) return;
    UINavigationController *nav = [self topNav];
    if (nav) [nav pushViewController:page animated:YES];
    else [CHPageNavigationController showPage:page];
}

// The pages already on top (the current nav stack, or a page stack)
+ (NSArray *)visiblePages
{
    UINavigationController *nav = [self topNav];
    return nav ? nav.viewControllers : [CHPageNavigationController visibleStack].viewControllers;
}

// The digits that follow `marker` ("/status/123" -> "123"), nil when there are none
+ (NSString *)digitsAfter:(NSString *)marker in:(NSString *)s
{
    NSRange r = [s rangeOfString:marker];
    if (r.location == NSNotFound) return nil;
    NSMutableString *d = [NSMutableString string];
    for (NSUInteger i = r.location + r.length; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') break;
        [d appendFormat:@"%C", c];
    }
    return d.length >= 6 ? d : nil;
}

+ (BOOL)openLink:(NSString *)link
{
    NSString *s = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!s.length) return NO;
    // a bare @handle
    if ([s hasPrefix:@"@"] && s.length > 1) {
        NSString *h = [[[s substringFromIndex:1] componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] objectAtIndex:0];
        if (h.length) { [self openProfile:h]; return YES; }
    }
    // a bare tweet id
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (s.length >= 10 && [s rangeOfCharacterFromSet:nonDigits].location == NSNotFound) { [self openTweetId:s]; return YES; }

    NSString *lower = [s lowercaseString];
    if ([lower rangeOfString:@"twitter.com"].location == NSNotFound && [lower rangeOfString:@"x.com"].location == NSNotFound) return NO;
    if (![lower hasPrefix:@"http"]) s = [@"https://" stringByAppendingString:s];
    NSURL *url = [NSURL URLWithString:s];
    NSString *host = [url.host lowercaseString] ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    if ([host hasPrefix:@"mobile."]) host = [host substringFromIndex:7];
    BOOL ours = [host isEqualToString:@"twitter.com"] || [host isEqualToString:@"x.com"] ||
                [host hasSuffix:@".twitter.com"] || [host hasSuffix:@".x.com"];
    if (!ours) return NO;

    NSString *path = url.path ?: @"";
    NSString *tid = [self digitsAfter:@"/status/" in:path] ?: [self digitsAfter:@"/statuses/" in:path];
    if (tid) { [self openTweetId:tid]; return YES; }

    NSArray *parts = [[path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] componentsSeparatedByString:@"/"];
    NSString *first = parts.count ? [[parts objectAtIndex:0] lowercaseString] : @"";
    if ([first isEqualToString:@"hashtag"] && parts.count > 1 && [[parts objectAtIndex:1] length]) {
        [self openHashtag:[[parts objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: [parts objectAtIndex:1]];
        return YES;
    }
    if ([first isEqualToString:@"search"]) {
        [self openSearch:CHStr([[CHUtils parseQuery:url.query ?: @""] objectForKey:@"q"])];
        return YES;
    }
    // /<handle> (profile). /i/..., /intent/... and the other reserved roots go to a browser.
    if (parts.count >= 1 && first.length && ![CHReservedHandles() containsObject:first]) {
        [self openProfile:[parts objectAtIndex:0]];
        return YES;
    }
    return NO;
}

+ (void)openTweet:(CHTweet *)tweet
{
    if (!tweet.tweetId.length) return;
    [self push:[[CHTweetDetailViewController alloc] initWithTweet:tweet]];
}

+ (void)openTweetId:(NSString *)tweetId
{
    NSString *digits = [[tweetId componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (!digits.length) return;
    [self push:[[CHTweetDetailViewController alloc] initWithTweetId:digits]];
}

+ (void)openProfile:(NSString *)handle
{
    if ([handle hasPrefix:@"@"]) handle = [handle substringFromIndex:1];
    handle = [[handle componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]] firstObject];
    if (!handle.length) return;
    // from that very profile (a tweet opened from it, then its author tapped): back rather than a second copy
    NSArray *pages = [self visiblePages];
    if (pages.count >= 2) {
        UIViewController *below = [pages objectAtIndex:pages.count - 2];
        if ([below isKindOfClass:[CHProfileViewController class]] &&
            [[(CHProfileViewController *)below handle] caseInsensitiveCompare:handle] == NSOrderedSame) {
            [[self topNav] popViewControllerAnimated:YES];
            return;
        }
    }
    [self push:[[CHProfileViewController alloc] initWithHandle:handle]];
}

+ (void)openHashtag:(NSString *)tag
{
    NSString *t = [[tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
    if (!t.length) return;
    [self openSearch:[@"#" stringByAppendingString:t]];
}

+ (void)openSearch:(NSString *)query
{
    UIViewController *top = [[self topNav] topViewController];
    if ([top isKindOfClass:[CHSearchViewController class]]) {
        if (query.length) [(CHSearchViewController *)top searchFor:query];
        return;
    }
    [self push:[[CHSearchViewController alloc] initWithQuery:query]];
}

#pragma mark - Web links in tweet text

+ (NSString *)webLinkString:(id)link
{
    NSString *s = [link isKindOfClass:[NSURL class]] ? [(NSURL *)link absoluteString] : [link isKindOfClass:[NSString class]] ? link : nil;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;
    if ([s rangeOfString:@"://"].location == NSNotFound) s = [@"https://" stringByAppendingString:s];
    return s;
}

+ (void)openWebLink:(id)link from:(UIViewController *)controller anchor:(UIView *)anchor
{
    NSString *s = [self webLinkString:link];
    if (!s) return;
    if ([self openLink:s]) return;   // a twitter.com / x.com link opens inside the app
    NSURL *url = [NSURL URLWithString:s] ?: [NSURL URLWithString:[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @""];
    if (!url) return;
    [CHExternalOpen presentOpenInForURL:url from:controller ?: [self topController] anchor:anchor];
}

+ (void)openWebLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!links.count) return;
    if (links.count == 1) { [self openWebLink:[links objectAtIndex:0] from:controller anchor:anchor]; return; }
    CHLinkChoice *choice = [[CHLinkChoice alloc] init];
    choice.links = links;
    choice.controller = controller;
    choice.anchor = anchor;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Open a link") delegate:choice cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (id link in links) [sheet addButtonWithTitle:[CHUtils linkTitle:link length:60]];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (!g_choices) g_choices = [NSMutableArray array];
    [g_choices addObject:choice];
    [CHExternalOpen showSheet:sheet from:controller ?: [self topController] anchor:anchor];
}

@end

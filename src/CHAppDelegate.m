#import "CHAppDelegate.h"
#import "CHRootViewController.h"
#import "CHLinkRouter.h"
#import "CHTLSSocket.h"
#import "CHImageLoader.h"
#import "CHMediaProxy.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHModern.h"
#import "CHCommon.h"
#include <dlfcn.h>
#include <signal.h>
#include <mach/mach.h>

static BOOL CHButtonMatches(UIButton *button, NSString *text)
{
    for (NSString *name in @[ button.currentTitle ?: @"", button.accessibilityLabel ?: @"" ])
        if (name.length && [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static BOOL CHViewContainsText(UIView *view, NSString *text)
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        return s.length && [s rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    for (UIView *sub in view.subviews) { if ([sub isKindOfClass:[UIControl class]]) continue; if (CHViewContainsText(sub, text)) return YES; }
    return NO;
}

static BOOL CHPressView(UIView *v, NSString *text)
{
    if ([v isKindOfClass:[UIButton class]]) {
        if (!CHButtonMatches((UIButton *)v, text)) return NO;
        [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)v;
        if (!CHViewContainsText(cell, text)) return NO;
        UIView *table = cell.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
        NSIndexPath *ip = [(UITableView *)table indexPathForCell:cell];
        id<UITableViewDelegate> delegate = [(UITableView *)table delegate];
        if (!ip || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [delegate tableView:(UITableView *)table didSelectRowAtIndexPath:ip];
        return YES;
    }
    return NO;
}

@implementation CHAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    signal(SIGPIPE, SIG_IGN);
    [CHSettings registerDefaults];
    CHLog(@"Chirpie %@ starting on %@ (iOS %@)", [CHUtils appVersion], [CHUtils deviceModel], [UIDevice currentDevice].systemVersion);
    CHModernSetUp([[CHTheme shared] barStyle]);     // the iOS 6 look on iOS 7+
    [CHTLSSocket warmUp];
    [[CHImageLoader shared] pruneDisk];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.root = [[CHRootViewController alloc] init];
    self.window.rootViewController = self.root;
    self.window.backgroundColor = [[CHTheme shared] backgroundColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:[[CHTheme shared] statusBarStyle] animated:NO];
    return YES;
}

- (UIViewController *)topController
{
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UITabBarController class]]) top = [(UITabBarController *)top selectedViewController];
    if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
    return top;
}

// chirpie:open?url=<a twitter/x link>, chirpie:tweet/<id>, chirpie:user/<handle>, chirpie:search?q=, chirpie:tag/<tag>,
// chirpie:server?url=&key=, and plain twitter.com / x.com links (how Surfari hands links over); chirp: works too.
// Debug commands (need Documents/debug): snapshot, screen, press?title=/n=, back, stats, lang?set=, link?url=, tab?i=.
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSString *s = url.absoluteString ?: @"";
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) return [CHLinkRouter openLink:s];
    NSString *scheme = [lower hasPrefix:@"chirpie:"] ? @"chirpie:" : [lower hasPrefix:@"chirp:"] ? @"chirp:" : nil;
    if (!scheme) return NO;
    NSString *target = [s substringFromIndex:scheme.length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) { query = [target substringFromIndex:q.location + 1]; target = [target substringToIndex:q.location]; }
    NSDictionary *params = query.length ? [CHUtils parseQuery:query] : @{};

    if ([target hasPrefix:@"tweet/"]) { [CHLinkRouter openTweetId:[target substringFromIndex:@"tweet/".length]]; return YES; }
    if ([target hasPrefix:@"user/"]) { [CHLinkRouter openProfile:[target substringFromIndex:@"user/".length]]; return YES; }
    if ([target hasPrefix:@"tag/"]) {
        NSString *tag = [target substringFromIndex:@"tag/".length];
        [CHLinkRouter openHashtag:[tag stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: tag];
        return YES;
    }
    if ([target isEqualToString:@"search"]) { [CHLinkRouter openSearch:params[@"q"]]; return YES; }
    if ([target isEqualToString:@"open"] && [params[@"url"] length]) {
        if (![CHLinkRouter openLink:params[@"url"]]) [CHUtils alertWithTitle:L(@"Open a link") message:L(@"That does not look like a Twitter link.")];
        return YES;
    }
    if ([target isEqualToString:@"server"]) {
        if ([params[@"url"] length]) [CHSettings setServerBaseURL:params[@"url"]];
        if (params[@"key"]) [CHSettings setServerKey:params[@"key"]];
        [CHUtils alertWithTitle:L(@"Settings") message:[CHSettings serverBaseURL].length ? [CHSettings serverBaseURL] : L(@"Not set")];
        return YES;
    }

    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[CHUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    UIViewController *top = [self topController];
    if ([target isEqualToString:@"tab"]) { [self.root selectTab:[params[@"i"] integerValue]]; return YES; }
    if ([target isEqualToString:@"stats"]) {
        struct task_basic_info info; mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
            CHLog(@"Memory: %.1f MB resident", info.resident_size / 1048576.0);
        CHLog(@"Top: %@, server %@ (%@), bookmarks %lu", NSStringFromClass([top class]), [CHSettings serverBaseURL],
              [CHSettings serverKey].length ? @"keyed" : @"no key", (unsigned long)[CHSettings savedTweets].count);
        return YES;
    }
    if ([target isEqualToString:@"lang"]) {
        NSString *set = params[@"set"] ?: @"system";
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if ([set isEqualToString:@"system"]) [d removeObjectForKey:@"AppleLanguages"]; else [d setObject:@[ set ] forKey:@"AppleLanguages"];
        [d synchronize];
        CHLog(@"Language %@ from the next launch: quitting", set);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
        return YES;
    }
    if ([target isEqualToString:@"link"]) {
        NSString *link = params[@"url"];
        if (link.length) [CHLinkRouter openWebLink:link from:top anchor:nil];
        return YES;
    }
    if ([target isEqualToString:@"snapshot"] || [target isEqualToString:@"screen"]) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = NO;
        if ([target isEqualToString:@"screen"]) {
            CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
            CGImageRef shot = grab ? grab() : NULL;
            if (shot) { ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:shot]) writeToFile:path atomically:YES]; CGImageRelease(shot); }
        } else {
            CGSize size = [UIScreen mainScreen].bounds.size;
            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.hidden && w.alpha > 0) [w.layer renderInContext:UIGraphicsGetCurrentContext()];
            ok = [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES];
            UIGraphicsEndImageContext();
        }
        CHLog(@"%@ %@: %@", target, ok ? @"written" : @"failed", path);
        return YES;
    }
    if ([target isEqualToString:@"press"]) {
        NSString *byTitle = params[@"title"];
        NSInteger n = [params[@"n"] integerValue];
        NSMutableArray *views = [NSMutableArray array];
        UIView *topView = top.navigationController.view ?: top.view;
        if (topView) [views addObject:topView];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [views addObject:w];
        BOOL pressed = NO;
        for (NSUInteger i = 0; i < views.count && !pressed; i++) {
            UIView *v = views[i];
            if (!byTitle.length && [v isKindOfClass:[UIActionSheet class]] && ((UIActionSheet *)v).visible) {
                UIActionSheet *sheet = (UIActionSheet *)v;
                if ([sheet.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [sheet.delegate actionSheet:sheet clickedButtonAtIndex:n];
                [sheet dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (!byTitle.length && [v isKindOfClass:[UIAlertView class]] && ((UIAlertView *)v).visible) {
                UIAlertView *alert = (UIAlertView *)v;
                if ([alert.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [alert.delegate alertView:alert clickedButtonAtIndex:n];
                [alert dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (byTitle.length && !v.hidden && CHPressView(v, byTitle)) {
                pressed = YES;
            } else {
                [views addObjectsFromArray:v.subviews];
            }
        }
        CHLog(@"Press %@: %@", query ?: @"", pressed ? @"done" : @"nothing found");
        return YES;
    }
    if ([target isEqualToString:@"back"]) {
        UINavigationController *nav = top.navigationController;
        if (nav.viewControllers.count > 1) [nav popViewControllerAnimated:YES];
        else if ([self topController].presentingViewController) [[self topController] dismissViewControllerAnimated:YES completion:nil];
        return YES;
    }
    if ([target isEqualToString:@"scroll"]) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:top.view];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if ([v isKindOfClass:[UIScrollView class]] && ((UIScrollView *)v).contentSize.height > v.bounds.size.height + 1) {
                UIScrollView *sv = (UIScrollView *)v;
                CGFloat dir = [params[@"dir"] isEqualToString:@"up"] ? -1 : 1;
                CGFloat y = MAX(0, MIN(sv.contentSize.height - sv.bounds.size.height, sv.contentOffset.y + dir * sv.bounds.size.height));
                [sv setContentOffset:CGPointMake(0, y) animated:YES];
                break;
            }
            [stack addObjectsFromArray:v.subviews];
        }
        return YES;
    }
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application { [[CHMediaProxy shared] ensureRunning]; }
- (void)applicationDidEnterBackground:(UIApplication *)application { [CHSettings save]; }

@end

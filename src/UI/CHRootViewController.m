#import "CHRootViewController.h"
#import "CHTimelineViewController.h"
#import "CHSearchViewController.h"
#import "CHNotificationsViewController.h"
#import "CHMessagesViewController.h"
#import "CHMeViewController.h"
#import "CHLoginViewController.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHCommon.h"

static UIImage *CHTabIcon(NSString *name)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    [[UIColor blackColor] setFill];
    [[UIColor blackColor] setStroke];
    if ([name isEqualToString:@"bell"]) {
        UIBezierPath *b = [UIBezierPath bezierPath];
        [b moveToPoint:CGPointMake(6, 22)];
        [b addCurveToPoint:CGPointMake(8, 13) controlPoint1:CGPointMake(8, 19) controlPoint2:CGPointMake(8, 16)];
        [b addArcWithCenter:CGPointMake(15, 11) radius:7 startAngle:M_PI endAngle:0 clockwise:YES];
        [b addCurveToPoint:CGPointMake(24, 22) controlPoint1:CGPointMake(22, 16) controlPoint2:CGPointMake(22, 19)];
        [b closePath];
        [b fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12.5, 22, 5, 5)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(13, 3, 4, 4)] fill];
    } else if ([name isEqualToString:@"envelope"]) {
        UIBezierPath *r = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 7, 24, 16) cornerRadius:3];
        [r fill];
        UIGraphicsGetCurrentContext();
        CGContextSetBlendMode(UIGraphicsGetCurrentContext(), kCGBlendModeClear);
        UIBezierPath *flap = [UIBezierPath bezierPath];
        [flap moveToPoint:CGPointMake(4, 9)]; [flap addLineToPoint:CGPointMake(15, 17)]; [flap addLineToPoint:CGPointMake(26, 9)];
        flap.lineWidth = 2; flap.lineJoinStyle = kCGLineJoinRound; [flap stroke];
    } else if ([name isEqualToString:@"person"]) {
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 3, 10, 10)] fill];
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(5, 15, 20, 15) cornerRadius:9];
        [body fill];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation CHRootViewController

- (instancetype)init
{
    if ((self = [super init])) {
        CHTheme *th = [CHTheme shared];
        NSArray *vcs = @[ [[CHTimelineViewController alloc] initWithMode:CHTimelineHome],
                          [[CHSearchViewController alloc] initWithQuery:nil],
                          [[CHNotificationsViewController alloc] init],
                          [[CHMessagesViewController alloc] init],
                          [[CHMeViewController alloc] init] ];
        NSArray *titles = @[ L(@"Home"), L(@"Explore"), L(@"Notifications"), L(@"Messages"), L(@"Me") ];
        NSArray *icons = @[ [th tabIconHome], [th tabIconSearch], CHTabIcon(@"bell"), CHTabIcon(@"envelope"), CHTabIcon(@"person") ];
        NSMutableArray *navs = [NSMutableArray array];
        for (NSUInteger i = 0; i < vcs.count; i++) {
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[vcs objectAtIndex:i]];
            [th applyToNavigationBar:nav.navigationBar];
            nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:[titles objectAtIndex:i] image:[icons objectAtIndex:i] tag:(NSInteger)i];
            [navs addObject:nav];
        }
        self.viewControllers = navs;
        [th applyToTabBar:self.tabBar];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(needsLogin) name:CHNeedsLoginNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:CHSettingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)selectTab:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger)self.viewControllers.count) self.selectedIndex = (NSUInteger)index;
}

- (BOOL)loginOnScreen
{
    UIViewController *p = self.presentedViewController;
    if ([p isKindOfClass:[UINavigationController class]]) p = [(UINavigationController *)p topViewController];
    return [p isKindOfClass:[CHLoginViewController class]];
}

- (void)presentLogin
{
    if (![CHTwitter configured] || [CHSettings loggedIn] || [self loginOnScreen] || self.presentedViewController) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[CHLoginViewController alloc] init]];
    [[CHTheme shared] applyToNavigationBar:nav.navigationBar];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)needsLogin { [self presentLogin]; }

// After a login or a settings change, refresh the tab the user is looking at (others refresh on their next appear)
- (void)settingsChanged
{
    UIViewController *vc = self.selectedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) vc = [(UINavigationController *)vc topViewController];
    if ([vc respondsToSelector:@selector(reload)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [vc performSelector:@selector(reload)];
        #pragma clang diagnostic pop
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSUInteger)supportedInterfaceOrientations
{
    return CHIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

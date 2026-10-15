#import "CHRootViewController.h"
#import "CHTimelineViewController.h"
#import "CHSearchViewController.h"
#import "CHTheme.h"
#import "CHCommon.h"

static UIImage *CHBookmarkTabIcon(void)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(8, 3)];
    [p addLineToPoint:CGPointMake(22, 3)];
    [p addLineToPoint:CGPointMake(22, 27)];
    [p addLineToPoint:CGPointMake(15, 20.5)];
    [p addLineToPoint:CGPointMake(8, 27)];
    [p closePath];
    [[UIColor blackColor] setFill];
    [p fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation CHRootViewController

- (instancetype)init
{
    if ((self = [super init])) {
        CHTheme *th = [CHTheme shared];
        CHTimelineViewController *home = [[CHTimelineViewController alloc] initWithMode:CHTimelineHome];
        CHSearchViewController *explore = [[CHSearchViewController alloc] initWithQuery:nil];
        CHTimelineViewController *saved = [[CHTimelineViewController alloc] initWithMode:CHTimelineSaved];

        NSArray *vcs = @[ home, explore, saved ];
        NSArray *titles = @[ L(@"Home"), L(@"Explore"), L(@"Bookmarks") ];
        NSArray *icons = @[ [th tabIconHome], [th tabIconSearch], CHBookmarkTabIcon() ];
        NSMutableArray *navs = [NSMutableArray array];
        for (NSUInteger i = 0; i < vcs.count; i++) {
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vcs[i]];
            [th applyToNavigationBar:nav.navigationBar];
            nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i] image:icons[i] tag:(NSInteger)i];
            [navs addObject:nav];
        }
        self.viewControllers = navs;
        [th applyToTabBar:self.tabBar];
    }
    return self;
}

- (void)selectTab:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger)self.viewControllers.count) self.selectedIndex = (NSUInteger)index;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return CHIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

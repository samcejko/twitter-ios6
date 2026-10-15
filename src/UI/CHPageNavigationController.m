#import "CHPageNavigationController.h"
#import <QuartzCore/QuartzCore.h>
#import "CHLinkRouter.h"
#import "CHTheme.h"
#import "CHModern.h"
#import "CHCommon.h"

// Stands under the first page so that the bar draws a real (arrow-shaped) back button there; it is never shown
@interface CHStackBottom : UIViewController
@end

@implementation CHStackBottom
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = [UIColor blackColor]; }
@end

@interface CHPageNavigationController () <UINavigationControllerDelegate, UINavigationBarDelegate>
@property (nonatomic) BOOL closing;
@end

@implementation CHPageNavigationController

+ (CHPageNavigationController *)visibleStack
{
    UIViewController *top = [CHLinkRouter topController];
    return [top isKindOfClass:[CHPageNavigationController class]] ? (CHPageNavigationController *)top : nil;
}

// The slide of a push, for a modal presentation (iOS 6 has none): the window's next picture comes in from the side
+ (void)slideWindow:(UIWindow *)window fromRight:(BOOL)fromRight
{
    if (!window) return;
    CATransition *t = [CATransition animation];
    t.type = kCATransitionPush;
    t.subtype = fromRight ? kCATransitionFromRight : kCATransitionFromLeft;
    t.duration = 0.3;
    t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [window.layer addAnimation:t forKey:@"CHPageSlide"];
}

+ (void)showPage:(UIViewController *)page
{
    if (!page) return;
    CHPageNavigationController *stack = [self visibleStack];
    if (stack) { [stack pushViewController:page animated:YES]; return; }
    UIViewController *top = [CHLinkRouter topController];
    CHStackBottom *bottom = [[CHStackBottom alloc] init];
    bottom.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Back") style:UIBarButtonItemStyleBordered target:nil action:NULL];
    CHPageNavigationController *nav = [[CHPageNavigationController alloc] initWithRootViewController:bottom];
    [nav pushViewController:page animated:NO];
    [self slideWindow:top.view.window fromRight:YES];
    [top presentViewController:nav animated:NO completion:nil];
}

- (instancetype)initWithRootViewController:(UIViewController *)root
{
    if ((self = [super initWithRootViewController:root])) {
        self.delegate = self;
        self.wantsFullScreenLayout = YES;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        [[CHTheme shared] applyToNavigationBar:self.navigationBar];
        // (Back has logic of its own below; the swipe of iOS 7+ would pop past the first page onto the black bottom)
        CHModernDisableSwipeBack(self);
    }
    return self;
}

- (void)closeAnimated:(BOOL)animated
{
    if (self.closing) return;
    self.closing = YES;
    UIViewController *presenter = self.presentingViewController;
    if (animated) [CHPageNavigationController slideWindow:self.view.window fromRight:NO];
    [presenter dismissViewControllerAnimated:NO completion:nil];
}

- (void)goBack
{
    if (self.viewControllers.count <= 2) [self closeAnimated:YES];
    else [self popViewControllerAnimated:YES];
}

// The bar's back button. (A pop made in code has already taken the page off when the bar asks: then it just goes.)
- (BOOL)navigationBar:(UINavigationBar *)bar shouldPopItem:(UINavigationItem *)item
{
    if (self.viewControllers.count < bar.items.count) return YES;
    [self goBack];
    return NO;
}

// A page that wants the whole screen (no bar) opts in with -prefersBarHidden; the hidden bottom is always bare
- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated
{
    BOOL bare = [vc isKindOfClass:[CHStackBottom class]] ||
                ([vc respondsToSelector:@selector(prefersBarHidden)] && [(id)vc prefersBarHidden]);
    if (self.navigationBarHidden != bare) [self setNavigationBarHidden:bare animated:animated];
}

- (BOOL)shouldAutorotate { return self.topViewController ? [self.topViewController shouldAutorotate] : YES; }

- (NSUInteger)supportedInterfaceOrientations
{
    return self.topViewController ? [self.topViewController supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}

@end

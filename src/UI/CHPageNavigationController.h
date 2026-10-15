#import <UIKit/UIKit.h>

// The pages pushed over the tab bar root - a profile, a tweet with its thread, search - as one stack: a full-screen
// navigation controller that slides in from the side (iOS 6 has no such modal transition, so the window does the
// slide). Its first page gets a real back button; going back from it closes the whole stack and the tab underneath
// goes on where it was. A page that wants the whole screen without the bar implements -prefersBarHidden.
@interface CHPageNavigationController : UINavigationController

// Pushes onto the stack on screen, or opens a new stack over whatever is on screen
+ (void)showPage:(UIViewController *)page;
// The stack on screen (nil when none is on top)
+ (CHPageNavigationController *)visibleStack;

- (void)closeAnimated:(BOOL)animated;
// Back one page; from the first page the stack closes
- (void)goBack;

@end

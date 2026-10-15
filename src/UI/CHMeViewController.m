#import "CHMeViewController.h"
#import "CHProfileViewController.h"
#import "CHTimelineViewController.h"
#import "CHSettingsViewController.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHCommon.h"

@interface CHMeViewController ()
@property (nonatomic, strong) CHProfileViewController *profile;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic) BOOL resolving;
@end

@implementation CHMeViewController

- (void)loadView
{
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [[CHTheme shared] backgroundColor];
    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 0;
    self.status.textColor = [[CHTheme shared] secondaryTextColor]; self.status.font = [[CHTheme shared] bodyFont];
    self.status.hidden = YES;
    [self.view addSubview:self.status];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Profile");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Settings") style:UIBarButtonItemStyleBordered target:self action:@selector(openSettings)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Bookmarks") style:UIBarButtonItemStyleBordered target:self action:@selector(openBookmarks)];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self resolve]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.status.frame = CGRectInset(self.view.bounds, 28, 0); self.profile.view.frame = self.view.bounds; }

- (void)resolve
{
    if (self.profile || self.resolving) return;
    if (![CHTwitter configured]) { self.status.text = L(@"Set your server address in Settings to see your profile."); self.status.hidden = NO; return; }
    if (![CHTwitter loggedIn]) { self.status.text = L(@"Log in with your X account to see your profile."); self.status.hidden = NO; return; }
    NSString *known = [CHTwitter accountHandle];
    if (known.length) { [self embed:known]; return; }
    self.resolving = YES;
    [CHTwitter fetchMe:^(CHUser *user, NSError *error) {
        self.resolving = NO;
        if (user.handle.length) [self embed:user.handle];
        else { self.status.text = error.localizedDescription ?: L(@"Could not load your profile."); self.status.hidden = NO; }
    }];
}

- (void)embed:(NSString *)handle
{
    if (self.profile) return;
    self.handle = handle;
    self.title = [@"@" stringByAppendingString:handle];
    self.status.hidden = YES;
    CHProfileViewController *p = [[CHProfileViewController alloc] initWithHandle:handle];
    [self addChildViewController:p];
    p.view.frame = self.view.bounds;
    p.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:p.view];
    [p didMoveToParentViewController:self];
    self.profile = p;
}

- (void)openSettings
{
    CHSettingsViewController *settings = [[CHSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    [[CHTheme shared] applyToNavigationBar:nav.navigationBar];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)openBookmarks
{
    [self.navigationController pushViewController:[[CHTimelineViewController alloc] initWithMode:CHTimelineSaved] animated:YES];
}

@end

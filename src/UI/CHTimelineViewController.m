#import "CHTimelineViewController.h"
#import "CHComposeViewController.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHCommon.h"

@interface CHTimelineViewController ()
@property (nonatomic) CHTimelineMode mode;
@property (nonatomic, strong) UISegmentedControl *feedSwitch;
@end

@implementation CHTimelineViewController

- (instancetype)initWithMode:(CHTimelineMode)mode
{
    if ((self = [super init])) {
        _mode = mode;
        if (mode == CHTimelineSaved) {
            self.title = L(@"Bookmarks");
            self.emptyMessage = L(@"Tap the bookmark on a tweet to keep it here.");
        } else {
            self.title = L(@"Home");
            self.emptyMessage = L(@"No tweets to show. Pull down to refresh.");
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self installSettingsButton];
    if (self.mode == CHTimelineHome) {
        self.feedSwitch = [[UISegmentedControl alloc] initWithItems:@[ L(@"For You"), L(@"Following") ]];
        self.feedSwitch.selectedSegmentIndex = [CHSettings followingTimeline] ? 1 : 0;
        [self.feedSwitch addTarget:self action:@selector(switchFeed:) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = self.feedSwitch;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(compose)];
    }
    if (self.mode == CHTimelineSaved)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:CHLibraryDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.mode == CHTimelineSaved) [self reload];
}

- (void)switchFeed:(UISegmentedControl *)sender
{
    [CHSettings setFollowingTimeline:sender.selectedSegmentIndex == 1];
    [self reload];
}

- (void)compose
{
    CHComposeViewController *c = [CHComposeViewController composeNew];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:c];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)fetchWithCursor:(NSString *)cursor completion:(void (^)(CHTweetPage *, NSError *))completion
{
    if (![CHTwitter configured]) {
        completion(nil, CHMakeError(CHErrorAPI, L(@"Set your server address to start.\nSettings are behind the button at the top left.")));
        return;
    }
    if (self.mode == CHTimelineSaved) { [CHTwitter bookmarks:cursor completion:completion]; return; }
    [CHTwitter homeTimelineFollowing:[CHSettings followingTimeline] cursor:cursor completion:completion];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end

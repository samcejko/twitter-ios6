#import "CHTimelineViewController.h"
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

- (void)fetchWithCursor:(NSString *)cursor completion:(void (^)(CHTweetPage *, NSError *))completion
{
    if (self.mode == CHTimelineSaved) {
        NSMutableArray *tweets = [NSMutableArray array];
        for (NSDictionary *json in [CHSettings savedTweets]) { CHTweet *t = [CHTweet tweetFromJSON:json]; if (t) [tweets addObject:t]; }
        CHTweetPage *page = [[CHTweetPage alloc] init];
        page.tweets = tweets;
        page.hasMore = NO;
        completion(page, nil);
        return;
    }
    if (![CHTwitter configured]) {
        completion(nil, CHMakeError(CHErrorAPI, L(@"Set your server address to start.\nSettings are behind the button at the top left.")));
        return;
    }
    [CHTwitter homeTimelineFollowing:[CHSettings followingTimeline] cursor:cursor completion:completion];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end

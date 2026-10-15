#import "CHMediaViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import "CHImageLoader.h"
#import "CHMediaProxy.h"
#import "CHTwitter.h"
#import "CHSettings.h"
#import "CHTheme.h"
#import "CHCommon.h"

static NSDictionary *CHTwitterMediaHeaders(void)
{
    return @{ @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
              @"Referer": @"https://twitter.com/" };
}

#pragma mark - A zoomable photo page

@interface CHPhotoPage : UIScrollView <UIScrollViewDelegate>
@property (nonatomic, strong) CHImageView *imageView;
@end

@implementation CHPhotoPage
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.delegate = self;
        self.minimumZoomScale = 1.0;
        self.maximumZoomScale = 4.0;
        self.showsHorizontalScrollIndicator = NO;
        self.showsVerticalScrollIndicator = NO;
        _imageView = [[CHImageView alloc] initWithFrame:self.bounds];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.maxPixels = 2048;
        [self addSubview:_imageView];
        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
        dbl.numberOfTapsRequired = 2;
        [self addGestureRecognizer:dbl];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; if (self.zoomScale == 1.0) self.imageView.frame = self.bounds; }
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return self.imageView; }
- (void)doubleTap:(UITapGestureRecognizer *)g { [self setZoomScale:(self.zoomScale > 1.0 ? 1.0 : 2.5) animated:YES]; }
@end

#pragma mark - Viewer

@interface CHMediaViewController () <UIScrollViewDelegate>
@property (nonatomic, copy) NSArray *media;          // CHMedia
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) NSMutableArray *pages; // UIView per item
@property (nonatomic, strong) MPMoviePlayerController *player;
@property (nonatomic) NSInteger playerPage;          // which page the player is on (-1 none)
@end

@implementation CHMediaViewController

- (instancetype)initWithMedia:(NSArray *)media startIndex:(NSInteger)index
{
    if ((self = [super init])) {
        _media = media ?: @[];
        _index = MAX(0, MIN(index, (NSInteger)_media.count - 1));
        _playerPage = -1;
    }
    return self;
}

- (void)loadView
{
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[CHMediaProxy shared] ensureRunning];
    self.pager = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.pager.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pager.pagingEnabled = YES;
    self.pager.delegate = self;
    self.pager.showsHorizontalScrollIndicator = NO;
    self.pager.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.pager];

    self.pages = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.media.count; i++) {
        CHMedia *m = self.media[i];
        UIView *page;
        if (m.isVideo) {
            page = [[UIView alloc] init];
            page.backgroundColor = [UIColor blackColor];
            CHImageView *still = [[CHImageView alloc] init];
            still.contentMode = UIViewContentModeScaleAspectFit;
            still.tag = 77;
            [still setImageURL:(m.previewURL.length ? m.previewURL : m.url) placeholder:nil];
            [page addSubview:still];
        } else {
            CHPhotoPage *photo = [[CHPhotoPage alloc] initWithFrame:CGRectZero];
            [photo.imageView setImageURL:(m.url.length ? m.url : m.previewURL) placeholder:nil];
            page = photo;
        }
        [self.pager addSubview:page];
        [self.pages addObject:page];
    }

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    [close setImage:[[CHTheme shared] closeIconWhite] forState:UIControlStateNormal];
    close.frame = CGRectMake(8, 24, 44, 44);
    close.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self layoutPages];
    [self.pager setContentOffset:CGPointMake(self.index * self.pager.bounds.size.width, 0) animated:NO];
}

- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self showVideoForPage:self.index]; }

- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutPages]; }

- (void)layoutPages
{
    CGSize size = self.pager.bounds.size;
    if (size.width < 1) return;
    for (NSUInteger i = 0; i < self.pages.count; i++) {
        UIView *page = self.pages[i];
        page.frame = CGRectMake(i * size.width, 0, size.width, size.height);
        if ([page isKindOfClass:[CHPhotoPage class]]) {
            CHPhotoPage *pp = (CHPhotoPage *)page;
            pp.zoomScale = 1.0;
            pp.imageView.frame = pp.bounds;
        } else {
            for (UIView *sub in page.subviews) sub.frame = page.bounds;   // the still, and the player view when present
        }
    }
    self.pager.contentSize = CGSizeMake(size.width * self.pages.count, size.height);
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    NSInteger page = (NSInteger)roundf(scrollView.contentOffset.x / MAX(1, scrollView.bounds.size.width));
    if (page != self.index) { self.index = page; [self showVideoForPage:page]; }
}

- (void)showVideoForPage:(NSInteger)page
{
    if (page < 0 || page >= (NSInteger)self.media.count) return;
    CHMedia *m = self.media[(NSUInteger)page];
    if (!m.isVideo) { [self.player stop]; [self.player.view removeFromSuperview]; self.player = nil; self.playerPage = -1; return; }
    if (self.playerPage == page && self.player) return;
    [self.player stop];
    [self.player.view removeFromSuperview];

    NSString *src = m.url;
    NSString *proxied;
    if ([CHSettings streamThroughServer]) proxied = [CHTwitter proxyURLForMediaURL:src];
    if (!proxied) proxied = [[CHMediaProxy shared] proxyURLForURL:[NSURL URLWithString:src] upstreamHeaders:CHTwitterMediaHeaders()];
    if (!proxied) proxied = src;

    MPMoviePlayerController *mp = [[MPMoviePlayerController alloc] initWithContentURL:[NSURL URLWithString:proxied]];
    mp.controlStyle = MPMovieControlStyleEmbedded;
    mp.shouldAutoplay = YES;
    mp.repeatMode = [m.type isEqualToString:@"gif"] ? MPMovieRepeatModeOne : MPMovieRepeatModeNone;
    UIView *host = self.pages[(NSUInteger)page];
    mp.view.frame = host.bounds;
    mp.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:mp.view];
    [mp prepareToPlay];
    [mp play];
    self.player = mp;
    self.playerPage = page;
}

- (void)close
{
    [self.player stop];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (NSUInteger)supportedInterfaceOrientations { return CHIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)dealloc { [_player stop]; }

@end

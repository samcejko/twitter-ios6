#import "CHTweetActions.h"
#import "CHTweetCell.h"
#import "CHComposeViewController.h"
#import "CHExternalOpen.h"
#import "CHLinkRouter.h"
#import "CHTwitter.h"
#import "CHUtils.h"
#import "CHCommon.h"

typedef enum { CHMoreCopy, CHMoreShare, CHMoreOpen, CHMoreDelete } CHMoreAction;

@interface CHTweetActions () <UIActionSheetDelegate>
@property (nonatomic, strong) CHTweet *tweet;
@property (nonatomic, weak) CHTweetCell *cell;
@property (nonatomic, weak) UIViewController *vc;
@property (nonatomic) BOOL retweetSheet;         // YES: the repost/quote sheet; NO: the more sheet
@property (nonatomic, strong) NSArray *moreActions;   // NSNumber(CHMoreAction) per button
@end

static NSMutableArray *g_live;

@implementation CHTweetActions

+ (void)handleAction:(NSString *)action tweet:(CHTweet *)tweet cell:(CHTweetCell *)cell from:(UIViewController *)vc
{
    if (!tweet.tweetId.length) return;
    CHTweetActions *a = [[CHTweetActions alloc] init];
    a.tweet = tweet; a.cell = cell; a.vc = vc;

    if ([action isEqualToString:@"like"]) { [a toggleLike]; return; }
    if ([action isEqualToString:@"bookmark"]) { [a toggleBookmark]; return; }
    if ([action isEqualToString:@"reply"]) { [a reply]; return; }
    if ([action isEqualToString:@"retweet"]) { [a showRetweetSheet]; return; }
    if ([action isEqualToString:@"more"]) { [a showMoreSheet]; return; }
}

- (void)refresh { if (self.cell) [self.cell setTweet:self.tweet]; }

- (void)toggleLike
{
    BOOL was = self.tweet.favorited;
    self.tweet.favorited = !was;
    self.tweet.likeCount = MAX(0LL, self.tweet.likeCount + (was ? -1 : 1));
    [self refresh];
    [CHTwitter performAction:(was ? @"unlike" : @"like") onId:self.tweet.tweetId completion:^(BOOL ok, NSError *error) {
        if (!ok) {
            self.tweet.favorited = was;
            self.tweet.likeCount = MAX(0LL, self.tweet.likeCount + (was ? 1 : -1));
            [self refresh];
            [CHUtils alertWithTitle:L(@"Like") message:error.localizedDescription ?: L(@"That did not work.")];
        }
    }];
}

- (void)toggleBookmark
{
    BOOL was = self.tweet.bookmarked;
    self.tweet.bookmarked = !was;
    [self refresh];
    [CHTwitter performAction:(was ? @"unbookmark" : @"bookmark") onId:self.tweet.tweetId completion:^(BOOL ok, NSError *error) {
        if (!ok) { self.tweet.bookmarked = was; [self refresh]; [CHUtils alertWithTitle:L(@"Bookmark") message:error.localizedDescription ?: L(@"That did not work.")]; }
        else if (!was) [CHUtils alertWithTitle:L(@"Bookmarked") message:L(@"Added to your bookmarks.")];
    }];
}

- (void)toggleRetweet
{
    BOOL was = self.tweet.retweeted;
    self.tweet.retweeted = !was;
    self.tweet.retweetCount = MAX(0LL, self.tweet.retweetCount + (was ? -1 : 1));
    [self refresh];
    [CHTwitter performAction:(was ? @"unretweet" : @"retweet") onId:self.tweet.tweetId completion:^(BOOL ok, NSError *error) {
        if (!ok) {
            self.tweet.retweeted = was;
            self.tweet.retweetCount = MAX(0LL, self.tweet.retweetCount + (was ? 1 : -1));
            [self refresh];
            [CHUtils alertWithTitle:L(@"Repost") message:error.localizedDescription ?: L(@"That did not work.")];
        }
    }];
}

- (void)reply
{
    CHComposeViewController *c = [CHComposeViewController composeReplyTo:self.tweet];
    [self present:c];
}

- (void)quote
{
    CHComposeViewController *c = [CHComposeViewController composeQuoteOf:self.tweet];
    [self present:c];
}

- (void)present:(UIViewController *)c
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:c];
    if (CHIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [(self.vc ?: [CHLinkRouter topController]) presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Sheets

- (void)keepAlive { if (!g_live) g_live = [NSMutableArray array]; [g_live addObject:self]; }
- (void)letGo { CHTweetActions *me = self; dispatch_async(dispatch_get_main_queue(), ^{ [g_live removeObject:me]; }); }

- (void)showRetweetSheet
{
    self.retweetSheet = YES;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:self.tweet.retweeted ? L(@"Undo repost") : L(@"Repost")];
    [sheet addButtonWithTitle:L(@"Quote")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    [self keepAlive];
    [self show:sheet];
}

- (void)showMoreSheet
{
    self.retweetSheet = NO;
    NSMutableArray *actions = [NSMutableArray array];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:L(@"Copy link")]; [actions addObject:@(CHMoreCopy)];
    [sheet addButtonWithTitle:L(@"Share")]; [actions addObject:@(CHMoreShare)];
    [sheet addButtonWithTitle:L(@"Open in browser")]; [actions addObject:@(CHMoreOpen)];
    NSString *me = [CHTwitter accountHandle];
    if (me.length && [self.tweet.author.handle caseInsensitiveCompare:me] == NSOrderedSame) {
        [sheet addButtonWithTitle:L(@"Delete")];
        [actions addObject:@(CHMoreDelete)];
        sheet.destructiveButtonIndex = (NSInteger)actions.count - 1;
    }
    self.moreActions = actions;
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    [self keepAlive];
    [self show:sheet];
}

- (void)show:(UIActionSheet *)sheet
{
    [CHExternalOpen showSheet:sheet from:(self.vc ?: [CHLinkRouter topController]) anchor:self.cell];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    if (index < 0 || index == sheet.cancelButtonIndex) return;
    if (self.retweetSheet) {
        if (index == 0) [self toggleRetweet];
        else if (index == 1) [self quote];
        return;
    }
    if (index >= (NSInteger)self.moreActions.count) return;
    NSString *url = self.tweet.shareURL;
    switch ((CHMoreAction)[[self.moreActions objectAtIndex:(NSUInteger)index] integerValue]) {
        case CHMoreCopy: [UIPasteboard generalPasteboard].string = url; [CHUtils alertWithTitle:L(@"Copy link") message:L(@"Link copied.")]; break;
        case CHMoreShare: if (url.length) [CHExternalOpen presentShareSheetForURL:[NSURL URLWithString:url] from:(self.vc ?: [CHLinkRouter topController]) anchor:self.cell]; break;
        case CHMoreOpen: if (url.length) [CHExternalOpen openInSafari:[NSURL URLWithString:url]]; break;
        case CHMoreDelete: [self confirmDelete]; break;
    }
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index { sheet.delegate = nil; [self letGo]; }

- (void)confirmDelete
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Delete") message:L(@"Delete this post?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Delete"), nil];
    [self keepAlive];
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex)
        [CHTwitter performAction:@"delete" onId:self.tweet.tweetId completion:^(BOOL ok, NSError *error) {
            [CHUtils alertWithTitle:L(@"Delete") message:ok ? L(@"Deleted.") : (error.localizedDescription ?: L(@"That did not work."))];
        }];
    [self letGo];
}

@end

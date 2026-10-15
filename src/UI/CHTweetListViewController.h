#import <UIKit/UIKit.h>
#import "CHTweetCell.h"

// A table of tweets with pull-to-refresh, infinite scroll and the empty / error states. Subclasses implement
// -fetchWithCursor:completion: (nil cursor = the first page / a refresh). Home, a profile's tweets, bookmarks and
// search results are all this, with a different fetch.
@interface CHTweetListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, CHTweetCellDelegate>

@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSMutableArray *tweets;       // CHTweet
@property (nonatomic, copy) NSString *emptyMessage;         // shown when a load returns nothing

- (void)reload;        // fresh (also pull-to-refresh)
- (void)loadMore;
- (void)showStatus:(NSString *)message;    // centred message (empty / error); nil hides it
- (void)installSettingsButton;             // a gear in the left bar that presents Settings
- (void)openSettings;

// Subclasses override. Call completion on the main thread with a page to append (its tweets, bottomCursor, hasMore)
// or an error. A refresh passes cursor == nil.
- (void)fetchWithCursor:(NSString *)cursor completion:(void (^)(CHTweetPage *page, NSError *error))completion;

// Replace the whole list (e.g. local bookmarks). Subclasses that have all data at once can call this instead.
- (void)setTweetsAndReloadTable:(NSArray *)tweets;

@end

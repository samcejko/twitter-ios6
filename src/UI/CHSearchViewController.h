#import "CHTweetListViewController.h"

// Explore: a search bar, Top / Latest / People, and the trends when nothing is being searched.
@interface CHSearchViewController : CHTweetListViewController
- (instancetype)initWithQuery:(NSString *)query;
- (void)searchFor:(NSString *)query;       // run a search (e.g. a tapped #hashtag)
@end

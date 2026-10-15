#import "CHTweetListViewController.h"

typedef enum { CHTimelineHome, CHTimelineSaved } CHTimelineMode;

// The home timeline (For You / Following, switched from a segmented control in the bar) and the local bookmarks list.
@interface CHTimelineViewController : CHTweetListViewController
- (instancetype)initWithMode:(CHTimelineMode)mode;
@end

#import <UIKit/UIKit.h>
#import "CHModels.h"

@class CHTweetCell;

@protocol CHTweetCellDelegate <NSObject>
@optional
- (void)tweetCell:(CHTweetCell *)cell didTapUser:(CHUser *)user;
- (void)tweetCell:(CHTweetCell *)cell didTapMediaAtIndex:(NSInteger)index;
- (void)tweetCell:(CHTweetCell *)cell didTapQuoted:(CHTweet *)quoted;
- (void)tweetCellDidToggleSave:(CHTweetCell *)cell;
@end

// One tweet in a list. iOS 6 has no self-sizing cells, so the geometry is computed once (CHTweetComputeLayout) and
// used both to lay the subviews out and to answer +heightForTweet:width:.
@interface CHTweetCell : UITableViewCell
@property (nonatomic, strong) CHTweet *tweet;
@property (nonatomic, weak) id<CHTweetCellDelegate> delegate;
@property (nonatomic) BOOL expanded;     // the focal tweet of a thread: bigger text (tappable links), a full date line
- (void)setTweet:(CHTweet *)tweet;       // set `expanded` before this
- (void)setSaved:(BOOL)saved;            // the list sets the bookmark star's state (the cell has no store)
+ (CGFloat)heightForTweet:(CHTweet *)tweet width:(CGFloat)width;
+ (CGFloat)heightForTweet:(CHTweet *)tweet width:(CGFloat)width expanded:(BOOL)expanded;
@end

#import <UIKit/UIKit.h>

// One direct-message conversation: the history and a box to send a message.
@interface CHConversationViewController : UIViewController
- (instancetype)initWithHandle:(NSString *)handle userId:(NSString *)userId name:(NSString *)name;
@end

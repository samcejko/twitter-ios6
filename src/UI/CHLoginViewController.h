#import <UIKit/UIKit.h>

// Sign in by pasting the X cookies (auth_token + ct0) from a browser. They are kept only on the device (keychain)
// and sent with each request; nothing is stored on the server.
@interface CHLoginViewController : UITableViewController
@end

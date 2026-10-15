#import "CHComposeViewController.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#define CHTweetLimit 280

@interface CHComposeViewController () <UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) CHTweet *replyTarget;
@property (nonatomic, strong) CHTweet *quoteTarget;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UILabel *contextLabel;      // "Replying to @x" / "Quoting @x: …"
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIButton *removePhoto;
@property (nonatomic, strong) UILabel *counter;
@property (nonatomic, strong) UIImage *attachedImage;
@property (nonatomic, strong) UIBarButtonItem *postItem;
@property (nonatomic) BOOL posting;
@end

@implementation CHComposeViewController

+ (instancetype)composeNew { return [[self alloc] init]; }
+ (instancetype)composeReplyTo:(CHTweet *)tweet { CHComposeViewController *c = [[self alloc] init]; c.replyTarget = tweet; return c; }
+ (instancetype)composeQuoteOf:(CHTweet *)tweet { CHComposeViewController *c = [[self alloc] init]; c.quoteTarget = tweet; return c; }

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th cardColor];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    CHTheme *th = [CHTheme shared];
    self.title = self.replyTarget ? L(@"Reply") : self.quoteTarget ? L(@"Quote") : L(@"New Tweet");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.postItem = [[UIBarButtonItem alloc] initWithTitle:(self.replyTarget ? L(@"Reply") : L(@"Post")) style:UIBarButtonItemStyleDone target:self action:@selector(post)];
    self.navigationItem.rightBarButtonItem = self.postItem;

    CGFloat y = 8;
    if (self.replyTarget || self.quoteTarget) {
        self.contextLabel = [[UILabel alloc] init];
        self.contextLabel.font = [th smallFont];
        self.contextLabel.textColor = [th secondaryTextColor];
        self.contextLabel.numberOfLines = 2;
        self.contextLabel.backgroundColor = [UIColor clearColor];
        if (self.replyTarget) self.contextLabel.text = [NSString stringWithFormat:L(@"Replying to @%@"), self.replyTarget.author.handle ?: @""];
        else self.contextLabel.text = [NSString stringWithFormat:L(@"Quoting @%@: %@"), self.quoteTarget.author.handle ?: @"",
                                       [CHUtils truncate:[CHUtils displayText:self.quoteTarget.text] to:80]];
        [self.view addSubview:self.contextLabel];
    }

    self.textView = [[UITextView alloc] init];
    self.textView.font = [UIFont systemFontOfSize:CHIsPad() ? 19 : 17];
    self.textView.delegate = self;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [th primaryTextColor];
    [self.view addSubview:self.textView];

    self.placeholder = [[UILabel alloc] init];
    self.placeholder.font = self.textView.font;
    self.placeholder.textColor = [th placeholderColor];
    self.placeholder.text = self.replyTarget ? L(@"Post your reply") : L(@"What's happening?");
    [self.view addSubview:self.placeholder];

    self.photoView = [[UIImageView alloc] init];
    self.photoView.contentMode = UIViewContentModeScaleAspectFill;
    self.photoView.clipsToBounds = YES;
    self.photoView.layer.cornerRadius = 10;
    self.photoView.hidden = YES;
    [self.view addSubview:self.photoView];
    self.removePhoto = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.removePhoto setImage:[th closeIconWhite] forState:UIControlStateNormal];
    self.removePhoto.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.removePhoto.layer.cornerRadius = 14;
    self.removePhoto.hidden = YES;
    [self.removePhoto addTarget:self action:@selector(removeImage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.removePhoto];

    // keyboard accessory: a photo button and the character counter
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    [th applyToToolbar:bar];
    self.counter = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 44, 20)];
    self.counter.font = [UIFont systemFontOfSize:13];
    self.counter.textColor = [th secondaryTextColor];
    self.counter.textAlignment = NSTextAlignmentRight;
    self.counter.backgroundColor = [UIColor clearColor];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:L(@"Photo") style:UIBarButtonItemStyleBordered target:self action:@selector(pickPhoto)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    bar.items = @[ photo, flex, [[UIBarButtonItem alloc] initWithCustomView:self.counter] ];
    self.textView.inputAccessoryView = bar;

    [self updatePost];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat pad = 12, w = self.view.bounds.size.width - 2 * pad;
    CGFloat y = [self topInset] + 8;
    if (self.contextLabel) {
        CGFloat h = ceilf((float)[self.contextLabel.text sizeWithFont:self.contextLabel.font constrainedToSize:CGSizeMake(w, 60) lineBreakMode:NSLineBreakByWordWrapping].height);
        self.contextLabel.frame = CGRectMake(pad, y, w, h);
        y += h + 6;
    }
    CGFloat photoH = self.attachedImage ? 140 : 0;
    self.textView.frame = CGRectMake(pad - 4, y, w + 8, self.view.bounds.size.height - y - photoH - 16);
    self.placeholder.frame = CGRectMake(pad, y + 8, w, 24);
    if (self.attachedImage) {
        CGFloat pw = MIN(w, 220);
        self.photoView.frame = CGRectMake(pad, self.view.bounds.size.height - photoH - 8, pw, 132);
        self.removePhoto.frame = CGRectMake(CGRectGetMaxX(self.photoView.frame) - 30, self.photoView.frame.origin.y + 6, 28, 28);
    }
}

- (CGFloat)topInset
{
    CGFloat nav = self.navigationController.navigationBar.frame.size.height;
    CGRect sb = [UIApplication sharedApplication].statusBarFrame;
    return nav + MIN(sb.size.width, sb.size.height);
}

- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self.textView becomeFirstResponder]; }

#pragma mark - State

- (void)textViewDidChange:(UITextView *)textView { [self updatePost]; [self.view setNeedsLayout]; }

- (void)updatePost
{
    NSString *t = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger remaining = CHTweetLimit - (NSInteger)self.textView.text.length;
    self.counter.text = [NSString stringWithFormat:@"%ld", (long)remaining];
    self.counter.textColor = remaining < 0 ? [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:1] : [[CHTheme shared] secondaryTextColor];
    [self.counter sizeToFit];
    self.placeholder.hidden = self.textView.text.length > 0;
    self.postItem.enabled = !self.posting && (t.length > 0 || self.attachedImage != nil) && remaining >= 0;
}

#pragma mark - Photo

- (void)pickPhoto
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    [self dismissViewControllerAnimated:YES completion:^{
        if (image) {
            self.attachedImage = [self downscale:image to:1600];
            self.photoView.image = self.attachedImage;
            self.photoView.hidden = self.removePhoto.hidden = NO;
            [self.view setNeedsLayout];
            [self updatePost];
        }
        [self.textView becomeFirstResponder];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:^{ [self.textView becomeFirstResponder]; }];
}

- (UIImage *)downscale:(UIImage *)image to:(CGFloat)maxSide
{
    CGFloat w = image.size.width, h = image.size.height, m = MAX(w, h);
    if (m <= maxSide) return image;
    CGFloat s = maxSide / m;
    CGSize size = CGSizeMake(roundf(w * s), roundf(h * s));
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

- (void)removeImage
{
    self.attachedImage = nil;
    self.photoView.hidden = self.removePhoto.hidden = YES;
    [self.view setNeedsLayout];
    [self updatePost];
}

#pragma mark - Post

- (void)cancel { [self.textView resignFirstResponder]; [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)post
{
    if (self.posting) return;
    self.posting = YES;
    [self updatePost];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    NSData *image = self.attachedImage ? UIImageJPEGRepresentation(self.attachedImage, 0.85) : nil;
    [CHTwitter postText:self.textView.text
                replyTo:self.replyTarget.tweetId
               quoteURL:self.quoteTarget.shareURL
              imageData:image
              imageType:@"jpg"
             completion:^(NSString *newId, NSError *error) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        self.posting = NO;
        if (newId.length) {
            [self.textView resignFirstResponder];
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self updatePost];
            [CHUtils alertWithTitle:L(@"Post") message:error.localizedDescription ?: L(@"The post could not be sent.")];
        }
    }];
}

@end

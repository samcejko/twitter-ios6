#import "CHConversationViewController.h"
#import "CHTwitter.h"
#import "CHTheme.h"
#import "CHUtils.h"
#import "CHCommon.h"

#pragma mark - A message bubble

@interface CHMessageCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *label;
- (void)setMessage:(CHMessage *)m;
+ (UIFont *)font;
+ (CGFloat)heightFor:(CHMessage *)m width:(CGFloat)width;
@end

@implementation CHMessageCell
+ (UIFont *)font { return [UIFont systemFontOfSize:CHIsPad() ? 17 : 15]; }
+ (CGFloat)bubbleMaxWidth:(CGFloat)width { return floorf(width * 0.74); }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid
{
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [[CHTheme shared] backgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [[UIView alloc] init];
        _bubble.layer.cornerRadius = 16;
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.font = [CHMessageCell font];
        _label.backgroundColor = [UIColor clearColor];
        [_bubble addSubview:_label];
        [self.contentView addSubview:_bubble];
    }
    return self;
}

- (void)setMessage:(CHMessage *)m
{
    CHTheme *th = [CHTheme shared];
    self.label.text = [CHUtils displayText:m.text];
    if (m.fromMe) { self.bubble.backgroundColor = [th accentColor]; self.label.textColor = [UIColor whiteColor]; }
    else { self.bubble.backgroundColor = th.isDark ? [UIColor colorWithWhite:0.22 alpha:1] : [UIColor colorWithWhite:0.90 alpha:1]; self.label.textColor = [th primaryTextColor]; }
    self.tag = m.fromMe ? 1 : 0;
    [self setNeedsLayout];
}

+ (CGFloat)heightFor:(CHMessage *)m width:(CGFloat)width
{
    CGFloat maxW = [self bubbleMaxWidth:width] - 24;
    CGSize sz = [[CHUtils displayText:m.text] sizeWithFont:[self font] constrainedToSize:CGSizeMake(maxW, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf((float)sz.height) + 20 + 10;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat pad = 10, width = self.contentView.bounds.size.width;
    CGFloat maxW = [CHMessageCell bubbleMaxWidth:width] - 24;
    CGSize sz = [self.label.text sizeWithFont:[CHMessageCell font] constrainedToSize:CGSizeMake(maxW, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat bw = ceilf((float)sz.width) + 24, bh = ceilf((float)sz.height) + 20;
    CGFloat x = (self.tag == 1) ? width - pad - bw : pad;
    self.bubble.frame = CGRectMake(x, 5, bw, bh);
    self.label.frame = CGRectMake(12, 10, bw - 24, bh - 20);
}
@end

#pragma mark - Conversation

@interface CHConversationViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *send;
@property (nonatomic, strong) NSMutableArray *messages;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic) BOOL sending;
@end

@implementation CHConversationViewController

- (instancetype)initWithHandle:(NSString *)handle userId:(NSString *)userId name:(NSString *)name
{
    if ((self = [super init])) {
        _handle = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
        _userId = userId; _messages = [NSMutableArray array];
        self.title = name.length ? name : (_handle.length ? [@"@" stringByAppendingString:_handle] : L(@"Messages"));
    }
    return self;
}

- (void)loadView
{
    CHTheme *th = [CHTheme shared];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [th backgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [th backgroundColor];
    self.tableView.allowsSelection = NO;
    [self.view addSubview:self.tableView];

    self.inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 48, self.view.bounds.size.width, 48)];
    self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.inputBar.backgroundColor = [th cardColor];
    self.field = [[UITextField alloc] init];
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.placeholder = L(@"Message");
    self.field.delegate = self;
    self.field.returnKeyType = UIReturnKeySend;
    self.field.font = [UIFont systemFontOfSize:16];
    [self.inputBar addSubview:self.field];
    self.send = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.send setTitle:L(@"Send") forState:UIControlStateNormal];
    [self.send setTitleColor:[th accentColor] forState:UIControlStateNormal];
    self.send.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.send addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.send];
    [self.view addSubview:self.inputBar];

    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = [th secondaryTextColor]; self.status.font = [th bodyFont]; self.status.hidden = YES;
    [self.view addSubview:self.status];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
    [self load];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    self.field.frame = CGRectMake(10, 8, w - 20 - 60, 32);
    self.send.frame = CGRectMake(w - 66, 6, 60, 36);
    self.status.frame = CGRectInset(self.view.bounds, 28, 0);
    [self adjustInsets];
}

- (void)adjustInsets
{
    CGFloat bottom = self.view.bounds.size.height - self.inputBar.frame.origin.y;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
}

- (void)keyboard:(NSNotification *)note
{
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:end fromView:nil];
    CGFloat top = MIN(local.origin.y, self.view.bounds.size.height);
    [UIView animateWithDuration:0.25 animations:^{
        self.inputBar.frame = CGRectMake(0, top - 48, self.view.bounds.size.width, 48);
        [self adjustInsets];
    }];
    [self scrollToBottom:NO];
}

- (void)load
{
    if (![CHTwitter configured]) { self.status.text = L(@"Set the server address in Settings first."); self.status.hidden = NO; return; }
    [CHTwitter dmHistoryWith:self.handle userId:self.userId cursor:nil completion:^(NSArray *messages, NSString *uid, NSString *cursor, BOOL more, NSError *error) {
        if (uid.length) self.userId = uid;
        if (messages) { [self.messages setArray:messages]; [self.tableView reloadData]; [self scrollToBottom:NO]; }
        if (!self.messages.count) { self.status.text = error.localizedDescription ?: L(@"No messages yet. Say hi!"); self.status.hidden = NO; }
        else self.status.hidden = YES;
    }];
}

- (void)scrollToBottom:(BOOL)animated
{
    if (!self.messages.count) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self sendMessage]; return NO; }

- (void)sendMessage
{
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || self.sending) return;
    self.sending = YES;
    self.field.text = @"";
    [CHTwitter sendDM:text to:self.handle userId:self.userId completion:^(CHMessage *message, NSString *uid, NSError *error) {
        self.sending = NO;
        if (uid.length) self.userId = uid;
        if (message) { [self.messages addObject:message]; self.status.hidden = YES; [self.tableView reloadData]; [self scrollToBottom:YES]; }
        else { self.field.text = text; [CHUtils alertWithTitle:L(@"Message") message:error.localizedDescription ?: L(@"The message could not be sent.")]; }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.messages.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CHMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"m"];
    if (!cell) cell = [[CHMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"m"];
    [cell setMessage:self.messages[(NSUInteger)indexPath.row]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [CHMessageCell heightFor:self.messages[(NSUInteger)indexPath.row] width:tableView.bounds.size.width];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end

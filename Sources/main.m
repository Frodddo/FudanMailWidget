#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

static NSString * const ServiceName = @"com.openai.fudan-mail-widget";

static NSString *KeychainPassword(NSString *account) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ServiceName,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL SaveKeychainPassword(NSString *account, NSString *password, NSError **error) {
    NSDictionary *key = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ServiceName,
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)key);
    NSMutableDictionary *item = [key mutableCopy];
    item[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecSuccess) return YES;
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return NO;
}

@interface DesktopWindow : NSWindow @end
@implementation DesktopWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface DraggableEffectView : NSVisualEffectView @end
@implementation DraggableEffectView
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

@interface DragView : NSView @end
@implementation DragView
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

@interface DragLabel : NSTextField @end
@implementation DragLabel
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

@interface FirstClickButton : NSButton @end
@implementation FirstClickButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

static NSButton *IconButton(NSString *symbol, NSString *description, id target, SEL action) {
    FirstClickButton *button = [[FirstClickButton alloc] initWithFrame:NSZeroRect];
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
    button.target = target;
    button.action = action;
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.buttonType = NSButtonTypeMomentaryChange;
    return button;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property DesktopWindow *window;
@property NSTextField *countLabel;
@property NSTextField *statusLabel;
@property NSStackView *messageStack;
@property NSTimer *dailyTimer;
@property NSButton *refreshButton;
@property NSString *sessionAccount;
@property NSString *sessionPassword;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self buildWindow];
    [self scheduleDailyRefresh];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(wokeFromSleep:) name:NSWorkspaceDidWakeNotification object:nil];
    if ([self credentials]) [self refresh:nil]; else [self showSettings:nil];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(40, 120, 292, 174);
    self.window = [[DesktopWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    [self.window standardWindowButton:NSWindowCloseButton].hidden = YES;
    [self.window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.movable = YES;
    self.window.movableByWindowBackground = YES;
    self.window.ignoresMouseEvents = NO;
    self.window.acceptsMouseMovedEvents = YES;
    self.window.contentMinSize = NSMakeSize(250, 140);
    self.window.contentMaxSize = NSMakeSize(500, 360);
    // Above Finder's desktop-icons window so real mouse events reach the card,
    // while remaining below ordinary application windows.
    self.window.level = CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    [self.window setFrameAutosaveName:@"FudanMailWidgetFrame"];

    DraggableEffectView *effect = [[DraggableEffectView alloc] initWithFrame:frame];
    effect.material = NSVisualEffectMaterialSidebar;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.alphaValue = 0.94;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 16;
    effect.layer.masksToBounds = YES;
    effect.layer.borderWidth = 0.5;
    effect.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
    self.window.contentView = effect;

    DragLabel *title = [[DragLabel alloc] initWithFrame:NSZeroRect];
    title.stringValue = @"复旦云邮箱";
    title.bezeled = NO;
    title.editable = NO;
    title.selectable = NO;
    title.drawsBackground = NO;
    title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];

    self.countLabel = [NSTextField labelWithString:@"—"];
    self.countLabel.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
    self.countLabel.textColor = NSColor.systemBlueColor;
    self.countLabel.alignment = NSTextAlignmentRight;

    NSTextField *unreadText = [NSTextField labelWithString:@"封未读"];
    unreadText.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    unreadText.textColor = NSColor.secondaryLabelColor;

    NSStackView *countStack = [NSStackView stackViewWithViews:@[self.countLabel, unreadText]];
    countStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    countStack.alignment = NSLayoutAttributeCenterY;
    countStack.spacing = 4;

    self.refreshButton = IconButton(@"arrow.clockwise", @"刷新", self, @selector(refresh:));
    self.refreshButton.contentTintColor = NSColor.systemBlueColor;
    NSButton *settings = IconButton(@"gearshape", @"设置", self, @selector(showSettings:));
    NSButton *resize = IconButton(@"arrow.up.left.and.arrow.down.right", @"调整大小", self, @selector(toggleSize:));
    NSButton *quit = IconButton(@"xmark.circle", @"退出", self, @selector(quit:));
    for (NSButton *button in @[self.refreshButton, settings, resize, quit]) button.bordered = NO;
    self.refreshButton.toolTip = @"立即检查"; settings.toolTip = @"邮箱设置"; resize.toolTip = @"切换大小，也可拖动边缘"; quit.toolTip = @"退出";

    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.refreshButton, settings, resize, quit]];
    buttons.spacing = 5;

    DragView *spacer = [DragView new];
    NSStackView *header = [NSStackView stackViewWithViews:@[title, spacer, countStack, buttons]];
    header.alignment = NSLayoutAttributeCenterY;

    self.messageStack = [NSStackView new];
    self.messageStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.messageStack.alignment = NSLayoutAttributeLeading;
    self.messageStack.spacing = 5;
    self.messageStack.distribution = NSStackViewDistributionFillEqually;

    self.statusLabel = [NSTextField labelWithString:@"尚未检查"];
    self.statusLabel.font = [NSFont systemFontOfSize:10];
    self.statusLabel.textColor = NSColor.tertiaryLabelColor;

    NSStackView *root = [NSStackView stackViewWithViews:@[header, self.messageStack, self.statusLabel]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 8;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:14],
        [root.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor constant:-14],
        [root.topAnchor constraintEqualToAnchor:effect.topAnchor constant:10],
        [root.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor constant:-10],
        [header.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [self.messageStack.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [self.statusLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor]
    ]];
    [self renderPlaceholder:@"每天 09:30 自动检查\n点击齿轮完成邮箱设置"];
    [self.window orderFrontRegardless];
}

- (NSArray *)credentials {
    NSString *account = [[NSUserDefaults standardUserDefaults] stringForKey:@"email"];
    if ([account isEqualToString:self.sessionAccount] && self.sessionPassword.length) return @[account, self.sessionPassword];
    NSString *password = account.length ? KeychainPassword(account) : nil;
    if (account.length && password.length) {
        self.sessionAccount = account;
        self.sessionPassword = password;
    }
    return (account.length && password.length) ? @[account, password] : nil;
}

- (void)showSettings:(id)sender {
    // A desktop-level accessory window does not reliably receive keyboard focus
    // when started by launchd. Temporarily become a regular foreground app while
    // the credentials sheet is open, then return to accessory mode.
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    self.window.level = NSFloatingWindowLevel;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"设置复旦云邮箱";
    alert.informativeText = @"请输入完整的 @m.fudan.edu.cn 地址和客户端专用密码。密码只保存到 macOS 钥匙串。";
    [alert addButtonWithTitle:@"保存并检查"];
    [alert addButtonWithTitle:@"取消"];

    NSTextField *emailField = [NSTextField textFieldWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"email"] ?: @""];
    emailField.placeholderString = @"学号@m.fudan.edu.cn";
    NSSecureTextField *passwordField = [NSSecureTextField textFieldWithString:@""];
    passwordField.placeholderString = @"客户端专用密码";
    NSStackView *form = [NSStackView stackViewWithViews:@[emailField, passwordField]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 10;
    form.frame = NSMakeRect(0, 0, 330, 62);
    [NSLayoutConstraint activateConstraints:@[
        [emailField.widthAnchor constraintEqualToConstant:330],
        [emailField.heightAnchor constraintEqualToConstant:26],
        [passwordField.widthAnchor constraintEqualToConstant:330],
        [passwordField.heightAnchor constraintEqualToConstant:26]
    ]];
    alert.accessoryView = form;

    alert.window.level = NSModalPanelWindowLevel;
    alert.window.initialFirstResponder = emailField;
    [alert.window makeKeyAndOrderFront:nil];
    [alert.window makeFirstResponder:emailField];

    NSModalResponse response = [alert runModal];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.window.level = CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1;
    if (response != NSAlertFirstButtonReturn) return;

    NSString *account = [emailField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSString *password = passwordField.stringValue;
    if (![account hasSuffix:@"@m.fudan.edu.cn"] || !password.length) {
        [self showError:@"请输入完整的 @m.fudan.edu.cn 邮箱地址和客户端专用密码。"];
        return;
    }
    NSError *error = nil;
    if (!SaveKeychainPassword(account, password, &error)) {
        [self showError:[NSString stringWithFormat:@"无法保存到钥匙串：%@", error.localizedDescription]];
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:account forKey:@"email"];
    self.sessionAccount = account;
    self.sessionPassword = password;
    [self refresh:nil];
}

- (void)refresh:(id)sender {
    NSArray *credentials = [self credentials];
    if (!credentials) { [self renderPlaceholder:@"尚未配置邮箱\n点击齿轮开始设置"]; return; }
    self.refreshButton.enabled = NO;
    self.statusLabel.stringValue = @"正在安全连接…";
    NSString *script = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"check_mail.py"].path;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
        task.arguments = @[script, credentials[0]];
        NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe], *errors = [NSPipe pipe];
        task.standardInput = input; task.standardOutput = output; task.standardError = errors;
        NSError *runError = nil;
        if (![task launchAndReturnError:&runError]) { [self finishWithError:runError.localizedDescription]; return; }
        [[input fileHandleForWriting] writeData:[credentials[1] dataUsingEncoding:NSUTF8StringEncoding]];
        [[input fileHandleForWriting] closeFile];
        [task waitUntilExit];
        NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
        NSData *errorData = [[errors fileHandleForReading] readDataToEndOfFile];
        if (task.terminationStatus != 0) {
            NSString *message = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] ?: @"未知错误";
            [self finishWithError:[message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            return;
        }
        NSDictionary *summary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&runError];
        if (!summary) { [self finishWithError:runError.localizedDescription]; return; }
        dispatch_async(dispatch_get_main_queue(), ^{ [self render:summary]; });
    });
}

- (void)finishWithError:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.refreshButton.enabled = YES;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss";
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ 刷新失败：%@", [formatter stringFromDate:NSDate.date], message ?: @"未知错误"];
    });
}

- (void)render:(NSDictionary *)summary {
    self.refreshButton.enabled = YES;
    self.countLabel.stringValue = [summary[@"unread"] stringValue];
    for (NSView *view in self.messageStack.arrangedSubviews.copy) [self.messageStack removeArrangedSubview:view], [view removeFromSuperview];
    NSArray *messages = summary[@"messages"];
    if (!messages.count) {
        [self renderPlaceholder:@"收件箱很清净，没有未读邮件"];
    } else {
        for (NSDictionary *item in [messages subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)3, messages.count))]) {
            NSString *subject = [item[@"subject"] length] ? item[@"subject"] : @"（无主题）";
            NSString *line = [NSString stringWithFormat:@"%@\n%@ · %@", subject, item[@"from"], item[@"date"]];
            NSTextField *label = [NSTextField wrappingLabelWithString:line];
            label.font = [NSFont systemFontOfSize:11];
            label.maximumNumberOfLines = 2;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            [self.messageStack addArrangedSubview:label];
            [label.widthAnchor constraintEqualToAnchor:self.messageStack.widthAnchor].active = YES;
        }
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"M月d日 HH:mm";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"上次检查：%@ · 每天 09:30", [formatter stringFromDate:NSDate.date]];
    [[NSUserDefaults standardUserDefaults] setObject:NSDate.date forKey:@"lastRefresh"];
}

- (void)renderPlaceholder:(NSString *)text {
    for (NSView *view in self.messageStack.arrangedSubviews.copy) [self.messageStack removeArrangedSubview:view], [view removeFromSuperview];
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:13];
    label.textColor = NSColor.secondaryLabelColor;
    [self.messageStack addArrangedSubview:label];
    [label.widthAnchor constraintEqualToAnchor:self.messageStack.widthAnchor].active = YES;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new]; alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"设置未保存"; alert.informativeText = message; [alert runModal];
}

- (void)scheduleDailyRefresh {
    [self.dailyTimer invalidate];
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:NSDate.date];
    parts.hour = 9; parts.minute = 30; parts.second = 0;
    NSDate *next = [calendar dateFromComponents:parts];
    if ([next compare:NSDate.date] != NSOrderedDescending) next = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:next options:0];
    self.dailyTimer = [[NSTimer alloc] initWithFireDate:next interval:86400 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.dailyTimer forMode:NSRunLoopCommonModes];
}

- (void)wokeFromSleep:(NSNotification *)notification {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:NSDate.date];
    parts.hour = 9; parts.minute = 30;
    NSDate *scheduled = [calendar dateFromComponents:parts];
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastRefresh"] ?: NSDate.distantPast;
    if ([NSDate.date compare:scheduled] != NSOrderedAscending && [last compare:scheduled] == NSOrderedAscending) [self refresh:nil];
    [self scheduleDailyRefresh];
}

- (void)quit:(id)sender { [NSApp terminate:nil]; }

- (void)toggleSize:(id)sender {
    NSRect frame = self.window.frame;
    NSSize next;
    if (frame.size.width < 330) next = NSMakeSize(380, 260);
    else if (frame.size.width < 430) next = NSMakeSize(500, 340);
    else next = NSMakeSize(292, 174);
    frame.origin.y += frame.size.height - next.height;
    frame.size = next;
    [self.window setFrame:frame display:YES animate:YES];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

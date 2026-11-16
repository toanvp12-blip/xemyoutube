#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>
#import <notify.h>

extern char **environ;
static NSString * const kNotifSettingsChanged = @"XemYouTubeSettingsChangedNotification";

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (PrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface AppSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL autoOpenCarPlay;
@property (nonatomic, assign) BOOL restoreLastLayout;
@property (nonatomic, assign) BOOL autoDimScreen;
@property (nonatomic, assign) BOOL showSpeedBubble;
@property (nonatomic, assign) NSInteger speedLimitValue;
@property (nonatomic, assign) NSInteger defaultSplitMode;
- (void)resetAll;
@end

@implementation AppSettings
+ (instancetype)shared {
    static AppSettings *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [[AppSettings alloc] init]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:@"cfg_init"] == nil) {
            [ud setBool:YES forKey:@"cfg_init"];
            [ud setBool:YES forKey:@"autoOpenCarPlay"];
            [ud setBool:YES forKey:@"restoreLastLayout"];
            [ud setBool:NO  forKey:@"autoDimScreen"];
            [ud setBool:YES forKey:@"showSpeedBubble"];
            [ud setInteger:50 forKey:@"speedLimitValue"];
            [ud setInteger:1  forKey:@"defaultSplitMode"];
        }
    }
    return self;
}
- (BOOL)showSpeedBubble { return [[NSUserDefaults standardUserDefaults] boolForKey:@"showSpeedBubble"]; }
- (void)setShowSpeedBubble:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"showSpeedBubble"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}
- (NSInteger)speedLimitValue { return [[NSUserDefaults standardUserDefaults] integerForKey:@"speedLimitValue"] ?: 50; }
- (void)setSpeedLimitValue:(NSInteger)v {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"speedLimitValue"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}
- (NSInteger)defaultSplitMode { return [[NSUserDefaults standardUserDefaults] integerForKey:@"defaultSplitMode"]; }
- (void)setDefaultSplitMode:(NSInteger)v {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"defaultSplitMode"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}
- (void)resetAll {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[@"cfg_init", @"autoOpenCarPlay", @"restoreLastLayout", @"autoDimScreen", @"showSpeedBubble", @"speedLimitValue", @"defaultSplitMode"]) [ud removeObjectForKey:key];
    [ud setBool:YES forKey:@"showSpeedBubble"];
    [ud setInteger:50 forKey:@"speedLimitValue"];
    [ud setInteger:1 forKey:@"defaultSplitMode"];
    [ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}
@end

@interface InstalledAppItem : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *mirrorURL;
@end

@implementation InstalledAppItem
@end

static NSString *MirrorURLForApp(NSString *bundleID, NSString *name) {
    NSString *k = [NSString stringWithFormat:@"%@ %@", bundleID.lowercaseString, name.lowercaseString];
    if ([k containsString:@"youtube"]) return @"https://m.youtube.com";
    if ([k containsString:@"vietmap"]) return nil;
    if ([k containsString:@"maps"]) return @"https://www.google.com/maps";
    if ([k containsString:@"zing"]) return @"https://zingmp3.vn";
    if ([k containsString:@"spotify"] || [k containsString:@"nhạc"]) return @"https://open.spotify.com";
    if ([k containsString:@"tiktok"]) return @"https://www.tiktok.com";
    if ([k containsString:@"zalo"]) return @"https://chat.zalo.me";
    if ([k containsString:@"telegram"]) return @"https://web.telegram.org";
    return [NSString stringWithFormat:@"https://www.google.com/search?igu=1&q=%@", [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @""];
}

static NSArray<InstalledAppItem *> *ScanDeviceApps(void) {
    NSMutableArray<InstalledAppItem *> *list = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass) {
        id ws = [wsClass defaultWorkspace];
        NSArray *all = [ws allInstalledApplications];
        for (id proxy in all) {
            NSString *bid = [proxy valueForKey:@"applicationIdentifier"];
            NSString *type = [proxy valueForKey:@"applicationType"];
            NSString *name = [proxy valueForKey:@"localizedName"];
            if (!bid || !name || name.length == 0) continue;
            if ([bid isEqualToString:@"com.xemyoutube"]) continue;
            if (![type isEqualToString:@"User"] && ![bid isEqualToString:@"com.apple.Maps"] && ![bid isEqualToString:@"com.apple.Music"]) continue;

            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = bid;
            item.name = name;
            item.mirrorURL = MirrorURLForApp(bid, name);
            if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
                item.icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
            }
            if (!item.icon) item.icon = [UIImage systemImageNamed:@"app.fill"];
            [list addObject:item];
        }
    }
    [list sortUsingComparator:^NSComparisonResult(InstalledAppItem *a, InstalledAppItem *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return list;
}

@class MultiTaskPaneView;
@protocol MultiTaskPaneDelegate <NSObject>
- (void)paneDidRequestAppPicker:(MultiTaskPaneView *)pane;
- (void)paneDidRequestLayoutSheet:(MultiTaskPaneView *)pane;
- (void)paneDidRequestOpenNativeApp:(MultiTaskPaneView *)pane;
@end

@interface MultiTaskPaneView : UIView <WKNavigationDelegate>
@property (nonatomic, assign) NSInteger paneNumber;
@property (nonatomic, weak) id<MultiTaskPaneDelegate> delegate;
@property (nonatomic, strong) UIButton *activeTabButton;
@property (nonatomic, strong) UIView *tabStripContainer;
@property (nonatomic, strong) UIStackView *tabStripStack;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIButton *recentEmptyBtn;
@property (nonatomic, strong) UIView *runningContainerView;
@property (nonatomic, strong) WKWebView *interactiveWebView;
@property (nonatomic, strong) NSMutableArray<InstalledAppItem *> *openedTabs;
@property (nonatomic, strong) InstalledAppItem *currentApp;
- (instancetype)initWithPaneNumber:(NSInteger)num;
- (void)openAppInPane:(InstalledAppItem *)app;
- (void)closeCurrentTab;
@end

@implementation MultiTaskPaneView

- (instancetype)initWithPaneNumber:(NSInteger)num {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.paneNumber = num;
        self.openedTabs = [NSMutableArray array];
        self.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
        self.clipsToBounds = YES;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIView *chromeBar = [[UIView alloc] init];
    chromeBar.backgroundColor = [UIColor colorWithRed:0.91 green:0.92 blue:0.95 alpha:1.0];
    chromeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:chromeBar];

    self.activeTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.activeTabButton.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    self.activeTabButton.layer.cornerRadius = 9;
    self.activeTabButton.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.activeTabButton setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
    [self.activeTabButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    self.activeTabButton.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    self.activeTabButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.activeTabButton.contentEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 5);
    self.activeTabButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activeTabButton addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    UIView *dotsContainer = [[UIView alloc] init];
    dotsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *bY = [self makeWindowCircle:[UIColor colorWithRed:0.96 green:0.74 blue:0.25 alpha:1.0] symbol:@"arrow.left.and.right" action:@selector(onTapYellow)];
    UIButton *bG = [self makeWindowCircle:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0] symbol:@"arrow.up.left.and.arrow.down.right" action:@selector(onTapGreen)];
    UIButton *bR = [self makeWindowCircle:[UIColor colorWithRed:0.95 green:0.35 blue:0.30 alpha:1.0] symbol:@"xmark" action:@selector(onTapRed)];

    [dotsContainer addSubview:bY]; [dotsContainer addSubview:bG]; [dotsContainer addSubview:bR];
    [NSLayoutConstraint activateConstraints:@[
        [dotsContainer.widthAnchor constraintEqualToConstant:48], [dotsContainer.heightAnchor constraintEqualToConstant:16],
        [bY.leadingAnchor constraintEqualToAnchor:dotsContainer.leadingAnchor], [bY.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor], [bY.widthAnchor constraintEqualToConstant:13], [bY.heightAnchor constraintEqualToConstant:13],
        [bG.centerXAnchor constraintEqualToAnchor:dotsContainer.centerXAnchor], [bG.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor], [bG.widthAnchor constraintEqualToConstant:13], [bG.heightAnchor constraintEqualToConstant:13],
        [bR.trailingAnchor constraintEqualToAnchor:dotsContainer.trailingAnchor], [bR.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor], [bR.widthAnchor constraintEqualToConstant:13], [bR.heightAnchor constraintEqualToConstant:13]
    ]];

    [chromeBar addSubview:self.activeTabButton];
    [chromeBar addSubview:dotsContainer];

    self.tabStripContainer = [[UIView alloc] init];
    self.tabStripContainer.backgroundColor = [UIColor systemBackgroundColor];
    self.tabStripContainer.hidden = YES;
    self.tabStripContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.tabStripContainer];

    UIScrollView *tabScroll = [[UIScrollView alloc] init];
    tabScroll.showsHorizontalScrollIndicator = NO;
    tabScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tabStripContainer addSubview:tabScroll];

    self.tabStripStack = [[UIStackView alloc] init];
    self.tabStripStack.spacing = 4;
    self.tabStripStack.translatesAutoresizingMaskIntoConstraints = NO;
    [tabScroll addSubview:self.tabStripStack];

    self.emptyStateView = [[UIView alloc] init];
    self.emptyStateView.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.emptyStateView];

    UILabel *recentHdr = [[UILabel alloc] init];
    recentHdr.text = @"Gần đây";
    recentHdr.font = [UIFont boldSystemFontOfSize:12];
    recentHdr.translatesAutoresizingMaskIntoConstraints = NO;

    self.recentEmptyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.recentEmptyBtn setTitle:@"Chưa có app gần đây" forState:UIControlStateNormal];
    [self.recentEmptyBtn setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    self.recentEmptyBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    self.recentEmptyBtn.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.recentEmptyBtn.layer.cornerRadius = 10;
    self.recentEmptyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.recentEmptyBtn addTarget:self action:@selector(onTapRecentButton) forControlEvents:UIControlEventTouchUpInside];

    UIButton *allAppsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [allAppsBtn setTitle:@"Tất cả app ›" forState:UIControlStateNormal];
    allAppsBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    allAppsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [allAppsBtn addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    [self.emptyStateView addSubview:recentHdr];
    [self.emptyStateView addSubview:self.recentEmptyBtn];
    [self.emptyStateView addSubview:allAppsBtn];

    self.runningContainerView = [[UIView alloc] init];
    self.runningContainerView.backgroundColor = [UIColor blackColor];
    self.runningContainerView.hidden = YES;
    self.runningContainerView.clipsToBounds = YES;
    self.runningContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.runningContainerView];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    self.interactiveWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.interactiveWebView.navigationDelegate = self;
    self.interactiveWebView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
    self.interactiveWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runningContainerView addSubview:self.interactiveWebView];

    [NSLayoutConstraint activateConstraints:@[
        [chromeBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [chromeBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [chromeBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [chromeBar.heightAnchor constraintEqualToConstant:32],
        [dotsContainer.trailingAnchor constraintEqualToAnchor:chromeBar.trailingAnchor constant:-6],
        [dotsContainer.centerYAnchor constraintEqualToAnchor:chromeBar.centerYAnchor],
        [self.activeTabButton.leadingAnchor constraintEqualToAnchor:chromeBar.leadingAnchor constant:5],
        [self.activeTabButton.bottomAnchor constraintEqualToAnchor:chromeBar.bottomAnchor],
        [self.activeTabButton.heightAnchor constraintEqualToConstant:26],
        [self.activeTabButton.trailingAnchor constraintLessThanOrEqualToAnchor:dotsContainer.leadingAnchor constant:-4],

        [self.tabStripContainer.topAnchor constraintEqualToAnchor:chromeBar.bottomAnchor],
        [self.tabStripContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.tabStripContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.tabStripContainer.heightAnchor constraintEqualToConstant:26],
        [tabScroll.topAnchor constraintEqualToAnchor:self.tabStripContainer.topAnchor],
        [tabScroll.bottomAnchor constraintEqualToAnchor:self.tabStripContainer.bottomAnchor],
        [tabScroll.leadingAnchor constraintEqualToAnchor:self.tabStripContainer.leadingAnchor constant:4],
        [tabScroll.trailingAnchor constraintEqualToAnchor:self.tabStripContainer.trailingAnchor constant:-4],
        [self.tabStripStack.leadingAnchor constraintEqualToAnchor:tabScroll.leadingAnchor],
        [self.tabStripStack.trailingAnchor constraintEqualToAnchor:tabScroll.trailingAnchor],
        [self.tabStripStack.centerYAnchor constraintEqualToAnchor:tabScroll.centerYAnchor],

        [self.emptyStateView.topAnchor constraintEqualToAnchor:chromeBar.bottomAnchor],
        [self.emptyStateView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.emptyStateView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.emptyStateView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [recentHdr.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:12],
        [recentHdr.centerYAnchor constraintEqualToAnchor:self.emptyStateView.centerYAnchor constant:-44],
        [self.recentEmptyBtn.topAnchor constraintEqualToAnchor:recentHdr.bottomAnchor constant:8],
        [self.recentEmptyBtn.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:12],
        [self.recentEmptyBtn.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor constant:-12],
        [self.recentEmptyBtn.heightAnchor constraintEqualToConstant:36],
        [allAppsBtn.topAnchor constraintEqualToAnchor:self.recentEmptyBtn.bottomAnchor constant:14],
        [allAppsBtn.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],

        [self.runningContainerView.topAnchor constraintEqualToAnchor:self.tabStripContainer.bottomAnchor],
        [self.runningContainerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.runningContainerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.runningContainerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.interactiveWebView.topAnchor constraintEqualToAnchor:self.runningContainerView.topAnchor],
        [self.interactiveWebView.leadingAnchor constraintEqualToAnchor:self.runningContainerView.leadingAnchor],
        [self.interactiveWebView.trailingAnchor constraintEqualToAnchor:self.runningContainerView.trailingAnchor],
        [self.interactiveWebView.bottomAnchor constraintEqualToAnchor:self.runningContainerView.bottomAnchor]
    ]];
}

- (UIButton *)makeWindowCircle:(UIColor *)bg symbol:(NSString *)sym action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = bg;
    b.tintColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    b.layer.cornerRadius = 6.5;
    [b setImage:[UIImage systemImageNamed:sym withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:6.5 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)openAppInPane:(InstalledAppItem *)app {
    if (!app) return;
    if (app.mirrorURL.length == 0) {
        [self.interactiveWebView loadHTMLString:@"<meta name='viewport' content='width=device-width'><p>VIETMAP LIVE chưa được nhúng trong bản build này. Cần bộ nhúng ứng dụng gốc; trang web không thay thế được ứng dụng.</p>" baseURL:nil];
    }
    self.currentApp = app;
    self.emptyStateView.hidden = YES;
    self.tabStripContainer.hidden = NO;
    self.runningContainerView.hidden = NO;

    NSString *shortName = app.name.length > 8 ? [[app.name substringToIndex:7] stringByAppendingString:@"..."] : app.name;
    [self.activeTabButton setTitle:[NSString stringWithFormat:@" %@ ⌄", shortName] forState:UIControlStateNormal];
    [self.activeTabButton setImage:[self scaledIcon:app.icon size:CGSizeMake(13, 13)] forState:UIControlStateNormal];

    NSPredicate *p = [NSPredicate predicateWithFormat:@"bundleID != %@", app.bundleID];
    [self.openedTabs filterUsingPredicate:p];
    [self.openedTabs insertObject:app atIndex:0];
    if (self.openedTabs.count > 5) [self.openedTabs removeLastObject];
    [self refreshTabStrip];

    NSURL *url = app.mirrorURL.length ? [NSURL URLWithString:app.mirrorURL] : nil;
    if (url) {
        [self.interactiveWebView loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (void)closeCurrentTab {
    [self.interactiveWebView stopLoading];
    [self.interactiveWebView loadHTMLString:@"" baseURL:nil];
    self.currentApp = nil;
    self.runningContainerView.hidden = YES;
    self.tabStripContainer.hidden = YES;
    self.emptyStateView.hidden = NO;
    [self.activeTabButton setImage:nil forState:UIControlStateNormal];
    [self.activeTabButton setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
    if (self.openedTabs.count > 0) {
        InstalledAppItem *last = self.openedTabs.firstObject;
        [self.recentEmptyBtn setTitle:[NSString stringWithFormat:@"Mở lại: %@", last.name] forState:UIControlStateNormal];
    }
}

- (void)onTapRecentButton {
    if (self.openedTabs.count > 0) [self openAppInPane:self.openedTabs.firstObject];
    else [self onTapSelectApp];
}

- (void)refreshTabStrip {
    for (UIView *v in self.tabStripStack.arrangedSubviews) {
        [self.tabStripStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSInteger i = 0; i < self.openedTabs.count; i++) {
        InstalledAppItem *item = self.openedTabs[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i;
        NSString *shortTitle = item.name.length > 7 ? [[item.name substringToIndex:6] stringByAppendingString:@"..."] : item.name;
        [b setTitle:[NSString stringWithFormat:@" %@", shortTitle] forState:UIControlStateNormal];
        [b setImage:[self scaledIcon:item.icon size:CGSizeMake(12, 12)] forState:UIControlStateNormal];
        b.tintColor = [UIColor labelColor];
        b.titleLabel.font = [UIFont systemFontOfSize:10 weight:(i == 0 ? UIFontWeightSemibold : UIFontWeightRegular)];
        b.backgroundColor = (i == 0) ? [UIColor secondarySystemBackgroundColor] : [UIColor clearColor];
        b.layer.cornerRadius = 5;
        b.contentEdgeInsets = UIEdgeInsetsMake(2, 5, 2, 5);
        [b addTarget:self action:@selector(onTapRecentStrip:) forControlEvents:UIControlEventTouchUpInside];
        [self.tabStripStack addArrangedSubview:b];
    }
}

- (UIImage *)scaledIcon:(UIImage *)img size:(CGSize)sz {
    if (!img) return nil;
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0.0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, sz.width, sz.height) cornerRadius:3] addClip];
    [img drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
    UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [res imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)onTapRecentStrip:(UIButton *)sender {
    if (sender.tag >= 0 && sender.tag < self.openedTabs.count) [self openAppInPane:self.openedTabs[sender.tag]];
}

- (void)onTapSelectApp { [self.delegate paneDidRequestAppPicker:self]; }
- (void)onTapYellow { [self.delegate paneDidRequestLayoutSheet:self]; }
- (void)onTapGreen { [self.delegate paneDidRequestLayoutSheet:self]; }
- (void)onTapRed { [self closeCurrentTab]; }

@end

#pragma mark - Hop Thoai Chia Man Hinh & Luoi App

typedef NS_ENUM(NSInteger, SidePlaySplitMode) {
    SidePlaySplitSingle = 0,
    SidePlaySplitDual = 1,
    SidePlaySplitTriple = 2,
    SidePlaySplitQuad = 3,
    SidePlaySplitGrid3 = 4,
    SidePlaySplitPiP = 5
};

@interface SidePlayLayoutModal : UIView
@property (nonatomic, assign) SidePlaySplitMode activeMode;
@property (nonatomic, copy) void (^onPickMode)(SidePlaySplitMode mode);
@property (nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithMode:(SidePlaySplitMode)mode;
@end

@implementation SidePlayLayoutModal
- (instancetype)initWithMode:(SidePlaySplitMode)mode {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.activeMode = mode;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.layer.cornerRadius = 22;
        [self setupUI];
    }
    return self;
}
- (void)setupUI {
    UILabel *hdr = [[UILabel alloc] init];
    hdr.text = @"Chia màn hình";
    hdr.font = [UIFont boldSystemFontOfSize:16];
    hdr.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [xBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    xBtn.tintColor = [UIColor systemGray3Color];
    xBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [xBtn addTarget:self action:@selector(closeModal) forControlEvents:UIControlEventTouchUpInside];

    NSArray *icons1 = @[@"rectangle.fill", @"rectangle.split.2x1.fill", @"rectangle.split.3x1.fill", @"rectangle.grid.2x2.fill"];
    UIStackView *row1 = [[UIStackView alloc] init];
    row1.spacing = 10; row1.distribution = UIStackViewDistributionFillEqually; row1.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger i = 0; i < 4; i++) [row1 addArrangedSubview:[self modeButton:(SidePlaySplitMode)i icon:icons1[i]]];

    UIStackView *row2 = [[UIStackView alloc] init];
    row2.spacing = 10; row2.distribution = UIStackViewDistributionFillEqually; row2.translatesAutoresizingMaskIntoConstraints = NO;
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitGrid3 icon:@"rectangle.leftthird.inset.filled"]];
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitPiP icon:@"pip.fill"]];
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitDual icon:@"plus"]];

    UIButton *exitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [exitBtn setTitle:@"Thoát SidePlay" forState:UIControlStateNormal];
    [exitBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    exitBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    exitBtn.backgroundColor = [UIColor systemGray6Color];
    exitBtn.layer.cornerRadius = 12;
    exitBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [exitBtn addTarget:self action:@selector(exitTap) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:hdr]; [self addSubview:xBtn]; [self addSubview:row1]; [self addSubview:row2]; [self addSubview:exitBtn];
    [NSLayoutConstraint activateConstraints:@[
        [hdr.topAnchor constraintEqualToAnchor:self.topAnchor constant:16], [hdr.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [xBtn.centerYAnchor constraintEqualToAnchor:hdr.centerYAnchor], [xBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [row1.topAnchor constraintEqualToAnchor:hdr.bottomAnchor constant:16], [row1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16], [row1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16], [row1.heightAnchor constraintEqualToConstant:46],
        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:10], [row2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:44], [row2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-44], [row2.heightAnchor constraintEqualToConstant:46],
        [exitBtn.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:24], [exitBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [exitBtn.widthAnchor constraintEqualToConstant:150], [exitBtn.heightAnchor constraintEqualToConstant:36]
    ]];
}
- (UIButton *)modeButton:(SidePlaySplitMode)m icon:(NSString *)ic {
    BOOL sel = (self.activeMode == m);
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tag = m;
    [b setImage:[UIImage systemImageNamed:ic] forState:UIControlStateNormal];
    b.tintColor = sel ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    b.backgroundColor = sel ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.15] : [UIColor systemGray6Color];
    b.layer.cornerRadius = 12;
    [b addTarget:self action:@selector(modeTap:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)modeTap:(UIButton * )sender { if (self.onPickMode) self.onPickMode((SidePlaySplitMode)sender.tag); }
- (void)closeModal { if (self.onClose) self.onClose(); }
- (void)exitTap { exit(0); }
@end

@interface AppGridPickerView : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *headerTitle;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@property (nonatomic, copy) void (^onSelect)(InstalledAppItem *app);
@property (nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<InstalledAppItem *> *)apps;
@end

@implementation AppGridPickerView
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<InstalledAppItem *> *)apps {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.headerTitle = title; self.apps = apps; self.backgroundColor = [UIColor systemBackgroundColor]; self.layer.cornerRadius = 18; self.clipsToBounds = YES;
        [self setupGrid];
    }
    return self;
}
- (void)setupGrid {
    UILabel *lbl = [[UILabel alloc] init]; lbl.text = self.headerTitle; lbl.font = [UIFont boldSystemFontOfSize:15]; lbl.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem]; [xBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal]; xBtn.tintColor = [UIColor labelColor]; xBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [xBtn addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];

    UICollectionViewFlowLayout *fl = [[UICollectionViewFlowLayout alloc] init]; fl.minimumLineSpacing = 12; fl.minimumInteritemSpacing = 4; fl.sectionInset = UIEdgeInsetsMake(6, 10, 14, 10);
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:fl]; cv.backgroundColor = [UIColor clearColor]; cv.dataSource = self; cv.delegate = self;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"AppCell"]; cv.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:lbl]; [self addSubview:xBtn]; [self addSubview:cv];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.topAnchor constant:14], [lbl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [xBtn.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor], [xBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [cv.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:8], [cv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [cv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [cv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}
- (void)closeTap { if (self.onClose) self.onClose(); }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.apps.count; }
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"AppCell" forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    InstalledAppItem *app = self.apps[ip.item];
    UIImageView *iv = [[UIImageView alloc] initWithImage:app.icon]; iv.layer.cornerRadius = 11; iv.clipsToBounds = YES; iv.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *name = [[UILabel alloc] init]; name.text = app.name; name.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium]; name.textAlignment = NSTextAlignmentCenter; name.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:iv]; [cell.contentView addSubview:name];
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:2], [iv.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor], [iv.widthAnchor constraintEqualToConstant:44], [iv.heightAnchor constraintEqualToConstant:44],
        [name.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4], [name.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:1], [name.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-1]
    ]];
    return cell;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat w = floor((cv.bounds.size.width - 38) / 5.0);
    return CGSizeMake(MAX(w, 48), 66);
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.onSelect) self.onSelect(self.apps[ip.item]);
}
@end

#pragma mark - SimulationViewController

@interface SimulationViewController : UIViewController <MultiTaskPaneDelegate, CLLocationManagerDelegate>
@property (nonatomic, assign) BOOL isCarPlayWindow;
@property (nonatomic, assign) SidePlaySplitMode splitMode;
@property (nonatomic, strong) UIView *outerFrame;
@property (nonatomic, strong) NSMutableArray<MultiTaskPaneView *> *panes;
@property (nonatomic, strong) UIView *centerDivider;
@property (nonatomic, strong) NSLayoutConstraint *pane1WidthConstraint;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) UIView *overlayModal;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *deviceApps;
@property (nonatomic, strong) UIView *speedCard;
@property (nonatomic, strong) UILabel *clockLbl;
@property (nonatomic, strong) UILabel *speedValueLbl;
@property (nonatomic, strong) CLLocationManager *locMgr;
@end

@implementation SimulationViewController
- (void)startNativeTest {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Thử nhúng ứng dụng gốc" message:@"Mở không gian thử hai ô trong SpringBoard. Chưa xác nhận tương thích trên thiết bị. Nút Đóng sẽ kết thúc phiên thử. Nếu không xuất hiện, bộ tweak chưa được nạp; hãy gửi lại kết quả." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Bắt đầu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        notify_post("com.xemyoutube.native-test.open");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSInteger mode = [AppSettings shared].defaultSplitMode;
    [self rebuildWorkspaceLayout:mode == 0 ? SidePlaySplitSingle : SidePlaySplitDual];
    self.speedCard.hidden = ![AppSettings shared].showSpeedBubble;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0];
    self.deviceApps = ScanDeviceApps();
    self.splitMode = SidePlaySplitDual;
    self.splitRatio = 0.5;
    self.panes = [NSMutableArray array];

    UILabel *bigTitle = [[UILabel alloc] init]; bigTitle.text = @"Mô phỏng"; bigTitle.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold]; bigTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bigTitle];
    bigTitle.text = @"Mô phỏng · Web";
    bigTitle.font = [UIFont boldSystemFontOfSize:24];
    UIButton *native = [UIButton buttonWithType:UIButtonTypeSystem];
    [native setTitle:@"Thử app gốc" forState:UIControlStateNormal];
    native.translatesAutoresizingMaskIntoConstraints = NO;
    [native addTarget:self action:@selector(startNativeTest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:native];
    [NSLayoutConstraint activateConstraints:@[
        [native.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [native.centerYAnchor constraintEqualToAnchor:bigTitle.centerYAnchor],
        [bigTitle.trailingAnchor constraintLessThanOrEqualToAnchor:native.leadingAnchor constant:-8]
    ]];


    self.outerFrame = [[UIView alloc] init]; self.outerFrame.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0]; self.outerFrame.layer.cornerRadius = 18; self.outerFrame.layer.borderWidth = 2.0; self.outerFrame.layer.borderColor = [UIColor colorWithWhite:0.84 alpha:1.0].CGColor; self.outerFrame.clipsToBounds = YES; self.outerFrame.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.outerFrame];

    [NSLayoutConstraint activateConstraints:@[
        [bigTitle.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10], [bigTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.outerFrame.topAnchor constraintEqualToAnchor:bigTitle.bottomAnchor constant:12], [self.outerFrame.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14], [self.outerFrame.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14], [self.outerFrame.heightAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:0.94]
    ]];

    for (NSInteger i = 1; i <= 4; i++) {
        MultiTaskPaneView *p = [[MultiTaskPaneView alloc] initWithPaneNumber:i]; p.delegate = self; p.translatesAutoresizingMaskIntoConstraints = NO;
        [self.panes addObject:p];
    }

    self.centerDivider = [[UIView alloc] init]; self.centerDivider.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0]; self.centerDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.centerDivider addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDividerDrag:)]];

    [self rebuildWorkspaceLayout:SidePlaySplitDual];
    [self buildSpeedWidget];
}

- (void)rebuildWorkspaceLayout:(SidePlaySplitMode)mode {
    self.splitMode = mode;
    for (UIView *sub in self.outerFrame.subviews) { if (sub != self.speedCard) [sub removeFromSuperview]; }

    MultiTaskPaneView *p1 = self.panes[0];
    MultiTaskPaneView *p2 = self.panes[1];

    if (mode == SidePlaySplitSingle) {
        [self.outerFrame addSubview:p1];
        [NSLayoutConstraint activateConstraints:@[[p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor], [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor], [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor], [p1.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]]];
    } else {
        [self.outerFrame addSubview:p1]; [self.outerFrame addSubview:self.centerDivider]; [self.outerFrame addSubview:p2];
        self.pane1WidthConstraint = [p1.widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:self.splitRatio constant:-4];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor], [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor], [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor], self.pane1WidthConstraint,
            [self.centerDivider.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor], [self.centerDivider.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor], [self.centerDivider.leadingAnchor constraintEqualToAnchor:p1.trailingAnchor], [self.centerDivider.widthAnchor constraintEqualToConstant:8],
            [p2.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor], [p2.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor], [p2.leadingAnchor constraintEqualToAnchor:self.centerDivider.trailingAnchor], [p2.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
        ]];
    }
    if (self.speedCard) [self.outerFrame bringSubviewToFront:self.speedCard];
}

- (void)buildSpeedWidget {
    self.speedCard = [[UIView alloc] init]; self.speedCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.96]; self.speedCard.layer.cornerRadius = 16; self.speedCard.layer.shadowColor = [UIColor blackColor].CGColor; self.speedCard.layer.shadowOpacity = 0.16; self.speedCard.layer.shadowRadius = 8; self.speedCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.clockLbl = [[UILabel alloc] init]; self.clockLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]; self.clockLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedValueLbl = [[UILabel alloc] init]; self.speedValueLbl.text = @"0"; self.speedValueLbl.font = [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightBold]; self.speedValueLbl.textAlignment = NSTextAlignmentCenter; self.speedValueLbl.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *sign = [[UIView alloc] init]; sign.backgroundColor = [UIColor whiteColor]; sign.layer.cornerRadius = 20; sign.layer.borderWidth = 3.5; sign.layer.borderColor = [UIColor systemRedColor].CGColor; sign.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *sn = [[UILabel alloc] init]; sn.text = @"50"; sn.font = [UIFont boldSystemFontOfSize:14]; sn.translatesAutoresizingMaskIntoConstraints = NO; [sign addSubview:sn];

    [self.speedCard addSubview:self.clockLbl]; [self.speedCard addSubview:self.speedValueLbl]; [self.speedCard addSubview:sign];
    [self.outerFrame addSubview:self.speedCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.speedCard.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor constant:8], [self.speedCard.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor constant:-10], [self.speedCard.widthAnchor constraintEqualToConstant:114], [self.speedCard.heightAnchor constraintEqualToConstant:76],
        [self.clockLbl.topAnchor constraintEqualToAnchor:self.speedCard.topAnchor constant:6], [self.clockLbl.leadingAnchor constraintEqualToAnchor:self.speedCard.leadingAnchor constant:10],
        [self.speedValueLbl.topAnchor constraintEqualToAnchor:self.clockLbl.bottomAnchor constant:6], [self.speedValueLbl.leadingAnchor constraintEqualToAnchor:self.speedCard.leadingAnchor constant:8], [self.speedValueLbl.widthAnchor constraintEqualToConstant:44],
        [sign.trailingAnchor constraintEqualToAnchor:self.speedCard.trailingAnchor constant:-10], [sign.bottomAnchor constraintEqualToAnchor:self.speedCard.bottomAnchor constant:-10], [sign.widthAnchor constraintEqualToConstant:40], [sign.heightAnchor constraintEqualToConstant:40],
        [sn.centerXAnchor constraintEqualToAnchor:sign.centerXAnchor], [sn.centerYAnchor constraintEqualToAnchor:sign.centerYAnchor]
    ]];

    NSDateFormatter *df = [[NSDateFormatter alloc] init]; df.dateFormat = @"HH:mm"; self.clockLbl.text = [df stringFromDate:[NSDate date]];
}

- (void)handleDividerDrag:(UIPanGestureRecognizer *)pan {
    if (self.splitMode != SidePlaySplitDual) return;
    CGPoint pt = [pan locationInView:self.outerFrame];
    CGFloat r = MIN(MAX(pt.x / MAX(self.outerFrame.bounds.size.width, 1.0), 0.25), 0.75);
    self.splitRatio = r;
    self.pane1WidthConstraint.active = NO;
    self.pane1WidthConstraint = [self.panes[0].widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:r constant:-4];
    self.pane1WidthConstraint.active = YES;
}

- (void)showOverlay:(UIView *)modal {
    [self.overlayModal removeFromSuperview]; modal.translatesAutoresizingMaskIntoConstraints = NO; [self.outerFrame addSubview:modal];
    [NSLayoutConstraint activateConstraints:@[[modal.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor constant:6], [modal.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor constant:-6], [modal.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor constant:6], [modal.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor constant:-6]]];
    self.overlayModal = modal;
}

- (void)paneDidRequestAppPicker:(MultiTaskPaneView *)pane {
    self.deviceApps = ScanDeviceApps();
    AppGridPickerView *picker = [[AppGridPickerView alloc] initWithTitle:[NSString stringWithFormat:@"Chọn app ô %ld", (long)pane.paneNumber] apps:self.deviceApps];
    __weak typeof(self) ws = self;
    picker.onClose = ^{ [ws.overlayModal removeFromSuperview]; ws.overlayModal = nil; };
    picker.onSelect = ^(InstalledAppItem *app) { [pane openAppInPane:app]; [ws.overlayModal removeFromSuperview]; ws.overlayModal = nil; };
    [self showOverlay:picker];
}

- (void)paneDidRequestLayoutSheet:(MultiTaskPaneView *)pane {
    SidePlayLayoutModal *sheet = [[SidePlayLayoutModal alloc] initWithMode:self.splitMode];
    __weak typeof(self) ws = self;
    sheet.onClose = ^{ [ws.overlayModal removeFromSuperview]; ws.overlayModal = nil; };
    sheet.onPickMode = ^(SidePlaySplitMode m) { [ws rebuildWorkspaceLayout:m]; [ws.overlayModal removeFromSuperview]; ws.overlayModal = nil; };
    [self showOverlay:sheet];
}

- (void)paneDidRequestOpenNativeApp:(MultiTaskPaneView *)pane {
    if (pane.currentApp.bundleID.length > 0) {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) { [[wsClass defaultWorkspace] openApplicationWithBundleID:pane.currentApp.bundleID]; }
    }
}
@end

#pragma mark - Tab 1, 2, 4 & TabBar

@interface HomeLauncherViewController : UITableViewController
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@end
@implementation HomeLauncherViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"XemYouTube";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 350, 250)];
    UIView *card = [UIView new]; card.backgroundColor = [UIColor colorWithRed:0.10 green:0.21 blue:0.36 alpha:1]; card.layer.cornerRadius = 22; card.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:card];
    UILabel *name = [UILabel new]; name.text = @"XemYouTube\nCARPLAY WORKSPACE"; name.numberOfLines = 2; name.textColor = UIColor.whiteColor; name.font = [UIFont boldSystemFontOfSize:23]; name.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:name];
    UILabel *status = [UILabel new]; status.text = @"Bản phát triển\nChưa xác minh chạy app gốc"; status.numberOfLines = 2; status.textColor = [UIColor colorWithWhite:0.8 alpha:1]; status.font = [UIFont systemFontOfSize:15]; status.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:status];
    [NSLayoutConstraint activateConstraints:@[[card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16], [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16], [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:16], [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12], [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22], [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:24], [status.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22], [status.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24]]];
    self.tableView.tableHeaderView = header;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 1; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text = ip.section == 0 ? @"Không gian CarPlay" : @"Có gì mới";
    c.textLabel.font = [UIFont boldSystemFontOfSize:20];
    c.detailTextLabel.text = ip.section == 0 ? @"Mở tab Mô phỏng để chọn bố cục" : @"Giao diện đang được hoàn thiện theo ảnh mẫu";
    c.detailTextLabel.numberOfLines = 0;
    c.imageView.image = [UIImage systemImageNamed:ip.section == 0 ? @"rectangle.split.2x1" : @"sparkles"];
    c.imageView.tintColor = UIColor.systemBlueColor;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    self.tabBarController.selectedIndex = 2;
}
@end

@interface CarSettingsViewController : UITableViewController
@end
@implementation CarSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trên xe";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 3; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (ip.row == 0) {
        c.textLabel.text = @"Hiện bảng tốc độ trong mô phỏng";
        UISwitch *toggle = [UISwitch new];
        toggle.on = [AppSettings shared].showSpeedBubble;
        [toggle addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = toggle;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        c.textLabel.text = ip.row == 1 ? @"Bố cục mặc định" : @"Ứng dụng và mã định danh";
        c.detailTextLabel.text = ip.row == 1 ? ([AppSettings shared].defaultSplitMode == 0 ? @"Một ô" : @"Hai ô") : @"Kiểm tra";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}
- (void)speedChanged:(UISwitch *)sender { [AppSettings shared].showSpeedBubble = sender.on; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row == 0) return;
    if (ip.row == 2) {
        HomeLauncherViewController *apps = [HomeLauncherViewController new];
        [self.navigationController pushViewController:apps animated:YES];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Bố cục mặc định" message:@"Áp dụng khi quay lại tab Mô phỏng." preferredStyle:UIAlertControllerStyleAlert];
    for (NSInteger i = 0; i < 2; i++) {
        NSInteger mode = i;
        [a addAction:[UIAlertAction actionWithTitle:i == 0 ? @"Một ô" : @"Hai ô" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [AppSettings shared].defaultSplitMode = mode;
            [self.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

@interface AccountProViewController : UITableViewController
@end
@implementation AccountProViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tài khoản";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.textLabel.text = ip.row == 0 ? @"Chẩn đoán bản thử nghiệm" : @"Đặt lại cài đặt";
    c.textLabel.textColor = ip.row == 0 ? [UIColor systemBlueColor] : [UIColor systemRedColor];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row == 0) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
        NSString *message = [NSString stringWithFormat:@"XemYouTube %@\\niOS %@\\nQuét được %lu ứng dụng.\\n\\nBản build này chỉ chứa ứng dụng giao diện. Các ô đang dùng WebKit, chưa có bộ nhúng ứng dụng gốc. VIETMAP LIVE chưa chạy trong ô. Việc có Sileo không xác nhận khả năng nhúng ứng dụng.", version, [UIDevice currentDevice].systemVersion, (unsigned long)ScanDeviceApps().count];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Chẩn đoán" message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đặt lại cài đặt?" message:@"Khôi phục bảng tốc độ và bố cục mặc định của XemYouTube." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [[AppSettings shared] resetAll]; }]];
        [self presentViewController:a animated:YES completion:nil];
    }
}
@end

@interface FloatingPillTabBarController : UITabBarController
@property (nonatomic, strong) UIView *pillBar;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@end

@implementation FloatingPillTabBarController
- (void)viewDidLoad {
    [super viewDidLoad]; self.tabBar.hidden = YES;
    self.viewControllers = @[
        [[UINavigationController alloc] initWithRootViewController:[[HomeLauncherViewController alloc] init]],
        [[UINavigationController alloc] initWithRootViewController:[[CarSettingsViewController alloc] init]],
        [[SimulationViewController alloc] init],
        [[UINavigationController alloc] initWithRootViewController:[[AccountProViewController alloc] init]]
    ];
    [self buildBar]; [self switchToTab:0];
}
- (void)buildBar {
    self.pillBar = [[UIView alloc] init]; self.pillBar.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.96]; self.pillBar.layer.cornerRadius = 28; self.pillBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pillBar];
    UIStackView *st = [[UIStackView alloc] init]; st.distribution = UIStackViewDistributionFillEqually; st.spacing = 6; st.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pillBar addSubview:st];

    NSArray *titles = @[@"Trang chủ", @"Trên xe", @"Mô phỏng", @"Tài khoản"];
    NSArray *icons  = @[@"house.fill", @"car.fill", @"play.rectangle.fill", @"person.crop.circle.fill"];
    self.tabButtons = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.tag = i; b.layer.cornerRadius = 22;
        UIStackView *vs = [[UIStackView alloc] init]; vs.axis = UILayoutConstraintAxisVertical; vs.alignment = UIStackViewAlignmentCenter; vs.spacing = 3; vs.userInteractionEnabled = NO; vs.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icons[i]]]; iv.tag = 101; iv.contentMode = UIViewContentModeScaleAspectFit; [iv.widthAnchor constraintEqualToConstant:22].active = YES; [iv.heightAnchor constraintEqualToConstant:22].active = YES;
        UILabel *l = [[UILabel alloc] init]; l.tag = 102; l.text = titles[i]; l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        [vs addArrangedSubview:iv]; [vs addArrangedSubview:l]; [b addSubview:vs];
        [NSLayoutConstraint activateConstraints:@[[vs.centerXAnchor constraintEqualToAnchor:b.centerXAnchor], [vs.centerYAnchor constraintEqualToAnchor:b.centerYAnchor]]];
        [b addTarget:self action:@selector(tapTab:) forControlEvents:UIControlEventTouchUpInside];
        [st addArrangedSubview:b]; [self.tabButtons addObject:b];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.pillBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16], [self.pillBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16], [self.pillBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4], [self.pillBar.heightAnchor constraintEqualToConstant:62],
        [st.topAnchor constraintEqualToAnchor:self.pillBar.topAnchor constant:5], [st.bottomAnchor constraintEqualToAnchor:self.pillBar.bottomAnchor constant:-5], [st.leadingAnchor constraintEqualToAnchor:self.pillBar.leadingAnchor constant:6], [st.trailingAnchor constraintEqualToAnchor:self.pillBar.trailingAnchor constant:-6]
    ]];
}
- (void)tapTab:(UIButton *)s { [self switchToTab:s.tag]; }
- (void)switchToTab:(NSInteger)idx {
    self.selectedIndex = idx;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = self.tabButtons[i]; BOOL sel = (i == idx);
        b.backgroundColor = sel ? [UIColor colorWithRed:0.86 green:0.93 blue:1.0 alpha:1.0] : [UIColor clearColor];
        ((UIImageView *)[b viewWithTag:101]).tintColor = sel ? [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0] : [UIColor colorWithWhite:0.45 alpha:1.0];
        ((UILabel *)[b viewWithTag:102]).textColor = sel ? [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0] : [UIColor colorWithWhite:0.45 alpha:1.0];
    }
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication * )application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.window.rootViewController = [[FloatingPillTabBarController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}
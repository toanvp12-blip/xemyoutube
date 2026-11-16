#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <spawn.h>

extern char **environ;

static NSString * const kNotifSettingsChanged = @"XemYouTubeSettingsChangedNotification";

#pragma mark - Private APIs

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

#pragma mark - Cai Dat Luu Tru Chung (AppSettings)

@interface AppSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL autoOpenCarPlay;
@property (nonatomic, assign) BOOL restoreLastLayout;
@property (nonatomic, assign) BOOL autoDimScreen;
@property (nonatomic, assign) BOOL showSpeedBubble;
@property (nonatomic, assign) NSInteger speedLimitValue;
@property (nonatomic, assign) NSInteger tabAutoHideSeconds; // 0 = Luon hien, 5 = 5 giay, 10 = 10 giay
@property (nonatomic, assign) NSInteger defaultSplitMode;   // 0..5
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
            [ud setInteger:0  forKey:@"tabAutoHideSeconds"];
            [ud setInteger:1  forKey:@"defaultSplitMode"];
        }
    }
    return self;
}
- (BOOL)autoOpenCarPlay { return [[NSUserDefaults standardUserDefaults] boolForKey:@"autoOpenCarPlay"]; }
- (void)setAutoOpenCarPlay:(BOOL)v { [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"autoOpenCarPlay"]; }

- (BOOL)restoreLastLayout { return [[NSUserDefaults standardUserDefaults] boolForKey:@"restoreLastLayout"]; }
- (void)setRestoreLastLayout:(BOOL)v { [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"restoreLastLayout"]; }

- (BOOL)autoDimScreen { return [[NSUserDefaults standardUserDefaults] boolForKey:@"autoDimScreen"]; }
- (void)setAutoDimScreen:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"autoDimScreen"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
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

- (NSInteger)tabAutoHideSeconds { return [[NSUserDefaults standardUserDefaults] integerForKey:@"tabAutoHideSeconds"]; }
- (void)setTabAutoHideSeconds:(NSInteger)v {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"tabAutoHideSeconds"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}

- (NSInteger)defaultSplitMode { return [[NSUserDefaults standardUserDefaults] integerForKey:@"defaultSplitMode"]; }
- (void)setDefaultSplitMode:(NSInteger)v {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"defaultSplitMode"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}

- (void)resetAll {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = [ud dictionaryRepresentation];
    for (id key in dict) [ud removeObjectForKey:key];
    [ud synchronize];
    [self init];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSettingsChanged object:nil];
}
@end

#pragma mark - App Model & Quet Danh Sach App Tren May

@interface InstalledAppItem : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *interactiveURL;
@end

@implementation InstalledAppItem
@end

static NSString *InteractiveURLForApp(NSString *bundleID, NSString *name) {
    NSString *k = [NSString stringWithFormat:@"%@ %@", bundleID.lowercaseString, name.lowercaseString];
    if ([k containsString:@"youtube"]) return @"https://m.youtube.com";
    if ([k containsString:@"vietmap"]) return @"https://www.google.com/maps/@10.7769,106.7009,15z";
    if ([k containsString:@"maps"] || [k containsString:@"bản đồ"]) return @"https://www.google.com/maps";
    if ([k containsString:@"zing"]) return @"https://zingmp3.vn";
    if ([k containsString:@"nhạc"] || [k containsString:@"music"]) return @"https://m.youtube.com/music";
    if ([k containsString:@"podcast"]) return @"https://podcasts.apple.com";
    if ([k containsString:@"spotify"]) return @"https://open.spotify.com";
    if ([k containsString:@"tiktok"]) return @"https://www.tiktok.com";
    if ([k containsString:@"zalo"]) return @"https://chat.zalo.me";
    if ([k containsString:@"telegram"]) return @"https://web.telegram.org";
    if ([k containsString:@"dịch"] || [k containsString:@"translate"]) return @"https://translate.google.com";
    if ([k containsString:@"gmail"] || [k containsString:@"mail"]) return @"https://mail.google.com";
    if ([k containsString:@"thời tiết"] || [k containsString:@"weather"]) return @"https://embed.windy.com";
    if ([k containsString:@"shopee"] || [k containsString:@"蝦皮"]) return @"https://shopee.vn";
    if ([k containsString:@"safari"]) return @"https://www.google.com";
    return [NSString stringWithFormat:@"https://www.google.com/search?q=%@", [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
}

static NSArray<InstalledAppItem *> *ScanDeviceApps(void) {
    NSMutableArray<InstalledAppItem *> *list = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass) {
        id ws = [wsClass defaultWorkspace];
        NSArray *all = [ws allInstalledApplications];
        NSSet *sysAllow = [NSSet setWithArray:@[
            @"com.apple.Maps", @"com.apple.Music", @"com.apple.mobilesafari",
            @"com.apple.weather", @"com.apple.podcasts", @"com.apple.mobilemail"
        ]];
        for (id proxy in all) {
            NSString *bid = [proxy valueForKey:@"applicationIdentifier"];
            NSString *type = [proxy valueForKey:@"applicationType"];
            NSString *name = [proxy valueForKey:@"localizedName"];
            if (!bid || !name || name.length == 0) continue;
            if (![type isEqualToString:@"User"] && ![sysAllow containsObject:bid]) continue;

            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = bid;
            item.name = name;
            item.interactiveURL = InteractiveURLForApp(bid, name);
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

#pragma mark - 1 O Cua So Da Nhiem (MultiTaskPaneView)

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
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
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
    self.activeTabButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.activeTabButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.activeTabButton.contentEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 5);
    self.activeTabButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activeTabButton addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    // Cum 3 nut tron Vang / Xanh la / Do co khoang cach co dinh, khong bao gio de len nhau
    UIView *dotsContainer = [[UIView alloc] init];
    dotsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *btnYellow = [self makeWindowCircle:[UIColor colorWithRed:0.96 green:0.74 blue:0.25 alpha:1.0] symbol:@"arrow.left.and.right" action:@selector(onTapYellow)];
    UIButton *btnGreen  = [self makeWindowCircle:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0] symbol:@"arrow.up.left.and.arrow.down.right" action:@selector(onTapGreen)];
    UIButton *btnRed    = [self makeWindowCircle:[UIColor colorWithRed:0.95 green:0.35 blue:0.30 alpha:1.0] symbol:@"xmark" action:@selector(onTapRed)];

    [dotsContainer addSubview:btnYellow];
    [dotsContainer addSubview:btnGreen];
    [dotsContainer addSubview:btnRed];

    [NSLayoutConstraint activateConstraints:@[
        [dotsContainer.widthAnchor constraintEqualToConstant:48],
        [dotsContainer.heightAnchor constraintEqualToConstant:16],

        [btnYellow.leadingAnchor constraintEqualToAnchor:dotsContainer.leadingAnchor],
        [btnYellow.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor],
        [btnYellow.widthAnchor constraintEqualToConstant:13],
        [btnYellow.heightAnchor constraintEqualToConstant:13],

        [btnGreen.centerXAnchor constraintEqualToAnchor:dotsContainer.centerXAnchor],
        [btnGreen.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor],
        [btnGreen.widthAnchor constraintEqualToConstant:13],
        [btnGreen.heightAnchor constraintEqualToConstant:13],

        [btnRed.trailingAnchor constraintEqualToAnchor:dotsContainer.trailingAnchor],
        [btnRed.centerYAnchor constraintEqualToAnchor:dotsContainer.centerYAnchor],
        [btnRed.widthAnchor constraintEqualToConstant:13],
        [btnRed.heightAnchor constraintEqualToConstant:13]
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
    recentHdr.textColor = [UIColor labelColor];
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
    [allAppsBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    allAppsBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    allAppsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [allAppsBtn addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    [self.emptyStateView addSubview:recentHdr];
    [self.emptyStateView addSubview:self.recentEmptyBtn];
    [self.emptyStateView addSubview:allAppsBtn];

    self.runningContainerView = [[UIView alloc] init];
    self.runningContainerView.backgroundColor = [UIColor systemBackgroundColor];
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
    self.interactiveWebView.backgroundColor = [UIColor systemBackgroundColor];
    self.interactiveWebView.opaque = YES;
    self.interactiveWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runningContainerView addSubview:self.interactiveWebView];

    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingSpinner.hidesWhenStopped = YES;
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runningContainerView addSubview:self.loadingSpinner];

    // Thanh nut mo nhanh App Goc ben duoi khung neu nguoi dung muon bung sang App Goc
    UIButton *nativeJumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [nativeJumpBtn setTitle:@" ↗ Mở App Gốc " forState:UIControlStateNormal];
    nativeJumpBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [nativeJumpBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    nativeJumpBtn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
    nativeJumpBtn.layer.cornerRadius = 10;
    nativeJumpBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [nativeJumpBtn addTarget:self action:@selector(onTapOpenNative) forControlEvents:UIControlEventTouchUpInside];
    [self.runningContainerView addSubview:nativeJumpBtn];

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
        [self.interactiveWebView.bottomAnchor constraintEqualToAnchor:self.runningContainerView.bottomAnchor],

        [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:self.runningContainerView.centerXAnchor],
        [self.loadingSpinner.centerYAnchor constraintEqualToAnchor:self.runningContainerView.centerYAnchor],

        [nativeJumpBtn.trailingAnchor constraintEqualToAnchor:self.runningContainerView.trailingAnchor constant:-6],
        [nativeJumpBtn.topAnchor constraintEqualToAnchor:self.runningContainerView.topAnchor constant:6],
        [nativeJumpBtn.heightAnchor constraintEqualToConstant:22]
    ]];
}

- (UIButton *)makeWindowCircle:(UIColor *)bg symbol:(NSString *)sym action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = bg;
    b.tintColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    b.layer.cornerRadius = 6.5;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:6.5 weight:UIImageSymbolWeightBold];
    [b setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)openAppInPane:(InstalledAppItem *)app {
    if (!app) return;
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

    [self.loadingSpinner startAnimating];
    NSURL *url = [NSURL URLWithString:app.interactiveURL];
    if (url) {
        [self.interactiveWebView loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.loadingSpinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.loadingSpinner stopAnimating];
}

- (void)closeCurrentTab {
    self.currentApp = nil;
    [self.interactiveWebView loadHTMLString:@"" baseURL:nil];
    self.runningContainerView.hidden = YES;
    self.tabStripContainer.hidden = YES;
    self.emptyStateView.hidden = NO;
    [self.activeTabButton setImage:nil forState:UIControlStateNormal];
    [self.activeTabButton setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
    if (self.openedTabs.count > 0) {
        InstalledAppItem *last = self.openedTabs.firstObject;
        [self.recentEmptyBtn setTitle:[NSString stringWithFormat:@"%@ (Chạm để mở lại)", last.name] forState:UIControlStateNormal];
        [self.recentEmptyBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    }
}

- (void)onTapRecentButton {
    if (self.openedTabs.count > 0) {
        [self openAppInPane:self.openedTabs.firstObject];
    } else {
        [self onTapSelectApp];
    }
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
    if (sender.tag >= 0 && sender.tag < self.openedTabs.count) {
        [self openAppInPane:self.openedTabs[sender.tag]];
    }
}

- (void)onTapSelectApp { [self.delegate paneDidRequestAppPicker:self]; }
- (void)onTapYellow { [self.delegate paneDidRequestLayoutSheet:self]; }
- (void)onTapGreen { [self.delegate paneDidRequestLayoutSheet:self]; }
- (void)onTapRed { [self closeCurrentTab]; }
- (void)onTapOpenNative { [self.delegate paneDidRequestOpenNativeApp:self]; }

@end

#pragma mark - Hop Thoai "Chia man hinh"

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
@property (nonatomic, copy) void (^onQuickPreset)(void);
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
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 14;
        [self buildModal];
    }
    return self;
}

- (void)buildModal {
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
    row1.spacing = 10;
    row1.distribution = UIStackViewDistributionFillEqually;
    row1.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger i = 0; i < 4; i++) {
        [row1 addArrangedSubview:[self modeButton:(SidePlaySplitMode)i icon:icons1[i]]];
    }

    UIStackView *row2 = [[UIStackView alloc] init];
    row2.spacing = 10;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.translatesAutoresizingMaskIntoConstraints = NO;
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitGrid3 icon:@"rectangle.leftthird.inset.filled"]];
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitPiP icon:@"pip.fill"]];
    [row2 addArrangedSubview:[self modeButton:SidePlaySplitDual icon:@"plus"]];

    UILabel *qTitle = [[UILabel alloc] init];
    qTitle.text = @"MỞ NHANH (YOUTUBE + BẢN ĐỒ)";
    qTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    qTitle.textColor = [UIColor secondaryLabelColor];
    qTitle.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *quickPill = [UIButton buttonWithType:UIButtonTypeSystem];
    quickPill.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.10];
    quickPill.layer.cornerRadius = 18;
    quickPill.layer.borderWidth = 1.2;
    quickPill.layer.borderColor = [UIColor systemBlueColor].CGColor;
    [quickPill setTitle:@"  +   ⊞   ▶ YouTube + 🗺️ Maps  " forState:UIControlStateNormal];
    quickPill.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    quickPill.translatesAutoresizingMaskIntoConstraints = NO;
    [quickPill addTarget:self action:@selector(quickTap) forControlEvents:UIControlEventTouchUpInside];

    UIButton *exitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [exitBtn setTitle:@"Thoát SidePlay" forState:UIControlStateNormal];
    [exitBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    exitBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    exitBtn.backgroundColor = [UIColor systemGray6Color];
    exitBtn.layer.cornerRadius = 12;
    exitBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [exitBtn addTarget:self action:@selector(exitTap) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:hdr];
    [self addSubview:xBtn];
    [self addSubview:row1];
    [self addSubview:row2];
    [self addSubview:qTitle];
    [self addSubview:quickPill];
    [self addSubview:exitBtn];

    [NSLayoutConstraint activateConstraints:@[
        [hdr.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [hdr.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [xBtn.centerYAnchor constraintEqualToAnchor:hdr.centerYAnchor],
        [xBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],

        [row1.topAnchor constraintEqualToAnchor:hdr.bottomAnchor constant:16],
        [row1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row1.heightAnchor constraintEqualToConstant:46],

        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:10],
        [row2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:44],
        [row2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-44],
        [row2.heightAnchor constraintEqualToConstant:46],

        [qTitle.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:16],
        [qTitle.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

        [quickPill.topAnchor constraintEqualToAnchor:qTitle.bottomAnchor constant:8],
        [quickPill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [quickPill.heightAnchor constraintEqualToConstant:40],
        [quickPill.widthAnchor constraintEqualToConstant:230],

        [exitBtn.topAnchor constraintEqualToAnchor:quickPill.bottomAnchor constant:16],
        [exitBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [exitBtn.widthAnchor constraintEqualToConstant:150],
        [exitBtn.heightAnchor constraintEqualToConstant:34]
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
    if (sel) {
        b.layer.borderWidth = 1.8;
        b.layer.borderColor = [UIColor systemBlueColor].CGColor;
    }
    [b addTarget:self action:@selector(modeTap:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)modeTap:(UIButton *)sender { if (self.onPickMode) self.onPickMode((SidePlaySplitMode)sender.tag); }
- (void)quickTap { if (self.onQuickPreset) self.onQuickPreset(); }
- (void)closeModal { if (self.onClose) self.onClose(); }
- (void)exitTap { exit(0); }

@end

#pragma mark - Luoi "Chon app o 1 / 2 / 3 / 4"

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
        self.headerTitle = title;
        self.apps = apps;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.layer.cornerRadius = 18;
        self.clipsToBounds = YES;
        [self setupGrid];
    }
    return self;
}

- (void)setupGrid {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = self.headerTitle;
    lbl.font = [UIFont boldSystemFontOfSize:15];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [xBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    xBtn.tintColor = [UIColor labelColor];
    xBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [xBtn addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];

    UICollectionViewFlowLayout *fl = [[UICollectionViewFlowLayout alloc] init];
    fl.minimumLineSpacing = 12;
    fl.minimumInteritemSpacing = 4;
    fl.sectionInset = UIEdgeInsetsMake(6, 10, 14, 10);

    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:fl];
    cv.backgroundColor = [UIColor clearColor];
    cv.dataSource = self;
    cv.delegate = self;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"AppCell"];
    cv.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:lbl];
    [self addSubview:xBtn];
    [self addSubview:cv];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [lbl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [xBtn.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],
        [xBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [cv.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:8],
        [cv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [cv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [cv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)closeTap { if (self.onClose) self.onClose(); }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.apps.count; }

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"AppCell" forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    InstalledAppItem *app = self.apps[ip.item];

    UIImageView *iv = [[UIImageView alloc] initWithImage:app.icon];
    iv.layer.cornerRadius = 11;
    iv.clipsToBounds = YES;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *name = [[UILabel alloc] init];
    name.text = app.name;
    name.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    name.textAlignment = NSTextAlignmentCenter;
    name.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:iv];
    [cell.contentView addSubview:name];
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:2],
        [iv.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [iv.widthAnchor constraintEqualToConstant:44],
        [iv.heightAnchor constraintEqualToConstant:44],
        [name.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4],
        [name.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:1],
        [name.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-1]
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

#pragma mark - Tab 3: Man Hinh "Mo phong"

@interface SimulationViewController : UIViewController <MultiTaskPaneDelegate, CLLocationManagerDelegate>
@property (nonatomic, assign) BOOL isCarPlayWindow;
@property (nonatomic, assign) SidePlaySplitMode splitMode;
@property (nonatomic, strong) UIView *outerFrame;
@property (nonatomic, strong) UIView *dimOverlay;
@property (nonatomic, strong) NSMutableArray<MultiTaskPaneView *> *panes;
@property (nonatomic, strong) UIView *centerDivider;
@property (nonatomic, strong) UIView *centerPillThumb;
@property (nonatomic, strong) NSLayoutConstraint *pane1WidthConstraint;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) UIView *overlayModal;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *deviceApps;

@property (nonatomic, strong) UIView *speedCard;
@property (nonatomic, strong) UILabel *clockLbl;
@property (nonatomic, strong) UILabel *batLbl;
@property (nonatomic, strong) UILabel *speedValueLbl;
@property (nonatomic, strong) UIView *limitCircle;
@property (nonatomic, strong) UILabel *limitValueLbl;
@property (nonatomic, strong) CLLocationManager *locMgr;
- (void)openAppInFirstAvailablePane:(InstalledAppItem *)app;
@end

@implementation SimulationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0];
    self.deviceApps = ScanDeviceApps();
    self.splitMode = (SidePlaySplitMode)[AppSettings shared].defaultSplitMode;
    self.splitRatio = 0.5;
    self.panes = [NSMutableArray array];

    UILabel *bigTitle = [[UILabel alloc] init];
    bigTitle.text = @"Mô phỏng";
    bigTitle.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    bigTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bigTitle];

    UIButton *quickSplitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [quickSplitBtn setImage:[UIImage systemImageNamed:@"rectangle.split.2x1.fill"] forState:UIControlStateNormal];
    [quickSplitBtn setTitle:@" Chia màn hình" forState:UIControlStateNormal];
    quickSplitBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    quickSplitBtn.backgroundColor = [UIColor whiteColor];
    quickSplitBtn.layer.cornerRadius = 12;
    quickSplitBtn.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    quickSplitBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [quickSplitBtn addTarget:self action:@selector(openLayoutSheetFromHeader) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:quickSplitBtn];

    self.outerFrame = [[UIView alloc] init];
    self.outerFrame.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    self.outerFrame.layer.cornerRadius = 18;
    self.outerFrame.layer.borderWidth = 2.0;
    self.outerFrame.layer.borderColor = [UIColor colorWithWhite:0.84 alpha:1.0].CGColor;
    self.outerFrame.clipsToBounds = YES;
    self.outerFrame.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.outerFrame];

    if (self.isCarPlayWindow) {
        bigTitle.hidden = YES;
        quickSplitBtn.hidden = YES;
        [NSLayoutConstraint activateConstraints:@[
            [self.outerFrame.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
            [self.outerFrame.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
            [self.outerFrame.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:4],
            [self.outerFrame.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-4]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [bigTitle.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
            [bigTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],

            [quickSplitBtn.centerYAnchor constraintEqualToAnchor:bigTitle.centerYAnchor],
            [quickSplitBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

            [self.outerFrame.topAnchor constraintEqualToAnchor:bigTitle.bottomAnchor constant:12],
            [self.outerFrame.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
            [self.outerFrame.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
            [self.outerFrame.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-76]
        ]];
    }

    for (NSInteger i = 1; i <= 4; i++) {
        MultiTaskPaneView *p = [[MultiTaskPaneView alloc] initWithPaneNumber:i];
        p.delegate = self;
        p.translatesAutoresizingMaskIntoConstraints = NO;
        [self.panes addObject:p];
    }

    self.centerDivider = [[UIView alloc] init];
    self.centerDivider.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    self.centerDivider.translatesAutoresizingMaskIntoConstraints = NO;

    self.centerPillThumb = [[UIView alloc] init];
    self.centerPillThumb.backgroundColor = [UIColor whiteColor];
    self.centerPillThumb.layer.cornerRadius = 6;
    self.centerPillThumb.layer.shadowColor = [UIColor blackColor].CGColor;
    self.centerPillThumb.layer.shadowOpacity = 0.18;
    self.centerPillThumb.layer.shadowRadius = 3;
    self.centerPillThumb.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *gripDots = [[UILabel alloc] init];
    gripDots.text = @"☰";
    gripDots.font = [UIFont systemFontOfSize:8];
    gripDots.textColor = [UIColor grayColor];
    gripDots.translatesAutoresizingMaskIntoConstraints = NO;
    [self.centerPillThumb addSubview:gripDots];
    [self.centerDivider addSubview:self.centerPillThumb];

    [NSLayoutConstraint activateConstraints:@[
        [self.centerPillThumb.centerXAnchor constraintEqualToAnchor:self.centerDivider.centerXAnchor],
        [self.centerPillThumb.centerYAnchor constraintEqualToAnchor:self.centerDivider.centerYAnchor],
        [self.centerPillThumb.widthAnchor constraintEqualToConstant:14],
        [self.centerPillThumb.heightAnchor constraintEqualToConstant:36],
        [gripDots.centerXAnchor constraintEqualToAnchor:self.centerPillThumb.centerXAnchor],
        [gripDots.centerYAnchor constraintEqualToAnchor:self.centerPillThumb.centerYAnchor]
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDividerDrag:)];
    [self.centerDivider addGestureRecognizer:pan];

    [self rebuildWorkspaceLayout:self.splitMode];
    [self buildSpeedWidget];

    self.dimOverlay = [[UIView alloc] init];
    self.dimOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.dimOverlay.userInteractionEnabled = NO;
    self.dimOverlay.hidden = ![AppSettings shared].autoDimScreen;
    self.dimOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.outerFrame addSubview:self.dimOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [self.dimOverlay.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
        [self.dimOverlay.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
        [self.dimOverlay.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
        [self.dimOverlay.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyLiveSettings) name:kNotifSettingsChanged object:nil];
}

- (void)applyLiveSettings {
    self.speedCard.hidden = ![AppSettings shared].showSpeedBubble;
    self.limitValueLbl.text = [NSString stringWithFormat:@"%ld", (long)[AppSettings shared].speedLimitValue];
    self.dimOverlay.hidden = ![AppSettings shared].autoDimScreen;
}

- (void)openAppInFirstAvailablePane:(InstalledAppItem *)app {
    if (!self.panes[0].currentApp) {
        [self.panes[0] openAppInPane:app];
    } else {
        [self.panes[1] openAppInPane:app];
    }
}

- (void)openLayoutSheetFromHeader {
    [self paneDidRequestLayoutSheet:self.panes[0]];
}

- (void)rebuildWorkspaceLayout:(SidePlaySplitMode)mode {
    self.splitMode = mode;
    [AppSettings shared].defaultSplitMode = mode;

    for (UIView *sub in self.outerFrame.subviews) {
        if (sub != self.speedCard && sub != self.dimOverlay) [sub removeFromSuperview];
    }

    MultiTaskPaneView *p1 = self.panes[0];
    MultiTaskPaneView *p2 = self.panes[1];
    MultiTaskPaneView *p3 = self.panes[2];

    if (mode == SidePlaySplitSingle) {
        [self.outerFrame addSubview:p1];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            [p1.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
        ]];
    } else if (mode == SidePlaySplitDual) {
        [self.outerFrame addSubview:p1];
        [self.outerFrame addSubview:p2];
        [self.outerFrame addSubview:self.centerDivider];

        self.pane1WidthConstraint = [p1.widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:self.splitRatio constant:-4];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            self.pane1WidthConstraint,

            [self.centerDivider.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [self.centerDivider.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [self.centerDivider.leadingAnchor constraintEqualToAnchor:p1.trailingAnchor],
            [self.centerDivider.widthAnchor constraintEqualToConstant:8],

            [p2.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p2.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p2.leadingAnchor constraintEqualToAnchor:self.centerDivider.trailingAnchor],
            [p2.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
        ]];
    } else if (mode == SidePlaySplitGrid3) {
        [self.outerFrame addSubview:p1];
        [self.outerFrame addSubview:p2];
        [self.outerFrame addSubview:p3];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            [p1.widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:0.5],

            [p2.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p2.leadingAnchor constraintEqualToAnchor:p1.trailingAnchor constant:2],
            [p2.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor],
            [p2.heightAnchor constraintEqualToAnchor:self.outerFrame.heightAnchor multiplier:0.5],

            [p3.topAnchor constraintEqualToAnchor:p2.bottomAnchor constant:2],
            [p3.leadingAnchor constraintEqualToAnchor:p1.trailingAnchor constant:2],
            [p3.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor],
            [p3.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor]
        ]];
    } else if (mode == SidePlaySplitPiP) {
        [self.outerFrame addSubview:p1];
        p2.layer.cornerRadius = 14;
        p2.layer.borderWidth = 1.5;
        p2.layer.borderColor = [UIColor systemGray3Color].CGColor;
        [self.outerFrame addSubview:p2];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            [p1.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor],

            [p2.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor constant:-10],
            [p2.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor constant:-12],
            [p2.widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:0.46],
            [p2.heightAnchor constraintEqualToAnchor:self.outerFrame.heightAnchor multiplier:0.45]
        ]];
    } else {
        NSInteger cnt = (mode == SidePlaySplitTriple) ? 3 : 4;
        UIStackView *st = [[UIStackView alloc] init];
        st.distribution = UIStackViewDistributionFillEqually;
        st.spacing = 2;
        st.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSInteger i = 0; i < cnt; i++) [st addArrangedSubview:self.panes[i]];
        [self.outerFrame addSubview:st];
        [NSLayoutConstraint activateConstraints:@[
            [st.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [st.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [st.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            [st.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
        ]];
    }

    if (self.speedCard) [self.outerFrame bringSubviewToFront:self.speedCard];
    if (self.dimOverlay) [self.outerFrame bringSubviewToFront:self.dimOverlay];
}

- (void)buildSpeedWidget {
    self.speedCard = [[UIView alloc] init];
    self.speedCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.96];
    self.speedCard.layer.cornerRadius = 16;
    self.speedCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.speedCard.layer.shadowOpacity = 0.16;
    self.speedCard.layer.shadowRadius = 8;
    self.speedCard.layer.shadowOffset = CGSizeMake(0, 3);
    self.speedCard.hidden = ![AppSettings shared].showSpeedBubble;
    self.speedCard.translatesAutoresizingMaskIntoConstraints = NO;

    // Cho phep keo di chuyen bong bong toc do quanh man hinh
    UIPanGestureRecognizer *dragHud = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSpeedCardDrag:)];
    [self.speedCard addGestureRecognizer:dragHud];

    self.clockLbl = [[UILabel alloc] init];
    self.clockLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    self.clockLbl.textColor = [UIColor blackColor];
    self.clockLbl.translatesAutoresizingMaskIntoConstraints = NO;

    self.batLbl = [[UILabel alloc] init];
    self.batLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    self.batLbl.textColor = [UIColor blackColor];
    self.batLbl.translatesAutoresizingMaskIntoConstraints = NO;

    self.speedValueLbl = [[UILabel alloc] init];
    self.speedValueLbl.text = @"0";
    self.speedValueLbl.font = [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightBold];
    self.speedValueLbl.textColor = [UIColor blackColor];
    self.speedValueLbl.textAlignment = NSTextAlignmentCenter;
    self.speedValueLbl.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *kmh = [[UILabel alloc] init];
    kmh.text = @"km/h";
    kmh.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    kmh.textColor = [UIColor grayColor];
    kmh.translatesAutoresizingMaskIntoConstraints = NO;

    self.limitCircle = [[UIView alloc] init];
    self.limitCircle.backgroundColor = [UIColor whiteColor];
    self.limitCircle.layer.cornerRadius = 20;
    self.limitCircle.layer.borderWidth = 3.5;
    self.limitCircle.layer.borderColor = [UIColor systemRedColor].CGColor;
    self.limitCircle.translatesAutoresizingMaskIntoConstraints = NO;

    self.limitValueLbl = [[UILabel alloc] init];
    self.limitValueLbl.text = [NSString stringWithFormat:@"%ld", (long)[AppSettings shared].speedLimitValue];
    self.limitValueLbl.font = [UIFont boldSystemFontOfSize:14];
    self.limitValueLbl.textColor = [UIColor blackColor];
    self.limitValueLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.limitCircle addSubview:self.limitValueLbl];

    [self.speedCard addSubview:self.clockLbl];
    [self.speedCard addSubview:self.batLbl];
    [self.speedCard addSubview:self.speedValueLbl];
    [self.speedCard addSubview:kmh];
    [self.speedCard addSubview:self.limitCircle];
    [self.outerFrame addSubview:self.speedCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.speedCard.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor constant:8],
        [self.speedCard.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor constant:-10],
        [self.speedCard.widthAnchor constraintEqualToConstant:114],
        [self.speedCard.heightAnchor constraintEqualToConstant:76],

        [self.clockLbl.topAnchor constraintEqualToAnchor:self.speedCard.topAnchor constant:6],
        [self.clockLbl.leadingAnchor constraintEqualToAnchor:self.speedCard.leadingAnchor constant:10],

        [self.batLbl.topAnchor constraintEqualToAnchor:self.speedCard.topAnchor constant:6],
        [self.batLbl.trailingAnchor constraintEqualToAnchor:self.speedCard.trailingAnchor constant:-10],

        [self.speedValueLbl.topAnchor constraintEqualToAnchor:self.clockLbl.bottomAnchor constant:6],
        [self.speedValueLbl.leadingAnchor constraintEqualToAnchor:self.speedCard.leadingAnchor constant:8],
        [self.speedValueLbl.widthAnchor constraintEqualToConstant:44],

        [kmh.topAnchor constraintEqualToAnchor:self.speedValueLbl.bottomAnchor constant:0],
        [kmh.centerXAnchor constraintEqualToAnchor:self.speedValueLbl.centerXAnchor],

        [self.limitCircle.trailingAnchor constraintEqualToAnchor:self.speedCard.trailingAnchor constant:-10],
        [self.limitCircle.bottomAnchor constraintEqualToAnchor:self.speedCard.bottomAnchor constant:-10],
        [self.limitCircle.widthAnchor constraintEqualToConstant:40],
        [self.limitCircle.heightAnchor constraintEqualToAnchor:self.limitCircle.widthAnchor],

        [self.limitValueLbl.centerXAnchor constraintEqualToAnchor:self.limitCircle.centerXAnchor],
        [self.limitValueLbl.centerYAnchor constraintEqualToAnchor:self.limitCircle.centerYAnchor]
    ]];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm";
    self.clockLbl.text = [df stringFromDate:[NSDate date]];
    float b = [UIDevice currentDevice].batteryLevel;
    self.batLbl.text = [NSString stringWithFormat:@"%d%% 🔋", (b >= 0) ? (int)round(b * 100) : 95];

    self.locMgr = [[CLLocationManager alloc] init];
    self.locMgr.delegate = self;
    self.locMgr.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locMgr requestWhenInUseAuthorization];
    [self.locMgr startUpdatingLocation];
}

- (void)handleSpeedCardDrag:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.outerFrame];
    pan.view.center = CGPointMake(pan.view.center.x + trans.x, pan.view.center.y + trans.y);
    [pan setTranslation:CGPointZero inView:self.outerFrame];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (loc) {
        int kmh = (loc.speed >= 0) ? (int)round(loc.speed * 3.6) : 0;
        self.speedValueLbl.text = [NSString stringWithFormat:@"%d", kmh];
    }
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
    [self.overlayModal removeFromSuperview];
    modal.translatesAutoresizingMaskIntoConstraints = NO;
    [self.outerFrame addSubview:modal];
    [NSLayoutConstraint activateConstraints:@[
        [modal.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor constant:6],
        [modal.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor constant:-6],
        [modal.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor constant:6],
        [modal.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor constant:-6]
    ]];
    self.overlayModal = modal;
}

- (void)paneDidRequestAppPicker:(MultiTaskPaneView *)pane {
    self.deviceApps = ScanDeviceApps();
    NSString *title = [NSString stringWithFormat:@"Chọn app ô %ld", (long)pane.paneNumber];
    AppGridPickerView *picker = [[AppGridPickerView alloc] initWithTitle:title apps:self.deviceApps];
    __weak typeof(self) weakSelf = self;
    picker.onClose = ^{
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    picker.onSelect = ^(InstalledAppItem *app) {
        [pane openAppInPane:app];
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    [self showOverlay:picker];
}

- (void)paneDidRequestLayoutSheet:(MultiTaskPaneView *)pane {
    SidePlayLayoutModal *sheet = [[SidePlayLayoutModal alloc] initWithMode:self.splitMode];
    __weak typeof(self) weakSelf = self;
    sheet.onClose = ^{
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    sheet.onPickMode = ^(SidePlaySplitMode mode) {
        [weakSelf rebuildWorkspaceLayout:mode];
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    sheet.onQuickPreset = ^{
        [weakSelf rebuildWorkspaceLayout:SidePlaySplitDual];
        for (InstalledAppItem *item in weakSelf.deviceApps) {
            if ([item.bundleID.lowercaseString containsString:@"youtube"]) [weakSelf.panes[0] openAppInPane:item];
            if ([item.bundleID.lowercaseString containsString:@"vietmap"] || [item.bundleID.lowercaseString containsString:@"maps"]) [weakSelf.panes[1] openAppInPane:item];
        }
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    [self showOverlay:sheet];
}

- (void)paneDidRequestOpenNativeApp:(MultiTaskPaneView *)pane {
    if (pane.currentApp.bundleID.length > 0) {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) {
            [[wsClass defaultWorkspace] openApplicationWithBundleID:pane.currentApp.bundleID];
        }
    }
}

@end

#pragma mark - Tab 2: "Tren xe" (Tat ca cac dong deu hoat dong that khi cham vao)

@interface CarSettingsViewController : UITableViewController
@end

@implementation CarSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trên xe";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"CARPLAY" : @"TUỲ CHỈNH";
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 3 : 8;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    AppSettings *cfg = [AppSettings shared];

    if (ip.section == 0) {
        if (ip.row == 0) {
            [self styleCell:cell icon:@"car.fill" color:[UIColor systemBlueColor] title:@"Mở khi kết nối CarPlay" detail:nil];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = cfg.autoOpenCarPlay;
            sw.tag = 100;
            [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (ip.row == 1) {
            [self styleCell:cell icon:@"arrow.counterclockwise" color:[UIColor systemIndigoColor] title:@"Mở lại bố cục lần cuối" detail:nil];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = cfg.restoreLastLayout;
            sw.tag = 101;
            [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            [self styleCell:cell icon:@"power" color:[UIColor systemPurpleColor] title:@"Tự làm tối màn hình" detail:nil];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = cfg.autoDimScreen;
            sw.tag = 102;
            [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSString *speedStatus = cfg.showSpeedBubble ? [NSString stringWithFormat:@"Bật (%ld km/h)", (long)cfg.speedLimitValue] : @"Tắt";
        NSString *tabTime = cfg.tabAutoHideSeconds == 0 ? @"Luôn hiện" : [NSString stringWithFormat:@"%ld giây", (long)cfg.tabAutoHideSeconds];
        NSArray *splitNames = @[@"1 ô", @"2 ô chia đôi", @"3 ô dọc", @"4 ô dọc", @"Lưới 1+2", @"PiP nổi"];
        NSString *splitLabel = splitNames[MIN(MAX(cfg.defaultSplitMode, 0), 5)];

        NSArray *rows = @[
            @[@"speedometer", [UIColor systemOrangeColor], @"Bong bóng tốc độ", speedStatus],
            @[@"waveform", [UIColor systemPurpleColor], @"Trợ lí SideStaff", @"Đã mở khoá"],
            @[@"sparkles", [UIColor systemGreenColor], @"Đèn SideLed", @"Chưa kết nối"],
            @[@"macwindow", [UIColor systemGrayColor], @"Thanh tab ứng dụng", tabTime],
            @[@"sparkles.rectangle.stack.fill", [UIColor systemBlueColor], @"Mở nhanh", @"YouTube + Maps"],
            @[@"rectangle.split.2x1", [UIColor systemCyanColor], @"Màn hình trên xe", splitLabel],
            @[@"square.grid.2x2.fill", [UIColor systemIndigoColor], @"Ứng dụng", [NSString stringWithFormat:@"%lu app", (unsigned long)ScanDeviceApps().count]],
            @[@"wrench.and.screwdriver.fill", [UIColor systemGrayColor], @"Tuỳ chỉnh", @"Đầy đủ"]
        ];
        NSArray *r = rows[ip.row];
        [self styleCell:cell icon:r[0] color:r[1] title:r[2] detail:r[3]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)onSwitchChanged:(UISwitch *)sw {
    if (sw.tag == 100) [AppSettings shared].autoOpenCarPlay = sw.on;
    if (sw.tag == 101) [AppSettings shared].restoreLastLayout = sw.on;
    if (sw.tag == 102) [AppSettings shared].autoDimScreen = sw.on;
}

- (void)styleCell:(UITableViewCell *)cell icon:(NSString *)ic color:(UIColor *)col title:(NSString *)t detail:(NSString *)d {
    cell.textLabel.text = t;
    cell.textLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightMedium];
    if (d && d.length > 0) cell.detailTextLabel.text = d;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0.0);
    [col setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 30, 30) cornerRadius:7] fill];
    UIImage *sym = [[UIImage systemImageNamed:ic] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    [sym drawInRect:CGRectMake(5, 5, 20, 20)];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1) return;

    AppSettings *cfg = [AppSettings shared];
    if (ip.row == 0) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Bong bóng tốc độ" message:@"Tuỳ chỉnh hiển thị tốc độ GPS và biển báo giới hạn trên màn hình" preferredStyle:UIAlertControllerStyleActionSheet];
        [ac addAction:[UIAlertAction actionWithTitle:(cfg.showSpeedBubble ? @"Ẩn bong bóng tốc độ" : @"Hiện bong bóng tốc độ") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            cfg.showSpeedBubble = !cfg.showSpeedBubble;
            [tv reloadData];
        }]];
        for (NSNumber *lim in @[@50, @60, @80, @100, @120]) {
            [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Giới hạn tốc độ: %@ km/h", lim] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                cfg.showSpeedBubble = YES;
                cfg.speedLimitValue = lim.integerValue;
                [tv reloadData];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else if (ip.row == 3) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Thanh tab ứng dụng" message:@"Chọn thời gian tự ẩn thanh tab" preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *sec in @[@0, @5, @10, @15]) {
            NSString *t = sec.integerValue == 0 ? @"Luôn hiển thị" : [NSString stringWithFormat:@"Sau %@ giây", sec];
            [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                cfg.tabAutoHideSeconds = sec.integerValue;
                [tv reloadData];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else if (ip.row == 4 || ip.row == 6) {
        self.tabBarController.selectedIndex = 2;
    } else if (ip.row == 5) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Màn hình trên xe mặc định" message:@"Chọn số ô chia màn hình khi khởi động" preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *names = @[@"1 ô toàn màn hình", @"2 ô chia đôi dọc", @"3 ô chia dọc", @"4 ô chia dọc", @"Lưới 3 ô (1 Trái + 2 Phải)", @"Cửa sổ nổi PiP"];
        for (NSInteger i = 0; i < names.count; i++) {
            [ac addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                cfg.defaultSplitMode = i;
                [tv reloadData];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đã kích hoạt SidePro" message:@"Tính năng này đã được mở khoá sẵn trên bản XemYouTube 2.4.0 của bạn." preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    }
}

@end

#pragma mark - Tab 4: "Tai khoan"

@interface AccountProViewController : UITableViewController
@end

@implementation AccountProViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tài khoản";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0 || s == 1) return 1;
    if (s == 2 || s == 3) return 3;
    return 2;
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return s == 4 ? @"SidePlay2 2.4.0 (Full Active)" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"SidePro · Vĩnh viễn";
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.text = @"Đã mở khoá toàn bộ tính năng Pro";
        cell.detailTextLabel.textColor = [UIColor systemGreenColor];
        cell.imageView.image = [UIImage systemImageNamed:@"checkmark.seal.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (ip.section == 1) {
        cell.textLabel.text = @"Trạng thái bản quyền";
        cell.detailTextLabel.text = @"Đã kích hoạt";
        cell.imageView.image = [UIImage systemImageNamed:@"creditcard.circle.fill"];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
    } else if (ip.section == 2) {
        NSArray *items = @[
            @[@"circle.lefthalf.filled", [UIColor systemIndigoColor], @"Giao diện", @"Sáng"],
            @[@"globe", [UIColor systemBlueColor], @"Ngôn ngữ", @"Tiếng Việt"],
            @[@"gauge.with.dots.needle.67percent", [UIColor systemGreenColor], @"Chế độ máy", @"Mượt (60fps)"]
        ];
        NSArray *r = items[ip.row];
        cell.imageView.image = [UIImage systemImageNamed:r[0]];
        cell.imageView.tintColor = r[1];
        cell.textLabel.text = r[2];
        cell.detailTextLabel.text = r[3];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 3) {
        NSArray *items = @[
            @[@"bell.fill", [UIColor systemRedColor], @"Thông báo"],
            @[@"questionmark.square.fill", [UIColor systemBlueColor], @"Câu hỏi thường gặp"],
            @[@"ladybug.fill", [UIColor systemGrayColor], @"Báo cáo lỗi"]
        ];
        NSArray *r = items[ip.row];
        cell.imageView.image = [UIImage systemImageNamed:r[0]];
        cell.imageView.tintColor = r[1];
        cell.textLabel.text = r[2];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        if (ip.row == 0) {
            cell.textLabel.text = @"Respring";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            cell.textLabel.text = @"Đặt lại tất cả cài đặt";
            cell.textLabel.textColor = [UIColor systemRedColor];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 4 && ip.row == 0) {
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, environ);
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, environ);
    } else if (ip.section == 4 && ip.row == 1) {
        [[AppSettings shared] resetAll];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đã đặt lại" message:@"Toàn bộ cài đặt đã trở về mặc định." preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    }
}

@end

#pragma mark - Tab 1: "Trang chu"

@interface HomeLauncherViewController : UITableViewController
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@end

@implementation HomeLauncherViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trang chủ";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
    self.apps = ScanDeviceApps();
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @"CHẠM VÀO ỨNG DỤNG ĐỂ MỞ TRONG Ô MÔ PHỎNG";
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.apps.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    InstalledAppItem *a = self.apps[ip.row];
    cell.textLabel.text = a.name;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
    cell.detailTextLabel.text = a.bundleID;
    cell.imageView.image = a.icon;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    InstalledAppItem *app = self.apps[ip.row];
    SimulationViewController *simVC = (SimulationViewController *)self.tabBarController.viewControllers[2];
    if ([simVC isKindOfClass:[SimulationViewController class]]) {
        [simVC view];
        [simVC openAppInFirstAvailablePane:app];
    }
    self.tabBarController.selectedIndex = 2;
}
@end

#pragma mark - Floating Pill TabBarController

@interface FloatingPillTabBarController : UITabBarController
@property (nonatomic, strong) UIView *pillBar;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@end

@implementation FloatingPillTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.hidden = YES;

    UINavigationController *vc0 = [[UINavigationController alloc] initWithRootViewController:[[HomeLauncherViewController alloc] init]];
    UINavigationController *vc1 = [[UINavigationController alloc] initWithRootViewController:[[CarSettingsViewController alloc] init]];
    SimulationViewController *vc2 = [[SimulationViewController alloc] init];
    UINavigationController *vc3 = [[UINavigationController alloc] initWithRootViewController:[[AccountProViewController alloc] init]];

    self.viewControllers = @[vc0, vc1, vc2, vc3];
    [self buildFloatingPillBar];
    [self switchToTab:2];
}

- (void)buildFloatingPillBar {
    self.pillBar = [[UIView alloc] init];
    self.pillBar.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.96];
    self.pillBar.layer.cornerRadius = 28;
    self.pillBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.pillBar.layer.shadowOpacity = 0.10;
    self.pillBar.layer.shadowRadius = 12;
    self.pillBar.layer.shadowOffset = CGSizeMake(0, 4);
    self.pillBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pillBar];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pillBar addSubview:stack];

    NSArray *titles = @[@"Trang chủ", @"Trên xe", @"Mô phỏng", @"Tài khoản"];
    NSArray *icons  = @[@"house.fill", @"car.fill", @"play.rectangle.fill", @"person.crop.circle.fill"];
    self.tabButtons = [NSMutableArray array];

    for (NSInteger i = 0; i < 4; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = i;
        btn.layer.cornerRadius = 22;

        UIStackView *vStack = [[UIStackView alloc] init];
        vStack.axis = UILayoutConstraintAxisVertical;
        vStack.alignment = UIStackViewAlignmentCenter;
        vStack.spacing = 3;
        vStack.userInteractionEnabled = NO;
        vStack.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icons[i]]];
        iv.tag = 101;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        [iv.widthAnchor constraintEqualToConstant:22].active = YES;
        [iv.heightAnchor constraintEqualToConstant:22].active = YES;

        UILabel *lbl = [[UILabel alloc] init];
        lbl.tag = 102;
        lbl.text = titles[i];
        lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];

        [vStack addArrangedSubview:iv];
        [vStack addArrangedSubview:lbl];
        [btn addSubview:vStack];

        [NSLayoutConstraint activateConstraints:@[
            [vStack.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
            [vStack.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor]
        ]];

        [btn addTarget:self action:@selector(onPillTabTap:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [self.tabButtons addObject:btn];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.pillBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.pillBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.pillBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [self.pillBar.heightAnchor constraintEqualToConstant:62],

        [stack.topAnchor constraintEqualToAnchor:self.pillBar.topAnchor constant:5],
        [stack.bottomAnchor constraintEqualToAnchor:self.pillBar.bottomAnchor constant:-5],
        [stack.leadingAnchor constraintEqualToAnchor:self.pillBar.leadingAnchor constant:6],
        [stack.trailingAnchor constraintEqualToAnchor:self.pillBar.trailingAnchor constant:-6]
    ]];
}

- (void)onPillTabTap:(UIButton *)sender {
    [self switchToTab:sender.tag];
}

- (void)switchToTab:(NSInteger)idx {
    self.selectedIndex = idx;
    UIColor *activeBlue = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];
    UIColor *activeBg   = [UIColor colorWithRed:0.86 green:0.93 blue:1.0 alpha:1.0];
    UIColor *inactiveGr = [UIColor colorWithWhite:0.45 alpha:1.0];

    for (NSInteger i = 0; i < self.tabButtons.count; i++) {
        UIButton *b = self.tabButtons[i];
        BOOL sel = (i == idx);
        b.backgroundColor = sel ? activeBg : [UIColor clearColor];
        UIImageView *iv = [b viewWithTag:101];
        UILabel *lbl = [b viewWithTag:102];
        iv.tintColor = sel ? activeBlue : inactiveGr;
        lbl.textColor = sel ? activeBlue : inactiveGr;
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    if (self.tabButtons.count == 4 && selectedIndex < 4) {
        UIColor *activeBlue = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];
        UIColor *activeBg   = [UIColor colorWithRed:0.86 green:0.93 blue:1.0 alpha:1.0];
        UIColor *inactiveGr = [UIColor colorWithWhite:0.45 alpha:1.0];
        for (NSInteger i = 0; i < 4; i++) {
            UIButton *b = self.tabButtons[i];
            BOOL sel = (i == (NSInteger)selectedIndex);
            b.backgroundColor = sel ? activeBg : [UIColor clearColor];
            UIImageView *iv = [b viewWithTag:101];
            UILabel *lbl = [b viewWithTag:102];
            iv.tintColor = sel ? activeBlue : inactiveGr;
            lbl.textColor = sel ? activeBlue : inactiveGr;
        }
    }
}

@end

#pragma mark - CarPlay & Phone Scene Delegates

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property (nonatomic, strong) CPWindow *carWindow;
@end

@implementation CarPlaySceneDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)s didConnectInterfaceController:(CPInterfaceController *)ic toWindow:(CPWindow *)window {
    self.carWindow = window;
    SimulationViewController *carSim = [[SimulationViewController alloc] init];
    carSim.isCarPlayWindow = YES;
    window.rootViewController = carSim;
    [window makeKeyAndVisible];
}
@end

@interface PhoneSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PhoneSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.window.rootViewController = [[FloatingPillTabBarController alloc] init];
    [self.window makeKeyAndVisible];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions { return YES; }
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if ([session.role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication]) {
        UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"CarPlayScene" sessionRole:session.role];
        cfg.delegateClass = [CarPlaySceneDelegate class];
        return cfg;
    }
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"PhoneScene" sessionRole:session.role];
    cfg.delegateClass = [PhoneSceneDelegate class];
    return cfg;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
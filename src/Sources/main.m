#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>

extern char **environ;

#pragma mark - Private APIs (LSApplicationWorkspace + FrontBoard / BackBoard Live Scene Hosting)

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

@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dict;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)dashboardService;
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleID withOptions:(id)options completion:(void (^)(id process, NSError *error))completion;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (NSSet *)scenes;
@end

@interface FBScene : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
- (id)uiPresentationManager;
- (void)updateSettingsWithBlock:(void (^)(id mutableSettings))block;
@end

@interface FBSMutableSceneSettings : NSObject
- (void)setFrame:(CGRect)frame;
- (void)setForeground:(BOOL)fg;
- (void)setInterfaceOrientation:(UIInterfaceOrientation)orientation;
@end

@interface UIScenePresentationManager : NSObject
- (id)createPresenterWithIdentifier:(NSString *)identifier;
@end

@interface UIScenePresenter : NSObject
@property (nonatomic, readonly) UIView *presentationView;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
@end

#pragma mark - App Model & Quet Danh Sach Ung Dung That Tren May

@interface InstalledAppItem : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *webMirrorURL;
@end

@implementation InstalledAppItem
@end

static NSString *MirrorURLForApp(NSString *bundleID, NSString *name) {
    NSString *k = [NSString stringWithFormat:@"%@ %@", bundleID.lowercaseString, name.lowercaseString];
    if ([k containsString:@"youtube"]) return @"https://m.youtube.com";
    if ([k containsString:@"vietmap"]) return @"https://maps.vietmap.vn";
    if ([k containsString:@"maps"] || [k containsString:@"google.maps"]) return @"https://www.google.com/maps";
    if ([k containsString:@"translate"] || [k containsString:@"dich"]) return @"https://translate.google.com";
    if ([k containsString:@"gmail"] || [k containsString:@"mail"]) return @"https://mail.google.com";
    if ([k containsString:@"zing"]) return @"https://zingmp3.vn";
    if ([k containsString:@"spotify"] || [k containsString:@"music"] || [k containsString:@"nhac"]) return @"https://open.spotify.com";
    if ([k containsString:@"tiktok"]) return @"https://www.tiktok.com";
    if ([k containsString:@"zalo"]) return @"https://chat.zalo.me";
    if ([k containsString:@"telegram"]) return @"https://web.telegram.org";
    if ([k containsString:@"messenger"] || [k containsString:@"facebook"]) return @"https://m.facebook.com";
    if ([k containsString:@"weather"] || [k containsString:@"thoi tiet"]) return @"https://www.windy.com";
    if ([k containsString:@"shopee"]) return @"https://shopee.vn";
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
            item.webMirrorURL = MirrorURLForApp(bid, name);
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

#pragma mark - 1 O Cua So Da Nhiem (Co "+ Tab moi", "Gan day", "Tat ca app >", Thanh Tab & Live Host)

@class MultiTaskPaneView;
@protocol MultiTaskPaneDelegate <NSObject>
- (void)paneDidRequestAppPicker:(MultiTaskPaneView *)pane;
- (void)paneDidRequestLayoutSheet:(MultiTaskPaneView *)pane;
- (void)paneDidRequestToggleFull:(MultiTaskPaneView *)pane;
@end

@interface MultiTaskPaneView : UIView
@property (nonatomic, assign) NSInteger paneNumber; // 1..4
@property (nonatomic, weak) id<MultiTaskPaneDelegate> delegate;
@property (nonatomic, strong) UIButton *activeTabButton;
@property (nonatomic, strong) UIView *tabStripContainer;
@property (nonatomic, strong) UIStackView *tabStripStack;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIButton *recentEmptyBtn;
@property (nonatomic, strong) UIView *runningContainerView;
@property (nonatomic, strong) WKWebView *interactiveWebView;
@property (nonatomic, strong) id liveScenePresenter;
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
    // 1. Thanh Chrome tren cung kieu trinh duyet (+ Tab moi v | 3 nut Vang/Xanh/Do)
    UIView *chromeBar = [[UIView alloc] init];
    chromeBar.backgroundColor = [UIColor colorWithRed:0.91 green:0.92 blue:0.95 alpha:1.0];
    chromeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:chromeBar];

    self.activeTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.activeTabButton.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    self.activeTabButton.layer.cornerRadius = 10;
    self.activeTabButton.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.activeTabButton setTitle:@" +  Tab mới  ⌄" forState:UIControlStateNormal];
    [self.activeTabButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    self.activeTabButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.activeTabButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.activeTabButton.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
    self.activeTabButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activeTabButton addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    UIButton *btnYellow = [self makeWindowCircle:[UIColor colorWithRed:0.96 green:0.74 blue:0.25 alpha:1.0] symbol:@"arrow.left.and.right" action:@selector(onTapYellow)];
    UIButton *btnGreen  = [self makeWindowCircle:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0] symbol:@"arrow.up.left.and.arrow.down.right" action:@selector(onTapGreen)];
    UIButton *btnRed    = [self makeWindowCircle:[UIColor colorWithRed:0.95 green:0.35 blue:0.30 alpha:1.0] symbol:@"xmark" action:@selector(onTapRed)];

    UIStackView *winBtns = [[UIStackView alloc] initWithArrangedSubviews:@[btnYellow, btnGreen, btnRed]];
    winBtns.spacing = 7;
    winBtns.translatesAutoresizingMaskIntoConstraints = NO;

    [chromeBar addSubview:self.activeTabButton];
    [chromeBar addSubview:winBtns];

    // 2. Thanh Tab Strip (hien thi khi da mo >= 1 app: Googl... | YouT... | VIET...)
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

    // 3. Trang thai "+ Tab moi" khi chua mo app (Giong het anh 2: Gan day / Chua co app gan day / Tat ca app >)
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
    [self.recentEmptyBtn addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    UIButton *allAppsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [allAppsBtn setTitle:@"Tất cả app ›" forState:UIControlStateNormal];
    [allAppsBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    allAppsBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    allAppsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [allAppsBtn addTarget:self action:@selector(onTapSelectApp) forControlEvents:UIControlEventTouchUpInside];

    [self.emptyStateView addSubview:recentHdr];
    [self.emptyStateView addSubview:self.recentEmptyBtn];
    [self.emptyStateView addSubview:allAppsBtn];

    // 4. Khung chay ung dung song song
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
    self.interactiveWebView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
    self.interactiveWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runningContainerView addSubview:self.interactiveWebView];

    [NSLayoutConstraint activateConstraints:@[
        [chromeBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [chromeBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [chromeBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [chromeBar.heightAnchor constraintEqualToConstant:34],

        [self.activeTabButton.leadingAnchor constraintEqualToAnchor:chromeBar.leadingAnchor constant:6],
        [self.activeTabButton.bottomAnchor constraintEqualToAnchor:chromeBar.bottomAnchor],
        [self.activeTabButton.heightAnchor constraintEqualToConstant:28],
        [self.activeTabButton.trailingAnchor constraintLessThanOrEqualToAnchor:winBtns.leadingAnchor constant:-6],
        [self.activeTabButton.widthAnchor constraintGreaterThanOrEqualToConstant:88],

        [winBtns.trailingAnchor constraintEqualToAnchor:chromeBar.trailingAnchor constant:-8],
        [winBtns.centerYAnchor constraintEqualToAnchor:chromeBar.centerYAnchor],

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

        [recentHdr.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:14],
        [recentHdr.centerYAnchor constraintEqualToAnchor:self.emptyStateView.centerYAnchor constant:-48],

        [self.recentEmptyBtn.topAnchor constraintEqualToAnchor:recentHdr.bottomAnchor constant:8],
        [self.recentEmptyBtn.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:14],
        [self.recentEmptyBtn.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor constant:-14],
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
    b.layer.cornerRadius = 7;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:7 weight:UIImageSymbolWeightBold];
    [b setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:14].active = YES;
    [b.heightAnchor constraintEqualToConstant:14].active = YES;
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
    [self.activeTabButton setTitle:[NSString stringWithFormat:@" %@  ⌄", shortName] forState:UIControlStateNormal];
    [self.activeTabButton setImage:[self scaledIcon:app.icon size:CGSizeMake(14, 14)] forState:UIControlStateNormal];

    NSPredicate *p = [NSPredicate predicateWithFormat:@"bundleID != %@", app.bundleID];
    [self.openedTabs filterUsingPredicate:p];
    [self.openedTabs insertObject:app atIndex:0];
    if (self.openedTabs.count > 4) [self.openedTabs removeLastObject];
    [self refreshTabStrip];

    // 1. Khoi chay ngam ung dung goc & nhung truc tiep Live Scene neu co quyen FrontBoard
    BOOL attachedLive = [self launchAndAttachLiveSceneForApp:app];
    if (!attachedLive) {
        self.interactiveWebView.hidden = NO;
        [self.interactiveWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:app.webMirrorURL]]];
    }
}

- (BOOL)launchAndAttachLiveSceneForApp:(InstalledAppItem *)app {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard", RTLD_LAZY);

    // Khoi chay ngam process ung dung goc qua FBSOpenApplicationService
    Class openSvcClass = NSClassFromString(@"FBSOpenApplicationService");
    Class openOptClass = NSClassFromString(@"FBSOpenApplicationOptions");
    if (openSvcClass && openOptClass) {
        id service = [openSvcClass respondsToSelector:@selector(serviceWithDefaultShellEndpoint)] ? [openSvcClass serviceWithDefaultShellEndpoint] : nil;
        if (service) {
            NSDictionary *optsDict = @{ @"__ActivateSuspended" : @YES };
            id opts = [openOptClass optionsWithDictionary:optsDict];
            [service openApplication:app.bundleID withOptions:opts completion:nil];
        }
    }

    // Kiem tra FBSceneManager de lay UIScenePresenter truc tiep
    Class fbMgrClass = NSClassFromString(@"FBSceneManager");
    if (fbMgrClass && [fbMgrClass respondsToSelector:@selector(sharedInstance)]) {
        id mgr = [fbMgrClass sharedInstance];
        if ([mgr respondsToSelector:@selector(scenes)]) {
            for (id scene in [mgr scenes]) {
                NSString *sid = [scene valueForKey:@"identifier"];
                if ([sid containsString:app.bundleID]) {
                    if ([scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
                        CGRect targetBounds = self.runningContainerView.bounds.size.width > 10 ? self.runningContainerView.bounds : CGRectMake(0, 0, 180, 360);
                        [scene updateSettingsWithBlock:^(id mutableSettings) {
                            if ([mutableSettings respondsToSelector:@selector(setForeground:)]) [mutableSettings setForeground:YES];
                            if ([mutableSettings respondsToSelector:@selector(setFrame:)]) [mutableSettings setFrame:targetBounds];
                        }];
                    }
                    id presMgr = [scene uiPresentationManager];
                    if ([presMgr respondsToSelector:@selector(createPresenterWithIdentifier:)]) {
                        id presenter = [presMgr createPresenterWithIdentifier:[NSString stringWithFormat:@"SidePlayHost-%ld", (long)self.paneNumber]];
                        if ([presenter respondsToSelector:@selector(activate)]) {
                            [presenter activate];
                            UIView *v = [presenter presentationView];
                            if (v) {
                                for (UIView *sub in self.runningContainerView.subviews) {
                                    if (sub != self.interactiveWebView) [sub removeFromSuperview];
                                }
                                self.interactiveWebView.hidden = YES;
                                v.frame = self.runningContainerView.bounds;
                                v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                                [self.runningContainerView addSubview:v];
                                self.liveScenePresenter = presenter;
                                return YES;
                            }
                        }
                    }
                }
            }
        }
    }
    return NO;
}

- (void)closeCurrentTab {
    self.currentApp = nil;
    self.runningContainerView.hidden = YES;
    self.tabStripContainer.hidden = YES;
    self.emptyStateView.hidden = NO;
    [self.activeTabButton setImage:nil forState:UIControlStateNormal];
    [self.activeTabButton setTitle:@" +  Tab mới  ⌄" forState:UIControlStateNormal];
    if (self.openedTabs.count > 0) {
        InstalledAppItem *last = self.openedTabs.firstObject;
        [self.recentEmptyBtn setTitle:[NSString stringWithFormat:@"Mở lại: %@", last.name] forState:UIControlStateNormal];
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
- (void)onTapGreen { [self.delegate paneDidRequestToggleFull:self]; }
- (void)onTapRed { [self closeCurrentTab]; }

@end

#pragma mark - Hop Thoai "Chia man hinh" (Giong het anh 6)

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
    qTitle.text = @"MỞ NHANH";
    qTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    qTitle.textColor = [UIColor secondaryLabelColor];
    qTitle.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *quickPill = [UIButton buttonWithType:UIButtonTypeSystem];
    quickPill.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    quickPill.layer.cornerRadius = 18;
    quickPill.layer.borderWidth = 1.2;
    quickPill.layer.borderColor = [UIColor systemBlueColor].CGColor;
    [quickPill setTitle:@"  +   ⊞   ▶   🗺️  " forState:UIControlStateNormal];
    quickPill.titleLabel.font = [UIFont boldSystemFontOfSize:14];
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

        [qTitle.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:18],
        [qTitle.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

        [quickPill.topAnchor constraintEqualToAnchor:qTitle.bottomAnchor constant:8],
        [quickPill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [quickPill.heightAnchor constraintEqualToConstant:40],
        [quickPill.widthAnchor constraintEqualToConstant:156],

        [exitBtn.topAnchor constraintEqualToAnchor:quickPill.bottomAnchor constant:18],
        [exitBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [exitBtn.widthAnchor constraintEqualToConstant:140],
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

#pragma mark - Luoi "Chon app o 1 / 2" (5 cot giong het anh 4)

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

#pragma mark - Tab 3: Man Hinh "Mo phong" (Giong het anh 2, 4, 5, 6)

@interface SimulationViewController : UIViewController <MultiTaskPaneDelegate, CLLocationManagerDelegate>
@property (nonatomic, assign) BOOL isCarPlayWindow;
@property (nonatomic, assign) SidePlaySplitMode splitMode;
@property (nonatomic, strong) UIView *outerFrame;
@property (nonatomic, strong) NSMutableArray<MultiTaskPaneView *> *panes;
@property (nonatomic, strong) UIView *centerDivider;
@property (nonatomic, strong) UIView *centerPillThumb;
@property (nonatomic, strong) NSLayoutConstraint *pane1WidthConstraint;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) UIView *overlayModal;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *deviceApps;

// Bong bong toc do goc duoi ben trai o 1
@property (nonatomic, strong) UIView *speedCard;
@property (nonatomic, strong) UILabel *clockLbl;
@property (nonatomic, strong) UILabel *batLbl;
@property (nonatomic, strong) UILabel *speedValueLbl;
@property (nonatomic, strong) UIView *limitCircle;
@property (nonatomic, strong) UILabel *limitValueLbl;
@property (nonatomic, strong) CLLocationManager *locMgr;
@end

@implementation SimulationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0];
    self.deviceApps = ScanDeviceApps();
    self.splitMode = SidePlaySplitDual;
    self.splitRatio = 0.5;
    self.panes = [NSMutableArray array];

    UILabel *bigTitle = [[UILabel alloc] init];
    bigTitle.text = @"Mô phỏng";
    bigTitle.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    bigTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bigTitle];

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
        [NSLayoutConstraint activateConstraints:@[
            [self.outerFrame.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
            [self.outerFrame.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
            [self.outerFrame.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:4],
            [self.outerFrame.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-4]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [bigTitle.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
            [bigTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],

            [self.outerFrame.topAnchor constraintEqualToAnchor:bigTitle.bottomAnchor constant:14],
            [self.outerFrame.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
            [self.outerFrame.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
            [self.outerFrame.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.50]
        ]];
    }

    for (NSInteger i = 1; i <= 4; i++) {
        MultiTaskPaneView *p = [[MultiTaskPaneView alloc] initWithPaneNumber:i];
        p.delegate = self;
        p.translatesAutoresizingMaskIntoConstraints = NO;
        [self.panes addObject:p];
    }

    self.centerDivider = [[UIView alloc] init];
    self.centerDivider.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1.0];
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
        [self.centerPillThumb.widthAnchor constraintEqualToConstant:12],
        [self.centerPillThumb.heightAnchor constraintEqualToConstant:36],
        [gripDots.centerXAnchor constraintEqualToAnchor:self.centerPillThumb.centerXAnchor],
        [gripDots.centerYAnchor constraintEqualToAnchor:self.centerPillThumb.centerYAnchor]
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDividerDrag:)];
    [self.centerDivider addGestureRecognizer:pan];

    [self rebuildWorkspaceLayout:SidePlaySplitDual];
    [self buildSpeedWidget];
}

- (void)rebuildWorkspaceLayout:(SidePlaySplitMode)mode {
    self.splitMode = mode;
    for (UIView *sub in self.outerFrame.subviews) {
        if (sub != self.speedCard) [sub removeFromSuperview];
    }

    MultiTaskPaneView *p1 = self.panes[0];
    MultiTaskPaneView *p2 = self.panes[1];

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

        self.pane1WidthConstraint = [p1.widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:self.splitRatio constant:-1];
        [NSLayoutConstraint activateConstraints:@[
            [p1.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.outerFrame.leadingAnchor],
            self.pane1WidthConstraint,

            [self.centerDivider.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [self.centerDivider.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [self.centerDivider.leadingAnchor constraintEqualToAnchor:p1.trailingAnchor],
            [self.centerDivider.widthAnchor constraintEqualToConstant:2],

            [p2.topAnchor constraintEqualToAnchor:self.outerFrame.topAnchor],
            [p2.bottomAnchor constraintEqualToAnchor:self.outerFrame.bottomAnchor],
            [p2.leadingAnchor constraintEqualToAnchor:self.centerDivider.trailingAnchor],
            [p2.trailingAnchor constraintEqualToAnchor:self.outerFrame.trailingAnchor]
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
}

- (void)buildSpeedWidget {
    self.speedCard = [[UIView alloc] init];
    self.speedCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.96];
    self.speedCard.layer.cornerRadius = 16;
    self.speedCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.speedCard.layer.shadowOpacity = 0.14;
    self.speedCard.layer.shadowRadius = 8;
    self.speedCard.layer.shadowOffset = CGSizeMake(0, 3);
    self.speedCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.clockLbl = [[UILabel alloc] init];
    self.clockLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    self.clockLbl.textColor = [UIColor blackColor];
    self.clockLbl.translatesAutoresizingMaskIntoConstraints = NO;

    self.batLbl = [[UILabel alloc] init];
    self.batLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    self.batLbl.textColor = [UIColor blackColor];
    self.batLbl.translatesAutoresizingMaskIntoConstraints = NO;

    self.speedValueLbl = [[UILabel alloc] init];
    self.speedValueLbl.text = @"--";
    self.speedValueLbl.font = [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightBold];
    self.speedValueLbl.textColor = [UIColor darkGrayColor];
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
    self.limitCircle.layer.borderWidth = 2.0;
    self.limitCircle.layer.borderColor = [UIColor grayColor].CGColor;
    self.limitCircle.translatesAutoresizingMaskIntoConstraints = NO;

    self.limitValueLbl = [[UILabel alloc] init];
    self.limitValueLbl.text = @"--";
    self.limitValueLbl.font = [UIFont boldSystemFontOfSize:14];
    self.limitValueLbl.textColor = [UIColor darkGrayColor];
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
        [self.limitCircle.heightAnchor constraintEqualToConstant:40],

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

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (loc) {
        int kmh = (loc.speed >= 0) ? (int)round(loc.speed * 3.6) : 0;
        self.speedValueLbl.text = [NSString stringWithFormat:@"%d", kmh];
        self.speedValueLbl.textColor = [UIColor blackColor];
        self.limitCircle.layer.borderWidth = 3.5;
        self.limitCircle.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.limitValueLbl.text = @"50";
        self.limitValueLbl.textColor = [UIColor blackColor];
    }
}

- (void)handleDividerDrag:(UIPanGestureRecognizer *)pan {
    if (self.splitMode != SidePlaySplitDual) return;
    CGPoint pt = [pan locationInView:self.outerFrame];
    CGFloat r = MIN(MAX(pt.x / MAX(self.outerFrame.bounds.size.width, 1.0), 0.25), 0.75);
    self.splitRatio = r;
    self.pane1WidthConstraint.active = NO;
    self.pane1WidthConstraint = [self.panes[0].widthAnchor constraintEqualToAnchor:self.outerFrame.widthAnchor multiplier:r constant:-1];
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
            if ([item.bundleID containsString:@"youtube"]) [weakSelf.panes[0] openAppInPane:item];
            if ([item.bundleID containsString:@"vietmap"] || [item.bundleID containsString:@"Maps"]) [weakSelf.panes[1] openAppInPane:item];
        }
        [weakSelf.overlayModal removeFromSuperview];
        weakSelf.overlayModal = nil;
    };
    [self showOverlay:sheet];
}

- (void)paneDidRequestToggleFull:(MultiTaskPaneView *)pane {
    [self paneDidRequestLayoutSheet:pane];
}

@end

#pragma mark - Tab 2: "Tren xe" (Giong het anh 1: CARPLAY & TUY CHINH)

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
    if (ip.section == 0) {
        if (ip.row == 0) {
            [self styleCell:cell icon:@"car.fill" color:[UIColor systemBlueColor] title:@"Mở khi kết nối CarPlay" detail:nil];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = YES;
            cell.accessoryView = sw;
        } else if (ip.row == 1) {
            [self styleCell:cell icon:@"arrow.counterclockwise" color:[UIColor systemIndigoColor] title:@"Mở lại bố cục lần cuối" detail:nil];
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
            cell.accessoryView.tintColor = [UIColor systemGray2Color];
        } else {
            [self styleCell:cell icon:@"power" color:[UIColor systemPurpleColor] title:@"Tự làm tối màn hình" detail:nil];
            cell.accessoryView = [[UISwitch alloc] init];
        }
    } else {
        NSArray *rows = @[
            @[@"speedometer", [UIColor systemOrangeColor], @"Bong bóng tốc độ", @""],
            @[@"waveform", [UIColor systemPurpleColor], @"Trợ lí SideStaff", @"LOCK"],
            @[@"sparkles", [UIColor systemGreenColor], @"Đèn SideLed", @"Chưa kết nối"],
            @[@"macwindow", [UIColor systemGrayColor], @"Thanh tab ứng dụng", @"5 giây"],
            @[@"sparkles.rectangle.stack.fill", [UIColor systemBlueColor], @"Mở nhanh", @""],
            @[@"rectangle.split.2x1", [UIColor systemCyanColor], @"Màn hình trên xe", @""],
            @[@"square.grid.2x2.fill", [UIColor systemIndigoColor], @"Ứng dụng", @"Tất cả"],
            @[@"wrench.and.screwdriver.fill", [UIColor systemGrayColor], @"Tuỳ chỉnh", @""]
        ];
        NSArray *r = rows[ip.row];
        [self styleCell:cell icon:r[0] color:r[1] title:r[2] detail:r[3]];
        if ([r[3] isEqualToString:@"LOCK"]) {
            cell.detailTextLabel.text = @"";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
            cell.accessoryView.tintColor = [UIColor systemGray2Color];
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
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
}

@end

#pragma mark - Tab 4: "Tai khoan" (Giong het anh 3: SidePro, Giao dien, Respring...)

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
    return s == 4 ? @"XemYouTube (SidePlay2 UI) 2.3.0" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"SidePro · SideMonth";
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.text = @"Còn 29 ngày (Đã kích hoạt)";
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = [UIImage systemImageNamed:@"creditcard.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (ip.section == 1) {
        cell.textLabel.text = @"Mua SidePro";
        cell.imageView.image = [UIImage systemImageNamed:@"creditcard.circle.fill"];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2) {
        NSArray *items = @[
            @[@"circle.lefthalf.filled", [UIColor systemIndigoColor], @"Giao diện", @"Sáng"],
            @[@"globe", [UIColor systemBlueColor], @"Ngôn ngữ", @"Tiếng Việt"],
            @[@"gauge.with.dots.needle.67percent", [UIColor systemGreenColor], @"Chế độ máy", @"Mượt"]
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
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, environ);
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, environ);
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
    return @"CHẠM ĐỂ MỞ TRONG ĐA CỬA SỐ MÔ PHỎNG";
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
    self.tabBarController.selectedIndex = 2;
}
@end

#pragma mark - Custom Floating Pill TabBarController (Giong het thanh 4 tab noi o day anh)

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
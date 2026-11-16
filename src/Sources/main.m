#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma mark - Private APIs (LSApplicationWorkspace + FrontBoard Scene Hosting)

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

// FrontBoard Scene Hosting interfaces (nhung truc tiep giao dien ung dung that vao o cua so)
@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (NSSet *)scenes;
- (id)sceneWithIdentifier:(NSString *)identifier;
@end

@interface FBScene : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
- (id)uiPresentationManager;
- (id)settings;
- (void)updateSettingsWithBlock:(void (^)(id settings))block;
@end

@interface UIScenePresentationManager : NSObject
- (UIView *)createPresenterWithIdentifier:(NSString *)identifier;
@end

@interface UIScenePresenter : NSObject
@property (nonatomic, readonly) UIView *presentationView;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
@end

#pragma mark - App Model & Quet App Tren May

@interface InstalledAppItem : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *fallbackURL;
@end

@implementation InstalledAppItem
@end

static NSString *FallbackURLForApp(NSString *bundleID, NSString *name) {
    NSString *key = [NSString stringWithFormat:@"%@ %@", bundleID.lowercaseString, name.lowercaseString];
    if ([key containsString:@"youtube"]) return @"https://m.youtube.com";
    if ([key containsString:@"vietmap"]) return @"https://maps.vietmap.vn";
    if ([key containsString:@"maps"] || [key containsString:@"google"]) return @"https://www.google.com/maps";
    if ([key containsString:@"zing"]) return @"https://zingmp3.vn";
    if ([key containsString:@"spotify"]) return @"https://open.spotify.com";
    if ([key containsString:@"tiktok"]) return @"https://www.tiktok.com";
    if ([key containsString:@"zalo"]) return @"https://chat.zalo.me";
    if ([key containsString:@"telegram"]) return @"https://web.telegram.org";
    if ([key containsString:@"vtv"]) return @"https://vtvgo.vn";
    return @"https://www.google.com";
}

static NSArray<InstalledAppItem *> *GetInstalledApps(void) {
    NSMutableArray<InstalledAppItem *> *list = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass) {
        id ws = [wsClass defaultWorkspace];
        NSArray *all = [ws allInstalledApplications];
        NSSet *sysKeep = [NSSet setWithArray:@[
            @"com.apple.Maps", @"com.apple.Music", @"com.apple.mobilesafari",
            @"com.apple.weather", @"com.apple.podcasts", @"com.apple.mobilemail"
        ]];
        for (id proxy in all) {
            NSString *bid = [proxy valueForKey:@"applicationIdentifier"];
            NSString *type = [proxy valueForKey:@"applicationType"];
            NSString *name = [proxy valueForKey:@"localizedName"];
            if (!bid || !name || name.length == 0) continue;
            if ([bid isEqualToString:@"com.xemyoutube"]) continue;
            if (![type isEqualToString:@"User"] && ![sysKeep containsObject:bid]) continue;

            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = bid;
            item.name = name;
            item.fallbackURL = FallbackURLForApp(bid, name);
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
    if (list.count == 0) {
        NSArray *fallback = @[
            @[@"com.google.ios.youtube", @"YouTube", @"play.rectangle.fill", @"https://m.youtube.com"],
            @[@"vn.vietmap.live", @"VIETMAP Live", @"map.fill", @"https://maps.vietmap.vn"],
            @[@"com.google.Maps", @"Google Maps", @"location.fill", @"https://www.google.com/maps"],
            @[@"com.zing.mp3", @"Zing MP3", @"music.note", @"https://zingmp3.vn"]
        ];
        for (NSArray *f in fallback) {
            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = f[0];
            item.name = f[1];
            item.icon = [UIImage systemImageNamed:f[2]];
            item.fallbackURL = f[3];
            [list addObject:item];
        }
    }
    return list;
}

#pragma mark - 1 O Cua So Ung Dung (Nhung Scene that + Thanh Tab App + 3 Nut Vang/Xanh/Do)

@class AppWindowPane;
@protocol AppWindowPaneDelegate <NSObject>
- (void)windowPaneDidTapTitle:(AppWindowPane *)pane;
- (void)windowPaneDidTapLayout:(AppWindowPane *)pane;
- (void)windowPaneDidTapClose:(AppWindowPane *)pane;
@end

@interface AppWindowPane : UIView
@property (nonatomic, assign) NSInteger slotIndex;
@property (nonatomic, weak) id<AppWindowPaneDelegate> delegate;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *recentTabsStack;
@property (nonatomic, strong) UIView *contentHostView;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) id activeScenePresenter;
@property (nonatomic, strong) InstalledAppItem *currentApp;
@property (nonatomic, strong) NSMutableArray<InstalledAppItem *> *recentApps;
- (instancetype)initWithSlotIndex:(NSInteger)slot;
- (void)hostApplication:(InstalledAppItem *)app;
@end

@implementation AppWindowPane

- (instancetype)initWithSlotIndex:(NSInteger)slot {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.slotIndex = slot;
        self.recentApps = [NSMutableArray array];
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.clipsToBounds = YES;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    // 1. Thanh tieu de tren cung (Icon + Ten app + 3 nut tron Vang/Xanh/Do)
    UIView *topBar = [[UIView alloc] init];
    topBar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:topBar];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.layer.cornerRadius = 5;
    self.iconView.clipsToBounds = YES;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chev.tintColor = [UIColor secondaryLabelColor];
    chev.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *btnYellow = [self dotBtn:[UIColor systemYellowColor] sel:@selector(onLayout)];
    UIButton *btnGreen = [self dotBtn:[UIColor systemGreenColor] sel:@selector(onLayout)];
    UIButton *btnRed = [self dotBtn:[UIColor systemRedColor] sel:@selector(onClose)];

    UIStackView *dots = [[UIStackView alloc] initWithArrangedSubviews:@[btnYellow, btnGreen, btnRed]];
    dots.spacing = 6;
    dots.translatesAutoresizingMaskIntoConstraints = NO;

    [topBar addSubview:self.iconView];
    [topBar addSubview:self.titleLabel];
    [topBar addSubview:chev];
    [topBar addSubview:dots];

    UITapGestureRecognizer *tapTitle = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTitle)];
    [topBar addGestureRecognizer:tapTitle];

    // 2. Thanh tab chuyen nhanh app da mo trong o (giong Googl... | YouT... | VIET...)
    UIScrollView *tabStrip = [[UIScrollView alloc] init];
    tabStrip.backgroundColor = [UIColor systemBackgroundColor];
    tabStrip.showsHorizontalScrollIndicator = NO;
    tabStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:tabStrip];

    self.recentTabsStack = [[UIStackView alloc] init];
    self.recentTabsStack.axis = UILayoutConstraintAxisHorizontal;
    self.recentTabsStack.spacing = 6;
    self.recentTabsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [tabStrip addSubview:self.recentTabsStack];

    // 3. Khung noi dung chinh (nhung Scene app that hoac WebView)
    self.contentHostView = [[UIView alloc] init];
    self.contentHostView.backgroundColor = [UIColor blackColor];
    self.contentHostView.clipsToBounds = YES;
    self.contentHostView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.contentHostView];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentHostView addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:30],

        [self.iconView.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:8],
        [self.iconView.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:17],
        [self.iconView.heightAnchor constraintEqualToConstant:17],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:6],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [self.titleLabel.widthAnchor constraintLessThanOrEqualToConstant:85],

        [chev.leadingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor constant:3],
        [chev.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [chev.widthAnchor constraintEqualToConstant:10],
        [chev.heightAnchor constraintEqualToConstant:10],

        [dots.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-8],
        [dots.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],

        [tabStrip.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [tabStrip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [tabStrip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [tabStrip.heightAnchor constraintEqualToConstant:26],

        [self.recentTabsStack.leadingAnchor constraintEqualToAnchor:tabStrip.leadingAnchor constant:6],
        [self.recentTabsStack.trailingAnchor constraintEqualToAnchor:tabStrip.trailingAnchor constant:-6],
        [self.recentTabsStack.centerYAnchor constraintEqualToAnchor:tabStrip.centerYAnchor],

        [self.contentHostView.topAnchor constraintEqualToAnchor:tabStrip.bottomAnchor],
        [self.contentHostView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentHostView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.contentHostView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.webView.topAnchor constraintEqualToAnchor:self.contentHostView.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.contentHostView.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.contentHostView.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.contentHostView.bottomAnchor]
    ]];
}

- (UIButton *)dotBtn:(UIColor *)color sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = color;
    b.layer.cornerRadius = 5.5;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:11].active = YES;
    [b.heightAnchor constraintEqualToConstant:11].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)hostApplication:(InstalledAppItem *)app {
    if (!app) return;
    self.currentApp = app;
    self.titleLabel.text = app.name;
    self.iconView.image = app.icon;

    // Cap nhat danh sach tab mo nhanh
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"bundleID != %@", app.bundleID];
    [self.recentApps filterUsingPredicate:pred];
    [self.recentApps insertObject:app atIndex:0];
    if (self.recentApps.count > 4) [self.recentApps removeLastObject];
    [self rebuildRecentTabs];

    // Thu nhung Scene ung dung that qua FrontBoard neu he thong cho phep
    BOOL embeddedNativeScene = [self tryEmbedNativeSceneForBundleID:app.bundleID];
    if (!embeddedNativeScene) {
        self.webView.hidden = NO;
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:app.fallbackURL]]];
    }
}

- (BOOL)tryEmbedNativeSceneForBundleID:(NSString *)bundleID {
    dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard", RTLD_LAZY);
    Class fbSceneMgrClass = NSClassFromString(@"FBSceneManager");
    if (!fbSceneMgrClass || ![fbSceneMgrClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }

    id sceneMgr = [fbSceneMgrClass sharedInstance];
    if (![sceneMgr respondsToSelector:@selector(scenes)]) return NO;

    NSSet *scenes = [sceneMgr scenes];
    for (id scene in scenes) {
        NSString *ident = [scene valueForKey:@"identifier"];
        if ([ident containsString:bundleID]) {
            id presMgr = [scene uiPresentationManager];
            if ([presMgr respondsToSelector:@selector(createPresenterWithIdentifier:)]) {
                NSString *presID = [NSString stringWithFormat:@"XemYouTube-Slot%ld", (long)self.slotIndex];
                id presenter = [presMgr createPresenterWithIdentifier:presID];
                if ([presenter respondsToSelector:@selector(activate)]) {
                    [presenter activate];
                    UIView *hostView = [presenter presentationView];
                    if (hostView) {
                        for (UIView *sub in self.contentHostView.subviews) {
                            if (sub != self.webView) [sub removeFromSuperview];
                        }
                        self.webView.hidden = YES;
                        hostView.frame = self.contentHostView.bounds;
                        hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                        [self.contentHostView addSubview:hostView];
                        self.activeScenePresenter = presenter;
                        return YES;
                    }
                }
            }
        }
    }
    return NO;
}

- (void)rebuildRecentTabs {
    for (UIView *v in self.recentTabsStack.arrangedSubviews) {
        [self.recentTabsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSInteger i = 0; i < self.recentApps.count; i++) {
        InstalledAppItem *item = self.recentApps[i];
        UIButton *tabBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        tabBtn.tag = i;
        [tabBtn setTitle:[NSString stringWithFormat:@" %@", item.name] forState:UIControlStateNormal];
        [tabBtn setImage:[self resizeIcon:item.icon size:CGSizeMake(13, 13)] forState:UIControlStateNormal];
        tabBtn.tintColor = [UIColor labelColor];
        tabBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:(i == 0 ? UIFontWeightBold : UIFontWeightRegular)];
        tabBtn.backgroundColor = (i == 0) ? [UIColor secondarySystemBackgroundColor] : [UIColor clearColor];
        tabBtn.layer.cornerRadius = 6;
        tabBtn.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
        [tabBtn addTarget:self action:@selector(recentTabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.recentTabsStack addArrangedSubview:tabBtn];
    }
}

- (UIImage *)resizeIcon:(UIImage *)img size:(CGSize)sz {
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0.0);
    [img drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
    UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [res imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)recentTabTapped:(UIButton *)sender {
    if (sender.tag >= 0 && sender.tag < self.recentApps.count) {
        [self hostApplication:self.recentApps[sender.tag]];
    }
}

- (void)onTitle { [self.delegate windowPaneDidTapTitle:self]; }
- (void)onLayout { [self.delegate windowPaneDidTapLayout:self]; }
- (void)onClose { [self.delegate windowPaneDidTapClose:self]; }

@end

#pragma mark - Hop Thoai "Chia man hinh" (6 Bo cuc + Mo nhanh + Thoat)

typedef NS_ENUM(NSInteger, SplitLayoutMode) {
    SplitLayoutSingle = 0,     // 1 o toan man hinh
    SplitLayoutDual = 1,       // 2 o doc
    SplitLayoutTriple = 2,     // 3 o doc
    SplitLayoutQuad = 3,       // 4 o doc
    SplitLayoutGrid3 = 4,      // 1 trai + 2 phai
    SplitLayoutPiP = 5         // 1 lon + 1 noi goc duoi
};

@interface SplitLayoutSheetView : UIView
@property (nonatomic, assign) SplitLayoutMode selectedMode;
@property (nonatomic, copy) void (^onSelectMode)(SplitLayoutMode mode);
@property (nonatomic, copy) void (^onQuickLaunch)(NSString *bundleID);
@property (nonatomic, copy) void (^onDismiss)(void);
- (instancetype)initWithCurrentMode:(SplitLayoutMode)mode;
@end

@implementation SplitLayoutSheetView

- (instancetype)initWithCurrentMode:(SplitLayoutMode)mode {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.selectedMode = mode;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.layer.cornerRadius = 22;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = [UIColor systemGray3Color].CGColor;
        self.clipsToBounds = YES;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"Chia màn hình";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor systemGray2Color];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismissTap) forControlEvents:UIControlEventTouchUpInside];

    // Hang 1: 4 kieu chia (1 o, 2 o, 3 o, 4 o)
    NSArray *row1Icons = @[@"rectangle.fill", @"rectangle.split.2x1.fill", @"rectangle.split.3x1.fill", @"rectangle.grid.2x2.fill"];
    UIStackView *row1 = [[UIStackView alloc] init];
    row1.spacing = 10;
    row1.distribution = UIStackViewDistributionFillEqually;
    row1.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger i = 0; i < 4; i++) {
        [row1 addArrangedSubview:[self layoutCardButtonWithMode:(SplitLayoutMode)i icon:row1Icons[i]]];
    }

    // Hang 2: Luoi 1+2, PiP, nut +
    UIStackView *row2 = [[UIStackView alloc] init];
    row2.spacing = 10;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.translatesAutoresizingMaskIntoConstraints = NO;
    [row2 addArrangedSubview:[self layoutCardButtonWithMode:SplitLayoutGrid3 icon:@"rectangle.leftthird.inset.filled"]];
    [row2 addArrangedSubview:[self layoutCardButtonWithMode:SplitLayoutPiP icon:@"pip.fill"]];
    [row2 addArrangedSubview:[self layoutCardButtonWithMode:SplitLayoutDual icon:@"plus"]];

    UILabel *quickLbl = [[UILabel alloc] init];
    quickLbl.text = @"MỞ NHANH";
    quickLbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    quickLbl.textColor = [UIColor secondaryLabelColor];
    quickLbl.textAlignment = NSTextAlignmentCenter;
    quickLbl.translatesAutoresizingMaskIntoConstraints = NO;

    // Khung vien net dut MO NHANH
    UIView *quickBox = [[UIView alloc] init];
    quickBox.layer.cornerRadius = 18;
    quickBox.layer.borderWidth = 1.5;
    quickBox.layer.borderColor = [UIColor systemBlueColor].CGColor;
    quickBox.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *qDual = [self quickAppBtnWithIcon:[UIImage systemImageNamed:@"rectangle.split.2x1.fill"] tag:0];
    UIImage *ytIcon = [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)] ?
        [UIImage _applicationIconImageForBundleIdentifier:@"com.google.ios.youtube" format:2 scale:2.0] : [UIImage systemImageNamed:@"play.rectangle.fill"];
    UIImage *vmIcon = [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)] ?
        [UIImage _applicationIconImageForBundleIdentifier:@"vn.vietmap.live" format:2 scale:2.0] : [UIImage systemImageNamed:@"map.fill"];

    UIButton *qYT = [self quickAppBtnWithIcon:[ytIcon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] tag:1];
    UIButton *qVM = [self quickAppBtnWithIcon:[vmIcon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] tag:2];

    UIStackView *qStack = [[UIStackView alloc] initWithArrangedSubviews:@[qDual, qYT, qVM]];
    qStack.spacing = 12;
    qStack.translatesAutoresizingMaskIntoConstraints = NO;
    [quickBox addSubview:qStack];

    UIButton *exitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [exitBtn setTitle:@"Thoát XemYouTube" forState:UIControlStateNormal];
    [exitBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    exitBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    exitBtn.backgroundColor = [UIColor systemGray6Color];
    exitBtn.layer.cornerRadius = 12;
    exitBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [exitBtn addTarget:self action:@selector(exitAppTap) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:title];
    [self addSubview:closeBtn];
    [self addSubview:row1];
    [self addSubview:row2];
    [self addSubview:quickLbl];
    [self addSubview:quickBox];
    [self addSubview:exitBtn];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

        [closeBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [closeBtn.widthAnchor constraintEqualToConstant:28],
        [closeBtn.heightAnchor constraintEqualToConstant:28],

        [row1.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [row1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row1.heightAnchor constraintEqualToConstant:48],

        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:10],
        [row2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:42],
        [row2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-42],
        [row2.heightAnchor constraintEqualToConstant:48],

        [quickLbl.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:18],
        [quickLbl.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

        [quickBox.topAnchor constraintEqualToAnchor:quickLbl.bottomAnchor constant:8],
        [quickBox.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [quickBox.heightAnchor constraintEqualToConstant:46],
        [quickBox.widthAnchor constraintEqualToConstant:168],

        [qStack.centerXAnchor constraintEqualToAnchor:quickBox.centerXAnchor],
        [qStack.centerYAnchor constraintEqualToAnchor:quickBox.centerYAnchor],

        [exitBtn.topAnchor constraintEqualToAnchor:quickBox.bottomAnchor constant:18],
        [exitBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [exitBtn.widthAnchor constraintEqualToConstant:170],
        [exitBtn.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (UIButton *)layoutCardButtonWithMode:(SplitLayoutMode)mode icon:(NSString *)iconName {
    BOOL isSelected = (self.selectedMode == mode);
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = mode;
    [btn setImage:[UIImage systemImageNamed:iconName] forState:UIControlStateNormal];
    btn.tintColor = isSelected ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    btn.backgroundColor = isSelected ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.15] : [UIColor systemGray6Color];
    btn.layer.cornerRadius = 12;
    if (isSelected) {
        btn.layer.borderWidth = 2.0;
        btn.layer.borderColor = [UIColor systemBlueColor].CGColor;
    }
    [btn addTarget:self action:@selector(modeTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIButton *)quickAppBtnWithIcon:(UIImage *)img tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    [b setImage:img forState:UIControlStateNormal];
    b.layer.cornerRadius = 8;
    b.clipsToBounds = YES;
    [b.widthAnchor constraintEqualToConstant:30].active = YES;
    [b.heightAnchor constraintEqualToConstant:30].active = YES;
    [b addTarget:self action:@selector(quickTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)modeTapped:(UIButton *)sender {
    if (self.onSelectMode) self.onSelectMode((SplitLayoutMode)sender.tag);
}

- (void)quickTapped:(UIButton *)sender {
    if (sender.tag == 0 && self.onSelectMode) {
        self.onSelectMode(SplitLayoutDual);
    } else if (sender.tag == 1 && self.onQuickLaunch) {
        self.onQuickLaunch(@"com.google.ios.youtube");
    } else if (sender.tag == 2 && self.onQuickLaunch) {
        self.onQuickLaunch(@"vn.vietmap.live");
    }
}

- (void)dismissTap { if (self.onDismiss) self.onDismiss(); }
- (void)exitAppTap { exit(0); }

@end

#pragma mark - Luoi Chon App Tren Dien Thoai ("Chon app o 1")

@interface AppPickerGridView : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@property (nonatomic, copy) void (^onPick)(InstalledAppItem *app);
@property (nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<InstalledAppItem *> *)apps;
@end

@implementation AppPickerGridView

- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<InstalledAppItem *> *)apps {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.titleText = title;
        self.apps = apps;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.layer.cornerRadius = 20;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = [UIColor systemGray3Color].CGColor;
        self.clipsToBounds = YES;
        [self setup];
    }
    return self;
}

- (void)setup {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = self.titleText;
    lbl.font = [UIFont boldSystemFontOfSize:16];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [UIColor secondaryLabelColor];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 4;
    layout.sectionInset = UIEdgeInsetsMake(8, 10, 14, 10);

    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    cv.backgroundColor = [UIColor clearColor];
    cv.dataSource = self;
    cv.delegate = self;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
    cv.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:lbl];
    [self addSubview:close];
    [self addSubview:cv];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [lbl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [close.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [cv.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:6],
        [cv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [cv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [cv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)closeTap { if (self.onClose) self.onClose(); }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.apps.count; }

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    InstalledAppItem *app = self.apps[ip.item];

    UIImageView *iv = [[UIImageView alloc] initWithImage:app.icon];
    iv.layer.cornerRadius = 12;
    iv.clipsToBounds = YES;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *t = [[UILabel alloc] init];
    t.text = app.name;
    t.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    t.textAlignment = NSTextAlignmentCenter;
    t.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:iv];
    [cell.contentView addSubview:t];
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:2],
        [iv.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [iv.widthAnchor constraintEqualToConstant:46],
        [iv.heightAnchor constraintEqualToConstant:46],
        [t.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4],
        [t.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:2],
        [t.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-2]
    ]];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat w = floor((cv.bounds.size.width - 40) / 5.0);
    return CGSizeMake(MAX(w, 50), 68);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.onPick) self.onPick(self.apps[ip.item]);
}
@end

#pragma mark - Man Hinh Chinh "Mo phong" & "Tren xe"

@interface MultiWindowWorkspaceViewController : UIViewController <AppWindowPaneDelegate, CLLocationManagerDelegate>
@property (nonatomic, assign) BOOL isCarScreen;
@property (nonatomic, assign) SplitLayoutMode layoutMode;
@property (nonatomic, strong) UIView *stageContainer;
@property (nonatomic, strong) NSMutableArray<AppWindowPane *> *panes;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong) NSLayoutConstraint *pane0WidthConstraint;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) UIView *activeModalOverlay;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *allApps;

// Widget HUD goc duoi o 1 (Gio + Pin + Toc do + Bien bao 50)
@property (nonatomic, strong) UIView *hudCard;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@end

@implementation MultiWindowWorkspaceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.allApps = GetInstalledApps();
    self.layoutMode = SplitLayoutDual;
    self.splitRatio = 0.5;
    self.panes = [NSMutableArray array];

    UILabel *headerTitle = [[UILabel alloc] init];
    headerTitle.text = self.isCarScreen ? @"Trên xe" : @"Mô phỏng";
    headerTitle.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headerTitle];

    UIButton *layoutBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [layoutBtn setImage:[UIImage systemImageNamed:@"rectangle.split.2x1.fill"] forState:UIControlStateNormal];
    layoutBtn.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    layoutBtn.layer.cornerRadius = 10;
    layoutBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [layoutBtn addTarget:self action:@selector(openLayoutSheet) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:layoutBtn];

    self.stageContainer = [[UIView alloc] init];
    self.stageContainer.backgroundColor = [UIColor systemBackgroundColor];
    self.stageContainer.layer.cornerRadius = 20;
    self.stageContainer.layer.borderWidth = 2.0;
    self.stageContainer.layer.borderColor = [UIColor systemGray3Color].CGColor;
    self.stageContainer.clipsToBounds = YES;
    self.stageContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stageContainer];

    [NSLayoutConstraint activateConstraints:@[
        [headerTitle.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [headerTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],

        [layoutBtn.centerYAnchor constraintEqualToAnchor:headerTitle.centerYAnchor],
        [layoutBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [layoutBtn.widthAnchor constraintEqualToConstant:40],
        [layoutBtn.heightAnchor constraintEqualToConstant:32],

        [self.stageContainer.topAnchor constraintEqualToAnchor:headerTitle.bottomAnchor constant:12],
        [self.stageContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.stageContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.stageContainer.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.55]
    ]];

    for (NSInteger i = 1; i <= 4; i++) {
        AppWindowPane *p = [[AppWindowPane alloc] initWithSlotIndex:i];
        p.delegate = self;
        p.translatesAutoresizingMaskIntoConstraints = NO;
        [self.panes addObject:p];
    }

    self.dividerView = [[UIView alloc] init];
    self.dividerView.backgroundColor = [UIColor systemGray5Color];
    self.dividerView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *grip = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    grip.tintColor = [UIColor systemGrayColor];
    grip.transform = CGAffineTransformMakeRotation(M_PI_2);
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dividerView addSubview:grip];
    [NSLayoutConstraint activateConstraints:@[
        [grip.centerXAnchor constraintEqualToAnchor:self.dividerView.centerXAnchor],
        [grip.centerYAnchor constraintEqualToAnchor:self.dividerView.centerYAnchor],
        [grip.widthAnchor constraintEqualToConstant:14],
        [grip.heightAnchor constraintEqualToConstant:14]
    ]];
    [self.dividerView addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanDivider:)]];

    [self applySplitLayout:SplitLayoutDual];
    [self setupHUD];
    [self assignInitialApps];
}

- (void)assignInitialApps {
    InstalledAppItem *yt = [self appByBundle:@"com.google.ios.youtube"] ?: self.allApps.firstObject;
    InstalledAppItem *vm = [self appByBundle:@"vn.vietmap.live"] ?: (self.allApps.count > 1 ? self.allApps[1] : yt);
    InstalledAppItem *gm = [self appByBundle:@"com.google.Maps"] ?: yt;
    InstalledAppItem *zm = [self appByBundle:@"com.zing.mp3"] ?: vm;

    [self.panes[0] hostApplication:yt];
    [self.panes[1] hostApplication:vm];
    [self.panes[2] hostApplication:gm];
    [self.panes[3] hostApplication:zm];
}

- (InstalledAppItem *)appByBundle:(NSString *)bid {
    for (InstalledAppItem *item in self.allApps) {
        if ([item.bundleID isEqualToString:bid]) return item;
    }
    return nil;
}

- (void)applySplitLayout:(SplitLayoutMode)mode {
    self.layoutMode = mode;
    for (UIView *sub in self.stageContainer.subviews) {
        if (sub != self.hudCard) [sub removeFromSuperview];
    }

    AppWindowPane *p0 = self.panes[0];
    AppWindowPane *p1 = self.panes[1];
    AppWindowPane *p2 = self.panes[2];
    AppWindowPane *p3 = self.panes[3];

    if (mode == SplitLayoutSingle) {
        [self.stageContainer addSubview:p0];
        [NSLayoutConstraint activateConstraints:@[
            [p0.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p0.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [p0.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
            [p0.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor]
        ]];
    } else if (mode == SplitLayoutDual) {
        [self.stageContainer addSubview:p0];
        [self.stageContainer addSubview:self.dividerView];
        [self.stageContainer addSubview:p1];
        self.pane0WidthConstraint = [p0.widthAnchor constraintEqualToAnchor:self.stageContainer.widthAnchor multiplier:self.splitRatio constant:-6];
        [NSLayoutConstraint activateConstraints:@[
            [p0.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p0.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [p0.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
            self.pane0WidthConstraint,

            [self.dividerView.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [self.dividerView.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [self.dividerView.leadingAnchor constraintEqualToAnchor:p0.trailingAnchor],
            [self.dividerView.widthAnchor constraintEqualToConstant:12],

            [p1.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p1.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:self.dividerView.trailingAnchor],
            [p1.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor]
        ]];
    } else if (mode == SplitLayoutTriple || mode == SplitLayoutQuad) {
        NSInteger count = (mode == SplitLayoutTriple) ? 3 : 4;
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.spacing = 2;
        stack.backgroundColor = [UIColor systemGray4Color];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSInteger i = 0; i < count; i++) [stack addArrangedSubview:self.panes[i]];
        [self.stageContainer addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor]
        ]];
    } else if (mode == SplitLayoutGrid3) {
        [self.stageContainer addSubview:p0];
        [self.stageContainer addSubview:p1];
        [self.stageContainer addSubview:p2];
        [NSLayoutConstraint activateConstraints:@[
            [p0.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p0.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [p0.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
            [p0.widthAnchor constraintEqualToAnchor:self.stageContainer.widthAnchor multiplier:0.5],

            [p1.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p1.leadingAnchor constraintEqualToAnchor:p0.trailingAnchor constant:2],
            [p1.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor],
            [p1.heightAnchor constraintEqualToAnchor:self.stageContainer.heightAnchor multiplier:0.5],

            [p2.topAnchor constraintEqualToAnchor:p1.bottomAnchor constant:2],
            [p2.leadingAnchor constraintEqualToAnchor:p0.trailingAnchor constant:2],
            [p2.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor],
            [p2.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor]
        ]];
    } else if (mode == SplitLayoutPiP) {
        [self.stageContainer addSubview:p0];
        p1.layer.cornerRadius = 14;
        p1.layer.borderWidth = 1.5;
        p1.layer.borderColor = [UIColor systemGray3Color].CGColor;
        [self.stageContainer addSubview:p1];
        [NSLayoutConstraint activateConstraints:@[
            [p0.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
            [p0.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor],
            [p0.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
            [p0.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor],

            [p1.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor constant:-12],
            [p1.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor constant:-16],
            [p1.widthAnchor constraintEqualToAnchor:self.stageContainer.widthAnchor multiplier:0.46],
            [p1.heightAnchor constraintEqualToAnchor:self.stageContainer.heightAnchor multiplier:0.45]
        ]];
    }

    if (self.hudCard) {
        [self.stageContainer bringSubviewToFront:self.hudCard];
    }
}

- (void)setupHUD {
    self.hudCard = [[UIView alloc] init];
    self.hudCard.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.95];
    self.hudCard.layer.cornerRadius = 16;
    self.hudCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.hudCard.layer.shadowOpacity = 0.16;
    self.hudCard.layer.shadowRadius = 6;
    self.hudCard.layer.shadowOffset = CGSizeMake(0, 2);
    self.hudCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.batteryLabel = [[UILabel alloc] init];
    self.batteryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.batteryLabel.textAlignment = NSTextAlignmentRight;
    self.batteryLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.text = @"0";
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightBold];
    self.speedLabel.textAlignment = NSTextAlignmentCenter;
    self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *unitLbl = [[UILabel alloc] init];
    unitLbl.text = @"km/h";
    unitLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    unitLbl.textColor = [UIColor secondaryLabelColor];
    unitLbl.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *sign = [[UIView alloc] init];
    sign.backgroundColor = [UIColor whiteColor];
    sign.layer.cornerRadius = 21;
    sign.layer.borderWidth = 4.0;
    sign.layer.borderColor = [UIColor systemRedColor].CGColor;
    sign.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *signNum = [[UILabel alloc] init];
    signNum.text = @"50";
    signNum.textColor = [UIColor blackColor];
    signNum.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
    signNum.translatesAutoresizingMaskIntoConstraints = NO;
    [sign addSubview:signNum];

    [self.hudCard addSubview:self.timeLabel];
    [self.hudCard addSubview:self.batteryLabel];
    [self.hudCard addSubview:self.speedLabel];
    [self.hudCard addSubview:unitLbl];
    [self.hudCard addSubview:sign];
    [self.stageContainer addSubview:self.hudCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.hudCard.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor constant:10],
        [self.hudCard.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor constant:-18],
        [self.hudCard.widthAnchor constraintEqualToConstant:118],
        [self.hudCard.heightAnchor constraintEqualToConstant:78],

        [self.timeLabel.topAnchor constraintEqualToAnchor:self.hudCard.topAnchor constant:6],
        [self.timeLabel.leadingAnchor constraintEqualToAnchor:self.hudCard.leadingAnchor constant:10],
        [self.batteryLabel.topAnchor constraintEqualToAnchor:self.hudCard.topAnchor constant:6],
        [self.batteryLabel.trailingAnchor constraintEqualToAnchor:self.hudCard.trailingAnchor constant:-10],

        [self.speedLabel.topAnchor constraintEqualToAnchor:self.timeLabel.bottomAnchor constant:2],
        [self.speedLabel.leadingAnchor constraintEqualToAnchor:self.hudCard.leadingAnchor constant:8],
        [self.speedLabel.widthAnchor constraintEqualToConstant:48],
        [unitLbl.topAnchor constraintEqualToAnchor:self.speedLabel.bottomAnchor constant:-2],
        [unitLbl.centerXAnchor constraintEqualToAnchor:self.speedLabel.centerXAnchor],

        [sign.trailingAnchor constraintEqualToAnchor:self.hudCard.trailingAnchor constant:-10],
        [sign.bottomAnchor constraintEqualToAnchor:self.hudCard.bottomAnchor constant:-10],
        [sign.widthAnchor constraintEqualToConstant:42],
        [sign.heightAnchor constraintEqualToConstant:42],
        [signNum.centerXAnchor constraintEqualToAnchor:sign.centerXAnchor],
        [signNum.centerYAnchor constraintEqualToAnchor:sign.centerYAnchor]
    ]];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    self.timeLabel.text = [fmt stringFromDate:[NSDate date]];
    float bat = [UIDevice currentDevice].batteryLevel;
    self.batteryLabel.text = [NSString stringWithFormat:@"%d%%", (bat >= 0) ? (int)round(bat * 100) : 95];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)onPanDivider:(UIPanGestureRecognizer *)pan {
    if (self.layoutMode != SplitLayoutDual) return;
    CGPoint pt = [pan locationInView:self.stageContainer];
    CGFloat ratio = MIN(MAX(pt.x / MAX(self.stageContainer.bounds.size.width, 1.0), 0.25), 0.75);
    self.splitRatio = ratio;
    self.pane0WidthConstraint.active = NO;
    self.pane0WidthConstraint = [self.panes[0].widthAnchor constraintEqualToAnchor:self.stageContainer.widthAnchor multiplier:ratio constant:-6];
    self.pane0WidthConstraint.active = YES;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (loc && loc.speed >= 0) {
        self.speedLabel.text = [NSString stringWithFormat:@"%d", (int)round(loc.speed * 3.6)];
    }
}

#pragma mark - AppWindowPaneDelegate & Modals

- (void)presentOverlayCard:(UIView *)card {
    [self.activeModalOverlay removeFromSuperview];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.stageContainer.topAnchor],
        [card.leadingAnchor constraintEqualToAnchor:self.stageContainer.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.stageContainer.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.stageContainer.bottomAnchor]
    ]];
    self.activeModalOverlay = card;
}

- (void)windowPaneDidTapTitle:(AppWindowPane *)pane {
    self.allApps = GetInstalledApps();
    NSString *title = [NSString stringWithFormat:@"Chọn app ô %ld", (long)pane.slotIndex];
    AppPickerGridView *picker = [[AppPickerGridView alloc] initWithTitle:title apps:self.allApps];
    __weak typeof(self) weakSelf = self;
    picker.onClose = ^{
        [weakSelf.activeModalOverlay removeFromSuperview];
        weakSelf.activeModalOverlay = nil;
    };
    picker.onPick = ^(InstalledAppItem *app) {
        [pane hostApplication:app];
        [weakSelf.activeModalOverlay removeFromSuperview];
        weakSelf.activeModalOverlay = nil;
    };
    [self presentOverlayCard:picker];
}

- (void)windowPaneDidTapLayout:(AppWindowPane *)pane {
    [self openLayoutSheet];
}

- (void)windowPaneDidTapClose:(AppWindowPane *)pane {
    [self windowPaneDidTapTitle:pane];
}

- (void)openLayoutSheet {
    SplitLayoutSheetView *sheet = [[SplitLayoutSheetView alloc] initWithCurrentMode:self.layoutMode];
    __weak typeof(self) weakSelf = self;
    sheet.onDismiss = ^{
        [weakSelf.activeModalOverlay removeFromSuperview];
        weakSelf.activeModalOverlay = nil;
    };
    sheet.onSelectMode = ^(SplitLayoutMode mode) {
        [weakSelf applySplitLayout:mode];
        [weakSelf.activeModalOverlay removeFromSuperview];
        weakSelf.activeModalOverlay = nil;
    };
    sheet.onQuickLaunch = ^(NSString *bundleID) {
        InstalledAppItem *app = [weakSelf appByBundle:bundleID];
        if (app) [weakSelf.panes[0] hostApplication:app];
        [weakSelf.activeModalOverlay removeFromSuperview];
        weakSelf.activeModalOverlay = nil;
    };
    [self presentOverlayCard:sheet];
}

@end

#pragma mark - Tab 1 & Tab 4

@interface HomeListController : UITableViewController
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@end

@implementation HomeListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trang chủ";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.apps = GetInstalledApps();
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.apps.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    InstalledAppItem *a = self.apps[ip.row];
    cell.textLabel.text = a.name;
    cell.detailTextLabel.text = a.bundleID;
    cell.imageView.image = a.icon;
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    self.tabBarController.selectedIndex = 2;
}
@end

@interface AccountSettingsController : UITableViewController
@end

@implementation AccountSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tài khoản";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (ip.row == 0) {
        cell.textLabel.text = @"Phiên bản";
        cell.detailTextLabel.text = @"2.1.6 (Full Split & Scene Host)";
    } else {
        cell.textLabel.text = @"Ứng dụng đã quét trên máy";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu app", (unsigned long)GetInstalledApps().count];
    }
    return cell;
}
@end

#pragma mark - MainTabBar & Scene Delegates

@interface MainTabBarController : UITabBarController
@end

@implementation MainTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.tintColor = [UIColor systemBlueColor];

    UINavigationController *t1 = [[UINavigationController alloc] initWithRootViewController:[[HomeListController alloc] init]];
    t1.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chủ" image:[UIImage systemImageNamed:@"house"] selectedImage:[UIImage systemImageNamed:@"house.fill"]];

    MultiWindowWorkspaceViewController *t2 = [[MultiWindowWorkspaceViewController alloc] init];
    t2.isCarScreen = YES;
    t2.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trên xe" image:[UIImage systemImageNamed:@"car"] selectedImage:[UIImage systemImageNamed:@"car.fill"]];

    MultiWindowWorkspaceViewController *t3 = [[MultiWindowWorkspaceViewController alloc] init];
    t3.isCarScreen = NO;
    t3.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Mô phỏng" image:[UIImage systemImageNamed:@"play.rectangle"] selectedImage:[UIImage systemImageNamed:@"play.rectangle.fill"]];

    UINavigationController *t4 = [[UINavigationController alloc] initWithRootViewController:[[AccountSettingsController alloc] init]];
    t4.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Tài khoản" image:[UIImage systemImageNamed:@"person.crop.circle"] selectedImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];

    self.viewControllers = @[t1, t2, t3, t4];
    self.selectedIndex = 2;
}
@end

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property (nonatomic, strong) CPWindow *carWindow;
@end

@implementation CarPlaySceneDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)s didConnectInterfaceController:(CPInterfaceController *)ic toWindow:(CPWindow *)window {
    self.carWindow = window;
    MultiWindowWorkspaceViewController *vc = [[MultiWindowWorkspaceViewController alloc] init];
    vc.isCarScreen = YES;
    window.rootViewController = vc;
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
    self.window.rootViewController = [[MainTabBarController alloc] init];
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
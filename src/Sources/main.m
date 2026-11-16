#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Private API Interfaces (Quet danh sach app & lay icon that tren iOS)

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@property (nonatomic, readonly) NSArray<NSString *> *appTags;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (PrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - Model App tren dien thoai

@interface InstalledAppItem : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *fallbackURL;
@end

@implementation InstalledAppItem
@end

static NSString *FallbackWebURLForBundle(NSString *bundleID, NSString *name) {
    NSString *lower = [bundleID.lowercaseString stringByAppendingFormat:@" %@", name.lowercaseString];
    if ([lower containsString:@"youtube"]) return @"https://m.youtube.com";
    if ([lower containsString:@"vietmap"]) return @"https://maps.vietmap.vn";
    if ([lower containsString:@"maps"] || [lower containsString:@"google"]) return @"https://www.google.com/maps";
    if ([lower containsString:@"zing"]) return @"https://zingmp3.vn";
    if ([lower containsString:@"spotify"]) return @"https://open.spotify.com";
    if ([lower containsString:@"tiktok"]) return @"https://www.tiktok.com";
    if ([lower containsString:@"zalo"]) return @"https://chat.zalo.me";
    if ([lower containsString:@"telegram"]) return @"https://web.telegram.org";
    if ([lower containsString:@"vtv"]) return @"https://vtvgo.vn";
    return @"https://www.google.com";
}

static NSArray<InstalledAppItem *> *FetchInstalledUserApps(void) {
    NSMutableArray<InstalledAppItem *> *result = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass) {
        id workspace = [wsClass defaultWorkspace];
        NSArray *apps = [workspace allInstalledApplications];
        NSSet *allowedSystemIDs = [NSSet setWithArray:@[
            @"com.apple.Maps", @"com.apple.Music", @"com.apple.mobilesafari",
            @"com.apple.weather", @"com.apple.podcasts", @"com.apple.mobilemail"
        ]];

        for (id proxy in apps) {
            NSString *bundleID = [proxy valueForKey:@"applicationIdentifier"];
            NSString *appType = [proxy valueForKey:@"applicationType"];
            NSString *name = [proxy valueForKey:@"localizedName"];
            if (!bundleID || !name || name.length == 0) continue;
            if ([bundleID isEqualToString:@"com.xemyoutube"]) continue;

            BOOL isUserApp = [appType isEqualToString:@"User"];
            BOOL isAllowedSys = [allowedSystemIDs containsObject:bundleID];
            if (!isUserApp && !isAllowedSys) continue;

            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = bundleID;
            item.name = name;
            item.fallbackURL = FallbackWebURLForBundle(bundleID, name);

            if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
                item.icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
            }
            if (!item.icon) {
                item.icon = [UIImage systemImageNamed:@"app.fill"];
            }
            [result addObject:item];
        }
    }

    [result sortUsingComparator:^NSComparisonResult(InstalledAppItem *a, InstalledAppItem *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    if (result.count == 0) {
        NSArray *defaults = @[
            @[@"com.google.ios.youtube", @"YouTube", @"play.rectangle.fill", @"https://m.youtube.com"],
            @[@"vn.vietmap.live", @"VIETMAP Live", @"map.fill", @"https://maps.vietmap.vn"],
            @[@"com.google.Maps", @"Google Maps", @"location.fill", @"https://www.google.com/maps"],
            @[@"com.zing.mp3", @"Zing MP3", @"music.note", @"https://zingmp3.vn"],
            @[@"com.apple.mobilesafari", @"Safari", @"safari.fill", @"https://www.google.com"]
        ];
        for (NSArray *d in defaults) {
            InstalledAppItem *item = [[InstalledAppItem alloc] init];
            item.bundleID = d[0];
            item.name = d[1];
            item.icon = [UIImage systemImageNamed:d[2]];
            item.fallbackURL = d[3];
            [result addObject:item];
        }
    }
    return result;
}

#pragma mark - Khung Hien Thi 1 O Ung Dung (PaneView: Thanh tieu de 3 cham + WebView/App Launcher)

@class AppPaneView;
@protocol AppPaneViewDelegate <NSObject>
- (void)paneViewDidRequestSelectApp:(AppPaneView *)paneView;
- (void)paneViewDidRequestExpand:(AppPaneView *)paneView;
- (void)paneViewDidRequestReload:(AppPaneView *)paneView;
@end

@interface AppPaneView : UIView
@property (nonatomic, assign) NSInteger paneIndex; // 1 hoac 2
@property (nonatomic, weak) id<AppPaneViewDelegate> delegate;
@property (nonatomic, strong) UIImageView *appIconView;
@property (nonatomic, strong) UILabel *appTitleLabel;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *currentBundleID;
@property (nonatomic, copy) NSString *currentAppName;
- (void)loadAppWithBundleID:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon url:(NSString *)urlStr;
@end

@implementation AppPaneView

- (instancetype)initWithPaneIndex:(NSInteger)index {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.paneIndex = index;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.clipsToBounds = YES;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor secondarySystemBackgroundColor];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:header];

    self.appIconView = [[UIImageView alloc] init];
    self.appIconView.layer.cornerRadius = 5;
    self.appIconView.clipsToBounds = YES;
    self.appIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.appIconView.translatesAutoresizingMaskIntoConstraints = NO;

    self.appTitleLabel = [[UILabel alloc] init];
    self.appTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.appTitleLabel.textColor = [UIColor labelColor];
    self.appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *selectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [selectBtn setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    selectBtn.tintColor = [UIColor secondaryLabelColor];
    selectBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [selectBtn addTarget:self action:@selector(onSelectTap) forControlEvents:UIControlEventTouchUpInside];

    // 3 nut tron kieu thanh cua so (Vang = Doi app, Xanh = Mo app that, Do = Tai lai)
    UIButton *yellowDot = [self makeDotButtonWithColor:[UIColor systemYellowColor] action:@selector(onSelectTap)];
    UIButton *greenDot = [self makeDotButtonWithColor:[UIColor systemGreenColor] action:@selector(onExpandTap)];
    UIButton *redDot = [self makeDotButtonWithColor:[UIColor systemRedColor] action:@selector(onReloadTap)];

    UIStackView *dots = [[UIStackView alloc] initWithArrangedSubviews:@[yellowDot, greenDot, redDot]];
    dots.axis = UILayoutConstraintAxisHorizontal;
    dots.spacing = 6;
    dots.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:self.appIconView];
    [header addSubview:self.appTitleLabel];
    [header addSubview:selectBtn];
    [header addSubview:dots];

    UITapGestureRecognizer *headerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSelectTap)];
    [header addGestureRecognizer:headerTap];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:32],

        [self.appIconView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:8],
        [self.appIconView.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.appIconView.widthAnchor constraintEqualToConstant:18],
        [self.appIconView.heightAnchor constraintEqualToConstant:18],

        [self.appTitleLabel.leadingAnchor constraintEqualToAnchor:self.appIconView.trailingAnchor constant:6],
        [self.appTitleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.appTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:selectBtn.leadingAnchor constant:-4],

        [selectBtn.leadingAnchor constraintEqualToAnchor:self.appTitleLabel.trailingAnchor constant:2],
        [selectBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [selectBtn.widthAnchor constraintEqualToConstant:16],
        [selectBtn.heightAnchor constraintEqualToConstant:16],

        [dots.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-8],
        [dots.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [self.webView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (UIButton *)makeDotButtonWithColor:(UIColor *)color action:(SEL)sel {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 6;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.widthAnchor constraintEqualToConstant:12].active = YES;
    [btn.heightAnchor constraintEqualToConstant:12].active = YES;
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)loadAppWithBundleID:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon url:(NSString *)urlStr {
    self.currentBundleID = bundleID;
    self.currentAppName = name;
    self.appTitleLabel.text = name;
    self.appIconView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    if (urlStr.length > 0) {
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
    }
}

- (void)onSelectTap { [self.delegate paneViewDidRequestSelectApp:self]; }
- (void)onExpandTap { [self.delegate paneViewDidRequestExpand:self]; }
- (void)onReloadTap { [self.webView reload]; [self.delegate paneViewDidRequestReload:self]; }

@end

#pragma mark - Hop Thoai Luoi Chon App Tren Dien Thoai (Giong het anh "Chon app o 1")

@interface AppPickerOverlayView : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@property (nonatomic, copy) void (^onSelectApp)(InstalledAppItem *app);
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, strong) UICollectionView *collectionView;
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<InstalledAppItem *> *)apps;
@end

@implementation AppPickerOverlayView

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
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.text = self.titleText;
    headerLabel.font = [UIFont boldSystemFontOfSize:16];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor secondaryLabelColor];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 14;
    layout.minimumInteritemSpacing = 6;
    layout.sectionInset = UIEdgeInsetsMake(8, 12, 16, 12);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"AppIconCell"];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:headerLabel];
    [self addSubview:closeBtn];
    [self addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [headerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],

        [closeBtn.centerYAnchor constraintEqualToAnchor:headerLabel.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [closeBtn.widthAnchor constraintEqualToConstant:28],
        [closeBtn.heightAnchor constraintEqualToConstant:28],

        [self.collectionView.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:8],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)closeTapped {
    if (self.onClose) self.onClose();
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.apps.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AppIconCell" forIndexPath:indexPath];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    InstalledAppItem *app = self.apps[indexPath.item];

    UIImageView *iv = [[UIImageView alloc] initWithImage:app.icon];
    iv.layer.cornerRadius = 12;
    iv.clipsToBounds = YES;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = app.name;
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.lineBreakMode = NSLineBreakByTruncatingTail;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:iv];
    [cell.contentView addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:2],
        [iv.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [iv.widthAnchor constraintEqualToConstant:48],
        [iv.heightAnchor constraintEqualToConstant:48],

        [lbl.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:5],
        [lbl.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:2],
        [lbl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-2]
    ]];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = floor((collectionView.bounds.size.width - 48) / 5.0);
    return CGSizeMake(MAX(w, 52), 70);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.onSelectApp) {
        self.onSelectApp(self.apps[indexPath.item]);
    }
}

@end

#pragma mark - Man Hinh Mo Phong & Tren Xe (Chia 2 o + Thanh keo + Widget Toc Do 50)

@interface WorkspaceContainerViewController : UIViewController <AppPaneViewDelegate, CLLocationManagerDelegate>
@property (nonatomic, assign) BOOL isCarMode;
@property (nonatomic, strong) UIView *stageBox;
@property (nonatomic, strong) AppPaneView *pane1;
@property (nonatomic, strong) AppPaneView *pane2;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong) NSLayoutConstraint *pane1WidthConstraint;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) AppPickerOverlayView *pickerOverlay;
@property (nonatomic, strong) NSArray<InstalledAppItem *> *installedApps;

// Widget toc do + bien bao 50 + gio + pin
@property (nonatomic, strong) UIView *hudCard;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSTimer *clockTimer;
@end

@implementation WorkspaceContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.installedApps = FetchInstalledUserApps();
    self.splitRatio = ([[NSUserDefaults standardUserDefaults] floatForKey:@"splitRatio"] > 0.2) ? [[NSUserDefaults standardUserDefaults] floatForKey:@"splitRatio"] : 0.5;

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = self.isCarMode ? @"Trên xe" : @"Mô phỏng";
    titleLbl.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLbl];

    UIButton *pick1Btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [pick1Btn setTitle:@"Ô 1" forState:UIControlStateNormal];
    pick1Btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    pick1Btn.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    pick1Btn.layer.cornerRadius = 10;
    pick1Btn.translatesAutoresizingMaskIntoConstraints = NO;
    [pick1Btn addTarget:self action:@selector(openPickerForPane1) forControlEvents:UIControlEventTouchUpInside];

    UIButton *pick2Btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [pick2Btn setTitle:@"Ô 2" forState:UIControlStateNormal];
    pick2Btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    pick2Btn.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    pick2Btn.layer.cornerRadius = 10;
    pick2Btn.translatesAutoresizingMaskIntoConstraints = NO;
    [pick2Btn addTarget:self action:@selector(openPickerForPane2) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:pick1Btn];
    [self.view addSubview:pick2Btn];

    self.stageBox = [[UIView alloc] init];
    self.stageBox.backgroundColor = [UIColor systemBackgroundColor];
    self.stageBox.layer.cornerRadius = 20;
    self.stageBox.layer.borderWidth = 2.0;
    self.stageBox.layer.borderColor = [UIColor systemGray3Color].CGColor;
    self.stageBox.clipsToBounds = YES;
    self.stageBox.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stageBox];

    [NSLayoutConstraint activateConstraints:@[
        [titleLbl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [titleLbl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],

        [pick2Btn.centerYAnchor constraintEqualToAnchor:titleLbl.centerYAnchor],
        [pick2Btn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [pick2Btn.widthAnchor constraintEqualToConstant:48],
        [pick2Btn.heightAnchor constraintEqualToConstant:30],

        [pick1Btn.centerYAnchor constraintEqualToAnchor:titleLbl.centerYAnchor],
        [pick1Btn.trailingAnchor constraintEqualToAnchor:pick2Btn.leadingAnchor constant:-8],
        [pick1Btn.widthAnchor constraintEqualToConstant:48],
        [pick1Btn.heightAnchor constraintEqualToConstant:30],

        [self.stageBox.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:12],
        [self.stageBox.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.stageBox.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.stageBox.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.54]
    ]];

    [self setupSplitPanes];
    [self setupSpeedHUD];
    [self loadSavedOrDefaultApps];
}

- (void)setupSplitPanes {
    self.pane1 = [[AppPaneView alloc] initWithPaneIndex:1];
    self.pane1.delegate = self;
    self.pane1.translatesAutoresizingMaskIntoConstraints = NO;

    self.pane2 = [[AppPaneView alloc] initWithPaneIndex:2];
    self.pane2.delegate = self;
    self.pane2.translatesAutoresizingMaskIntoConstraints = NO;

    self.dividerView = [[UIView alloc] init];
    self.dividerView.backgroundColor = [UIColor systemGray5Color];
    self.dividerView.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *gripIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    gripIcon.tintColor = [UIColor systemGrayColor];
    gripIcon.transform = CGAffineTransformMakeRotation(M_PI_2);
    gripIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dividerView addSubview:gripIcon];
    [NSLayoutConstraint activateConstraints:@[
        [gripIcon.centerXAnchor constraintEqualToAnchor:self.dividerView.centerXAnchor],
        [gripIcon.centerYAnchor constraintEqualToAnchor:self.dividerView.centerYAnchor],
        [gripIcon.widthAnchor constraintEqualToConstant:14],
        [gripIcon.heightAnchor constraintEqualToConstant:14]
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDividerPan:)];
    [self.dividerView addGestureRecognizer:pan];

    [self.stageBox addSubview:self.pane1];
    [self.stageBox addSubview:self.dividerView];
    [self.stageBox addSubview:self.pane2];

    self.pane1WidthConstraint = [self.pane1.widthAnchor constraintEqualToAnchor:self.stageBox.widthAnchor multiplier:self.splitRatio constant:-6];

    [NSLayoutConstraint activateConstraints:@[
        [self.pane1.topAnchor constraintEqualToAnchor:self.stageBox.topAnchor],
        [self.pane1.bottomAnchor constraintEqualToAnchor:self.stageBox.bottomAnchor],
        [self.pane1.leadingAnchor constraintEqualToAnchor:self.stageBox.leadingAnchor],
        self.pane1WidthConstraint,

        [self.dividerView.topAnchor constraintEqualToAnchor:self.stageBox.topAnchor],
        [self.dividerView.bottomAnchor constraintEqualToAnchor:self.stageBox.bottomAnchor],
        [self.dividerView.leadingAnchor constraintEqualToAnchor:self.pane1.trailingAnchor],
        [self.dividerView.widthAnchor constraintEqualToConstant:12],

        [self.pane2.topAnchor constraintEqualToAnchor:self.stageBox.topAnchor],
        [self.pane2.bottomAnchor constraintEqualToAnchor:self.stageBox.bottomAnchor],
        [self.pane2.leadingAnchor constraintEqualToAnchor:self.dividerView.trailingAnchor],
        [self.pane2.trailingAnchor constraintEqualToAnchor:self.stageBox.trailingAnchor]
    ]];
}

- (void)setupSpeedHUD {
    self.hudCard = [[UIView alloc] init];
    self.hudCard.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.95];
    self.hudCard.layer.cornerRadius = 16;
    self.hudCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.hudCard.layer.shadowOpacity = 0.18;
    self.hudCard.layer.shadowRadius = 8;
    self.hudCard.layer.shadowOffset = CGSizeMake(0, 3);
    self.hudCard.translatesAutoresizingMaskIntoConstraints = NO;

    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.timeLabel.textColor = [UIColor labelColor];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.batteryLabel = [[UILabel alloc] init];
    self.batteryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.batteryLabel.textColor = [UIColor labelColor];
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
    unitLbl.textAlignment = NSTextAlignmentCenter;
    unitLbl.translatesAutoresizingMaskIntoConstraints = NO;

    // Bien bao gioi han toc do 50 tron vien do
    UIView *signCircle = [[UIView alloc] init];
    signCircle.backgroundColor = [UIColor whiteColor];
    signCircle.layer.cornerRadius = 21;
    signCircle.layer.borderWidth = 4.0;
    signCircle.layer.borderColor = [UIColor systemRedColor].CGColor;
    signCircle.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *signNum = [[UILabel alloc] init];
    signNum.text = @"50";
    signNum.textColor = [UIColor blackColor];
    signNum.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
    signNum.textAlignment = NSTextAlignmentCenter;
    signNum.translatesAutoresizingMaskIntoConstraints = NO;
    [signCircle addSubview:signNum];

    [self.hudCard addSubview:self.timeLabel];
    [self.hudCard addSubview:self.batteryLabel];
    [self.hudCard addSubview:self.speedLabel];
    [self.hudCard addSubview:unitLbl];
    [self.hudCard addSubview:signCircle];
    [self.stageBox addSubview:self.hudCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.hudCard.leadingAnchor constraintEqualToAnchor:self.stageBox.leadingAnchor constant:10],
        [self.hudCard.bottomAnchor constraintEqualToAnchor:self.stageBox.bottomAnchor constant:-18],
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

        [signCircle.trailingAnchor constraintEqualToAnchor:self.hudCard.trailingAnchor constant:-10],
        [signCircle.bottomAnchor constraintEqualToAnchor:self.hudCard.bottomAnchor constant:-10],
        [signCircle.widthAnchor constraintEqualToConstant:42],
        [signCircle.heightAnchor constraintEqualToConstant:42],

        [signNum.centerXAnchor constraintEqualToAnchor:signCircle.centerXAnchor],
        [signNum.centerYAnchor constraintEqualToAnchor:signCircle.centerYAnchor]
    ]];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self updateClockAndBattery];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(updateClockAndBattery) userInfo:nil repeats:YES];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)updateClockAndBattery {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    self.timeLabel.text = [fmt stringFromDate:[NSDate date]];

    float bat = [UIDevice currentDevice].batteryLevel;
    int pct = (bat >= 0) ? (int)round(bat * 100) : 95;
    self.batteryLabel.text = [NSString stringWithFormat:@"%d%%", pct];
}

- (void)loadSavedOrDefaultApps {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *b1 = [ud stringForKey:@"pane1Bundle"] ?: @"com.google.ios.youtube";
    NSString *b2 = [ud stringForKey:@"pane2Bundle"] ?: @"vn.vietmap.live";

    InstalledAppItem *app1 = [self findAppByBundleID:b1] ?: self.installedApps.firstObject;
    InstalledAppItem *app2 = [self findAppByBundleID:b2] ?: (self.installedApps.count > 1 ? self.installedApps[1] : app1);

    if (app1) [self.pane1 loadAppWithBundleID:app1.bundleID name:app1.name icon:app1.icon url:app1.fallbackURL];
    if (app2) [self.pane2 loadAppWithBundleID:app2.bundleID name:app2.name icon:app2.icon url:app2.fallbackURL];
}

- (InstalledAppItem *)findAppByBundleID:(NSString *)bundleID {
    for (InstalledAppItem *item in self.installedApps) {
        if ([item.bundleID isEqualToString:bundleID]) return item;
    }
    return nil;
}

- (void)showPickerForPane:(NSInteger)paneIndex {
    [self.pickerOverlay removeFromSuperview];
    self.installedApps = FetchInstalledUserApps();

    NSString *title = [NSString stringWithFormat:@"Chọn app ô %ld", (long)paneIndex];
    AppPickerOverlayView *picker = [[AppPickerOverlayView alloc] initWithTitle:title apps:self.installedApps];
    picker.translatesAutoresizingMaskIntoConstraints = NO;

    __weak typeof(self) weakSelf = self;
    picker.onClose = ^{
        [weakSelf.pickerOverlay removeFromSuperview];
        weakSelf.pickerOverlay = nil;
    };
    picker.onSelectApp = ^(InstalledAppItem *app) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if (paneIndex == 1) {
            [ud setObject:app.bundleID forKey:@"pane1Bundle"];
            [weakSelf.pane1 loadAppWithBundleID:app.bundleID name:app.name icon:app.icon url:app.fallbackURL];
        } else {
            [ud setObject:app.bundleID forKey:@"pane2Bundle"];
            [weakSelf.pane2 loadAppWithBundleID:app.bundleID name:app.name icon:app.icon url:app.fallbackURL];
        }
        [weakSelf.pickerOverlay removeFromSuperview];
        weakSelf.pickerOverlay = nil;
    };

    [self.view addSubview:picker];
    [NSLayoutConstraint activateConstraints:@[
        [picker.topAnchor constraintEqualToAnchor:self.stageBox.topAnchor],
        [picker.leadingAnchor constraintEqualToAnchor:self.stageBox.leadingAnchor],
        [picker.trailingAnchor constraintEqualToAnchor:self.stageBox.trailingAnchor],
        [picker.bottomAnchor constraintEqualToAnchor:self.stageBox.bottomAnchor]
    ]];
    self.pickerOverlay = picker;
}

- (void)openPickerForPane1 { [self showPickerForPane:1]; }
- (void)openPickerForPane2 { [self showPickerForPane:2]; }

- (void)paneViewDidRequestSelectApp:(AppPaneView *)paneView {
    [self showPickerForPane:paneView.paneIndex];
}

- (void)paneViewDidRequestExpand:(AppPaneView *)paneView {
    // Cham nut xanh la cay se mo truc tiep ung dung that tren dien thoai
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass && paneView.currentBundleID.length > 0) {
        [[wsClass defaultWorkspace] openApplicationWithBundleID:paneView.currentBundleID];
    }
}

- (void)paneViewDidRequestReload:(AppPaneView *)paneView {}

- (void)handleDividerPan:(UIPanGestureRecognizer *)gesture {
    CGPoint loc = [gesture locationInView:self.stageBox];
    CGFloat ratio = MIN(MAX(loc.x / MAX(self.stageBox.bounds.size.width, 1.0), 0.28), 0.72);
    self.splitRatio = ratio;
    [[NSUserDefaults standardUserDefaults] setFloat:ratio forKey:@"splitRatio"];
    self.pane1WidthConstraint.active = NO;
    self.pane1WidthConstraint = [self.pane1.widthAnchor constraintEqualToAnchor:self.stageBox.widthAnchor multiplier:ratio constant:-6];
    self.pane1WidthConstraint.active = YES;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *latest = locations.lastObject;
    if (latest && latest.speed >= 0) {
        int kmh = (int)round(latest.speed * 3.6);
        self.speedLabel.text = [NSString stringWithFormat:@"%d", kmh];
    }
}

@end

#pragma mark - Tab 1: Trang Chu (Danh sach ung dung da cai tren may)

@interface HomeAppsViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) NSArray<InstalledAppItem *> *apps;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation HomeAppsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trang chủ";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.apps = FetchInstalledUserApps();

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(12, 16, 24, 16);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"HomeAppCell"];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.apps.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HomeAppCell" forIndexPath:indexPath];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    InstalledAppItem *app = self.apps[indexPath.item];
    cell.contentView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.layer.cornerRadius = 16;

    UIImageView *iv = [[UIImageView alloc] initWithImage:app.icon];
    iv.layer.cornerRadius = 12;
    iv.clipsToBounds = YES;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nameLbl = [[UILabel alloc] init];
    nameLbl.text = app.name;
    nameLbl.font = [UIFont boldSystemFontOfSize:14];
    nameLbl.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *idLbl = [[UILabel alloc] init];
    idLbl.text = app.bundleID;
    idLbl.font = [UIFont systemFontOfSize:11];
    idLbl.textColor = [UIColor secondaryLabelColor];
    idLbl.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:iv];
    [cell.contentView addSubview:nameLbl];
    [cell.contentView addSubview:idLbl];

    [NSLayoutConstraint activateConstraints:@[
        [iv.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
        [iv.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:44],
        [iv.heightAnchor constraintEqualToConstant:44],

        [nameLbl.topAnchor constraintEqualToAnchor:iv.topAnchor constant:4],
        [nameLbl.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:12],
        [nameLbl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],

        [idLbl.topAnchor constraintEqualToAnchor:nameLbl.bottomAnchor constant:2],
        [idLbl.leadingAnchor constraintEqualToAnchor:nameLbl.leadingAnchor],
        [idLbl.trailingAnchor constraintEqualToAnchor:nameLbl.trailingAnchor]
    ]];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width - 32, 68);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    InstalledAppItem *app = self.apps[indexPath.item];
    [[NSUserDefaults standardUserDefaults] setObject:app.bundleID forKey:@"pane1Bundle"];
    self.tabBarController.selectedIndex = 2; // Chuyen thang sang tab Mo phong
}

@end

#pragma mark - Tab 4: Tai Khoan & Cai Dat

@interface AccountViewController : UITableViewController
@end

@implementation AccountViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tài khoản";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Thiết bị & Trạng thái CarPlay" : @"Tùy chọn hiển thị";
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Phiên bản XemYouTube";
            cell.detailTextLabel.text = @"2.1.5";
        } else {
            cell.textLabel.text = @"Quét ứng dụng hệ thống";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu ứng dụng", (unsigned long)FetchInstalledUserApps().count];
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Đặt lại Ô 1 (YouTube) & Ô 2 (VIETMAP)";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            cell.textLabel.text = @"Tốc độ & Biển báo 50";
            cell.detailTextLabel.text = @"Đang bật";
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:@"com.google.ios.youtube" forKey:@"pane1Bundle"];
        [ud setObject:@"vn.vietmap.live" forKey:@"pane2Bundle"];
        [ud setFloat:0.5 forKey:@"splitRatio"];
    }
}
@end

#pragma mark - TabBar 4 Muc & Scene Delegates

@interface MainTabBarController : UITabBarController
@end

@implementation MainTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.tintColor = [UIColor systemBlueColor];

    UINavigationController *navHome = [[UINavigationController alloc] initWithRootViewController:[[HomeAppsViewController alloc] init]];
    navHome.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chủ" image:[UIImage systemImageNamed:@"house"] selectedImage:[UIImage systemImageNamed:@"house.fill"]];

    WorkspaceContainerViewController *carVC = [[WorkspaceContainerViewController alloc] init];
    carVC.isCarMode = YES;
    carVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trên xe" image:[UIImage systemImageNamed:@"car"] selectedImage:[UIImage systemImageNamed:@"car.fill"]];

    WorkspaceContainerViewController *simVC = [[WorkspaceContainerViewController alloc] init];
    simVC.isCarMode = NO;
    simVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Mô phỏng" image:[UIImage systemImageNamed:@"play.rectangle"] selectedImage:[UIImage systemImageNamed:@"play.rectangle.fill"]];

    UINavigationController *navAcc = [[UINavigationController alloc] initWithRootViewController:[[AccountViewController alloc] init]];
    navAcc.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Tài khoản" image:[UIImage systemImageNamed:@"person.crop.circle"] selectedImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];

    self.viewControllers = @[navHome, carVC, simVC, navAcc];
    self.selectedIndex = 2; // Mo san tab Mo phong
}
@end

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property (nonatomic, strong) CPWindow *carWindow;
@end

@implementation CarPlaySceneDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController toWindow:(CPWindow *)window {
    self.carWindow = window;
    WorkspaceContainerViewController *vc = [[WorkspaceContainerViewController alloc] init];
    vc.isCarMode = YES;
    window.rootViewController = vc;
    [window makeKeyAndVisible];
}
@end

@interface PhoneSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PhoneSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[MainTabBarController alloc] init];
    [self.window makeKeyAndVisible];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    if ([connectingSceneSession.role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication]) {
        UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"CarPlayScene" sessionRole:connectingSceneSession.role];
        cfg.delegateClass = [CarPlaySceneDelegate class];
        return cfg;
    }
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"PhoneScene" sessionRole:connectingSceneSession.role];
    cfg.delegateClass = [PhoneSceneDelegate class];
    return cfg;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
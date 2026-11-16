#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>

@interface AppPreset : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, strong) UIColor *color;
+ (instancetype)presetWithName:(NSString *)name url:(NSString *)url icon:(NSString *)icon color:(UIColor *)color;
@end

@implementation AppPreset
+ (instancetype)presetWithName:(NSString *)name url:(NSString *)url icon:(NSString *)icon color:(UIColor *)color {
    AppPreset *p = [[AppPreset alloc] init];
    p.name = name;
    p.url = url;
    p.icon = icon;
    p.color = color;
    return p;
}
@end

static NSArray<AppPreset *> *DefaultPresets(void) {
    return @[
        [AppPreset presetWithName:@"YouTube" url:@"https://m.youtube.com" icon:@"play.rectangle.fill" color:[UIColor systemRedColor]],
        [AppPreset presetWithName:@"Google Maps" url:@"https://www.google.com/maps" icon:@"map.fill" color:[UIColor systemGreenColor]],
        [AppPreset presetWithName:@"Zing MP3" url:@"https://zingmp3.vn" icon:@"music.note" color:[UIColor systemPurpleColor]],
        [AppPreset presetWithName:@"VTVgo" url:@"https://vtvgo.vn" icon:@"tv.fill" color:[UIColor systemBlueColor]],
        [AppPreset presetWithName:@"Spotify" url:@"https://open.spotify.com" icon:@"waveform" color:[UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1.0]],
        [AppPreset presetWithName:@"Google" url:@"https://www.google.com" icon:@"magnifyingglass" color:[UIColor systemOrangeColor]]
    ];
}

#pragma mark - SidePlay Workspace (Chia doi man hinh + Thanh Dock ben trai + Bong bong GPS)

@interface SidePlayWorkspaceViewController : UIViewController <CLLocationManagerDelegate, WKNavigationDelegate>
@property (nonatomic, strong) UIView *dockView;
@property (nonatomic, strong) WKWebView *primaryWebView;
@property (nonatomic, strong) WKWebView *secondaryWebView;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong) NSLayoutConstraint *primaryWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *dividerWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *secondaryWidthConstraint;
@property (nonatomic, strong) UIView *speedBubble;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL isSplitMode;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, assign) NSInteger activeTargetPane; // 0 = trai, 1 = phai
@property (nonatomic, strong) UIButton *paneSwitchBtn;
@property (nonatomic, strong) UIButton *splitToggleBtn;
@end

@implementation SidePlayWorkspaceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:1.0];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    self.isSplitMode = ([ud objectForKey:@"splitMode"] != nil) ? [ud boolForKey:@"splitMode"] : YES;
    self.splitRatio = ([ud floatForKey:@"splitRatio"] > 0.2) ? [ud floatForKey:@"splitRatio"] : 0.55;
    self.activeTargetPane = 0;

    [self setupDock];
    [self setupWebViews];
    [self setupSpeedBubble];
    [self applyLayoutModeAnimated:NO];
}

- (WKWebView *)createConfiguredWebView {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    wv.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
    wv.backgroundColor = [UIColor blackColor];
    wv.opaque = NO;
    wv.scrollView.backgroundColor = [UIColor blackColor];
    wv.navigationDelegate = self;
    wv.translatesAutoresizingMaskIntoConstraints = NO;
    return wv;
}

- (void)setupDock {
    self.dockView = [[UIView alloc] init];
    self.dockView.backgroundColor = [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1.0];
    self.dockView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.dockView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.distribution = UIStackViewDistributionEqualSpacing;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dockView addSubview:stack];

    NSArray<AppPreset *> *presets = DefaultPresets();
    for (NSInteger i = 0; i < presets.count; i++) {
        AppPreset *p = presets[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag = i;
        btn.backgroundColor = [p.color colorWithAlphaComponent:0.22];
        btn.tintColor = p.color;
        btn.layer.cornerRadius = 12;
        UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:p.icon withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [btn.widthAnchor constraintEqualToConstant:40].active = YES;
        [btn.heightAnchor constraintEqualToConstant:40].active = YES;
        [stack addArrangedSubview:btn];
    }

    // Nut chon mo o khung Trai (L) hoac Phai (R)
    self.paneSwitchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.paneSwitchBtn setTitle:@"L" forState:UIControlStateNormal];
    self.paneSwitchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.paneSwitchBtn.backgroundColor = [UIColor systemBlueColor];
    self.paneSwitchBtn.tintColor = [UIColor whiteColor];
    self.paneSwitchBtn.layer.cornerRadius = 10;
    [self.paneSwitchBtn addTarget:self action:@selector(toggleTargetPane) forControlEvents:UIControlEventTouchUpInside];
    [self.paneSwitchBtn.widthAnchor constraintEqualToConstant:40].active = YES;
    [self.paneSwitchBtn.heightAnchor constraintEqualToConstant:32].active = YES;
    [stack addArrangedSubview:self.paneSwitchBtn];

    // Nut bat/tat che do chia doi man hinh
    self.splitToggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *splitCfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [self.splitToggleBtn setImage:[UIImage systemImageNamed:@"rectangle.split.2x1.fill" withConfiguration:splitCfg] forState:UIControlStateNormal];
    self.splitToggleBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    self.splitToggleBtn.tintColor = [UIColor whiteColor];
    self.splitToggleBtn.layer.cornerRadius = 10;
    [self.splitToggleBtn addTarget:self action:@selector(toggleSplitMode) forControlEvents:UIControlEventTouchUpInside];
    [self.splitToggleBtn.widthAnchor constraintEqualToConstant:40].active = YES;
    [self.splitToggleBtn.heightAnchor constraintEqualToConstant:34].active = YES;
    [stack addArrangedSubview:self.splitToggleBtn];

    // Nut tai lai trang
    UIButton *reloadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [reloadBtn setImage:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:splitCfg] forState:UIControlStateNormal];
    reloadBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    reloadBtn.tintColor = [UIColor lightGrayColor];
    reloadBtn.layer.cornerRadius = 10;
    [reloadBtn addTarget:self action:@selector(reloadActiveWeb) forControlEvents:UIControlEventTouchUpInside];
    [reloadBtn.widthAnchor constraintEqualToConstant:40].active = YES;
    [reloadBtn.heightAnchor constraintEqualToConstant:34].active = YES;
    [stack addArrangedSubview:reloadBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.dockView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.dockView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.dockView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.dockView.widthAnchor constraintEqualToConstant:54],

        [stack.topAnchor constraintEqualToAnchor:self.dockView.topAnchor constant:10],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.dockView.bottomAnchor constant:-10],
        [stack.centerXAnchor constraintEqualToAnchor:self.dockView.centerXAnchor]
    ]];
}

- (void)setupWebViews {
    self.primaryWebView = [self createConfiguredWebView];
    self.secondaryWebView = [self createConfiguredWebView];

    self.dividerView = [[UIView alloc] init];
    self.dividerView.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.dividerView.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *grip = [[UIView alloc] init];
    grip.backgroundColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    grip.layer.cornerRadius = 2;
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dividerView addSubview:grip];
    [NSLayoutConstraint activateConstraints:@[
        [grip.centerXAnchor constraintEqualToAnchor:self.dividerView.centerXAnchor],
        [grip.centerYAnchor constraintEqualToAnchor:self.dividerView.centerYAnchor],
        [grip.widthAnchor constraintEqualToConstant:4],
        [grip.heightAnchor constraintEqualToConstant:36]
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDividerPan:)];
    [self.dividerView addGestureRecognizer:pan];

    [self.view addSubview:self.primaryWebView];
    [self.view addSubview:self.dividerView];
    [self.view addSubview:self.secondaryWebView];

    self.dividerWidthConstraint = [self.dividerView.widthAnchor constraintEqualToConstant:10];
    self.secondaryWidthConstraint = [self.secondaryWebView.widthAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.primaryWebView.leadingAnchor constraintEqualToAnchor:self.dockView.trailingAnchor],
        [self.primaryWebView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.primaryWebView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.dividerView.leadingAnchor constraintEqualToAnchor:self.primaryWebView.trailingAnchor],
        [self.dividerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.dividerView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        self.dividerWidthConstraint,

        [self.secondaryWebView.leadingAnchor constraintEqualToAnchor:self.dividerView.trailingAnchor],
        [self.secondaryWebView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.secondaryWebView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.secondaryWebView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *leftURL = [ud stringForKey:@"leftURL"] ?: @"https://m.youtube.com";
    NSString *rightURL = [ud stringForKey:@"rightURL"] ?: @"https://www.google.com/maps";

    [self.primaryWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:leftURL]]];
    [self.secondaryWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:rightURL]]];
}

- (void)applyLayoutModeAnimated:(BOOL)animated {
    if (self.primaryWidthConstraint) {
        self.primaryWidthConstraint.active = NO;
    }
    if (self.isSplitMode) {
        self.dividerWidthConstraint.constant = 10;
        self.dividerView.hidden = NO;
        self.secondaryWebView.hidden = NO;
        self.paneSwitchBtn.hidden = NO;
        self.splitToggleBtn.tintColor = [UIColor systemCyanColor];

        // Chieu rong vung noi dung = tong chieu rong - dock (54) - divider (10)
        self.primaryWidthConstraint = [NSLayoutConstraint constraintWithItem:self.primaryWebView
                                                                   attribute:NSLayoutAttributeWidth
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self.view.safeAreaLayoutGuide
                                                                   attribute:NSLayoutAttributeWidth
                                                                  multiplier:self.splitRatio
                                                                    constant:-36];
    } else {
        self.dividerWidthConstraint.constant = 0;
        self.dividerView.hidden = YES;
        self.secondaryWebView.hidden = YES;
        self.paneSwitchBtn.hidden = YES;
        self.splitToggleBtn.tintColor = [UIColor whiteColor];

        self.primaryWidthConstraint = [self.primaryWebView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor];
    }
    self.primaryWidthConstraint.active = YES;

    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

- (void)setupSpeedBubble {
    self.speedBubble = [[UIView alloc] init];
    self.speedBubble.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
    self.speedBubble.layer.cornerRadius = 18;
    self.speedBubble.layer.borderWidth = 1.0;
    self.speedBubble.layer.borderColor = [[UIColor systemCyanColor] colorWithAlphaComponent:0.5].CGColor;
    self.speedBubble.translatesAutoresizingMaskIntoConstraints = NO;

    self.speedValueLabel = [[UILabel alloc] init];
    self.speedValueLabel.text = @"0 km/h";
    self.speedValueLabel.textColor = [UIColor whiteColor];
    self.speedValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightBold];
    self.speedValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.speedBubble addSubview:self.speedValueLabel];
    [self.view addSubview:self.speedBubble];

    [NSLayoutConstraint activateConstraints:@[
        [self.speedValueLabel.topAnchor constraintEqualToAnchor:self.speedBubble.topAnchor constant:8],
        [self.speedValueLabel.bottomAnchor constraintEqualToAnchor:self.speedBubble.bottomAnchor constant:-8],
        [self.speedValueLabel.leadingAnchor constraintEqualToAnchor:self.speedBubble.leadingAnchor constant:12],
        [self.speedValueLabel.trailingAnchor constraintEqualToAnchor:self.speedBubble.trailingAnchor constant:-12],
        [self.speedBubble.leadingAnchor constraintEqualToAnchor:self.dockView.trailingAnchor constant:12],
        [self.speedBubble.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    BOOL showSpeed = ([[NSUserDefaults standardUserDefaults] objectForKey:@"showSpeed"] != nil) ? [[NSUserDefaults standardUserDefaults] boolForKey:@"showSpeed"] : YES;
    self.speedBubble.hidden = !showSpeed;

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)presetTapped:(UIButton *)sender {
    NSArray<AppPreset *> *presets = DefaultPresets();
    if (sender.tag < 0 || sender.tag >= presets.count) return;
    AppPreset *p = presets[sender.tag];
    NSURL *url = [NSURL URLWithString:p.url];
    if (!self.isSplitMode || self.activeTargetPane == 0) {
        [self.primaryWebView loadRequest:[NSURLRequest requestWithURL:url]];
    } else {
        [self.secondaryWebView loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (void)toggleTargetPane {
    self.activeTargetPane = (self.activeTargetPane == 0) ? 1 : 0;
    [self.paneSwitchBtn setTitle:(self.activeTargetPane == 0 ? @"L" : @"R") forState:UIControlStateNormal];
    self.paneSwitchBtn.backgroundColor = (self.activeTargetPane == 0) ? [UIColor systemBlueColor] : [UIColor systemOrangeColor];
}

- (void)toggleSplitMode {
    self.isSplitMode = !self.isSplitMode;
    [[NSUserDefaults standardUserDefaults] setBool:self.isSplitMode forKey:@"splitMode"];
    [self applyLayoutModeAnimated:YES];
}

- (void)reloadActiveWeb {
    [self.primaryWebView reload];
    if (self.isSplitMode) {
        [self.secondaryWebView reload];
    }
}

- (void)handleDividerPan:(UIPanGestureRecognizer *)gesture {
    if (!self.isSplitMode) return;
    CGFloat contentWidth = MAX(self.view.safeAreaLayoutGuide.layoutFrame.size.width - 64, 1.0);
    CGPoint loc = [gesture locationInView:self.view];
    CGFloat offsetX = loc.x - self.dockView.frame.origin.x - 54;
    CGFloat ratio = MIN(MAX(offsetX / contentWidth, 0.30), 0.75);
    self.splitRatio = ratio;
    [[NSUserDefaults standardUserDefaults] setFloat:ratio forKey:@"splitRatio"];
    [self applyLayoutModeAnimated:NO];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *latest = locations.lastObject;
    if (latest && latest.speed >= 0) {
        int kmh = (int)round(latest.speed * 3.6);
        self.speedValueLabel.text = [NSString stringWithFormat:@"%d km/h", kmh];
    }
}

@end

#pragma mark - Trang Chu (Bang dieu khien kieu SidePlay)

@interface HomeDashboardViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation HomeDashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"XemYouTube CarPlay";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 14;
    layout.minimumInteritemSpacing = 14;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 24, 16);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"CardCell"];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return DefaultPresets().count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"CardCell" forIndexPath:indexPath];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    AppPreset *p = DefaultPresets()[indexPath.item];
    cell.contentView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.layer.cornerRadius = 18;

    UIView *badge = [[UIView alloc] init];
    badge.backgroundColor = [p.color colorWithAlphaComponent:0.18];
    badge.layer.cornerRadius = 14;
    badge.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:p.icon]];
    iv.tintColor = p.color;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:iv];

    UILabel *title = [[UILabel alloc] init];
    title.text = p.name;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"Chạm để mở trên CarPlay / Mô phỏng";
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.numberOfLines = 2;
    sub.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:badge];
    [cell.contentView addSubview:title];
    [cell.contentView addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [badge.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],
        [badge.widthAnchor constraintEqualToConstant:44],
        [badge.heightAnchor constraintEqualToConstant:44],

        [iv.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:24],
        [iv.heightAnchor constraintEqualToConstant:24],

        [title.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],
        [title.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14],

        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],
        [sub.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14]
    ]];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = (collectionView.bounds.size.width - 46) / 2.0;
    return CGSizeMake(MAX(w, 140), 132);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    AppPreset *p = DefaultPresets()[indexPath.item];
    [[NSUserDefaults standardUserDefaults] setObject:p.url forKey:@"leftURL"];
    self.tabBarController.selectedIndex = 1;
}

@end

#pragma mark - Cai Dat (Day du cong tac tuy chinh)

@interface SettingsTableViewController : UITableViewController
@end

@implementation SettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cài đặt";
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Giao diện CarPlay & Chia màn hình" : @"Thông tin ứng dụng";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Bật chia đôi màn hình mặc định";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = ([ud objectForKey:@"splitMode"] != nil) ? [ud boolForKey:@"splitMode"] : YES;
            [sw addTarget:self action:@selector(toggleSplitSetting:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Hiển thị bong bóng tốc độ GPS";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = ([ud objectForKey:@"showSpeed"] != nil) ? [ud boolForKey:@"showSpeed"] : YES;
            [sw addTarget:self action:@selector(toggleSpeedSetting:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Đặt lại mặc định (YouTube + Maps)";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Phiên bản";
            cell.detailTextLabel.text = @"2.1.3 (SidePlay UI)";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Trạng thái CarPlay";
            cell.detailTextLabel.text = @"Sẵn sàng";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 2) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:@"https://m.youtube.com" forKey:@"leftURL"];
        [ud setObject:@"https://www.google.com/maps" forKey:@"rightURL"];
        [ud setFloat:0.55 forKey:@"splitRatio"];
        [ud setBool:YES forKey:@"splitMode"];
        [ud setBool:YES forKey:@"showSpeed"];
        [tableView reloadData];
    }
}

- (void)toggleSplitSetting:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"splitMode"];
}

- (void)toggleSpeedSetting:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"showSpeed"];
}

@end

#pragma mark - TabBar & Scene Delegates

@interface MainTabBarController : UITabBarController
@end

@implementation MainTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];

    UINavigationController *navHome = [[UINavigationController alloc] initWithRootViewController:[[HomeDashboardViewController alloc] init]];
    navHome.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chủ" image:[UIImage systemImageNamed:@"square.grid.2x2.fill"] tag:0];

    SidePlayWorkspaceViewController *simVC = [[SidePlayWorkspaceViewController alloc] init];
    simVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"CarPlay / Mô phỏng" image:[UIImage systemImageNamed:@"car.fill"] tag:1];

    UINavigationController *navSet = [[UINavigationController alloc] initWithRootViewController:[[SettingsTableViewController alloc] init]];
    navSet.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cài đặt" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2];

    self.viewControllers = @[navHome, simVC, navSet];
}
@end

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property (nonatomic, strong) CPWindow *carWindow;
@end

@implementation CarPlaySceneDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController toWindow:(CPWindow *)window {
    self.carWindow = window;
    window.rootViewController = [[SidePlayWorkspaceViewController alloc] init];
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
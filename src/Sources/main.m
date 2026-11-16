#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>

@interface SplitScreenViewController : UIViewController <CLLocationManagerDelegate>
@property (nonatomic, strong) WKWebView *leftWebView;
@property (nonatomic, strong) WKWebView *rightWebView;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) CGFloat splitRatio;
@property (nonatomic, strong) NSLayoutConstraint *leftWidthConstraint;
@end

@implementation SplitScreenViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.splitRatio = 0.5;

    WKWebViewConfiguration *cfg1 = [[WKWebViewConfiguration alloc] init];
    cfg1.allowsInlineMediaPlayback = YES;
    self.leftWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg1];
    self.leftWebView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1";
    self.leftWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://m.youtube.com"]]];

    WKWebViewConfiguration *cfg2 = [[WKWebViewConfiguration alloc] init];
    cfg2.allowsInlineMediaPlayback = YES;
    self.rightWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg2];
    self.rightWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rightWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com/maps"]]];

    UIView *divider = [[UIView alloc] init];
    divider.backgroundColor = [UIColor separatorColor];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [divider addGestureRecognizer:pan];

    [self.view addSubview:self.leftWebView];
    [self.view addSubview:divider];
    [self.view addSubview:self.rightWebView];

    self.leftWidthConstraint = [self.leftWebView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:self.splitRatio constant:-4];

    [NSLayoutConstraint activateConstraints:@[
        [self.leftWebView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.leftWebView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.leftWebView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        self.leftWidthConstraint,

        [divider.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:self.leftWebView.trailingAnchor],
        [divider.widthAnchor constraintEqualToConstant:8],

        [self.rightWebView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.rightWebView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.rightWebView.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [self.rightWebView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    [self setupSpeedBubble];
}

- (void)setupSpeedBubble {
    UIView *bubble = [[UIView alloc] init];
    bubble.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.9];
    bubble.layer.cornerRadius = 16;
    bubble.translatesAutoresizingMaskIntoConstraints = NO;

    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.text = @"0 km/h";
    self.speedLabel.font = [UIFont boldSystemFontOfSize:18];
    self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [bubble addSubview:self.speedLabel];
    [self.view addSubview:bubble];

    [NSLayoutConstraint activateConstraints:@[
        [self.speedLabel.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:10],
        [self.speedLabel.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-10],
        [self.speedLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:14],
        [self.speedLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-14],
        [bubble.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [bubble.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]
    ]];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint loc = [gesture locationInView:self.view];
    CGFloat ratio = loc.x / MAX(self.view.bounds.size.width, 1.0);
    ratio = MIN(MAX(ratio, 0.25), 0.75);
    self.splitRatio = ratio;
    self.leftWidthConstraint.active = NO;
    self.leftWidthConstraint = [self.leftWebView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:ratio constant:-4];
    self.leftWidthConstraint.active = YES;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *latest = locations.lastObject;
    if (latest && latest.speed >= 0) {
        int kmh = (int)round(latest.speed * 3.6);
        self.speedLabel.text = [NSString stringWithFormat:@"%d km/h", kmh];
    }
}
@end

@interface MainTabBarController : UITabBarController
@end

@implementation MainTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];

    UIViewController *homeVC = [[UIViewController alloc] init];
    homeVC.view.backgroundColor = [UIColor systemBackgroundColor];
    homeVC.title = @"XemYouTube 2.1.3";
    UILabel *status = [[UILabel alloc] init];
    status.text = @"San sang cho CarPlay\nChuyen sang tab Mo phong de thu chia doi man hinh";
    status.numberOfLines = 0;
    status.textAlignment = NSTextAlignmentCenter;
    status.translatesAutoresizingMaskIntoConstraints = NO;
    [homeVC.view addSubview:status];
    [NSLayoutConstraint activateConstraints:@[
        [status.centerXAnchor constraintEqualToAnchor:homeVC.view.centerXAnchor],
        [status.centerYAnchor constraintEqualToAnchor:homeVC.view.centerYAnchor],
        [status.leadingAnchor constraintEqualToAnchor:homeVC.view.leadingAnchor constant:24],
        [status.trailingAnchor constraintEqualToAnchor:homeVC.view.trailingAnchor constant:-24]
    ]];
    UINavigationController *navHome = [[UINavigationController alloc] initWithRootViewController:homeVC];
    navHome.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chu" image:[UIImage systemImageNamed:@"house.fill"] tag:0];

    SplitScreenViewController *simVC = [[SplitScreenViewController alloc] init];
    simVC.title = @"Mo phong";
    UINavigationController *navSim = [[UINavigationController alloc] initWithRootViewController:simVC];
    navSim.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Mo phong" image:[UIImage systemImageNamed:@"play.rectangle.fill"] tag:1];

    UIViewController *settingsVC = [[UIViewController alloc] init];
    settingsVC.view.backgroundColor = [UIColor systemBackgroundColor];
    settingsVC.title = @"Cai dat";
    UINavigationController *navSet = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    navSet.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cai dat" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2];

    self.viewControllers = @[navHome, navSim, navSet];
}
@end

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property (nonatomic, strong) CPWindow *carWindow;
@end

@implementation CarPlaySceneDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController toWindow:(CPWindow *)window {
    self.carWindow = window;
    window.rootViewController = [[SplitScreenViewController alloc] init];
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
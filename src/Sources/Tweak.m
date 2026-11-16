#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

// Khai bao cac lop Private cua SpringBoard & FrontBoard de nhung truc tiep App Goc
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (PrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
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

@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dict;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleID withOptions:(id)options completion:(void (^)(id process, NSError *error))completion;
@end

// Cua so Overlay chay ngay trong SpringBoard khi nguoi dung mo XemYouTube -> co toan quyen nhung Live App Goc!
@interface SP2LivePane : UIView
@property (nonatomic, assign) NSInteger paneIndex;
@property (nonatomic, copy) NSString *currentBundleID;
@property (nonatomic, strong) UIButton *titleBtn;
@property (nonatomic, strong) UIStackView *recentStack;
@property (nonatomic, strong) UIView *sceneHostContainer;
@property (nonatomic, strong) id activePresenter;
@property (nonatomic, strong) id hostedScene;
@property (nonatomic, assign) CGRect originalFrame;
@property (nonatomic, assign) BOOL originalForeground;
@property (nonatomic, assign) BOOL hasOriginalSettings;
@property (nonatomic, assign) NSUInteger generation;
- (void)closeTap;
- (void)showStatus:(NSString *)message;
- (void)attachSceneWithRetry:(NSInteger)attempt generation:(NSUInteger)generation;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recentApps;
@property (nonatomic, copy) void (^onRequestPickApp)(SP2LivePane *pane);
@property (nonatomic, copy) void (^onRequestLayout)(void);
- (instancetype)initWithIndex:(NSInteger)idx;
- (void)embedNativeAppWithBundleID:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon;
- (void)refreshSceneFrame;
@end

@implementation SP2LivePane

- (instancetype)initWithIndex:(NSInteger)idx {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.paneIndex = idx;
        self.recentApps = [NSMutableArray array];
        self.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
        self.clipsToBounds = YES;
        [self buildBar];
    }
    return self;
}

- (void)buildBar {
    UIView *topBar = [[UIView alloc] init];
    topBar.backgroundColor = [UIColor colorWithRed:0.91 green:0.92 blue:0.95 alpha:1.0];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:topBar];

    self.titleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.titleBtn.backgroundColor = [UIColor whiteColor];
    self.titleBtn.layer.cornerRadius = 8;
    [self.titleBtn setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
    [self.titleBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.titleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.titleBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleBtn addTarget:self action:@selector(pickTap) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:self.titleBtn];

    UIView *dots = [[UIView alloc] init];
    dots.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:dots];

    UIButton *bY = [self dot:[UIColor systemYellowColor] sel:@selector(layoutTap)];
    UIButton *bG = [self dot:[UIColor systemGreenColor] sel:@selector(layoutTap)];
    UIButton *bR = [self dot:[UIColor systemRedColor] sel:@selector(closeTap)];
    [dots addSubview:bY]; [dots addSubview:bG]; [dots addSubview:bR];

    UIScrollView *stripScroll = [[UIScrollView alloc] init];
    stripScroll.backgroundColor = [UIColor whiteColor];
    stripScroll.showsHorizontalScrollIndicator = NO;
    stripScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stripScroll];

    self.recentStack = [[UIStackView alloc] init];
    self.recentStack.spacing = 4;
    self.recentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [stripScroll addSubview:self.recentStack];

    self.sceneHostContainer = [[UIView alloc] init];
    self.sceneHostContainer.backgroundColor = [UIColor blackColor];
    self.sceneHostContainer.clipsToBounds = YES;
    self.sceneHostContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.sceneHostContainer];

    UIButton *centerPickBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [centerPickBtn setTitle:@"Chạm để chọn App Gốc chạy trực tiếp ›" forState:UIControlStateNormal];
    centerPickBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [centerPickBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    centerPickBtn.backgroundColor = [UIColor systemBlueColor];
    centerPickBtn.layer.cornerRadius = 12;
    centerPickBtn.tag = 999;
    centerPickBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [centerPickBtn addTarget:self action:@selector(pickTap) forControlEvents:UIControlEventTouchUpInside];
    [self.sceneHostContainer addSubview:centerPickBtn];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:30],

        [dots.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-6],
        [dots.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [dots.widthAnchor constraintEqualToConstant:44],
        [dots.heightAnchor constraintEqualToConstant:14],

        [bY.leadingAnchor constraintEqualToAnchor:dots.leadingAnchor],
        [bY.centerYAnchor constraintEqualToAnchor:dots.centerYAnchor],
        [bY.widthAnchor constraintEqualToConstant:12], [bY.heightAnchor constraintEqualToConstant:12],

        [bG.centerXAnchor constraintEqualToAnchor:dots.centerXAnchor],
        [bG.centerYAnchor constraintEqualToAnchor:dots.centerYAnchor],
        [bG.widthAnchor constraintEqualToConstant:12], [bG.heightAnchor constraintEqualToConstant:12],

        [bR.trailingAnchor constraintEqualToAnchor:dots.trailingAnchor],
        [bR.centerYAnchor constraintEqualToAnchor:dots.centerYAnchor],
        [bR.widthAnchor constraintEqualToConstant:12], [bR.heightAnchor constraintEqualToConstant:12],

        [self.titleBtn.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:5],
        [self.titleBtn.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor constant:-2],
        [self.titleBtn.heightAnchor constraintEqualToConstant:24],
        [self.titleBtn.trailingAnchor constraintLessThanOrEqualToAnchor:dots.leadingAnchor constant:-4],

        [stripScroll.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [stripScroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stripScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stripScroll.heightAnchor constraintEqualToConstant:24],

        [self.recentStack.leadingAnchor constraintEqualToAnchor:stripScroll.leadingAnchor constant:4],
        [self.recentStack.trailingAnchor constraintEqualToAnchor:stripScroll.trailingAnchor constant:-4],
        [self.recentStack.centerYAnchor constraintEqualToAnchor:stripScroll.centerYAnchor],

        [self.sceneHostContainer.topAnchor constraintEqualToAnchor:stripScroll.bottomAnchor],
        [self.sceneHostContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.sceneHostContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.sceneHostContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [centerPickBtn.centerXAnchor constraintEqualToAnchor:self.sceneHostContainer.centerXAnchor],
        [centerPickBtn.centerYAnchor constraintEqualToAnchor:self.sceneHostContainer.centerYAnchor],
        [centerPickBtn.widthAnchor constraintEqualToConstant:150],
        [centerPickBtn.heightAnchor constraintEqualToConstant:40]
    ]];
    centerPickBtn.titleLabel.numberOfLines = 2;
    centerPickBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
}

- (UIButton *)dot:(UIColor *)c sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = c;
    b.layer.cornerRadius = 6;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)pickTap { if (self.onRequestPickApp) self.onRequestPickApp(self); }
- (void)layoutTap { if (self.onRequestLayout) self.onRequestLayout(); }

- (void)showStatus:(NSString *)message {
    UIButton *status = (UIButton *)[self.sceneHostContainer viewWithTag:999];
    [status setTitle:message forState:UIControlStateNormal];
    status.hidden = NO;
    NSLog(@"[XYT native] pane %ld: %@", (long)self.paneIndex, message);
}
- (void)closeTap {
    self.generation++;
    if (self.hasOriginalSettings && self.hostedScene) {
        @try {
            CGRect frame = self.originalFrame;
            BOOL foreground = self.originalForeground;
            [self.hostedScene updateSettingsWithBlock:^(id settings) {
                if ([settings respondsToSelector:@selector(setFrame:)])
                    ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, @selector(setFrame:), frame);
                if ([settings respondsToSelector:@selector(setForeground:)])
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, @selector(setForeground:), foreground);
            }];
        } @catch (NSException *exception) { NSLog(@"[XYT native] restore failed: %@", exception.name); }
    }
    self.hostedScene = nil;
    self.hasOriginalSettings = NO;
    if ([self.activePresenter respondsToSelector:@selector(deactivate)]) [self.activePresenter deactivate];
    if (self.activePresenter && [self.activePresenter respondsToSelector:@selector(invalidate)]) {
        [self.activePresenter invalidate];
    }
    self.activePresenter = nil;
    self.currentBundleID = nil;
    for (UIView *sub in self.sceneHostContainer.subviews) {
        if (sub.tag != 999) [sub removeFromSuperview];
    }
    [self.titleBtn setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
    [self showStatus:@"Chạm để chọn ứng dụng"];
}

- (void)embedNativeAppWithBundleID:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon {
    if (!bundleID) return;
    [self closeTap];
    self.currentBundleID = bundleID;
    NSUInteger generation = self.generation;
    [self showStatus:@"Đang khởi chạy…"];
    NSString *shortName = name.length > 8 ? [[name substringToIndex:7] stringByAppendingString:@"..."] : name;
    [self.titleBtn setTitle:[NSString stringWithFormat:@" %@ ⌄", shortName] forState:UIControlStateNormal];

    // Luu vao thanh tab chuyen nhanh
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"id != %@", bundleID];
    [self.recentApps filterUsingPredicate:pred];
    [self.recentApps insertObject:@{@"id": bundleID, @"name": name ?: bundleID, @"icon": icon ?: [UIImage new]} atIndex:0];
    if (self.recentApps.count > 4) [self.recentApps removeLastObject];
    [self rebuildStrip];

    // 1. Khoi chay ung dung goc o che do nen qua FBSOpenApplicationService
    Class svcCls = NSClassFromString(@"FBSOpenApplicationService");
    Class optCls = NSClassFromString(@"FBSOpenApplicationOptions");
    if (svcCls && optCls && [svcCls respondsToSelector:@selector(serviceWithDefaultShellEndpoint)]) {
        id svc = [svcCls serviceWithDefaultShellEndpoint];
        id opts = [optCls optionsWithDictionary:@{ @"__ActivateSuspended" : @YES }];
        if ([svc respondsToSelector:@selector(openApplication:withOptions:completion:)]) {
            [svc openApplication:bundleID withOptions:opts completion:^(id proc, NSError *err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.generation) return;
                    if (err) { [self showStatus:[NSString stringWithFormat:@"Không mở được: %@", err.localizedDescription]]; return; }
                    [self attachSceneWithRetry:0 generation:generation];
                });
            }];
            return;
        }
    }
    [self showStatus:@"Thiếu dịch vụ khởi chạy ứng dụng"];
}

- (void)attachSceneWithRetry:(NSInteger)attempt generation:(NSUInteger)generation {
    if (!self.currentBundleID || generation != self.generation) return;
    @try {
    Class mgrCls = NSClassFromString(@"FBSceneManager");
    if (!mgrCls || ![mgrCls respondsToSelector:@selector(sharedInstance)]) { [self showStatus:@"Không có FBSceneManager"]; return; }

    id mgr = [mgrCls sharedInstance];
    NSSet *scenes = [mgr respondsToSelector:@selector(scenes)] ? [mgr scenes] : nil;
    id matchedScene = nil;

    for (id sc in scenes) {
        NSString *sid = [sc valueForKey:@"identifier"];
        if (sid && [sid containsString:self.currentBundleID]) {
            matchedScene = sc;
            break;
        }
    }

    if (!matchedScene) {
        if (attempt < 6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self attachSceneWithRetry:attempt + 1 generation:generation];
            });
        } else { [self showStatus:@"Không tìm thấy scene của ứng dụng"]; }
        return;
    }

    // Ep FBScene cua App Goc luon o che do Foreground va render theo kich thuoc that
    CGRect targetBounds = self.sceneHostContainer.bounds.size.width > 20 ? self.sceneHostContainer.bounds : CGRectMake(0, 0, 375, 667);
    CGFloat scaleFactor = targetBounds.size.width / 375.0;
    CGRect fullPhoneRect = CGRectMake(0, 0, 375, MAX(targetBounds.size.height / MAX(scaleFactor, 0.35), 600));

    if (self.hostedScene != matchedScene) {
        id settings = [matchedScene respondsToSelector:@selector(settings)] ? [matchedScene valueForKey:@"settings"] : nil;
        if ([settings respondsToSelector:@selector(frame)] && [settings respondsToSelector:@selector(isForeground)]) {
            self.originalFrame = ((CGRect (*)(id, SEL))objc_msgSend)(settings, @selector(frame));
            self.originalForeground = ((BOOL (*)(id, SEL))objc_msgSend)(settings, @selector(isForeground));
            self.hasOriginalSettings = YES;
        } else {
            [self showStatus:@"Không đọc được trạng thái scene để khôi phục"];
            return;
        }
        self.hostedScene = matchedScene;
    }
    if ([matchedScene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
        [matchedScene updateSettingsWithBlock:^(id mutableSettings) {
            if ([mutableSettings respondsToSelector:@selector(setForeground:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(mutableSettings, @selector(setForeground:), YES);
            }
            if ([mutableSettings respondsToSelector:@selector(setFrame:)]) {
                ((void (*)(id, SEL, CGRect))objc_msgSend)(mutableSettings, @selector(setFrame:), fullPhoneRect);
            }
        }];
    }

    if (self.activePresenter && [self.activePresenter respondsToSelector:@selector(invalidate)]) {
        [self.activePresenter invalidate];
        self.activePresenter = nil;
    }

    if (![matchedScene respondsToSelector:@selector(uiPresentationManager)]) { [self showStatus:@"Scene thiếu presentation manager"]; return; }
    id presMgr = [matchedScene uiPresentationManager];
    if ([presMgr respondsToSelector:@selector(createPresenterWithIdentifier:)]) {
        NSString *pid = [NSString stringWithFormat:@"SP2LivePane-%ld-%u", (long)self.paneIndex, arc4random_uniform(9999)];
        id presenter = [presMgr createPresenterWithIdentifier:pid];
        if ([presenter respondsToSelector:@selector(activate)]) {
            [presenter activate];
            UIView *liveView = [presenter respondsToSelector:@selector(presentationView)] ? [presenter presentationView] : nil;
            if (liveView) {
                for (UIView *sub in self.sceneHostContainer.subviews) {
                    if (sub.tag != 999) [sub removeFromSuperview];
                }
                liveView.bounds = fullPhoneRect;
                liveView.center = CGPointMake(targetBounds.size.width / 2.0, targetBounds.size.height / 2.0);
                liveView.transform = CGAffineTransformMakeScale(scaleFactor, scaleFactor);
                [self.sceneHostContainer addSubview:liveView];
                self.activePresenter = presenter;
                liveView.userInteractionEnabled = YES;
                [self.sceneHostContainer viewWithTag:999].hidden = YES;
            }
        }
    }
    if (!self.activePresenter) [self showStatus:@"Không tạo được presentation view"];
    } @catch (NSException *exception) {
        [self showStatus:[NSString stringWithFormat:@"API không tương thích: %@", exception.name]];
    }
}

- (void)refreshSceneFrame {
    if (self.currentBundleID) {
        [self attachSceneWithRetry:5 generation:self.generation];
    }
}

- (void)rebuildStrip {
    for (UIView *v in self.recentStack.arrangedSubviews) {
        [self.recentStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSInteger i = 0; i < self.recentApps.count; i++) {
        NSDictionary *d = self.recentApps[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i;
        NSString *nm = d[@"name"];
        NSString *shortNm = nm.length > 7 ? [[nm substringToIndex:6] stringByAppendingString:@"..."] : nm;
        [b setTitle:[NSString stringWithFormat:@" %@", shortNm] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:10 weight:(i == 0 ? UIFontWeightBold : UIFontWeightRegular)];
        [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        b.backgroundColor = (i == 0) ? [UIColor colorWithWhite:0.90 alpha:1.0] : [UIColor clearColor];
        b.layer.cornerRadius = 5;
        [b addTarget:self action:@selector(recentTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.recentStack addArrangedSubview:b];
    }
}

- (void)recentTap:(UIButton *)sender {
    if (sender.tag >= 0 && sender.tag < self.recentApps.count) {
        NSDictionary *d = self.recentApps[sender.tag];
        [self embedNativeAppWithBundleID:d[@"id"] name:d[@"name"] icon:d[@"icon"]];
    }
}

@end

// Explicit opt-in phone test. No automatic replacement of the CarPlay dashboard.
@interface XYTNativeTestController : UIViewController
@property (nonatomic, strong) NSArray<SP2LivePane *> *panes;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, assign) CGFloat ratio;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation XYTNativeTestController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.ratio = 0.5;
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Đóng thử nghiệm" forState:UIControlStateNormal];
    close.frame = CGRectMake(12, 50, 180, 44);
    close.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
    [close addTarget:self action:@selector(closeTest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    NSMutableArray *panes = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < 2; i++) {
        SP2LivePane *pane = [[SP2LivePane alloc] initWithIndex:i];
        pane.onRequestPickApp = ^(SP2LivePane *target) { [weakSelf pickApp:target]; };
        pane.onRequestLayout = ^{ weakSelf.ratio = 0.5; [weakSelf.view setNeedsLayout]; };
        [self.view addSubview:pane];
        [panes addObject:pane];
    }
    self.panes = panes;
    self.divider = [UIView new];
    self.divider.backgroundColor = [UIColor systemGrayColor];
    [self.divider addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [self.view addSubview:self.divider];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat top = MAX(self.view.safeAreaInsets.top + 48, 100);
    CGFloat height = MAX(0, bounds.size.height - top - self.view.safeAreaInsets.bottom - 12);
    CGFloat width = MAX(0, bounds.size.width - 24);
    CGFloat left = (width - 20) * self.ratio;
    self.panes[0].frame = CGRectMake(12, top, left, height);
    self.divider.frame = CGRectMake(12 + left, top, 20, height);
    self.panes[1].frame = CGRectMake(32 + left, top, width - left - 20, height);
    // Resize the existing view without creating new presenters during every pan.
    for (SP2LivePane *pane in self.panes) {
        [pane layoutIfNeeded];
        UIView *live = [pane.activePresenter respondsToSelector:@selector(presentationView)] ? [pane.activePresenter presentationView] : nil;
        if (live) {
            CGFloat scale = pane.sceneHostContainer.bounds.size.width / MAX(live.bounds.size.width, 1);
            live.transform = CGAffineTransformMakeScale(scale, scale);
            live.center = CGPointMake(CGRectGetMidX(pane.sceneHostContainer.bounds), CGRectGetMidY(pane.sceneHostContainer.bounds));
        }
    }
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGFloat width = MAX(self.view.bounds.size.width - 44, 1);
    self.ratio = MIN(0.75, MAX(0.25, ([gesture locationInView:self.view].x - 12) / width));
    [self.view setNeedsLayout];
}
- (void)pickApp:(SP2LivePane *)pane {
    @try {
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        if (![cls respondsToSelector:@selector(defaultWorkspace)]) { [pane showStatus:@"Không truy cập được danh sách ứng dụng"]; return; }
        NSArray *apps = [[cls defaultWorkspace] allInstalledApplications];
        NSMutableArray *targets = [NSMutableArray array];
        for (id proxy in apps) {
            NSString *bid = [proxy valueForKey:@"applicationIdentifier"];
            NSString *name = [proxy valueForKey:@"localizedName"];
            NSString *key = [NSString stringWithFormat:@"%@ %@", bid ?: @"", name ?: @""].lowercaseString;
            if ([bid isEqualToString:@"com.google.ios.youtube"] || [key containsString:@"vietmap"]) {
                if (bid.length && name.length) [targets addObject:@{@"id":bid, @"name":name}];
            }
        }
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Chọn app gốc" message:targets.count ? @"Ứng dụng đã cài trên thiết bị" : @"Không tìm thấy YouTube hoặc VIETMAP. Hãy cài ứng dụng rồi thử lại." preferredStyle:UIAlertControllerStyleAlert];
        for (NSDictionary *app in targets) {
            [picker addAction:[UIAlertAction actionWithTitle:app[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                for (SP2LivePane *other in self.panes) {
                    if (other != pane && [other.currentBundleID isEqualToString:app[@"id"]]) {
                        [pane showStatus:@"Ứng dụng này đang ở ô còn lại"];
                        return;
                    }
                }
                @try { [pane embedNativeAppWithBundleID:app[@"id"] name:app[@"name"] icon:nil]; }
                @catch (NSException *exception) { [pane showStatus:[NSString stringWithFormat:@"Lỗi khởi chạy: %@", exception.name]]; }
            }]];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:picker animated:YES completion:nil];
    } @catch (NSException *exception) { [pane showStatus:[NSString stringWithFormat:@"Lỗi quét app: %@", exception.name]]; }
}
- (void)closeTest {
    for (SP2LivePane *pane in self.panes) {
        @try { [pane closeTap]; } @catch (NSException *exception) { NSLog(@"[XYT native] close: %@", exception.name); }
    }
    if (self.onClose) self.onClose();
}
@end

static UIWindow *XYTNativeWindow;
static int XYTNativeNotifyToken;

__attribute__((constructor)) static void XYTInstallNativeTest(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        notify_register_dispatch("com.xemyoutube.native-test.open", &XYTNativeNotifyToken, dispatch_get_main_queue(), ^(int token) {
            if (XYTNativeWindow) return;
            UIWindowScene *scene = nil;
            for (UIScene *candidate in [UIApplication sharedApplication].connectedScenes) {
                if ([candidate isKindOfClass:[UIWindowScene class]] && candidate.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)candidate;
                    break;
                }
            }
            if (!scene) { NSLog(@"[XYT native] no foreground UIWindowScene"); return; }
            XYTNativeTestController *controller = [XYTNativeTestController new];
            controller.onClose = ^{
                XYTNativeWindow.hidden = YES;
                XYTNativeWindow.rootViewController = nil;
                XYTNativeWindow = nil;
            };
            XYTNativeWindow = [[UIWindow alloc] initWithWindowScene:scene];
            XYTNativeWindow.windowLevel = UIWindowLevelAlert + 1;
            XYTNativeWindow.rootViewController = controller;
            [XYTNativeWindow makeKeyAndVisible];
        });
    }
}

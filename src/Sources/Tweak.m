#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>

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

- (void)closeTap {
    if (self.activePresenter && [self.activePresenter respondsToSelector:@selector(invalidate)]) {
        [self.activePresenter invalidate];
    }
    self.activePresenter = nil;
    self.currentBundleID = nil;
    for (UIView *sub in self.sceneHostContainer.subviews) {
        if (sub.tag != 999) [sub removeFromSuperview];
    }
    [self.titleBtn setTitle:@" + Tab mới ⌄" forState:UIControlStateNormal];
}

- (void)embedNativeAppWithBundleID:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon {
    if (!bundleID) return;
    self.currentBundleID = bundleID;
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
                    [self attachSceneWithRetry:0];
                });
            }];
            return;
        }
    }
    [self attachSceneWithRetry:0];
}

- (void)attachSceneWithRetry:(NSInteger)attempt {
    if (!self.currentBundleID) return;
    Class mgrCls = NSClassFromString(@"FBSceneManager");
    if (!mgrCls || ![mgrCls respondsToSelector:@selector(sharedInstance)]) return;

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
                [self attachSceneWithRetry:attempt + 1];
            });
        }
        return;
    }

    // Ep FBScene cua App Goc luon o che do Foreground va render theo kich thuoc that
    CGRect targetBounds = self.sceneHostContainer.bounds.size.width > 20 ? self.sceneHostContainer.bounds : CGRectMake(0, 0, 375, 667);
    CGFloat scaleFactor = targetBounds.size.width / 375.0;
    CGRect fullPhoneRect = CGRectMake(0, 0, 375, MAX(targetBounds.size.height / MAX(scaleFactor, 0.35), 600));

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

    id presMgr = [matchedScene uiPresentationManager];
    if ([presMgr respondsToSelector:@selector(createPresenterWithIdentifier:)]) {
        NSString *pid = [NSString stringWithFormat:@"SP2LivePane-%ld-%u", (long)self.paneIndex, arc4random_uniform(9999)];
        id presenter = [presMgr createPresenterWithIdentifier:pid];
        if ([presenter respondsToSelector:@selector(activate)]) {
            [presenter activate];
            UIView *liveView = [presenter presentationView];
            if (liveView) {
                for (UIView *sub in self.sceneHostContainer.subviews) {
                    if (sub.tag != 999) [sub removeFromSuperview];
                }
                liveView.bounds = fullPhoneRect;
                liveView.center = CGPointMake(targetBounds.size.width / 2.0, targetBounds.size.height / 2.0);
                liveView.transform = CGAffineTransformMakeScale(scaleFactor, scaleFactor);
                [self.sceneHostContainer addSubview:liveView];
                self.activePresenter = presenter;
            }
        }
    }
}

- (void)refreshSceneFrame {
    if (self.currentBundleID) {
        [self attachSceneWithRetry:5];
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
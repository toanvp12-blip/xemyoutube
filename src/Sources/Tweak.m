#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Tweak nap vao SpringBoard de giu cac ung dung duoc chon chay song song foreground
__attribute__((constructor))
static void XemYouTubeSpringBoardInit(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

    [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.xemyoutube.launchBackgroundScene"
                                                                 object:nil
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification *note) {
        NSString *targetBundle = note.userInfo[@"bundleID"];
        if (!targetBundle) return;
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) {
            id ws = [wsClass performSelector:@selector(defaultWorkspace)];
            SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
            if ([ws respondsToSelector:openSel]) {
                ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSel, targetBundle);
            }
        }
    }];
}
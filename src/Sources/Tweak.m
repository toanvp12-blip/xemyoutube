#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void LaunchRequestedAppCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.xemyoutube.ipc.plist"];
            NSString *targetBundle = prefs[@"targetBundleID"];
            if (!targetBundle || targetBundle.length == 0) return;

            Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
            if (wsClass) {
                id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
                SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
                if ([ws respondsToSelector:openSel]) {
                    ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSel, targetBundle);
                }
            }
        } @catch (NSException *e) {}
    });
}

__attribute__((constructor))
static void XemYouTubeSpringBoardInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || ![bundleID isEqualToString:@"com.apple.springboard"]) return;

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            LaunchRequestedAppCallback,
            CFSTR("com.xemyoutube.darwin.launchapp"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
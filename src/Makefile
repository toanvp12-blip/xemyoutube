TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard XemYouTube

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XemYouTube
XemYouTube_FILES = Sources/main.m
XemYouTube_FRAMEWORKS = UIKit Foundation WebKit CarPlay CoreLocation QuartzCore CoreFoundation
XemYouTube_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-value
XemYouTube_CODESIGN_FLAGS = -Sentitlements.plist

TWEAK_NAME = XemYouTubeSB
XemYouTubeSB_FILES = Sources/Tweak.m
XemYouTubeSB_FRAMEWORKS = UIKit Foundation CoreFoundation
XemYouTubeSB_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk
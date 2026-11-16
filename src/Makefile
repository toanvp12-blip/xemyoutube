TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = XemYouTube

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XemYouTube
XemYouTube_FILES = Sources/main.m
XemYouTube_FRAMEWORKS = UIKit Foundation WebKit CarPlay CoreLocation
XemYouTube_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
XemYouTube_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
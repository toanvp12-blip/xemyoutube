TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XemYouTube
XemYouTube_FILES = $(wildcard Sources/*.swift)
XemYouTube_FRAMEWORKS = UIKit SwiftUI CarPlay WebKit CoreLocation
XemYouTube_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
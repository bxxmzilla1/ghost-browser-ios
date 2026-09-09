export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Heavenzy
Heavenzy_FILES = Tweak.xm GBStore.m GBMenu.m GBBundle.m GBFloatingButton.m
Heavenzy_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Heavenzy_FRAMEWORKS = UIKit Foundation Security WebKit SafariServices CoreGraphics
Heavenzy_WEAK_FRAMEWORKS = AdSupport

include $(THEOS)/makefiles/tweak.mk

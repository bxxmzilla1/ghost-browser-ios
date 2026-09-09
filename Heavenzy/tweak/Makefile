export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Heavenzy
Heavenzy_FILES = Tweak.xm GBStore.m GBMenu.m GBFloatingButton.m GBTokens.m GBBundleSocial.m ../common/HZDevice.m ../common/HZConfig.m
Heavenzy_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I../common
Heavenzy_FRAMEWORKS = UIKit Foundation Security WebKit CoreGraphics CoreFoundation
Heavenzy_WEAK_FRAMEWORKS = AdSupport DeviceCheck CoreTelephony

include $(THEOS)/makefiles/tweak.mk

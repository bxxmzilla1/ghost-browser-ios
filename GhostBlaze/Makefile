export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GhostBlaze
GhostBlaze_FILES = Tweak.xm GBStore.m GBMenu.m
GhostBlaze_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
GhostBlaze_FRAMEWORKS = UIKit Foundation Security WebKit CFNetwork
GhostBlaze_WEAK_FRAMEWORKS = AdSupport

include $(THEOS)/makefiles/tweak.mk

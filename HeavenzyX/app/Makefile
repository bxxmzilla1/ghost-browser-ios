export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Heavenzy

Heavenzy_FILES = main.m HZAppDelegate.m HZTheme.m HZAppListViewController.m HZAppDetailViewController.m HZAppToolsViewController.m HZAppData.m HZSettingsViewController.m HZContainerSync.m ../common/HZDevice.m ../common/HZConfig.m
Heavenzy_FRAMEWORKS = UIKit Foundation QuartzCore
Heavenzy_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I../common
Heavenzy_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS)/makefiles/application.mk

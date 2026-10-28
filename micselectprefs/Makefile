TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MicSelectPrefs
MicSelectPrefs_FILES = MSPRootListController.m
MicSelectPrefs_FRAMEWORKS = UIKit AVFoundation
MicSelectPrefs_PRIVATE_FRAMEWORKS = Preferences
MicSelectPrefs_INSTALL_PATH = /Library/PreferenceBundles
MicSelectPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

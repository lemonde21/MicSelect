TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MicSelect
MicSelect_FILES = Tweak.x
MicSelect_CFLAGS = -fobjc-arc
MicSelect_FRAMEWORKS = AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += micselctl micselectprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

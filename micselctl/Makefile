TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = micsel
micsel_FILES = main.m
micsel_CFLAGS = -fobjc-arc
micsel_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk

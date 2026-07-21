export TARGET = iphone:clang:latest:16.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard Maps
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = gpsq

gpsq_FILES = gpsq.mm
gpsq_FRAMEWORKS = UIKit Foundation CoreLocation MapKit QuartzCore
gpsq_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
gpsq_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk

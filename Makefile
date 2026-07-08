ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Maps
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GPS
GPS_FILES = Sources/GPS.mm Sources/GPSApiClient.mm
GPS_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
GPS_CCFLAGS = -std=c++17
GPS_FRAMEWORKS = UIKit Foundation CoreLocation MapKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

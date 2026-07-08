export TARGET = iphone:clang:latest:13.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KSA

KSA_FILES = KSA.mm
KSA_FRAMEWORKS = UIKit CoreLocation MapKit CoreBluetooth CoreGraphics Security SystemConfiguration
KSA_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

# Chirpie - unofficial X / Twitter reader for jailbroken iOS, with its own TLS stack.
# One source tree, two packages (Theos):
#   make package                               armv7 for iOS 6.x (the iOS 9.3 SDK, deployment target 6.0)
#   make package THEOS_PACKAGE_SCHEME=rootless arm64 for iOS 14-17 (the iOS 16.5 SDK, deployment target 14.0):
#                                              the .deb for rootless jailbreaks, the IPA for TrollStore
# (`make clean` between the two; CI builds both, see .github/workflows/build.yml)

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
endif
DEBUG ?= 0

THEOS_DEVICE_IP ?= 192.168.1.176
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Chirpie

Chirpie_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) \
               vendor/mbedtls_glue.c \
               $(wildcard vendor/mbedtls/library/*.c)

Chirpie_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore CoreText Security ImageIO AVFoundation CoreMedia MediaPlayer AudioToolbox

Chirpie_CFLAGS := -Isrc -Isrc/Net -Isrc/Twitter -Isrc/UI -Isrc/Util \
                -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                -Os -fvisibility=hidden \
                -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-unused-parameter \
                -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

Chirpie_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

Chirpie_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk

CHIRPIE_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/Chirpie.app
CHIRPIE_STAGED_BIN := $(CHIRPIE_STAGED_APP)/Chirpie

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(CHIRPIE_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements-arm64.xml" "$(CHIRPIE_STAGED_BIN)"
before-package::
	sed -i -e 's/^Depends: .*/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/Chirpie.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
else
# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. The app avoids those classes; should the linker still record
# CFNetwork, the load command is pointed at Foundation (harmless when there is none), then the binary is signed again.
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(CHIRPIE_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(CHIRPIE_STAGED_BIN)"
endif

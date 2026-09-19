TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = dylibtest

dylibtest_FILES = Tweak.x MyGoldAPI.mm
dylibtest_CFLAGS = -fobjc-arc
dylibtest_LIBRARIES = z
dylibtest_FRAMEWORKS = UIKit Foundation
# Assets visuais usados pelo menu UIKit
dylibtest_RESOURCES = Resources/Debrosee-ALPnL.ttf Resources/profile-reference.jpg

include $(THEOS_MAKE_PATH)/library.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/dylibtest"
	@cp Resources/Debrosee-ALPnL.ttf "$(THEOS_STAGING_DIR)/Library/Application Support/dylibtest/Debrosee-ALPnL.ttf"
	@cp Resources/profile-reference.jpg "$(THEOS_STAGING_DIR)/Library/Application Support/dylibtest/profile-reference.jpg"

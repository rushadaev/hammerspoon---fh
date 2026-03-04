# FunnyHow Build Makefile

# Project settings
PROJECT = Hammerspoon.xcodeproj
SCHEME = Hammerspoon
CONFIG = Release
BUILD_DIR = build

# Derived paths
APP_NAME = Funny How.app
ARCHIVE_PATH = $(BUILD_DIR)/FunnyHow.xcarchive
EXPORT_PATH = $(BUILD_DIR)/export

.PHONY: all clean build archive export-unsigned export-signed help

help:
	@echo "FunnyHow Build Commands:"
	@echo "  make build          - Build the app (Debug)"
	@echo "  make release        - Build the app (Release)"
	@echo "  make archive        - Create Xcode archive"
	@echo "  make export-unsigned - Export unsigned app (for testing)"
	@echo "  make clean          - Clean build directory"
	@echo ""
	@echo "For distribution, use 'make archive' then sign in Xcode."

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

archive:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release archive -archivePath $(ARCHIVE_PATH)
	@echo ""
	@echo "Archive created at: $(ARCHIVE_PATH)"
	@echo "Open in Xcode to sign and export: open $(ARCHIVE_PATH)"

export-unsigned:
	@mkdir -p $(EXPORT_PATH)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CONFIGURATION_BUILD_DIR=$(EXPORT_PATH) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		build
	@echo ""
	@echo "Unsigned app built at: $(EXPORT_PATH)/$(APP_NAME)"
	@echo "NOTE: This is for local testing only. Not distributable."

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	@echo "Build directory cleaned"

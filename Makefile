# FunnyHow Build Makefile

# Project settings
WORKSPACE = FunnyHow.xcworkspace
SCHEME = FunnyHow
CONFIG = Release
BUILD_DIR = build

# Derived paths
APP_NAME = Funny How.app
ARCHIVE_PATH = $(BUILD_DIR)/FunnyHow.xcarchive
EXPORT_PATH = $(BUILD_DIR)/export

.PHONY: all clean clean-all rebuild rebuild-unsigned build archive export-unsigned export-signed dmg help

help:
	@echo "FunnyHow Build Commands:"
	@echo "  make build          - Build the app (Debug)"
	@echo "  make release        - Build the app (Release)"
	@echo "  make archive        - Create Xcode archive"
	@echo "  make export-unsigned - Export unsigned app (for testing)"
	@echo "  make clean          - Clean build directory"
	@echo "  make clean-all      - Remove everything (app, configs, caches, logs)"
	@echo "  make rebuild        - Clean everything and rebuild fresh (signed)"
	@echo "  make rebuild-unsigned - Clean everything and rebuild unsigned (for testing)"
	@echo "  make dmg              - Create signed DMG for distribution"
	@echo ""
	@echo "For distribution: 'make dmg' (requires Developer ID certificate in Xcode)"

build:
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Debug build

release:
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Release build

archive:
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Release archive -archivePath $(ARCHIVE_PATH)
	@echo ""
	@echo "Archive created at: $(ARCHIVE_PATH)"
	@echo "Open in Xcode to sign and export: open $(ARCHIVE_PATH)"

export-unsigned:
	@echo "Building unsigned app (using default DerivedData)..."
	@xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Debug \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		ENABLE_ADDRESS_SANITIZER=NO \
		ENABLE_THREAD_SANITIZER=NO \
		ENABLE_UNDEFINED_BEHAVIOR_SANITIZER=NO \
		build | grep -E '^\*\*|BUILD|error:|warning:' || true
	@echo ""
	@echo "Copying app to build directory..."
	@mkdir -p $(EXPORT_PATH)
	@cp -R ~/Library/Developer/Xcode/DerivedData/FunnyHow-*/Build/Products/Debug/"$(APP_NAME)" $(EXPORT_PATH)/ 2>/dev/null || \
		(echo "Error: Could not find built app. Build may have failed." && exit 1)
	@echo "Copying FunnyHow module..."
	@mkdir -p "$(EXPORT_PATH)/$(APP_NAME)/Contents/Resources/extensions/hs/funnyhow"
	@cp -R extensions/funnyhow/* "$(EXPORT_PATH)/$(APP_NAME)/Contents/Resources/extensions/hs/funnyhow/"
	@echo "✅ FunnyHow module copied to extensions/hs/funnyhow/"
	@echo ""
	@echo "✅ Unsigned app built at: $(EXPORT_PATH)/$(APP_NAME)"
	@echo "NOTE: This is for local testing only. Not distributable."

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) clean
	@echo "Build directory cleaned"

clean-all:
	@echo "🧹 Cleaning everything..."
	@echo "Stopping running FunnyHow process..."
	@pkill -x "Funny How" || true
	@echo "Removing installed app..."
	@rm -rf "/Applications/Funny How.app" || true
	@echo "Removing built app in repo..."
	@rm -rf "Funny How.app" || true
	@echo "Removing build directory..."
	@rm -rf $(BUILD_DIR) || true
	@echo "Removing runtime config..."
	@rm -rf ~/.funny-how || true
	@echo "Removing application support..."
	@rm -rf ~/Library/Application\ Support/FunnyHow || true
	@echo "Removing caches..."
	@rm -rf ~/Library/Caches/com.funnyhow.* || true
	@echo "Removing preferences..."
	@rm -rf ~/Library/Preferences/com.funnyhow.* || true
	@echo "Removing logs..."
	@rm -rf /tmp/funnyhow*.log || true
	@echo "Running xcodebuild clean..."
	@xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) clean || true
	@echo "✅ Everything cleaned!"

rebuild: clean-all
	@echo ""
	@echo "🔨 Building fresh release..."
	@$(MAKE) release
	@echo ""
	@echo "✅ Rebuild complete!"

rebuild-unsigned: clean-all
	@echo ""
	@echo "🔨 Building fresh unsigned build for testing..."
	@$(MAKE) export-unsigned
	@echo ""
	@echo "✅ Unsigned rebuild complete!"

dmg:
	@echo "📦 Building signed DMG for distribution..."
	@echo ""
	@echo "Step 1: Building Release version..."
	@xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Release \
		ENABLE_ADDRESS_SANITIZER=NO \
		ENABLE_THREAD_SANITIZER=NO \
		ENABLE_UNDEFINED_BEHAVIOR_SANITIZER=NO \
		build | grep -E '^\*\*|BUILD|error:|warning:' || true
	@echo ""
	@echo "Step 2: Copying app..."
	@mkdir -p $(EXPORT_PATH)
	@cp -R ~/Library/Developer/Xcode/DerivedData/FunnyHow-*/Build/Products/Release/"$(APP_NAME)" $(EXPORT_PATH)/ 2>/dev/null || \
		(echo "❌ Error: Could not find built app" && exit 1)
	@echo "Step 3: Copying FunnyHow module..."
	@mkdir -p "$(EXPORT_PATH)/$(APP_NAME)/Contents/Resources/extensions/hs/funnyhow"
	@cp -R extensions/funnyhow/* "$(EXPORT_PATH)/$(APP_NAME)/Contents/Resources/extensions/hs/funnyhow/"
	@echo "Step 4: Creating DMG..."
	@rm -f "$(BUILD_DIR)/FunnyHow.dmg"
	@hdiutil create -volname "Funny How" -srcfolder "$(EXPORT_PATH)/$(APP_NAME)" -ov -format UDZO "$(BUILD_DIR)/FunnyHow.dmg"
	@echo ""
	@echo "✅ DMG created at: $(BUILD_DIR)/FunnyHow.dmg"
	@echo ""
	@echo "Next steps:"
	@echo "1. Verify code signature: codesign -dv --verbose=4 '$(EXPORT_PATH)/$(APP_NAME)'"
	@echo "2. Notarize with Apple (recommended): xcrun notarytool submit"
	@echo "3. Distribute: $(BUILD_DIR)/FunnyHow.dmg"

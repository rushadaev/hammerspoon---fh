#!/bin/bash
# Deep sign all components for notarization

set -e

APP_PATH="$1"
IDENTITY="Developer ID Application: Aleksei Khrishchatyi (X2K2WW6UUG)"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 <path-to-app>"
    exit 1
fi

echo "🔐 Signing all frameworks and binaries for notarization..."
echo "App: $APP_PATH"
echo "Identity: $IDENTITY"
echo ""

# Find and sign all .dylib files
echo "Signing .dylib files..."
find "$APP_PATH" -type f -name "*.dylib" | while read dylib; do
    echo "  - $(basename "$dylib")"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$dylib" 2>/dev/null || true
done

# Sign all executables in Frameworks
echo ""
echo "Signing framework executables..."
find "$APP_PATH/Contents/Frameworks" -type f -perm +111 | while read exec; do
    echo "  - $(basename "$exec")"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$exec" 2>/dev/null || true
done

# Sign all .app bundles inside (like Sparkle's Updater.app)
echo ""
echo "Signing embedded .app bundles..."
find "$APP_PATH/Contents/Frameworks" -type d -name "*.app" | while read app; do
    echo "  - $(basename "$app")"
    codesign --force --deep --timestamp --options runtime --sign "$IDENTITY" "$app" 2>/dev/null || true
done

# Sign all frameworks
echo ""
echo "Signing frameworks..."
find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" | while read framework; do
    echo "  - $(basename "$framework")"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$framework" 2>/dev/null || true
done

# Finally, sign the main app
echo ""
echo "Signing main app bundle..."
codesign --force --deep --timestamp --options runtime --sign "$IDENTITY" "$APP_PATH"

echo ""
echo "✅ Signing complete!"
echo ""
echo "Verifying signature..."
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|Identifier|Timestamp"

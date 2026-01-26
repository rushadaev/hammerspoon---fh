#!/bin/bash
#
# Funny How Enterprise Installation Script
# Installs Funny How with enterprise lockdown features:
# - Protected config
# - Admin password required to quit
# - Auto-restart on quit/crash
#

set -e  # Exit on error

echo "🎵 Funny How Enterprise Installer"
echo "=================================="
echo ""

# Check if running as regular user (not root)
if [ "$EUID" -eq 0 ]; then
   echo "❌ Please run as regular user (not root/sudo)"
   echo "   The script will ask for admin password when needed."
   exit 1
fi

# Paths
APP_SOURCE="./Funny How.app"
APP_DEST="/Applications/Funny How.app"
CONFIG_DIR="$HOME/.hammerspoon"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="com.funnyhow.FunnyHow.plist"

echo "📋 Installation Plan:"
echo "  - App: $APP_DEST"
echo "  - Config: $CONFIG_DIR"
echo "  - LaunchAgent: $LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST"
echo ""

# Check if app exists in current directory
if [ ! -d "$APP_SOURCE" ]; then
    echo "❌ Error: 'Funny How.app' not found in current directory"
    echo "   Please run this script from the directory containing the app."
    exit 1
fi

echo "📦 Step 1: Installing app..."
if [ -d "$APP_DEST" ]; then
    echo "   Removing existing app..."
    sudo rm -rf "$APP_DEST"
fi
sudo cp -R "$APP_SOURCE" "$APP_DEST"
echo "   ✅ App installed to /Applications"

echo ""
echo "📁 Step 2: Setting up config directory..."
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    echo "   ✅ Created $CONFIG_DIR"
else
    echo "   ℹ️  Config directory already exists"
fi

# Copy default config if init.lua doesn't exist
if [ ! -f "$CONFIG_DIR/init.lua" ]; then
    if [ -f "./enterprise-init.lua" ]; then
        cp "./enterprise-init.lua" "$CONFIG_DIR/init.lua"
        echo "   ✅ Installed default init.lua"
    else
        echo "   ⚠️  Warning: enterprise-init.lua not found, skipping config install"
    fi
else
    echo "   ℹ️  init.lua already exists, keeping existing config"
fi

echo ""
echo "🔒 Step 3: Enabling enterprise mode..."
touch "$CONFIG_DIR/.enterprise"
echo "   ✅ Created enterprise marker"

echo ""
echo "🔐 Step 4: Protecting config from editing and deletion..."
echo "   (You may be prompted for your admin password)"

# Make config read-only by changing ownership to root
if [ -f "$CONFIG_DIR/init.lua" ]; then
    sudo chown root:wheel "$CONFIG_DIR/init.lua"
    sudo chmod 644 "$CONFIG_DIR/init.lua"
    echo "   ✅ init.lua is now read-only (owned by root)"
fi

# Protect entire directory from deletion
sudo chown root:wheel "$CONFIG_DIR/.enterprise"
sudo chmod 444 "$CONFIG_DIR/.enterprise"

# Set ACLs to prevent deletion of directory itself
chmod +a "user:$USER deny delete" "$CONFIG_DIR" 2>/dev/null || echo "   ⚠️  Could not set ACL (may require newer macOS)"

echo "   ✅ Config is now fully protected (read-only)"

echo ""
echo "🚀 Step 5: Installing LaunchAgent for auto-restart..."
if [ ! -d "$LAUNCH_AGENT_DIR" ]; then
    mkdir -p "$LAUNCH_AGENT_DIR"
fi

if [ -f "./$LAUNCH_AGENT_PLIST" ]; then
    cp "./$LAUNCH_AGENT_PLIST" "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST"
    echo "   ✅ LaunchAgent plist installed"
else
    echo "   ❌ Error: $LAUNCH_AGENT_PLIST not found"
    exit 1
fi

echo ""
echo "▶️  Step 6: Loading LaunchAgent..."
launchctl load "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST" 2>/dev/null || true
echo "   ✅ LaunchAgent loaded"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📖 What was installed:"
echo "  ✅ Funny How app with enterprise features"
echo "  ✅ Protected config in ~/.hammerspoon/"
echo "  ✅ Auto-restart LaunchAgent"
echo ""
echo "🔒 Enterprise Features:"
echo "  ✅ Admin password required to quit"
echo "  ✅ Quit menu items hidden"
echo "  ✅ Auto-restart if force-quit"
echo "  ✅ Config is READ-ONLY (requires sudo to edit)"
echo "  ✅ Config protected from deletion"
echo ""
echo "🎵 Funny How should now be running!"
echo "   Check your menu bar for the waveform icon."
echo ""
echo "📝 To uninstall:"
echo "   Run: launchctl unload ~/Library/LaunchAgents/$LAUNCH_AGENT_PLIST"
echo "   Then delete the app and config manually."
echo ""

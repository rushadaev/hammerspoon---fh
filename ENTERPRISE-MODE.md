# Funny How Enterprise Mode 🔒

## Overview

Funny How now includes **enterprise lockdown features** for recording studio environments where the app needs to run continuously and cannot be easily closed or modified by users.

## Features

### ✅ What's Protected:

1. **Admin Password to Quit**
   - Users must enter an admin password to quit the app
   - Works for both Cmd+Q and menu quit
   - Quit menu items are hidden in enterprise mode

2. **Protected Configuration**
   - Config files in `~/.hammerspoon/` cannot be deleted by regular users
   - ACL (Access Control List) permissions prevent deletion
   - Users can still modify config, but cannot remove it

3. **Auto-Restart**
   - App automatically restarts if force-quit from Activity Monitor
   - App automatically restarts if it crashes
   - Uses macOS LaunchAgent with KeepAlive

4. **Launch at Login**
   - App starts automatically when user logs in
   - Cannot be disabled through System Preferences

---

## How It Works

### Enterprise Mode Detection

The app checks for a marker file:
```
~/.hammerspoon/.enterprise
```

If this file exists, enterprise mode is activated automatically.

### Code Changes Made

**Files Modified:**
1. `Hammerspoon/MJAppDelegate.h` - Added `enterpriseMode` property
2. `Hammerspoon/MJAppDelegate.m` - Added enterprise detection and quit protection

**Security Framework:**
- Uses macOS `Security.framework` for admin authentication
- `AuthorizationCreate()` and `AuthorizationCopyRights()` APIs

---

## Installation

### Quick Install (Recommended)

1. **Build the app:**
   ```bash
   cd /Users/beilec/XCODE/hammerspoon---fh
   xcodebuild -workspace FunnyHow.xcworkspace -scheme FunnyHow -configuration Debug build
   ```

2. **Copy app to distribution folder:**
   ```bash
   cp -R "/Users/beilec/Library/Developer/Xcode/DerivedData/FunnyHow-fnrfpxdkyfxaawhjmnbovandeioc/Build/Products/Debug/Funny How.app" .
   ```

3. **Run the enterprise installer:**
   ```bash
   ./install-enterprise.sh
   ```

The installer will:
- Install app to `/Applications/`
- Create `~/.hammerspoon/` directory
- Install default `init.lua` config
- Create `.enterprise` marker file
- Set ACL permissions
- Install and load LaunchAgent

### Manual Installation

If you prefer to install manually:

```bash
# 1. Install the app
sudo cp -R "Funny How.app" "/Applications/"

# 2. Create config directory
mkdir -p ~/.hammerspoon

# 3. Copy default config (optional)
cp enterprise-init.lua ~/.hammerspoon/init.lua

# 4. Enable enterprise mode
touch ~/.hammerspoon/.enterprise

# 5. Protect config from deletion
chmod +a "user:$USER deny delete" ~/.hammerspoon
chmod +a "user:$USER deny delete" ~/.hammerspoon/init.lua

# 6. Install LaunchAgent
cp com.funnyhow.FunnyHow.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist
```

---

## Testing Enterprise Mode

### Test 1: Verify Enterprise Mode is Active

```bash
# Check if marker file exists
ls -la ~/.hammerspoon/.enterprise

# Launch app and check Console.app for:
# "🔒 Enterprise mode enabled"
```

### Test 2: Try to Quit

1. Press `Cmd+Q` or use menu → should ask for admin password
2. Cancel the password dialog → app should NOT quit
3. Enter correct admin password → app should quit

### Test 3: Verify Auto-Restart

1. Open Activity Monitor
2. Find "Funny How" process
3. Force Quit it
4. Wait 5-10 seconds → app should restart automatically

### Test 4: Try to Delete Config

```bash
# This should fail with permission denied:
rm ~/.hammerspoon/init.lua
# Output: rm: ~/.hammerspoon/init.lua: Operation not permitted
```

### Test 5: Verify Quit Menu Hidden

1. Launch app
2. Click menu bar icon (waveform)
3. "Quit Funny How" menu item should NOT be visible

---

## Uninstalling Enterprise Mode

### Complete Removal:

```bash
# 1. Unload LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist

# 2. Remove LaunchAgent
rm ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist

# 3. Remove ACL permissions
chmod -a "user:$USER deny delete" ~/.hammerspoon 2>/dev/null
chmod -a "user:$USER deny delete" ~/.hammerspoon/init.lua 2>/dev/null

# 4. Remove enterprise marker
rm ~/.hammerspoon/.enterprise

# 5. Remove app
sudo rm -rf "/Applications/Funny How.app"
```

### Disable Enterprise Mode Only (Keep App):

```bash
# Just remove the marker file:
rm ~/.hammerspoon/.enterprise

# App will run in normal mode after relaunch
```

---

## Distribution

### Creating Installer Package

You can distribute the enterprise setup to multiple machines:

**Package Contents:**
```
FunnyHow-Enterprise/
├── Funny How.app
├── com.funnyhow.FunnyHow.plist
├── enterprise-init.lua
├── install-enterprise.sh
└── ENTERPRISE-MODE.md (this file)
```

**Distribution Methods:**
1. **ZIP Archive** - Simple distribution
2. **.pkg Installer** - Professional macOS installer
3. **MDM Deployment** - Enterprise device management

---

## Security Considerations

### What CAN Be Prevented:
✅ Normal quit (Cmd+Q, menu)
✅ Config file deletion (ACLs)
✅ Disabling auto-launch
✅ App staying closed after force-quit

### What CANNOT Be Prevented:
❌ Admin user with root access
❌ Booting into Recovery Mode
❌ System shutdown/restart
❌ Uninstalling LaunchAgent (requires admin, but possible)

### Intended Use:
This is designed for **studio/kiosk environments** where:
- Users are not admins
- App needs to run continuously
- Accidental closes must be prevented

This is **NOT** absolute security. An admin user can always remove these protections.

---

## Troubleshooting

### App Not Starting Automatically

```bash
# Check LaunchAgent status
launchctl list | grep funnyhow

# Reload LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist
launchctl load ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist
```

### App Not Restarting After Force Quit

```bash
# Check LaunchAgent logs
tail -f /tmp/funnyhow.log
tail -f /tmp/funnyhow-error.log
```

### Password Dialog Not Appearing

Make sure Security.framework is properly linked:
```bash
# Check if framework is present
otool -L "/Applications/Funny How.app/Contents/MacOS/Funny How" | grep Security
```

### Cannot Delete Config (Need to Update)

If you need to update the config and ACLs are blocking you:

```bash
# Temporarily remove ACL
chmod -a "user:$USER deny delete" ~/.hammerspoon/init.lua

# Make your changes
nano ~/.hammerspoon/init.lua

# Re-add ACL
chmod +a "user:$USER deny delete" ~/.hammerspoon/init.lua
```

---

## Technical Details

### LaunchAgent Configuration

**File:** `~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist`

```xml
<key>KeepAlive</key>
<dict>
    <key>SuccessfulExit</key>
    <false/>  <!-- Restart even if app exits normally -->
    <key>Crashed</key>
    <true/>   <!-- Restart if app crashes -->
</dict>
```

### Authorization API

The quit protection uses macOS Authorization Services:

```objective-c
AuthorizationCreate()  // Create auth session
AuthorizationCopyRights()  // Request admin rights
AuthorizationFree()  // Clean up
```

### ACL Permissions

Access Control Lists prevent deletion:

```bash
# View ACLs
ls -led ~/.hammerspoon/init.lua

# Output shows:
# 0: user:username deny delete
```

---

## Changelog

### Version 1.0 (2026-01-23)
- ✅ Initial enterprise mode implementation
- ✅ Admin password quit protection
- ✅ Config deletion protection via ACLs
- ✅ Auto-restart via LaunchAgent
- ✅ Enterprise marker detection
- ✅ Hidden quit menu items
- ✅ Installation script
- ✅ Default studio config

---

## Support

For issues or questions about enterprise mode:
1. Check the console logs for "🔒" emoji
2. Review LaunchAgent logs in `/tmp/funnyhow*.log`
3. Verify enterprise marker exists: `~/.hammerspoon/.enterprise`

---

**Built with ❤️ for Recording Studios**

🎵 Funny How - Your Studio Automation Hub

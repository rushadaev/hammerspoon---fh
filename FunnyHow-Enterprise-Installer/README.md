# Funny How - Enterprise Installer 🎵

## Quick Start

**Install in 2 steps:**

1. Open Terminal in this folder
2. Run: `./install-enterprise.sh`

That's it! The app will be installed with enterprise lockdown features.

---

## What Gets Installed

✅ **Funny How.app** - Recording studio automation tool
✅ **Enterprise Lockdown** - Admin password required to quit
✅ **Protected Config** - Read-only configuration (requires sudo to edit)
✅ **Auto-Restart** - App automatically restarts if force-quit
✅ **Launch at Login** - Starts automatically when user logs in

---

## Enterprise Features

### 🔒 Admin Password to Quit
- Users must enter admin password to quit
- Quit menu items are hidden
- Prevents accidental closures

### 📁 Read-Only Config
- Config file owned by root
- Users cannot edit without `sudo`
- Users cannot delete the config
- Perfect for studio environments

### 🔄 Auto-Restart
- App restarts if force-quit
- App restarts if it crashes
- Always running

### 🚀 Launch at Login
- Starts automatically
- Cannot be disabled via System Preferences

---

## Installation

### Automatic (Recommended)

```bash
./install-enterprise.sh
```

The script will:
1. Install app to /Applications
2. Create protected config in ~/.hammerspoon/
3. Set up auto-restart LaunchAgent
4. Enable enterprise mode

You'll be prompted for your admin password.

---

## Files in This Package

| File | Description |
|------|-------------|
| **Funny How.app** | The application |
| **install-enterprise.sh** | Automatic installer |
| **com.funnyhow.FunnyHow.plist** | LaunchAgent for auto-restart |
| **enterprise-init.lua** | Default protected config |
| **ENTERPRISE-MODE.md** | Full documentation |
| **README.md** | This file |

---

## After Installation

### The app should launch automatically!

Look for the **waveform icon** (🎵) in your menu bar.

### To edit the config:

```bash
sudo nano ~/.hammerspoon/init.lua
```

The config is read-only and requires admin privileges.

### To test enterprise features:

1. **Try to quit** (Cmd+Q) → Should ask for password
2. **Try to edit config** without sudo → Should fail
3. **Force quit** from Activity Monitor → Should restart automatically

---

## Uninstalling

To completely remove:

```bash
# Unload LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist

# Remove files
rm ~/Library/LaunchAgents/com.funnyhow.FunnyHow.plist
sudo rm -rf "/Applications/Funny How.app"
sudo rm ~/.hammerspoon/.enterprise
sudo chown $USER ~/.hammerspoon/init.lua
```

---

## Documentation

For complete documentation, see **ENTERPRISE-MODE.md**

Topics covered:
- How enterprise mode works
- Manual installation
- Testing procedures
- Troubleshooting
- Security considerations

---

## System Requirements

- macOS 13.0 or later
- Admin privileges for installation
- ~20 MB disk space

---

## Support

Check the console logs for troubleshooting:
```bash
# LaunchAgent logs
tail -f /tmp/funnyhow.log
tail -f /tmp/funnyhow-error.log

# System logs
log show --predicate 'process == "Funny How"' --last 10m
```

---

**Built for Recording Studios**
🎵 Funny How - Studio Automation Hub

Version: 1.0 (Enterprise Edition)

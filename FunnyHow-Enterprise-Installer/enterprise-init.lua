-- Funny How Enterprise Configuration
-- Recording Studio Edition
--
-- This config is protected and managed by your administrator.
-- Changes made here will persist, but the file cannot be deleted.

hs.hotkey.alertDuration = 0
hs.hints.showTitleThresh = 0

-- Welcome message
hs.alert.show("🎵 Funny How Studio - Ready", 2)

-- Example: Reload config (Cmd+Alt+R)
hs.hotkey.bind({"cmd", "alt"}, "R", function()
    hs.reload()
end)

-- Example: Show console (Cmd+Alt+C)
hs.hotkey.bind({"cmd", "alt"}, "C", function()
    hs.toggleConsole()
end)

-- Add your studio automation scripts below
-- ==========================================

-- Example: Quick audio device switcher
-- hs.hotkey.bind({"cmd", "alt"}, "A", function()
--     local audiodevices = hs.audiodevice.allOutputDevices()
--     hs.alert.show("Audio Devices Available: " .. #audiodevices)
-- end)

print("✅ Funny How Enterprise config loaded")

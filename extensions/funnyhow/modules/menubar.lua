-- Menubar Module
-- Integrates Funny How Locker into the macOS menubar
-- Features: 1. Login/Account 2. Timer to Lock 3. About

local privacyOverlay = require("modules.privacy-overlay")
local auth = require("modules.auth")
local M = {}

M.menu = nil
M.lockTimer = nil  -- Main timer that triggers the lock
M.countdownTimer = nil -- Timer that updates the UI every second
M.endTime = nil    -- When the timer will finish
M.chooser = nil    -- The command palette

-- Configuration
M.title = "🎙️" -- Microphone icon
M.accountUrl = "https://funny-how.com/account" -- Placeholder URL
M.loginUrl = "https://funny-how.com/login?redirect=hammerspoon://funny-how" -- URL to your login page

-- Format seconds into MM:SS
local function formatTime(seconds)
    local min = math.floor(seconds / 60)
    local sec = math.floor(seconds % 60)
    return string.format("%d:%02d", min, sec)
end

-- Update the menubar title with remaining time
local function updateCountdown()
    if not M.endTime then return end
    
    local remaining = math.ceil(M.endTime - os.time())
    if remaining > 0 then
        M.menu:setTitle(M.title .. " " .. formatTime(remaining))
    else
        -- Timer finished, reset title
        M.menu:setTitle(M.title)
    end
end

-- Stop the current timer
function M.stopTimer()
    if M.lockTimer then
        M.lockTimer:stop()
        M.lockTimer = nil
    end
    
    if M.countdownTimer then
        M.countdownTimer:stop()
        M.countdownTimer = nil
    end
    
    M.endTime = nil
    M.menu:setTitle(M.title)
    M.updateMenu() -- Refresh menu to show "Set Timer" options again
end

-- Start a timer to lock the screen
function M.startLockTimer(minutes)
    M.stopTimer() -- Clear any existing timer
    
    local seconds = minutes * 60
    hs.alert.show("Locker set for " .. minutes .. " minutes")
    
    M.endTime = os.time() + seconds
    M.updateMenu() -- Refresh menu to show "Cancel Timer"
    updateCountdown() -- Update title immediately
    
    -- Timer to update the UI every second
    M.countdownTimer = hs.timer.doEvery(1, updateCountdown)
    
    -- Timer to actually trigger the lock
    M.lockTimer = hs.timer.doAfter(seconds, function()
        privacyOverlay.show()
        M.stopTimer()
        hs.alert.show("Time's up! Locking...")
    end)
end

-- Handle Chooser Selection
local function handleSelection(choice)
    if not choice then return end -- Cancelled
    
    if choice.minutes then
        M.startLockTimer(choice.minutes)
    elseif choice.action == "custom" then
         -- Fallback to native text prompt for custom time
         -- This is native macOS UI, instant and reliable
        local button, timeStr = hs.dialog.textPrompt("Schedule Lock", "Enter time (HH:MM):", os.date("%H:%M"), "OK", "Cancel")
        if button == "OK" then
            local hour, min = timeStr:match("(%d+):(%d+)")
            if hour and min then
                hour = tonumber(hour)
                min = tonumber(min)
                if hour >= 0 and hour <= 23 and min >= 0 and min <= 59 then
                    local now = os.date("*t")
                    local targetTime = os.time({year=now.year, month=now.month, day=now.day, hour=hour, min=min, sec=0})
                    if targetTime < os.time() then targetTime = targetTime + 24 * 60 * 60 end
                    local durationMinutes = (targetTime - os.time()) / 60
                    if durationMinutes < 0.1 then durationMinutes = 0.1 end
                    M.startLockTimer(durationMinutes)
                else
                    hs.alert.show("Invalid time format")
                end
            else
                hs.alert.show("Invalid format")
            end
        end
    end
end

-- Show the Command Palette (Chooser)
function M.showSchedulePalette()
    if not M.chooser then
        M.chooser = hs.chooser.new(handleSelection)
        M.chooser:placeholderText("Select duration or schedule time...")
        M.chooser:bgDark(true) -- Match dark theme
        M.chooser:fgColor(nil) -- Default text color
        M.chooser:subTextColor(nil)
    end
    
    local choices = {
        {
            text = "30 Minutes",
            subText = "Lock in half an hour",
            image = hs.image.imageFromAppBundle("com.apple.clock"),
            minutes = 30
        },
        {
            text = "1 Hour",
            subText = "Lock in 60 minutes",
            image = hs.image.imageFromAppBundle("com.apple.clock"),
            minutes = 60
        },
        {
            text = "4 Hours",
            subText = "Deep work session",
            image = hs.image.imageFromAppBundle("com.apple.clock"),
            minutes = 240
        },
        {
            text = "Custom Time...",
            subText = "Schedule a specific time (HH:MM)",
            image = hs.image.imageFromName("NSActionTemplate"),
            action = "custom"
        }
    }
    
    M.chooser:choices(choices)
    M.chooser:show()
end

-- Show About dialog
function M.showAbout()
    hs.dialog.blockAlert("About Funny How Locker", "Funny How Locker\n\nA mindful privacy and focus tool.\n\nVersion 1.0", "Close")
end

-- Open Login/Account page
function M.handleLoginClick()
    if auth.isAuthenticated() then
        hs.urlevent.openURL(M.accountUrl)
    else
        hs.urlevent.openURL(M.loginUrl)
    end
end

-- Update the menu based on state
function M.updateMenu()
    local menuTable = {}
    
    -- 1. Account Option
    if auth.isAuthenticated() then
        table.insert(menuTable, { title = "My Account (" .. "Logged In" .. ")", fn = M.handleLoginClick })
        table.insert(menuTable, { title = "Logout", fn = auth.logout })
    else
        table.insert(menuTable, { title = "Login", fn = M.handleLoginClick })
    end
    
    table.insert(menuTable, { title = "-" })
    
    -- 2. Timer Options
    if M.lockTimer then
        -- Timer IS running
        local remaining = "calculating..."
        if M.endTime then
            remaining = formatTime(math.ceil(M.endTime - os.time()))
        end
        
        table.insert(menuTable, { title = "Time Remaining: " .. remaining, disabled = true })
        table.insert(menuTable, { title = "Cancel Timer", fn = M.stopTimer })
    else
        -- Timer IS NOT running
        -- "Schedule Lock..." opens the Command Palette
        table.insert(menuTable, { title = "Schedule Lock...", fn = M.showSchedulePalette })
    end
    
    table.insert(menuTable, { title = "-" })
    
    -- 3. About Option
    local aboutIcon = hs.image.imageFromName("NSInfo"):setSize({w=16, h=16})
    table.insert(menuTable, { title = "About Funny How Locker", fn = M.showAbout, image = aboutIcon })
    
    M.menu:setMenu(menuTable)
end

function M.setup()
    M.menu = hs.menubar.new()
    M.menu:setTitle(M.title)
    M.updateMenu()
    
    -- Update menu when auth state changes
    auth.onChange(function()
        M.updateMenu()
    end)
end

return M

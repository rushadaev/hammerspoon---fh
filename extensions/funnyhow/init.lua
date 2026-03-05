--- === hs.funnyhow ===
---
--- FunnyHow Device Locker - Custom lock screen with QR code and password validation
--- Remotely lock/unlock Mac via funny-how.com
---
--- This module provides:
---  * Device registration with funny-how.com
---  * Custom fullscreen lock screen with QR code
---  * Password validation against backend API
---  * Automatic lock/unlock based on booking status

local funnyhow = {}
funnyhow.__index = funnyhow

-- Internal modules
local http = require("hs.http")
local json = require("hs.json")
local settings = require("hs.settings")
local timer = require("hs.timer")
local menubar = require("hs.menubar")
local dialog = require("hs.dialog")
local notify = require("hs.notify")
local screen = require("hs.screen")
local webview = require("hs.webview")
local drawing = require("hs.drawing")
local eventtap = require("hs.eventtap")
local host = require("hs.host")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

funnyhow.config = {
    -- CHANGE THIS URL IF NEEDED (e.g., "http://127.0.0.1/api" for local dev)
    API_BASE_URL = "https://funny-how.com/api",

    -- Check interval in seconds
    CHECK_INTERVAL = 45,

    -- App version
    APP_VERSION = "1.0.0",

    -- Settings keys
    KEY_DEVICE_TOKEN = "funnyhow_device_token",
    KEY_DEVICE_UUID = "funnyhow_device_uuid",
    KEY_DEVICE_NAME = "funnyhow_device_name",
    KEY_USERNAME = "funnyhow_username",
    KEY_HOURLY_RATE = "funnyhow_hourly_rate",

    -- QR code API
    QR_API_URL = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=",
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

funnyhow._state = {
    isLocked = false,
    lockScreens = {},
    keyboardBlocker = nil,
    currentLockoutInfo = nil,
    checkTimer = nil,
    timerRunning = false,
    menubarItem = nil,
    currentStatus = "Not logged in",
}

--------------------------------------------------------------------------------
-- STORAGE
--------------------------------------------------------------------------------

function funnyhow.saveCredentials(deviceUuid, deviceToken, deviceName, username, hourlyRate)
    settings.set(funnyhow.config.KEY_DEVICE_UUID, deviceUuid)
    settings.set(funnyhow.config.KEY_DEVICE_TOKEN, deviceToken)
    settings.set(funnyhow.config.KEY_DEVICE_NAME, deviceName)
    settings.set(funnyhow.config.KEY_USERNAME, username)
    settings.set(funnyhow.config.KEY_HOURLY_RATE, hourlyRate)
    print("[FunnyHow] Credentials saved")
end

function funnyhow.loadCredentials()
    return {
        deviceUuid = settings.get(funnyhow.config.KEY_DEVICE_UUID),
        deviceToken = settings.get(funnyhow.config.KEY_DEVICE_TOKEN),
        deviceName = settings.get(funnyhow.config.KEY_DEVICE_NAME),
        username = settings.get(funnyhow.config.KEY_USERNAME),
        hourlyRate = settings.get(funnyhow.config.KEY_HOURLY_RATE),
    }
end

function funnyhow.clearCredentials()
    settings.clear(funnyhow.config.KEY_DEVICE_UUID)
    settings.clear(funnyhow.config.KEY_DEVICE_TOKEN)
    settings.clear(funnyhow.config.KEY_DEVICE_NAME)
    settings.clear(funnyhow.config.KEY_USERNAME)
    settings.clear(funnyhow.config.KEY_HOURLY_RATE)
    print("[FunnyHow] Credentials cleared")
end

function funnyhow.isAuthenticated()
    local creds = funnyhow.loadCredentials()
    return creds.deviceUuid ~= nil and creds.deviceToken ~= nil
end

--------------------------------------------------------------------------------
-- DEVICE INFO
--------------------------------------------------------------------------------

function funnyhow.getMacAddress()
    local output, status = hs.execute("ifconfig en0 | grep ether | awk '{print $2}'")
    if status and output then
        return output:gsub("%s+", "")
    end
    return "00:00:00:00:00:00"
end

function funnyhow.getOsVersion()
    local output, status = hs.execute("sw_vers -productVersion")
    if status and output then
        return "macOS " .. output:gsub("%s+", "")
    end
    return "macOS Unknown"
end

function funnyhow.getComputerName()
    return host.localizedName() or "Unknown Mac"
end

function funnyhow.generateUUID()
    local output, status = hs.execute("uuidgen")
    if status and output then
        return output:gsub("%s+", ""):lower()
    end
    return string.format("%x-%x-%x-%x",
        os.time(),
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535))
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local function getHeaders()
    return {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }
end

function funnyhow.registerDevice(registrationToken, deviceName, hourlyRate, callback)
    local creds = funnyhow.loadCredentials()
    local deviceUuid = creds.deviceUuid or funnyhow.generateUUID()

    local requestBody = json.encode({
        registration_token = registrationToken,
        device_name = deviceName or funnyhow.getComputerName(),
        mac_address = funnyhow.getMacAddress(),
        device_uuid = deviceUuid,
        os_version = funnyhow.getOsVersion(),
        app_version = funnyhow.config.APP_VERSION,
        hourly_rate = tonumber(hourlyRate) or 0
    })

    local url = funnyhow.config.API_BASE_URL .. "/devices/register-with-token"
    print("[FunnyHow] Registering device at: " .. url)

    http.asyncPost(url, requestBody, getHeaders(), function(statusCode, body, headers)
        print("[FunnyHow] Register response: " .. tostring(statusCode))

        if statusCode == 200 or statusCode == 201 then
            local success, responseData = pcall(json.decode, body)
            if success and responseData and responseData.device_token then
                local username = "device_" .. deviceUuid:sub(1, 8)
                funnyhow.saveCredentials(
                    deviceUuid,
                    responseData.device_token,
                    deviceName or funnyhow.getComputerName(),
                    username,
                    tonumber(hourlyRate) or 0
                )
                callback(true, nil, responseData)
            else
                callback(false, "Invalid response from server", nil)
            end
        elseif statusCode < 0 then
            callback(false, "Network error: Cannot connect to server", nil)
        else
            local errorMsg = "HTTP " .. tostring(statusCode)
            local success, responseData = pcall(json.decode, body)
            if success and responseData and responseData.message then
                errorMsg = responseData.message
            end
            callback(false, errorMsg, nil)
        end
    end)
end

function funnyhow.checkStatus(callback)
    local creds = funnyhow.loadCredentials()

    if not creds.deviceUuid or not creds.deviceToken then
        callback(false, "Not authenticated", nil)
        return
    end

    local requestBody = json.encode({
        device_uuid = creds.deviceUuid,
        device_token = creds.deviceToken,
        os_version = funnyhow.getOsVersion(),
        app_version = funnyhow.config.APP_VERSION
    })

    local url = funnyhow.config.API_BASE_URL .. "/devices/check-status"

    http.asyncPost(url, requestBody, getHeaders(), function(statusCode, body, headers)
        if statusCode == 200 then
            local success, responseData = pcall(json.decode, body)
            if success and responseData then
                callback(true, nil, {
                    shouldLock = responseData.should_lock or false,
                    isBlocked = responseData.is_blocked or false,
                    message = responseData.message or "Device locked",
                    lockoutInfo = responseData.lockout_info
                })
            else
                callback(false, "Invalid response", nil)
            end
        elseif statusCode < 0 then
            callback(false, "Network error", nil)
        else
            callback(false, "HTTP " .. tostring(statusCode), nil)
        end
    end)
end

function funnyhow.validatePassword(password, callback)
    local creds = funnyhow.loadCredentials()

    if not creds.deviceUuid or not creds.deviceToken then
        callback(false, "Not authenticated")
        return
    end

    local requestBody = json.encode({
        device_uuid = creds.deviceUuid,
        device_token = creds.deviceToken,
        password = password
    })

    local url = funnyhow.config.API_BASE_URL .. "/devices/unlock"

    http.asyncPost(url, requestBody, getHeaders(), function(statusCode, body, headers)
        if statusCode == 200 then
            local success, responseData = pcall(json.decode, body)
            if success and responseData and responseData.success then
                callback(true, nil)
            else
                local errorMsg = "Invalid password"
                if responseData and responseData.message then
                    errorMsg = responseData.message
                end
                callback(false, errorMsg)
            end
        else
            callback(false, "Validation failed")
        end
    end)
end

--------------------------------------------------------------------------------
-- LOCK SCREEN
--------------------------------------------------------------------------------

function funnyhow._generateLockScreenHTML(lockoutInfo)
    local studioName = lockoutInfo and lockoutInfo.studio_name or "Studio"
    local hourlyRate = lockoutInfo and lockoutInfo.hourly_rate or 0

    -- Get booking URL from API and replace local IP with funny-how.com domain
    local bookingUrl = lockoutInfo and (lockoutInfo.booking_url or lockoutInfo.cashapp_qr_url) or "https://funny-how.com"
    -- Replace any 192.168.x.x or localhost with funny-how.com
    bookingUrl = bookingUrl:gsub("http://[0-9%.]+", "https://funny-how.com")
    bookingUrl = bookingUrl:gsub("https://[0-9%.]+", "https://funny-how.com")
    bookingUrl = bookingUrl:gsub("http://localhost", "https://funny-how.com")
    bookingUrl = bookingUrl:gsub("https://localhost", "https://funny-how.com")

    local qrUrl = funnyhow.config.QR_API_URL .. http.encodeForQuery(bookingUrl)

    local html = [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f0f23 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif;
            height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            user-select: none;
            -webkit-user-select: none;
        }
        .container { text-align: center; max-width: 600px; padding: 40px; }
        .lock-icon { font-size: 64px; margin-bottom: 20px; }
        h1 {
            font-size: 48px; font-weight: 700; color: #ef4444;
            margin-bottom: 10px; text-transform: uppercase; letter-spacing: 4px;
        }
        .studio-name { font-size: 28px; color: #94a3b8; margin-bottom: 5px; }
        .rate { font-size: 22px; color: #64748b; margin-bottom: 30px; }
        .qr-container {
            background: white; padding: 20px; border-radius: 16px;
            display: inline-block; margin: 20px 0;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
        }
        .qr-container img { display: block; width: 250px; height: 250px; }
        .scan-text { font-size: 20px; color: #cbd5e1; margin: 20px 0; }
        .password-section {
            margin-top: 40px; padding-top: 30px;
            border-top: 1px solid rgba(255,255,255,0.1);
        }
        .password-label { font-size: 16px; color: #94a3b8; margin-bottom: 15px; }
        .password-input {
            width: 300px; padding: 15px 20px; font-size: 18px;
            border: 2px solid #334155; border-radius: 12px;
            background: rgba(30, 41, 59, 0.8); color: white;
            text-align: center; outline: none; transition: border-color 0.3s;
        }
        .password-input:focus { border-color: #3b82f6; }
        .password-input::placeholder { color: #64748b; }
        .unlock-btn {
            display: block; width: 300px; margin: 20px auto 0;
            padding: 15px 30px; font-size: 18px; font-weight: 600;
            color: white; background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
            border: none; border-radius: 12px; cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .unlock-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 30px rgba(59, 130, 246, 0.3);
        }
        .error-message { color: #ef4444; font-size: 14px; margin-top: 15px; min-height: 20px; }
        .instructions { font-size: 14px; color: #64748b; margin-top: 30px; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <div class="lock-icon">🔒</div>
        <h1>Device Locked</h1>
        <div class="studio-name">]] .. studioName .. [[</div>
        <div class="rate">$]] .. string.format("%.2f", hourlyRate) .. [[/hour</div>
        <div class="scan-text">Scan QR Code to Book Studio Time</div>
        <div class="qr-container">
            <img src="]] .. qrUrl .. [[" alt="QR Code" />
        </div>
        <div class="password-section">
            <div class="password-label">Enter unlock password:</div>
            <input type="password" id="password" class="password-input" placeholder="Password" autofocus />
            <button id="unlockBtn" class="unlock-btn">Unlock Device</button>
            <div id="error" class="error-message"></div>
        </div>
        <div class="instructions">
            Visit funny-how.com or scan the QR code above to book studio time.<br>
            Your device will automatically unlock when your session begins.
        </div>
    </div>
    <script>
        const passwordInput = document.getElementById('password');
        const unlockBtn = document.getElementById('unlockBtn');
        const errorDiv = document.getElementById('error');

        function attemptUnlock() {
            const password = passwordInput.value;
            if (!password) { errorDiv.textContent = 'Please enter a password'; return; }
            errorDiv.textContent = 'Validating...';
            unlockBtn.disabled = true;
            try {
                window.webkit.messageHandlers.funnyhow.postMessage({password: password});
            } catch(e) {
                errorDiv.textContent = 'Error communicating with app';
                unlockBtn.disabled = false;
            }
        }

        unlockBtn.addEventListener('click', attemptUnlock);
        passwordInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') attemptUnlock();
        });

        window.onbeforeunload = function() { return false; };
        passwordInput.focus();
    </script>
</body>
</html>
]]
    return html
end

function funnyhow.showLockScreen(lockoutInfo)
    if funnyhow._state.isLocked then
        print("[FunnyHow] Already locked")
        return
    end

    print("[FunnyHow] Showing custom lock screen")
    funnyhow._state.currentLockoutInfo = lockoutInfo

    local html = funnyhow._generateLockScreenHTML(lockoutInfo)
    local screens = screen.allScreens()
    funnyhow._state.lockScreens = {}

    for i, scr in ipairs(screens) do
        local frame = scr:fullFrame()

        local userContentController = webview.usercontent.new("funnyhow")
        userContentController:setCallback(function(message)
            if message.body and message.body.password then
                funnyhow._handleUnlockAttempt(message.body.password)
            end
        end)

        local wv = webview.new(frame, {}, userContentController)
        wv:windowStyle(webview.windowMasks.borderless)
        wv:level(drawing.windowLevels.screenSaver)
        wv:behavior(drawing.windowBehaviors.canJoinAllSpaces + drawing.windowBehaviors.stationary)
        wv:closeOnEscape(false)
        wv:allowTextEntry(true)
        wv:allowNewWindows(false)
        wv:allowNavigationGestures(false)
        wv:html(html)
        wv:show()
        wv:bringToFront(true)

        table.insert(funnyhow._state.lockScreens, wv)
        print("[FunnyHow] Lock screen created for screen " .. i)
    end

    funnyhow._state.keyboardBlocker = eventtap.new(
        {eventtap.event.types.keyDown},
        function(event)
            local flags = event:getFlags()
            if flags.cmd or flags.ctrl or flags.alt then
                return true
            end
            return false
        end
    )
    funnyhow._state.keyboardBlocker:start()

    funnyhow._state.isLocked = true
    funnyhow._updateStatus("Locked")
    print("[FunnyHow] Lock screen active")
end

function funnyhow.hideLockScreen()
    if not funnyhow._state.isLocked then return end

    print("[FunnyHow] Hiding lock screen")

    if funnyhow._state.keyboardBlocker then
        funnyhow._state.keyboardBlocker:stop()
        funnyhow._state.keyboardBlocker = nil
    end

    for _, wv in ipairs(funnyhow._state.lockScreens) do
        wv:delete()
    end
    funnyhow._state.lockScreens = {}

    funnyhow._state.isLocked = false
    funnyhow._state.currentLockoutInfo = nil
    funnyhow._updateStatus("Connected")

    notify.new({
        title = "FunnyHow",
        subTitle = "Device Unlocked",
        informativeText = "Your device has been unlocked"
    }):send()

    print("[FunnyHow] Lock screen hidden")
end

function funnyhow._handleUnlockAttempt(password)
    print("[FunnyHow] Unlock attempt received")

    funnyhow.validatePassword(password, function(success, error)
        if success then
            print("[FunnyHow] Password validated - unlocking")
            funnyhow.hideLockScreen()
        else
            print("[FunnyHow] Invalid password: " .. (error or "unknown error"))
            for _, wv in ipairs(funnyhow._state.lockScreens) do
                wv:evaluateJavaScript([[
                    document.getElementById('error').textContent = ']] .. (error or "Invalid password") .. [[';
                    document.getElementById('unlockBtn').disabled = false;
                    document.getElementById('password').value = '';
                    document.getElementById('password').focus();
                ]])
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- TIMER
--------------------------------------------------------------------------------

function funnyhow.startTimer()
    if funnyhow._state.timerRunning then
        print("[FunnyHow] Timer already running")
        return
    end

    print("[FunnyHow] Starting background checker (interval: " .. funnyhow.config.CHECK_INTERVAL .. "s)")

    funnyhow._checkStatusNow()

    funnyhow._state.checkTimer = timer.doEvery(
        funnyhow.config.CHECK_INTERVAL,
        function() funnyhow._checkStatusNow() end
    )

    funnyhow._state.timerRunning = true
end

function funnyhow.stopTimer()
    if funnyhow._state.checkTimer then
        funnyhow._state.checkTimer:stop()
        funnyhow._state.checkTimer = nil
    end
    funnyhow._state.timerRunning = false
    print("[FunnyHow] Background checker stopped")
end

function funnyhow._checkStatusNow()
    if not funnyhow.isAuthenticated() then return end

    funnyhow.checkStatus(function(success, error, data)
        if success and data then
            if data.shouldLock and not funnyhow._state.isLocked then
                print("[FunnyHow] Server says should_lock=true, showing lock screen...")
                funnyhow.showLockScreen(data.lockoutInfo)
            elseif not data.shouldLock and funnyhow._state.isLocked then
                print("[FunnyHow] Server says should_lock=false, unlocking...")
                funnyhow.hideLockScreen()
            elseif not data.shouldLock then
                funnyhow._updateStatus("Connected")
            end
        else
            print("[FunnyHow] Status check failed: " .. (error or "unknown error"))
            funnyhow._updateStatus("Disconnected")
        end
    end)
end

--------------------------------------------------------------------------------
-- UI (Menu Bar)
--------------------------------------------------------------------------------

function funnyhow._showRegistrationDialog()
    local button = dialog.blockAlert(
        "FunnyHow Device Registration",
        "To register this Mac with FunnyHow:\n\n" ..
        "1. Open funny-how.com in your browser\n" ..
        "2. Go to Devices page\n" ..
        "3. Click 'Generate Token'\n" ..
        "4. Copy the token\n\n" ..
        "Token expires in 24 hours and can only be used once.",
        "Continue", "Cancel"
    )

    if button == "Continue" then
        funnyhow._promptForToken()
    end
end

function funnyhow._promptForToken()
    local button, token = dialog.textPrompt(
        "Registration Token",
        "Paste your device registration token:",
        "",
        "Next",
        "Cancel",
        true
    )

    if button == "Next" and token and token ~= "" then
        funnyhow._promptForDeviceName(token)
    end
end

function funnyhow._promptForDeviceName(registrationToken)
    local button, deviceName = dialog.textPrompt(
        "Device Name",
        "Enter a name for this device:",
        funnyhow.getComputerName(),
        "Next",
        "Cancel"
    )

    if button == "Next" and deviceName and deviceName ~= "" then
        funnyhow._promptForHourlyRate(registrationToken, deviceName)
    end
end

function funnyhow._promptForHourlyRate(registrationToken, deviceName)
    local button, hourlyRate = dialog.textPrompt(
        "Hourly Rate",
        "Enter hourly rate for this device (e.g., 45.00):",
        "45.00",
        "Register",
        "Cancel"
    )

    if button == "Register" then
        local rate = tonumber(hourlyRate) or 0
        funnyhow._updateStatus("Registering...")

        funnyhow.registerDevice(registrationToken, deviceName, rate, function(success, error, data)
            if success then
                funnyhow._updateStatus("Connected")
                funnyhow._rebuildMenu()
                funnyhow.startTimer()

                notify.new({
                    title = "Registration Successful",
                    subTitle = "Device registered",
                    informativeText = "Your device has been registered with FunnyHow"
                }):send()
            else
                funnyhow._updateStatus("Registration failed")
                dialog.blockAlert("Registration Failed", error or "Unknown error occurred", "OK")
            end
        end)
    end
end

function funnyhow._showLogoutConfirmation()
    local button = dialog.blockAlert("Logout", "Are you sure you want to logout?", "Logout", "Cancel")

    if button == "Logout" then
        funnyhow.clearCredentials()
        funnyhow.stopTimer()
        funnyhow.hideLockScreen()
        funnyhow._updateStatus("Not logged in")
        funnyhow._rebuildMenu()

        notify.new({
            title = "Logged Out",
            informativeText = "You have been logged out"
        }):send()
    end
end

function funnyhow._updateStatus(status)
    funnyhow._state.currentStatus = status
    funnyhow._rebuildMenu()
end

function funnyhow._createMenubar()
    if funnyhow._state.menubarItem then
        funnyhow._state.menubarItem:delete()
    end

    funnyhow._state.menubarItem = menubar.new()
    funnyhow._state.menubarItem:setTitle("FH")
    funnyhow._rebuildMenu()
end

function funnyhow._rebuildMenu()
    if not funnyhow._state.menubarItem then return end

    local menuItems = {}

    table.insert(menuItems, { title = "Status: " .. funnyhow._state.currentStatus, disabled = true })
    table.insert(menuItems, { title = "-" })

    if funnyhow.isAuthenticated() then
        local creds = funnyhow.loadCredentials()
        table.insert(menuItems, { title = "Device: " .. (creds.deviceName or "Unknown"), disabled = true })
        if creds.hourlyRate and creds.hourlyRate > 0 then
            table.insert(menuItems, { title = string.format("Rate: $%.2f/hour", creds.hourlyRate), disabled = true })
        end
        table.insert(menuItems, { title = "-" })
        table.insert(menuItems, {
            title = "Test Lock Screen",
            fn = function()
                funnyhow.showLockScreen({
                    studio_name = creds.deviceName or "Test Studio",
                    hourly_rate = creds.hourlyRate or 45,
                    booking_url = "https://funny-how.com"
                })
            end
        })
        table.insert(menuItems, { title = "Logout", fn = function() funnyhow._showLogoutConfirmation() end })
    else
        table.insert(menuItems, { title = "Register Device...", fn = function() funnyhow._showRegistrationDialog() end })
    end

    table.insert(menuItems, { title = "-" })
    table.insert(menuItems, {
        title = "About",
        fn = function()
            dialog.blockAlert(
                "FunnyHow Locker",
                "Version " .. funnyhow.config.APP_VERSION .. "\n\n" ..
                "Custom lock screen with QR code and password validation.\n\n" ..
                "Automatically locks your Mac when outside of booked sessions.",
                "OK"
            )
        end
    })

    funnyhow._state.menubarItem:setMenu(menuItems)
end

--------------------------------------------------------------------------------
-- BUNDLED MODULES
--------------------------------------------------------------------------------

-- Setup module path for bundled modules
local function setupModulePath()
    -- Get the path to the funnyhow extension
    local extensionPath = hs.processInfo.resourcePath .. "/extensions/funnyhow"

    -- Add modules directory to package.path
    local modulesPath = extensionPath .. "/modules/?.lua"
    if not package.path:find(modulesPath, 1, true) then
        package.path = modulesPath .. ";" .. package.path
        print("[FunnyHow] Added modules path: " .. modulesPath)
    end
end

-- Load and initialize all bundled modules
function funnyhow._loadBundledModules()
    print("[FunnyHow] Loading bundled modules...")

    setupModulePath()

    -- Store loaded modules
    funnyhow.modules = {}

    -- List of modules to load (in dependency order)
    local moduleList = {
        { name = "auth", setup = false },
        { name = "particles", setup = false },
        { name = "privacy-overlay", setup = true },
        { name = "window-positioning", setup = true },
        { name = "window-focus", setup = true },
        { name = "pomodoro", setup = true },
        { name = "config-watcher", setup = true },
        { name = "focus-mode", setup = true },
        { name = "eye-break", setup = true },
        -- Note: menubar and standup have external dependencies, load separately
    }

    for _, modInfo in ipairs(moduleList) do
        local success, mod = pcall(require, "modules." .. modInfo.name)
        if success then
            funnyhow.modules[modInfo.name] = mod
            if modInfo.setup and mod.setup then
                local setupSuccess, err = pcall(mod.setup)
                if setupSuccess then
                    print("[FunnyHow] Loaded and initialized: " .. modInfo.name)
                else
                    print("[FunnyHow] Failed to setup " .. modInfo.name .. ": " .. tostring(err))
                end
            else
                print("[FunnyHow] Loaded: " .. modInfo.name)
            end
        else
            print("[FunnyHow] Failed to load " .. modInfo.name .. ": " .. tostring(mod))
        end
    end

    -- Load menubar module (depends on privacy-overlay and auth)
    local success, menubarMod = pcall(require, "modules.menubar")
    if success then
        funnyhow.modules["menubar"] = menubarMod
        local setupSuccess, err = pcall(menubarMod.setup)
        if setupSuccess then
            print("[FunnyHow] Loaded and initialized: menubar")
        else
            print("[FunnyHow] Failed to setup menubar: " .. tostring(err))
        end
    else
        print("[FunnyHow] Failed to load menubar: " .. tostring(menubarMod))
    end

    print("[FunnyHow] Bundled modules loaded")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--- hs.funnyhow.init()
--- Function
--- Initializes the FunnyHow Device Locker
---
--- Parameters:
---  * None
---
--- Returns:
---  * The hs.funnyhow module
function funnyhow.init()
    print("[FunnyHow] Initializing FunnyHow Locker v" .. funnyhow.config.APP_VERSION)

    -- Load bundled modules first
    funnyhow._loadBundledModules()

    -- Create FunnyHow locker menubar
    funnyhow._createMenubar()

    if funnyhow.isAuthenticated() then
        local creds = funnyhow.loadCredentials()
        print("[FunnyHow] Restored session for: " .. (creds.username or "unknown"))
        funnyhow._updateStatus("Connected")
        funnyhow.startTimer()
    else
        print("[FunnyHow] No saved session")
        funnyhow._updateStatus("Not logged in")
    end

    return funnyhow
end

--- hs.funnyhow.setAPIURL(url)
--- Function
--- Sets the API base URL
---
--- Parameters:
---  * url - The API base URL (e.g., "https://funny-how.com/api" or "http://127.0.0.1/api")
---
--- Returns:
---  * None
function funnyhow.setAPIURL(url)
    funnyhow.config.API_BASE_URL = url
    print("[FunnyHow] API URL set to: " .. url)
end

return funnyhow

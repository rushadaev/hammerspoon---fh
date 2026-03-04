-- Lid Angle Sensor Module
-- Monitors MacBook lid angle using pybooklid Python library
-- Provides menubar display, threshold notifications, and event callbacks

local M = {}

-- Configuration
M.config = {
    enabled = true,
    pythonCommand = "/Users/ruslanshadaev/.pyenv/versions/3.13.1/bin/python", -- Full path to python with pybooklid
    updateInterval = 0.5,     -- Seconds between angle updates (nil to disable continuous monitoring)
    menubarEnabled = true,    -- Show angle in menubar
    consoleLogging = false,   -- Log angle changes to console
    focusModeEnabled = true,  -- Auto-trigger focus mode when lid closes below threshold
    focusModeThreshold = 50,  -- Angle threshold for focus mode
    volumeControlEnabled = false, -- Progressive volume control based on lid angle
    volumeMinAngle = 30,      -- Angle at 0% volume (muted)
    volumeMaxAngle = 120,     -- Angle at 100% volume (original level)
    volumeControlThreshold = 110, -- Angle above which volume is not controlled (sampling zone)
    thresholds = {
        -- Define additional angle thresholds for notifications/callbacks
        -- { angle = 30, direction = "closing", message = "Lid closing", callback = nil }
    }
}

-- Internal state
local state = {
    currentAngle = nil,
    previousAngle = nil,
    menubar = nil,
    timer = nil,
    lastThresholdFired = {},
    originalVolume = nil,
    volumeControlActive = false,
    inFadeZone = false  -- Track if we're currently in the fade zone
}

-- Read current lid angle from sensor
function M.readAngle()
    local task = hs.task.new(
        M.config.pythonCommand,
        function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                local angle = tonumber(stdOut)
                if angle then
                    M._handleAngleUpdate(angle)
                else
                    if M.config.consoleLogging then
                        hs.printf("[lid-angle] Failed to parse angle: %s", stdOut)
                    end
                end
            else
                if M.config.consoleLogging then
                    hs.printf("[lid-angle] Error reading angle (exit %d): %s", exitCode, stdErr)
                end
            end
        end,
        {"-c", "from pybooklid import read_lid_angle; print(read_lid_angle())"}
    )
    task:start()
    return task
end

-- Handle angle update
function M._handleAngleUpdate(angle)
    state.previousAngle = state.currentAngle
    state.currentAngle = angle

    -- Log to console if enabled
    if M.config.consoleLogging and state.previousAngle ~= angle then
        hs.printf("[lid-angle] Angle: %.1f°", angle)
    end

    -- Update menubar
    if M.config.menubarEnabled and state.menubar then
        local title = string.format("%.0f°", angle)

        -- Add volume indicator if volume control is active
        if M.config.volumeControlEnabled and state.volumeControlActive then
            local device = hs.audiodevice.defaultOutputDevice()
            if device then
                local currentVolume = device:volume()
                title = string.format("%.0f° (🔊%.0f%%)", angle, currentVolume)
            end
        end

        state.menubar:setTitle(title)
    end

    -- Focus mode trigger
    if M.config.focusModeEnabled and state.previousAngle then
        if state.previousAngle >= M.config.focusModeThreshold and angle < M.config.focusModeThreshold then
            local focusMode = require("modules.focus-mode")
            focusMode.show()
            if M.config.consoleLogging then
                hs.printf("[lid-angle] Focus mode triggered at %.1f°", angle)
            end
        end
    end

    -- Volume control
    if M.config.volumeControlEnabled then
        M._handleVolumeControl(angle)
    end

    -- Check thresholds
    M._checkThresholds(angle, state.previousAngle)
end

-- Check if any thresholds were crossed
function M._checkThresholds(currentAngle, previousAngle)
    if not previousAngle then return end

    for i, threshold in ipairs(M.config.thresholds) do
        local thresholdAngle = threshold.angle
        local direction = threshold.direction or "both" -- "closing", "opening", or "both"

        local crossed = false
        local isClosing = currentAngle < previousAngle

        -- Check if threshold was crossed
        if direction == "both" then
            crossed = (previousAngle > thresholdAngle and currentAngle <= thresholdAngle) or
                     (previousAngle < thresholdAngle and currentAngle >= thresholdAngle)
        elseif direction == "closing" then
            crossed = isClosing and previousAngle > thresholdAngle and currentAngle <= thresholdAngle
        elseif direction == "opening" then
            crossed = not isClosing and previousAngle < thresholdAngle and currentAngle >= thresholdAngle
        end

        if crossed then
            -- Prevent duplicate notifications
            local lastFired = state.lastThresholdFired[i]
            local now = hs.timer.secondsSinceEpoch()
            if not lastFired or (now - lastFired) > 5 then -- 5 second cooldown
                state.lastThresholdFired[i] = now

                -- Show notification if message provided
                if threshold.message then
                    hs.notify.new({
                        title = "Lid Angle",
                        informativeText = string.format("%s (%.0f°)", threshold.message, currentAngle),
                        withdrawAfter = 2
                    }):send()
                end

                -- Call callback if provided
                if threshold.callback then
                    threshold.callback(currentAngle, previousAngle)
                end
            end
        end
    end
end

-- Handle progressive volume control based on lid angle
function M._handleVolumeControl(angle)
    -- Get default output device
    local device = hs.audiodevice.defaultOutputDevice()
    if not device then
        hs.printf("[lid-angle] ERROR: No audio output device available")
        return
    end

    local controlThreshold = M.config.volumeControlThreshold or 110

    -- Show one-time notification on first activation
    if not state.volumeControlActive then
        state.volumeControlActive = true
        hs.notify.new({
            title = "Volume Control Enabled",
            informativeText = string.format("Control threshold: %.0f°\nCurrent angle: %.0f°", controlThreshold, angle),
            withdrawAfter = 3
        }):send()
    end

    if angle >= controlThreshold then
        -- "Hands off" zone - sample and save reference, don't control volume
        local currentVolume = device:volume()

        -- Log when entering hands-off zone
        if state.inFadeZone and M.config.consoleLogging then
            hs.printf("[lid-angle] Entered hands-off zone (angle: %.1f°)", angle)
        end
        state.inFadeZone = false

        -- Only update and log if reference changed significantly (>2%)
        if not state.originalVolume or math.abs(currentVolume - state.originalVolume) > 2 then
            state.originalVolume = currentVolume
            if M.config.consoleLogging then
                hs.printf("[lid-angle] Reference volume updated: %.0f%%", state.originalVolume)
            end
        end
        -- Don't set volume here, let user control manually
    else
        -- "Fade" zone - apply progressive volume reduction

        -- Log when entering fade zone
        if not state.inFadeZone and M.config.consoleLogging then
            hs.printf("[lid-angle] Entered fade zone (angle: %.1f°)", angle)
        end
        state.inFadeZone = true

        if not state.originalVolume then
            -- Initialize reference if needed (first time below threshold)
            state.originalVolume = device:volume()
            if M.config.consoleLogging then
                hs.printf("[lid-angle] Initial reference: %.0f%%", state.originalVolume)
            end
        end

        local minAngle = M.config.volumeMinAngle
        local maxAngle = controlThreshold  -- Use control threshold as max for fade

        local volumePercent
        if angle <= minAngle then
            volumePercent = 0
        else
            volumePercent = (angle - minAngle) / (maxAngle - minAngle)
        end

        local targetVolume = volumePercent * state.originalVolume

        -- Set volume
        device:setVolume(targetVolume)

        if M.config.consoleLogging then
            hs.printf("[lid-angle] Fading: %.0f%% (angle: %.1f°, ref: %.0f%%)",
                targetVolume, angle, state.originalVolume)
        end
    end
end

-- Get current angle (synchronous - returns last known angle)
function M.getCurrentAngle()
    return state.currentAngle
end

-- Get current angle with callback (asynchronous - reads from sensor)
function M.getAngle(callback)
    local task = hs.task.new(
        M.config.pythonCommand,
        function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                local angle = tonumber(stdOut)
                if angle and callback then
                    callback(angle)
                end
            end
        end,
        {"-c", "from pybooklid import read_lid_angle; print(read_lid_angle())"}
    )
    task:start()
end

-- Start continuous monitoring
function M.startMonitoring()
    if state.timer then
        state.timer:stop()
    end

    if M.config.updateInterval then
        state.timer = hs.timer.doEvery(M.config.updateInterval, function()
            M.readAngle()
        end)
        -- Read immediately
        M.readAngle()
    end
end

-- Stop continuous monitoring
function M.stopMonitoring()
    if state.timer then
        state.timer:stop()
        state.timer = nil
    end
end

-- Enable volume control
function M.enableVolumeControl()
    M.config.volumeControlEnabled = true
    state.volumeControlActive = false  -- Reset to save new original volume
    state.originalVolume = nil
    state.inFadeZone = false
    if M.config.consoleLogging then
        hs.printf("[lid-angle] Volume control enabled")
    end
end

-- Disable volume control
function M.disableVolumeControl()
    M.config.volumeControlEnabled = false

    -- Restore original volume if we saved it
    if state.originalVolume then
        local device = hs.audiodevice.defaultOutputDevice()
        if device then
            device:setVolume(state.originalVolume)
            if M.config.consoleLogging then
                hs.printf("[lid-angle] Volume restored to %.0f%%", state.originalVolume)
            end
        end
    end

    state.volumeControlActive = false
    state.originalVolume = nil
    state.inFadeZone = false

    if M.config.consoleLogging then
        hs.printf("[lid-angle] Volume control disabled")
    end
end

-- Setup menubar
function M._setupMenubar()
    if M.config.menubarEnabled then
        state.menubar = hs.menubar.new()
        state.menubar:setTitle("--°")
        state.menubar:setMenu(function()
            return {
                {
                    title = string.format("Current Angle: %.1f°", state.currentAngle or 0),
                    disabled = true
                },
                { title = "-" },
                {
                    title = "Refresh",
                    fn = function()
                        M.readAngle()
                    end
                },
                {
                    title = state.timer and "Stop Monitoring" or "Start Monitoring",
                    fn = function()
                        if state.timer then
                            M.stopMonitoring()
                        else
                            M.startMonitoring()
                        end
                    end
                },
                { title = "-" },
                {
                    title = string.format("Focus Mode @ %d°: %s", M.config.focusModeThreshold, M.config.focusModeEnabled and "On" or "Off"),
                    fn = function()
                        M.config.focusModeEnabled = not M.config.focusModeEnabled
                    end
                },
                {
                    title = string.format("Volume Control (fade <%d°): %s", M.config.volumeControlThreshold, M.config.volumeControlEnabled and "On" or "Off"),
                    fn = function()
                        if M.config.volumeControlEnabled then
                            M.disableVolumeControl()
                        else
                            M.enableVolumeControl()
                        end
                    end
                },
                {
                    title = string.format("Console Logging: %s", M.config.consoleLogging and "On" or "Off"),
                    fn = function()
                        M.config.consoleLogging = not M.config.consoleLogging
                    end
                }
            }
        end)
    end
end

-- Initialize module
function M.setup()
    if not M.config.enabled then
        hs.printf("[lid-angle] Module disabled")
        return M
    end

    -- Setup menubar
    M._setupMenubar()

    -- Start monitoring if configured
    if M.config.updateInterval then
        M.startMonitoring()
    else
        -- Just read once
        M.readAngle()
    end

    hs.printf("[lid-angle] Module initialized")
    return M
end

-- Cleanup
function M.cleanup()
    M.stopMonitoring()

    -- Restore volume if volume control is active
    if M.config.volumeControlEnabled then
        M.disableVolumeControl()
    end

    if state.menubar then
        state.menubar:delete()
        state.menubar = nil
    end
end

return M

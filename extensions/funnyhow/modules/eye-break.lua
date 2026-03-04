-- Eye Break Reminder Module
-- A single eye roams around a dimmed screen with countdown timer
-- Based on the 20-20-20 rule: Every 20 min, look 20 feet away for 20 seconds

local M = {}

-- Configuration
M.interval = 20 * 60  -- 20 minutes between reminders (seconds)
M.displayDuration = 20  -- Show for 20 seconds
M.eyeSize = 100

-- Pattern definitions (waypoints as screen fractions 0-1)
M.patterns = {
    {
        name = "Figure-8",
        waypoints = {
            {x = 0.25, y = 0.5},   -- left node
            {x = 0.35, y = 0.35},  -- upper left loop
            {x = 0.50, y = 0.25},  -- top center
            {x = 0.65, y = 0.35},  -- upper right loop
            {x = 0.75, y = 0.5},   -- right node
            {x = 0.65, y = 0.65},  -- lower right loop
            {x = 0.50, y = 0.75},  -- bottom center
            {x = 0.35, y = 0.65}   -- lower left loop
        },
        acceleration = 0.012,
        damping = 0.94,
        switchDistance = 100
    },
    {
        name = "Clock",
        waypoints = {
            {x = 0.5, y = 0.1},   -- 12 o'clock
            {x = 0.75, y = 0.15}, -- 1 o'clock
            {x = 0.9, y = 0.35},  -- 2 o'clock
            {x = 0.9, y = 0.5},   -- 3 o'clock
            {x = 0.9, y = 0.65},  -- 4 o'clock
            {x = 0.75, y = 0.85}, -- 5 o'clock
            {x = 0.5, y = 0.9},   -- 6 o'clock
            {x = 0.25, y = 0.85}, -- 7 o'clock
            {x = 0.1, y = 0.65},  -- 8 o'clock
            {x = 0.1, y = 0.5},   -- 9 o'clock
            {x = 0.1, y = 0.35},  -- 10 o'clock
            {x = 0.25, y = 0.15}  -- 11 o'clock
        },
        acceleration = 0.015,
        damping = 0.93,
        switchDistance = 120
    },
    {
        name = "Diagonal",
        waypoints = {
            {x = 0.15, y = 0.15}, -- top-left
            {x = 0.85, y = 0.85}, -- bottom-right
            {x = 0.85, y = 0.15}, -- top-right
            {x = 0.15, y = 0.85}  -- bottom-left
        },
        acceleration = 0.009,
        damping = 0.95,
        switchDistance = 150
    },
    {
        name = "Near-Far",
        waypoints = {
            {x = 0.5, y = 0.5},   -- center (near)
            {x = 0.1, y = 0.1},   -- far top-left
            {x = 0.5, y = 0.5},   -- center (near)
            {x = 0.9, y = 0.1},   -- far top-right
            {x = 0.5, y = 0.5},   -- center (near)
            {x = 0.9, y = 0.9},   -- far bottom-right
            {x = 0.5, y = 0.5},   -- center (near)
            {x = 0.1, y = 0.9}    -- far bottom-left
        },
        acceleration = 0.011,
        damping = 0.94,
        switchDistance = 130
    }
}

-- State
local reminderTimer = nil
local animTimer = nil
local countdownTimer = nil
local overlays = {}  -- Table to hold overlay (keeping as table for compatibility)
local eyeCanvases = {}  -- Table to hold eye canvas (keeping as table for compatibility)
local eyeStates = {}  -- Table to hold movement state (keeping as table for compatibility)
local isActive = false
local isPaused = false
local timeRemaining = 0

-- Get the next waypoint from the current pattern
local function getNextWaypoint(state, screenFrame)
    if not state.currentPattern then
        -- Pick a random pattern at start
        state.currentPattern = M.patterns[math.random(#M.patterns)]
        state.waypointIndex = 1
    end

    -- Get waypoint (as fraction of screen)
    local waypoint = state.currentPattern.waypoints[state.waypointIndex]

    -- Convert to absolute coordinates with safe margins
    local margin = M.eyeSize * 2
    state.targetX = screenFrame.x + margin + (waypoint.x * (screenFrame.w - margin * 2))
    state.targetY = screenFrame.y + margin + (waypoint.y * (screenFrame.h - margin * 2))

    -- Advance to next waypoint (loop)
    state.waypointIndex = (state.waypointIndex % #state.currentPattern.waypoints) + 1
end

-- Show the eye break reminder
function M.showReminder()
    if #overlays > 0 then return end  -- Already showing

    -- Only show on primary screen
    local screen = hs.screen.primaryScreen()
    local frame = screen:fullFrame()
    timeRemaining = M.displayDuration

    -- Create dim overlay
    local overlay = hs.canvas.new(frame)
    overlay[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { red = 0, green = 0, blue = 0, alpha = 0.7 }
    }

    -- Countdown timer text at bottom
    overlay[2] = {
        type = "text",
        text = "Look away • " .. timeRemaining .. "s",
        textColor = { red = 0.7, green = 0.8, blue = 1, alpha = 0.9 },
        textSize = 24,
        textFont = ".AppleSystemUIFontRounded-Medium",
        frame = { x = 0, y = frame.h - 80, w = frame.w, h = 40 },
        textAlignment = "center"
    }

    -- Subtle hint
    overlay[3] = {
        type = "text",
        text = "click anywhere to dismiss",
        textColor = { red = 0.5, green = 0.5, blue = 0.6, alpha = 0.5 },
        textSize = 14,
        frame = { x = 0, y = frame.h - 45, w = frame.w, h = 30 },
        textAlignment = "center"
    }

    overlay:level(hs.canvas.windowLevels.overlay)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, false, false, false)
    overlay:mouseCallback(function()
        M.dismissReminder()
    end)
    overlay:show()
    table.insert(overlays, overlay)

    -- Create the floating eye
    local state = {
        eyeX = frame.x + frame.w / 2,
        eyeY = frame.y + frame.h / 2,
        velocityX = 0,
        velocityY = 0,
        targetX = 0,
        targetY = 0,
        currentPattern = nil,  -- Will be set by getNextWaypoint
        waypointIndex = 1
    }
    getNextWaypoint(state, frame)  -- Initialize first target
    table.insert(eyeStates, state)

    local eyeCanvas = hs.canvas.new({
        x = state.eyeX - M.eyeSize/2,
        y = state.eyeY - M.eyeSize/2,
        w = M.eyeSize,
        h = M.eyeSize
    })

    -- Glow behind eye
    eyeCanvas[1] = {
        type = "circle",
        action = "fill",
        fillColor = { red = 0.4, green = 0.6, blue = 1, alpha = 0.3 },
        center = { x = M.eyeSize/2, y = M.eyeSize/2 },
        radius = M.eyeSize/2
    }

    -- The eye emoji
    eyeCanvas[2] = {
        type = "text",
        text = "👁️",
        textSize = M.eyeSize * 0.65,
        frame = { x = 0, y = 5, w = M.eyeSize, h = M.eyeSize },
        textAlignment = "center"
    }

    eyeCanvas:level(hs.canvas.windowLevels.overlay + 1)
    eyeCanvas:clickActivating(false)
    eyeCanvas:canvasMouseEvents(true, false, false, false)
    eyeCanvas:mouseCallback(function()
        M.dismissReminder()
    end)
    eyeCanvas:show()
    table.insert(eyeCanvases, eyeCanvas)
    
    -- Animation loop - eye floats continuously toward pattern waypoints
    local time = 0
    animTimer = hs.timer.doEvery(0.016, function()  -- ~60fps
        time = time + 0.016

        -- Use pattern-specific parameters
        local pattern = state.currentPattern or M.patterns[1]
        local accel = pattern.acceleration
        local damp = pattern.damping
        local switchDist = pattern.switchDistance

        -- Move toward target with smooth easing
        local dx = state.targetX - state.eyeX
        local dy = state.targetY - state.eyeY
        local dist = math.sqrt(dx*dx + dy*dy)

        -- Switch waypoint when close enough
        if dist < switchDist then
            getNextWaypoint(state, frame)
        end

        -- Smoother movement with pattern-specific tuning
        state.velocityX = state.velocityX * damp + dx * accel
        state.velocityY = state.velocityY * damp + dy * accel

        -- Reduced wobble for therapeutic mode
        local wobbleX = math.sin(time * 2) * 0.5
        local wobbleY = math.cos(time * 1.5) * 0.5

        state.eyeX = state.eyeX + state.velocityX + wobbleX
        state.eyeY = state.eyeY + state.velocityY + wobbleY

        -- Keep within bounds
        state.eyeX = math.max(frame.x + M.eyeSize, math.min(frame.x + frame.w - M.eyeSize, state.eyeX))
        state.eyeY = math.max(frame.y + M.eyeSize, math.min(frame.y + frame.h - M.eyeSize, state.eyeY))

        -- Update eye position
        eyeCanvas:frame({
            x = state.eyeX - M.eyeSize/2,
            y = state.eyeY - M.eyeSize/2,
            w = M.eyeSize,
            h = M.eyeSize
        })

        -- Pulse the glow
        local pulse = 0.2 + math.sin(time * 4) * 0.1
        eyeCanvas[1].fillColor = { red = 0.4, green = 0.6, blue = 1, alpha = pulse }
    end)
    
    -- Countdown timer
    countdownTimer = hs.timer.doEvery(1, function()
        timeRemaining = timeRemaining - 1

        -- Update countdown text
        if overlay and overlay[2] then
            overlay[2].text = "Look away • " .. timeRemaining .. "s"
        end

        if timeRemaining <= 0 then
            M.dismissReminder()
        end
    end)
end

-- Dismiss the reminder
function M.dismissReminder()
    if animTimer then
        animTimer:stop()
        animTimer = nil
    end

    if countdownTimer then
        countdownTimer:stop()
        countdownTimer = nil
    end

    -- Clean up all eye canvases
    for _, eyeCanvas in ipairs(eyeCanvases) do
        if eyeCanvas then
            eyeCanvas:delete()
        end
    end
    eyeCanvases = {}

    -- Clean up all overlays
    for _, overlay in ipairs(overlays) do
        if overlay then
            overlay:delete()
        end
    end
    overlays = {}

    -- Clear eye states
    eyeStates = {}
end

-- Start the reminder loop
function M.start()
    if isActive then return end
    isActive = true
    isPaused = false
    
    reminderTimer = hs.timer.doEvery(M.interval, function()
        if not isPaused then
            M.showReminder()
        end
    end)
    
    hs.alert.show("👁️ Eye breaks ON (every 20 min)")
end

-- Stop the reminder loop
function M.stop()
    isActive = false
    
    if reminderTimer then
        reminderTimer:stop()
        reminderTimer = nil
    end
    
    M.dismissReminder()
    hs.alert.show("👁️ Eye breaks OFF")
end

-- Toggle on/off
function M.toggle()
    if isActive then
        M.stop()
    else
        M.start()
    end
end

-- Test: Show reminder immediately
function M.test()
    M.showReminder()
end

function M.setup()
    -- Toggle eye break reminders
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "E", M.toggle)
    
    -- Test/preview the reminder
    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "E", M.test)
    
    -- Auto-start
    M.start()
end

return M

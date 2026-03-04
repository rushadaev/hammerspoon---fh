-- Privacy Overlay Module
-- Clean, minimal lock screen with embedded webview
--
-- Usage: Cmd+Ctrl+L to lock, type password + Enter to unlock

local particles = require("modules.particles")

local M = {}

-- Configuration
M.password = "1234"
M.webUrl = "https://funny-how.com/"
M.webviewWidth = 900
M.webviewHeight = 600

-- State
local overlays = {}
local webviews = {}
local passwordDisplays = {}
local loaders = {}  -- Loading overlays per screen
local loaderTimer = nil
local keyTap = nil
local mouseTap = nil
local passwordBuffer = ""

-- Colors
local colors = {
    bg = { red = 0.04, green = 0.04, blue = 0.08, alpha = 0.94 },
    border = { red = 0.2, green = 0.25, blue = 0.35, alpha = 0.8 },
    accent = { red = 0.3, green = 0.5, blue = 0.9, alpha = 0.6 },
    dot = { red = 0.5, green = 0.6, blue = 0.9, alpha = 0.8 },
    dotBg = { red = 0.1, green = 0.1, blue = 0.15, alpha = 0.9 },
}

-- Create password display at bottom of each screen
local function createPasswordDisplay()
    local displayW = 200
    local displayH = 50
    
    for _, screen in ipairs(hs.screen.allScreens()) do
        local screenFrame = screen:frame()
        local displayX = screenFrame.x + (screenFrame.w - displayW) / 2
        local displayY = screenFrame.y + screenFrame.h - 100
        
        local display = hs.canvas.new({
            x = displayX,
            y = displayY,
            w = displayW,
            h = displayH
        })
        
        -- Background pill
        display[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = colors.dotBg,
            roundedRectRadii = { xRadius = 25, yRadius = 25 }
        }
        
        -- Border
        display[2] = {
            type = "rectangle",
            action = "stroke",
            strokeColor = colors.border,
            strokeWidth = 1,
            roundedRectRadii = { xRadius = 25, yRadius = 25 }
        }
        
        -- Password dots
        display[3] = {
            type = "text",
            text = "│",
            textColor = colors.dot,
            textSize = 20,
            textFont = ".AppleSystemUIFont",
            frame = { x = 0, y = 12, w = displayW, h = 30 },
            textAlignment = "center"
        }
        
        display:level(hs.canvas.windowLevels.screenSaver + 3)
        display:show()
        table.insert(passwordDisplays, display)
    end
end

local function updatePasswordDisplay()
    local dotCount = #passwordBuffer
    local dots = string.rep("●  ", dotCount)
    if dots == "" then
        dots = "│"
    end
    
    for _, display in ipairs(passwordDisplays) do
        display[3].text = dots
    end
end

function M.hide()
    particles.stop()
    
    if loaderTimer then
        loaderTimer:stop()
        loaderTimer = nil
    end
    
    for _, loader in ipairs(loaders) do
        loader:delete()
    end
    loaders = {}

    for _, overlay in ipairs(overlays) do
        overlay:delete()
    end
    overlays = {}

    for _, wv in ipairs(webviews) do
        wv:delete()
    end
    webviews = {}
    
    for _, display in ipairs(passwordDisplays) do
        display:delete()
    end
    passwordDisplays = {}

    if keyTap then
        keyTap:stop()
        keyTap = nil
    end

    if mouseTap then
        mouseTap:stop()
        mouseTap = nil
    end

    passwordBuffer = ""
end

function M.show()
    if #overlays > 0 then return end

    for _, screen in ipairs(hs.screen.allScreens()) do
        local frame = screen:fullFrame()
        local screenFrame = screen:frame()
        
        -- Background overlay
        local overlay = hs.canvas.new(frame)
        
        -- Dark background
        overlay[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = colors.bg
        }
        
        -- Subtle gradient
        overlay[2] = {
            type = "rectangle",
            action = "fill",
            fillGradient = "radial",
            fillGradientColors = {
                { red = 0.08, green = 0.1, blue = 0.18, alpha = 0.5 },
                { red = 0, green = 0, blue = 0, alpha = 0 }
            },
            fillGradientCenter = { x = 0.5, y = 0.5 },
        }
        
        -- Add particles
        particles.addToCanvas(overlay, 3, frame)
        
        overlay:level(hs.canvas.windowLevels.screenSaver)
        overlay:clickActivating(false)
        overlay:show()
        table.insert(overlays, overlay)
        
        -- Webview frame
        local webFrame = {
            x = screenFrame.x + (screenFrame.w - M.webviewWidth) / 2,
            y = screenFrame.y + (screenFrame.h - M.webviewHeight) / 2,
            w = M.webviewWidth,
            h = M.webviewHeight
        }
        
        -- Border frame
        local borderCanvas = hs.canvas.new({
            x = webFrame.x - 1,
            y = webFrame.y - 1,
            w = webFrame.w + 2,
            h = webFrame.h + 2
        })
        borderCanvas[1] = {
            type = "rectangle",
            action = "stroke",
            strokeColor = colors.border,
            strokeWidth = 1,
            roundedRectRadii = { xRadius = 4, yRadius = 4 }
        }
        borderCanvas[2] = {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.2, green = 0.3, blue = 0.5, alpha = 0.1 },
            roundedRectRadii = { xRadius = 4, yRadius = 4 }
        }
        borderCanvas:level(hs.canvas.windowLevels.screenSaver + 1)
        borderCanvas:show()
        table.insert(overlays, borderCanvas)
        
        -- Webview (hidden initially)
        local webview = hs.webview.new(webFrame)
        webview:windowStyle({"borderless"})
        webview:level(hs.canvas.windowLevels.screenSaver + 2)
        webview:allowTextEntry(true)
        webview:url(M.webUrl)
        webview:hide()  -- Hidden until loader finishes
        table.insert(webviews, webview)
        
        -- Loader overlay (covers webview area)
        local loader = hs.canvas.new(webFrame)
        
        -- Dark background for loader
        loader[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.06, green = 0.06, blue = 0.1, alpha = 1 },
            roundedRectRadii = { xRadius = 4, yRadius = 4 }
        }
        
        -- Pulsing rings
        local centerX = webFrame.w / 2
        local centerY = webFrame.h / 2
        
        loader[2] = {
            type = "circle",
            action = "stroke",
            strokeColor = { red = 0.3, green = 0.5, blue = 0.9, alpha = 0.3 },
            strokeWidth = 2,
            center = { x = centerX, y = centerY },
            radius = 30
        }
        
        loader[3] = {
            type = "circle",
            action = "stroke",
            strokeColor = { red = 0.4, green = 0.6, blue = 1.0, alpha = 0.2 },
            strokeWidth = 2,
            center = { x = centerX, y = centerY },
            radius = 45
        }
        
        loader[4] = {
            type = "circle",
            action = "stroke",
            strokeColor = { red = 0.3, green = 0.5, blue = 0.9, alpha = 0.1 },
            strokeWidth = 2,
            center = { x = centerX, y = centerY },
            radius = 60
        }
        
        -- Loading text
        loader[5] = {
            type = "text",
            text = "Loading",
            textColor = { red = 0.5, green = 0.6, blue = 0.8, alpha = 0.8 },
            textSize = 14,
            textFont = ".AppleSystemUIFont",
            frame = { x = 0, y = centerY + 80, w = webFrame.w, h = 30 },
            textAlignment = "center"
        }
        
        loader:level(hs.canvas.windowLevels.screenSaver + 3)
        loader:show()
        table.insert(loaders, loader)
    end
    
    -- Animate loader and reveal webviews after 3 seconds
    local animTime = 0
    loaderTimer = hs.timer.doEvery(0.05, function()
        animTime = animTime + 0.05
        
        -- Pulsing animation
        for _, loader in ipairs(loaders) do
            local pulse = math.sin(animTime * 3) * 0.3 + 0.7
            local pulse2 = math.sin(animTime * 3 + 1) * 0.3 + 0.7
            local pulse3 = math.sin(animTime * 3 + 2) * 0.3 + 0.7
            
            loader[2].strokeColor = { red = 0.3, green = 0.5, blue = 0.9, alpha = 0.3 * pulse }
            loader[3].strokeColor = { red = 0.4, green = 0.6, blue = 1.0, alpha = 0.2 * pulse2 }
            loader[4].strokeColor = { red = 0.3, green = 0.5, blue = 0.9, alpha = 0.15 * pulse3 }
            
            -- Expand rings
            local baseRadius = 30 + math.sin(animTime * 2) * 5
            loader[2].radius = baseRadius
            loader[3].radius = baseRadius + 15
            loader[4].radius = baseRadius + 30
            
            -- Dots animation for loading text
            local dots = string.rep(".", (math.floor(animTime * 2) % 4))
            loader[5].text = "Redirecting" .. dots
        end
        
        -- After 3 seconds, reveal webviews
        if animTime >= 1 then
            loaderTimer:stop()
            loaderTimer = nil
            
            -- Hide loaders and show webviews
            for _, loader in ipairs(loaders) do
                loader:hide()
            end
            for _, wv in ipairs(webviews) do
                wv:show()
            end
        end
    end)
    
    -- Password display
    createPasswordDisplay()
    
    particles.start()
    passwordBuffer = ""

    -- Keyboard handler
    keyTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local keyCode = event:getKeyCode()
        local char = event:getCharacters()

        local numpadMap = {
            [82] = "0", [83] = "1", [84] = "2", [85] = "3", [86] = "4",
            [87] = "5", [88] = "6", [89] = "7", [91] = "8", [92] = "9"
        }

        if keyCode == 51 then
            passwordBuffer = passwordBuffer:sub(1, -2)
            updatePasswordDisplay()
        elseif keyCode == 36 or keyCode == 76 then
            if passwordBuffer == M.password then
                M.hide()
            else
                passwordBuffer = ""
                updatePasswordDisplay()
                -- Shake animation on all screens
                for _, display in ipairs(passwordDisplays) do
                    local origFrame = display:frame()
                    hs.timer.doAfter(0, function()
                        if display then display:frame({ x = origFrame.x - 10, y = origFrame.y, w = origFrame.w, h = origFrame.h }) end
                    end)
                    hs.timer.doAfter(0.05, function()
                        if display then display:frame({ x = origFrame.x + 10, y = origFrame.y, w = origFrame.w, h = origFrame.h }) end
                    end)
                    hs.timer.doAfter(0.1, function()
                        if display then display:frame({ x = origFrame.x - 5, y = origFrame.y, w = origFrame.w, h = origFrame.h }) end
                    end)
                    hs.timer.doAfter(0.15, function()
                        if display then display:frame(origFrame) end
                    end)
                end
            end
        elseif numpadMap[keyCode] then
            passwordBuffer = passwordBuffer .. numpadMap[keyCode]
            updatePasswordDisplay()
        elseif char and #char > 0 then
            passwordBuffer = passwordBuffer .. char
            updatePasswordDisplay()
        end

        return true
    end)
    keyTap:start()

    -- Mouse handler
    mouseTap = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.leftMouseUp,
        hs.eventtap.event.types.rightMouseDown,
        hs.eventtap.event.types.rightMouseUp,
        hs.eventtap.event.types.leftMouseDragged,
        hs.eventtap.event.types.rightMouseDragged,
        hs.eventtap.event.types.scrollWheel,
        hs.eventtap.event.types.gesture
    }, function(event)
        local mousePos = hs.mouse.absolutePosition()
        
        for _, wv in ipairs(webviews) do
            local wf = wv:frame()
            if mousePos.x >= wf.x and mousePos.x <= wf.x + wf.w and
               mousePos.y >= wf.y and mousePos.y <= wf.y + wf.h then
                return false
            end
        end
        
        return true
    end)
    mouseTap:start()
end

function M.setup()
    hs.hotkey.bind({"cmd", "ctrl"}, "L", M.show)
end

return M

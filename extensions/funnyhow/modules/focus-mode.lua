-- Focus Mode Module
-- Minimal lock screen for creative thinking - no webview, just vibes
--
-- Usage: Option+Cmd+L to enter, type password + Enter to exit

local particles = require("modules.particles")

local M = {}

-- Configuration
M.password = "1234"
M.message = "💭"  -- Change to whatever you want or leave empty

-- State
local overlays = {}
local keyTap = nil
local mouseTap = nil
local passwordBuffer = ""

-- Colors
local colors = {
    bg = { red = 0.03, green = 0.03, blue = 0.06, alpha = 0.96 },
    text = { red = 0.4, green = 0.45, blue = 0.55, alpha = 0.6 },
}

function M.hide()
    particles.stop()

    for _, overlay in ipairs(overlays) do
        overlay:delete()
    end
    overlays = {}

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
        
        local overlay = hs.canvas.new(frame)
        
        -- Dark background
        overlay[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = colors.bg
        }
        
        -- Subtle center glow
        overlay[2] = {
            type = "rectangle",
            action = "fill",
            fillGradient = "radial",
            fillGradientColors = {
                { red = 0.06, green = 0.08, blue = 0.14, alpha = 0.6 },
                { red = 0, green = 0, blue = 0, alpha = 0 }
            },
            fillGradientCenter = { x = 0.5, y = 0.5 },
        }
        
        -- Optional centered message/emoji
        if M.message and #M.message > 0 then
            overlay[3] = {
                type = "text",
                text = M.message,
                textColor = colors.text,
                textSize = 48,
                frame = { x = "0", y = "45%", w = "100%", h = "10%" },
                textAlignment = "center"
            }
            particles.addToCanvas(overlay, 4, frame)
        else
            particles.addToCanvas(overlay, 3, frame)
        end
        
        overlay:level(hs.canvas.windowLevels.screenSaver)
        overlay:clickActivating(false)
        overlay:show()
        table.insert(overlays, overlay)
    end
    
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
        elseif keyCode == 36 or keyCode == 76 then
            if passwordBuffer == M.password then
                M.hide()
            else
                passwordBuffer = ""
            end
        elseif numpadMap[keyCode] then
            passwordBuffer = passwordBuffer .. numpadMap[keyCode]
        elseif char and #char > 0 then
            passwordBuffer = passwordBuffer .. char
        end

        return true
    end)
    keyTap:start()

    -- Block all mouse
    mouseTap = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.leftMouseUp,
        hs.eventtap.event.types.rightMouseDown,
        hs.eventtap.event.types.rightMouseUp,
        hs.eventtap.event.types.scrollWheel,
    }, function()
        return true
    end)
    mouseTap:start()
end

function M.setup()
    hs.hotkey.bind({"alt", "cmd"}, "L", M.show)
end

return M

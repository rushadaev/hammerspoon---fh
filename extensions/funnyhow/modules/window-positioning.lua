-- Window Positioning Module
-- Handles window quadrant placement, half-screen positioning, movement, and resizing

local M = {}

-- Movement/resize step size
M.globalStep = 50

function M.setup()
    local step = M.globalStep

    -- === Quadrant Positioning ===

    -- Top-left quadrant (Y)
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "Y", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x
        f.y = max.y
        f.w = max.w / 2
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- Top-right quadrant (U)
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "U", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x + max.w / 2
        f.y = max.y
        f.w = max.w / 2
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- Bottom-left quadrant (B)
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "B", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x
        f.y = max.y + max.h / 2
        f.w = max.w / 2
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- Bottom-right quadrant (N)
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "N", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x + max.w / 2
        f.y = max.y + max.h / 2
        f.w = max.w / 2
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- === Half-Screen Positioning ===

    -- Left half
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "Left", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x
        f.y = max.y
        f.w = max.w / 2
        f.h = max.h
        win:setFrame(f)
    end)

    -- Right half
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "Right", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x + (max.w / 2)
        f.y = max.y
        f.w = max.w / 2
        f.h = max.h
        win:setFrame(f)
    end)

    -- Top half
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "Up", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x
        f.y = max.y
        f.w = max.w
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- Bottom half
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "Down", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local max = win:screen():frame()
        f.x = max.x
        f.y = max.y + (max.h / 2)
        f.w = max.w
        f.h = max.h / 2
        win:setFrame(f)
    end)

    -- === Window Movement (with Shift) ===

    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "K", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.y = f.y - step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "J", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.y = f.y + step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "H", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.x = f.x - step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "L", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.x = f.x + step
        win:setFrame(f)
    end)

    -- === Window Resizing (without Shift) ===

    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "K", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.h = f.h - step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "J", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.h = f.h + step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "H", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.w = f.w - step
        win:setFrame(f)
    end)

    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "L", function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        f.w = f.w + step
        win:setFrame(f)
    end)
end

return M

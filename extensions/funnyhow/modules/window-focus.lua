-- Window Focus Module
-- Handles directional window focus switching

local M = {}

function M.setup()
    -- Focus window to the west
    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Left", function()
        local win = hs.window.focusedWindow()
        if win then win:focusWindowWest() end
    end)

    -- Focus window to the east
    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Right", function()
        local win = hs.window.focusedWindow()
        if win then win:focusWindowEast() end
    end)

    -- Focus window to the north
    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Up", function()
        local win = hs.window.focusedWindow()
        if win then win:focusWindowNorth() end
    end)

    -- Focus window to the south
    hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Down", function()
        local win = hs.window.focusedWindow()
        if win then win:focusWindowSouth() end
    end)
end

return M

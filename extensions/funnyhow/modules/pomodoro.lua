-- Pomodoro Timer Module
-- Uses the Cherry spoon for pomodoro functionality

local M = {}

function M.setup()
    hs.loadSpoon("Cherry")
    
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "C", function()
        spoon.Cherry:start()
    end)
end

return M

-- Auth Module
-- Handles authentication state and deep linking for funny-how integration

local M = {}

M.token = nil
M.callbacks = {}

-- Load token from settings on startup
function M.load()
    M.token = hs.settings.get("funnyHowToken")
end

-- Save token to settings
function M.saveToken(token)
    M.token = token
    hs.settings.set("funnyHowToken", token)
    M.notify()
end

-- Clear token (Logout)
function M.logout()
    M.token = nil
    hs.settings.clear("funnyHowToken")
    M.notify()
end

-- Check if user is authenticated
function M.isAuthenticated()
    return M.token ~= nil and M.token ~= ""
end

-- Register a callback to be notified when auth state changes
function M.onChange(fn)
    table.insert(M.callbacks, fn)
end

-- Notify all listeners
function M.notify()
    for _, fn in ipairs(M.callbacks) do
        fn(M.isAuthenticated())
    end
end

-- URL Handler: hammerspoon://funny-how?token=...
hs.urlevent.bind("funny-how", function(eventName, params)
    print("Received URL event: " .. eventName)
    if params and params.token then
        M.saveToken(params.token)
        hs.alert.show("Funny How Locker: Logged In ✅")
    else
        hs.alert.show("Funny How Locker: Login failed (No token)")
    end
end)

-- Initialize
M.load()

return M

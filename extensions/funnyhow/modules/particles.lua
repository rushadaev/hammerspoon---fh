-- Particles Animation Module
-- Creates floating particle effects on canvas overlays

local M = {}

-- Configuration
M.count = 15
M.minSize = 2
M.maxSize = 5
M.speed = 0.3
M.colors = {
    { red = 0.4, green = 0.5, blue = 0.9 },   -- Blue
    { red = 0.5, green = 0.3, blue = 0.8 },   -- Purple
    { red = 0.3, green = 0.6, blue = 0.7 },   -- Teal
}

-- State
local timer = nil
local particles = {}  -- { canvas, startIndex, endIndex, screenFrame }[]

-- Add particles to a canvas starting at a given element index
function M.addToCanvas(canvas, startIndex, screenFrame)
    local endIndex = startIndex
    
    for i = 1, M.count do
        local color = M.colors[math.random(1, #M.colors)]
        local size = math.random(M.minSize, M.maxSize)
        
        canvas[startIndex + i - 1] = {
            type = "circle",
            action = "fill",
            fillColor = { 
                red = color.red, 
                green = color.green, 
                blue = color.blue, 
                alpha = 0.08 + math.random() * 0.12
            },
            center = { 
                x = math.random(0, screenFrame.w), 
                y = math.random(0, screenFrame.h) 
            },
            radius = size
        }
        endIndex = startIndex + i - 1
    end
    
    table.insert(particles, {
        canvas = canvas,
        startIndex = startIndex,
        endIndex = endIndex,
        screenFrame = screenFrame
    })
    
    return endIndex + 1  -- Return next available index
end

-- Start the animation loop
function M.start()
    if timer then return end
    
    local time = 0
    timer = hs.timer.doEvery(0.05, function()
        time = time + 0.05
        
        for _, p in ipairs(particles) do
            for i = 0, M.count - 1 do
                local idx = p.startIndex + i
                if p.canvas[idx] then
                    -- Each particle has unique movement pattern
                    local seed = idx * 137
                    local baseX = (seed * 7) % p.screenFrame.w
                    local baseY = (seed * 11) % p.screenFrame.h
                    
                    local newX = baseX + math.sin(time * M.speed + seed * 0.1) * 80
                    local newY = baseY + math.cos(time * M.speed * 0.7 + seed * 0.15) * 60
                    
                    -- Wrap around screen edges
                    newX = newX % p.screenFrame.w
                    newY = newY % p.screenFrame.h
                    
                    p.canvas[idx].center = { x = newX, y = newY }
                end
            end
        end
    end)
end

-- Stop animation and clear state
function M.stop()
    if timer then
        timer:stop()
        timer = nil
    end
    particles = {}
end

return M

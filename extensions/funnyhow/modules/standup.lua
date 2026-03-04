-- Daily Standup Helper Module
-- Aggregates work activity and uses AI to generate a summary
--
-- Usage: Cmd+Alt+Ctrl+S to open the standup window

local M = {}
local secrets = require("secrets")
local apiKey = secrets.openai_api_key or os.getenv("OPENAI_API_KEY")

-- Configuration
M.scanPaths = { "~/Desktop" } -- Directories to scan for git repos
M.scanDepth = 3
M.lookbackDays = 4 -- How many days back to look (1 = yesterday/today)

-- State
local webview = nil
local gatheredData = {
    commits = {},
    claude = {},
    calendar = nil, -- start as nil to indicate not loaded
    summary = nil,
    additionalContext = "", -- store user's additional context
    todos = nil, -- start as nil, load on startup
    todosFilter = "all", -- all, active, completed
    trends = nil -- historical trends data
}
local backgroundTimer = nil

-- ... (Keep Helper Functions) ...

-- ... (Keep gatherGitCommits and gatherClaudeHistory) ...

-- 3. Gather Calendar Events (Native Swift)
function M.gatherCalendarEvents(isInteractive)
    if isInteractive then
        gatheredData.calendar = nil
        M.updateWebview()
    end
    
    local binary = os.getenv("HOME") .. "/.hammerspoon/scripts/fetch_calendar"
    
    -- Use synchronous execution because the binary is fast (~0.5s)
    -- hs.task was causing 20s delays for unknown reasons
    local output, status, type, rc = hs.execute(binary)
    
    local events = {}
    
    if status and output then
        for item in output:gmatch("[^\r\n]+") do
            local title, timeStr = item:match("(.+)|(.+)")
            if title then
                table.insert(events, {
                    title = title,
                    time = timeStr
                })
            elseif item:match("Access denied") then
                 table.insert(events, { title = "⚠️ Permission Denied", time = "Check Settings" })
            end
        end
    else
         -- If execution failed
         table.insert(events, { title = "⚠️ Calendar Error", time = "" })
    end
    
    gatheredData.calendar = events
    M.updateWebview()
    
    -- Trigger AI summary
    if not gatheredData.summary then
        M.generateSummary()
    end
end

-- ... (Keep generateSummary) ...

-- ... (Keep generateHtml) ...

function M.refresh()
    -- Interactive refresh (user clicked button)
    gatheredData.summary = nil -- Reset summary to force regeneration
    M.updateWebview() -- Show loading state
    
    M.gatherGitCommits()
    M.gatherClaudeHistory()
    M.gatherCalendarEvents(true) -- Pass true to identify interactive
end

function M.startBackgroundSync()
    -- Load todos and trends on startup
    local todosData = loadTodos()
    gatheredData.todos = organizeTodos(todosData)
    local history = loadHistory(7)
    gatheredData.trends = M.calculateTrends(history)

    -- Initial fetch
    M.gatherGitCommits()
    M.gatherClaudeHistory()
    M.gatherCalendarEvents(false) -- Background fetch

    -- Schedule usage every 15 minutes
    if backgroundTimer then backgroundTimer:stop() end
    backgroundTimer = hs.timer.doEvery(15 * 60, function()
        -- Reload todos and trends
        local todosData = loadTodos()
        gatheredData.todos = organizeTodos(todosData)
        local history = loadHistory(7)
        gatheredData.trends = M.calculateTrends(history)

        M.gatherGitCommits()
        M.gatherClaudeHistory()
        M.gatherCalendarEvents(false)
    end)
end

function M.show()
    if not webview then
        local rect = hs.screen.mainScreen():frame()
        local w = 800
        local h = 700
        local x = rect.x + (rect.w - w) / 2
        local y = rect.y + (rect.h - h) / 2
        
        webview = hs.webview.new({x=x, y=y, w=w, h=h})
        webview:windowStyle({"titled", "closable", "nonactivating", "resizable"})
        webview:allowTextEntry(true)
    end
    
    webview:show()
    M.updateWebview() -- Show cached data immediately
    
    -- If cache is empty/old, maybe trigger refresh?
    if not gatheredData.calendar then
         M.refresh() 
    end
end

function M.setup()
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", M.show)
    
    hs.urlevent.bind("standup", function(eventName, params)
        if params.action == "refresh" then
            M.refresh()
        end
    end)
    
    -- Start background sync
    M.startBackgroundSync()
end

-- Execute shell command and return output
local function exec(cmd)
    local output, status = hs.execute(cmd)
    -- Filter out known benign errors from the console log
    local benign = false
    if output then
        if output:match("does not have any commits yet") then benign = true end
        if output:match("No calendars") then benign = true end
        if output:match("fatal: not a git repository") then benign = true end
        if output:match("Connection is invalid") then benign = true end -- Calendar -609
    end
    
    if not status and not benign then
        print("Standup: Command failed: " .. cmd .. "\nOutput: " .. (output or ""))
    end
    return output or ""
end

-- Read file content
local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

-- Save additional context to file
local function saveAdditionalContext(text)
    local contextPath = os.getenv("HOME") .. "/.hammerspoon/standup_context.txt"
    local f = io.open(contextPath, "w")
    if f then
        f:write(text or "")
        f:close()
    end
end

-- Load additional context from file
local function loadAdditionalContext()
    local contextPath = os.getenv("HOME") .. "/.hammerspoon/standup_context.txt"
    local f = io.open(contextPath, "r")
    if f then
        local content = f:read("*all")
        f:close()
        return content or ""
    end
    return ""
end

-- URL decode function
local function urlDecode(str)
    if not str then return "" end
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

-- Parse JSON line by line
local function parseJsonL(content)
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        local ok, data = pcall(hs.json.decode, line)
        if ok and data then
            table.insert(lines, data)
        end
    end
    return lines
end

-- === Todo Tracking Data Persistence ===

-- Load todos from JSON file
local function loadTodos()
    local todosPath = os.getenv("HOME") .. "/.hammerspoon/standup_todos.json"
    local f = io.open(todosPath, "r")
    if not f then
        return { version = 1, todos = {} }
    end
    local content = f:read("*all")
    f:close()

    local ok, data = pcall(hs.json.decode, content)
    if ok and data and data.todos then
        return data
    else
        -- Malformed JSON, reset
        return { version = 1, todos = {} }
    end
end

-- Save todos to JSON file
local function saveTodos(todosData)
    local todosPath = os.getenv("HOME") .. "/.hammerspoon/standup_todos.json"
    local f = io.open(todosPath, "w")
    if f then
        local json = hs.json.encode(todosData)
        f:write(json)
        f:close()
        return true
    end
    return false
end

-- Organize todos into active, completed, and archived
local function organizeTodos(todosData)
    local active = {}
    local completed = {}
    local archived = {}

    for _, todo in ipairs(todosData.todos or {}) do
        if todo.archivedAt then
            table.insert(archived, todo)
        elseif todo.completed then
            table.insert(completed, todo)
        else
            table.insert(active, todo)
        end
    end

    return {
        active = active,
        completed = completed,
        archived = archived,
        all = todosData.todos or {}
    }
end

-- Load history from JSONL file
local function loadHistory(daysBack)
    local historyPath = os.getenv("HOME") .. "/.hammerspoon/standup_history.jsonl"
    local f = io.open(historyPath, "r")
    if not f then
        return {}
    end

    local content = f:read("*all")
    f:close()

    local history = parseJsonL(content)
    local cutoff = os.time() - (daysBack * 24 * 60 * 60)
    local filtered = {}

    for _, entry in ipairs(history) do
        if entry.timestamp and entry.timestamp > cutoff then
            table.insert(filtered, entry)
        end
    end

    return filtered
end

-- Save daily summary to history
local function saveDailySummary()
    local historyPath = os.getenv("HOME") .. "/.hammerspoon/standup_history.jsonl"
    local today = os.date("%Y-%m-%d")

    -- Calculate metrics
    local commitsCount = 0
    for _, repo in ipairs(gatheredData.commits or {}) do
        commitsCount = commitsCount + #repo.messages
    end

    local calendarCount = gatheredData.calendar and #gatheredData.calendar or 0

    local todosCompleted = 0
    local todosActive = 0
    if gatheredData.todos then
        todosCompleted = #gatheredData.todos.completed
        todosActive = #gatheredData.todos.active
    end

    local reposActive = #(gatheredData.commits or {})
    local claudeQueries = #(gatheredData.claude or {})

    local entry = {
        date = today,
        timestamp = os.time(),
        commits_count = commitsCount,
        calendar_events = calendarCount,
        todos_completed = todosCompleted,
        todos_added = todosActive,
        metrics = {
            repos_active = reposActive,
            claude_queries = claudeQueries
        }
    }

    -- Encode entry to JSON
    local ok, jsonEntry = pcall(hs.json.encode, entry)
    if not ok then
        print("Standup: Failed to encode daily summary to JSON")
        return
    end

    -- Check if entry for today already exists
    local existingContent = readFile(historyPath) or ""
    local lines = {}
    local todayExists = false

    if existingContent ~= "" then
        for line in existingContent:gmatch("[^\r\n]+") do
            if line ~= "" then
                local ok, data = pcall(hs.json.decode, line)
                if ok and data then
                    -- Only keep valid JSON lines
                    if data.date == today then
                        todayExists = true
                        table.insert(lines, jsonEntry)
                    else
                        -- Re-encode to ensure it's valid
                        local reEncoded = hs.json.encode(data)
                        table.insert(lines, reEncoded)
                    end
                else
                    -- Skip corrupted lines
                    print("Standup: Skipping corrupted history line: " .. line:sub(1, 50))
                end
            end
        end
    end

    if not todayExists then
        table.insert(lines, jsonEntry)
    end

    -- Write back
    local f = io.open(historyPath, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

-- === Todo CRUD Operations ===

function M.addTodo(text)
    if not text or text == "" then return end

    local todosData = loadTodos()
    local newTodo = {
        id = "todo_" .. os.time() .. "_" .. math.random(1000, 9999),
        text = text,
        completed = false,
        createdAt = os.time(),
        dueDate = nil,
        archivedAt = nil
    }

    table.insert(todosData.todos, newTodo)
    saveTodos(todosData)

    -- Update gatheredData
    gatheredData.todos = organizeTodos(todosData)
    M.updateWebview()
end

function M.toggleTodo(todoId)
    if not todoId then return end

    local todosData = loadTodos()

    for _, todo in ipairs(todosData.todos) do
        if todo.id == todoId then
            todo.completed = not todo.completed
            break
        end
    end

    saveTodos(todosData)
    gatheredData.todos = organizeTodos(todosData)
    M.updateWebview()
end

function M.deleteTodo(todoId)
    if not todoId then return end

    local todosData = loadTodos()

    for _, todo in ipairs(todosData.todos) do
        if todo.id == todoId then
            todo.archivedAt = os.time()
            break
        end
    end

    saveTodos(todosData)
    gatheredData.todos = organizeTodos(todosData)
    M.updateWebview()
end

function M.editTodo(todoId, newText)
    if not todoId or not newText or newText == "" then return end

    local todosData = loadTodos()

    for _, todo in ipairs(todosData.todos) do
        if todo.id == todoId then
            todo.text = newText
            break
        end
    end

    saveTodos(todosData)
    gatheredData.todos = organizeTodos(todosData)
    M.updateWebview()
end

function M.archiveCompleted()
    local todosData = loadTodos()
    local now = os.time()

    for _, todo in ipairs(todosData.todos) do
        if todo.completed and not todo.archivedAt then
            todo.archivedAt = now
        end
    end

    saveTodos(todosData)
    gatheredData.todos = organizeTodos(todosData)
    M.updateWebview()
end

-- === Trend Analysis ===

function M.calculateTrends(history)
    if not history or #history == 0 then
        return nil
    end

    local totalCommits = 0
    local totalCalendarEvents = 0
    local totalTodosCompleted = 0
    local totalTodosAdded = 0
    local days = #history

    local commitsByDay = {}

    for _, entry in ipairs(history) do
        totalCommits = totalCommits + (entry.commits_count or 0)
        totalCalendarEvents = totalCalendarEvents + (entry.calendar_events or 0)
        totalTodosCompleted = totalTodosCompleted + (entry.todos_completed or 0)
        totalTodosAdded = totalTodosAdded + (entry.todos_added or 0)
        table.insert(commitsByDay, entry.commits_count or 0)
    end

    local avgCommits = days > 0 and math.floor(totalCommits / days) or 0
    local avgCalendarEvents = days > 0 and math.floor(totalCalendarEvents / days) or 0
    local todoCompletionRate = totalTodosAdded > 0 and math.floor((totalTodosCompleted / totalTodosAdded) * 100) or 0

    -- Determine commit trend
    local commitTrend = "stable"
    if #commitsByDay >= 3 then
        local recent = (commitsByDay[#commitsByDay] + commitsByDay[#commitsByDay - 1]) / 2
        local older = (commitsByDay[1] + commitsByDay[2]) / 2
        if recent > older * 1.2 then
            commitTrend = "increasing"
        elseif recent < older * 0.8 then
            commitTrend = "decreasing"
        end
    end

    return {
        avg_commits = avgCommits,
        avg_calendar_events = avgCalendarEvents,
        todo_completion_rate = todoCompletionRate,
        commit_trend = commitTrend,
        days_analyzed = days
    }
end

-- === Data Gathering ===

-- 1. Scan for active Git repositories
function M.gatherGitCommits()
    local commits = {}
    local sinceDate = os.date("%Y-%m-%d", os.time() - (M.lookbackDays * 24 * 60 * 60))
    
    for _, path in ipairs(M.scanPaths) do
        local expandedPath = string.gsub(path, "^~", os.getenv("HOME"))
        
        -- Find .git directories
        local findCmd = string.format("/usr/bin/find '%s' -maxdepth %d -type d -name '.git' 2>/dev/null", expandedPath, M.scanDepth)
        local gitDirs = exec(findCmd)
        
        for gitDir in gitDirs:gmatch("[^\r\n]+") do
            local repoPath = gitDir:sub(1, -6) -- remove /.git
            
            -- Get commits since looking back
            local logCmd = string.format("cd '%s' && /usr/bin/git log --since='%s 00:00' --pretty=format:'%%H|%%an|%%ad|%%s' --date=short --no-merges 2>&1", repoPath, sinceDate)
            
            local repoCommits = exec(logCmd)
            if repoCommits and #repoCommits > 0 and not repoCommits:match("fatal:") then
                local repoName = repoPath:match("([^/]+)$")
                local commitList = {}
                
                for line in repoCommits:gmatch("[^\r\n]+") do
                    local hash, author, date, msg = line:match("^(%w+)|(.-)|(.-)|(.*)$")
                    if msg then
                         -- formatting: [Author] Msg
                         table.insert(commitList, string.format("[%s] %s", author, msg))
                    else
                         if line ~= "" then
                            table.insert(commitList, line)
                         end
                    end
                end
                
                if #commitList > 0 then
                    table.insert(commits, {
                        repo = repoName,
                        path = repoPath,
                        messages = commitList
                    })
                end
            end
        end
    end
    
    gatheredData.commits = commits
    return commits
end

-- 2. Gather Claude Code History
function M.gatherClaudeHistory()
    local home = os.getenv("HOME")
    local historyPath = home .. "/.claude/history.jsonl"
    local content = readFile(historyPath)
    
    if not content then return {} end
    
    local lines = parseJsonL(content)
    local relevant = {}
    local cutoff = os.time() - (M.lookbackDays * 24 * 60 * 60)
    
    -- Iterate backwards
    for i = #lines, 1, -1 do
        local entry = lines[i]
        if entry.timestamp and (entry.timestamp / 1000) > cutoff then
            if entry.display and entry.display:match("^%s*[^/]") then -- Filter out slash commands
                table.insert(relevant, {
                    prompt = entry.display,
                    project = entry.project and entry.project:match("([^/]+)$") or "Unknown"
                })
            end
        else
             if entry.timestamp and (entry.timestamp / 1000) < (cutoff - 86400) then
                break 
             end
        end
    end
    
    gatheredData.claude = relevant
    return relevant
end

-- 3. Gather Calendar Events (Today)
-- 3. Gather Calendar Events (Today)
-- 3. Gather Calendar Events (Today)
function M.gatherCalendarEvents()
    -- Reset to nil (Loading state)
    gatheredData.calendar = nil
    -- gatheredData.summary is NO LONGER reset here to persist it across refreshes if desired, 
    -- or we can reset it if we want a fresh start. Let's keep it if valid, or reset if nil.
    -- But refresh() typically clears everything. 
    -- Let's rely on refresh() for full clearing.
    M.updateWebview()

    local binary = os.getenv("HOME") .. "/.hammerspoon/scripts/fetch_calendar"
    
    -- Synchronous execution (fast enough, <0.5s)
    local output, status, type, rc = hs.execute(binary)
    
    local events = {}
    
    if output then
        -- Check for known error messages from the binary
        if output:match("Access denied") then
             table.insert(events, { title = "⚠️ Access denied (Grant Calendar Access)", time = "" })
        elseif output:match("No calendars") then
             table.insert(events, { title = "⚠️ No calendars found", time = "" })
        else
            -- Parse "Title|Time" output
            for line in output:gmatch("[^\r\n]+") do
                local title, timeStr = line:match("(.+)|(.+)")
                if title then
                    table.insert(events, {
                        title = title,
                        time = timeStr
                    })
                end
            end
        end
    else
        table.insert(events, { title = "⚠️ Failed to run calendar tool", time = "" })
    end
    
    gatheredData.calendar = events
    M.updateWebview()

    -- Automatically generate summary after gathering all data
    M.generateSummary()
end

-- 4. Call OpenAI for Summarization
function M.generateSummary()
    if not apiKey then
        gatheredData.summary = "⚠️ OpenAI API Key not found. Please add 'openai_api_key' to ~/.hammerspoon/secrets.lua"
        M.updateWebview()
        return
    end

    gatheredData.isGenerating = true
    
    -- Only trigger animation logic if sidebar is not already visible
    if not gatheredData.showSidebar then
        gatheredData.sidebarAnimationPlayed = false
        -- Mark animation as played after it finishes (0.4s duration)
        -- Store timer to prevent GC
        if M.animTimer then M.animTimer:stop() end
        M.animTimer = hs.timer.doAfter(0.5, function()
            gatheredData.sidebarAnimationPlayed = true
        end)
    end
    
    gatheredData.showSidebar = true
    M.updateWebview()
    
    local prompt = "Summarize my work activity for yesterday and today based on these logs. Create a concise daily standup report with: \n" ..
                   "1. Achievements (completed items)\n" ..
                   "2. In Progress (active work)\n" ..
                   "3. Meetings/Events\n\n" ..
                   "Make it brief (bullet points). Format with HTML tags for bold/lists suitable for display. DO NOT USE EMOJIS.\n\n" ..
                   "DATA:\n"
    
    -- Add Git
    prompt = prompt .. "GIT COMMITS:\n"
    for _, repo in ipairs(gatheredData.commits) do
        prompt = prompt .. "Repo: " .. repo.repo .. "\n"
        for _, msg in ipairs(repo.messages) do
            prompt = prompt .. "- " .. msg .. "\n"
        end
    end
    
    -- Add Claude
    prompt = prompt .. "\nAI CHATS (CLAUDE):\n"
    for _, item in ipairs(gatheredData.claude) do
        prompt = prompt .. "- " .. item.prompt:sub(1,100) .. " [" .. item.project .. "]\n"
    end
    
    -- Add Calendar
    prompt = prompt .. "\nCALENDAR:\n"
    if gatheredData.calendar then
        for _, event in ipairs(gatheredData.calendar) do
            prompt = prompt .. "- " .. event.title .. " at " .. event.time .. "\n"
        end
    end

    -- Add Todos
    if gatheredData.todos then
        prompt = prompt .. "\nTODOS:\n"
        prompt = prompt .. string.format("Active: %d | Completed: %d\n",
            #gatheredData.todos.active, #gatheredData.todos.completed)

        if #gatheredData.todos.active > 0 then
            prompt = prompt .. "Active tasks:\n"
            for _, todo in ipairs(gatheredData.todos.active) do
                prompt = prompt .. "- " .. todo.text .. "\n"
            end
        end

        if #gatheredData.todos.completed > 0 then
            prompt = prompt .. "Completed tasks:\n"
            for i, todo in ipairs(gatheredData.todos.completed) do
                if i <= 5 then
                    prompt = prompt .. "- " .. todo.text .. "\n"
                end
            end
        end
    end

    -- Add trends if available
    if gatheredData.trends then
        local commitsCount = 0
        for _, repo in ipairs(gatheredData.commits or {}) do
            commitsCount = commitsCount + #repo.messages
        end
        local calendarCount = gatheredData.calendar and #gatheredData.calendar or 0

        prompt = prompt .. "\n\nHISTORICAL CONTEXT (Last 7 days):\n"
        prompt = prompt .. string.format("- Average commits per day: %d (today: %d)\n",
            gatheredData.trends.avg_commits, commitsCount)
        prompt = prompt .. string.format("- Average meetings per day: %d (today: %d)\n",
            gatheredData.trends.avg_calendar_events, calendarCount)
        prompt = prompt .. string.format("- Todo completion rate: %d%%\n", gatheredData.trends.todo_completion_rate)
        prompt = prompt .. string.format("- Commit trend: %s\n", gatheredData.trends.commit_trend)
    end

    -- Add additional context if provided
    if gatheredData.additionalContext and #gatheredData.additionalContext > 0 then
        prompt = prompt .. "\nADDITIONAL CONTEXT:\n" .. gatheredData.additionalContext .. "\n"
    end

    -- Write request body to temp file
    local body = hs.json.encode({
        model = "gpt-4.1-mini",
        messages = {
            { role = "system", content = "You are a helpful assistant assisting with daily standup reports. Output CLEAN HTML (no markdown backticks, no markdown fencing, just the inner HTML content). Use <h4> for headers, <ul>/<li> for lists, <b> for emphasis. DO NOT USE EMOJIS. Provide actionable insights based on productivity trends. Be proactive with suggestions for blocked tasks or patterns you notice. Include a 'Recommendations' section if you spot opportunities for improvement or potential blockers." },
            { role = "user", content = prompt }
        },
        temperature = 0.5,
        stream = true
    })
    
    local bodyPath = os.getenv("HOME") .. "/.hammerspoon/standup_req.json"
    local f = io.open(bodyPath, "w")
    if f then
        f:write(body)
        f:close()
    else
        print("Failed to write body file")
        return
    end

    -- Clear previous summary
    gatheredData.summary = ""
    
    local task = hs.task.new("/usr/bin/curl", function(code, stdout, stderr)
        -- Completion callback
        gatheredData.isGenerating = false
        os.remove(bodyPath)

        if code ~= 0 then
             gatheredData.summary = "Error: curl failed with code " .. code .. "\n" .. stderr
             M.updateWebview()
        else
            -- Final update to ensure everything is sync
            M.updateWebview()
            -- Save to history
            saveDailySummary()
        end
    end, function(task, stdout, stderr)
        -- Stream callback
        if stdout then
            for line in stdout:gmatch("[^\r\n]+") do
                if line:match("^data: %s*DONE") then
                    -- Done
                elseif line:match("^data:") then
                    local jsonStr = line:sub(7) -- remove "data: "
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(hs.json.decode, jsonStr)
                        if ok and data and data.choices and data.choices[1] and data.choices[1].delta.content then
                            local content = data.choices[1].delta.content
                            
                            gatheredData.summary = gatheredData.summary .. content
                            
                            -- Inject into webview
                            if webview then
                                -- Escape content for JS string
                                local escaped = gatheredData.summary:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "")
                                webview:evaluateJavaScript("updateContent('" .. escaped .. "');")
                            end
                        end
                    end
                end
            end
        end
        return true
    end, {
        "-N", -- no buffer
        "-X", "POST",
        "https://api.openai.com/v1/chat/completions",
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer " .. apiKey,
        "-d", "@" .. bodyPath
    })
    
    task:start()
end


-- === UI / Webview ===

function M.generateHtml()
    local css = [[
        <style>
            * {
                box-sizing: border-box;
            }
            :root {
                --bg: #09090b;
                --sidebar-bg: #18181b;
                --card: #09090b;
                --border: #27272a;
                --text: #fafafa;
                --subtext: #a1a1aa;
                --accent: #fafafa;
                --accent-fg: #18181b;
                --hover: #27272a;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                background: var(--bg);
                color: var(--text);
                margin: 0; padding: 0;
                height: 100vh;
                width: 100vw;
                overflow: hidden;
                display: flex;
            }

            /* Layout */
            .wrapper { display: flex; width: 100%; height: 100%; overflow: hidden; }
            .main-content { flex: 1; padding: 16px; overflow-x: hidden; overflow-y: auto; display: flex; flex-direction: column; gap: 16px; position: relative; min-width: 0; }
            .dashboard-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                grid-auto-rows: minmax(180px, 1fr);
                gap: 12px;
                flex: 1;
                min-height: 0;
                min-width: 0;
                width: 100%;
            }
            .ai-sidebar {
                width: 360px;
                background: #0a0a0c;
                border-left: 1px solid var(--border);
                padding: 24px;
                overflow-y: auto;
                display: flex;
                flex-direction: column;
                box-shadow: -4px 0 24px rgba(0,0,0,0.5);
                transform: translateX(100%); /* Initial state hidden if not active */
            }

            /* ... (keep slideIn animation same) ... */
            .ai-sidebar.open {
                animation: slideIn 0.4s cubic-bezier(0.16, 1, 0.3, 1) forwards;
            }
            
            .ai-sidebar.open-no-anim {
                transform: translateX(0);
                opacity: 1;
            }
            
            @keyframes slideIn {
                from { transform: translateX(100%); opacity: 0; }
                to { transform: translateX(0); opacity: 1; }
            }

            /* Typography */
            h2 { font-size: 22px; font-weight: 700; letter-spacing: -0.5px; margin: 0; }
            h3 { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--subtext); margin: 0 0 8px 0; display: flex; align-items: center; gap: 8px; }
            p { font-size: 13px; color: var(--subtext); line-height: 1.35; margin: 0; }
            
            /* Cards & Lists */
            .card {
                border: 1px solid var(--border);
                border-radius: 8px;
                padding: 0;
                background: #0a0a0c;
                box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                transition: all 0.2s;
                display: flex;
                flex-direction: column;
                min-height: 0;
                min-width: 0;
                overflow: auto;
            }
            .card:hover {
                border-color: #3f3f46;
                transform: translateY(-2px);
                box-shadow: 0 4px 12px rgba(0,0,0,0.4);
            }
            
            /* Inner Card Spacing */
            .card h3 {
                margin: 0;
                padding: 10px 10px 6px 10px;
                font-size: 13px;
                color: var(--text);
                position: sticky;
                top: 0;
                background: #0a0a0c;
                z-index: 10;
                border-bottom: 1px solid var(--border);
            }
            
            .card p { padding: 0 10px 10px 10px; }

            .card ul { list-style: none; padding: 0 10px 10px 10px; margin: 0; }
            
            li { padding: 2px 0; font-size: 13px; color: var(--subtext); display: flex; align-items: flex-start; gap: 8px; }
            li:before { content: "•"; color: #52525b; margin-top: 1px; }
            
            .repo-title {
                color: var(--text); font-weight: 500; font-size: 13px;
                padding: 8px 10px 4px 10px;
                margin: 0 0 4px 0;
                display: block; position: sticky; top: 37px;
                background: #0a0a0c;
                z-index: 5;
                border-bottom: 1px solid var(--border);
            }
            .time-tag { background: #27272a; color: var(--text); padding: 2px 6px; border-radius: 4px; font-size: 10px; font-weight: 500; }
            .item-text { flex: 1; word-break: break-word; }

            /* Buttons */
            .btn {
                display: inline-flex; align-items: center; justify-content: center;
                border-radius: 6px; font-size: 13px; font-weight: 500;
                padding: 0 12px; height: 28px;
                cursor: pointer; text-decoration: none; transition: all 0.2s;
            }
            .btn-outline { border: 1px solid var(--border); color: var(--text); background: transparent; }
            .btn-outline:hover { background: var(--hover); }
            
            .btn-primary { background: var(--accent); color: var(--accent-fg); border: none; height: 32px; }
            .btn-primary:hover { opacity: 0.9; }

            .refresh-btn { position: absolute; top: 24px; right: 24px; z-index: 10; }
            
            /* summary content override */
            .summary-content { font-size: 13px; line-height: 1.5; color: var(--text); }
            .summary-content h4 { font-size: 13px; font-weight: 600; margin-top: 12px; margin-bottom: 6px; color: var(--text); }
            .summary-content ul { list-style: disc; padding-left: 16px; }
            .summary-content li { display: list-item; color: var(--subtext); padding: 1px 0; }
            .summary-content li:before { display: none; }
            .summary-content b { color: var(--text); font-weight: 600; }

            /* Textarea */
            .card textarea {
                width: 100%;
                margin: 0;
                background: transparent;
                border: none;
                border-bottom: 1px solid var(--border);
                color: var(--text);
                padding: 12px 0;
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                font-size: 13px;
                line-height: 1.5;
                height: 120px;
                resize: vertical;
                box-sizing: border-box;
            }
            .card textarea:focus {
                outline: none;
                border-bottom-color: var(--text);
            }

            /* Save Status Indicator */
            .save-status {
                font-size: 11px;
                color: #22c55e;
                margin-top: 4px;
                opacity: 0;
                transition: opacity 0.3s ease;
            }
            .save-status.show {
                opacity: 1;
            }

            /* Scrollbar */
            ::-webkit-scrollbar { width: 4px; }
            ::-webkit-scrollbar-track { background: transparent; }
            ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 2px; }
            ::-webkit-scrollbar-thumb:hover { background: #52525b; }

            /* Loader */
            .loader { display: flex; gap: 4px; align-items: center; margin-bottom: 16px; color: var(--subtext); font-size: 13px; }
            .dot { width: 6px; height: 6px; background: var(--text); border-radius: 50%; animation: bounce 1.4s infinite ease-in-out both; }
            .dot:nth-child(1) { animation-delay: -0.32s; }
            .dot:nth-child(2) { animation-delay: -0.16s; }
            @keyframes bounce { 0%, 80%, 100% { transform: scale(0); } 40% { transform: scale(1); } }

            /* Todo Styles */
            .filter-btn {
                background: transparent;
                border: 1px solid var(--border);
                color: var(--subtext);
                padding: 2px 8px;
                border-radius: 4px;
                font-size: 11px;
                cursor: pointer;
                transition: all 0.2s;
            }
            .filter-btn:hover {
                background: var(--hover);
            }
            .filter-btn.filter-active {
                background: var(--accent);
                color: var(--accent-fg);
                border-color: var(--accent);
            }
            input[type="checkbox"] {
                accent-color: var(--accent);
                cursor: pointer;
            }
            input[type="text"].todo-input {
                width: 100%;
                background: transparent;
                border: 1px solid var(--border);
                color: var(--text);
                padding: 8px 12px;
                font-size: 13px;
                border-radius: 6px;
                transition: all 0.2s;
                box-sizing: border-box;
            }
            input[type="text"].todo-input:focus {
                outline: none;
                border-color: var(--text);
            }
            input[type="text"].todo-input::placeholder {
                color: var(--subtext);
            }
            .todo-item {
                display: flex;
                align-items: center;
                gap: 8px;
                padding: 6px 0;
                border-bottom: 1px solid transparent;
                transition: border-color 0.2s;
            }
            .todo-item:hover {
                border-bottom-color: var(--border);
            }
            .todo-text {
                flex: 1;
                font-size: 13px;
                color: var(--text);
                word-break: break-word;
            }
            .todo-text.completed {
                text-decoration: line-through;
                color: var(--subtext);
                opacity: 0.6;
            }
            .todo-delete-btn {
                background: transparent;
                border: 1px solid var(--border);
                color: var(--subtext);
                width: 20px;
                height: 20px;
                border-radius: 4px;
                font-size: 14px;
                line-height: 1;
                cursor: pointer;
                display: flex;
                align-items: center;
                justify-content: center;
                transition: all 0.2s;
            }
            .todo-delete-btn:hover {
                background: #ef4444;
                border-color: #ef4444;
                color: white;
            }
        </style>
        <script>
            function updateContent(text) {
                var el = document.getElementById('summary-content');
                if (el) el.innerHTML = text;
            }

            // Handle todo form submission
            function handleTodoAdd(event) {
                event.preventDefault();
                var input = document.getElementById('todoInput');
                var text = input.value.trim();
                if (text) {
                    var encoded = encodeURIComponent(text);
                    window.location = 'hammerspoon://standup?action=addTodo&text=' + encoded;
                    input.value = '';
                }
                return false;
            }

            // Auto-save additional context
            var saveTimeout;
            var hideTimeout;
            document.addEventListener('DOMContentLoaded', function() {
                var contextInput = document.getElementById('contextInput');
                var saveStatus = document.getElementById('saveStatus');
                if (contextInput) {
                    contextInput.addEventListener('input', function() {
                        clearTimeout(saveTimeout);
                        clearTimeout(hideTimeout);
                        if (saveStatus) saveStatus.classList.remove('show');

                        saveTimeout = setTimeout(function() {
                            var text = encodeURIComponent(contextInput.value);
                            window.location = 'hammerspoon://standup?action=saveContext&text=' + text;

                            // Show save indicator
                            if (saveStatus) {
                                saveStatus.classList.add('show');
                                hideTimeout = setTimeout(function() {
                                    saveStatus.classList.remove('show');
                                }, 2000); // Hide after 2 seconds
                            }
                        }, 1000); // Save 1 second after user stops typing
                    });
                }
            });
        </script>
    ]]

    local html = [[<!DOCTYPE html><html><head>]] .. css .. [[</head><body>]]
    
    html = html .. [[<div class="wrapper">]]
    
    -- MAIN CONTENT
    html = html .. [[<div class="main-content">]]
        html = html .. [[<div style="display:flex; align-items:center; justify-content:space-between; padding-bottom:12px; border-bottom:1px solid var(--border);">]]
        html = html .. [[<h2>Standup Helper</h2>]]
        html = html .. [[<a href="hammerspoon://standup?action=refresh" class="btn btn-outline">↻ Refresh</a>]]
        html = html .. [[</div>]]

        -- GRID CONTAINER
        html = html .. [[<div class="dashboard-grid">]]
        
            -- 1. Git
            html = html .. [[<div class="card"><h3>Recent Commits</h3>]]
            if #gatheredData.commits == 0 then
                html = html .. [[<p>No commits found</p>]]
            else
                for _, repo in ipairs(gatheredData.commits) do
                    html = html .. [[<span class="repo-title">]] .. repo.repo .. [[</span><ul>]]
                    for _, msg in ipairs(repo.messages) do
                        html = html .. [[<li><span class="item-text">]] .. msg .. [[</span></li>]]
                    end
                    html = html .. [[</ul>]]
                end
            end
            html = html .. [[</div>]]
            
            -- 2. Calendar
            html = html .. [[<div class="card"><h3>Today's Events</h3><ul style="padding: 4px 10px 10px 10px;">]]
            if not gatheredData.calendar or #gatheredData.calendar == 0 then
                 html = html .. [[<li>No events or loading...</li>]]
            else
                for _, event in ipairs(gatheredData.calendar) do
                    html = html .. [[<li style="padding: 4px 0;"><span class="item-text">]] .. event.title .. [[</span><span class="time-tag">]] .. event.time .. [[</span></li>]]
                end
            end
            html = html .. [[</ul></div>]]
            
            -- 3. Additional Context
            html = html .. [[<div class="card">]]
            html = html .. [[<h3>Additional Context</h3>]]
            html = html .. [[<div style="padding: 0 10px 10px 10px;">]]
            html = html .. [[<textarea id="contextInput" placeholder="Type additional context here...">]]
            html = html .. (gatheredData.additionalContext or "")
            html = html .. [[</textarea>]]
            html = html .. [[<div id="saveStatus" class="save-status">✓ Saved</div>]]
            html = html .. [[<p style="padding:0; margin-top:4px; font-size:11px; color:#71717a;">Add context for AI summary (e.g., blocked items, focus areas)</p>]]
            html = html .. [[</div>]]
            html = html .. [[</div>]]

            -- 4. Todos
            html = html .. [[<div class="card" style="grid-row: span 2;">]]
            html = html .. [[<h3>Tasks]]
            html = html .. [[<div style="display:inline-flex; gap:4px; margin-left:auto;">]]

            -- Filter buttons
            local filters = {"all", "active", "completed"}
            for _, filter in ipairs(filters) do
                local activeClass = (gatheredData.todosFilter == filter) and " filter-active" or ""
                local label = filter:sub(1,1):upper() .. filter:sub(2)
                html = html .. [[<button class="filter-btn]] .. activeClass .. [[" onclick="window.location='hammerspoon://standup?action=setFilter&filter=]] .. filter .. [['">]] .. label .. [[</button>]]
            end

            html = html .. [[</div></h3>]]

            -- Todo input form
            html = html .. [[<div style="padding: 10px;">]]
            html = html .. [[<form onsubmit="return handleTodoAdd(event);">]]
            html = html .. [[<input type="text" id="todoInput" class="todo-input" placeholder="Add a task..." />]]
            html = html .. [[</form>]]
            html = html .. [[</div>]]

            -- Todo list
            html = html .. [[<div style="padding: 0 10px 10px 10px; overflow-y: auto;">]]

            if gatheredData.todos then
                local displayTodos = {}
                if gatheredData.todosFilter == "active" then
                    displayTodos = gatheredData.todos.active
                elseif gatheredData.todosFilter == "completed" then
                    displayTodos = gatheredData.todos.completed
                else
                    -- Show active first, then completed
                    for _, todo in ipairs(gatheredData.todos.active) do
                        table.insert(displayTodos, todo)
                    end
                    for _, todo in ipairs(gatheredData.todos.completed) do
                        table.insert(displayTodos, todo)
                    end
                end

                if #displayTodos == 0 then
                    html = html .. [[<p style="color: var(--subtext); font-size: 13px;">No tasks yet. Add one above!</p>]]
                else
                    for _, todo in ipairs(displayTodos) do
                        local checkedAttr = todo.completed and " checked" or ""
                        local completedClass = todo.completed and " completed" or ""

                        html = html .. [[<div class="todo-item">]]
                        html = html .. [[<input type="checkbox"]] .. checkedAttr .. [[ onchange="window.location='hammerspoon://standup?action=toggleTodo&id=]] .. todo.id .. [['" />]]
                        html = html .. [[<span class="todo-text]] .. completedClass .. [[">]] .. todo.text .. [[</span>]]
                        html = html .. [[<button class="todo-delete-btn" onclick="window.location='hammerspoon://standup?action=deleteTodo&id=]] .. todo.id .. [['">×</button>]]
                        html = html .. [[</div>]]
                    end
                end
            else
                html = html .. [[<p style="color: var(--subtext); font-size: 13px;">Loading todos...</p>]]
            end

            html = html .. [[</div>]]

            -- Archive button
            if gatheredData.todos and #gatheredData.todos.completed > 0 then
                html = html .. [[<div style="padding:0 10px 10px 10px; border-top: 1px solid var(--border); padding-top: 10px;">]]
                html = html .. [[<button onclick="window.location='hammerspoon://standup?action=archiveCompleted'" class="btn btn-outline" style="width:100%;">]]
                html = html .. [[Archive ]] .. #gatheredData.todos.completed .. [[ Completed]]
                html = html .. [[</button>]]
                html = html .. [[</div>]]
            end

            html = html .. [[</div>]]

        html = html .. [[</div>]] -- close grid
    
        -- Generate Button (Visible if sidebar not showing)
        if not gatheredData.showSidebar then
            html = html .. [[<a href="hammerspoon://standup?action=generate" class="btn btn-primary" style="position:absolute; bottom:16px; right:16px; width:auto; min-width:200px;">Generate AI Summary</a>]]
        end
        
    html = html .. [[</div>]] -- end main-content
    
    -- SIDEBAR (AI Summary)
    local sidebarClass = "ai-sidebar"
    if gatheredData.showSidebar then
        if gatheredData.sidebarAnimationPlayed then
            sidebarClass = "ai-sidebar open-no-anim"
        else
            sidebarClass = "ai-sidebar open"
        end
    end
    
    html = html .. [[<div class="]] .. sidebarClass .. [[">]]
        html = html .. [[<h3>AI Summary</h3>]]
        
        if gatheredData.isGenerating then
            html = html .. [[<div class="loader"><div class="dot"></div><div class="dot"></div><div class="dot"></div>Wait for it...</div>]]
        end
        
        html = html .. [[<div id="summary-content" class="summary-content">]]
        if gatheredData.summary then
            html = html .. gatheredData.summary
        end
        html = html .. [[</div>]]
        
        if gatheredData.summary and not gatheredData.isGenerating then
             html = html .. [[<div style="margin-top:auto; display:flex; gap:10px; padding-top:20px;">]]
             html = html .. [[<a href="hammerspoon://standup?action=generate" class="btn btn-outline" style="flex:1">Regenerate</a>]]
             html = html .. [[</div>]]
        end
        
    html = html .. [[</div>]] -- end sidebar
    
    html = html .. [[</div></body></html>]]
    
    return html
end

function M.updateWebview()
    if webview then
        webview:html(M.generateHtml())
    end
end

function M.refresh()
    gatheredData.summary = nil -- Reset summary
    gatheredData.isGenerating = false
    gatheredData.showSidebar = false -- Reset sidebar state
    gatheredData.sidebarAnimationPlayed = false -- Reset animation state
    M.updateWebview()
    
    -- Gather data
    M.gatherGitCommits()
    M.gatherClaudeHistory()
    M.gatherCalendarEvents()
    M.updateWebview()
    
    -- Note: generateSummary is now called by the calendar callback to avoid crash
end

function M.show()
    if not webview then
        local rect = hs.screen.mainScreen():frame()
        local w = rect.w * 0.7
        local h = rect.h * 0.8
        local x = rect.x + (rect.w - w) / 2
        local y = rect.y + (rect.h - h) / 2

        webview = hs.webview.new({x=x, y=y, w=w, h=h})
        webview:windowStyle({"titled", "closable", "nonactivating", "resizable"})
        webview:allowTextEntry(true)
        webview:level(hs.drawing.windowLevels.floating)
        -- webview:darkMode(true)
    end

    -- Load saved context
    gatheredData.additionalContext = loadAdditionalContext()

    -- Load todos
    local todosData = loadTodos()
    gatheredData.todos = organizeTodos(todosData)

    -- Load trends from history
    local history = loadHistory(7) -- Last 7 days
    gatheredData.trends = M.calculateTrends(history)

    webview:show()
    M.refresh()
end

function M.setup()
    hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", M.show)

    -- Register URL handler for all actions
    hs.urlevent.bind("standup", function(eventName, params)
        if params.action == "refresh" then
            M.refresh()
        elseif params.action == "generate" then
            M.generateSummary()
        elseif params.action == "saveContext" then
            -- Handle saving additional context
            if params.text then
                local decoded = urlDecode(params.text)
                gatheredData.additionalContext = decoded
                saveAdditionalContext(decoded)
            end
        -- Todo actions
        elseif params.action == "addTodo" then
            if params.text then
                M.addTodo(urlDecode(params.text))
            end
        elseif params.action == "toggleTodo" then
            M.toggleTodo(params.id)
        elseif params.action == "deleteTodo" then
            M.deleteTodo(params.id)
        elseif params.action == "editTodo" then
            if params.id and params.text then
                M.editTodo(params.id, urlDecode(params.text))
            end
        elseif params.action == "archiveCompleted" then
            M.archiveCompleted()
        elseif params.action == "setFilter" then
            if params.filter then
                gatheredData.todosFilter = params.filter
                M.updateWebview()
            end
        end
    end)
end

return M

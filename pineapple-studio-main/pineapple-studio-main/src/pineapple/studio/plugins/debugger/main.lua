local debugger = require("pineapple.studio.core.debugger")
local termview = require("pineapple.studio.ui.termview")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws, settings = studio.ui, studio.workspace, studio.settings

  local breakpoints = {}
  local session, state
  local runningPath
  local panel
  local markedView

  local function linesFor(path)
    local set = breakpoints[path]
    if not set then set = {}; breakpoints[path] = set end
    return set
  end

  local function saveBreakpoints()
    local out = {}
    for path, set in pairs(breakpoints) do
      local list = {}
      for line in pairs(set) do list[#list + 1] = line end
      if #list > 0 then table.sort(list); out[ws:relative(path)] = list end
    end
    ws:setState("breakpoints", out)
  end

  local function loadBreakpoints()
    breakpoints = {}
    local saved = ws:getState("breakpoints")
    if type(saved) == "table" then
      for rel, list in pairs(saved) do
        local set = linesFor(ws:path(rel))
        for _, line in ipairs(list) do set[line] = true end
      end
    end
  end

  local function isLua(path) return path:match("%.lua$") ~= nil end

  local function attach(e)
    local view = e.instance and e.instance.view
    if not view or e.doc.virtual or not isLua(e.doc.path) then return end
    view.breakpointLines = linesFor(e.doc.path)
    view.onGutterClick = function(v, line)
      local set = linesFor(v.doc.path)
      set[line] = not set[line] or nil
      saveBreakpoints()
      v.element:markRenderDirty()
    end
    view.element:markRenderDirty()
  end

  local function refreshViews()
    for _, e in ipairs(ui:editors()) do
      local view = e.instance and e.instance.view
      if view and view.breakpointLines then
        view.breakpointLines = linesFor(e.doc.path)
        view.element:markRenderDirty()
      end
    end
  end

  loadBreakpoints()
  for _, e in ipairs(ui:editors()) do attach(e) end
  studio.events:on("editorOpened", attach)
  ws:on("rootChanged", function() loadBreakpoints(); refreshViews() end)

  local function clearMark()
    if markedView then
      markedView.executionLine = nil
      markedView.element:markRenderDirty()
      markedView = nil
    end
  end

  local function showLocation(path, line)
    clearMark()
    if not path or not fs.exists(path) then return end
    local e = ui:openFile(path)
    local view = e and e.instance.view
    if not view then return end
    view.executionLine = line
    view:gotoLine(line, 1)
    markedView = view
  end

  local selectedFrame, expanded, varOffset = 1, {}, 0

  local function setMode(mode)
    if not panel then return end
    panel.mode = mode
    panel.consoleFrame.visible = mode == "console"
    panel.vars.visible = mode == "variables"
    panel.toolbar:markRenderDirty()
    panel.vars:markRenderDirty()
  end

  local function statusText()
    if state then
      return "Paused at " .. (state.path and fs.getName(state.path) or "?") .. ":" .. tostring(state.line)
    elseif session then
      return "Running " .. (runningPath and fs.getName(runningPath) or "")
    end
    return "Not debugging"
  end

  local actions

  local function drawToolbar(canvas, buf)
    local t = ui:theme()
    local w = canvas.width
    local bg, fg, muted = colors.gray, colors.white, colors.lightGray
    buf:fill(1, 1, w, 1, " ", fg, bg)
    panel.hits = {}
    local x = 1
    local paused = state ~= nil
    local items = {
      { "Continue", "continue", paused }, { "Over", "over", paused }, { "Into", "into", paused },
      { "Out", "out", paused }, { "Pause", "pause", session ~= nil and not paused },
      { "Stop", "stop", session ~= nil },
    }
    if not session then items = { { "Debug File", "start", true } } end
    for _, item in ipairs(items) do
      local label = " " .. item[1] .. " "
      if x + #label - 1 > w then break end
      buf:blit(x, 1, label, item[3] and fg or muted, bg)
      local action = item[2]
      if item[3] then panel.hits[#panel.hits + 1] = { x1 = x, x2 = x + #label - 1, action = action } end
      x = x + #label
    end

    local tabs = { { "Console", "console" }, { "Variables", "variables" } }
    x = x + 1
    for _, tab in ipairs(tabs) do
      local label = " " .. tab[1] .. " "
      if x + #label - 1 <= w then
        local active = panel.mode == tab[2]
        buf:blit(x, 1, label, active and t.tabActiveForeground or muted, active and t.tabActiveBackground or bg)
        panel.hits[#panel.hits + 1] = { x1 = x, x2 = x + #label - 1, action = "mode:" .. tab[2] }
        x = x + #label
      end
    end
    local status = statusText()
    if x + #status + 2 <= w then buf:blit(w - #status, 1, status, paused and colors.yellow or muted, bg) end
  end

  local function variableRows()
    local rows = {}
    local frame = state and state.frames[selectedFrame]
    if not frame then return rows end
    local function add(list, prefix, depth)
      for _, v in ipairs(list) do
        local key = prefix .. "/" .. v.name
        local isTable = type(v.value) == "table"
        rows[#rows + 1] = { depth = depth, name = v.name, value = v.value, key = key, expandable = isTable }
        if isTable and expanded[key] and depth < 6 then
          add(debugger.children(v.value), key, depth + 1)
        end
      end
    end
    rows[#rows + 1] = { header = "Locals" }
    add(frame.locals, "L" .. selectedFrame, 0)
    if #frame.upvalues > 0 then
      rows[#rows + 1] = { header = "Upvalues" }
      add(frame.upvalues, "U" .. selectedFrame, 0)
    end
    return rows
  end

  local function drawVars(canvas, buf)
    local w, h = canvas.width, canvas.height
    local bg = colors.black
    buf:fill(1, 1, w, h, " ", colors.white, bg)
    panel.varHits = {}
    if not state then
      buf:blit(2, 1, ("Not paused. Set breakpoints by clicking line numbers,"):sub(1, w - 1), colors.lightGray, bg)
      buf:blit(2, 2, ("then Debug (Shift+F9)."):sub(1, w - 1), colors.lightGray, bg)
      return
    end

    local stackW = math.min(22, math.max(12, math.floor(w / 3)))
    for i, frame in ipairs(state.frames) do
      if i > h then break end
      local active = i == selectedFrame
      local text = " " .. frame.name .. " " .. (frame.path and fs.getName(frame.path) or "?") .. ":" .. tostring(frame.line)
      buf:blit(1, i, (text .. string.rep(" ", stackW)):sub(1, stackW),
        active and colors.black or colors.white, active and colors.lightBlue or bg)
      panel.varHits[#panel.varHits + 1] = { x1 = 1, x2 = stackW, y = i, frame = i }
    end
    for y = 1, h do buf:blit(stackW + 1, y, "\149", colors.gray, bg) end
    local vx = stackW + 3
    local rows = variableRows()
    varOffset = math.max(0, math.min(varOffset, #rows - h))
    for r = 1, h do
      local row = rows[varOffset + r]
      if not row then break end
      if row.header then
        buf:blit(vx, r, row.header, colors.lightBlue, bg)
      else
        local indent = string.rep("  ", row.depth)
        local mark = row.expandable and (expanded[row.key] and "- " or "+ ") or "  "
        local name = indent .. mark .. row.name .. " = "
        buf:blit(vx, r, name:sub(1, w - vx + 1), colors.white, bg)
        local x = vx + #name
        if x <= w then
          local value = debugger.describe(row.value)
          local color = type(row.value) == "string" and colors.lime or (type(row.value) == "number" and colors.lightBlue or colors.lightGray)
          buf:blit(x, r, value:sub(1, w - x + 1), color, bg)
        end
        if row.expandable then
          local key = row.key
          panel.varHits[#panel.varHits + 1] = { x1 = vx, x2 = w, y = r, toggle = key }
        end
      end
    end
  end

  ui:addPanel({
    id = "debug", title = "Debug", location = "bottom", order = 15,
    create = function(frame)
      panel = { mode = "console" }
      panel.toolbar = frame:addCanvas({
        x = 1, y = 1, height = 1, width = function() return frame.width end,
        background = colors.gray, draw = drawToolbar,
      })
      panel.consoleFrame = frame:addFrame({
        x = 1, y = 2, width = function() return frame.width end,
        height = function() return math.max(1, frame.height - 1) end, background = ui:theme().panelBackground,
      })
      panel.console = termview.new(panel.consoleFrame, {
        onRawEvent = function(fn) return ui:onRawEvent(fn) end,
        onExit = function(v, ok, err)
          if ok then v:print("[Finished]", colors.lightGray)
          elseif err == "Stopped" then v:print("[Stopped]", colors.lightGray)
          else v:print(tostring(err), colors.red) end
          session, state, runningPath = nil, nil, nil
          clearMark()
          setMode("console")
          ui:refreshStatus()
        end,
        onLink = function(path, line)
          if path:sub(1, 1) ~= "/" then path = "/" .. path end
          local e = ui:openFile(path)
          if e and e.instance.view then e.instance.view:gotoLine(line); e.instance.view:focus() end
        end,
        onPause = function()
          selectedFrame, expanded, varOffset = 1, {}, 0
          if state then showLocation(state.path, state.line) end
          setMode("variables")
          ui:showPanel("debug", true)
          ui:refreshStatus()
        end,
      })
      panel.console:print("Debug a file with Shift+F9. Click line numbers to set breakpoints.", colors.lightGray)
      panel.vars = frame:addCanvas({
        x = 1, y = 2, width = function() return frame.width end,
        height = function() return math.max(1, frame.height - 1) end,
        background = ui:theme().panelBackground, visible = false, draw = drawVars,
      })
      panel.toolbar:onClick(function(_, _, x)
        for _, hit in ipairs(panel.hits or {}) do
          if x >= hit.x1 and x <= hit.x2 then
            local mode = hit.action:match("^mode:(.+)$")
            if mode then setMode(mode) else actions[hit.action]() end
            return
          end
        end
      end)
      panel.vars:onClick(function(_, _, x, y)
        for _, hit in ipairs(panel.varHits or {}) do
          if y == hit.y and x >= hit.x1 and x <= hit.x2 then
            if hit.frame then
              selectedFrame = hit.frame
              local f = state and state.frames[hit.frame]
              if f and f.path then showLocation(f.path, f.line) end
            elseif hit.toggle then
              expanded[hit.toggle] = not expanded[hit.toggle] or nil
            end
            panel.vars:markRenderDirty()
            return
          end
        end
      end)
      panel.vars:onScroll(function(_, dir) varOffset = math.max(0, varOffset + dir); panel.vars:markRenderDirty() end)
      return {
        focus = function() if panel.mode == "console" then panel.console:focus() else panel.vars:focus() end end,
        dispose = function()
          if panel then panel.console:dispose() end
          panel, session, state = nil, nil, nil
          clearMark()
        end,
      }
    end,
  })

  local function saveAll()
    if not settings:get("run.saveBeforeRun", true) then return true end
    for _, doc in ipairs(ws:dirtyDocuments()) do
      local ok, err = doc:save()
      if not ok then ui:notify(err, "error") return false end
    end
    return true
  end

  local function start(path)
    if not saveAll() then return end
    ui:showPanel("debug")
    if panel.console:isRunning() then panel.console:stop(true) end
    panel.console:clear()
    setMode("console")
    local env = termview.programEnv(path, ws:path(""), ui:shell())
    local fn, err = loadfile(path, "t", env)
    if not fn then
      panel.console:print(tostring(err), colors.red)
      return
    end
    session = debugger.new({
      pause = termview.PAUSE,
      isBreakpoint = function(p, line)
        local set = breakpoints[p]
        return set ~= nil and set[line] == true
      end,
      onPause = function(s) state = s end,
    })
    runningPath = path
    state = nil
    ui:refreshStatus()
    panel.console:run(session:wrap(fn, env))
    if panel then panel.toolbar:markRenderDirty() end
  end

  local function continueWith(mode)
    if not session or not state then return end
    session:resume(mode)
    state = nil
    clearMark()
    setMode("console")
    ui:refreshStatus()
    panel.console:continue()
    if panel then panel.toolbar:markRenderDirty() end
  end

  local function currentFile()
    local e = ui:activeEditor()
    if not e or e.doc.virtual or not isLua(e.doc.path) then ui:notify("Open a Lua file to debug", "info") return nil end
    return e.doc.path
  end

  actions = {
    start = function() local p = currentFile() if p then start(p) end end,
    continue = function() continueWith(nil) end,
    over = function() continueWith("over") end,
    into = function() continueWith("into") end,
    out = function() continueWith("out") end,
    pause = function()
      if session and not state then
        session:pauseSoon()
        ui:notify("Pausing at the next line the program runs", "info", 2)
      end
    end,
    stop = function()
      if panel and panel.console:isRunning() then panel.console:stop() end
    end,
  }

  local function isPaused() return state ~= nil end
  local function isDebugging() return session ~= nil end
  studio.commands:register("debug.file", actions.start)
  studio.commands:register("debug.project", function()
    local main = settings:get("run.main")
    local path = main and ws:exists(main) and ws:path(main)
    if not path then
      for _, name in ipairs({ "main.lua", "startup.lua", "init.lua" }) do
        if ws:exists(name) then path = ws:path(name) break end
      end
    end
    if not path then ui:notify("Set the project's main file first (Run > Set Project Main File)", "info") return end
    start(path)
  end)
  studio.commands:register("debug.continue", actions.continue, { enabled = isPaused })
  studio.commands:register("debug.stepOver", actions.over, { enabled = isPaused })
  studio.commands:register("debug.stepInto", actions.into, { enabled = isPaused })
  studio.commands:register("debug.stepOut", actions.out, { enabled = isPaused })
  studio.commands:register("debug.pause", actions.pause, { enabled = function() return session ~= nil and not state end })
  studio.commands:register("debug.stop", actions.stop, { enabled = isDebugging })
  studio.commands:register("debug.toggleBreakpoint", function()
    local e = ui:activeEditor()
    local view = e and e.instance.view
    if not view or not view.onGutterClick then return end
    view.onGutterClick(view, view.buffer.line)
  end)
  studio.commands:register("debug.clearBreakpoints", function()
    for _, set in pairs(breakpoints) do for line in pairs(set) do set[line] = nil end end
    saveBreakpoints()
    refreshViews()
  end)

  ui:addStatusItem({
    id = "debug.status", align = "left", priority = 21,
    text = function()
      if state then return "Paused at " .. fs.getName(state.path or "?") .. ":" .. tostring(state.line) end
      if session then return "Debugging " .. (runningPath and fs.getName(runningPath) or "") end
      return nil
    end,
  })

  plugin.state = function() return state end
  plugin.session = function() return session end
end

return plugin

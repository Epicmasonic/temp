
local termview = require("pineapple.studio.ui.termview")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws, settings = studio.ui, studio.workspace, studio.settings
  local view, running
  local lastArgs = {}
  local capture -- a run started by run.capture: { callback, timer, timedOut, stillRunning }
  local runId, currentRun = 0, nil -- every run gets an id, so callers can tell runs apart

  local function finishCapture(ok, err)
    local c = capture
    if not c then return end
    capture = nil
    if c.timer then c.timer:dispose() end
    local result = {
      id = currentRun and currentRun.id, ok = ok == true, error = err and tostring(err) or nil,
      timedOut = c.timedOut == true, running = c.stillRunning == true,
      output = view and view:transcript() or "",
    }
    pcall(c.callback, result)
  end

  local function openLink(path, line)
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    local editor = ui:openFile(path)
    if editor and editor.instance.view then
      editor.instance.view:gotoLine(line)
      editor.instance.view:focus()
    end
  end

  local function onExit(v, ok, err)
    finishCapture(ok, err)
    if ok then
      v:print("[Finished]", colors.lightGray)
    elseif err == "Stopped" then
      v:print("[Stopped]", colors.lightGray)
    else
      v:print(tostring(err), colors.red)
      v:print("[Exited with an error - click it to open the file]", colors.lightGray)
    end
    running = nil
    ui:refreshStatus()
  end

  ui:addPanel({
    id = "run", title = "Run", location = "bottom", order = 10,
    create = function(frame)
      view = termview.new(frame, {
        background = colors.black,
        foreground = colors.white,
        onRawEvent = function(fn) return ui:onRawEvent(fn) end,
        onExit = onExit,
        onLink = openLink,
      })
      view:print("Run a file with F5, or the project with F6.", colors.lightGray)
      return {
        focus = function() view:focus() end,
        dispose = function()
          finishCapture(false, "The Run panel was closed")
          view:dispose(); view = nil; running = nil; ui:refreshStatus()
        end,
      }
    end,
  })

  local function saveAll()
    if not settings:get("run.saveBeforeRun") then return true end
    for _, doc in ipairs(ws:dirtyDocuments()) do
      local ok, err = doc:save()
      if not ok then ui:notify(err, "error") return false end
    end
    return true
  end

  local function load(path, args)
    local env = termview.programEnv(path, ws:path(""), ui:shell(), args)
    return loadfile(path, "t", env)
  end

  -- Returns true once the program has started, or false and a reason.
  local function run(path, argLine, forCapture)
    if capture and not forCapture then finishCapture(false, "Interrupted: another program was started") end
    if not saveAll() then return false, "Files couldn't be saved before running" end
    local opened, panelError = ui:showPanel("run")
    if not opened or not view then
      if not panelError then
        ui:notify("The Run panel couldn't create its terminal view.", "error")
      end
      return false, panelError or "The Run panel couldn't create its terminal view"
    end
    view:clear()
    local args = termview.splitArgs(argLine)
    local fn, err = load(path, args)
    if not fn then
      view:print(tostring(err), colors.red)
      view:print("[Could not start - click the error to open it]", colors.lightGray)
      return false, tostring(err)
    end
    if #args > 0 then view:print("> " .. ws:relative(path) .. " " .. argLine, colors.lightGray) end
    running = path
    runId = runId + 1
    currentRun = { id = runId, path = path }
    ui:refreshStatus()
    view:run(fn, table.unpack(args))
    return true
  end

  local function projectArgs()
    return tostring(settings:get("run.args", "") or "")
  end

  local function askArgs(title, default, callback)
    ui:prompt({
      title = title,
      message = "Arguments, separated by spaces. Use \"double quotes\" for an argument with spaces.",
      default = default or "",
    }, function(value)
      if value ~= nil then callback(value) end
    end)
  end

  local function currentFile()
    local e = ui:activeEditor()
    if not e then ui:notify("Open a Lua file first", "info") return nil end
    if e.doc.virtual or not e.doc.path:match("%.lua$") then ui:notify(fs.getName(e.doc.path) .. " isn't a Lua file", "warning") return nil end
    return e.doc.path
  end

  local function projectMainPath()
    local configured = settings:get("run.main")
    if configured and ws:exists(configured) then return ws:path(configured) end
    for _, name in ipairs({ "main.lua", "startup.lua", "init.lua" }) do
      if ws:exists(name) then return ws:path(name) end
    end
    return nil
  end

  local function projectMain(callback)
    local configured = settings:get("run.main")
    if configured and ws:exists(configured) then return callback(ws:path(configured)) end
    for _, name in ipairs({ "main.lua", "startup.lua", "init.lua" }) do
      if ws:exists(name) then return callback(ws:path(name)) end
    end
    studio.commands:execute("run.setMain", callback)
  end

  studio.commands:register("run.file", function()
    local path = currentFile()
    if path then run(path) end
  end)

  studio.commands:register("run.project", function()
    projectMain(function(path) run(path, projectArgs()) end)
  end)

  studio.commands:register("run.fileWithArgs", function()
    local path = currentFile()
    if not path then return end
    askArgs("Run " .. fs.getName(path), lastArgs[path], function(line)
      lastArgs[path] = line
      run(path, line)
    end)
  end)

  studio.commands:register("run.projectWithArgs", function()
    projectMain(function(path)
      askArgs("Run Project", lastArgs[path] or projectArgs(), function(line)
        lastArgs[path] = line
        run(path, line)
      end)
    end)
  end)

  studio.commands:register("run.setArgs", function()
    if not ui:hasProject() then ui:notify("Open a project first", "info") return end
    askArgs("Project Arguments", projectArgs(), function(line)
      settings:set("run.args", line, "project")
      ui:notify(line == "" and "Run Project will start without arguments" or "Project arguments saved", "success", 2)
    end)
  end)

  -- For other plugins (the AI Assistant's run tools).
  --   run.capture(path, argLine, timeout, callback, options) runs path (the project's main file
  --   when path is nil) in the Run panel and calls callback({ id, ok, error, timedOut, running,
  --   output }) when it ends or `timeout` seconds pass. At the time limit the program is stopped,
  --   unless options.keepRunning, when it's left running and `running` is true.
  --   Returns false if it didn't start.
  local function startCapture(path, argLine, timeout, callback, options)
    if capture then finishCapture(false, "Interrupted: another program was started") end
    capture = { callback = callback }
    local started, err = run(path, argLine or "", true)
    if not started then
      finishCapture(false, err or "The program couldn't start")
      return false
    end
    if capture and view and view:isRunning() then
      local limit = math.max(1, tonumber(timeout) or 15)
      capture.timer = studio.timers:after(limit, function()
        if not (capture and view and view:isRunning()) then return end
        capture.timer = nil
        if options and options.keepRunning then
          capture.stillRunning = true
          finishCapture(nil, nil)
        else
          capture.timedOut = true
          view:stop()
        end
      end)
    end
    return true
  end

  studio.commands:register("run.capture", function(path, argLine, timeout, callback, options)
    if type(callback) ~= "function" then return false end
    if path == nil then
      path = projectMainPath()
      if argLine == nil then argLine = projectArgs() end
      if not path then
        callback({ ok = false, error = "The project has no main file. Set one with Run > Set Project Main File.", output = "" })
        return false
      end
    else
      path = ws:path(path)
    end
    return startCapture(path, argLine, timeout, callback, options)
  end)

  -- run.captureCommand(commandLine, ...) is run.capture for a shell command such as "ls" or
  -- "gps locate": the first word is found on the shell's program path.
  studio.commands:register("run.captureCommand", function(commandLine, timeout, callback, options)
    if type(callback) ~= "function" then return false end
    local words = termview.splitArgs(commandLine)
    local shellApi = ui:shell()
    local program = words[1] and shellApi and shellApi.resolveProgram and shellApi.resolveProgram(words[1])
    if not program then
      callback({ ok = false, error = "No program called '" .. tostring(words[1] or "") .. "'.", output = "" })
      return false
    end
    local rest = tostring(commandLine):gsub("^%s*%S+%s*", "")
    return startCapture("/" .. program:gsub("^/", ""), rest, timeout, callback, options)
  end)

  -- run.status() -> { running, id, path, output } for the program in the Run panel.
  studio.commands:register("run.status", function()
    return {
      running = view ~= nil and view:isRunning(),
      id = currentRun and currentRun.id, path = currentRun and currentRun.path,
      output = view and view:transcript() or "",
    }
  end)

  -- run.input(id, text, pressEnter) types into run `id` if it's still the one running.
  studio.commands:register("run.input", function(id, text, pressEnter)
    if not (view and view:isRunning() and currentRun and currentRun.id == id) then return false end
    for ch in tostring(text or ""):gmatch(".") do view:send("char", ch) end
    if pressEnter then
      view:send("key", keys.enter, false)
      view:send("key_up", keys.enter)
    end
    return true
  end)

  -- run.event(id, name, ...) queues an event (mouse_click, key, char...) for run `id` if it's
  -- still the one running, as if it came from the user.
  studio.commands:register("run.event", function(id, name, ...)
    if not (view and view:isRunning() and currentRun and currentRun.id == id) then return false end
    view:send(name, ...)
    return true
  end)

  -- run.screen() -> what the Run terminal shows (see termview View:screen), or nil.
  studio.commands:register("run.screen", function()
    return view and view:screen() or nil
  end)

  -- run.stopRun(id) stops run `id` if it's still the one running.
  studio.commands:register("run.stopRun", function(id)
    if not (view and view:isRunning() and currentRun and currentRun.id == id) then return false end
    view:stop()
    return true
  end)

  studio.commands:register("run.stop", function()
    if view and view:isRunning() then view:stop() end
  end, { enabled = function() return view ~= nil and view:isRunning() end })

  studio.commands:register("run.setMain", function(callback)
    local items = {}
    local function walk(dir, depth)
      if depth > 6 then return end
      for _, entry in ipairs(ws:list(dir)) do
        if entry.isDir then walk(entry.path, depth + 1)
        elseif entry.name:match("%.lua$") then items[#items + 1] = { label = ws:relative(entry.path), path = entry.path } end
      end
    end
    walk("", 0)
    if #items == 0 then ui:notify("This project has no Lua files yet", "info") return end
    ui:quickPick(items, { placeholder = "Main file to run", title = "Run" }, function(item)
      if not item then return end
      settings:set("run.main", ws:relative(item.path), "project")
      if type(callback) == "function" then callback(item.path) end
    end)
  end)

  studio.commands:register("run.fullscreen", function()
    local path = currentFile()
    if not path or not saveAll() then return end
    local fn, err = load(path)
    if not fn then
      run(path)
      return
    end
    local root = ui:root()
    local layer = root:addFrame({ x = 1, y = 1, width = root.width, height = root.height, z = 950, background = colors.black })
    local waiting = false
    local exitedAt = 0
    local full
    full = termview.new(layer, {
      onRawEvent = function(hook) return ui:onRawEvent(hook) end,
      onExit = function(v, ok, e)
        if not ok and e ~= "Stopped" then v:print(tostring(e), colors.red) end
        v:print("Press any key to return to the editor", colors.lightGray)
        waiting = true
        exitedAt = os.epoch("utc")
      end,
    })
    full.canvas:onKey(function()

      if not waiting or os.epoch("utc") - exitedAt < 200 then return end
      full:dispose()
      layer:destroy()
      local e = ui:activeEditor()
      if e then e.instance.focus(e.instance) end
    end)
    full:focus()
    full:run(fn)
  end)

  ui:addStatusItem({
    id = "run.status", align = "left", priority = 20,
    text = function() return running and ("Running " .. fs.getName(running)) or nil end,
  })
end

return plugin

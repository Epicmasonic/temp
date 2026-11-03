
local commands = require("pineapple.studio.core.commands")
local keybindings = require("pineapple.studio.core.keybindings")
local settings = require("pineapple.studio.core.settings")
local editors = require("pineapple.studio.core.editors")
local events = require("pineapple.studio.core.events")
local timers = require("pineapple.studio.core.timers")
local workspace = require("pineapple.studio.core.workspace")
local plugins = require("pineapple.studio.core.plugins")
local projects = require("pineapple.studio.core.projects")
local startscreen = require("pineapple.studio.ui.startscreen")
local files = require("pineapple.studio.core.files")
local api = require("pineapple.studio.core.api")
local aiTools = require("pineapple.studio.core.ai_tools")
local workbenchModule = require("pineapple.studio.ui.workbench")
local themes = require("pineapple.studio.ui.theme")
local keymaps = require("pineapple.studio.core.keymaps")

local M = {}
M.VERSION = api.VERSION

M.NAME = "Pineapple Studio"

local release = require("pineapple.studio.version")
M.DISPLAY_VERSION = release.version
M.BUILD = release.build

local Studio = {}
Studio.__index = Studio

local function moduleDir()
  local source = debug.getinfo(1, "S").source
  local path = source:match("^@(.*)$") or ""
  return fs.getDir(path)
end

local CORE = {
  id = "pineapple.workbench", name = "Workbench", version = M.VERSION, required = true,
  description = "Studio itself: menus, tabs, panels, projects and files.",
  contributes = {
    commands = {
      { id = "project.new", title = "New Project...", category = "Project" },
      { id = "project.open", title = "Open Folder...", category = "Project" },
      { id = "project.openRecent", title = "Open Recent...", category = "Project" },
      { id = "project.close", title = "Close Project", category = "Project" },
      { id = "file.new", title = "New File...", category = "File" },
      { id = "file.save", title = "Save", category = "File" },
      { id = "file.saveAll", title = "Save All", category = "File" },
      { id = "file.revert", title = "Revert File", category = "File" },
      { id = "file.openWith", title = "Reopen With...", category = "File" },
      { id = "file.close", title = "Close Editor", category = "File" },
      { id = "file.closeAll", title = "Close All Editors", category = "File" },
      { id = "file.closeOthers", title = "Close Other Editors", category = "File" },
      { id = "file.closeLeft", title = "Close Editors to the Left", category = "File" },
      { id = "file.closeRight", title = "Close Editors to the Right", category = "File" },
      { id = "studio.quit", title = "Quit", category = "Studio" },
      { id = "view.openPanel", title = "Open Panel...", category = "View" },
      { id = "view.toggleSidebar", title = "Toggle Left Panel", category = "View" },
      { id = "view.togglePanel", title = "Toggle Bottom Panel", category = "View" },
      { id = "view.toggleRightDock", title = "Toggle Right Panel", category = "View" },
      { id = "view.movePanel", title = "Move Panel...", category = "View" },
      { id = "view.nextEditor", title = "Next Editor", category = "View" },
      { id = "view.previousEditor", title = "Previous Editor", category = "View" },
      { id = "view.changeTheme", title = "Theme...", category = "Settings" },
      { id = "help.about", title = "About", category = "Studio" },
    },
    keybindings = {
      { key = "ctrl+n", command = "file.new" },
      { key = "ctrl+shift+n", command = "project.new" },
      { key = "ctrl+s", command = "file.save" },
      { key = "ctrl+v", command = "clipboard.paste" },
      { key = "ctrl+w", command = "file.close" },
      { key = "ctrl+q", command = "studio.quit" },
      { key = "ctrl+b", command = "view.toggleSidebar" },
      { key = "ctrl+j", command = "view.togglePanel" },
      { key = "ctrl+shift+b", command = "view.toggleRightDock" },
      { key = "ctrl+tab", command = "view.nextEditor" },
      { key = "ctrl+shift+tab", command = "view.previousEditor" },
    },
    menus = {
      { menu = "Studio", command = "help.about", group = "0" },
      { menu = "Studio", command = "project.new", group = "2" },
      { menu = "Studio", command = "project.open", group = "2" },
      { menu = "Studio", command = "project.openRecent", group = "2" },
      { menu = "Studio", command = "project.close", group = "2" },
      { menu = "File", command = "file.new", group = "1" },
      { menu = "File", command = "file.save", group = "2" },
      { menu = "File", command = "file.saveAll", group = "2" },
      { menu = "File", command = "file.revert", group = "2" },
      { menu = "File", command = "file.openWith", group = "3" },
      { menu = "File", command = "file.close", group = "3" },
      { menu = "File", command = "file.closeAll", group = "3" },
      { menu = "Studio", command = "studio.quit", group = "9" },
      { menu = "View", command = "view.openPanel", group = "1" },
      { menu = "View", command = "view.toggleSidebar", group = "1" },
      { menu = "View", command = "view.togglePanel", group = "1" },
      { menu = "View", command = "view.toggleRightDock", group = "1" },
      { menu = "View", command = "view.movePanel", group = "1" },
      { menu = "View", command = "view.nextEditor", group = "2" },
      { menu = "View", command = "view.previousEditor", group = "2" },
    },
    settings = {
      ["workbench.sidebarWidth"] = { type = "number", default = 16, title = "Sidebar width" },
      ["workbench.statusBar"] = { type = "string", default = "auto", title = "Status bar",
        description = "auto shows it on screens 25+ rows tall", options = { "auto", "always", "never" } },
      ["workbench.panelHeight"] = { type = "number", default = 8, title = "Bottom panel height" },
      ["workbench.rightWidth"] = { type = "number", default = 24, title = "Right panel width" },
      ["workbench.panelLocations"] = { type = "table", default = {}, hidden = true,
        title = "Panels moved to another dock" },
      ["workbench.dockLayout"] = { type = "table", default = {}, hidden = true,
        title = "Docked panels and active dock tabs" },
      ["plugins.disabled"] = { type = "table", default = {}, hidden = true,
        title = "Plugins turned off in the plugin manager" },
      ["keybindings.keymap"] = { type = "string", default = keymaps.DEFAULT, title = "Keymap",
        description = "Which IDE's keys to use", hidden = true,
        options = function()
          local out = {}
          for _, k in ipairs(keymaps.list) do out[#out + 1] = { value = k.id, label = k.name } end
          return out
        end },
      ["keybindings.custom"] = { type = "table", default = {}, hidden = true,
        title = "Your own keyboard shortcuts (command id = chord, or false for none)" },
      ["workbench.theme"] = { type = "string", default = "pineapple-light", title = "Colour theme", hidden = true,
        options = function()
          local out = {}
          for _, t in ipairs(themes.list()) do out[#out + 1] = { value = t.id, label = t.name } end
          return out
        end },
    },
  },
}

function M.new(options)
  options = options or {}
  local self = setmetatable({ running = false, log = {}, _hooks = {} }, Studio)

  self.shell = options.shell or shell
  local root = options.root
  self.hasProject = root ~= nil
  self.version = M.VERSION
  self.displayVersion = M.DISPLAY_VERSION
  self.name = M.NAME
  self.dataDir = options.dataDir or "/.pineapple/studio"

  local function onError(err, source)
    local msg = (source and ("[" .. tostring(source) .. "] ") or "") .. tostring(err)
    self.log[#self.log + 1] = msg
    if self.workbench then self.workbench:notify(msg, "error", 6) end
  end
  self.onError = onError

  self.events = events.new(onError)
  self.commands = commands.new()
  self.keybindings = keybindings.new(self.commands)
  self.keybindings.onError = function(err, id) onError(err, id) end
  self.settings = settings.new({
    userPath = files.join(self.dataDir, "settings.lua"),
    projectPath = root and files.join(root, ".pineapple", "project.lua") or nil,
    onError = onError,
  })
  self.settings:load()
  self.editors = editors.new()
  self.timers = timers.new(nil, nil, onError)
  self.workspace = workspace.new({ root = root or "/", onError = onError })
  if root then self.workspace:loadState() end
  self.projects = projects.new({ dataDir = self.dataDir })
  self.aiTools = aiTools.new()

  self.basalt = options.basalt or require("basalt")
  self.frame = self.basalt.createFrame(options.term or term.current())
  self.theme = options.theme or themes.load(self.settings:get("workbench.theme", themes.DEFAULT), self.basalt)

  self.plugins = plugins.new({
    commands = self.commands,
    keybindings = self.keybindings,
    settings = self.settings,
    editors = self.editors,
    events = self.events,
    timers = self.timers,
    getWorkspace = function() return self.workspace end,
    projects = self.projects,
    aiTools = self.aiTools,
    storageRoot = files.join(self.dataDir, "storage"),
    require = require,
    onError = onError,
    log = function(id, ...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      self.log[#self.log + 1] = "[" .. id .. "] " .. table.concat(parts, " ")
    end,
  })

  self.plugins._services.isDisabled = function(id)
    for _, d in ipairs(self.settings:get("plugins.disabled") or {}) do if d == id then return true end end
    return false
  end
  self.plugins._services.pluginManager = self:_pluginFacade(moduleDir())

  self.plugins._services.when = function(expr)
    return self.workbench ~= nil and self.workbench:matchesContext(expr)
  end
  self.plugins:add(CORE)

  self.workbench = workbenchModule.new(self)
  self.plugins._services.ui = self.workbench:service()
  self:_registerCoreCommands()

  local function applyKeys()
    self.keybindings:setKeymap(keymaps.get(self.settings:get("keybindings.keymap")))
    self.keybindings:setOverrides(self.settings:get("keybindings.custom") or {})
  end
  applyKeys()
  self.settings:onChange("*", function(key)
    if key == nil or (type(key) == "string" and key:match("^keybindings%.")) then
      applyKeys()
      if self.workbench then
        self.workbench:rebuildMenus()
        self.workbench.welcome:markRenderDirty()
      end
    end
    local wb = self.workbench
    if key == nil or key == "workbench.theme" then
      local id = self.settings:get("workbench.theme", themes.DEFAULT)
      if id ~= self.theme.id then wb:setTheme(id) end
    end
    if key == nil or (type(key) == "string" and key:match("^workbench%.")) then wb:layout() end
  end)

  local dirs = options.pluginDirs or {
    files.join(moduleDir(), "plugins"),
    files.join(self.dataDir, "plugins"),
  }
  for _, dir in ipairs(dirs) do self.plugins:discover(dir) end
  self.plugins:fire("onStartup")
  self.workbench:restoreDockLayout()

  self.workbench:rebuildMenus()
  self.plugins.events:on("menusChanged", function() self.workbench:rebuildMenus() end)
  self.plugins.events:on("activated", function() self.workbench:rebuildMenus() end)

  self.startScreen = startscreen.new(self, {
    open = function(path) self:openProject(path) end,
    create = function(templateId, parent, name)
      local folder, err = self.projects:create(templateId, parent, name)
      if folder then self:openProject(folder) end
      return folder, err
    end,
    settings = function()
      self.startScreen:hide()
      self.commands:execute("settings.open")
    end,
  })

  self.events:on("editorClosed", function()
    if not self.hasProject and #self.workbench.editors == 0 then self.startScreen:show("home") end
  end)
  self.events:on("themeChanged", function(t) self.startScreen:applyTheme(t) end)

  if self.hasProject then
    self.projects:addRecent(root)
    if options.restore ~= false then self.workbench:restoreSession() end
  else
    self.startScreen:show("home")
  end
  return self
end

function Studio:openProject(path, callback)
  path = files.join(path)
  if not fs.isDir(path) then
    self.workbench:notify("Not a folder: " .. path, "error")
    if callback then callback(false) end
    return
  end
  if self.hasProject then
    self.workbench:saveSession()
    self.workspace:saveState()
  end
  self.workbench:closeAll(function(closed)
    if not closed then if callback then callback(false) end return end
    self.workspace:setRoot(path)
    self.settings:setProjectPath(files.join(path, ".pineapple", "project.lua"))
    self.projects:addRecent(path)
    self.hasProject = true
    self.startScreen:hide()
    self.workbench:restoreSession()
    self.workbench:layout()
    self.events:emit("projectOpened", path)
    if callback then callback(true) end
  end)
end

function Studio:closeProject(callback)
  if not self.hasProject then self.startScreen:show("home") return end
  self.workbench:saveSession()
  self.workspace:saveState()
  self.workbench:closeAll(function(closed)
    if not closed then if callback then callback(false) end return end
    self.hasProject = false
    self.startScreen:show("home")
    self.events:emit("projectClosed")
    if callback then callback(true) end
  end)
end

function Studio:_pluginFacade(builtinDir)
  local studio = self
  local manager = function() return studio.plugins end
  local builtin = files.join(builtinDir, "plugins")
  local function persist()
    local off = {}
    for _, p in ipairs(manager():list()) do
      if p.state == "disabled" then off[#off + 1] = p.id end
    end
    studio.settings:set("plugins.disabled", off)
  end
  local facade = {}
  -- Menu entries plugins contributed to `name` (e.g. "explorer/context"), in contribution order.
  -- Entries are copies: { command, group, when, plugin }.
  function facade:menus(name)
    local out = {}
    for _, entry in ipairs(manager().menus or {}) do
      if entry.menu == name then
        out[#out + 1] = { command = entry.command, group = entry.group, when = entry.when, plugin = entry.plugin }
      end
    end
    return out
  end
  function facade:list()
    local out = {}
    for _, p in ipairs(manager():list()) do
      local m = p.manifest
      local commands = m.contributes and m.contributes.commands or {}
      out[#out + 1] = {
        id = p.id, name = m.name, version = m.version, description = m.description,

        state = (p.state == "inactive" and not m.main) and "active" or p.state,
        error = p.error and tostring(p.error) or nil, required = m.required == true,
        builtin = p.path == nil or p.path:sub(1, #builtin) == builtin, path = p.path,
        commands = #commands,
      }
    end
    return out
  end
  function facade:enable(id)
    local ok = manager():enable(id)
    if ok then persist(); studio.workbench:rebuildMenus() end
    return ok
  end
  function facade:disable(id)
    local ok = manager():disable(id)
    if ok then persist(); studio.workbench:rebuildMenus() end
    return ok
  end
  function facade:rediscover()
    local added = manager():rediscover()
    studio.workbench:rebuildMenus()
    return #added
  end
  function facade:errors()
    local out = {}
    for i, e in ipairs(manager().errors or {}) do out[i] = tostring(e) end
    return out
  end
  function facade:userFolder() return files.join(studio.dataDir, "plugins") end
  return facade
end

function Studio:fileTemplates()
  local ws = self.workspace
  return self.projects:fileTemplates({
    files.join(ws:path(""), ".pineapple", "templates"),
    files.join(self.dataDir, "templates"),
  })
end

function Studio:newFile(folder, templateId)
  local wb, ws = self.workbench, self.workspace
  folder = folder or ws:path("")
  local items = { { label = "Empty File", detail = "any name", template = { id = "empty", content = "" } } }
  for _, t in ipairs(self:fileTemplates()) do
    items[#items + 1] = { label = t.title or t.id, detail = t.extension and ("." .. t.extension) or nil,
      hint = t.description, template = t }
  end
  local where = ws:relative(folder)
  local function chosen(item)
    if not item then return end
    local t = item.template
    wb:prompt({ title = "New " .. (item.label or "File"),
      message = "Name (in " .. (where ~= "" and where or "project root") .. "):" }, function(name)
      if not name or name == "" then return end
      if t.extension and not name:lower():match("%." .. t.extension:lower() .. "$") then
        name = name .. "." .. t.extension
      end
      local path = "/" .. fs.combine(folder, name)
      if fs.exists(path) then wb:notify(name .. " already exists", "warning") return end
      local base = fs.getName(path):gsub("%.[^%.]+$", "")
      local content = t.content
      if type(content) == "function" then
        local ok, result = pcall(content, base)
        if not ok then wb:notify(tostring(result), "error") return end
        content = result
      end
      local ok, err = ws:writeFile(path, content or "")
      if not ok then wb:notify(tostring(err), "error") return end
      wb:openFile(path)
    end)
  end
  if templateId then
    for _, item in ipairs(items) do
      if item.template.id == templateId then return chosen(item) end
    end
  end
  wb:quickPick(items, { title = "New File", placeholder = "What kind of file?" }, chosen)
end

function Studio:_registerCoreCommands()
  local c, wb = self.commands, self.workbench
  local function active() return wb:activeEditor() end
  local function hasActive() return active() ~= nil end
  local function hasFile() return active() ~= nil and not active().doc.virtual end

  c:register("clipboard.paste", function()
    local text = wb:getClipboard()
    if text ~= "" then self.basalt.update("paste", text) end
  end)

  c:register("project.new", function() self.startScreen:show("new") end)

  c:register("project.open", function()
    local items, seen = {}, {}
    local function add(path, detail)
      if seen[path] or not fs.isDir(path) then return end
      seen[path] = true
      items[#items + 1] = { label = path, detail = detail, path = path }
    end
    for _, p in ipairs(self.projects:recent()) do add(p, "recent") end
    if fs.isDir("/projects") then
      for _, name in ipairs(fs.list("/projects")) do add("/projects/" .. name) end
    end
    for _, name in ipairs(fs.list("/")) do
      if name ~= "rom" and name:sub(1, 1) ~= "." then add("/" .. name) end
    end
    items[#items + 1] = { label = "Other folder...", other = true }
    wb:quickPick(items, { placeholder = "Folder to open", title = "Open Folder" }, function(item)
      if not item then return end
      if not item.other then self:openProject(item.path) return end
      wb:prompt({ title = "Open Folder", message = "Folder path:", default = "/" }, function(path)
        if path and path ~= "" then self:openProject(path) end
      end)
    end)
  end)

  c:register("project.openRecent", function()
    local items = {}
    for _, p in ipairs(self.projects:recent()) do
      items[#items + 1] = { label = fs.getName(p), detail = p, path = p }
    end
    if #items == 0 then wb:notify("No recent projects", "info") return end
    wb:quickPick(items, { placeholder = "Recent project", title = "Recent" }, function(item)
      if item then self:openProject(item.path) end
    end)
  end)

  c:register("project.close", function() self:closeProject() end,
    { enabled = function() return self.hasProject end })

  c:register("file.new", function(folder, templateId) self:newFile(folder, templateId) end)

  c:register("file.save", function()
    local e = active()
    if not e then return end
    local ok, err = e.doc:save()
    if not ok then wb:notify(err, "error") end
  end, { enabled = hasFile })

  c:register("file.saveAll", function()
    for _, doc in ipairs(self.workspace:dirtyDocuments()) do
      local ok, err = doc:save()
      if not ok then wb:notify(err, "error") end
    end
  end)

  c:register("file.revert", function()
    local e = active()
    if e then e.doc:revert() end
  end, { enabled = hasFile })

  c:register("file.openWith", function()
    local e = active()
    if not e then return end
    local items = {}
    for _, p in ipairs(self.editors:candidates(e.doc.path)) do
      items[#items + 1] = { label = p.title or p.id, detail = p == e.provider and "current" or nil, provider = p }
    end
    wb:quickPick(items, { placeholder = "Reopen with...", title = "Editors" }, function(item)
      if not item or item.provider == e.provider then return end
      local path = e.doc.path
      wb:openFile(path, item.provider.id)
    end)
  end, { enabled = hasFile })

  c:register("file.close", function() wb:closeEditor() end, { enabled = hasActive })
  c:register("file.closeAll", function() wb:closeAll() end)
  for id, which in pairs({ ["file.closeOthers"] = "others", ["file.closeLeft"] = "left", ["file.closeRight"] = "right" }) do
    c:register(id, function() wb:closeEditors(wb:editorsAround(wb:activeEditor(), which)) end, { enabled = hasActive })
  end
  c:register("studio.quit", function() self:quit() end)
  c:register("view.toggleSidebar", function() wb:toggleSidebar() end)
  c:register("view.togglePanel", function() wb:togglePanel() end)
  c:register("view.toggleRightDock", function() wb:toggleDock("right") end)
  c:register("view.movePanel", function() wb:chooseMovePanel() end)
  c:register("view.openPanel", function() wb:chooseOpenPanel() end)
  c:register("view.nextEditor", function() wb:cycleEditor(1) end)
  c:register("view.previousEditor", function() wb:cycleEditor(-1) end)
  c:register("view.changeTheme", function()
    local current = self.settings:get("workbench.theme")
    local items = {}
    for _, t in ipairs(themes.list()) do
      items[#items + 1] = { label = t.name, detail = t.id == current and "current" or nil, id = t.id }
    end
    wb:quickPick(items, { placeholder = "Select a theme", title = "Themes" }, function(item)
      if item then self.settings:set("workbench.theme", item.id) end
    end)
  end)

  c:register("help.about", function()
    wb:choose({
      title = "About",
      message = M.NAME .. " " .. M.DISPLAY_VERSION .. (M.BUILD and (" (build " .. M.BUILD .. ")") or " (development)")
        .. "\nAn in-game IDE for CC: Tweaked, built on Basalt "
        .. tostring(self.basalt.VERSION) .. ".",
      buttons = { "OK" },
    })
  end)
end

function Studio:addEventHook(fn)
  local hooks = self._hooks
  hooks[#hooks + 1] = fn
  return require("pineapple.studio.core.disposable").new(function()
    for i = #hooks, 1, -1 do if hooks[i] == fn then table.remove(hooks, i) end end
  end)
end

function Studio:handleEvent(event, ...)
  for i = #self._hooks, 1, -1 do
    local hook = self._hooks[i]
    if hook then
      local ok, err = pcall(hook, event, ...)
      if not ok then self.onError(err, "event hook") end
    end
  end
  if event == "terminate" then
    self:quit()
    return
  end
  if event == "term_resize" then
    self.basalt.update(event, ...)
    self.workbench:layout()
    self.startScreen:layout()
    self.basalt.update()
    return
  end
  if self.timers:handle(event, ...) then
    self.basalt.update()
    return
  end
  if self.keybindings:handle(event, ...) then
    self.basalt.update()
    return
  end
  if self.workbench:handlePointer(event, ...) then
    self.basalt.update()
    return
  end
  self.basalt.update(event, ...)
end

function Studio:quit(force)
  local function finish()
    if self.hasProject then
      self.workbench:saveSession()
      self.workspace:saveState()
    end
    self.plugins:deactivateAll()
    self.running = false
  end
  local dirty = self.workspace:dirtyDocuments()
  if force or #dirty == 0 then finish() return end
  local names = {}
  for i, d in ipairs(dirty) do names[i] = fs.getName(d.path) end
  self.workbench:choose({
    title = "Quit " .. M.NAME,
    message = "Unsaved changes in: " .. table.concat(names, ", "),
    buttons = { "Save All", "Discard", "Cancel" }, default = 1, cancel = 3,
  }, function(choice)
    if choice == 1 then
      for _, d in ipairs(dirty) do
        local ok, err = d:save()
        if not ok then self.workbench:notify(err, "error") return end
      end
      finish()
    elseif choice == 2 then
      for _, d in ipairs(dirty) do d:revert() end
      finish()
    end
  end)
end

function Studio:run()
  self.running = true
  self.basalt.update()
  while self.running do
    local ev = table.pack(os.pullEventRaw())
    local ok, err = pcall(self.handleEvent, self, table.unpack(ev, 1, ev.n))
    if not ok then self.onError(err, "studio") end
  end
  self.frame:cleanup()
  local t = term.current()
  t.setBackgroundColor(colors.black)
  t.setTextColor(colors.white)
  t.clear()
  t.setCursorPos(1, 1)
end

function M.run(options)
  local studio = M.new(options)
  studio:run()
  return studio
end

M.Studio = Studio
return M

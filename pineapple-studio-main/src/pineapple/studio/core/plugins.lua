local disposable = require("pineapple.studio.core.disposable")
local events = require("pineapple.studio.core.events")
local api = require("pineapple.studio.core.api")
local files = require("pineapple.studio.core.files")

local M = {}

local Manager = {}
Manager.__index = Manager

function M.new(services)
  local self = setmetatable({
    _services = services,
    _plugins = {},
    _order = {},
    menus = {},
    events = events.new(),
  }, Manager)
  services.commands.resolver = function(_, cmd)
    if cmd.plugin then self:activate(cmd.plugin) end
  end
  return self
end

local function report(self, err, pluginId)
  if self._services.onError then
    self._services.onError(err, pluginId)
  elseif printError then
    printError("[" .. tostring(pluginId) .. "] " .. tostring(err))
  end
end

local function isStringList(t)
  if type(t) ~= "table" then return false end
  for _, v in ipairs(t) do if type(v) ~= "string" then return false end end
  return true
end

function M.validate(m)
  if type(m) ~= "table" then return nil, "manifest must return a table" end
  if type(m.id) ~= "string" or not m.id:match("^[%w][%w%.%-_]*$") then
    return nil, "manifest needs an id made of letters, digits, '.', '-' or '_'"
  end
  if type(m.name) ~= "string" then return nil, m.id .. ": manifest needs a name" end
  if type(m.version) ~= "string" then return nil, m.id .. ": manifest needs a version" end
  if m.main ~= nil and type(m.main) ~= "string" then return nil, m.id .. ": main must be a file name" end
  if m.activation ~= nil and not isStringList(m.activation) then
    return nil, m.id .. ": activation must be a list of strings"
  end
  local c = m.contributes
  if c ~= nil then
    if type(c) ~= "table" then return nil, m.id .. ": contributes must be a table" end
    for key in pairs(c) do
      if key ~= "commands" and key ~= "keybindings" and key ~= "menus" and key ~= "settings"
        and key ~= "fileTemplates" then
        return nil, m.id .. ": unknown contribution type '" .. tostring(key) .. "'"
      end
    end
    for _, cmd in ipairs(c.commands or {}) do
      if type(cmd.id) ~= "string" then return nil, m.id .. ": every contributed command needs an id" end
    end
    for _, kb in ipairs(c.keybindings or {}) do
      if type(kb.key) ~= "string" or type(kb.command) ~= "string" then
        return nil, m.id .. ": keybindings need key and command"
      end
    end
    for _, menu in ipairs(c.menus or {}) do
      if type(menu.menu) ~= "string" or type(menu.command) ~= "string" then
        return nil, m.id .. ": menu entries need menu and command"
      end
    end
  end
  return true
end

function M.loadManifest(dir)
  local path = files.join(dir, "plugin.lua")
  local chunk, err = loadfile(path, "t", {})
  if not chunk then return nil, err end
  local ok, manifest = pcall(chunk)
  if not ok then return nil, path .. ": " .. tostring(manifest) end
  local valid, msg = M.validate(manifest)
  if not valid then return nil, msg end
  return manifest
end

local function addMenu(self, entry)
  self.menus[#self.menus + 1] = entry
  self.events:emit("menusChanged")
  return disposable.new(function()
    for i = #self.menus, 1, -1 do
      if self.menus[i] == entry then table.remove(self.menus, i) break end
    end
    self.events:emit("menusChanged")
  end)
end

local function registerContributions(self, p)
  local s = self._services
  local manifest = p.manifest
  p.contrib = disposable.store()
  local c = manifest.contributes or {}
  for _, cmd in ipairs(c.commands or {}) do
    p.contrib:add(s.commands:declare(cmd.id, {
      title = cmd.title, category = cmd.category, hidden = cmd.hidden, plugin = manifest.id,
    }))
  end
  for _, kb in ipairs(c.keybindings or {}) do

    local when
    if kb.when and s.when then when = function() return s.when(kb.when) end end
    p.contrib:add(s.keybindings:bind(kb.key, kb.command, when))
  end
  for key, schema in pairs(c.settings or {}) do
    p.contrib:add(s.settings:declare(key, schema))
  end

  for _, t in ipairs(c.fileTemplates or {}) do
    if s.projects and t.id then
      local template = {}
      for k, v in pairs(t) do template[k] = v end
      if t.file and p.path then
        local path = files.join(p.path, t.file)
        template.content = function() return files.read(path) or "" end
      end
      local ok, d = pcall(s.projects.registerFileTemplate, s.projects, template)
      if ok then p.contrib:add(d) else report(self, d, manifest.id) end
    end
  end
  for _, menu in ipairs(c.menus or {}) do
    p.contrib:add(addMenu(self, {
      menu = menu.menu, command = menu.command, group = menu.group, when = menu.when, plugin = manifest.id,
    }))
  end
end

function Manager:add(manifest, dir)
  local valid, msg = M.validate(manifest)
  if not valid then error(msg, 2) end
  if self._plugins[manifest.id] then error("plugin '" .. manifest.id .. "' is already loaded", 2) end

  local s = self._services
  local p = {
    id = manifest.id, manifest = manifest, path = dir and files.join(dir) or nil,
    state = "inactive", contrib = disposable.store(),
  }
  if not manifest.required and s.isDisabled and s.isDisabled(manifest.id) then
    p.state = "disabled"
  else
    registerContributions(self, p)
  end

  self._plugins[manifest.id] = p
  self._order[#self._order + 1] = manifest.id
  self.events:emit("added", p)
  return p
end

function Manager:discover(root)
  local errs = {}
  self.errors = self.errors or {}
  self._roots = self._roots or {}
  local known = false
  for _, r in ipairs(self._roots) do if r == root then known = true end end
  if not known then self._roots[#self._roots + 1] = root end
  if not fs.isDir(root) then return errs end
  local names = fs.list(root)
  table.sort(names)
  local loadedDirs = {}
  for _, p in pairs(self._plugins) do if p.path then loadedDirs[p.path] = true end end
  for _, name in ipairs(names) do
    local dir = files.join(root, name)
    if not loadedDirs[dir] and fs.isDir(dir) and fs.exists(files.join(dir, "plugin.lua")) then
      local manifest, err = M.loadManifest(dir)
      if manifest then
        local ok, addErr = pcall(self.add, self, manifest, dir)
        if not ok then errs[#errs + 1] = addErr end
      else
        errs[#errs + 1] = err
      end
    end
  end
  for _, err in ipairs(errs) do
    report(self, err, nil)
    self.errors[#self.errors + 1] = err
  end
  return errs
end

function Manager:roots()
  local out = {}
  for i, r in ipairs(self._roots or {}) do out[i] = r end
  return out
end

function Manager:rediscover()
  local before = {}
  for id in pairs(self._plugins) do before[id] = true end
  self.errors = {}
  for _, root in ipairs(self:roots()) do self:discover(root) end
  local added = {}
  for _, id in ipairs(self._order) do
    if not before[id] then
      added[#added + 1] = self._plugins[id]
      self:_startup(id)
    end
  end
  return added
end

function Manager:_startup(id)
  local p = self._plugins[id]
  if not p or p.state ~= "inactive" then return end
  for _, a in ipairs(p.manifest.activation or {}) do
    if a == "onStartup" then self:activate(id) return end
  end
end

function Manager:disable(id)
  local p = self._plugins[id]
  if not p or p.state == "disabled" then return false end
  if p.manifest.required then return false end
  self:deactivate(id)
  pcall(p.contrib.dispose, p.contrib)
  p.state = "disabled"
  p.error = nil
  self.events:emit("disabled", p)
  return true
end

function Manager:enable(id)
  local p = self._plugins[id]
  if not p then return false end
  if p.state == "failed" then
    pcall(p.contrib.dispose, p.contrib)
  elseif p.state ~= "disabled" then
    return false
  end
  registerContributions(self, p)
  p.state, p.error = "inactive", nil
  self.events:emit("enabled", p)
  self:_startup(id)
  return true
end

function Manager:get(id)
  return self._plugins[id]
end

function Manager:list()
  local out = {}
  for i, id in ipairs(self._order) do out[i] = self._plugins[id] end
  return out
end

local function pluginRequire(self, dir, env)
  local cache = {}
  local host = self._services.require or require
  return function(name)
    if cache[name] ~= nil then return cache[name] end
    local rel = name:gsub("%.", "/")
    local candidates = {}
    if dir then
      candidates[#candidates + 1] = files.join(dir, rel .. ".lua")
      candidates[#candidates + 1] = files.join(dir, rel, "init.lua")
    end
    for _, path in ipairs(candidates) do
      if fs.exists(path) and not fs.isDir(path) then
        local chunk, err = loadfile(path, "t", env)
        if not chunk then error(err, 2) end
        local result = chunk(name, path)
        if result == nil then result = true end
        cache[name] = result
        return result
      end
    end
    local result = host(name)
    cache[name] = result
    return result
  end
end

local function newEnvironment(self, dir)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.require = pluginRequire(self, dir, env)
  return env
end

function Manager:activate(id)
  local p = self._plugins[id]
  if not p then error("unknown plugin '" .. tostring(id) .. "'", 2) end
  if p.state == "active" then return true end
  if p.state == "failed" then return false end
  if p.state == "activating" then return true end

  p.state = "activating"
  local store = disposable.store()
  local s = self._services
  local info = { id = p.id, name = p.manifest.name, version = p.manifest.version, path = p.path }

  local ok, err = pcall(function()
    if not p.manifest.main then return end
    if not p.path then error("plugin has a main module but no folder", 0) end
    local env = newEnvironment(self, p.path)
    local mainPath = files.join(p.path, p.manifest.main)
    local chunk, loadErr = loadfile(mainPath, "t", env)
    if not chunk then error(loadErr, 0) end
    local module = chunk()
    if type(module) ~= "table" or type(module.activate) ~= "function" then
      error(p.manifest.main .. " must return a table with an activate function", 0)
    end
    p.module = module
    local storage = s.storageRoot and files.join(s.storageRoot, p.id) or nil
    local ctx = {
      plugin = info,
      subscriptions = store,
      storage = storage,
      studio = api.build(s, store, info),
      log = function(...)
        if s.log then s.log(p.id, ...) end
      end,
    }
    module.activate(ctx)
  end)

  if not ok then
    pcall(store.dispose, store)
    p.state = "failed"
    p.error = err
    p.module = nil
    report(self, err, id)
    self.events:emit("failed", p, err)
    return false
  end
  p.runtime = store
  p.state = "active"
  self.events:emit("activated", p)
  return true
end

function Manager:deactivate(id)
  local p = self._plugins[id]
  if not p or p.state ~= "active" then return end
  if p.module and type(p.module.deactivate) == "function" then
    local ok, err = pcall(p.module.deactivate)
    if not ok then report(self, err, id) end
  end
  local ok, err = pcall(p.runtime.dispose, p.runtime)
  if not ok then report(self, err, id) end
  p.runtime, p.module = nil, nil
  p.state = "inactive"
  self.events:emit("deactivated", p)
end

function Manager:remove(id)
  local p = self._plugins[id]
  if not p then return end
  self:deactivate(id)
  pcall(p.contrib.dispose, p.contrib)
  self._plugins[id] = nil
  for i = #self._order, 1, -1 do
    if self._order[i] == id then table.remove(self._order, i) break end
  end
  self.events:emit("removed", p)
end

function Manager:deactivateAll()
  for i = #self._order, 1, -1 do self:deactivate(self._order[i]) end
end

local function globToPattern(glob)
  local pattern = glob:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".")
  return "^" .. pattern .. "$"
end

local function matches(activation, event, arg)
  if activation == event then return true end
  local kind, value = activation:match("^(on%a+):(.+)$")
  if not kind or kind ~= event then return false end
  if kind == "onCommand" then return value == arg end
  if kind == "onOpen" then
    return type(arg) == "string" and fs.getName(arg):match(globToPattern(value)) ~= nil
  end
  return value == arg
end

function Manager:fire(event, arg)
  for _, id in ipairs(self._order) do
    local p = self._plugins[id]
    if p and p.state == "inactive" then
      for _, activation in ipairs(p.manifest.activation or {}) do
        if matches(activation, event, arg) then
          self:activate(id)
          break
        end
      end
    end
  end
end

return M

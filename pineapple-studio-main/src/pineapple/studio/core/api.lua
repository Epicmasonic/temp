local disposable = require("pineapple.studio.core.disposable")
local commandsModule = require("pineapple.studio.core.commands")

local M = {}

M.VERSION = "0.2.0"

local function tracked(getTarget, store, overrides)
  local proxy = {}
  return setmetatable(proxy, {
    __index = function(_, key)
      if overrides and overrides[key] then return overrides[key] end
      local target = getTarget()
      local value = target and target[key]
      if type(value) ~= "function" then return value end
      return function(self, ...)
        local results
        if self == proxy then
          results = table.pack(value(target, ...))
        else
          results = table.pack(value(target, self, ...))
        end
        if disposable.is(results[1]) and results[1] ~= target then store:add(results[1]) end
        return table.unpack(results, 1, results.n)
      end
    end,
    __newindex = function() error("studio API objects are read-only", 2) end,
  })
end
M.tracked = tracked

local function method(proxyRef, fn)
  return function(self, ...)
    if self == proxyRef[1] then return fn(...) end
    return fn(self, ...)
  end
end

function M.build(services, store, plugin)
  local commandsRef = {}
  local commands = tracked(function() return services.commands end, store, {
    register = method(commandsRef, function(id, handler, meta)
      local m = {}
      for k, v in pairs(meta or {}) do m[k] = v end
      m.plugin = plugin.id
      return store:add(services.commands:register(id, handler, m))
    end),
    label = method(commandsRef, function(cmd) return commandsModule.label(cmd) end),
  })
  commandsRef[1] = commands

  local timersRef = {}
  local timers = tracked(function() return services.timers end, store, {
    debounce = method(timersRef, function(seconds, fn)
      local d = services.timers:debounce(seconds, fn)
      store:add(disposable.new(d.cancel))
      return d
    end),
  })
  timersRef[1] = timers

  local workspaceRef = {}
  local workspace = tracked(services.getWorkspace, store, {
    on = method(workspaceRef, function(name, fn)
      return store:add(services.getWorkspace().events:on(name, fn))
    end),
  })
  workspaceRef[1] = workspace

  local toolsRef = {}
  local tools = tracked(function() return services.aiTools end, store, {
    register = method(toolsRef, function(spec)
      if not services.aiTools then error("AI tools are not available", 2) end
      return store:add(services.aiTools:register(plugin.id, spec))
    end),
  })
  toolsRef[1] = tools

  local studio = {
    version = M.VERSION,
    plugin = plugin,
    commands = commands,
    keybindings = tracked(function() return services.keybindings end, store),
    editors = tracked(function() return services.editors end, store),
    settings = tracked(function() return services.settings end, store),
    timers = timers,
    events = tracked(function() return services.events end, store),
    workspace = workspace,
    tools = tools,
    ui = tracked(function() return services.ui end, store),
    projects = tracked(function() return services.projects end, store),
    plugins = tracked(function() return services.pluginManager end, store),
  }
  return setmetatable(studio, { __newindex = function() error("studio API is read-only", 2) end })
end

return M

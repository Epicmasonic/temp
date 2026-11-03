local disposable = require("pineapple.studio.core.disposable")
local events = require("pineapple.studio.core.events")
local files = require("pineapple.studio.core.files")

local M = {}

local Settings = {}
Settings.__index = Settings

function M.new(options)
  options = options or {}
  local self = setmetatable({
    _schemas = {},
    _layers = { user = {}, project = {} },
    _paths = { user = options.userPath, project = options.projectPath },
    _events = events.new(options.onError),
  }, Settings)
  return self
end

function Settings:declare(key, schema)
  if self._schemas[key] then error("setting '" .. key .. "' is already declared", 2) end
  self._schemas[key] = schema or {}
  return disposable.new(function()
    if self._schemas[key] == schema then self._schemas[key] = nil end
  end)
end

function Settings:schema(key)
  return self._schemas[key]
end

function Settings:keys()
  local out = {}
  for key in pairs(self._schemas) do out[#out + 1] = key end
  table.sort(out)
  return out
end

function Settings:get(key, fallback)
  local v = self._layers.project[key]
  if v ~= nil then return v end
  v = self._layers.user[key]
  if v ~= nil then return v end
  local schema = self._schemas[key]
  if schema and schema.default ~= nil then return schema.default end
  return fallback
end

function Settings:inspect(key, scope)
  return self._layers[scope or "user"][key]
end

local function save(self, scope)
  local path = self._paths[scope]
  if path then
    local ok, err = files.writeTable(path, self._layers[scope])
    if not ok then error("cannot save settings: " .. tostring(err), 0) end
  end
end

function Settings:set(key, value, scope)
  scope = scope or "user"
  local layer = self._layers[scope]
  if not layer then error("unknown settings scope '" .. tostring(scope) .. "'", 2) end
  local schema = self._schemas[key]
  if value ~= nil and schema and schema.type and type(value) ~= schema.type then
    error("setting '" .. key .. "' must be a " .. schema.type .. ", got " .. type(value), 2)
  end
  local before = self:get(key)
  layer[key] = value
  save(self, scope)
  local after = self:get(key)
  if before ~= after then
    self._events:emit(key, after, before)
    self._events:emit("*", key, after, before)
  end
end

function Settings:onChange(key, fn)
  return self._events:on(key, fn)
end

local function loadLayer(self, scope)
  local path = self._paths[scope]
  if not path then self._layers[scope] = {}; return true end
  local value, err = files.readTable(path)
  if not value then
    self._layers[scope] = {}
    return nil, err
  end
  self._layers[scope] = value
  return true
end

function Settings:load()
  local errs = {}
  for _, scope in ipairs({ "user", "project" }) do
    local ok, err = loadLayer(self, scope)
    if not ok then errs[#errs + 1] = err end
  end
  if #errs > 0 then return nil, errs end
  return true
end

function Settings:setProjectPath(path)
  self._paths.project = path
  local ok, err = loadLayer(self, "project")
  self._events:emit("*", nil)
  return ok, err
end

return M

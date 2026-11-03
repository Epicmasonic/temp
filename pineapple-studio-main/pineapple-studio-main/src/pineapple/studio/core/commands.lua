local disposable = require("pineapple.studio.core.disposable")

local M = {}

local Registry = {}
Registry.__index = Registry

function M.new()
  return setmetatable({ _commands = {}, resolver = nil }, Registry)
end

local function entry(self, id)
  local cmd = self._commands[id]
  if not cmd then
    cmd = { id = id, title = id, category = nil }
    self._commands[id] = cmd
  end
  return cmd
end

local function copyMeta(cmd, meta)
  if not meta then return end
  for _, key in ipairs({ "title", "category", "enabled", "plugin", "hidden" }) do
    if meta[key] ~= nil then cmd[key] = meta[key] end
  end
end

function Registry:declare(id, meta)
  local cmd = entry(self, id)
  cmd.declared = true
  copyMeta(cmd, meta)
  return disposable.new(function()
    if self._commands[id] == cmd then
      cmd.declared = false
      if not cmd.handler then self._commands[id] = nil end
    end
  end)
end

function Registry:register(id, handler, meta)
  if type(id) ~= "string" or id == "" then error("command id must be a non-empty string", 2) end
  if type(handler) ~= "function" then error("command '" .. id .. "' needs a handler function", 2) end
  local cmd = entry(self, id)
  if cmd.handler then error("command '" .. id .. "' is already registered", 2) end
  cmd.handler = handler
  copyMeta(cmd, meta)
  return disposable.new(function()
    if self._commands[id] == cmd and cmd.handler == handler then
      cmd.handler = nil
      if not cmd.declared then self._commands[id] = nil end
    end
  end)
end

function Registry:get(id)
  return self._commands[id]
end

function Registry:has(id)
  return self._commands[id] ~= nil
end

function Registry:isEnabled(id)
  local cmd = self._commands[id]
  if not cmd then return false end
  if cmd.enabled then
    local ok, result = pcall(cmd.enabled)
    return ok and result ~= false
  end
  return true
end

function Registry:execute(id, ...)
  local cmd = self._commands[id]
  if not cmd then error("unknown command '" .. tostring(id) .. "'", 2) end
  if not cmd.handler and self.resolver then self.resolver(id, cmd) end
  if not cmd.handler then error("command '" .. id .. "' has no handler", 2) end
  if not self:isEnabled(id) then return nil end
  return cmd.handler(...)
end

function Registry:list(includeHidden)
  local out = {}
  for _, cmd in pairs(self._commands) do
    if includeHidden or not cmd.hidden then out[#out + 1] = cmd end
  end
  table.sort(out, function(a, b)
    local ca, cb = a.category or "", b.category or ""
    if ca ~= cb then return ca < cb end
    return (a.title or a.id) < (b.title or b.id)
  end)
  return out
end

function M.label(cmd)
  if cmd.category and cmd.category ~= "" then return cmd.category .. ": " .. (cmd.title or cmd.id) end
  return cmd.title or cmd.id
end

return M

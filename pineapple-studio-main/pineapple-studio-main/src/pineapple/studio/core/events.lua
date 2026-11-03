local disposable = require("pineapple.studio.core.disposable")

local M = {}

local Emitter = {}
Emitter.__index = Emitter

function M.new(onError)
  return setmetatable({ _listeners = {}, _onError = onError }, Emitter)
end

function Emitter:on(name, fn)
  if type(fn) ~= "function" then error("Emitter:on expects a function", 2) end
  local list = self._listeners[name]
  if not list then list = {}; self._listeners[name] = list end
  local entry = { fn = fn }
  list[#list + 1] = entry
  return disposable.new(function()
    entry.removed = true
    for i = #list, 1, -1 do
      if list[i] == entry then table.remove(list, i) break end
    end
  end)
end

function Emitter:once(name, fn)
  local d
  d = self:on(name, function(...)
    d:dispose()
    fn(...)
  end)
  return d
end

function Emitter:emit(name, ...)
  local list = self._listeners[name]
  if not list or #list == 0 then return end

  local snapshot = {}
  for i = 1, #list do snapshot[i] = list[i] end
  for i = 1, #snapshot do
    local entry = snapshot[i]
    if not entry.removed then
      local ok, err = pcall(entry.fn, ...)
      if not ok then
        if self._onError then self._onError(err, name)
        elseif printError then printError("event '" .. tostring(name) .. "': " .. tostring(err)) end
      end
    end
  end
end

function Emitter:listenerCount(name)
  local list = self._listeners[name]
  return list and #list or 0
end

return M

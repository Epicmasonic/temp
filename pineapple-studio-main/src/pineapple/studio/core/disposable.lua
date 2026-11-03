local M = {}

local Disposable = {}
Disposable.__index = Disposable

function M.new(fn)
  return setmetatable({ disposed = false, _fn = fn }, Disposable)
end

function Disposable:dispose()
  if self.disposed then return end
  self.disposed = true
  local fn = self._fn
  self._fn = nil
  if fn then fn() end
end

function M.none()
  return M.new(nil)
end

function M.is(value)
  return type(value) == "table" and type(value.dispose) == "function"
end

local Store = {}
Store.__index = Store

function M.store()
  return setmetatable({ disposed = false, _items = {} }, Store)
end

function Store:add(item)
  if type(item) == "function" then item = M.new(item) end
  if not M.is(item) then error("DisposableStore:add expects a disposable or function", 2) end
  if self.disposed then
    item:dispose()
  else
    self._items[#self._items + 1] = item
  end
  return item
end

function Store:count()
  return #self._items
end

function Store:dispose()
  if self.disposed then return end
  self.disposed = true
  local items = self._items
  self._items = {}
  local firstError
  for i = #items, 1, -1 do
    local ok, err = pcall(items[i].dispose, items[i])
    if not ok and not firstError then firstError = err end
  end
  if firstError then error(firstError, 0) end
end

function Store:clear()
  local items = self._items
  self._items = {}
  for i = #items, 1, -1 do pcall(items[i].dispose, items[i]) end
end

return M

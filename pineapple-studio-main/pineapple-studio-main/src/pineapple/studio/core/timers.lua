local disposable = require("pineapple.studio.core.disposable")

local M = {}

local Timers = {}
Timers.__index = Timers

function M.new(start, cancel, onError)
  return setmetatable({
    _start = start or os.startTimer,
    _cancel = cancel or os.cancelTimer,
    _pending = {},
    onError = onError,
  }, Timers)
end

local function run(self, fn)
  local ok, err = pcall(fn)
  if not ok then
    if self.onError then self.onError(err) elseif printError then printError(err) end
  end
end

function Timers:after(seconds, fn)
  local id = self._start(seconds)
  self._pending[id] = fn
  return disposable.new(function()
    if self._pending[id] then
      self._pending[id] = nil
      self._cancel(id)
    end
  end)
end

function Timers:every(seconds, fn)
  local current
  local stopped = false
  local function arm()
    current = self:after(seconds, function()
      if stopped then return end
      arm()
      fn()
    end)
  end
  arm()
  return disposable.new(function()
    stopped = true
    current:dispose()
  end)
end

function Timers:debounce(seconds, fn)
  local pending, lastArgs
  local debounced = {}
  local function fire()
    pending = nil
    local args = lastArgs
    lastArgs = nil
    fn(table.unpack(args, 1, args.n))
  end
  setmetatable(debounced, { __call = function(_, ...)
    lastArgs = table.pack(...)
    if pending then pending:dispose() end
    pending = self:after(seconds, fire)
  end })
  function debounced.cancel()
    if pending then pending:dispose(); pending = nil end
  end
  function debounced.flush()
    if pending then pending:dispose(); fire() end
  end
  function debounced.isPending() return pending ~= nil end
  return debounced
end

function Timers:handle(event, id)
  if event ~= "timer" then return false end
  local fn = self._pending[id]
  if not fn then return false end
  self._pending[id] = nil
  run(self, fn)
  return true
end

function Timers:pendingCount()
  local n = 0
  for _ in pairs(self._pending) do n = n + 1 end
  return n
end

return M

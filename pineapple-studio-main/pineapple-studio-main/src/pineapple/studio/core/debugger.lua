local M = {}

local Session = {}
Session.__index = Session

local MAX_FRAMES = 30
local MAX_LOCALS = 60

local function pathOf(source)
  if type(source) ~= "string" or source:sub(1, 1) ~= "@" then return nil end
  local p = source:sub(2)
  if p:sub(1, 1) ~= "/" then p = "/" .. p end
  return p
end
M.pathOf = pathOf

function M.new(options)
  options = options or {}
  local self = setmetatable({
    options = options,
    mode = options.stopOnEntry and "into" or nil,
    stepDepth = 0,
    paused = nil,
  }, Session)
  return self
end

local function depth()
  local n = 0
  while debug.getinfo(n + 3, "l") do n = n + 1 end
  return n
end

local function captureFrame(level)
  local info = debug.getinfo(level + 1, "Slnf")
  if not info then return nil end
  local frame = {
    path = pathOf(info.source), line = info.currentline,
    name = info.name or (info.what == "main" and "main chunk") or "function",
    what = info.what, locals = {}, upvalues = {},
  }
  for i = 1, MAX_LOCALS do
    local name, value = debug.getlocal(level + 1, i)
    if not name then break end
    if name:sub(1, 1) ~= "(" then frame.locals[#frame.locals + 1] = { name = name, value = value } end
  end
  if info.func then
    for i = 1, MAX_LOCALS do
      local name, value = debug.getupvalue(info.func, i)
      if not name then break end
      if name ~= "_ENV" and name ~= "" then frame.upvalues[#frame.upvalues + 1] = { name = name, value = value } end
    end
  end
  return frame
end

function Session:_include(path)
  if not path then return false end
  if self.options.include then return self.options.include(path) end
  return path:sub(1, 5) ~= "/rom/"
end

function Session:hook()
  return function(event, line)
    if event ~= "line" then return end
    local info = debug.getinfo(2, "S")
    local path = info and pathOf(info.source)
    if not self:_include(path) then return end
    local reason
    if self.mode == "into" then
      reason = "step"
    elseif self.mode == "over" or self.mode == "out" then
      local d = depth()
      if (self.mode == "over" and d <= self.stepDepth) or (self.mode == "out" and d < self.stepDepth) then
        reason = "step"
      end
    end
    if not reason and self.options.isBreakpoint and self.options.isBreakpoint(path, line) then
      reason = "breakpoint"
    end
    if not reason then return end

    self.mode = nil
    self.stepDepth = depth()
    local frames = {}
    for level = 2, MAX_FRAMES + 1 do
      local frame = captureFrame(level)
      if not frame then break end
      if frame.what ~= "C" then frames[#frames + 1] = frame end
    end
    local state = { path = path, line = line, reason = reason, frames = frames }
    self.paused = state
    if self.options.onPause then pcall(self.options.onPause, state) end
    coroutine.yield(self.options.pause)
    self.paused = nil
  end
end

function Session:wrap(fn, env)
  local hook = self:hook()
  if env then
    local co = {}
    for k, v in pairs(coroutine) do co[k] = v end
    co.create = function(f)
      local c = coroutine.create(f)
      debug.sethook(c, hook, "l")
      return c
    end
    co.wrap = function(f)
      local c = co.create(f)
      return function(...)
        local res = table.pack(coroutine.resume(c, ...))
        if not res[1] then error(res[2], 0) end
        return table.unpack(res, 2, res.n)
      end
    end
    env.coroutine = co
  end
  return function(...)
    debug.sethook(hook, "l")
    return fn(...)
  end
end

function Session:resume(mode)
  self.mode = mode
end

function Session:pauseSoon()
  self.mode = "into"
end

function M.describe(value)
  local t = type(value)
  if t == "string" then
    local s = string.format("%q", value):gsub("\\\n", "\\n")
    if #s > 60 then s = s:sub(1, 57) .. "...\"" end
    return s
  elseif t == "table" then
    local n, count = #value, 0
    for _ in pairs(value) do count = count + 1; if count > 999 then break end end
    if n > 0 and n == count then return "{...} " .. n .. " items" end
    return "{...} " .. count .. (count > 999 and "+" or "") .. " fields"
  elseif t == "function" then
    local info = debug.getinfo(value, "S")
    local where = info and pathOf(info.source)
    return "function" .. (where and (" " .. fs.getName(where) .. ":" .. (info.linedefined or "?")) or "")
  end
  return tostring(value)
end

function M.children(value, max)
  local out = {}
  if type(value) ~= "table" then return out end
  for k, v in pairs(value) do
    out[#out + 1] = { name = type(k) == "string" and k or ("[" .. tostring(k) .. "]"), key = k, value = v }
    if #out >= (max or 200) then break end
  end
  table.sort(out, function(a, b)
    local ta, tb = type(a.key), type(b.key)
    if ta ~= tb then return ta == "number" end
    if ta == "number" then return a.key < b.key end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

return M

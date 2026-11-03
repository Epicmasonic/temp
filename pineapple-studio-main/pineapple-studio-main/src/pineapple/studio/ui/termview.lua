local disposable = require("pineapple.studio.core.disposable")

local M = {}

M.PAUSE = setmetatable({}, { __tostring = function() return "<debugger pause>" end })

local ROUTED = {
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
  mouse_move = true, key = true, key_up = true, char = true, paste = true,
  term_resize = true,
}

local View = {}
View.__index = View

function M.new(host, options)
  options = options or {}
  local defaultBackground = options.background or colors.black
  local defaultForeground = options.foreground or colors.white
  local self = setmetatable({
    options = options,
    background = defaultBackground,
    foreground = defaultForeground,
    process = nil,
    _store = disposable.store(),
  }, View)

  local canvas = host:addCanvas({
    x = 1, y = 1,
    width = function() return host.width end,
    height = function() return host.height end,
    background = defaultBackground,
    draw = function(_, buf) self:_draw(buf) end,
  })
  self.canvas = canvas
  self.window = window.create(term.native(), 1, 1, math.max(1, host.width), math.max(1, host.height), false)
  -- Remember lines scrolled off the top so transcript() can return more than the visible rows.
  self.scrollback = {}
  local win, scroll = self.window, self.window.scroll
  win.scroll = function(n)
    local count = math.floor(tonumber(n) or 0)
    local _, height = win.getSize()
    for y = 1, math.min(count, height) do
      local line = win.getLine(y)
      self.scrollback[#self.scrollback + 1] = ((line or ""):gsub("%s+$", ""))
    end
    -- Kept generous so the AI Assistant sees long program output; trimmed only to bound memory.
    if #self.scrollback > 20000 then
      local keep = {}
      for i = #self.scrollback - 15000 + 1, #self.scrollback do keep[#keep + 1] = self.scrollback[i] end
      self.scrollback = keep
    end
    return scroll(n)
  end
  self.window.setBackgroundColor(defaultBackground)
  self.window.setTextColor(defaultForeground)
  self.window.clear()

  canvas:onClick(function(_, btn, x, y)
    if self:isRunning() then self:send("mouse_click", btn, x, y)
    else self:_clickLink(y) end
  end)
  canvas:onClickUp(function(_, btn, x, y) self:send("mouse_up", btn, x, y) end)
  canvas:onDrag(function(_, btn, x, y) self:send("mouse_drag", btn, x, y) end)
  canvas:onScroll(function(_, dir, x, y) self:send("mouse_scroll", dir, x, y) end)
  canvas:onKey(function(_, key, held) self:send("key", key, held) end)
  canvas:onKeyUp(function(_, key) self:send("key_up", key) end)
  canvas:onChar(function(_, ch) self:send("char", ch) end)
  canvas:onPaste(function(_, text) self:send("paste", text) end)

  if options.onRawEvent then
    self._store:add(options.onRawEvent(function(event, ...)
      if not ROUTED[event] then self:send(event, ...) end
    end))
  end
  return self
end

function View:isRunning()
  return self.process ~= nil
end

function View:_syncSize()
  local w, h = math.max(1, self.canvas.width), math.max(1, self.canvas.height)
  local cw, ch = self.window.getSize()
  if cw ~= w or ch ~= h then
    self.window.reposition(1, 1, w, h)
    if self.process then self:send("term_resize") end
  end
end

function View:_draw(buf)
  self:_syncSize()
  local _, h = self.window.getSize()
  for y = 1, h do
    local text, fg, bg = self.window.getLine(y)
    if text then buf:drawBlit(1, y, text, fg, bg) end
  end
  local root = self.canvas:getRoot()
  if self.process and root.getFocused and root:getFocused() == self.canvas then
    local cx, cy = self.window.getCursorPos()
    self.canvas:setCursor(cx, cy, self.window.getCursorBlink(), self.window.getTextColor())
  end
end

function View:print(text, color)
  self:_syncSize()
  local previous = term.redirect(self.window)
  if color and term.isColor() then term.setTextColor(color) end
  print(text)
  term.setTextColor(self.foreground)
  term.redirect(previous)
  self.canvas:markRenderDirty()
end

function View:clear()
  self.scrollback = {}
  self:_syncSize()
  self.window.setBackgroundColor(self.background)
  self.window.setTextColor(self.foreground)
  self.window.clear()
  self.window.setCursorPos(1, 1)
  self.canvas:markRenderDirty()
end

local function finish(self, ok, err)
  local proc = self.process
  if not proc then return end
  self.process = nil
  self.window.setCursorBlink(false)
  if self.options.onExit then pcall(self.options.onExit, self, ok, err) end
  self.canvas:markRenderDirty()
end

local function step(self, ...)
  local proc = self.process
  local previous = term.redirect(proc.term)
  local ok, result = coroutine.resume(proc.co, ...)
  proc.term = term.current()
  term.redirect(previous)
  return ok, result
end

local function afterStep(self, event, ok, result)
  local proc = self.process
  if not proc then return end
  if ok and result == M.PAUSE then
    proc.paused = true
    if self.options.onPause then pcall(self.options.onPause, self) end
    self.canvas:markRenderDirty()
    return
  end
  if not ok then
    if event == "terminate" and tostring(result):match("Terminated$") then
      finish(self, true, nil)
    else
      finish(self, false, result)
    end
  elseif coroutine.status(proc.co) == "dead" then
    finish(self, true, nil)
  else
    proc.filter = result
  end
  self.canvas:markRenderDirty()
end

local function resume(self, event, ...)
  local proc = self.process
  if not proc then return end
  if proc.paused then

    if #proc.queue < 256 then proc.queue[#proc.queue + 1] = table.pack(event, ...) end
    return
  end
  if proc.filter ~= nil and proc.filter ~= event and event ~= "terminate" then return end
  local ok, result = step(self, event, ...)
  afterStep(self, event, ok, result)
end

function View:send(event, ...)
  if self.process then resume(self, event, ...) end
end

function View:isPaused()
  return self.process ~= nil and self.process.paused == true
end

function View:continue()
  local proc = self.process
  if not proc or not proc.paused then return end
  proc.paused = false
  local ok, result = step(self)
  afterStep(self, nil, ok, result)
  while self.process == proc and not proc.paused and #proc.queue > 0 do
    local e = table.remove(proc.queue, 1)
    resume(self, table.unpack(e, 1, e.n))
  end
end

function View:run(fn, ...)
  self:stop(true)
  self:_syncSize()
  self.window.setCursorBlink(false)
  self.process = { co = coroutine.create(fn), term = self.window, filter = nil, queue = {} }
  local ok, result = step(self, ...)
  afterStep(self, nil, ok, result)
end

function View:stop(quiet)
  local proc = self.process
  if not proc then return end
  if quiet or proc.paused then

    self.process = nil
    if coroutine.close then pcall(coroutine.close, proc.co) end
    if not quiet and self.options.onExit then pcall(self.options.onExit, self, false, "Stopped") end
    self.canvas:markRenderDirty()
    return
  end
  resume(self, "terminate")
  if self.process == proc then
    self.process = nil
    if coroutine.close then pcall(coroutine.close, proc.co) end
    if self.options.onExit then pcall(self.options.onExit, self, false, "Stopped") end
  end
  self.canvas:markRenderDirty()
end

function View:_clickLink(y)
  if not self.options.onLink then return end
  local w = self.window.getSize()
  local joined = ""
  for row = math.max(1, y - 3), y do
    joined = joined .. (self.window.getLine(row) or "")
  end
  local found, foundLine
  for path, line in joined:gmatch("([%w%._/%-]+%.lua):(%d+):") do found, foundLine = path, line end
  if found then self.options.onLink(found, tonumber(foundLine)) end
end

function View:lines()
  local out = {}
  local _, h = self.window.getSize()
  for y = 1, h do out[y] = (self.window.getLine(y) or ""):gsub("%s+$", "") end
  return out
end

-- What the terminal shows now: { width, height, lines = { { text, fg, bg } }, cursor = { x, y, blink } },
-- with colours as blit strings (one hex digit per character).
function View:screen()
  local w, h = self.window.getSize()
  local lines = {}
  for y = 1, h do
    local text, fg, bg = self.window.getLine(y)
    lines[y] = { text = text or "", fg = fg or "", bg = bg or "" }
  end
  local cx, cy = self.window.getCursorPos()
  return { width = w, height = h, lines = lines, cursor = { x = cx, y = cy, blink = self.window.getCursorBlink() } }
end

-- Everything printed since the last clear: scrolled-off lines plus the screen.
function View:transcript()
  local out = {}
  for _, line in ipairs(self.scrollback or {}) do out[#out + 1] = line end
  for _, line in ipairs(self:lines()) do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return table.concat(out, "\n")
end

function View:focus()
  self.canvas:focus()
  self.canvas:markRenderDirty()
end

function View:dispose()
  self:stop(true)
  self._store:dispose()
  self.canvas:destroy()
end

-- Splits a command line into arguments the way the CraftOS shell does: words are separated
-- by spaces or tabs, and text inside double quotes stays one argument.
function M.splitArgs(line)
  local words, quoted = {}, false
  for part in ((line or "") .. "\""):gmatch("(.-)\"") do
    if quoted then
      words[#words + 1] = part
    else
      for word in part:gmatch("[^ \t]+") do words[#words + 1] = word end
    end
    quoted = not quoted
  end
  return words
end

function M.programEnv(path, dir, parentShell, args)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  dir = (dir or ""):gsub("^/", "")
  if parentShell then
    local programShell = setmetatable({}, { __index = parentShell })
    programShell.dir = function() return dir end
    programShell.setDir = function(d) dir = d end
    programShell.resolve = function(p)
      if p:sub(1, 1) == "/" or p:sub(1, 1) == "\\" then return fs.combine("", p) end
      return fs.combine(dir, p)
    end
    programShell.getRunningProgram = function() return (path:gsub("^/", "")) end
    env.shell = programShell
    env.multishell = multishell
  end
  env.arg = { [0] = path }
  for i, value in ipairs(args or {}) do env.arg[i] = value end
  if fs.exists("/rom/modules/main/cc/require.lua") then
    local make = dofile("/rom/modules/main/cc/require.lua").make
    env.require, env.package = make(env, fs.getDir(path))
    local libraryDirs = { fs.combine(dir, "lib"), "lib" }
    for _, libraryDir in ipairs(libraryDirs) do
      if libraryDir:sub(1, 1) ~= "/" then libraryDir = "/" .. libraryDir end
      if fs.isDir(libraryDir) then
        env.package.path = env.package.path .. ";" .. libraryDir .. "/?.lua;" .. libraryDir .. "/?/init.lua"
      end
    end
  end
  return env
end

return M

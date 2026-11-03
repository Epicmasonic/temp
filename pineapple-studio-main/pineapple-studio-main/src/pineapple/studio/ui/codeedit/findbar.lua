local search = require("pineapple.studio.core.search")
local dialogs = require("pineapple.studio.ui.dialogs")

local M = {}

local FindBar = {}
FindBar.__index = FindBar

function M.new(view, host)
  local self = setmetatable({
    view = view,
    host = host,
    query = { text = "", cursor = 1 },
    replacement = { text = "", cursor = 1 },
    field = "query",
    replaceMode = false,
    caseSensitive = false,
    matches = {},
    current = 0,
    visible = false,
    _hits = {},
  }, FindBar)
  self.canvas = host:addCanvas({
    x = 1, y = 1, height = 1, z = 2, visible = false,
    width = function() return host.width end,
    background = view.theme.findBackground or view.theme.panelHeaderBackground,
    draw = function(_, buf) self:_draw(buf) end,
  })
  local c = self.canvas
  c:onClick(function(_, _, x, y) self:_onClick(x, y) end)
  c:onKey(function(_, key) self:_onKey(key) end)
  c:onKeyUp(function(_, key) if key == (keys.escape or -1) then self:close() end end)
  c:onChar(function(_, ch) self:_insert(ch) end)
  c:onPaste(function(_, text) self:_insert((text:gsub("\n.*", ""))) end)
  return self
end

function FindBar:height()
  if not self.visible then return 0 end
  return self.replaceMode and 2 or 1
end

function FindBar:open(replaceMode, initial)
  self.visible = true
  self.replaceMode = replaceMode and true or false
  self.field = "query"
  local b = self.view.buffer
  self.originLine, self.originCol = b:selection()
  if not self.originLine then self.originLine, self.originCol = b.line, b.col end
  if initial and initial ~= "" then
    self.query.text, self.query.cursor = initial, #initial + 1
  end
  self.canvas.visible = true
  self.canvas.height = self:height()
  self.view:_layoutBar()
  self:update(true)
  self.canvas:focus()
  self.canvas:markRenderDirty()
end

function FindBar:close()
  if not self.visible then return end
  self.visible = false
  self.canvas.visible = false
  self.matches, self.current = {}, 0
  self.view.matchLines = nil
  self.view:_layoutBar()
  self.view:focus()
end

function FindBar:update(jump)
  local view = self.view
  self.matches = search.findAll(view.doc.lines, self.query.text, self.caseSensitive)
  local byLine = {}
  for i, m in ipairs(self.matches) do
    local list = byLine[m.line]
    if not list then list = {}; byLine[m.line] = list end
    list[#list + 1] = m
    m.index = i
  end
  view.matchLines = #self.matches > 0 and byLine or nil
  self.current = 0
  if #self.matches == 0 then
    view.element:markRenderDirty()
    self.canvas:markRenderDirty()
    return
  end

  local l1, c1, l2, c2 = view.buffer:selection()
  for i, m in ipairs(self.matches) do
    if l1 and m.line == l1 and l1 == l2 and m.col == c1 and m.col + m.len == c2 then self.current = i end
  end
  if jump then
    local target = 1
    for i, m in ipairs(self.matches) do
      if m.line > self.originLine or (m.line == self.originLine and m.col >= self.originCol) then
        target = i; break
      end
    end
    self:_select(target)
  end
  view.element:markRenderDirty()
  self.canvas:markRenderDirty()
end

function FindBar:_select(index)
  local m = self.matches[index]
  if not m then return end
  self.current = index
  self.view:select(m.line, m.col, m.line, m.col + m.len)
  self.canvas:markRenderDirty()
end

function FindBar:step(delta)
  if #self.matches == 0 then return end
  local b = self.view.buffer
  local l1, c1 = b:selection()
  local line, col = l1 or b.line, c1 or b.col
  local target
  if delta > 0 then
    for i, m in ipairs(self.matches) do
      if m.line > line or (m.line == line and m.col > col) then target = i; break end
    end
    target = target or 1
  else
    for i = #self.matches, 1, -1 do
      local m = self.matches[i]
      if m.line < line or (m.line == line and m.col < col) then target = i; break end
    end
    target = target or #self.matches
  end
  self:_select(target)
end

function FindBar:replaceOne()
  if self.view.doc.readOnly or #self.matches == 0 then return end
  if self.current == 0 then self:step(1) return end
  local m = self.matches[self.current]
  self.view:select(m.line, m.col, m.line, m.col + m.len)
  self.view.buffer:insert(self.replacement.text)
  self.view:changed()
  local b = self.view.buffer
  self.originLine, self.originCol = b.line, b.col
  self:update(true)
end

function FindBar:replaceAll()
  if self.view.doc.readOnly or #self.matches == 0 then return 0 end
  local count = #self.matches
  self.view.buffer:replaceRanges(self.matches, self.replacement.text)
  self.view:changed()
  self:update(false)
  return count
end

local function isShift(self)
  local root = self.canvas:getRoot()
  return root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
end

function FindBar:_insert(text)
  local state = self[self.field]
  dialogs.insertField(state, text)
  if self.field == "query" then self:update(true) end
  self.canvas:markRenderDirty()
end

function FindBar:_onKey(key)
  local state = self[self.field]
  if key == keys.enter or key == keys.numPadEnter then
    if self.field == "replacement" then self:replaceOne()
    else self:step(isShift(self) and -1 or 1) end
  elseif key == keys.down then self:step(1)
  elseif key == keys.up then self:step(-1)
  elseif key == keys.tab then
    if self.replaceMode then self.field = self.field == "query" and "replacement" or "query" end
  elseif dialogs.editField(state, key) then
    if self.field == "query" then self:update(true) end
  else
    return
  end
  self.canvas:markRenderDirty()
end

function FindBar:_onClick(x, y)
  for _, hit in ipairs(self._hits) do
    if y == hit.y and x >= hit.from and x <= hit.to then
      hit.action()
      self.canvas:markRenderDirty()
      return
    end
  end
end

function FindBar:_draw(buf)
  local theme = self.view.theme
  local w = self.canvas.width
  local bg = theme.findBackground or theme.panelHeaderBackground
  local fg = theme.findForeground or theme.panelHeaderForeground
  local fieldTheme = setmetatable({ inputBackground = theme.findInputBackground or theme.inputBackground },
    { __index = theme })
  local hits = {}
  self._hits = hits
  local narrow = w < 36

  local function button(x, y, label, action, active)
    buf:blit(x, y, label, active and theme.accentForeground or fg, active and theme.accent or bg)
    hits[#hits + 1] = { y = y, from = x, to = x + #label - 1, action = action }
    return x + #label
  end

  buf:fill(1, 1, w, self:height(), " ", fg, bg)
  local count
  if self.query.text == "" then count = ""
  elseif #self.matches == 0 then count = "0/0"
  else count = (self.current > 0 and self.current or "?") .. "/" .. #self.matches end
  local right = narrow and string.format("%-4s", count .. " ") or string.format(" %-5s ", count)
  local buttons = narrow and 7 or 9
  local label = narrow and "" or " Find "
  local fieldX = narrow and 2 or #label + 1
  local fieldW = math.max(4, w - fieldX - #right - buttons)
  local cursorX = dialogs.drawField(buf, fieldTheme, self.query, fieldX, 1, fieldW, narrow and "Find" or nil)
  if label ~= "" then buf:blit(1, 1, label, fg, bg) end
  local x = fieldX + fieldW
  local countColour = (#self.matches == 0 and self.query.text ~= "") and colors.red or fg
  buf:blit(x, 1, right, countColour, bg)
  x = x + #right
  x = button(x, 1, "Aa", function() self.caseSensitive = not self.caseSensitive; self:update(true) end,
    self.caseSensitive) + 1
  x = button(x, 1, "<", function() self:step(-1) end) + 1
  x = button(x, 1, ">", function() self:step(1) end) + 1
  button(x, 1, "x", function() self:close() end)
  hits[#hits + 1] = { y = 1, from = fieldX, to = fieldX + fieldW - 1, action = function() self.field = "query" end }
  local cursorY = 1

  if self.replaceMode then
    local rlabel = narrow and "" or " Repl "
    local rx = cursorX
    rx = dialogs.drawField(buf, fieldTheme, self.replacement, fieldX, 2, fieldW, narrow and "Replace" or nil)
    if rlabel ~= "" then buf:blit(1, 2, rlabel, fg, bg) end
    local bx = fieldX + fieldW + 1
    local inputBg = theme.findInputBackground or theme.inputBackground
    local function rbutton(text, action)
      buf:blit(bx, 2, text, fg, inputBg)
      hits[#hits + 1] = { y = 2, from = bx, to = bx + #text - 1, action = action }
      bx = bx + #text + 1
    end
    rbutton(narrow and "Rep" or "Replace", function() self:replaceOne() end)
    rbutton("All", function()
      local n = self:replaceAll()
      if self.onReplaced then self.onReplaced(n) end
    end)
    hits[#hits + 1] = { y = 2, from = fieldX, to = fieldX + fieldW - 1, action = function() self.field = "replacement" end }
    if self.field == "replacement" then cursorX, cursorY = rx, 2 end
  end

  local root = self.canvas:getRoot()
  if root.getFocused and root:getFocused() == self.canvas then
    self.canvas:setCursor(cursorX, cursorY, true, theme.inputForeground)
  end
end

function FindBar:applyTheme(theme)
  self.canvas.background = theme.findBackground or theme.panelHeaderBackground
  self.canvas:markRenderDirty()
end

function FindBar:dispose()
  self.canvas:destroy()
end

return M

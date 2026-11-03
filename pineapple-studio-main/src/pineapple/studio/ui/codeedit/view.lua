local bufferModule = require("pineapple.studio.ui.codeedit.buffer")
local lexer = require("pineapple.studio.ui.codeedit.lexer")
local languages = require("pineapple.studio.ui.codeedit.languages")
local findbar = require("pineapple.studio.ui.codeedit.findbar")
local blocks = require("pineapple.studio.ui.codeedit.blocks")
local scrollbar = require("pineapple.studio.ui.scrollbar")
local disposable = require("pineapple.studio.core.disposable")

local M = {}

M.clipboard = ""

local View = {}
View.__index = View

function M.new(host, doc, options)
  options = options or {}
  -- options.language: a spec from languages.lua (or its id), or false for plain text.
  -- Older callers pass only `highlight`, which means Lua.
  local language = options.language
  if type(language) == "string" then language = languages.get(language) end
  if language == nil then language = options.highlight ~= false and languages.get("lua") or nil end
  if language == false then language = nil end
  local self = setmetatable({
    doc = doc,
    theme = options.theme,
    buffer = bufferModule.new(doc, { tabSize = options.tabSize or 2 }),
    language = language,
    highlight = language ~= nil,
    structure = language ~= nil and language.structure == "lua",
    scrollX = 0, scrollY = 0,
    _reveal = true,
    host = host,
    completer = options.completer,
    insertText = options.insertText,
    getClipboard = options.getClipboard,
    setClipboard = options.setClipboard,
    _store = disposable.store(),
    _cursorListeners = {},
  }, View)
  self.highlighter = lexer.highlighter(function() return doc.lines end, language and language.tokenize)
  if options.onCursor then self._cursorListeners[1] = options.onCursor end

  local canvas = host:addCanvas({
    x = 1, y = 1,
    width = function() return host.width end,
    height = function() return math.max(1, host.height - self:barHeight()) end,
    background = self.theme.editorBackground,
    draw = function(_, buf) self:_draw(buf) end,
  })
  self.element = canvas

  canvas:onClick(function(_, btn, x, y) self:closeCompletion(); self:_onClick(btn, x, y) end)
  canvas:onDrag(function(_, btn, x, y) self:_onDrag(x, y) end)
  canvas:onClickUp(function() self._scrollDrag, self._hscrollDrag = false, false end)
  canvas:onScroll(function(_, dir)
    self:closeCompletion()

    local root = canvas:getRoot()
    local shift = root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
    if shift then self:scrollColumns(dir * 4) else self:scrollBy(dir * 3) end
  end)
  canvas:onKey(function(_, key, held) self:_onKey(key, held) end)
  canvas:onKeyUp(function(_, key)
    if key == (keys.escape or -1) then
      if self.completion then self:closeCompletion()
      elseif self.find and self.find.visible then self.find:close() end
    end
  end)
  canvas:onChar(function(_, ch) self:_onChar(ch) end)
  canvas:onPaste(function(_, text) self:closeCompletion(); self:insert(text) end)
  canvas:onBlur(function()

    local root = canvas:getRoot()
    local focused = root.getFocused and root:getFocused()
    if not (self.completion and focused == self.completion.popup) then self:closeCompletion() end
  end)

  self._store:add(doc:on("change", function(_, info)
    self._contentWidth = nil
    self.buffer:revalidate()
    self.highlighter:invalidate(info and info.line or 1)
    if self.find and self.find.visible then self.find:update(false) end
    canvas:markRenderDirty()
  end))
  return self
end

function View:barHeight()
  return self.find and self.find:height() or 0
end

function View:_layoutBar()
  self.element.y = 1 + self:barHeight()
  self.element:markRenderDirty()
  if self.host.markDirty then self.host:markDirty() end
end

function View:openFind(replace)
  self:closeCompletion()
  if not self.find then
    self.find = findbar.new(self, self.host)
    self.find.onReplaced = function(n) if self.onReplaced then self.onReplaced(n) end end
  end
  local initial
  if self.buffer:hasSelection() then
    local text = self.buffer:getSelectedText()
    if not text:find("\n") then initial = text end
  end
  self.find:open(replace, initial)
end

function View:findNext(delta)
  if self.find and #self.find.matches > 0 then
    self.find:step(delta or 1)
  else
    self:openFind(false)
  end
end

function View:select(l1, c1, l2, c2)
  self:closeCompletion()
  self.buffer:setCursor(l1, c1)
  self.buffer:setCursor(l2, c2, true)
  self:changed()
end

function View:gutterWidth()
  return math.max(3, #tostring(#self.doc.lines) + 1) + (self.breakpointLines and 1 or 0)
end

function View:contentWidth()
  if self._contentWidth and self._contentLines == self.doc.lines then return self._contentWidth end
  local longest = 0
  for _, line in ipairs(self.doc.lines) do
    if #line > longest then longest = #line end
  end
  self._contentWidth, self._contentLines = longest + 1, self.doc.lines
  return longest + 1
end

function View:scrollbars()
  local w, h = self.element.width, self.element.height
  local gw, total, wide = self:gutterWidth(), #self.doc.lines, self:contentWidth()
  local v = total > h
  local hb = h > 2 and wide > w - gw - (v and 1 or 0)
  if hb and not v then v = total > h - 1 end
  if v and not hb then hb = h > 2 and wide > w - gw - 1 end
  return v, hb
end

function View:hasScrollbar()
  return (self:scrollbars())
end

function View:hasHScrollbar()
  return select(2, self:scrollbars())
end

function View:textWidth()
  return math.max(1, self.element.width - self:gutterWidth() - (self:hasScrollbar() and 1 or 0))
end

function View:textHeight()
  return math.max(1, self.element.height - (self:hasHScrollbar() and 1 or 0))
end

function View:positionAt(x, y)
  local line = math.max(1, math.min(#self.doc.lines, self.scrollY + y))
  local col = x - self:gutterWidth() + self.scrollX
  return line, math.max(1, col)
end

local function clampScroll(self)
  local maxY = math.max(0, #self.doc.lines - self:textHeight())
  self.scrollY = math.max(0, math.min(self.scrollY, maxY))
  local maxX = math.max(0, self:contentWidth() - self:textWidth())
  self.scrollX = math.max(0, math.min(self.scrollX, maxX))
end

function View:reveal()
  local b = self.buffer
  local h, w = self:textHeight(), self:textWidth()
  if b.line <= self.scrollY then self.scrollY = b.line - 1 end
  if b.line > self.scrollY + h then self.scrollY = b.line - h end
  if b.col <= self.scrollX then self.scrollX = b.col - 1 end
  if b.col > self.scrollX + w then self.scrollX = b.col - w end
  clampScroll(self)
end

function View:scrollBy(lines)
  self.scrollY = self.scrollY + lines
  clampScroll(self)
  self.element:markRenderDirty()
end

function View:scrollColumns(cols)
  self.scrollX = self.scrollX + cols
  clampScroll(self)
  self.element:markRenderDirty()
end

function View:hscrollThumb()
  local tw, total = self:textWidth(), self:contentWidth()
  return scrollbar.thumb(tw, total, tw, self.scrollX)
end

function View:scrollToColumn(x)
  local tw = self:textWidth()
  self.scrollX = scrollbar.offsetAt(x, tw, self:contentWidth(), tw)
  clampScroll(self)
  self.element:markRenderDirty()
end

function View:scrollThumb()
  local h, total = self:textHeight(), #self.doc.lines
  local size = math.max(1, math.floor(h * h / total))
  local maxY = math.max(1, total - h)
  local start = 1 + math.floor((h - size) * self.scrollY / maxY + 0.5)
  return start, size
end

function View:scrollToRow(y)
  local h, total = self:textHeight(), #self.doc.lines
  local _, size = self:scrollThumb()
  local ratio = (y - 1 - size / 2) / math.max(1, h - size)
  self.scrollY = math.floor(ratio * (total - h) + 0.5)
  clampScroll(self)
  self.element:markRenderDirty()
end

function View:_draw(buf)
  local theme, b = self.theme, self.buffer
  if self._reveal then self:reveal(); self._reveal = false end
  local width = self.element.width
  local height = self:textHeight()
  local gw = self:gutterWidth()
  local tw = self:textWidth()
  local lines = self.doc.lines
  local syntax = theme.syntax
  local sep = theme.gutterSeparator or " "
  local l1, c1, l2, c2 = b:selection()
  local bg = theme.editorBackground

  local pairA, pairB
  if self.structure and not l1 then
    pairA, pairB = blocks.match(lines, function(i) return self.highlighter:tokens(i) end, b.line, b.col)
  end

  for row = 1, height do
    local index = self.scrollY + row
    local line = lines[index]
    if not line then break end

    local number = tostring(index)
    local gutter = string.rep(" ", gw - 1 - #number) .. number .. sep
    local gfg = index == b.line and theme.gutterActiveForeground or theme.gutterForeground
    local diags = self.diagnosticLines and self.diagnosticLines[index]
    local worst = diags and diags[1].severity
    if worst then
      local dbg = worst == "error" and (theme.errorBackground or colors.red) or (theme.warningBackground or colors.orange)
      buf:blit(1, row, gutter:sub(1, gw - 1), theme.errorForeground or colors.white, dbg)
      buf:blit(gw, row, sep, gfg, bg)
    else
      buf:blit(1, row, gutter, gfg, bg)
    end
    if self.breakpointLines then

      if index == self.executionLine then
        buf:blit(1, row, "\16", theme.debugMarker or colors.green, bg)
      elseif self.breakpointLines[index] then
        buf:blit(1, row, "\7", theme.breakpoint or colors.red, bg)
      end
    end

    if tw > 0 then
      local from = self.scrollX + 1
      local visible = line:sub(from, from + tw - 1)
      visible = visible .. string.rep(" ", tw - #visible)
      local rowBg = bg
      if index == b.line and not l1 and theme.currentLineBackground then rowBg = theme.currentLineBackground end
      if index == self.executionLine then rowBg = theme.debugLineBackground or colors.yellow end
      local fgs, bgs = {}, {}
      for i = 1, tw do fgs[i] = syntax.ident; bgs[i] = rowBg end

      local inline = diags and (worst == "error" or index == b.line) and diags[1]
      local inlineAt
      if inline then
        inlineAt = #line - self.scrollX + 3
        if inlineAt < tw then
          local msg = inline.message:sub(1, tw - inlineAt + 1)
          visible = visible:sub(1, inlineAt - 1) .. msg .. visible:sub(inlineAt + #msg)
        else
          inlineAt = nil
        end
      end
      if self.highlight then
        for _, tok in ipairs(self.highlighter:tokens(index)) do
          local color = syntax[tok.type] or syntax.ident
          for col = math.max(tok.from, from), math.min(tok.to, from + tw - 1) do
            fgs[col - from + 1] = color
          end
        end
      end
      if diags then
        for d = #diags, 1, -1 do
          local dg = diags[d]
          for col = math.max(dg.col, from), math.min(math.max(dg.endCol, dg.col), from + tw - 1) do
            if dg.severity == "error" then
              bgs[col - from + 1] = theme.errorBackground or colors.red
              fgs[col - from + 1] = theme.errorForeground or colors.white
            else
              fgs[col - from + 1] = theme.warningForeground or colors.orange
            end
          end
        end
        if inlineAt then
          local color = worst == "error" and (theme.errorText or colors.red) or (theme.warningText or colors.orange)
          for col = inlineAt, tw do fgs[col] = color end
        end
      end
      for _, m in ipairs({ pairA, pairB }) do
        if m.line == index then
          for col = math.max(m.from, from), math.min(m.to, from + tw - 1) do
            bgs[col - from + 1] = theme.matchBackground or theme.selectionBackground
            if theme.matchForeground then fgs[col - from + 1] = theme.matchForeground end
          end
        end
      end
      local matches = self.matchLines and self.matchLines[index]
      if matches then
        for _, m in ipairs(matches) do
          for col = math.max(m.col, from), math.min(m.col + m.len - 1, from + tw - 1) do
            bgs[col - from + 1] = theme.findMatchBackground or theme.selectionBackground
            if theme.findMatchForeground then fgs[col - from + 1] = theme.findMatchForeground end
          end
        end
      end
      if l1 and index >= l1 and index <= l2 then
        local s = index == l1 and c1 or 1
        local e = index == l2 and (c2 - 1) or (#line + 1)
        for col = math.max(s, from), math.min(e, from + tw - 1) do
          bgs[col - from + 1] = theme.selectionBackground
          if theme.selectionForeground then fgs[col - from + 1] = theme.selectionForeground end
        end
      end
      buf:colorBlit(gw + 1, row, visible, fgs, bgs)
    end
  end

  local vbar, hbar = self:scrollbars()
  if vbar then
    local start, size = self:scrollThumb()
    for row = 1, height do
      local thumb = row >= start and row < start + size
      buf:blit(width, row, " ", theme.foreground, thumb and theme.scrollbarThumb or theme.scrollbarTrack)
    end
  end
  if hbar then

    local hy = self.element.height
    buf:blit(1, hy, string.rep(" ", gw), theme.foreground, bg)
    local start, size = self:hscrollThumb()
    for col = 0, tw - 1 do
      local thumb = start and col >= start and col < start + size
      buf:blit(gw + 1 + col, hy, " ", theme.foreground, thumb and theme.scrollbarThumb or theme.scrollbarTrack)
    end
    if vbar then buf:blit(width, hy, " ", theme.foreground, theme.scrollbarTrack) end
  end

  local root = self.element:getRoot()
  if root.getFocused and root:getFocused() == self.element then
    local cx = gw + b.col - self.scrollX
    local cy = b.line - self.scrollY
    local visible = cx > gw and cx <= gw + tw and cy >= 1 and cy <= height
    self.element:setCursor(visible and cx or 0, visible and cy or 0, true, theme.cursor)
  end
end

function View:applyTheme(theme)
  self.element.background = theme.editorBackground
  if self.find then self.find:applyTheme(theme) end
  self:closeCompletion()
  self.element:markRenderDirty()
end

local function modifiers(self)
  local root = self.element:getRoot()
  if not root.isKeyDown then return false, false end
  local ctrl = root:isKeyDown(keys.leftCtrl) or root:isKeyDown(keys.rightCtrl)
  local shift = root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift)
  return ctrl, shift
end

function View:changed()
  self._contentWidth = nil
  self._reveal = true
  self.element:markRenderDirty()
  for _, fn in ipairs(self._cursorListeners) do pcall(fn, self) end
end

function View:onCursor(fn)
  local list = self._cursorListeners
  list[#list + 1] = fn
  return disposable.new(function()
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
  end)
end

function View:_onClick(btn, x, y)
  if btn ~= 1 then return end
  local vbar, hbar = self:scrollbars()
  if hbar and y == self.element.height then
    if x > self:gutterWidth() and x <= self:gutterWidth() + self:textWidth() then
      self._hscrollDrag = true
      self:scrollToColumn(x - self:gutterWidth() - 1)
    end
    return
  end
  if vbar and x == self.element.width then
    self._scrollDrag = true
    self:scrollToRow(y)
    return
  end
  if self.onGutterClick and x < self:gutterWidth() then
    local line = self.scrollY + y
    if line <= #self.doc.lines then self.onGutterClick(self, line) end
    return
  end
  local ctrl, shift = modifiers(self)
  local line, col = self:positionAt(x, y)

  local now = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  local last = self._lastClick
  local count = 1
  if last and not shift and not ctrl and now - last.time < 500 and last.line == line
    and math.abs(last.col - col) <= 1 then
    count = last.count + 1
  end
  self._lastClick = { time = now, line = line, col = col, count = count }
  if count >= 2 then
    self:expandSelection(count, line, col)
    return
  end
  self.buffer:setCursor(line, col, shift)
  self:changed()
  if ctrl and self.onCtrlClick then self.onCtrlClick(self) end
end

function View:selectLines(l1, l2)
  local lines = self.doc.lines
  self.buffer:setCursor(l1, 1)
  if l2 < #lines then self.buffer:setCursor(l2 + 1, 1, true)
  else self.buffer:setCursor(l2, #lines[l2] + 1, true) end
  self:changed()
end

function View:expandSelection(count, line, col)
  local lines = self.doc.lines
  local text = lines[line] or ""
  if count == 2 then
    if text == "" then self:selectLines(line, line) return end
    local at = math.max(1, math.min(col, #text))
    local function class(c)
      if c:match("[%w_]") then return "word" end
      if c:match("%s") then return "space" end
      return "symbol"
    end
    local kind = class(text:sub(at, at))

    if kind ~= "word" and at > 1 and col > #text and class(text:sub(at - 1, at - 1)) == "word" then
      at = at - 1; kind = "word"
    end
    local from, to = at, at
    while from > 1 and class(text:sub(from - 1, from - 1)) == kind do from = from - 1 end
    while to < #text and class(text:sub(to + 1, to + 1)) == kind do to = to + 1 end
    self.buffer:setCursor(line, from)
    self.buffer:setCursor(line, to + 1, true)
    self._blockRange = nil
    self:changed()
  elseif count == 3 then
    self._blockRange = nil
    self:selectLines(line, line)
  else
    local s, e
    if self.structure then
      local tokens = function(i) return self.highlighter:tokens(i) end
      local range = self._blockRange
      if count == 4 or not range then
        s, e = blocks.enclosing(lines, tokens, line)
      else
        s, e = blocks.enclosing(lines, tokens, range[1], true)

        while s and range and s >= range[1] and e <= range[2] do
          s, e = blocks.enclosing(lines, tokens, s, true)
        end
      end
    end
    if not s then s, e = 1, #lines end
    self._blockRange = { s, e }
    self:selectLines(s, e)
  end
end

function View:setDiagnostics(list)
  self.diagnostics = list or {}
  local byLine = {}
  for _, d in ipairs(self.diagnostics) do
    local l = byLine[d.line]
    if not l then l = {}; byLine[d.line] = l end
    l[#l + 1] = d
  end
  for _, l in pairs(byLine) do
    table.sort(l, function(a, b)
      if a.severity ~= b.severity then return a.severity == "error" end
      return a.col < b.col
    end)
  end
  self.diagnosticLines = next(byLine) and byLine or nil
  self.element:markRenderDirty()
end

function View:nextProblem(delta)
  local list = {}
  for _, d in ipairs(self.diagnostics or {}) do list[#list + 1] = d end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.line < b.line or (a.line == b.line and a.col < b.col) end)
  local b = self.buffer
  local target
  if delta > 0 then
    for _, d in ipairs(list) do
      if d.line > b.line or (d.line == b.line and d.col > b.col) then target = d break end
    end
    target = target or list[1]
  else
    for i = #list, 1, -1 do
      local d = list[i]
      if d.line < b.line or (d.line == b.line and d.col < b.col) then target = d break end
    end
    target = target or list[#list]
  end
  self:gotoLine(target.line, target.col)
  return target
end

function View:_onDrag(x, y)
  if self._scrollDrag then self:scrollToRow(y) return end
  if self._hscrollDrag then self:scrollToColumn(x - self:gutterWidth() - 1) return end
  local h = self:textHeight()
  if y < 1 then self:scrollBy(-1) elseif y > h then self:scrollBy(1) end
  local line, col = self:positionAt(x, math.max(1, math.min(h, y)))
  self.buffer:setCursor(line, col, true)
  self:changed()
end

function View:_onKey(key, _held)
  if self.doc.readOnly and key ~= keys.left and key ~= keys.right and key ~= keys.up
    and key ~= keys.down and key ~= keys.home and key ~= keys["end"]
    and key ~= keys.pageUp and key ~= keys.pageDown then
    return
  end
  local ctrl, shift = modifiers(self)
  if self.completion and self:_completionKey(key) then return end
  local b = self.buffer
  local page = math.max(1, self:textHeight() - 1)
  if key == keys.backspace and self.completion then
    b:backspace()
    clampScroll(self)
    self:changed()
    self:updateCompletion(false)
    return
  end
  if key == keys.left then b:left(shift, ctrl)
  elseif key == keys.right then b:right(shift, ctrl)
  elseif key == keys.up then
    if ctrl then self:scrollBy(-1) return end
    b:up(shift)
  elseif key == keys.down then
    if ctrl then self:scrollBy(1) return end
    b:down(shift)
  elseif key == keys.home then
    if ctrl then b:documentStart(shift) else b:home(shift) end
  elseif key == keys["end"] then
    if ctrl then b:documentEnd(shift) else b:lineEnd(shift) end
  elseif key == keys.pageUp then b:vertical(-page, shift); self.scrollY = self.scrollY - page
  elseif key == keys.pageDown then b:vertical(page, shift); self.scrollY = self.scrollY + page
  elseif key == keys.enter or key == keys.numPadEnter then self:_newline()
  elseif key == keys.backspace then b:backspace()
  elseif key == keys.delete then b:delete()
  elseif key == keys.tab then
    local sl1, _, sl2 = b:selection()
    if shift then
      local a, z = b:selectedLines()
      b:indentLines(a, z, -1)
    elseif sl1 and sl1 ~= sl2 then
      local a, z = b:selectedLines()
      b:indentLines(a, z, 1)
    else
      b:indent()
    end
  else return end
  self:closeCompletion()
  clampScroll(self)
  self:changed()
end

function View:_onChar(ch)
  local ctrl = modifiers(self)
  if ctrl or self.doc.readOnly then return end
  local paren = self._closeParen
  if paren and paren.line ~= self.buffer.line then self._closeParen, paren = nil, nil end
  if ch == ")" and paren and not self.buffer:hasSelection()
    and self.doc.lines[self.buffer.line]:sub(self.buffer.col, self.buffer.col) == ")"
    and self.buffer.col >= paren.col then
    self._closeParen = nil
    self.buffer:setCursor(self.buffer.line, self.buffer.col + 1)
    self:changed()
    self:closeCompletion()
    return
  end
  self.buffer:type(ch)
  self:_autoDedent()
  self:changed()
  if self.completer and (ch:match("[%w_%.:]")) then
    self:updateCompletion(false)
  else
    self:closeCompletion()
  end
end

function View:_tokens()
  return function(i) return self.highlighter:tokens(i) end
end

function View:_newline()
  local b = self.buffer
  if not self.structure or b:hasSelection() then b:newline() return end
  local line = self.doc.lines[b.line]
  local indent = line:match("^[ \t]*")
  local unit = string.rep(" ", b.tabSize)
  local opens = blocks.opensAt(line, self.highlighter:tokens(b.line), b.col)
  if not opens then b:newline() return end
  local rest = line:sub(b.col)
  local inner = indent .. unit
  if opens == ")" or opens == "]" or opens == "}" then
    if rest:match("^%s*%" .. opens) then

      b:insert("\n" .. inner .. "\n" .. indent, "newline")
      b:setCursor(b.line - 1, #inner + 1)
    else
      b:insert("\n" .. inner, "newline")
    end
    return
  end
  local closer = opens == "until" and "until " or "end"
  if opens ~= "indent" and rest:match("^%s*$")
    and blocks.unclosed(self.doc.lines, self:_tokens()) > 0 then

    b:insert("\n" .. inner .. "\n" .. indent .. closer, "newline")
    b:setCursor(b.line - 1, #inner + 1)
    return
  end
  b:insert("\n" .. inner, "newline")
end

local DEDENT_WORDS = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true }
function View:_autoDedent()
  if not self.structure then return end
  local b = self.buffer
  local line = self.doc.lines[b.line]
  if b.col ~= #line + 1 then return end
  local indent, word = line:match("^([ \t]*)([%a]+)$")
  local closer = word
  if not word then
    indent, closer = line:match("^([ \t]*)([%)%]}])$")
    if not closer then return end
  elseif not DEDENT_WORDS[word] then
    return
  end
  if indent == "" then return end
  self.highlighter:invalidate(b.line)
  local target = blocks.openerIndent(self.doc.lines, self:_tokens(), b.line, closer)
  if target and target ~= indent then
    b:setCursor(b.line, 1)
    b:setCursor(b.line, #indent + 1, true)
    b:insert(target, "type")
    b:lineEnd()
  end
end

function View:toggleComment()
  if self.doc.readOnly then return end
  local a, z = self.buffer:selectedLines()
  if self.buffer:toggleComment(a, z) then self:changed() end
end

function View:duplicateLines()
  if self.doc.readOnly then return end
  local a, z = self.buffer:selectedLines()
  self.buffer:duplicateLines(a, z)
  self:changed()
end

function View:deleteLines()
  if self.doc.readOnly then return end
  local a, z = self.buffer:selectedLines()
  self.buffer:deleteLines(a, z)
  self:changed()
end

function View:moveLines(delta)
  if self.doc.readOnly then return end
  local a, z = self.buffer:selectedLines()
  if self.buffer:moveLines(a, z, delta) then self:changed() end
end

local MAX_ITEMS = 50

function View:updateCompletion(manual)
  if not self.completer then return end
  local ok, items, start = pcall(self.completer, self, manual or (self.completion and self.completion.manual))
  if not ok or not items or #items == 0 then self:closeCompletion() return end
  local state = self.completion
  if not state then
    state = { manual = manual }
    self.completion = state
    local theme = self.theme
    state.shadow = self.host:addCanvas({ x = 1, y = 1, width = 1, height = 1, z = 3,
      background = theme.shadow or theme.muted, draw = function() end })
    state.popup = self.host:addCanvas({ x = 1, y = 1, width = 1, height = 1, z = 4,
      background = theme.completionBackground or theme.listBackground,
      draw = function(_, buf) self:_drawCompletion(buf) end })
    state.popup:onClick(function(_, _, _, y)
      local index = state.offset + y
      if state.items[index] then state.selected = index; self:acceptCompletion() end
    end)
    state.popup:onScroll(function(_, dir) self:_moveCompletion(dir) end)
  end
  local list = {}
  for i = 1, math.min(#items, MAX_ITEMS) do list[i] = items[i] end
  state.items, state.start = list, start
  state.selected, state.offset = 1, 0
  self:_placeCompletion()
end

function View:closeCompletion()
  local state = self.completion
  if not state then return end
  self.completion = nil
  state.popup:destroy()
  state.shadow:destroy()
  self.element:markRenderDirty()
end

local function itemText(item)
  return item.name .. (item.sig or "")
end

function View:_placeCompletion()
  local state = self.completion
  local hostW, hostH = self.host.width, self.host.height
  local width = 12
  for _, item in ipairs(state.items) do
    width = math.max(width, #itemText(item) + 4 + (item.source and #item.source + 1 or 0))
  end
  width = math.min(width, 40, hostW - 1)
  local selectedItem = state.items[state.selected]
  local rows = math.min(#state.items, 7)
  state.docRow = selectedItem and selectedItem.doc ~= nil
  local height = rows + (state.docRow and 1 or 0)
  local b = self.buffer
  local cursorRow = self.element.y - 1 + (b.line - self.scrollY)
  local x = self:gutterWidth() + state.start - self.scrollX
  x = math.max(1, math.min(x - 3, hostW - width))
  local y = cursorRow + 1
  if y + height - 1 > hostH and cursorRow - height >= 1 then y = cursorRow - height end
  height = math.min(height, math.max(1, hostH - y + 1))
  state.rows = height - (state.docRow and 1 or 0)
  if state.rows < 1 then state.rows, state.docRow = height, false end
  local p = state.popup
  p.x, p.y, p.width, p.height = x, y, width, height
  local sh = state.shadow
  sh.x, sh.y = x + 1, y + 1
  sh.width = math.min(width, hostW - x)
  sh.height = math.min(height, hostH - y)
  local theme = self.theme
  sh.visible = sh.width > 0 and sh.height > 0
    and theme.shadow ~= (theme.completionBackground or theme.listBackground)
  p:markRenderDirty()
  self.element:markRenderDirty()
end

function View:_drawCompletion(buf)
  local state, theme = self.completion, self.theme
  if not state then return end
  local p = state.popup
  local w = p.width
  local bg = theme.completionBackground or theme.listBackground
  local fg = theme.completionForeground or theme.listForeground
  local kinds = theme.completionKinds or {}
  if state.selected - state.offset > state.rows then state.offset = state.selected - state.rows end
  if state.selected - state.offset < 1 then state.offset = state.selected - 1 end
  for row = 1, state.rows do
    local item = state.items[state.offset + row]
    if not item then break end
    local active = state.offset + row == state.selected
    local rowFg = active and theme.listSelectionForeground or fg
    local rowBg = active and theme.listSelectionBackground or bg
    local muted = active and theme.listSelectionForeground or theme.muted
    buf:fill(1, row, w, 1, " ", rowFg, rowBg)
    local letter = (item.kind or "?"):sub(1, 1)
    buf:blit(2, row, letter, active and rowFg or (kinds[item.kind] or muted), rowBg)
    local source = item.source and (item.source .. " ") or ""
    local room = w - 4 - #source
    buf:blit(4, row, item.name:sub(1, room), rowFg, rowBg)
    if item.sig and #item.name < room then
      buf:blit(4 + #item.name, row, item.sig:sub(1, room - #item.name), muted, rowBg)
    end
    if source ~= "" and room > 0 then buf:blit(w - #source + 1, row, source, muted, rowBg) end
  end
  if state.docRow then
    local item = state.items[state.selected]
    local text = " " .. (item and item.doc or "")
    buf:fill(1, state.rows + 1, w, 1, " ", theme.muted, theme.findBackground or bg)
    buf:blit(1, state.rows + 1, text:sub(1, w), theme.findForeground or theme.muted, theme.findBackground or bg)
  end
end

function View:_moveCompletion(delta)
  local state = self.completion
  if not state then return end
  state.selected = math.max(1, math.min(#state.items, state.selected + delta))
  self:_placeCompletion()
end

function View:_completionKey(key)
  if key == keys.up then self:_moveCompletion(-1)
  elseif key == keys.down then self:_moveCompletion(1)
  elseif key == keys.pageUp then self:_moveCompletion(-(self.completion.rows or 5))
  elseif key == keys.pageDown then self:_moveCompletion(self.completion.rows or 5)
  elseif key == keys.enter or key == keys.numPadEnter or key == keys.tab then self:acceptCompletion()
  else return false end
  return true
end

function View:acceptCompletion()
  local state = self.completion
  if not state then return end
  local item = state.items[state.selected]
  self:closeCompletion()
  if not item or self.doc.readOnly then return end
  local b = self.buffer
  local line = self.doc.lines[b.line]

  local wordEnd = state.start + #(line:sub(state.start):match("^[%w_]*"))
  local nextChar = line:sub(wordEnd, wordEnd)
  local text, offset = item.name, 0
  if self.insertText then text, offset = self.insertText(item, nextChar) end
  b:setCursor(b.line, state.start)
  b:setCursor(b.line, wordEnd, true)
  b:insert(text)
  if offset and offset ~= 0 then b:setCursor(b.line, b.col + offset) end

  if text:sub(-1) == ")" and offset == -1 then self._closeParen = { line = b.line, col = b.col } end
  self:changed()
  local root = self.element:getRoot()
  if root.getFocused and root:getFocused() ~= self.element then self:focus() end
end

function View:insert(text)
  if self.doc.readOnly or text == "" then return end
  self.buffer:insert((text:gsub("\r\n?", "\n"):gsub("\t", string.rep(" ", self.buffer.tabSize))))
  self:changed()
end

function View:undo() if self.buffer:undo() then self:changed() end end
function View:redo() if self.buffer:redo() then self:changed() end end
function View:selectAll() self.buffer:selectAll(); self:changed() end

function View:_setClipboard(text)
  M.clipboard = tostring(text or "")
  if self.setClipboard then self.setClipboard(M.clipboard) end
  return M.clipboard
end

function View:_getClipboard()
  if self.getClipboard then return self.getClipboard() or "" end
  return M.clipboard
end

function View:copy()
  if self.buffer:hasSelection() then
    self:_setClipboard(self.buffer:getSelectedText())
  else
    self:_setClipboard(self.doc.lines[self.buffer.line] .. "\n")
  end
  return self:_getClipboard()
end

function View:cut()
  if self.doc.readOnly then return end
  if not self.buffer:hasSelection() then

    local b = self.buffer
    self:_setClipboard(self.doc.lines[b.line] .. "\n")
    if #self.doc.lines > 1 then
      if b.line < #self.doc.lines then
        b:setCursor(b.line, 1); b:setCursor(b.line + 1, 1, true)
      else
        b:setCursor(b.line - 1, #self.doc.lines[b.line - 1] + 1)
        b:setCursor(b.line + 1, #self.doc.lines[b.line + 1] + 1, true)
      end
    else
      b:setCursor(1, 1); b:lineEnd(true)
    end
    b:deleteSelection()
  else
    self:_setClipboard(self.buffer:getSelectedText())
    self.buffer:deleteSelection()
  end
  self:changed()
end

function View:pasteInternal()
  self:insert(self:_getClipboard())
end

function View:gotoLine(line, col)
  self:closeCompletion()
  self.buffer:setCursor(line, col or 1)
  self:changed()
end

function View:focus()
  self.element:focus()
  self.element:markRenderDirty()
end

function View:getViewState()
  return { line = self.buffer.line, col = self.buffer.col, scrollY = self.scrollY, scrollX = self.scrollX }
end

function View:setViewState(state)
  if type(state) ~= "table" then return end
  self.buffer:setCursor(state.line or 1, state.col or 1)
  self.scrollY, self.scrollX = state.scrollY or 0, state.scrollX or 0
  clampScroll(self)
  self._reveal = false
  self.element:markRenderDirty()
end

function View:dispose()
  self:closeCompletion()
  self._store:dispose()
  if self.find then self.find:dispose() end
  self.element:destroy()
end

return M

local M = {}

local Buffer = {}
Buffer.__index = Buffer

function M.new(doc, options)
  options = options or {}
  return setmetatable({
    doc = doc,
    line = 1, col = 1,
    anchorLine = nil, anchorCol = nil,
    preferredCol = nil,
    tabSize = options.tabSize or 2,
    _undo = {}, _redo = {},
    _group = nil,
  }, Buffer)
end

local function lines(self) return self.doc.lines end

local function clamp(self)
  local ls = lines(self)
  if self.line < 1 then self.line = 1 end
  if self.line > #ls then self.line = #ls end
  local max = #ls[self.line] + 1
  if self.col < 1 then self.col = 1 end
  if self.col > max then self.col = max end
end

local function before(l1, c1, l2, c2)
  return l1 < l2 or (l1 == l2 and c1 < c2)
end

function Buffer:hasSelection()
  return self.anchorLine ~= nil and (self.anchorLine ~= self.line or self.anchorCol ~= self.col)
end

function Buffer:selection()
  if not self:hasSelection() then return nil end
  if before(self.line, self.col, self.anchorLine, self.anchorCol) then
    return self.line, self.col, self.anchorLine, self.anchorCol
  end
  return self.anchorLine, self.anchorCol, self.line, self.col
end

function Buffer:clearSelection()
  self.anchorLine, self.anchorCol = nil, nil
end

function Buffer:selectAll()
  local ls = lines(self)
  self.anchorLine, self.anchorCol = 1, 1
  self.line, self.col = #ls, #ls[#ls] + 1
end

function Buffer:getRange(l1, c1, l2, c2)
  local ls = lines(self)
  if l1 == l2 then return ls[l1]:sub(c1, c2 - 1) end
  local parts = { ls[l1]:sub(c1) }
  for i = l1 + 1, l2 - 1 do parts[#parts + 1] = ls[i] end
  parts[#parts + 1] = ls[l2]:sub(1, c2 - 1)
  return table.concat(parts, "\n")
end

function Buffer:getSelectedText()
  local l1, c1, l2, c2 = self:selection()
  if not l1 then return "" end
  return self:getRange(l1, c1, l2, c2)
end

local function endOf(l, c, text)
  local count, last = 0, text
  for part in (text .. "\n"):gmatch("(.-)\n") do count = count + 1; last = part end
  if count == 1 then return l, c + #text end
  return l + count - 1, #last + 1
end

local function replace(self, l1, c1, l2, c2, text)
  local ls = lines(self)
  local prefix = ls[l1]:sub(1, c1 - 1)
  local suffix = ls[l2]:sub(c2)
  local newLines = {}
  for part in (text .. "\n"):gmatch("(.-)\n") do newLines[#newLines + 1] = part end
  local count = #newLines
  newLines[1] = prefix .. newLines[1]
  local endLine = l1 + count - 1
  local endCol = #newLines[count] + 1
  newLines[count] = newLines[count] .. suffix

  local removed = l2 - l1 + 1
  if removed == count then
    for i = 1, count do ls[l1 + i - 1] = newLines[i] end
  else
    for _ = 1, removed do table.remove(ls, l1) end
    for i = count, 1, -1 do table.insert(ls, l1, newLines[i]) end
  end
  return endLine, endCol, removed ~= count
end

local function edit(self, l1, c1, l2, c2, text, kind)
  local old = self:getRange(l1, c1, l2, c2)
  local cursorBefore = { self.line, self.col, self.anchorLine, self.anchorCol }
  local endLine, endCol, structural = replace(self, l1, c1, l2, c2, text)
  self.line, self.col = endLine, endCol
  self:clearSelection()
  self.preferredCol = nil

  local step = { l1 = l1, c1 = c1, text = text, old = old, cursor = cursorBefore }
  local group = self._group
  local canMerge = kind == "type" and group and group.kind == "type"
    and group.endLine == l1 and group.endCol == c1 and old == "" and not text:find("\n")
    and #group.steps < 64
  if canMerge then
    group.steps[#group.steps + 1] = step
  else
    group = { kind = kind, steps = { step } }
    self._undo[#self._undo + 1] = group
  end
  group.endLine, group.endCol = endLine, endCol
  self._group = group
  self._redo = {}

  local info = { line = l1, structural = structural or text:find("\n") ~= nil or old:find("\n") ~= nil }
  self.doc:changed(info)
  return info
end

function Buffer:applyEdits(edits, after, kind)
  if #edits == 0 then return nil end
  local cursorBefore = { self.line, self.col, self.anchorLine, self.anchorCol }
  local group = { kind = kind or "edit", steps = {} }
  local minLine, structural = math.huge, false
  for i = #edits, 1, -1 do
    local e = edits[i]
    local old = self:getRange(e.l1, e.c1, e.l2, e.c2)
    local _, _, changedLines = replace(self, e.l1, e.c1, e.l2, e.c2, e.text)
    group.steps[#group.steps + 1] = { l1 = e.l1, c1 = e.c1, text = e.text, old = old, cursor = cursorBefore }
    minLine = math.min(minLine, e.l1)
    if changedLines or e.text:find("\n") or old:find("\n") then structural = true end
  end
  self:clearSelection()
  self.preferredCol = nil
  if after then after(self) end
  clamp(self)
  self._undo[#self._undo + 1] = group
  self._group = nil
  self._redo = {}
  local info = { line = minLine, structural = structural }
  self.doc:changed(info)
  return info
end

function Buffer:replaceRanges(ranges, text)
  if #ranges == 0 then return nil end
  local edits = {}
  for i, r in ipairs(ranges) do
    edits[i] = { l1 = r.line, c1 = r.col, l2 = r.line, c2 = r.col + r.len, text = text }
  end
  local first = ranges[1]
  return self:applyEdits(edits, function(b)
    b.line, b.col = endOf(first.line, first.col, text)
  end, "replace")
end

function Buffer:selectedLines()
  local l1, _, l2, c2 = self:selection()
  if not l1 then return self.line, self.line end
  if c2 == 1 and l2 > l1 then l2 = l2 - 1 end
  return l1, l2
end

local function shiftColumns(b, deltas, anchorLine, anchorCol, line, col)
  if anchorLine then
    b.anchorLine, b.anchorCol = anchorLine, math.max(1, anchorCol + (deltas[anchorLine] or 0))
  end
  b.line, b.col = line, math.max(1, col + (deltas[line] or 0))
end

function Buffer:indentLines(l1, l2, delta)
  local ls = lines(self)
  local edits, deltas = {}, {}
  for i = l1, l2 do
    local line = ls[i]
    if delta > 0 then
      if line ~= "" then
        edits[#edits + 1] = { l1 = i, c1 = 1, l2 = i, c2 = 1, text = string.rep(" ", self.tabSize) }
        deltas[i] = self.tabSize
      end
    else
      local spaces = #line:match("^ *")
      local n = math.min(spaces, self.tabSize)
      if n == 0 and line:sub(1, 1) == "\t" then n = 1 end
      if n > 0 then
        edits[#edits + 1] = { l1 = i, c1 = 1, l2 = i, c2 = n + 1, text = "" }
        deltas[i] = -n
      end
    end
  end
  local al, ac, cl, cc = self.anchorLine, self.anchorCol, self.line, self.col
  return self:applyEdits(edits, function(b) shiftColumns(b, deltas, al, ac, cl, cc) end, "indent")
end

function Buffer:toggleComment(l1, l2)
  local ls = lines(self)
  local allCommented, minIndent = true, math.huge
  for i = l1, l2 do
    local line = ls[i]
    if line:match("%S") then
      minIndent = math.min(minIndent, #line:match("^%s*"))
      if not line:match("^%s*%-%-") then allCommented = false end
    end
  end
  if minIndent == math.huge then return nil end
  local edits, deltas = {}, {}
  for i = l1, l2 do
    local line = ls[i]
    if line:match("%S") then
      if allCommented then
        local indent = #line:match("^%s*")
        local mark = line:match("^%-%- ?", indent + 1)
        edits[#edits + 1] = { l1 = i, c1 = indent + 1, l2 = i, c2 = indent + 1 + #mark, text = "" }
        deltas[i] = -#mark
      else
        edits[#edits + 1] = { l1 = i, c1 = minIndent + 1, l2 = i, c2 = minIndent + 1, text = "-- " }
        deltas[i] = 3
      end
    end
  end
  local al, ac, cl, cc = self.anchorLine, self.anchorCol, self.line, self.col
  return self:applyEdits(edits, function(b) shiftColumns(b, deltas, al, ac, cl, cc) end, "comment")
end

function Buffer:duplicateLines(l1, l2)
  local ls = lines(self)
  local block = {}
  for i = l1, l2 do block[#block + 1] = ls[i] end
  local count = l2 - l1 + 1
  local al, ac, cl, cc = self.anchorLine, self.anchorCol, self.line, self.col
  return self:applyEdits({ { l1 = l2, c1 = #ls[l2] + 1, l2 = l2, c2 = #ls[l2] + 1,
    text = "\n" .. table.concat(block, "\n") } }, function(b)
    if al then b.anchorLine, b.anchorCol = al + count, ac end
    b.line, b.col = cl + count, cc
  end, "duplicate")
end

function Buffer:deleteLines(l1, l2)
  local ls = lines(self)
  local col = self.col
  local edit
  if l2 < #ls then
    edit = { l1 = l1, c1 = 1, l2 = l2 + 1, c2 = 1, text = "" }
  elseif l1 > 1 then
    edit = { l1 = l1 - 1, c1 = #ls[l1 - 1] + 1, l2 = l2, c2 = #ls[l2] + 1, text = "" }
  else
    edit = { l1 = 1, c1 = 1, l2 = l2, c2 = #ls[l2] + 1, text = "" }
  end
  return self:applyEdits({ edit }, function(b)
    b.line = math.min(l1, #lines(b))
    b.col = math.min(col, #lines(b)[b.line] + 1)
  end, "deleteLines")
end

function Buffer:moveLines(l1, l2, delta)
  local ls = lines(self)
  if (delta < 0 and l1 <= 1) or (delta > 0 and l2 >= #ls) then return nil end
  local block = {}
  for i = l1, l2 do block[#block + 1] = ls[i] end
  local from, to, text
  if delta < 0 then
    from, to = l1 - 1, l2
    text = table.concat(block, "\n") .. "\n" .. ls[l1 - 1]
  else
    from, to = l1, l2 + 1
    text = ls[l2 + 1] .. "\n" .. table.concat(block, "\n")
  end
  local al, ac, cl, cc = self.anchorLine, self.anchorCol, self.line, self.col
  return self:applyEdits({ { l1 = from, c1 = 1, l2 = to, c2 = #ls[to] + 1, text = text } }, function(b)
    if al then b.anchorLine, b.anchorCol = al + delta, ac end
    b.line, b.col = cl + delta, cc
  end, "move")
end

function Buffer:breakUndoGroup()
  self._group = nil
end

function Buffer:insert(text, kind)
  local l1, c1, l2, c2 = self:selection()
  if not l1 then l1, c1, l2, c2 = self.line, self.col, self.line, self.col end
  return edit(self, l1, c1, l2, c2, text, kind or "insert")
end

function Buffer:type(ch)
  return self:insert(ch, "type")
end

function Buffer:newline()
  local indent = lines(self)[self.line]:match("^[ \t]*")
  local l1 = self:selection()
  if l1 then indent = lines(self)[l1]:match("^[ \t]*") end
  return self:insert("\n" .. indent, "newline")
end

function Buffer:indent()
  local spaces = self.tabSize - ((self.col - 1) % self.tabSize)
  return self:insert(string.rep(" ", spaces), "type")
end

function Buffer:deleteSelection()
  local l1, c1, l2, c2 = self:selection()
  if not l1 then return nil end
  return edit(self, l1, c1, l2, c2, "", "delete")
end

function Buffer:backspace()
  if self:hasSelection() then return self:deleteSelection() end
  local ls = lines(self)
  if self.col > 1 then

    local left = ls[self.line]:sub(1, self.col - 1)
    local width = 1
    if left:match("^ +$") then
      width = ((self.col - 2) % self.tabSize) + 1
    end
    return edit(self, self.line, self.col - width, self.line, self.col, "", "backspace")
  elseif self.line > 1 then
    local prev = #ls[self.line - 1] + 1
    return edit(self, self.line - 1, prev, self.line, 1, "", "backspace")
  end
end

function Buffer:delete()
  if self:hasSelection() then return self:deleteSelection() end
  local ls = lines(self)
  if self.col <= #ls[self.line] then
    return edit(self, self.line, self.col, self.line, self.col + 1, "", "delete")
  elseif self.line < #ls then
    return edit(self, self.line, self.col, self.line + 1, 1, "", "delete")
  end
end

function Buffer:canUndo() return #self._undo > 0 end
function Buffer:canRedo() return #self._redo > 0 end

function Buffer:undo()
  local group = table.remove(self._undo)
  if not group then return nil end
  for i = #group.steps, 1, -1 do
    local s = group.steps[i]
    local el, ec = endOf(s.l1, s.c1, s.text)
    replace(self, s.l1, s.c1, el, ec, s.old)
  end
  local c = group.steps[1].cursor
  self.line, self.col, self.anchorLine, self.anchorCol = c[1], c[2], c[3], c[4]
  clamp(self)
  self._redo[#self._redo + 1] = group
  self._group = nil
  local minLine = math.huge
  for _, s in ipairs(group.steps) do minLine = math.min(minLine, s.l1) end
  local info = { line = minLine, structural = true }
  self.doc:changed(info)
  return info
end

function Buffer:redo()
  local group = table.remove(self._redo)
  if not group then return nil end
  local el, ec
  for _, s in ipairs(group.steps) do
    local ol, oc = endOf(s.l1, s.c1, s.old)
    el, ec = replace(self, s.l1, s.c1, ol, oc, s.text)
  end
  self.line, self.col = el, ec
  self:clearSelection()
  self._undo[#self._undo + 1] = group
  self._group = nil
  local minLine = math.huge
  for _, s in ipairs(group.steps) do minLine = math.min(minLine, s.l1) end
  local info = { line = minLine, structural = true }
  self.doc:changed(info)
  return info
end

local function prepareMove(self, select)
  if select then
    if not self.anchorLine then self.anchorLine, self.anchorCol = self.line, self.col end
  else
    self:clearSelection()
  end
  self._group = nil
end

function Buffer:setCursor(line, col, select)
  prepareMove(self, select)
  self.line, self.col = line, col
  self.preferredCol = nil
  clamp(self)
end

local function isWord(ch) return ch ~= "" and ch:match("[%w_]") ~= nil end

function Buffer:left(select, word)
  local hadSel = self:hasSelection()
  if hadSel and not select then
    local l1, c1 = self:selection()
    self:setCursor(l1, c1)
    return
  end
  prepareMove(self, select)
  local ls = lines(self)
  if self.col > 1 then
    if word then
      local line = ls[self.line]
      local c = self.col - 1
      while c > 1 and not isWord(line:sub(c, c)) do c = c - 1 end
      while c > 1 and isWord(line:sub(c - 1, c - 1)) do c = c - 1 end
      self.col = c
    else
      self.col = self.col - 1
    end
  elseif self.line > 1 then
    self.line = self.line - 1
    self.col = #ls[self.line] + 1
  end
  self.preferredCol = nil
end

function Buffer:right(select, word)
  local hadSel = self:hasSelection()
  if hadSel and not select then
    local _, _, l2, c2 = self:selection()
    self:setCursor(l2, c2)
    return
  end
  prepareMove(self, select)
  local ls = lines(self)
  local line = ls[self.line]
  if self.col <= #line then
    if word then
      local c = self.col
      while c <= #line and not isWord(line:sub(c, c)) do c = c + 1 end
      while c <= #line and isWord(line:sub(c, c)) do c = c + 1 end
      self.col = c
    else
      self.col = self.col + 1
    end
  elseif self.line < #ls then
    self.line = self.line + 1
    self.col = 1
  end
  self.preferredCol = nil
end

function Buffer:vertical(delta, select)
  prepareMove(self, select)
  local ls = lines(self)
  self.preferredCol = self.preferredCol or self.col
  self.line = math.max(1, math.min(#ls, self.line + delta))
  self.col = math.min(self.preferredCol, #ls[self.line] + 1)
end

function Buffer:up(select) self:vertical(-1, select) end
function Buffer:down(select) self:vertical(1, select) end

function Buffer:home(select)
  prepareMove(self, select)
  local firstText = #(lines(self)[self.line]:match("^%s*")) + 1
  self.col = (self.col == firstText) and 1 or firstText
  self.preferredCol = nil
end

function Buffer:lineEnd(select)
  prepareMove(self, select)
  self.col = #lines(self)[self.line] + 1
  self.preferredCol = nil
end

function Buffer:documentStart(select)
  prepareMove(self, select)
  self.line, self.col = 1, 1
end

function Buffer:documentEnd(select)
  prepareMove(self, select)
  local ls = lines(self)
  self.line, self.col = #ls, #ls[#ls] + 1
end

function Buffer:revalidate()
  clamp(self)
  if self.anchorLine then
    local ls = lines(self)
    if self.anchorLine > #ls then self.anchorLine = #ls end
    self.anchorCol = math.min(self.anchorCol, #ls[self.anchorLine] + 1)
  end
end

return M

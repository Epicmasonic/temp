-- The AI Assistant chat panel.
local scrollbar = require("pineapple.studio.ui.scrollbar")
local dialogs = require("pineapple.studio.ui.dialogs")
local languages = require("pineapple.studio.ui.codeedit.languages")

local M = {}

local MAX_INPUT_ROWS = 4

local function wrap(text, width)
  local out = {}
  width = math.max(1, width)
  for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" then
      out[#out + 1] = ""
    else
      local indent = paragraph:match("^%s*") or ""
      if #indent >= width then indent = "" end
      local line = ""
      for word in paragraph:gmatch("%S+") do
        if line == "" then
          line = indent .. word
          while #line > width do
            out[#out + 1] = line:sub(1, width)
            line = line:sub(width + 1)
          end
        elseif #line + #word + 1 <= width then
          line = line .. " " .. word
        else
          out[#out + 1] = line
          line = indent .. word
          while #line > width do
            out[#out + 1] = line:sub(1, width)
            line = line:sub(width + 1)
          end
        end
      end
      out[#out + 1] = line
    end
  end
  return out
end

-- Splits assistant text into prose lines and fenced code blocks.
local function parseBlocks(text)
  local out, code = {}, nil
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local fence = line:match("^%s*```%s*([%w_%+%-]*)")
    if fence then
      if code then out[#out + 1] = code; code = nil
      else code = { kind = "code", lang = fence:lower(), lines = {} } end
    elseif code then
      code.lines[#code.lines + 1] = line
    else
      out[#out + 1] = { kind = "text", text = line }
    end
  end
  if code then out[#out + 1] = code end
  while #out > 0 and out[#out].kind == "text" and out[#out].text == "" do out[#out] = nil end
  return out
end

-- Light markdown clean-up for prose: headings, bold and inline code markers.
local function prose(line)
  local heading = line:match("^#+%s+(.*)$")
  if heading then line = heading end
  line = line:gsub("%*%*(.-)%*%*", "%1"):gsub("`([^`\n]+)`", "%1")
  return line, heading ~= nil
end

local LANGUAGE_ALIASES = { [""] = "lua", lua = "lua", luau = "lua", xml = "xml", html = "xml" }

-- Turns the input text into visual rows of at most `width` characters, breaking at newlines.
local function inputRows(text, width)
  local rows, lineStart = {}, 1
  while true do
    local nl = text:find("\n", lineStart, true)
    local lineEnd = (nl or (#text + 1)) - 1
    local s = lineStart
    repeat
      local e = math.min(lineEnd, s + width - 1)
      rows[#rows + 1] = { from = s, to = e }
      s = e + 1
    until s > lineEnd
    if not nl then break end
    lineStart = nl + 1
  end
  return rows
end

local function cursorRow(rows, cursor)
  local index = 1
  for i, row in ipairs(rows) do
    if row.from <= cursor then index = i end
  end
  return index
end

-- state: send(text), cancel(), openMenu(x, y), undo(turn), copy(text), insert(text),
--        prompts() -> list, modelLabel() -> string
function M.new(host, studio, state)
  local ui = studio.ui
  local self = {
    items = {}, busy = false, busyText = nil, error = nil, usage = nil, scroll = 0,
    input = { text = "", cursor = 1 }, recall = nil,
  }
  local canvas
  local layout = { bodyY = 2, bodyHeight = 0, maxScroll = 0, contentOffset = 0, inputY = 1, inputRows = {}, inputTop = 1 }

  local function dirty() if canvas then canvas:markRenderDirty() end end

  local function contentLines(width, t)
    local lines = {}
    local codeBg = t.currentLineBackground or t.sidebarBackground or t.editorBackground
    if codeBg == t.editorBackground then codeBg = t.sidebarBackground end
    local previous
    for index, item in ipairs(self.items) do
      local role = item.role
      if previous and not (role == "activity" and previous == "activity") then
        lines[#lines + 1] = { text = "", color = t.muted }
      end
      previous = role
      if role == "user" then
        for _, line in ipairs(wrap("You: " .. item.text, width)) do
          lines[#lines + 1] = { text = line, color = t.accent, item = index }
        end
      elseif role == "assistant" then
        for _, block in ipairs(parseBlocks(item.text)) do
          if block.kind == "text" then
            local text, heading = prose(block.text)
            for _, line in ipairs(wrap(text, width)) do
              lines[#lines + 1] = { text = line, color = heading and t.accent or t.foreground, item = index }
            end
          else
            local language = languages.get(LANGUAGE_ALIASES[block.lang] or "") or nil
            local carry
            for _, code in ipairs(block.lines) do
              local text = " " .. code:gsub("\t", "  ")
              local spans = {}
              if language then
                local tokens
                tokens, carry = language.tokenize(code:gsub("\t", "  "), carry)
                for _, tok in ipairs(tokens) do
                  spans[#spans + 1] = { from = tok.from + 1, to = tok.to + 1, color = (t.syntax or {})[tok.type] }
                end
              end
              lines[#lines + 1] = { text = text, color = t.foreground, bg = codeBg, spans = spans, item = index }
            end
            local source = table.concat(block.lines, "\n")
            lines[#lines + 1] = {
              text = " Copy  Insert", color = t.muted, item = index,
              actions = {
                { from = 2, to = 5, run = function() state.copy(source) end },
                { from = 8, to = 13, run = function() state.insert(source) end },
              },
            }
          end
        end
      elseif role == "activity" then
        for _, line in ipairs(wrap("* " .. item.text, width)) do
          lines[#lines + 1] = { text = line, color = t.muted, item = index }
        end
      elseif role == "changes" then
        local wrapped = wrap(item.text, width)
        for i, line in ipairs(wrapped) do
          local entry = { text = line, color = t.accent, item = index }
          lines[#lines + 1] = entry
          if i == #wrapped then
            if item.undone then
              lines[#lines + 1] = { text = " (undone)", color = t.muted, item = index }
            elseif item.turn then
              lines[#lines + 1] = { text = " Undo these changes", color = t.muted, item = index,
                actions = { { from = 2, to = 19, run = function() state.undo(item.turn) end } } }
            end
          end
        end
      elseif role == "error" then
        for _, line in ipairs(wrap(item.text, width)) do
          lines[#lines + 1] = { text = line, color = colors.red, item = index }
        end
      else
        for _, line in ipairs(wrap(item.text, width)) do
          lines[#lines + 1] = { text = line, color = t.muted, item = index }
        end
      end
    end
    if #lines == 0 then
      for _, line in ipairs(wrap("Ask about your project. The assistant can read files, check problems, look up the "
        .. "CC API, run programs and propose edits; changes and runs are shown to you first unless "
        .. "auto-approve is on. Shift+Enter adds a line; Up recalls earlier prompts; Esc or the red "
        .. "square stops a reply.", width)) do
        lines[#lines + 1] = { text = line, color = t.muted }
      end
    end
    if self.error then
      lines[#lines + 1] = { text = "", color = t.muted }
      for _, line in ipairs(wrap("Error: " .. self.error, width)) do
        lines[#lines + 1] = { text = line, color = colors.red }
      end
    elseif self.busy then
      lines[#lines + 1] = { text = "", color = t.muted }
      lines[#lines + 1] = { text = self.busyText or "Thinking...", color = t.muted }
    end
    return lines
  end

  function self._selectionBounds()
    local a, b = self.selectionAnchor, self.selectionFocus
    if not a or not b or (a.row == b.row and a.col == b.col) then return nil end
    if a.row > b.row or (a.row == b.row and a.col > b.col) then a, b = b, a end
    return { startRow = a.row, startCol = a.col, endRow = b.row, endCol = b.col }
  end

  local function draw(_, buf)
    local w, h = canvas.width, canvas.height
    local t = ui:theme()
    local bg = t.editorBackground
    local hbg, hfg = t.panelHeaderBackground, t.panelHeaderForeground
    buf:fill(1, 1, w, h, " ", t.foreground, bg)

    -- Header: title, then (right aligned) usage, Stop while busy, and the menu.
    buf:fill(1, 1, w, 1, " ", hfg, hbg)
    self.headerHits = {}
    local right = w - 2
    buf:blit(math.max(1, right), 1, " = ", hfg, hbg)
    self.headerHits[#self.headerHits + 1] = { x1 = right, x2 = w, run = function(x)
      local ax, ay = canvas:getAbsolutePosition()
      state.openMenu(ax + x - 1, ay + 1)
    end }
    if self.usage then
      local usage = " " .. self.usage .. " "
      if right - #usage > 12 then
        right = right - #usage
        buf:blit(right, 1, usage, t.muted, hbg)
      end
    end
    local title = " AI Assistant [" .. state.modelLabel() .. "]"
    buf:blit(1, 1, title:sub(1, math.max(0, right - 1)), hfg, hbg)

    -- Input area (bottom)
    -- The grey field stops three columns short of the edge; the button (a send arrow, char 0x10,
    -- when idle, or a stop block, char 0x8F, while busy) sits in the middle of that gap.
    local fieldWidth = math.max(1, w - 3)
    local inputWidth = math.max(1, fieldWidth - 3)
    local rows = inputRows(self.input.text, inputWidth)
    local inputHeight = math.min(MAX_INPUT_ROWS, #rows)
    local currentRow = cursorRow(rows, self.input.cursor)
    if currentRow < layout.inputTop then layout.inputTop = currentRow end
    if currentRow > layout.inputTop + inputHeight - 1 then layout.inputTop = currentRow - inputHeight + 1 end
    layout.inputTop = math.max(1, math.min(layout.inputTop, #rows - inputHeight + 1))
    layout.inputRows = rows
    layout.inputY = h - inputHeight + 1
    local fieldBg, fieldFg = t.inputBackground or bg, t.inputForeground or t.foreground
    buf:fill(1, layout.inputY, fieldWidth, inputHeight, " ", fieldFg, fieldBg)
    for i = 1, inputHeight do
      local row = rows[layout.inputTop + i - 1]
      local prefix = (layout.inputTop + i - 1 == 1) and "> " or "  "
      buf:blit(1, layout.inputY + i - 1, prefix .. self.input.text:sub(row.from, row.to), fieldFg, fieldBg)
    end
    if self.input.text == "" then
      local hint = self.busy and "Type your next message..." or "Ask the assistant..."
      buf:blit(3, layout.inputY, hint:sub(1, inputWidth), t.inputPlaceholder or t.muted, fieldBg)
    end
    layout.buttonX = math.max(1, w - 1)
    if self.busy then
      buf:blit(layout.buttonX, layout.inputY, "\143", colors.red, bg)
    else
      local ready = self.input.text:match("%S") ~= nil
      buf:blit(layout.buttonX, layout.inputY, "\16", ready and t.accent or t.muted, bg)
    end
    buf:fill(1, layout.inputY - 1, w, 1, "-", t.muted, bg)

    -- Conversation
    layout.bodyY = 2
    layout.bodyHeight = math.max(0, layout.inputY - 1 - layout.bodyY)
    local width = math.max(1, w - 3)
    local lines = contentLines(width, t)
    layout.maxScroll = math.max(0, #lines - layout.bodyHeight)
    self.scroll = math.max(0, math.min(self.scroll, layout.maxScroll))
    layout.contentOffset = layout.maxScroll - self.scroll
    self._renderedLines = lines
    local selection = self._selectionBounds()
    for row = 1, layout.bodyHeight do
      local index = layout.contentOffset + row
      local line = lines[index]
      if line then
        local y = layout.bodyY + row - 1
        local lineBg = line.bg or bg
        if line.bg then buf:fill(2, y, width, 1, " ", line.color, line.bg) end
        local text = line.text:sub(1, width)
        if text ~= "" then buf:blit(2, y, text, line.color, lineBg) end
        for _, span in ipairs(line.spans or {}) do
          if span.color and span.from <= width then
            local piece = line.text:sub(span.from, math.min(span.to, width))
            if piece ~= "" then buf:blit(1 + span.from, y, piece, span.color, lineBg) end
          end
        end
        for _, action in ipairs(line.actions or {}) do
          local piece = line.text:sub(action.from, math.min(action.to, width))
          if piece ~= "" then buf:blit(1 + action.from, y, piece, t.tabActiveForeground or t.accentForeground or t.foreground, t.tabActiveBackground or t.accent) end
        end
        if selection and index >= selection.startRow and index <= selection.endRow then
          local from = index == selection.startRow and selection.startCol or 1
          local to = index == selection.endRow and (selection.endCol - 1) or #text
          local piece = text:sub(from, to)
          if piece ~= "" then
            buf:blit(1 + from, y, piece, t.selectionForeground or colors.white, t.selectionBackground or colors.blue)
          end
        end
      end
    end
    if layout.bodyHeight > 0 then
      scrollbar.draw(buf, t, w, layout.bodyY, layout.bodyHeight, #lines, layout.bodyHeight, layout.contentOffset)
    end

    local cursor = rows[currentRow]
    local col = self.input.cursor - cursor.from + 1
    canvas:setCursor(math.min(fieldWidth - 1, 2 + col), layout.inputY + currentRow - layout.inputTop, true, fieldFg)
  end

  canvas = host:addCanvas({
    x = 1, y = 1, width = function() return host.width end, height = function() return host.height end,
    background = ui:theme().editorBackground, draw = draw,
  })

  -- Public API -----------------------------------------------------------------------------------

  function self.setItems(items) self.items = items or {}; self.scroll = 0; dirty() end
  function self.setBusy(value, text) self.busy = value == true; self.busyText = text; dirty() end
  function self.setError(value) self.error = value; dirty() end
  function self.setUsage(text) self.usage = text; dirty() end
  function self.refresh() self.scroll = 0; dirty() end
  function self.clear()
    self.items, self.error, self.scroll = {}, nil, 0
    self.selectionAnchor, self.selectionFocus = nil, nil
    dirty()
  end
  function self.focus() canvas:focus(); dirty() end
  function self.setInput(text)
    self.input.text = text or ""
    self.input.cursor = #self.input.text + 1
    dirty()
  end
  function self.dispose() end

  function self.copySelection()
    local selection = self._selectionBounds()
    local lines = self._renderedLines or {}
    if not selection then return nil end
    local out = {}
    for row = selection.startRow, selection.endRow do
      local line = lines[row]
      if not line then return nil end
      local from = row == selection.startRow and selection.startCol or 1
      local to = row == selection.endRow and (selection.endCol - 1) or #line.text
      out[#out + 1] = to >= from and line.text:sub(from, to) or ""
    end
    return table.concat(out, "\n")
  end

  -- Input ----------------------------------------------------------------------------------------

  local function submit()
    local text = self.input.text
    if self.busy or text:match("^%s*$") then return end
    self.input.text, self.input.cursor, self.recall = "", 1, nil
    self.error = nil
    state.send(text)
    dirty()
  end

  local function recall(delta)
    local prompts = state.prompts()
    if #prompts == 0 then return false end
    if not self.recall then
      if delta > 0 then return false end
      self.recall = { index = #prompts + 1, draft = self.input.text }
    end
    local index = self.recall.index + delta
    if index < 1 then return true end
    if index > #prompts then
      self.setInput(self.recall.draft)
      self.recall = nil
      return true
    end
    self.recall.index = index
    self.setInput(prompts[index])
    return true
  end

  local function moveRow(delta)
    local rows = layout.inputRows
    if not rows or #rows == 0 then return false end
    local current = cursorRow(rows, self.input.cursor)
    local target = rows[current + delta]
    if not target then return false end
    local col = self.input.cursor - rows[current].from
    self.input.cursor = math.min(target.from + col, target.to + 1)
    dirty()
    return true
  end

  local function shiftDown()
    local root = canvas:getRoot()
    return root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
  end

  canvas:onKey(function(_, key)
    if key == keys.enter or key == keys.numPadEnter then
      if shiftDown() then dialogs.insertField(self.input, "\n"); dirty() else submit() end
    elseif key == keys.up then
      if not moveRow(-1) then recall(-1) end
    elseif key == keys.down then
      if not moveRow(1) then recall(1) end
    elseif key == keys.pageUp then
      self.scroll = math.min(layout.maxScroll, self.scroll + math.max(1, layout.bodyHeight - 1)); dirty()
    elseif key == keys.pageDown then
      self.scroll = math.max(0, self.scroll - math.max(1, layout.bodyHeight - 1)); dirty()
    elseif dialogs.editField(self.input, key) then
      self.recall = nil
      dirty()
    end
  end)
  canvas:onKeyUp(function(_, key)
    if key == (keys.escape or -1) then
      if self.busy then state.cancel()
      elseif self.selectionAnchor then self.selectionAnchor, self.selectionFocus = nil, nil; dirty()
      else self.setInput("") end
    end
  end)
  canvas:onChar(function(_, ch)
    dialogs.insertField(self.input, ch)
    self.recall = nil
    dirty()
  end)
  canvas:onPaste(function(_, text)
    dialogs.insertField(self.input, (text:gsub("\r\n?", "\n")))
    self.recall = nil
    dirty()
  end)

  -- Mouse ----------------------------------------------------------------------------------------

  local function lineAt(y)
    if y < layout.bodyY or y >= layout.bodyY + layout.bodyHeight then return nil end
    local index = layout.contentOffset + y - layout.bodyY + 1
    return index, self._renderedLines and self._renderedLines[index]
  end

  local function selectionPoint(x, y)
    local index, line = lineAt(y)
    if not line or x < 2 or x >= canvas.width then return nil end
    return { row = index, col = math.max(1, math.min(#line.text + 1, x - 1)) }
  end

  canvas:onClick(function(_, btn, x, y)
    if y == 1 then
      for _, hit in ipairs(self.headerHits or {}) do
        if x >= hit.x1 and x <= hit.x2 then hit.run(x) return end
      end
      return
    end
    if x == canvas.width and y >= layout.bodyY and y < layout.bodyY + layout.bodyHeight then
      self.dragging = true
      local top = scrollbar.offsetAt(y - layout.bodyY + 1, layout.bodyHeight, layout.maxScroll + layout.bodyHeight, layout.bodyHeight)
      self.scroll = layout.maxScroll - top
      dirty()
      return
    end
    if y == layout.inputY and layout.buttonX and x >= layout.buttonX then
      if self.busy then state.cancel() else submit() end
      return
    end
    if y >= layout.inputY then
      local rows = layout.inputRows
      local row = rows[layout.inputTop + y - layout.inputY]
      if row then self.input.cursor = math.max(row.from, math.min(row.to + 1, row.from + x - 3)) end
      dirty()
      return
    end
    local _, line = lineAt(y)
    if btn == 1 and line and line.actions then
      local col = x - 1
      for _, action in ipairs(line.actions) do
        if col >= action.from and col <= action.to then action.run() return end
      end
    end
    if btn == 1 then
      local point = selectionPoint(x, y)
      self.selectionAnchor, self.selectionFocus = point, point
      self.selecting = point ~= nil
      dirty()
    end
  end)
  canvas:onClickUp(function() self.dragging = false; self.selecting = false end)
  canvas:onDrag(function(_, _, x, y)
    if self.dragging then
      local top = scrollbar.offsetAt(y - layout.bodyY + 1, layout.bodyHeight, layout.maxScroll + layout.bodyHeight, layout.bodyHeight)
      self.scroll = math.max(0, math.min(layout.maxScroll, layout.maxScroll - top))
      dirty()
    elseif self.selecting then
      local point = selectionPoint(x, y)
      if point then self.selectionFocus = point; dirty() end
    end
  end)
  canvas:onScroll(function(_, direction)
    self.scroll = math.max(0, math.min(layout.maxScroll, self.scroll - direction))
    dirty()
  end)
  canvas:focus()
  return self
end

return M

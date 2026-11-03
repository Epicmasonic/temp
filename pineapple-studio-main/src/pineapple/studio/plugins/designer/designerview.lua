local model = require("pineapple.studio.plugins.designer.model")
local dialogs = require("pineapple.studio.ui.dialogs")
local scrollbar = require("pineapple.studio.ui.scrollbar")
local codeView = require("pineapple.studio.ui.codeedit.view")
local languages = require("pineapple.studio.ui.codeedit.languages")

local M = {}

local VALUE_WIDTH = 14
local MIN_SIDE = 22
local OPEN_ICON, CLOSED_ICON = "\31", "\16"
local TABS = { { " Design ", "design" }, { " Code ", "code" } }

function M.new(host, doc, studio, backend, theme)
  local ui = studio.ui
  local B = backend
  local self = {
    selected = nil,
    scrollX = 0, scrollY = 0,
    undo = {}, redo = {},
    showSide = false,
    editing = nil,
    mode = "design",
    sections = {
      { id = "toolbox", title = "Toolbox", open = true },
      { id = "props", title = "Properties", open = true },
      { id = "tree", title = "Layout Tree", open = false },
    },
    offsets = { toolbox = 0, props = 0, tree = 0 },
  }
  local current, err = B.parse(doc:getText())
  self.model = current
  self.error = err

  local bar, area, surface, overlay, side, codeHost
  local syncing = false

  local function wide() return host.width >= 50 end

  local function sideWidth()
    if not wide() then return host.width end
    local wanted = 1 + (self.labelW or 10) + 2 + VALUE_WIDTH + 1
    return math.max(MIN_SIDE, math.min(wanted, host.width - 20))
  end

  local function sync()
    syncing = true
    doc:setText(B.serialise(self.model))
    syncing = false
  end

  local function snapshot() return B.serialise(self.model) end

  local function remember()
    self.undo[#self.undo + 1] = snapshot()
    if #self.undo > 100 then table.remove(self.undo, 1) end
    self.redo = {}
  end

  local rebuild, commitEdit

  local function restore(text)
    local selectedName = self.selected and self.selected.name
    self.model = B.parse(text) or self.model
    self.selected = nil
    for _, e in ipairs(model.walk(self.model)) do
      if selectedName and e.node.name == selectedName then self.selected = e.node end
    end
    rebuild()
    sync()
  end

  function self.undoChange()
    if self.mode == "code" then if self.code then self.code:undo() end return end
    local text = table.remove(self.undo)
    if not text then return end
    self.redo[#self.redo + 1] = snapshot()
    restore(text)
  end

  function self.redoChange()
    if self.mode == "code" then if self.code then self.code:redo() end return end
    local text = table.remove(self.redo)
    if not text then return end
    self.undo[#self.undo + 1] = snapshot()
    restore(text)
  end

  local function surfaceOrigin()
    return 2 - self.scrollX, 2 - self.scrollY
  end

  local function measureLabels()
    local longest = 6
    for _, r in ipairs(B.rootRows(self.model)) do longest = math.max(longest, #r.name) end
    local seen = {}
    for _, e in ipairs(model.walk(self.model)) do
      if not seen[e.node.type] then
        seen[e.node.type] = true
        for _, r in ipairs(B.inspector(e.node, surface)) do longest = math.max(longest, #r.name) end
      end
    end
    local labelW = longest + 1
    if labelW ~= self.labelW then
      self.labelW = labelW
      if self.layout and side then self.layout() end
    end
  end

  local function scrollLimits()
    local cw, ch = self.model.width + 3, self.model.height + 3
    local vw, vh = area.width, area.height
    local v = ch > vh
    local h = cw > vw - (v and 1 or 0)
    if h and not v then v = ch > vh - 1 end
    vw, vh = vw - (v and 1 or 0), vh - (h and 1 or 0)
    return math.max(0, cw - vw), math.max(0, ch - vh), v, h, cw, ch, vw, vh
  end

  local function clampScroll()
    local mx, my = scrollLimits()
    self.scrollX = math.max(0, math.min(self.scrollX, mx))
    self.scrollY = math.max(0, math.min(self.scrollY, my))
  end

  local function scrollTo(x, y)
    self.scrollX, self.scrollY = x or self.scrollX, y or self.scrollY
    clampScroll()
    local ox, oy = surfaceOrigin()
    if surface then surface.moveTo(ox, oy) end
    overlay:markRenderDirty()
    area:markDirty()
  end
  self.scrollTo = scrollTo

  function rebuild()
    if surface then surface.destroy() end
    if area.width then clampScroll() end
    local ox, oy = surfaceOrigin()
    surface = B.build(area, self.model, ox, oy, theme)
    measureLabels()
    if overlay then overlay:markRenderDirty() end
    if side then side:markRenderDirty() end
    if bar then bar:markRenderDirty() end
  end

  local function rectOf(node)
    local x, y, w, h = surface.rect(node)
    if not x then return nil end
    local ox, oy = surfaceOrigin()
    return ox + x - 1, oy + y - 1, w, h
  end

  local function nodeAt(x, y)
    local list = model.walk(self.model)
    for i = #list, 1, -1 do
      local rx, ry, rw, rh = rectOf(list[i].node)
      if rx and x >= rx and x < rx + rw and y >= ry and y < ry + rh then return list[i].node end
    end
    return nil
  end

  local function parentOf(node)
    for _, e in ipairs(model.walk(self.model)) do
      if e.node == node then return e.parent end
    end
  end

  local function siblings(node)
    local parent = parentOf(node)
    return parent and parent.children or self.model.children
  end

  local function select(node)
    self.selected = node
    self.editing = nil
    overlay:markRenderDirty()
    side:markRenderDirty()
    bar:markRenderDirty()
  end

  function self.add(typeName)
    remember()
    local target = self.model.children
    local sel = self.selected
    if sel and B.isContainer(sel.type) then
      sel.children = sel.children or {}
      target = sel.children
    end
    local node = B.newNode(self.model, typeName)
    target[#target + 1] = node
    rebuild()
    select(node)
    sync()
    return node
  end

  function self.delete()
    if self.mode == "code" then return end
    local node = self.selected
    if not node then return end
    remember()
    local list = siblings(node)
    for i = #list, 1, -1 do if list[i] == node then table.remove(list, i) end end
    self.selected = nil
    rebuild()
    sync()
  end

  function self.duplicate()
    if self.mode == "code" then if self.code then self.code:duplicateLines() end return end
    local node = self.selected
    if not node then return end
    remember()
    local copy = model.copy(node)
    copy.name = model.uniqueName(self.model, node.type)
    B.move(copy, B.position(node, surface), 1, 1)
    local list = siblings(node)
    list[#list + 1] = copy
    rebuild()
    select(copy)
    sync()
  end

  function self.setProp(name, value)
    remember()
    local node = self.selected
    if not node then
      if name == "width" or name == "height" then
        self.model[name] = math.max(1, math.floor(tonumber(value) or self.model[name]))
      else
        B.setRoot(self.model, name, value)
      end
    elseif name == "name" then
      node.name = (value and value ~= "") and value or nil
    else
      node.props = node.props or {}
      node.props[name] = value
    end
    rebuild()
    sync()
  end

  local function sizeMenu(cx)
    local presets = {
      { label = "Computer", detail = "51x19", w = 51, h = 19 },
      { label = "Pocket computer", detail = "26x20", w = 26, h = 20 },
      { label = "Turtle", detail = "39x13", w = 39, h = 13 },
      { label = "Monitor 2x1", detail = "36x10", w = 36, h = 10 },
      { label = "Monitor 3x2", detail = "57x24", w = 57, h = 24 },
    }
    local ax, ay = bar:getAbsolutePosition()
    ui:popupMenu(ax + cx - 1, ay - #presets, presets, function(item)
      if item then
        remember()
        self.model.width, self.model.height = item.w, item.h
        rebuild(); sync()
      end
      overlay:focus()
    end)
  end

  local function drawBar(_, buf)
    local w = bar.width
    local bg, fg = theme.panelHeaderBackground, theme.menuForeground or theme.panelHeaderForeground
    buf:fill(1, 1, w, 1, " ", fg, bg)
    self.barHits = {}

    local tabsWidth = 0
    for _, t in ipairs(TABS) do tabsWidth = tabsWidth + #t[1] end
    local tx = math.max(1, w - tabsWidth + 1)
    for _, t in ipairs(TABS) do
      local label, mode = t[1], t[2]
      local active = self.mode == mode
      buf:blit(tx, 1, label,
        active and (theme.tabActiveForeground or theme.accentForeground or fg) or fg,
        active and (theme.tabActiveBackground or theme.accent) or bg)
      self.barHits[#self.barHits + 1] = { x1 = tx, x2 = tx + #label - 1, action = function() self.setMode(mode) end }
      tx = tx + #label
    end
    local limit = w - tabsWidth - 1

    if self.mode == "code" then
      if self.error then
        local message = (" Error: " .. tostring(self.error)):gsub("\n", " ")
        buf:blit(1, 1, message:sub(1, math.max(0, limit)), colors.red, bg)
      end
      return
    end

    local narrow = w < 40
    local items = {
      { narrow and " Del " or " Delete ", function() self.delete() end, self.selected == nil },
      { " " .. self.model.width .. "x" .. self.model.height .. (narrow and " " or " \30 "), sizeMenu },
    }
    if not wide() then
      table.insert(items, 1, { self.showSide and " Canvas " or " Tools ", function()
        commitEdit()
        self.showSide = not self.showSide
        self.layout()
      end })
    end
    local x, gap = 1, narrow and 0 or 1
    for _, item in ipairs(items) do
      local label, action, disabled = item[1], item[2], item[3]
      if x + #label - 1 > limit then break end
      buf:blit(x, 1, label, disabled and theme.panelHeaderForeground or fg, bg)
      local from = x
      if not disabled then
        self.barHits[#self.barHits + 1] = { x1 = x, x2 = x + #label - 1, action = function() action(from) end }
      end
      x = x + #label + gap
    end
  end

  local function drawOverlay(_, buf)
    local node = self.selected
    local rx, ry, rw, rh
    if node then
      rx, ry, rw, rh = rectOf(node)
    else
      rx, ry = surfaceOrigin()
      rw, rh = self.model.width, self.model.height
    end
    if not rx then return end
    local accent = theme.accent
    for _, c in ipairs({ { rx - 1, ry - 1 }, { rx + rw, ry - 1 }, { rx - 1, ry + rh } }) do
      buf:blit(c[1], c[2], " ", accent, accent)
    end
    if node then
      buf:blit(rx + rw, ry + rh, "\127", theme.accentForeground, accent)
    else
      buf:blit(rx + rw, ry + rh, " ", accent, accent)
    end

    local _, _, v, h, cw, ch, vw, vh = scrollLimits()
    self.bars = { v = v, h = h, vw = vw, vh = vh, cw = cw, ch = ch }
    if v then scrollbar.draw(buf, theme, overlay.width, 1, vh, ch, vh, self.scrollY) end
    if h then
      local start, size = scrollbar.thumb(vw, cw, vw, self.scrollX)
      for col = 0, vw - 1 do
        local on = start and col >= start and col < start + size
        buf:blit(col + 1, overlay.height, " ", colors.white,
          on and (theme.scrollbarThumb or colors.gray) or (theme.scrollbarTrack or colors.lightGray))
      end
    end
    if v and h then
      buf:blit(overlay.width, overlay.height, " ", colors.white, theme.scrollbarTrack or colors.lightGray)
    end
  end

  local function inspectorRows()
    local node = self.selected
    if not node then
      local rows = {
        { name = "width", kind = "number", value = self.model.width },
        { name = "height", kind = "number", value = self.model.height },
      }
      for _, r in ipairs(B.rootRows(self.model)) do rows[#rows + 1] = r end
      return rows, "Screen"
    end
    local rows = { { name = "name", kind = "string", value = node.name, isName = true } }
    for _, r in ipairs(B.inspector(node, surface)) do rows[#rows + 1] = r end
    return rows, node.type
  end

  local function showValue(row)
    local v = row.value
    if row.kind == "color" then return B.colorLabel(v) end
    if v == nil then return "" end
    if type(v) == "function" then return "auto" end
    return tostring(v)
  end

  local function treeEntries()
    local out = { { label = "Screen", depth = 0 } }
    local function visit(list, depth)
      for _, n in ipairs(list or {}) do
        out[#out + 1] = { node = n, depth = depth }
        if n.children then visit(n.children, depth + 1) end
      end
    end
    visit(self.model.children, 1)
    return out
  end

  -- Share the sidebar height between open sections: each gets what it needs if possible,
  -- otherwise an even share, and leftover space goes to the last open section so the
  -- collapsed headers below it sit at the bottom.
  local function allocate(total, needs)
    local open, sizes = {}, {}
    for _, s in ipairs(self.sections) do
      if s.open then open[#open + 1] = s; sizes[s.id] = 0 end
    end
    local rest = math.max(0, total - #self.sections)
    local pending = {}
    for i, s in ipairs(open) do pending[i] = s end
    while rest > 0 and #pending > 0 do
      local share = math.max(1, math.floor(rest / #pending))
      local still = {}
      for _, s in ipairs(pending) do
        local give = math.min(share, needs[s.id] - sizes[s.id], rest)
        sizes[s.id] = sizes[s.id] + give
        rest = rest - give
        if sizes[s.id] < needs[s.id] then still[#still + 1] = s end
      end
      pending = still
    end
    if rest > 0 and #open > 0 then
      local last = open[#open]
      sizes[last.id] = sizes[last.id] + rest
    end
    return sizes
  end

  local function clampOffset(id, total, height)
    local off = math.max(0, math.min(self.offsets[id] or 0, total - height))
    self.offsets[id] = off
    return off
  end

  local function sideColors()
    return theme.sidebarBackground, theme.sidebarForeground, theme.muted
  end

  local function drawToolbox(buf, y0, height, width)
    local bg, fg = sideColors()
    local list = B.TYPES
    local off = clampOffset("toolbox", #list, height)
    local barW = #list > height and 1 or 0
    for i = 1, height do
      local typeName = list[off + i]
      if not typeName then break end
      local y = y0 + i - 1
      buf:blit(2, y, typeName:sub(1, math.max(0, width - 2 - barW)), fg, bg)
      self.sideHits[y] = { action = function()
        self.add(typeName)
        if area.visible then overlay:focus() end
      end }
    end
    if barW == 1 then scrollbar.draw(buf, theme, width, y0, height, #list, height, off) end
  end

  local function drawTree(buf, entries, y0, height, width)
    local bg, fg, muted = sideColors()
    local selBg = theme.listSelectionBackground or theme.sidebarSelection or theme.accent
    local selFg = theme.listSelectionForeground or theme.sidebarSelectionForeground or theme.accentForeground or fg
    local off = clampOffset("tree", #entries, height)
    local barW = #entries > height and 1 or 0
    local textW = width - barW
    for i = 1, height do
      local e = entries[off + i]
      if not e then break end
      local y = y0 + i - 1
      local isSelected = e.node == self.selected
      local rowBg, rowFg = isSelected and selBg or bg, isSelected and selFg or fg
      if isSelected then buf:fill(1, y, textW, 1, " ", rowFg, rowBg) end
      local x = 2 + e.depth
      local name = e.node and (e.node.name or "?") or e.label
      if x <= textW then buf:blit(x, y, name:sub(1, textW - x + 1), rowFg, rowBg) end
      if e.node then
        local tx = x + #name + 1
        if tx + #e.node.type - 1 <= textW then
          buf:blit(tx, y, e.node.type, isSelected and selFg or muted, rowBg)
        end
      end
      self.sideHits[y] = { action = function()
        select(e.node)
        if area.visible then overlay:focus() end
      end }
    end
    if barW == 1 then scrollbar.draw(buf, theme, width, y0, height, #entries, height, off) end
  end

  local function drawProps(buf, rows, y0, height, width)
    local bg, fg, muted = sideColors()
    local fieldBg = theme.fieldBackground or theme.inputBackground
    if fieldBg == bg then fieldBg = theme.editorBackground end
    local fieldTheme = setmetatable({ inputBackground = fieldBg, inputForeground = theme.inputForeground },
      { __index = theme })
    local off = clampOffset("props", #rows, height)
    local barW = #rows > height and 1 or 0
    local longest = 4
    for _, r in ipairs(rows) do longest = math.max(longest, #r.name) end
    local labelW = math.max(4, math.min(math.max(longest + 1, self.labelW or 0), width - barW - 9))
    local valueX = labelW + 2
    local valueW = math.max(1, width - barW - valueX + 1)
    local cursorX, cursorY
    for i = 1, height do
      local row = rows[off + i]
      if not row then break end
      local y = y0 + i - 1
      local label = row.name
      if #label > labelW - 1 then label = label:sub(1, labelW - 2) .. "~" end
      buf:blit(2, y, label, row.default and muted or fg, bg)
      local value = showValue(row)
      if self.editing and self.editing.prop == row.name then
        cursorX = dialogs.drawField(buf, fieldTheme, self.editing.field, valueX, y, valueW)
        cursorY = y
      elseif row.kind == "boolean" then
        buf:blit(valueX, y, row.value and "[x]" or "[ ]", row.value and theme.accent or theme.inputForeground, fieldBg)
      elseif row.kind == "color" then
        local swatch = B.colorValue(row.value) or bg
        buf:blit(valueX, y, "  ", fg, swatch)
        buf:blit(valueX + 3, y, (value .. string.rep(" ", valueW)):sub(1, math.max(0, valueW - 3)),
          row.default and muted or theme.inputForeground, fieldBg)
      else
        buf:blit(valueX, y, (" " .. value .. string.rep(" ", valueW)):sub(1, valueW),
          row.default and muted or theme.inputForeground, fieldBg)
      end
      self.propHits[#self.propHits + 1] = { y = y, row = row, x = valueX }
    end
    if barW == 1 then scrollbar.draw(buf, theme, width, y0, height, #rows, height, off) end
    return cursorX, cursorY
  end

  local function drawSide(_, buf)
    local w, h = side.width, side.height
    local bg, fg = sideColors()
    buf:fill(1, 1, w, h, " ", fg, bg)
    local width = w
    if wide() then
      width = w - 1
      buf:fill(w, 1, 1, h, " ", fg, theme.dividerBackground or theme.editorBackground)
    end

    local rows, title = inspectorRows()
    local entries = treeEntries()
    self.propRows = rows
    self.sideHits, self.propHits, self.sideBodies = {}, {}, {}
    local sizes = allocate(h, {
      toolbox = math.max(1, #B.TYPES), props = math.max(1, #rows), tree = math.max(1, #entries),
    })

    local cursorX, cursorY
    local y = 1
    for _, s in ipairs(self.sections) do
      if y > h then break end
      -- Section headers use the theme's handle colours so they stand out from the lists.
      local hbg = theme.handleBackground or theme.menuBackground or colors.black
      local hfg = theme.menuForeground or colors.white
      buf:fill(1, y, width, 1, " ", hfg, hbg)
      buf:blit(2, y, s.title:sub(1, math.max(0, width - 3)), hfg, hbg)
      if s.id == "props" and 2 + #s.title + 1 + #title <= width - 2 then
        buf:blit(2 + #s.title + 1, y, title, theme.handleForeground or theme.accent, hbg)
      end
      buf:blit(math.max(1, width - 1), y, s.open and OPEN_ICON or CLOSED_ICON, hfg, hbg)
      self.sideHits[y] = { header = s }
      y = y + 1
      if s.open then
        local height = math.min(sizes[s.id] or 0, h - y + 1)
        if height > 0 then
          self.sideBodies[#self.sideBodies + 1] = { id = s.id, y1 = y, y2 = y + height - 1 }
          if s.id == "toolbox" then drawToolbox(buf, y, height, width)
          elseif s.id == "props" then cursorX, cursorY = drawProps(buf, rows, y, height, width)
          else drawTree(buf, entries, y, height, width) end
          y = y + height
        end
      end
    end

    local root = side:getRoot()
    if cursorX and root.getFocused and root:getFocused() == side then
      side:setCursor(cursorX, cursorY, true, theme.inputForeground)
    end
  end

  function commitEdit()
    local e = self.editing
    if not e then return end
    self.editing = nil
    local text = e.field.text
    local value
    if e.kind == "number" then
      if text == "" then value = nil
      else
        value = tonumber(text)
        if not value then ui:notify(e.prop .. " must be a number", "warning", 2) side:markRenderDirty() return end
      end
    elseif e.kind == "size" then

      if text == "" then value = nil
      elseif tonumber(text) then value = tonumber(text)
      elseif text:match("^[%d%.%%,%s%-%+]+$") then value = (text:gsub("%s", ""))
      else ui:notify(e.prop .. " must be a number or like 50%,-3", "warning", 3) side:markRenderDirty() return end
    else
      value = text
      if text == "" and e.prop ~= "text" then value = nil end
    end
    self.setProp(e.prop, value)
  end

  local function activateRow(row, x, y)
    commitEdit()
    if row.kind == "boolean" then
      self.setProp(row.name, not row.value)
    elseif row.kind == "color" then
      local entries = B.colorChoices(self.selected == nil)
      local ax, ay = side:getAbsolutePosition()
      ui:popupMenu(ax + x - 1, ay + y, entries, function(item)
        if item then self.setProp(row.name, item.value) end
        side:focus()
      end)
    else
      local text = (row.value ~= nil and type(row.value) ~= "function") and tostring(row.value) or ""
      if row.default and row.kind ~= "string" then text = "" end
      self.editing = { prop = row.name, kind = row.kind, field = { text = text, cursor = #text + 1 } }
      side:focus()
      side:markRenderDirty()
    end
  end

  function self.layout()
    local w, h = host.width, host.height
    local bodyH = math.max(1, h - 1)
    local code = self.mode == "code"
    local sw = sideWidth()
    side.visible = not code and (wide() or self.showSide)
    side.x, side.y, side.width, side.height = 1, 1, sw, bodyH
    area.visible = not code and (wide() or not self.showSide)
    area.x, area.y = wide() and (sw + 1) or 1, 1
    area.width = wide() and math.max(1, w - sw) or w
    area.height = bodyH
    overlay.width, overlay.height = area.width, area.height
    if codeHost then
      codeHost.visible = code
      codeHost.width, codeHost.height = w, bodyH
    end
    bar.y, bar.width = math.max(1, h), w
    if surface then scrollTo() end
    bar:markRenderDirty(); side:markRenderDirty(); overlay:markRenderDirty()
  end

  local function ensureCode()
    if self.code then return self.code end
    codeHost = host:addFrame({ x = 1, y = 1, width = host.width, height = math.max(1, host.height - 1),
      background = theme.editorBackground })
    codeHost.visible = false
    self.code = codeView.new(codeHost, doc, {
      theme = theme,
      tabSize = studio.settings:get("editor.tabSize", 2),
      language = languages.forPath(doc.path) or false,
      getClipboard = function() return ui:getClipboard() end,
      setClipboard = function(text) ui:setClipboard(text) end,
    })
    return self.code
  end

  function self.setMode(mode)
    if mode == self.mode then return end
    if mode == "code" then
      commitEdit()
      local code = ensureCode()
      -- Design edits rewrite the document; start the text undo history fresh so it only
      -- covers edits made in this Code session.
      code.buffer._undo, code.buffer._redo = {}, {}
      self.codeBefore = doc:getText()
      self.mode = "code"
    else
      if self.error then
        ui:notify("Fix the layout before switching to Design: " .. tostring(self.error), "error", 5)
        return
      end
      if self.codeBefore and doc:getText() ~= self.codeBefore then
        self.undo[#self.undo + 1] = self.codeBefore
        if #self.undo > 100 then table.remove(self.undo, 1) end
        self.redo = {}
      end
      self.codeBefore = nil
      self.mode = "design"
      if self.stale then self.stale = false; rebuild() end
    end
    self.layout()
    if self.onModeChange then self.onModeChange(self.mode == "code" and self.code or nil) end
    self.focus()
  end

  area = host:addFrame({ x = 1, y = 1, background = theme.panelHeaderBackground })
  overlay = area:addCanvas({ x = 1, y = 1, z = 100, background = false, draw = drawOverlay })
  side = host:addCanvas({ x = 1, y = 1, z = 5, background = theme.sidebarBackground, draw = drawSide })
  bar = host:addCanvas({ x = 1, y = math.max(1, host.height), height = 1, width = host.width, z = 5,
    background = theme.panelHeaderBackground, draw = drawBar })

  bar:onClick(function(_, _, x)
    for _, hit in ipairs(self.barHits or {}) do
      if x >= hit.x1 and x <= hit.x2 then hit.action() return end
    end
  end)

  local drag
  local function barScroll(x, y)
    local b = self.bars
    if self._barDrag == "v" then
      scrollTo(nil, scrollbar.offsetAt(y - 1, b.vh, b.ch, b.vh))
    elseif self._barDrag == "h" then
      scrollTo(scrollbar.offsetAt(x - 1, b.vw, b.cw, b.vw), nil)
    end
  end
  overlay:onClick(function(_, btn, x, y)
    commitEdit()
    local b = self.bars
    if b and b.v and x == overlay.width and y <= b.vh then
      self._barDrag = "v"; barScroll(x, y) return
    elseif b and b.h and y == overlay.height and x <= b.vw then
      self._barDrag = "h"; barScroll(x, y) return
    end
    local node = self.selected
    if node then
      local rx, ry, rw, rh = rectOf(node)
      if rx and x == rx + rw and y == ry + rh then
        drag = { mode = "resize", node = node, x = x, y = y,
          start = B.position(node, surface), before = snapshot() }
        return
      end
    end
    local hit = nodeAt(x, y)
    select(hit)
    if hit then
      drag = { mode = "move", node = hit, x = x, y = y, start = B.position(hit, surface), before = snapshot() }
    else
      drag = nil
    end
  end)
  overlay:onDrag(function(_, _, x, y)
    if self._barDrag then barScroll(x, y) return end
    if not drag then return end
    local node = drag.node
    if not drag.start then return end
    if drag.mode == "move" then
      B.move(node, drag.start, x - drag.x, y - drag.y)
    else
      B.resize(node, drag.start, x - drag.x, y - drag.y)
    end
    surface.update(node)
    drag.moved = true
    overlay:markRenderDirty()
    side:markRenderDirty()
    area:markDirty()
  end)
  overlay:onClickUp(function()
    self._barDrag = nil
    if drag and drag.moved then
      self.undo[#self.undo + 1] = drag.before
      self.redo = {}
      sync()
    end
    drag = nil
  end)
  overlay:onScroll(function(_, dir)
    local root = overlay:getRoot()
    local shift = root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
    if shift then scrollTo(self.scrollX + dir * 2, nil)
    else scrollTo(nil, self.scrollY + dir) end
  end)
  overlay:onKey(function(_, key)
    local node = self.selected
    if key == keys.delete or key == keys.backspace then self.delete() return end
    if key == keys.tab then
      local list = model.walk(self.model)
      if #list == 0 then return end
      local index = 0
      for i, e in ipairs(list) do if e.node == node then index = i end end
      select(list[index % #list + 1].node)
      return
    end
    if not node then return end
    local dx, dy = 0, 0
    if key == keys.left then dx = -1 elseif key == keys.right then dx = 1
    elseif key == keys.up then dy = -1 elseif key == keys.down then dy = 1 else return end
    remember()
    B.move(node, B.position(node, surface), dx, dy)
    surface.update(node)
    sync()
    overlay:markRenderDirty(); side:markRenderDirty(); area:markDirty()
  end)

  side:onClick(function(_, _, x, y)
    local hit = self.sideHits and self.sideHits[y]
    if hit and hit.header then
      commitEdit()
      hit.header.open = not hit.header.open
      side:markRenderDirty()
      return
    end
    for _, ph in ipairs(self.propHits or {}) do
      if ph.y == y then
        if x >= ph.x then activateRow(ph.row, x, y) else commitEdit() end
        side:markRenderDirty()
        return
      end
    end
    commitEdit()
    if hit and hit.action then hit.action() end
    side:markRenderDirty()
  end)
  side:onScroll(function(_, dir, _, y)
    for _, body in ipairs(self.sideBodies or {}) do
      if not y or (y >= body.y1 and y <= body.y2) then
        self.offsets[body.id] = math.max(0, (self.offsets[body.id] or 0) + dir)
        side:markRenderDirty()
        return
      end
    end
  end)
  side:onKey(function(_, key)
    if not self.editing then return end
    if key == keys.enter or key == keys.numPadEnter then commitEdit()
    elseif dialogs.editField(self.editing.field, key) then side:markRenderDirty() end
  end)
  side:onKeyUp(function(_, key)
    if key == (keys.escape or -1) and self.editing then self.editing = nil; side:markRenderDirty() end
  end)
  side:onChar(function(_, ch)
    if self.editing then dialogs.insertField(self.editing.field, ch); side:markRenderDirty() end
  end)
  side:onBlur(function() commitEdit() end)

  local listener = doc:on("change", function()
    if syncing then return end
    local parsed, perr = B.parse(doc:getText())
    if parsed then
      self.model, self.error = parsed, nil
      self.selected = nil
      if self.mode == "code" then self.stale = true else rebuild() end
    else
      self.error = perr
    end
    bar:markRenderDirty()
  end)

  local startInCode = false
  if not self.model then
    -- The file doesn't parse: open it as text so the user can fix it, instead of showing
    -- an empty canvas whose first edit would overwrite the file.
    self.model = B.newModel()
    startInCode = true
  end
  rebuild()
  self.layout()

  function self.focus()
    if self.mode == "code" and self.code then self.code:focus() else overlay:focus() end
  end
  function self.applyTheme(_, t)
    theme = t
    bar.background = t.panelHeaderBackground
    area.background = t.panelHeaderBackground
    side.background = t.sidebarBackground
    if codeHost then codeHost.background = t.editorBackground end
    if self.code then self.code:applyTheme(t) end
    bar:markRenderDirty(); side:markRenderDirty(); overlay:markRenderDirty()
  end
  function self.dispose()
    listener:dispose()
    if self.code then self.code:dispose() end
    bar:destroy(); area:destroy(); side:destroy()
    if codeHost then codeHost:destroy() end
  end
  if startInCode then
    self.setMode("code")
    ui:notify(fs.getName(doc.path) .. ": " .. tostring(err) .. " (opened in Code view)", "error", 5)
  end
  function self.elementOf(node) return surface.elementOf and surface.elementOf(node) end
  function self.rectOf(node) return rectOf(node) end
  self.area = area
  self.propsCanvas = side
  return self
end

return M

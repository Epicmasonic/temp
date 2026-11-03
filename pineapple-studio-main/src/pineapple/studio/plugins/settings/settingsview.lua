local dialogs = require("pineapple.studio.ui.dialogs")
local scrollbar = require("pineapple.studio.ui.scrollbar")
local R = require("pineapple.studio.ui.rows")

local M = {}

local PAGE_MODULES = {
  "pineapple.studio.plugins.settings.generalpage",
  "pineapple.studio.plugins.settings.pluginspage",
  "pineapple.studio.plugins.settings.themespage",
  "pineapple.studio.plugins.settings.keyspage",
}

function M.new(host, studio, theme)
  local ui = studio.ui
  local self = { hits = {}, pages = {}, state = {} }
  local canvas
  local function dirty() if canvas then canvas:markRenderDirty() end end

  local ctx = { studio = studio, theme = theme, dirty = dirty }

  function ctx.popup(x, y, items, callback)
    local ax, ay = canvas:getAbsolutePosition()
    ui:popupMenu(ax + x - 1, ay + y, items, function(item)
      callback(item)
      canvas:focus()
      dirty()
    end)
  end

  for _, name in ipairs(PAGE_MODULES) do
    local page = require(name).new(ctx)
    self.pages[#self.pages + 1] = page
    self.pages[page.id] = page
    self.state[page.id] = { query = { text = "", cursor = 1 }, scroll = 0, focus = nil }
  end
  self.page = self.pages[1]

  local function st() return self.state[self.page.id] end

  local function leave()
    local p = self.page
    if p.commit then p.commit() end
  end

  function self.show(id, scope)
    local page = self.pages[id] or self.pages[1]
    if page ~= self.page then leave(); self.page = page end
    if scope and page.setScope then page.setScope(scope) end
    dirty()
  end
  function self.setScope(scope) self.show("general", scope) end

  local function draw(_, buf)
    local w, h = canvas.width, canvas.height
    local t = ctx.theme
    R.theme = t
    ctx.cursor = nil
    local bg, fg, muted, accent = t.editorBackground, t.foreground, t.muted, t.accent
    local hits = {}
    self.hits = hits
    local s = st()
    buf:fill(1, 1, w, h, " ", fg, bg)

    local wide = w >= 46

    local bandBg, bandFg = t.panelHeaderBackground, t.panelHeaderForeground
    local tall = h >= 22
    local titleY = tall and 2 or 1
    local searchY = titleY + 2
    local bandH = searchY + 1
    buf:fill(1, 1, w, bandH, " ", bandFg, bandBg)
    local x
    if wide then
      buf:blit(3, titleY, "Settings", accent, bandBg)
      x = 13
    else
      local label = " " .. (self.page.short or self.page.label) .. " v "
      buf:blit(2, titleY, label, t.accentForeground, accent)
      hits[#hits + 1] = { x1 = 2, x2 = 1 + #label, y = titleY, action = function()
        local items = {}
        for _, p in ipairs(self.pages) do
          items[#items + 1] = { label = p.label, detail = p == self.page and "*" or nil, id = p.id }
        end
        ctx.popup(2, titleY, items, function(item) if item then self.show(item.id) end end)
      end }
      x = 3 + #label
    end
    for _, c in ipairs(self.page.header and self.page.header() or {}) do
      if x + #c.label - 1 <= w then
        local on = c.active or c.button
        buf:blit(x, titleY, c.label, on and t.accentForeground or bandFg, on and accent or bandBg)
        hits[#hits + 1] = { x1 = x, x2 = x + #c.label - 1, y = titleY, action = c.action }
      end
      x = x + #c.label + (c.button and 1 or 0)
    end
    local top = bandH + 2
    local contentX = 3
    local colW = wide and (w >= 72 and 20 or 12) or 0
    if wide then contentX = colW + 3 end

    local searchX = wide and (colW + 1) or 2
    local searchW = math.max(6, w - searchX)
    local searchTheme = setmetatable({ inputBackground = bg ~= bandBg and bg or (t.fieldBackground or t.inputBackground) },
      { __index = t })
    local searchCursor = dialogs.drawField(buf, searchTheme, s.query, searchX, searchY, searchW,
      self.page.placeholder or "Search")
    hits[#hits + 1] = { x1 = searchX, x2 = searchX + searchW - 1, y = searchY, action = function()
      if self.page.commit then self.page.commit() end
    end }

    if wide then

      local colBg = t.sidebarBackground
      buf:fill(1, bandH + 1, colW, h - bandH, " ", t.sidebarForeground, colBg)
      for i, p in ipairs(self.pages) do
        local y = top + i - 1
        if y > h then break end
        local active = p == self.page
        local name = (colW >= #p.label + 2) and p.label or (p.short or p.label)
        local rowFg = active and (t.sidebarSelectionForeground or t.accentForeground) or t.sidebarForeground
        local rowBg = active and (t.sidebarSelection or accent) or colBg
        buf:blit(1, y, (" " .. name .. string.rep(" ", colW)):sub(1, colW), rowFg, rowBg)
        local id = p.id
        hits[#hits + 1] = { x1 = 1, x2 = colW, y = y, action = function() self.show(id) end }
      end
    end
    local contentW = w - contentX - 2

    local rows = self.page.rows(contentW, s.query.text)
    local focusables = {}
    for i, r in ipairs(rows) do if r.focusable then focusables[#focusables + 1] = i end end
    self.focusables = focusables
    if s.focus and s.focus > #focusables then s.focus = #focusables > 0 and #focusables or nil end
    local focusRow = s.focus and self.keyboard and focusables[s.focus]

    local visible = h - top + 1
    if focusRow and not s.noFollow then
      if focusRow - 1 < s.scroll then s.scroll = math.max(0, focusRow - 2) end
      if focusRow + 3 > s.scroll + visible then s.scroll = focusRow + 3 - visible end
    end
    s.scroll = math.max(0, math.min(s.scroll, math.max(0, #rows - visible)))
    self.maxScroll = math.max(0, #rows - visible)

    for r = 1, visible do
      local i = s.scroll + r
      local row = rows[i]
      if not row then break end
      local y = top + r - 1
      local function hit(x1, x2, action) hits[#hits + 1] = { x1 = x1, x2 = x2, y = y, action = action } end
      row.draw(buf, contentX, y, contentW, i == focusRow, hit)
    end
    self.rows = rows

    self.bar = { x = w, y = top, height = visible, total = #rows, visible = visible }
    scrollbar.draw(buf, t, w, top, visible, #rows, visible, s.scroll)

    local root = canvas:getRoot()
    if root.getFocused and root:getFocused() == canvas then
      if ctx.cursor then canvas:setCursor(ctx.cursor[1], ctx.cursor[2], true, t.inputForeground)
      else canvas:setCursor(searchCursor, searchY, true, t.inputForeground) end
    end
  end

  canvas = host:addCanvas({
    x = 1, y = 1,
    width = function() return host.width end,
    height = function() return host.height end,
    background = theme.editorBackground,
    draw = draw,
  })

  local function scrollTo(y)
    local bar = self.bar
    st().scroll = scrollbar.offsetAt(y - bar.y, bar.height, bar.total, bar.visible)
    st().noFollow = true
    dirty()
  end
  canvas:onDrag(function(_, _, _, y) if self._barDrag then scrollTo(y) end end)
  canvas:onClickUp(function() self._barDrag = false end)
  canvas:onClick(function(_, _, x, y)
    self.keyboard = false
    st().noFollow = false
    local bar = self.bar
    if bar and x == bar.x and y >= bar.y and bar.total > bar.visible then
      self._barDrag = true
      scrollTo(y)
      return
    end
    for _, hit in ipairs(self.hits) do
      if y == hit.y and x >= hit.x1 and x <= hit.x2 then hit.action(); dirty(); return end
    end
    if self.page.commit then self.page.commit() end
    dirty()
  end)
  canvas:onScroll(function(_, dir)
    local s = st()
    s.scroll = math.max(0, math.min(self.maxScroll or 0, s.scroll + dir * 2))
    s.noFollow = true
    dirty()
  end)

  local function focusedRow()
    local s = st()
    local list = self.focusables or {}
    local index = s.focus or 1
    return self.rows and self.rows[list[index] or 0]
  end

  canvas:onKey(function(_, key)
    local page, s = self.page, st()
    if page.onKey and page.onKey(key) then return end
    s.noFollow = false
    local n = #(self.focusables or {})
    if key == keys.up or key == keys.down then
      self.keyboard = true
      if not s.focus then s.focus = key == keys.down and 1 or n
      else s.focus = math.max(1, math.min(n, s.focus + (key == keys.up and -1 or 1))) end
    elseif key == keys.pageUp or key == keys.pageDown then
      s.scroll = math.max(0, math.min(self.maxScroll or 0, s.scroll + (key == keys.pageUp and -8 or 8)))
      s.noFollow = true
    elseif key == keys.enter or key == keys.numPadEnter then
      self.keyboard = true
      s.focus = s.focus or 1
      local row = focusedRow()
      if row and row.activate then row.activate() end
    elseif key == keys.left or key == keys.right then
      self.keyboard = true
      s.focus = s.focus or 1
      local row = focusedRow()
      if row and row.cycle then row.cycle(key == keys.left and -1 or 1) end
    elseif dialogs.editField(s.query, key) then
      s.focus, s.scroll = nil, 0
    else
      return
    end
    dirty()
  end)
  canvas:onChar(function(_, ch)
    local page, s = self.page, st()
    if page.onChar and page.onChar(ch) then return end
    dialogs.insertField(s.query, ch)
    s.focus, s.scroll = nil, 0
    dirty()
  end)
  canvas:onPaste(function(_, text)
    if self.page.onPaste and self.page.onPaste(text) then return end
    dialogs.insertField(st().query, (text:gsub("\n.*", "")))
    dirty()
  end)
  canvas:onBlur(function() leave() end)

  local subscription = studio.settings:onChange("*", dirty)

  self.element = canvas
  function self.focus() canvas:focus(); dirty() end
  function self.applyTheme(_, t) canvas.background = t.editorBackground; dirty() end
  function self.dispose()
    for _, p in ipairs(self.pages) do if p.dispose then p.dispose() end end
    if subscription and subscription.dispose then subscription:dispose() end
    canvas:destroy()
  end

  function self.activateKey(key) return self.pages.general.activateKey(key) end
  function self.toggleId(id) return self.pages.plugins.toggleId(id) end
  return self
end

return M

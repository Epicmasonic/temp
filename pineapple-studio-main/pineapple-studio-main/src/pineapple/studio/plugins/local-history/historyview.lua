-- The Local History tab for one file: a list of versions (newest first, with "Current" on
-- top), a diff for the selected version, and Revert.
local diff = require("pineapple.studio.core.diff")
local files = require("pineapple.studio.core.files")
local scrollbar = require("pineapple.studio.ui.scrollbar")

local M = {}

function M.stamp(ms)
  local ok, text = pcall(os.date, "!%d %b %H:%M", math.floor((ms or 0) / 1000))
  return ok and text or "?"
end
local stamp = M.stamp

local MODES = { { " This change ", "change" }, { " Compare to now ", "current" } }

function M.new(host, studio, options)
  local ui, ws = studio.ui, studio.workspace
  local store = options.store
  local self = {
    path = options.path,
    selectedId = "current",
    selected = 1,
    listScroll = 0, diffScroll = 0,
    mode = "change",
    cache = {},
    list = {}, diffRows = {},
  }
  local canvas

  local function content(entry)
    if self.cache[entry.id] == nil then self.cache[entry.id] = store:read(entry) or "" end
    return self.cache[entry.id]
  end

  local function recompute()
    self.exists = fs.exists(self.path) and not fs.isDir(self.path)
    local now = self.exists and (files.read(self.path) or "") or nil
    self.list = { { current = true, id = "current" } }
    for _, e in ipairs(store:entries(self.path)) do self.list[#self.list + 1] = { entry = e, id = e.id } end

    self.selected = 1
    for i, item in ipairs(self.list) do
      if item.id == self.selectedId then self.selected = i end
    end
    self.selectedId = self.list[self.selected].id

    local item = self.list[self.selected]
    self.diffRows = {}
    if item.current then
      if #self.list == 1 then
        self.summary = "No earlier versions yet. Versions are kept each time Studio changes this file."
      elseif self.exists then
        self.summary = "The file as saved now. Select an earlier version to see what changed."
      else
        self.summary = "This file was deleted. Select a version and Revert to restore it."
      end
      return
    end

    local before, after = content(item.entry), nil
    if self.mode == "current" then
      after = now or ""
    else
      local newer = self.list[self.selected - 1]
      after = newer.current and (now or "") or content(newer.entry)
    end
    local ops = diff.compute(before, after)
    local added, removed = diff.stats(ops)
    self.diffRows = diff.hunks(ops, 3)
    if self.mode == "current" then
      self.summary = ("From this version to now: +%d -%d"):format(added, removed)
    else
      self.summary = ("%s, %s: +%d -%d"):format(item.entry.label, stamp(item.entry.time), added, removed)
    end
    if #self.diffRows == 0 then self.summary = self.summary .. " (no differences)" end
  end

  local function geometry()
    local w, h = canvas.width, canvas.height
    local top, bodyH = 2, math.max(0, h - 2)
    if w >= 60 then
      local lw = math.min(32, math.floor(w * 0.4))
      return { side = true,
        list = { x = 1, y = top, w = lw, h = bodyH },
        diff = { x = lw + 2, y = top, w = math.max(1, w - lw - 1), h = bodyH } }
    end
    local lh = math.max(1, math.min(#self.list, math.floor(bodyH / 2)))
    return { side = false,
      list = { x = 1, y = top, w = w, h = lh },
      diff = { x = 1, y = top + lh, w = w, h = math.max(0, bodyH - lh) } }
  end

  local function ensureVisible()
    local L = geometry().list
    if self.selected <= self.listScroll then self.listScroll = self.selected - 1 end
    if self.selected > self.listScroll + L.h then self.listScroll = self.selected - L.h end
  end

  local function select(index)
    index = math.max(1, math.min(index, #self.list))
    self.selectedId = self.list[index].id
    self.diffScroll = 0
    recompute()
    ensureVisible()
    canvas:markRenderDirty()
  end

  local function setMode(mode)
    if self.mode == mode then return end
    self.mode = mode
    self.diffScroll = 0
    recompute()
    canvas:markRenderDirty()
  end

  local function revert()
    local item = self.list[self.selected]
    if not item or item.current then return end
    local entry = item.entry
    local text = content(entry)
    ui:choose({
      title = "Revert File",
      message = "Replace " .. fs.getName(self.path) .. " with the version from " .. stamp(entry.time)
        .. "? What it contains now stays in Local History.",
      buttons = { "Revert", "Cancel" }, default = 2, cancel = 2,
    }, function(choice)
      if choice ~= 1 then return end
      local doc = ws:getDocument(self.path)
      if doc and doc:isDirty() then
        ui:notify(fs.getName(self.path) .. " has unsaved changes. Save or discard them first.", "warning", 4)
        return
      end
      local info = { source = "Revert to " .. stamp(entry.time) }
      local ok, err
      if doc then
        doc:setText(text)
        ok, err = doc:save(info)
      else
        ok, err = ws:writeFile(self.path, text, info)
      end
      if ok then
        self.selectedId = "current"
        recompute()
        canvas:markRenderDirty()
        ui:notify("Reverted " .. fs.getName(self.path), "success", 2)
      else
        ui:notify(tostring(err or "Could not revert the file"), "error")
      end
    end)
  end

  local function draw(_, buf)
    local t = ui:theme()
    local w, h = canvas.width, canvas.height
    local g = geometry()
    self.geo = g
    local hbg, hfg = t.panelHeaderBackground, t.panelHeaderForeground
    buf:fill(1, 1, w, h, " ", t.foreground, t.editorBackground)

    buf:fill(1, 1, w, 1, " ", hfg, hbg)
    local title = "Local History: " .. ws:relative(self.path)
    buf:blit(2, 1, title:sub(1, math.max(0, w - 2)), hfg, hbg)

    -- Versions
    local L = g.list
    local lbg, lfg = t.sidebarBackground, t.sidebarForeground
    local selBg = t.listSelectionBackground or t.sidebarSelection or t.accent
    local selFg = t.listSelectionForeground or t.sidebarSelectionForeground or lfg
    buf:fill(L.x, L.y, L.w, L.h, " ", lfg, lbg)
    self.listScroll = math.max(0, math.min(self.listScroll, #self.list - L.h))
    local listBar = #self.list > L.h and 1 or 0
    for i = 1, L.h do
      local index = self.listScroll + i
      local item = self.list[index]
      if not item then break end
      local y = L.y + i - 1
      local isSelected = index == self.selected
      local bg, fg = isSelected and selBg or lbg, isSelected and selFg or lfg
      if isSelected then buf:fill(L.x, y, L.w - listBar, 1, " ", fg, bg) end
      local text
      if item.current then
        text = self.exists and "Current" or "Current (deleted)"
      else
        text = stamp(item.entry.time) .. "  " .. item.entry.label
      end
      buf:blit(L.x + 1, y, text:sub(1, math.max(0, L.w - 2 - listBar)), fg, bg)
    end
    if listBar == 1 then scrollbar.draw(buf, t, L.x + L.w - 1, L.y, L.h, #self.list, L.h, self.listScroll) end
    if g.side then
      buf:fill(L.x + L.w, L.y, 1, L.h, " ", t.foreground, t.dividerBackground or hbg)
    end

    -- Diff
    local D = g.diff
    if D.h > 0 then
      buf:fill(D.x, D.y, D.w, 1, " ", hfg, hbg)
      buf:blit(D.x + 1, D.y, (self.summary or ""):sub(1, math.max(0, D.w - 2)), hfg, hbg)
      local rowsH = D.h - 1
      local total = #self.diffRows
      self.diffScroll = math.max(0, math.min(self.diffScroll, total - rowsH))
      local diffBar = total > rowsH and 1 or 0
      local textW = D.w - diffBar
      for i = 1, rowsH do
        local r = self.diffRows[self.diffScroll + i]
        if not r then break end
        local text, color
        if r.kind == "gap" then
          text, color = "     ...", t.muted
        else
          local number = r.kind == "del" and r.old or r.new
          local mark = r.kind == "add" and "+" or (r.kind == "del" and "-" or " ")
          text = ("%4s %s %s"):format(number and tostring(number) or "", mark, (r.text:gsub("\t", "  ")))
          color = r.kind == "add" and colors.green or (r.kind == "del" and colors.red or t.foreground)
        end
        buf:blit(D.x, D.y + i, text:sub(1, math.max(0, textW)), color, t.editorBackground)
      end
      if diffBar == 1 then
        scrollbar.draw(buf, t, D.x + D.w - 1, D.y + 1, rowsH, total, rowsH, self.diffScroll)
      end
    end

    -- Footer: Revert, then the diff mode switch
    buf:fill(1, h, w, 1, " ", hfg, hbg)
    self.footerHits = {}
    local item = self.list[self.selected]
    local x = 1
    local revertLabel = " Revert "
    local canRevert = item and not item.current
    buf:blit(x, h, revertLabel, canRevert and (t.menuForeground or hfg) or t.muted, hbg)
    if canRevert then self.footerHits[#self.footerHits + 1] = { x1 = x, x2 = x + #revertLabel - 1, action = revert } end
    x = x + #revertLabel + 1
    for _, m in ipairs(MODES) do
      local label, mode = m[1], m[2]
      if x + #label - 1 > w then break end
      local active = self.mode == mode
      buf:blit(x, h, label,
        active and (t.tabActiveForeground or t.accentForeground or hfg) or hfg,
        active and (t.tabActiveBackground or t.accent) or hbg)
      self.footerHits[#self.footerHits + 1] = { x1 = x, x2 = x + #label - 1, action = function() setMode(mode) end }
      x = x + #label
    end
    local hint = "Tab: switch  R: revert"
    if x + #hint + 2 <= w then buf:blit(w - #hint, h, hint, t.muted, hbg) end
  end

  canvas = host:addCanvas({
    x = 1, y = 1, width = function() return host.width end, height = function() return host.height end,
    background = ui:theme().editorBackground, draw = draw,
  })

  local function inside(r, x, y) return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

  canvas:onClick(function(_, _, x, y)
    local g = self.geo or geometry()
    if y == canvas.height then
      for _, hit in ipairs(self.footerHits or {}) do
        if x >= hit.x1 and x <= hit.x2 then hit.action() return end
      end
    elseif inside(g.list, x, y) then
      local index = self.listScroll + (y - g.list.y) + 1
      if self.list[index] then select(index) end
    end
  end)
  canvas:onScroll(function(_, dir, x, y)
    local g = self.geo or geometry()
    if x and y and inside(g.list, x, y) then
      self.listScroll = math.max(0, self.listScroll + dir)
    else
      self.diffScroll = math.max(0, self.diffScroll + dir * 2)
    end
    canvas:markRenderDirty()
  end)
  canvas:onKey(function(_, key)
    local g = self.geo or geometry()
    local page = math.max(1, g.diff.h - 2)
    if key == keys.up then select(self.selected - 1)
    elseif key == keys.down then select(self.selected + 1)
    elseif key == keys.pageUp then self.diffScroll = math.max(0, self.diffScroll - page); canvas:markRenderDirty()
    elseif key == keys.pageDown then self.diffScroll = self.diffScroll + page; canvas:markRenderDirty()
    elseif key == keys.tab then setMode(self.mode == "change" and "current" or "change")
    end
  end)
  canvas:onChar(function(_, ch)
    if ch == "r" or ch == "R" then revert() end
  end)

  recompute()

  function self.refresh()
    self.cache = {}
    recompute()
    canvas:markRenderDirty()
  end
  function self.setPath(path)
    self.path = path
    self.refresh()
  end
  function self.focus() canvas:focus() end
  function self.applyTheme() canvas.background = ui:theme().editorBackground; canvas:markRenderDirty() end
  function self.dispose()
    if self.onDispose then self.onDispose() end
    canvas:destroy()
  end
  return self
end

return M

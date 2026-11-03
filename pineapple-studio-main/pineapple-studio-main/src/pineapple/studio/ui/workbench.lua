
local disposable = require("pineapple.studio.core.disposable")
local commandsModule = require("pineapple.studio.core.commands")
local dialogs = require("pineapple.studio.ui.dialogs")
local themes = require("pineapple.studio.ui.theme")

local M = {}

local Workbench = {}
Workbench.__index = Workbench

local COMPACT_WIDTH = 40
local MENU_ORDER = { "Studio", "File", "Edit", "Selection", "View", "Go", "Run", "Help" }

function M.new(studio)
  local frame = studio.frame
  local self = setmetatable({
    studio = studio,
    frame = frame,
    theme = studio.theme,
    editors = {},
    active = nil,
    docks = {},
    panelList = {},
    statusItems = {},
    clipboard = "",
    _savedDockLayout = studio.settings:inspect("workbench.dockLayout", "user"),
    _tabOffset = 1,
    _tabHits = {},
    _nextId = 0,
    events = studio.events,
  }, Workbench)
  self:_build()
  self:layout()
  return self
end

local function settings(self) return self.studio.settings end
local function userSetting(self, key, fallback)
  local value = settings(self):inspect(key, "user")
  if value ~= nil then return value end
  return fallback
end
local function workspace(self) return self.studio.workspace end

function Workbench:_build()
  local theme, frame = self.theme, self.frame
  frame.background = theme.background

  self.menuBar = frame:addCanvas({
    x = 1, y = 1, height = 1, z = 10,
    background = theme.menuBackground,
    draw = function(_, buf) self:_drawMenuBar(buf) end,
  })
  self.menuBar:onClick(function(_, _, x) self:_clickMenuBar(x) end)
  self._menus = {}

  self.tabs = frame:addCanvas({
    y = 2, height = 1,
    background = theme.tabBackground,
    draw = function(_, buf) self:_drawTabs(buf) end,
  })
  self.tabs:onClick(function(_, btn, x) self:_clickTabs(btn, x) end)
  self.tabs:onDrag(function(_, _, x) self:_dragTab(x) end)
  self.tabs:onClickUp(function() self._tabDrag = nil end)
  self.tabs:onScroll(function(_, dir) self:cycleEditor(dir) end)

  self.editorArea = frame:addFrame({ y = 3, background = theme.editorBackground })
  self.welcome = self.editorArea:addCanvas({
    x = 1, y = 1,
    width = function() return self.editorArea.width end,
    height = function() return self.editorArea.height end,
    background = theme.editorBackground,
    draw = function(_, buf) self:_drawWelcome(buf) end,
  })
  self.welcome:onClick(function() end)

  self:_buildDocks()

  self.status = frame:addCanvas({
    x = 1, height = 1,
    background = theme.statusBackground,
    draw = function(_, buf) self:_drawStatus(buf) end,
  })

  self.toast = frame:addToast({ z = 800 })
end

local function handleColors(theme)
  return theme.handleBackground or theme.panelHeaderBackground,
    theme.handleForeground or theme.panelHeaderForeground
end
M.handleColors = handleColors

local DOCKS = { "left", "right", "bottom" }
local DOCK_NAMES = { left = "Left Side", right = "Right Side", bottom = "Bottom" }
local LOCATIONS = { sidebar = "left", left = "left", right = "right", bottom = "bottom" }
local MIN_SIDE = 3
local MENU_BUTTON = "\187"

local function openPanels(dock)
  local out = {}
  for _, p in ipairs(dock.panels) do if p.open then out[#out + 1] = p end end
  return out
end

local function showing(dock)
  return dock.expanded and (#openPanels(dock) > 0 or dock.showEmpty == true)
end

function Workbench:_buildDocks()
  local theme, frame = self.theme, self.frame
  for _, id in ipairs(DOCKS) do
    local dock = { id = id, panels = {}, active = nil, expanded = id ~= "bottom" }
    local side = id ~= "bottom"
    dock.container = frame:addFrame({
      background = side and theme.sidebarBackground or theme.panelBackground, visible = false, z = side and 5 or 4,
    })

    dock.header = dock.container:addCanvas({
      x = 1, y = 1, height = 1, z = 2,
      background = (handleColors(theme)),
      draw = function(_, buf) self:_drawDockHeader(dock, buf) end,
    })
    dock.header:onClick(function(_, btn, x) self:_clickDockHeader(dock, btn, x) end)

    dock.empty = dock.container:addCanvas({
      x = 1, y = 2, z = 1, visible = false,
      background = side and theme.sidebarBackground or theme.panelBackground,
      draw = function(_, buf) self:_drawEmptyDock(dock, buf) end,
    })
    dock.empty:onClick(function(_, _, x, y) self:_clickEmptyDock(dock, x, y) end)
    if side then

      dock.edge = frame:addCanvas({
        width = 1, z = 6, visible = false,
        background = (handleColors(theme)),
        draw = function(_, buf) self:_drawEdge(dock, buf) end,
      })
      dock.edge:onClick(function()
        self._drag = dock.id
        dock.edge:markRenderDirty()
      end)
    end
    self.docks[id] = dock
  end

  self.dropTarget = frame:addCanvas({
    z = 950, visible = false, width = 1, height = 1,
    draw = function(_, buf) self:_drawDropTarget(buf) end,
  })
end

function Workbench:isCompact()
  return self.frame.width < COMPACT_WIDTH
end

function Workbench:dockWidth(id)
  local key = id == "right" and "workbench.rightWidth" or "workbench.sidebarWidth"
  local w = (self._dragSize and self._dragSize.dock == id and self._dragSize.value)
    or userSetting(self, key, id == "right" and 24 or 16)
  if self:isCompact() then return math.min(self.frame.width, 22) end
  return math.max(MIN_SIDE, math.min(w, math.floor(self.frame.width / 2)))
end

function Workbench:sidebarWidth() return self:dockWidth("left") end

function Workbench:panelHeight()
  local h = self.frame.height
  local wanted = (self._dragSize and self._dragSize.dock == "bottom" and self._dragSize.value)
    or userSetting(self, "workbench.panelHeight", 8)
  if self:isCompact() then wanted = math.floor((h - 2) / 2) end
  return math.max(3, math.min(wanted, h - 5))
end

local STATUS_MIN_HEIGHT = 25
function Workbench:statusVisible()
  local mode = userSetting(self, "workbench.statusBar", "auto")
  if mode == "always" then return true end
  if mode == "never" then return false end
  return self.frame.height >= STATUS_MIN_HEIGHT
end

local function fitPanels(dock)
  local w, h = dock.container.width, math.max(1, dock.container.height - 1)
  local shown = showing(dock)
  for _, p in ipairs(dock.panels) do
    if p.frame then
      p.frame.x, p.frame.y = 1, 2
      p.frame.width, p.frame.height = w, h
      p.frame.visible = p == dock.active and shown
    end
  end
  dock.header.visible = true
  dock.header.width = w
  dock.empty.width, dock.empty.height = w, h
  dock.empty.visible = shown and #openPanels(dock) == 0
end

function Workbench:layout()
  local w, h = self.frame.width, self.frame.height
  local compact = self:isCompact()
  if self._compactKnown ~= compact then

    self._compactKnown = compact
    if compact then self.docks.left.expanded, self.docks.right.expanded = false, false end
  end
  local showStatus = self:statusVisible()
  local bottomEnd = showStatus and (h - 1) or h
  local bodyHeight = math.max(1, bottomEnd - 1)
  local x0, x1 = 1, w

  self.menuBar.width = w
  for _, id in ipairs({ "left", "right" }) do
    local dock = self.docks[id]
    local dw = self:dockWidth(id)
    local c, edge = dock.container, dock.edge
    c.y, c.height = 2, bodyHeight
    edge.y, edge.height = 2, bodyHeight
    c.visible, edge.visible = false, false
    if compact then

      c.visible = showing(dock)
      c.z = 500
      c.width = dw
      c.x = id == "left" and 1 or (w - dw + 1)
    else

      c.z = 5
      edge.visible = true
      if showing(dock) then
        c.visible, c.width = true, dw
        if id == "left" then
          c.x, edge.x = 1, dw + 1
          x0 = dw + 2
        else
          c.x, edge.x = w - dw + 1, w - dw
          x1 = w - dw - 1
        end
      else
        edge.x = id == "left" and 1 or w
        if id == "left" then x0 = 2 else x1 = w - 1 end
      end
    end
    fitPanels(dock)
  end

  local editorWidth = math.max(1, x1 - x0 + 1)
  local B = self.docks.bottom

  local bh = showing(B) and self:panelHeight() or 1
  B.container.visible = true
  B.container.x, B.container.y = x0, bottomEnd - bh + 1
  B.container.width, B.container.height = editorWidth, math.max(1, bh)
  fitPanels(B)
  self._editorBox = { x0 = x0, x1 = x1, bottomEnd = bottomEnd, bodyHeight = bodyHeight }

  self.tabs.x, self.tabs.width = x0, editorWidth
  self.editorArea.x, self.editorArea.y = x0, 3
  self.editorArea.width = editorWidth
  self.editorArea.height = math.max(1, bottomEnd - 2 - bh)
  for _, e in ipairs(self.editors) do
    e.host.width, e.host.height = self.editorArea.width, self.editorArea.height
    if e.instance and e.instance.resize then pcall(e.instance.resize, e.instance) end
  end

  self.status.visible = showStatus
  self.status.y, self.status.width = h, w
  for _, id in ipairs(DOCKS) do
    local d = self.docks[id]
    d.header:markRenderDirty()
    d.empty:markRenderDirty()
    if d.edge then d.edge:markRenderDirty() end
  end
  self.frame:markDirty()
end

function Workbench:_edgeHandleRow(dock)
  return math.max(1, math.floor(dock.edge.height / 2))
end

function Workbench:_drawEdge(dock, buf)
  local theme = self.theme
  local h = dock.edge.height
  local bg, grip = handleColors(theme)
  buf:fill(1, 1, 1, h, " ", grip, bg)
  local mid = self:_edgeHandleRow(dock)
  if self._drag == dock.id then grip = theme.accent end
  for row = math.max(1, mid - 1), math.min(h, mid + 1) do buf:blit(1, row, "\7", grip, bg) end
end

function Workbench:_drawDockHeader(dock, buf)
  local theme, w = self.theme, dock.header.width
  local bg, fg = handleColors(theme)
  buf:fill(1, 1, w, 1, " ", fg, bg)
  dock.hits = {}
  local x = 1
  local list = openPanels(dock)

  local room = w - 2 - (dock.id == "bottom" and 4 or 0)
  local total = 0
  for _, p in ipairs(list) do total = total + #p.title + 4 end

  local maxTitle, cramped
  if total > room and #list > 0 then
    cramped = true
    maxTitle = math.max(2, math.floor((room - 2 * #list - 2) / #list))
  end
  local shown = showing(dock)
  for _, p in ipairs(list) do
    local name = " " .. (maxTitle and p.title:sub(1, maxTitle) or p.title) .. " "
    local active = p == dock.active and shown
    local label = (cramped and not active) and name or (name .. "x ")
    if x + #name - 1 > w - 2 then break end
    local dragged = self._panelDrag and self._panelDrag.panel == p
    buf:blit(x, 1, label:sub(1, w - 2 - x + 1),
      (active or dragged) and theme.tabActiveForeground or fg, (active or dragged) and theme.tabActiveBackground or bg)
    dock.hits[#dock.hits + 1] = { from = x, to = x + #label - 1, close = #label > #name and x + #name or nil, panel = p }
    x = x + #label
  end
  if dock.id == "bottom" then

    local mid = math.floor(w / 2)
    local grip = self._drag == "bottom" and theme.accent or fg
    if mid - 1 > x and mid + 1 < w - 2 then buf:blit(mid - 1, 1, "\7\7\7", grip, bg) end
  end
  if w >= 3 then buf:blit(w - 1, 1, MENU_BUTTON, fg, bg) end
  self._bottomHits = self.docks.bottom.hits
end

function Workbench:_drawEmptyDock(dock, buf)
  local t = self.theme
  local w, h = dock.empty.width, dock.empty.height
  local bg = dock.id == "bottom" and t.panelBackground or t.sidebarBackground
  local fg = dock.id == "bottom" and (t.panelForeground or t.foreground) or t.sidebarForeground
  buf:fill(1, 1, w, h, " ", fg, bg)
  local lines = dialogs.wrap("No panel here. Drag a panel's tab onto this side, or:", math.max(4, w - 2))
  local y = math.max(1, math.floor((h - #lines - 2) / 2))
  for i, line in ipairs(lines) do
    buf:blit(math.max(1, math.floor((w - #line) / 2) + 1), y + i - 1, line, t.muted, bg)
  end
  local label = (" Open a panel "):sub(1, w)
  local bx, by = math.max(1, math.floor((w - #label) / 2) + 1), y + #lines + 1
  if by <= h then buf:blit(bx, by, label, t.accentForeground, t.accent) end
  dock.emptyButton = { x1 = bx, x2 = bx + #label - 1, y = by }
end

function Workbench:_clickEmptyDock(dock, x, y)
  local b = dock.emptyButton
  if b and y == b.y and x >= b.x1 and x <= b.x2 then
    local ax, ay = dock.empty:getAbsolutePosition()
    self:popupMenu(ax + b.x1 - 1, ay + b.y, self:_openPanelEntries(dock), function(e)
      if e and e.panel then self:_openPanelIn(e.panel, dock.id) end
    end)
  end
end

function Workbench:_openPanelEntries(dock)
  local out = {}
  for _, p in ipairs(self.panelList) do
    if not (p.dock == dock.id and p.open) then
      out[#out + 1] = { label = p.title, detail = p.dock ~= dock.id and DOCK_NAMES[p.dock] or nil, panel = p }
    end
  end
  if #out == 0 then out[1] = { label = "(every panel is here)", disabled = true } end
  return out
end

function Workbench:_openPanelIn(p, dockId)
  if p.dock ~= dockId then self:movePanel(p.id, dockId) else self:showPanel(p.id) end
end

function Workbench:_dockMenu(dock, x, y, panel)
  panel = panel or (showing(dock) and dock.active) or nil
  local entries = {}
  if panel then
    local moves = {}
    for _, id in ipairs(DOCKS) do
      if id ~= panel.dock then moves[#moves + 1] = { label = DOCK_NAMES[id], dock = id, panel = panel } end
    end
    entries[#entries + 1] = { label = "Move " .. panel.title .. " to", children = moves }
    entries[#entries + 1] = { label = "Close " .. panel.title, close = panel }
    entries[#entries + 1] = { separator = true }
  end
  entries[#entries + 1] = { label = "Open Panel Here", children = self:_openPanelEntries(dock), openHere = true }
  if showing(dock) then entries[#entries + 1] = { label = "Hide", hide = true }
  else entries[#entries + 1] = { label = "Show", show = true } end
  self:popupMenu(x, y, entries, function(e)
    if not e then return end
    if e.dock then self:movePanel(e.panel.id, e.dock)
    elseif e.close then self:closePanel(e.close.id)
    elseif e.panel then self:_openPanelIn(e.panel, dock.id)
    elseif e.hide then self:toggleDock(dock.id, false)
    elseif e.show then self:toggleDock(dock.id, true) end
  end)
end

function Workbench:_panelMenu(p, x, y) self:_dockMenu(self.docks[p.dock], x, y, p) end

function Workbench:_clickDockHeader(dock, btn, x)
  local w = dock.header.width
  local ax, ay = dock.header:getAbsolutePosition()
  if x >= w - 2 then
    self:_dockMenu(dock, ax + w - 2, ay + 1)
    return
  end
  for _, hit in ipairs(dock.hits or {}) do
    if x >= hit.from and x <= hit.to then
      if btn == 2 then
        self:_dockMenu(dock, ax + x - 1, ay + 1, hit.panel)
      elseif x == hit.close then
        self:closePanel(hit.panel.id)
      else
        self:showPanel(hit.panel.id)

        self._tabPress = { panel = hit.panel, x = ax + x - 1, y = ay }
      end
      return
    end
  end
  if dock.id == "bottom" then
    self._drag = "bottom"
    dock.header:markRenderDirty()
  elseif not showing(dock) then
    self:toggleDock(dock.id, true)
  end
end

function Workbench:_dropDockAt(x, y)
  local w = self.frame.width
  local box = self._editorBox
  if not box or y < 2 then return nil end
  local zone = math.max(3, math.floor(w / 5))
  if x <= zone then return "left" end
  if x > w - zone then return "right" end
  if y > box.bottomEnd - math.max(2, math.floor(box.bodyHeight / 3)) then return "bottom" end
  return nil
end

function Workbench:_dockArea(id)
  local w = self.frame.width
  local box = self._editorBox
  local zone = math.max(3, math.floor(w / 5))
  if id == "left" then return 1, 2, zone, box.bodyHeight end
  if id == "right" then return w - zone + 1, 2, zone, box.bodyHeight end
  local hh = math.max(2, math.floor(box.bodyHeight / 3))
  return box.x0, box.bottomEnd - hh + 1, box.x1 - box.x0 + 1, hh
end

function Workbench:_drawDropTarget(buf)
  local t = self.theme
  local d = self._panelDrag
  local c = self.dropTarget
  if not d or not d.target then return end
  buf:fill(1, 1, c.width, c.height, " ", t.accentForeground, t.accent)
  local text = ("Move " .. d.panel.title .. " here"):sub(1, c.width)
  buf:blit(math.max(1, math.floor((c.width - #text) / 2) + 1), math.max(1, math.floor(c.height / 2)), text,
    t.accentForeground, t.accent)
end

function Workbench:handlePointer(event, btn, x, y)
  if event ~= "mouse_drag" and event ~= "mouse_up" then return false end
  local capture = self._pointerCapture
  if capture then
    if event == "mouse_up" then self._pointerCapture = nil end
    local ok, err = pcall(capture, event, btn, x, y)
    if not ok then self:notify(tostring(err), "error") end
    return true
  end
  if self._drag then
    if event == "mouse_drag" then
      local dock = self.docks[self._drag]
      if dock.id == "bottom" then self:_dragDock(dock, nil, y) else self:_dragDock(dock, x, nil) end
    else
      self:_endDrag()
    end
    return true
  end
  local press = self._tabPress
  if press then
    if event == "mouse_drag" then
      if not self._panelDrag and math.abs(x - press.x) + math.abs(y - press.y) < 2 then return true end
      local target = self:_dropDockAt(x, y)
      if target == press.panel.dock then target = nil end
      self._panelDrag = { panel = press.panel, target = target }
      local c = self.dropTarget
      if target then
        local ax, ay, aw, ah = self:_dockArea(target)
        c.x, c.y, c.width, c.height = ax, ay, aw, ah
        c.visible = true
      else
        c.visible = false
      end
      c:markRenderDirty()
      self.frame:markDirty()
    else
      local d = self._panelDrag
      self._tabPress, self._panelDrag = nil, nil
      self.dropTarget.visible = false
      if d and d.target then self:movePanel(d.panel.id, d.target) end
      self:layout()
    end
    return true
  end
  return false
end

function Workbench:capturePointer(fn)
  self._pointerCapture = fn
end

function Workbench:_dragDock(dock, absX, absY)
  local w, h = self.frame.width, self.frame.height
  local function open()
    if not dock.expanded or not showing(dock) then
      dock.expanded = true

      if #openPanels(dock) == 0 then dock.showEmpty = true end
    end
  end
  if dock.id == "bottom" then
    local bottomEnd = self:statusVisible() and (h - 1) or h
    local size = bottomEnd - absY + 1
    if size < 3 then

      dock.expanded = false
      self._dragSize = nil
    else
      open()
      self._dragSize = { dock = "bottom", value = math.min(size, h - 5) }
    end
  else
    local size = dock.id == "left" and (absX - 1) or (w - absX)
    if size <= 1 then
      dock.expanded = false
      self._dragSize = nil
    else
      open()
      self._dragSize = { dock = dock.id, value = math.max(MIN_SIDE, math.min(size, math.floor(w / 2))) }
    end
  end
  self:layout()
end

function Workbench:_endDrag()
  local d = self._dragSize
  if d then
    local key = ({ left = "workbench.sidebarWidth", right = "workbench.rightWidth", bottom = "workbench.panelHeight" })[d.dock]
    pcall(settings(self).set, settings(self), key, d.value)
    self._dragSize = nil
  end
  self._drag = nil
  self:_saveDockLayout()
  self:layout()
end

function Workbench:_savedPanelOpen(id)
  local saved = self._savedDockLayout
  if type(saved) ~= "table" or type(saved.docks) ~= "table" then return nil, false end
  for _, dock in pairs(saved.docks) do
    if type(dock) == "table" and type(dock.open) == "table" and dock.open[id] ~= nil then
      return dock.open[id] == true, true
    end
  end
  return nil, false
end

function Workbench:restoreDockLayout()
  local saved = self._savedDockLayout
  if type(saved) ~= "table" or type(saved.docks) ~= "table" then return end

  for _, id in ipairs(DOCKS) do
    local dock, state = self.docks[id], saved.docks[id]
    if type(state) == "table" then
      local ordered, placed = {}, {}
      for _, panelId in ipairs(type(state.panels) == "table" and state.panels or {}) do
        local panel = self:findPanel(panelId)
        if panel and panel.dock == id and not placed[panel] then
          ordered[#ordered + 1], placed[panel] = panel, true
        end
      end
      for _, panel in ipairs(dock.panels) do
        if not placed[panel] then ordered[#ordered + 1] = panel end
      end
      dock.panels = ordered

      if type(state.expanded) == "boolean" then dock.expanded = state.expanded end
      local active = state.active and self:findPanel(state.active)
      if active and active.dock == id and active.open then dock.active = active
      elseif type(state.open) == "table" then dock.active = nil end
      dock.showEmpty = dock.expanded and #openPanels(dock) == 0
    end
  end
  self:layout()
end

function Workbench:_saveDockLayout()
  local saved = { version = 1, docks = {} }
  for _, id in ipairs(DOCKS) do
    local dock = self.docks[id]
    local state = { panels = {}, open = {}, expanded = dock.expanded == true }
    for _, panel in ipairs(dock.panels) do
      state.panels[#state.panels + 1] = panel.id
      state.open[panel.id] = panel.open == true
    end
    if dock.active and dock.active.open then state.active = dock.active.id end
    saved.docks[id] = state
  end
  self._savedDockLayout = saved
  pcall(settings(self).set, settings(self), "workbench.dockLayout", saved)
end

function Workbench:toggleDock(id, force)
  local dock = self.docks[id]
  if not dock then return end
  if force == nil then force = not showing(dock) end
  dock.expanded = force
  if force and #openPanels(dock) == 0 then dock.showEmpty = true end
  if not force then dock.showEmpty = false end
  self:_saveDockLayout()
  self:layout()
  if force and dock.active and dock.active.instance and dock.active.instance.focus then
    pcall(dock.active.instance.focus, dock.active.instance)
  elseif not force and self.active then
    self.active.instance:focus()
  end
end

function Workbench:toggleSidebar(force) self:toggleDock("left", force) end
function Workbench:togglePanel(force) self:toggleDock("bottom", force) end

function Workbench:closePanel(id)
  local target = self:findPanel(id)
  if not target or not target.open then return end
  local dock = self.docks[target.dock]
  target.open = false
  if target.instance and target.instance.dispose then pcall(target.instance.dispose, target.instance) end
  if target.frame then target.frame:destroy() end
  target.frame, target.instance = nil, nil
  if dock.active == target then
    dock.active = nil
    local remaining = openPanels(dock)
    if #remaining > 0 then
      self:showPanel(remaining[#remaining].id, true)
    else
      dock.showEmpty = true
      if self.active then self.active.instance:focus() end
    end
  end
  self:_saveDockLayout()
  self:layout()
end

function Workbench:movePanel(id, dockId)
  local p = self:findPanel(id)
  dockId = LOCATIONS[dockId]
  if not p or not dockId or p.dock == dockId then return false end
  self:closePanel(id)
  local from = self.docks[p.dock]
  for i = #from.panels, 1, -1 do if from.panels[i] == p then table.remove(from.panels, i) end end
  p.dock = dockId
  local to = self.docks[dockId]
  to.panels[#to.panels + 1] = p
  local saved = {}
  for k, v in pairs(userSetting(self, "workbench.panelLocations", {}) or {}) do saved[k] = v end
  saved[id] = dockId ~= p.home and dockId or nil
  pcall(settings(self).set, settings(self), "workbench.panelLocations", saved)
  self:showPanel(id)
  return true
end

function Workbench:chooseOpenPanel()
  local items = {}
  for _, p in ipairs(self.panelList) do
    items[#items + 1] = { label = p.title, detail = DOCK_NAMES[p.dock] .. (p.open and "" or " (closed)"), panel = p }
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  self:quickPick(items, { title = "Open Panel", placeholder = "Panel to show" }, function(item)
    if item then self:showPanel(item.panel.id) end
  end)
end

function Workbench:chooseMovePanel()
  local items = {}
  for _, p in ipairs(self.panelList) do
    items[#items + 1] = { label = p.title, detail = DOCK_NAMES[p.dock], panel = p }
  end
  self:quickPick(items, { title = "Move Panel", placeholder = "Panel to move" }, function(item)
    if not item then return end
    local choices = {}
    for _, id in ipairs(DOCKS) do
      if id ~= item.panel.dock then choices[#choices + 1] = { label = DOCK_NAMES[id], dock = id } end
    end
    self:quickPick(choices, { title = item.panel.title, placeholder = "Move to" }, function(c)
      if c then self:movePanel(item.panel.id, c.dock) end
    end)
  end)
end

function Workbench:rebuildMenus()
  local commands, keybindings = self.studio.commands, self.studio.keybindings
  local byMenu, names = {}, {}
  for index, entry in ipairs(self.studio.plugins.menus) do
    -- Names with a "/" (such as "explorer/context") are context menus owned by a view,
    -- not menu bar entries.
    if commands:has(entry.command) and not entry.menu:find("/", 1, true) then
      if not byMenu[entry.menu] then byMenu[entry.menu] = {}; names[#names + 1] = entry.menu end
      table.insert(byMenu[entry.menu], { entry = entry, index = index })
    end
  end

  for name, list in pairs(byMenu) do
    table.sort(list, function(a, b)
      local ga, gb = a.entry.group or "5", b.entry.group or "5"
      if ga ~= gb then return ga < gb end
      return a.index < b.index
    end)
    for i, item in ipairs(list) do list[i] = item.entry end
    byMenu[name] = list
  end
  local rank = {}
  for i, n in ipairs(MENU_ORDER) do rank[n] = i end
  table.sort(names, function(a, b)
    local ra, rb = rank[a] or 100, rank[b] or 100
    if ra ~= rb then return ra < rb end
    return a < b
  end)

  local menus = {}
  for _, name in ipairs(names) do
    local entries, lastGroup = {}, nil
    for _, e in ipairs(byMenu[name]) do
      if lastGroup ~= nil and (e.group or "") ~= lastGroup then
        entries[#entries + 1] = { separator = true }
      end
      lastGroup = e.group or ""
      local cmd = commands:get(e.command)
      local chord = keybindings:chordFor(e.command)
      entries[#entries + 1] = {
        label = cmd.title or cmd.id,
        detail = chord and M.shortChord(chord) or nil,
        command = e.command,
      }
    end
    menus[#menus + 1] = { name = name, entries = entries }
  end
  self._menus = menus
  self.menuBar:markRenderDirty()
end

function Workbench:_menuSpans()
  local spans, x = {}, 1
  local compact = self:isCompact()
  local gap = compact and 0 or 1
  for i, m in ipairs(self._menus) do

    local label = compact and (" " .. m.name) or (" " .. m.name .. " ")
    spans[i] = { x, x + #label - 1, label }
    x = x + #label + gap
  end
  return spans
end

function Workbench:_drawMenuBar(buf)
  local theme, w = self.theme, self.menuBar.width
  buf:fill(1, 1, w, 1, " ", theme.menuForeground, theme.menuBackground)
  local spans = self:_menuSpans()
  local used = 0
  for i, span in ipairs(spans) do
    local open = self._openMenu == i
    buf:blit(span[1], 1, span[3],
      open and theme.menuActiveForeground or theme.menuForeground,
      open and theme.menuActiveBackground or theme.menuBackground)
    used = span[2]
  end
end

function Workbench:_menuIndexAt(x)
  for i, span in ipairs(self:_menuSpans()) do
    if x >= span[1] and x <= span[2] then return i end
  end
  return nil
end

function Workbench:_clickMenuBar(x)
  local index = self:_menuIndexAt(x)
  if index then self:openMenu(index) end
end

function Workbench:openMenu(index)
  local menu = self._menus[index]
  if not menu then return end
  local span = self:_menuSpans()[index]
  self._openMenu = index
  self.menuBar:markRenderDirty()
  local count = #self._menus
  self._menuPopup = dialogs.menu(self.frame, self.theme, span[1], 2, menu.entries, {
    onOutside = function(x, y)
      local other = y == 1 and self:_menuIndexAt(x)
      if other and other ~= index then self:openMenu(other) end
    end,
    onLeft = function() self:openMenu(((index - 2) % count) + 1) end,
    onRight = function() self:openMenu((index % count) + 1) end,
  }, function(entry)
    if self._openMenu == index then self._openMenu = nil end
    self.menuBar:markRenderDirty()
    if entry and entry.command then self:runCommand(entry.command) end
  end)
  return self._menuPopup
end

local KEY_SYMBOLS = { comma = ",", period = ".", grave = "`", slash = "/", minus = "-", equals = "=" }

function M.shortChord(chord)
  local out = chord:gsub("ctrl%+", "^"):gsub("alt%+", "Alt+"):gsub("shift%+", "Shift+")
  return (out:gsub("([%w]+)$", function(k)
    if KEY_SYMBOLS[k] then return KEY_SYMBOLS[k] end
    return #k == 1 and k:upper() or (k:sub(1, 1):upper() .. k:sub(2))
  end))
end

function Workbench:runCommand(id, ...)
  local ok, err = pcall(self.studio.commands.execute, self.studio.commands, id, ...)
  if not ok then self:notify(tostring(err), "error") end
end

function Workbench:setTheme(id)
  local loaded = themes.load(id, self.studio.basalt)
  themes.applyInto(self.theme, loaded)
  local t = self.theme
  self.frame.background = t.background
  self.menuBar.background = t.menuBackground
  for _, id in ipairs(DOCKS) do
    local d = self.docks[id]
    d.container.background = id == "bottom" and t.panelBackground or t.sidebarBackground
    d.header.background = handleColors(t)
    d.empty.background = id == "bottom" and t.panelBackground or t.sidebarBackground
    if d.edge then d.edge.background = (handleColors(t)) end
    for _, p in ipairs(d.panels) do
      if p.frame then p.frame.background = id == "bottom" and t.panelBackground or t.sidebarBackground end
    end
  end
  self.tabs.background = t.tabBackground
  self.editorArea.background = t.editorBackground
  self.welcome.background = t.editorBackground
  self.status.background = t.statusBackground

  for _, e in ipairs(self.editors) do
    e.host.background = t.editorBackground
    if e.instance.applyTheme then pcall(e.instance.applyTheme, e.instance, t) end
  end
  self.events:emit("themeChanged", t)
  self.frame:markDirty()
end

function Workbench:addPanel(panel)
  if type(panel) ~= "table" or type(panel.id) ~= "string" or type(panel.create) ~= "function" then
    error("addPanel expects { id, title, create }", 2)
  end
  local home = LOCATIONS[panel.location or "left"] or "left"
  local saved = (userSetting(self, "workbench.panelLocations", {}) or {})[panel.id]
  local record = {
    id = panel.id, title = panel.title or panel.id, create = panel.create,
    home = home, dock = LOCATIONS[saved or home] or home, order = panel.order or 100,
  }
  local dock = self.docks[record.dock]

  local index = #dock.panels + 1
  for i, p in ipairs(dock.panels) do
    if record.order < p.order then index = i; break end
  end
  table.insert(dock.panels, index, record)
  self.panelList[#self.panelList + 1] = record
  local savedOpen, hasSavedOpen = self:_savedPanelOpen(record.id)
  local openByDefault = panel.openByDefault ~= false
  if hasSavedOpen then
    if savedOpen then self:showPanel(record.id, true) end
  elseif record.dock ~= "bottom" and (saved or (openByDefault and home ~= "bottom")) and not dock.active then
    self:showPanel(record.id, true)
  end
  self:layout()
  return disposable.new(function()
    local d = self.docks[record.dock]
    for i = #d.panels, 1, -1 do if d.panels[i] == record then table.remove(d.panels, i) end end
    for i = #self.panelList, 1, -1 do if self.panelList[i] == record then table.remove(self.panelList, i) end end
    if record.instance and record.instance.dispose then pcall(record.instance.dispose, record.instance) end
    if record.frame then record.frame:destroy() end
    record.open = false
    if d.active == record then
      d.active = nil
      local remaining = openPanels(d)
      if remaining[1] then self:showPanel(remaining[1].id, true) end
    end
    self:layout()
  end)
end

function Workbench:findPanel(id)
  for _, p in ipairs(self.panelList) do if p.id == id then return p end end
end
local function findPanel(self, id) return self:findPanel(id) end

function Workbench:showPanel(id, noFocus)
  local target = self:findPanel(id)
  if not target then return false end
  local dock = self.docks[target.dock]
  if not noFocus then dock.expanded = true end
  target.open = true
  dock.active = target

  self:layout()
  dock.showEmpty = false
  if not target.frame then
    target.frame = dock.container:addFrame({
      x = 1, y = 2, width = dock.container.width, height = math.max(1, dock.container.height - 1),
      background = dock.id == "bottom" and self.theme.panelBackground or self.theme.sidebarBackground,
    })
    local ok, inst = pcall(target.create, target.frame, self.studio)
    if ok then target.instance = inst
    else
      local frame = target.frame
      target.frame, target.instance = nil, nil
      if frame then frame:destroy() end
      self:layout()
      local message = "Panel " .. target.id .. ": " .. tostring(inst)
      self:notify(message, "error")
      return false, message
    end
    self:layout()
  end
  if not noFocus and target.instance and target.instance.focus then pcall(target.instance.focus, target.instance) end
  if not noFocus then self:_saveDockLayout() end
  return true
end

function Workbench:dockState(id)
  local d = self.docks[id]
  return d.active, d.expanded and #openPanels(d) > 0
end

function Workbench:dockShowing(id) return showing(self.docks[id]) end

function Workbench:addStatusItem(item)
  self.statusItems[#self.statusItems + 1] = item
  table.sort(self.statusItems, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
  self.status:markRenderDirty()
  return disposable.new(function()
    for i = #self.statusItems, 1, -1 do
      if self.statusItems[i] == item then table.remove(self.statusItems, i) end
    end
    self.status:markRenderDirty()
  end)
end

function Workbench:refreshStatus()
  self.status:markRenderDirty()
end

function Workbench:screenBuffer()
  local render = self.frame and rawget(self.frame, "_render")
  if not render then return nil, "Basalt has not rendered the Studio screen yet." end

  local used = {}
  for y = 1, render.height do
    local fg, bg = render.fg[y] or "", render.bg[y] or ""
    for i = 1, #fg do used[fg:byte(i)] = true end
    for i = 1, #bg do used[bg:byte(i)] = true end
  end
  local colors = render.mapper and render.mapper:build(used) or nil
  local lines = {}
  for y = 1, render.height do
    local text, fg, bg = render.text[y] or "", render.fg[y] or "", render.bg[y] or ""
    if colors then
      fg, bg = fg:gsub(".", colors), bg:gsub(".", colors)
    else
      local function hex(line)
        return (line:gsub(".", function(char) return ("%x"):format(char:byte() % 16) end))
      end
      fg, bg = hex(fg), hex(bg)
    end
    text = text:gsub(".", function(char)
      local byte = char:byte()
      if byte < 32 or byte > 126 then return ("\\x%02X"):format(byte) end
      return char
    end)
    lines[y] = { text = text, foreground = fg, background = bg }
  end
  return {
    width = render.width, height = render.height, lines = lines,
    cursor = { x = render.cursorX, y = render.cursorY, visible = render.cursorBlink == true },
  }
end

function Workbench:_drawStatus(buf)
  local theme, w = self.theme, self.status.width
  local left, right = {}, {}
  if self.active then
    local name = self.active.doc.virtual and self.active.doc.title or workspace(self):relative(self.active.doc.path)
    if self.active.doc.readOnly then name = name .. " [read-only]" end
    left[#left + 1] = name
  end
  for _, item in ipairs(self.statusItems) do
    local ok, text = pcall(item.text)
    if ok and text and text ~= "" then
      if item.align == "left" then left[#left + 1] = text else right[#right + 1] = text end
    end
  end
  local r = table.concat(right, "  ")
  local l = table.concat(left, "  ")
  local room = w - #r - 3
  if #l > room then l = l:sub(1, math.max(0, room - 1)) .. (room > 1 and "~" or "") end
  local line = " " .. l .. string.rep(" ", math.max(0, w - #l - #r - 2)) .. r .. " "
  buf:blit(1, 1, line:sub(1, w), theme.statusForeground, theme.statusBackground)
end

function Workbench:notify(message, kind, seconds)
  kind = kind or "info"
  local fn = self.toast[kind] or self.toast.show
  fn(self.toast, tostring(message), seconds)
end

function Workbench:choose(opts, callback)
  return dialogs.choose(self.frame, self.theme, opts, callback)
end

function Workbench:prompt(opts, callback)
  return dialogs.prompt(self.frame, self.theme, opts, callback)
end

function Workbench:popupMenu(x, y, entries, callback)
  return dialogs.menu(self.frame, self.theme, x, y, entries, {}, callback)
end

function Workbench:quickPick(items, opts, callback)
  return dialogs.quickPick(self.frame, self.theme, items, opts, callback)
end

local function displayName(self, editor)
  if editor.doc.virtual then return editor.doc.title end
  local name = fs.getName(editor.doc.path)

  for _, other in ipairs(self.editors) do
    if other ~= editor and not other.doc.virtual and fs.getName(other.doc.path) == name then
      return fs.getName(fs.getDir(editor.doc.path)) .. "/" .. name
    end
  end
  return name
end

function Workbench:findEditor(path, providerId)
  if not path:match("^%a+://") then path = workspace(self):path(path) end
  for _, e in ipairs(self.editors) do
    if e.doc.path == path and (not providerId or e.provider.id == providerId) then return e end
  end
  return nil
end

function Workbench:openFile(path, providerId)
  local ws = workspace(self)
  local abs = ws:path(path)
  if fs.isDir(abs) then return nil, abs .. " is a folder" end
  local existing = self:findEditor(abs, providerId)
  if existing then self:activate(existing); return existing end

  self.studio.plugins:fire("onOpen", abs)
  local provider
  if providerId then
    provider = self.studio.editors:get(providerId)
  else
    provider = self.studio.editors:resolve(abs)
  end
  if not provider then
    local msg = "No editor can open " .. fs.getName(abs)
    self:notify(msg, "warning")
    return nil, msg
  end

  local doc, err = ws:openDocument(abs)
  if not doc then self:notify(err, "error") return nil, err end

  self._nextId = self._nextId + 1
  local host = self.editorArea:addFrame({
    x = 1, y = 1, width = self.editorArea.width, height = self.editorArea.height,
    background = self.theme.editorBackground, visible = false,
  })
  local ok, instance = pcall(provider.create, host, doc, {
    theme = self.theme, settings = self.studio.settings, workbench = self, studio = self.studio,
  })
  if not ok or type(instance) ~= "table" then
    host:destroy()
    ws:closeDocument(doc)
    local msg = provider.id .. ": " .. tostring(instance)
    self:notify(msg, "error")
    return nil, msg
  end

  local editor = { id = self._nextId, doc = doc, provider = provider, host = host, instance = instance }
  editor.store = disposable.store()
  editor.store:add(doc:on("dirty", function()
    self.tabs:markRenderDirty(); self.status:markRenderDirty()
  end))
  editor.store:add(doc:on("rename", function()
    self.tabs:markRenderDirty(); self.status:markRenderDirty()
  end))
  local state = ws:getViewState(abs)
  if state and instance.setViewState then pcall(instance.setViewState, instance, state) end

  local index = #self.editors + 1
  if self.active then
    for i, e in ipairs(self.editors) do if e == self.active then index = i + 1 end end
  end
  table.insert(self.editors, index, editor)
  self:activate(editor)
  self.events:emit("editorOpened", editor)
  return editor
end

function Workbench:openView(spec)
  local path = "studio://" .. spec.id
  local existing = self:findEditor(path)
  if existing then self:activate(existing); return existing end
  local doc = {
    path = path, title = spec.title or spec.id, virtual = true, lines = {},
    isDirty = function() return false end,
    save = function() return true end,
    revert = function() end,
    on = function() return disposable.new(function() end) end,
  }
  self._nextId = self._nextId + 1
  local host = self.editorArea:addFrame({
    x = 1, y = 1, width = self.editorArea.width, height = self.editorArea.height,
    background = self.theme.editorBackground, visible = false,
  })
  local ok, instance = pcall(spec.create, host, {
    theme = self.theme, settings = self.studio.settings, workbench = self, studio = self.studio,
  })
  if not ok or type(instance) ~= "table" then
    host:destroy()
    self:notify(spec.id .. ": " .. tostring(instance), "error")
    return nil, instance
  end
  local editor = { id = self._nextId, doc = doc, provider = { id = "studio." .. spec.id }, host = host,
    instance = instance, store = disposable.store() }
  local index = #self.editors + 1
  if self.active then
    for i, e in ipairs(self.editors) do if e == self.active then index = i + 1 end end
  end
  table.insert(self.editors, index, editor)
  self:activate(editor)
  self.events:emit("editorOpened", editor)
  return editor
end

local function isInside(element, container)
  local e = element
  while e do
    if e == container then return true end
    e = rawget(e, "parent")
  end
  return false
end

function Workbench:matchesContext(expr)
  local providerId = expr:match("^activeEditor:(.+)$")
  if providerId then return self.active ~= nil and self.active.provider.id == providerId end
  local focused = self.frame.getFocused and self.frame:getFocused()
  if not focused then return false end
  local panelId = expr:match("^panelFocus:(.+)$")
  if panelId then
    local p = findPanel(self, panelId)
    return p ~= nil and p.frame ~= nil and isInside(focused, p.frame)
  end
  if expr == "editorFocus" then return isInside(focused, self.editorArea) end
  return false
end

function Workbench:activate(editor)
  if self.active and self.active ~= editor then self:_saveViewState(self.active) end
  for _, e in ipairs(self.editors) do e.host.visible = (e == editor) end
  self.active = editor
  self.welcome.visible = editor == nil
  if editor then
    if editor.instance.focus then pcall(editor.instance.focus, editor.instance) end
  end
  self.tabs:markRenderDirty()
  self.status:markRenderDirty()
  self.events:emit("activeEditorChanged", editor)
end

function Workbench:activeEditor()
  return self.active
end

function Workbench:getClipboard()
  return self.clipboard
end

function Workbench:setClipboard(text)
  self.clipboard = tostring(text or "")
  return self.clipboard
end

function Workbench:_saveViewState(editor)
  if editor.doc.virtual then return end
  if editor.instance.getViewState then
    local ok, state = pcall(editor.instance.getViewState, editor.instance)
    if ok and state then workspace(self):setViewState(editor.doc.path, state) end
  end
end

local function disposeEditor(self, editor)
  self:_saveViewState(editor)
  pcall(editor.store.dispose, editor.store)
  if editor.instance.dispose then pcall(editor.instance.dispose, editor.instance) end
  editor.host:destroy()
  if not editor.doc.virtual then workspace(self):closeDocument(editor.doc) end
  local index
  for i, e in ipairs(self.editors) do if e == editor then index = i end end
  if index then table.remove(self.editors, index) end
  if self.active == editor then
    self.active = nil
    local nextEditor = self.editors[math.min(index or 1, #self.editors)]
    self:activate(nextEditor)
  else
    self.tabs:markRenderDirty()
  end
  self.events:emit("editorClosed", editor)
end

local function otherEditorsOn(self, editor)
  for _, e in ipairs(self.editors) do
    if e ~= editor and e.doc == editor.doc then return true end
  end
  return false
end

function Workbench:closeEditor(editor, callback)
  editor = editor or self.active
  if not editor then if callback then callback(false) end return end
  if not editor.doc:isDirty() or otherEditorsOn(self, editor) then
    disposeEditor(self, editor)
    if callback then callback(true) end
    return
  end
  self:activate(editor)
  self:choose({
    title = "Unsaved changes",
    message = "Save changes to " .. fs.getName(editor.doc.path) .. "?",
    buttons = { "Save", "Don't Save", "Cancel" }, default = 1, cancel = 3,
  }, function(choice)
    if choice == 1 then
      local ok, err = editor.doc:save()
      if not ok then self:notify(err, "error"); if callback then callback(false) end return end
      disposeEditor(self, editor)
      if callback then callback(true) end
    elseif choice == 2 then
      editor.doc:revert()
      disposeEditor(self, editor)
      if callback then callback(true) end
    elseif callback then
      callback(false)
    end
  end)
end

function Workbench:closeAll(callback)
  local list = {}
  for i, e in ipairs(self.editors) do list[i] = e end
  self:closeEditors(list, callback)
end

function Workbench:closeEditors(list, callback)
  local i = #list + 1
  local function step()
    i = i - 1
    local e = list[i]
    if not e then if callback then callback(true) end return end
    self:closeEditor(e, function(closed)
      if closed then step() elseif callback then callback(false) end
    end)
  end
  step()
end

function Workbench:editorsAround(editor, which)
  local index
  for i, e in ipairs(self.editors) do if e == editor then index = i end end
  local out = {}
  if not index then return out end
  for i, e in ipairs(self.editors) do
    if (which == "others" and i ~= index) or (which == "left" and i < index) or (which == "right" and i > index) then
      out[#out + 1] = e
    end
  end
  return out
end

function Workbench:_tabMenu(editor, x, y)
  local left, right = self:editorsAround(editor, "left"), self:editorsAround(editor, "right")
  local chord = self.studio.keybindings:chordFor("file.close")
  local entries = {
    { label = "Close", detail = chord and M.shortChord(chord) or nil, act = function() self:closeEditor(editor) end },
    { label = "Close Others", disabled = #self.editors < 2,
      act = function() self:closeEditors(self:editorsAround(editor, "others")) end },
    { label = "Close All", act = function() self:closeAll() end },
    { separator = true },
    { label = "Close All to the Left", disabled = #left == 0, act = function() self:closeEditors(left) end },
    { label = "Close All to the Right", disabled = #right == 0, act = function() self:closeEditors(right) end },
  }
  self:popupMenu(x, y, entries, function(entry) if entry and entry.act then entry.act() end end)
end

function Workbench:cycleEditor(delta)
  if #self.editors < 2 or not self.active then return end
  local index = 1
  for i, e in ipairs(self.editors) do if e == self.active then index = i end end
  index = ((index - 1 + delta) % #self.editors) + 1
  self:activate(self.editors[index])
end

function Workbench:saveSession()
  local ws = workspace(self)
  local paths = {}
  for _, e in ipairs(self.editors) do
    if not e.doc.virtual then
      self:_saveViewState(e)
      paths[#paths + 1] = ws:relative(e.doc.path)
    end
  end
  ws:setState("openEditors", paths)
  local active = self.active and not self.active.doc.virtual and self.active
  ws:setState("activeEditor", active and ws:relative(active.doc.path) or nil)
  self:_saveDockLayout()
end

function Workbench:restoreSession()
  local ws = workspace(self)
  local paths = ws:getState("openEditors")
  if type(paths) ~= "table" then return end
  for _, p in ipairs(paths) do
    if ws:exists(p) then self:openFile(p) end
  end
  local active = ws:getState("activeEditor")
  local e = active and self:findEditor(active)
  if e then self:activate(e) end
end

function Workbench:_drawTabs(buf)
  local theme, w = self.theme, self.tabs.width
  buf:fill(1, 1, w, 1, " ", theme.tabForeground, theme.tabBackground)

  local widths = {}
  for i, e in ipairs(self.editors) do widths[i] = #displayName(self, e) + 4 end
  local activeIndex = 1
  for i, e in ipairs(self.editors) do if e == self.active then activeIndex = i end end
  self._tabOffset = math.max(1, math.min(self._tabOffset, #self.editors))
  if activeIndex < self._tabOffset then self._tabOffset = activeIndex end
  while #self.editors > 0 do
    local used = 0
    for i = self._tabOffset, activeIndex do used = used + (widths[i] or 0) end
    if used <= w or self._tabOffset >= activeIndex then break end
    self._tabOffset = self._tabOffset + 1
  end

  self._tabHits = {}
  local x = 1
  if self._tabOffset > 1 then
    buf:blit(1, 1, "<", theme.tabForeground, theme.tabBackground)
    x = 2
  end
  for i = self._tabOffset, #self.editors do
    local e = self.editors[i]
    if x > w then break end
    local active = e == self.active
    local name = displayName(self, e)
    local mark = e.doc:isDirty() and "*" or "x"
    local text = " " .. name .. " " .. mark .. " "
    local fg = active and theme.tabActiveForeground or theme.tabForeground
    local bg = active and theme.tabActiveBackground or theme.tabBackground
    buf:blit(x, 1, text, fg, bg)
    if e.doc:isDirty() then buf:blit(x + #name + 2, 1, "*", theme.tabDirty, bg) end
    self._tabHits[#self._tabHits + 1] = { from = x, to = x + #text - 1, close = x + #name + 2, editor = e }
    x = x + #text
  end
end

function Workbench:_clickTabs(btn, x)
  if x == 1 and self._tabOffset > 1 then
    self._tabOffset = self._tabOffset - 1
    self.tabs:markRenderDirty()
    return
  end
  for _, hit in ipairs(self._tabHits) do
    if x >= hit.from and x <= hit.to then

      local contextClick = btn == 2
        or (btn == 1 and self.studio.keybindings:isDown("ctrl"))
      if contextClick then
        local ax, ay = self.tabs:getAbsolutePosition()
        self:_tabMenu(hit.editor, ax + x - 1, ay + 1)
      elseif btn == 3 or x == hit.close then
        self:closeEditor(hit.editor)
      else
        self:activate(hit.editor)
        self._tabDrag = hit.editor
      end
      return
    end
  end
end

function Workbench:_dragTab(x)
  local dragged = self._tabDrag
  if not dragged then return end
  local target
  for _, hit in ipairs(self._tabHits) do
    if x >= hit.from and x <= hit.to then target = hit.editor end
  end
  if not target and #self._tabHits > 0 and x > self._tabHits[#self._tabHits].to then
    target = self._tabHits[#self._tabHits].editor
  end
  if not target or target == dragged then return end
  local from, to
  for i, e in ipairs(self.editors) do
    if e == dragged then from = i end
    if e == target then to = i end
  end
  table.remove(self.editors, from)
  table.insert(self.editors, to, dragged)
  self.tabs:markRenderDirty()
end

function Workbench:_drawWelcome(buf)
  local theme = self.theme
  local w, h = self.editorArea.width, self.editorArea.height
  local hints = {}
  local function hint(label, command)
    local chord = self.studio.keybindings:chordFor(command)
    if chord then hints[#hints + 1] = { label = label, chord = M.shortChord(chord) } end
  end
  hint("Search everywhere", "search.everywhere")
  hint("Commands", "palette.show")
  hint("Go to file", "file.open")
  hint("New file", "file.new")
  hint("Toggle sidebar", "view.toggleSidebar")

  local labelWidth, chordWidth = 0, 0
  for _, item in ipairs(hints) do
    labelWidth = math.max(labelWidth, #item.label)
    chordWidth = math.max(chordWidth, #item.chord)
  end
  local hintWidth = labelWidth + 2 + chordWidth
  local top = math.max(1, math.floor((h - 3 - #hints) / 2) + 1)
  local title = (self.studio.name or "Pineapple Studio"):sub(1, w)
  buf:blit(math.max(1, math.floor((w - #title) / 2) + 1), top, title, theme.accent, theme.editorBackground)
  local instructionText = "Open a file from the explorer"
  local instruction = instructionText:sub(1, w)
  buf:blit(math.max(1, math.floor((w - #instruction) / 2) + 1), top + 2,
    instruction, theme.muted, theme.editorBackground)
  local hintX = math.max(1, math.floor((w - hintWidth) / 2) + 1)
  for i, item in ipairs(hints) do
    local y = top + 2 + i
    buf:blit(hintX, y, item.label, theme.muted, theme.editorBackground)
    buf:blit(hintX + labelWidth + 2, y, item.chord, theme.muted, theme.editorBackground)
  end
end

function Workbench:service()
  local wb = self
  local function bind(name) return function(_, ...) return wb[name](wb, ...) end end
  return {
    addPanel = bind("addPanel"),
    showPanel = bind("showPanel"),
    addStatusItem = bind("addStatusItem"),
    refreshStatus = bind("refreshStatus"),
    notify = bind("notify"),
    choose = bind("choose"),
    prompt = bind("prompt"),
    quickPick = bind("quickPick"),
    openFile = bind("openFile"),
    closeEditor = bind("closeEditor"),
    activeEditor = bind("activeEditor"),
    toggleSidebar = bind("toggleSidebar"),
    togglePanel = bind("togglePanel"),
    closePanel = bind("closePanel"),
    movePanel = bind("movePanel"),
    fileTemplates = function() return wb.studio:fileTemplates() end,
    newFile = function(_, folder, templateId) return wb.studio:newFile(folder, templateId) end,
    toggleDock = bind("toggleDock"),
    popupMenu = bind("popupMenu"),
    capturePointer = bind("capturePointer"),
    openView = bind("openView"),
    setTheme = bind("setTheme"),
    editors = function() local out = {} for i, e in ipairs(wb.editors) do out[i] = e end return out end,
    theme = function() return wb.theme end,
    root = function() return wb.frame end,
    screenBuffer = bind("screenBuffer"),
    getClipboard = bind("getClipboard"),
    setClipboard = bind("setClipboard"),
    shell = function() return wb.studio.shell end,
    onRawEvent = function(_, fn) return wb.studio:addEventHook(fn) end,
    hasProject = function() return wb.studio.hasProject == true end,
    shortChord = function(_, chord) return M.shortChord(chord) end,
  }
end

M.label = commandsModule.label

return M

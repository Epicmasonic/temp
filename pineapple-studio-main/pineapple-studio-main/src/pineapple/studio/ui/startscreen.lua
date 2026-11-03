
local dialogs = require("pineapple.studio.ui.dialogs")
local images = require("pineapple.studio.core.images")

local M = {}

local Screen = {}
Screen.__index = Screen

local WIDE = 46
local BUTTON_W = 17

local function loadLogo()
  local dir = fs.getDir(debug.getinfo(1, "S").source:gsub("^@", ""))
  local path = "/" .. fs.combine(dir, "assets/pineapple.nft")
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  return images.nft(text)
end

function M.new(studio, callbacks)
  local self = setmetatable({
    studio = studio,
    theme = studio.theme,
    callbacks = callbacks or {},
    mode = "home",
    selected = 0,
    template = 1,
    focus = "name",
    name = { text = "", cursor = 1 },
    location = { text = "/projects", cursor = 10 },
    error = nil,
    logo = loadLogo(),
  }, Screen)
  local root = studio.frame

  self.frame = root:addFrame({ x = 1, y = 1, background = self.theme.background, z = 700, visible = false })
  self.canvas = self.frame:addCanvas({
    x = 1, y = 1,
    width = function() return self.frame.width end,
    height = function() return self.frame.height end,
    background = self.theme.background,
    draw = function(_, buf) self:_draw(buf) end,
  })
  self.canvas:onClick(function(_, button, x, y) self:_click(x, y, button) end)
  self.canvas:onScroll(function(_, dir) self:_move(dir) end)
  self.canvas:onKey(function(_, key) self:_key(key) end)
  self.canvas:onChar(function(_, ch) self:_char(ch) end)
  self.canvas:onPaste(function(_, text) self:_char((text:gsub("\n", " "))) end)
  self:layout()
  return self
end

function Screen:layout()
  local root = self.studio.frame
  self.frame.width = root.width
  self.frame.height = root.height
end

function Screen:isVisible()
  return self.frame.visible
end

function Screen:show(mode)
  self.mode = mode or "home"
  self.error = nil
  self.selected = 0
  if self.mode == "new" then
    self.template = 1
    self.focus = "name"
    self.name = { text = "", cursor = 1 }
  end
  self:layout()
  self.frame.visible = true
  self.canvas:focus()
  self.canvas:markRenderDirty()
end

function Screen:hide()
  self.frame.visible = false
end

local function templates(self) return self.studio.projects:templates() end
local function recent(self) return self.studio.projects:recent() end

function Screen:homeItems()
  local items = {
    { kind = "button", label = "New Project", command = "project.new" },
    { kind = "button", label = "Open Folder", command = "project.open" },
    { kind = "button", label = "Settings", action = "settings" },
    { kind = "button", label = "Quit", command = "studio.quit" },
  }
  for _, folder in ipairs(recent(self)) do
    items[#items + 1] = { kind = "recent", label = fs.getName(folder), path = folder }
  end
  return items
end

function Screen:_homeLayout(w, h)
  local wide = w >= WIDE
  local items = self:homeItems()
  local L = { wide = wide, rows = {}, items = items }
  local buttons, recents = {}, {}
  for i, item in ipairs(items) do
    if item.kind == "button" then buttons[#buttons + 1] = i else recents[#recents + 1] = i end
  end
  local bw = math.min(BUTTON_W, w - 4)
  local logoH = self.logo and self.logo.height or 0
  local logoW = self.logo and self.logo.width or 0

  local blockH = (logoH > 0 and (logoH + 1) or 0) + 2 + 1 + #buttons * 2 - 1
  if wide then
    L.sepX = math.floor(w / 2)
    local cx = L.sepX + math.floor((w - L.sepX) / 2) + 1
    local top = math.max(2, math.floor((h - blockH) / 2) + 1)
    L.logo = logoH > 0 and { x = cx - math.floor(logoW / 2), y = top } or nil
    local y = top + (logoH > 0 and (logoH + 1) or 0)
    L.nameY, L.versionY, L.centerX = y, y + 1, cx
    y = y + 3
    for _, index in ipairs(buttons) do
      L.rows[#L.rows + 1] = { index = index, item = items[index], x = cx - math.floor(bw / 2), y = y, w = bw, button = true }
      y = y + 2
    end

    L.listX, L.listY, L.listW = 3, 4, L.sepX - 5
    L.headerY = 2
    local ry = L.listY
    for _, index in ipairs(recents) do
      if ry + 1 > h - 1 then break end
      L.rows[#L.rows + 1] = { index = index, item = items[index], x = L.listX - 1, y = ry, w = L.listW + 2, h = 2 }
      ry = ry + 3
    end
    L.emptyY = L.listY
  else

    local cx = math.floor(w / 2) + 1
    L.centerX, L.nameY, L.versionY = cx, 2, 3
    local y = 5
    for _, index in ipairs(buttons) do
      L.rows[#L.rows + 1] = { index = index, item = items[index], x = cx - math.floor(bw / 2), y = y, w = bw, button = true }
      y = y + 1
    end
    L.headerY = y + 1
    L.listX, L.listW = 3, w - 4
    local ry = y + 2
    for _, index in ipairs(recents) do
      if ry > h then break end
      L.rows[#L.rows + 1] = { index = index, item = items[index], x = L.listX - 1, y = ry, w = L.listW + 2, h = 1 }
      ry = ry + 1
    end
    L.emptyY = y + 2
  end
  L.hasRecent = #recents > 0
  return L
end

local function put(buf, x, y, text, fg, bg, maxW)
  if maxW and #text > maxW then text = text:sub(1, math.max(0, maxW - 1)) .. "~" end
  if text ~= "" then buf:blit(x, y, text, fg, bg) end
end

local function centred(buf, cx, y, text, fg, bg)
  put(buf, cx - math.floor(#text / 2), y, text, fg, bg)
end

local function button(buf, t, x, y, w, label, active)
  local pad = math.max(0, w - #label)
  local text = string.rep(" ", math.floor(pad / 2)) .. label .. string.rep(" ", pad - math.floor(pad / 2))
  buf:blit(x, y, text:sub(1, w),
    active and t.buttonActiveForeground or t.buttonForeground,
    active and t.buttonActiveBackground or t.buttonBackground)
end

function Screen:_draw(buf)
  local t, w, h = self.theme, self.frame.width, self.frame.height
  buf:fill(1, 1, w, h, " ", t.foreground, t.background)
  if self.mode == "home" then self:_drawHome(buf, w, h) else self:_drawNew(buf, w, h) end
end

function Screen:_drawLogo(buf, x, y)
  local logo = self.logo
  if not logo then return end
  local bg = self.theme.background
  for row, line in ipairs(logo.frames[1]) do
    local text, fgs, bgs = {}, {}, {}
    for i = 1, #line[1] do
      text[i] = line[1]:sub(i, i)
      fgs[i] = images.colour(line[2]:sub(i, i)) or colors.white
      bgs[i] = images.colour(line[3]:sub(i, i)) or bg
    end
    if #text > 0 then buf:colorBlit(x, y + row - 1, table.concat(text), fgs, bgs) end
  end
end

function Screen:_drawHome(buf, w, h)
  local t = self.theme
  local L = self:_homeLayout(w, h)
  local name = self.studio.name or "Pineapple Studio"
  if L.wide then
    for y = 2, h - 1 do buf:blit(L.sepX, y, "|", t.dividerForeground or t.muted, t.background) end
    if L.logo then self:_drawLogo(buf, L.logo.x, L.logo.y) end
  end
  centred(buf, L.centerX, L.nameY, name, t.foreground, t.background)
  centred(buf, L.centerX, L.versionY, (self.studio.displayVersion or self.studio.version or ""), t.muted, t.background)
  put(buf, L.listX, L.headerY, "Recent Projects", t.accent, t.background)
  if not L.hasRecent then
    put(buf, L.listX, L.emptyY, "No recent projects", t.muted, t.background, L.listW)
    for i, line in ipairs(dialogs.wrap("Create one, or open a folder.", math.max(4, L.listW))) do
      put(buf, L.listX, L.emptyY + i, line, t.muted, t.background, L.listW)
    end
  end
  for _, r in ipairs(L.rows) do
    local active = r.index == self.selected
    if r.button then
      button(buf, t, r.x, r.y, r.w, r.item.label, active)
    else
      local fg = active and t.listSelectionForeground or t.foreground
      local bg = active and t.listSelectionBackground or t.background
      buf:fill(r.x, r.y, r.w, r.h, " ", fg, bg)
      put(buf, r.x + 1, r.y, r.item.label, fg, bg, r.w - 2)
      if r.h > 1 then
        put(buf, r.x + 1, r.y + 1, r.item.path, active and fg or t.muted, bg, r.w - 2)
      elseif #r.item.label + #r.item.path + 3 < r.w then
        put(buf, r.x + #r.item.label + 2, r.y, r.item.path, active and fg or t.muted, bg)
      end
    end
  end
  self.canvas:setCursor(0, 0, false)
end

function Screen:_newLayout(w, h)
  local wide = w >= WIDE
  local list = templates(self)
  local L = { list = {}, wide = wide }
  L.titleY = 2
  if wide then
    L.listX, L.listY, L.listW = 2, 4, math.min(20, math.floor(w * 0.38))
    L.listH = math.max(3, h - 6)
    L.rightX = L.listX + L.listW + 2
    L.rightW = w - L.rightX - 1
    L.descY = L.listY
    L.labelX = L.rightX
    L.fieldX = L.rightX + 10
    L.fieldW = math.max(4, w - L.fieldX - 1)
    L.nameY = math.max(L.descY + 4, h - 6)
    L.locationY = L.nameY + 1
    L.previewY = L.nameY + 2
    L.buttonY = h - 1
  else
    L.listX, L.listY, L.listW = 2, 4, w - 2
    L.listH = math.max(1, math.min(#list, h - 12))
    L.rightX, L.rightW = 2, w - 2
    L.descY = L.listY + L.listH + 1
    L.labelX, L.fieldX = 2, 12
    L.fieldW = math.max(4, w - L.fieldX)
    L.nameY = L.descY + 2
    L.locationY, L.previewY = L.nameY + 1, L.nameY + 2
    L.buttonY = h
  end
  for i, tpl in ipairs(list) do
    if i > L.listH then break end
    L.list[#L.list + 1] = { template = tpl, index = i, x = L.listX, y = L.listY + i - 1, w = L.listW }
  end

  L.createW, L.cancelW = 8, 8
  L.createX = w - L.createW
  L.cancelX = L.createX - L.cancelW - 1
  return L, list
end

function Screen:_drawNew(buf, w, h)
  local t = self.theme
  local L, list = self:_newLayout(w, h)
  put(buf, 2, L.titleY, "Create New", t.accent, t.background)

  buf:fill(L.listX, L.listY, L.listW, L.listH, " ", t.listForeground, t.inputBackground)
  for _, row in ipairs(L.list) do
    local active = row.index == self.template
    local fg = active and t.listSelectionForeground or t.listForeground
    local bg = active and t.listSelectionBackground or t.inputBackground
    local text = " " .. (row.template.title or row.template.id)
    put(buf, row.x, row.y, (text .. string.rep(" ", row.w)):sub(1, row.w), fg, bg)
  end
  if #list == 0 then put(buf, L.listX + 1, L.listY, "No templates", t.muted, t.inputBackground) end

  local selected = list[self.template]
  if selected then
    put(buf, L.rightX, L.descY, selected.title or selected.id, t.accent, t.background, L.rightW)
    for i, line in ipairs(dialogs.wrap(selected.description or "", L.rightW)) do
      local y = L.descY + 1 + i
      if y < L.nameY - 1 then put(buf, L.rightX, y, line, t.foreground, t.background) end
    end
  end

  put(buf, L.labelX, L.nameY, "Name", self.focus == "name" and t.accent or t.foreground, t.background)
  put(buf, L.labelX, L.locationY, "Location", self.focus == "location" and t.accent or t.foreground, t.background)
  local nameCursor = dialogs.drawField(buf, t, self.name, L.fieldX, L.nameY, L.fieldW, "my-project")
  local locCursor = dialogs.drawField(buf, t, self.location, L.fieldX, L.locationY, L.fieldW)
  if self.error then
    put(buf, L.labelX, L.previewY, self.error, colors.red, t.background, w - L.labelX)
  elseif self.name.text ~= "" then
    put(buf, L.labelX, L.previewY, "Creates " .. "/" .. fs.combine(self.location.text, self.name.text),
      t.muted, t.background, w - L.labelX)
  end

  button(buf, t, L.cancelX, L.buttonY, L.cancelW, "Cancel", self.focus == "cancel")
  button(buf, t, L.createX, L.buttonY, L.createW, "Create", true)

  if self.focus == "name" then self.canvas:setCursor(nameCursor, L.nameY, true, t.inputForeground)
  elseif self.focus == "location" then self.canvas:setCursor(locCursor, L.locationY, true, t.inputForeground)
  else self.canvas:setCursor(0, 0, false) end
end

function Screen:_activateHome(item)
  if not item then return end
  if item.kind == "recent" then
    if self.callbacks.open then self.callbacks.open(item.path) end
  elseif item.action == "settings" then
    if self.callbacks.settings then self.callbacks.settings() end
  else
    local ok, err = pcall(self.studio.commands.execute, self.studio.commands, item.command)
    if not ok then self.studio.workbench:notify(tostring(err), "error") end
  end
end

function Screen:_recentMenu(item, x, y)
  local workbench = self.studio.workbench
  local function refresh() self.canvas:markRenderDirty() end
  local entries = {
    { label = "Remove from Recents", act = function()
      self.studio.projects:removeRecent(item.path)
      self.selected = 0
      refresh()
    end },
    { separator = true },
    { label = "Delete Folder", act = function()
      workbench:choose({
        title = "Delete Project Folder?",
        message = "Permanently delete " .. item.path .. " and everything in it?",
        buttons = { "Delete", "Cancel" },
        default = 2,
        cancel = 2,
      }, function(choice)
        if choice ~= 1 then return end
        local path = item.path:gsub("/+$", "")
        if path == "" or path == "/" or path == "/rom" or path:match("^/rom/") then
          workbench:notify("That folder can't be deleted from Recents", "error")
          return
        end
        local ok, err = pcall(fs.delete, path)
        if not ok then
          workbench:notify("Couldn't delete " .. path .. ": " .. tostring(err), "error")
          return
        end
        self.studio.projects:removeRecent(item.path)
        self.selected = 0
        refresh()
      end)
    end },
  }
  workbench:popupMenu(x, y, entries, function(entry)
    if entry and entry.act then entry.act() end
  end)
end

function Screen:create()
  local list = templates(self)
  local template = list[self.template]
  if not template then self.error = "Pick a template"; self.canvas:markRenderDirty() return end
  local folder, err = self.callbacks.create(template.id, self.location.text, self.name.text)
  if not folder then
    self.error = err
    self.canvas:markRenderDirty()
  end
end

function Screen:_click(x, y, button)
  local w, h = self.frame.width, self.frame.height
  if self.mode == "home" then
    local L = self:_homeLayout(w, h)
    local root = self.canvas:getRoot()
    local ctrl = root.isKeyDown and (root:isKeyDown(keys.leftCtrl) or root:isKeyDown(keys.rightCtrl))
    if button == 2 or (button == 1 and ctrl) then
      for _, r in ipairs(L.rows) do
        if r.item.kind == "recent" and y >= r.y and y < r.y + r.h
          and x >= r.x and x < r.x + r.w then
          self.selected = r.index
          self.canvas:markRenderDirty()
          self:_recentMenu(r.item, x, y)
          return
        end
      end
      return
    end
    for _, r in ipairs(L.rows) do
      if y >= r.y and y < r.y + (r.h or 1) and x >= r.x and x < r.x + r.w then
        self.selected = r.index
        self.canvas:markRenderDirty()
        self:_activateHome(r.item)
        return
      end
    end
    return
  end
  local L = self:_newLayout(w, h)
  for _, row in ipairs(L.list) do
    if y == row.y and x >= row.x and x < row.x + row.w then
      self.template, self.focus = row.index, "list"
      self.canvas:markRenderDirty()
      return
    end
  end
  if y == L.nameY and x >= L.labelX then self.focus = "name"
  elseif y == L.locationY and x >= L.labelX then self.focus = "location"
  elseif y == L.buttonY and x >= L.createX and x < L.createX + L.createW then self.focus = "create"; self:create() return
  elseif y == L.buttonY and x >= L.cancelX and x < L.cancelX + L.cancelW then self:show("home") return
  end
  self.canvas:markRenderDirty()
end

function Screen:_move(dir)
  if self.mode == "home" then
    local n = #self:homeItems()
    self.selected = math.max(1, math.min(n, self.selected + dir))
  else
    self.template = math.max(1, math.min(#templates(self), self.template + dir))
  end
  self.canvas:markRenderDirty()
end

local FOCUS_ORDER = { "list", "name", "location", "create", "cancel" }

function Screen:_key(key)
  if self.mode == "home" then
    if key == keys.up then self:_move(-1)
    elseif key == keys.down or key == keys.tab then self:_move(1)
    elseif key == keys.enter or key == keys.numPadEnter then
      self:_activateHome(self:homeItems()[self.selected])
    end
    return
  end
  if key == keys.tab then
    local i = 1
    for k, f in ipairs(FOCUS_ORDER) do if f == self.focus then i = k end end
    self.focus = FOCUS_ORDER[(i % #FOCUS_ORDER) + 1]
  elseif key == keys.up then self:_move(-1) return
  elseif key == keys.down then self:_move(1) return
  elseif key == keys.enter or key == keys.numPadEnter then
    if self.focus == "cancel" then self:show("home") else self:create() end
    return
  elseif self.focus == "name" or self.focus == "location" then
    local field = self[self.focus]
    if key == keys.backspace and field.text == "" and self.focus == "name" then self:show("home") return end
    if dialogs.editField(field, key) then self.error = nil end
  end
  self.canvas:markRenderDirty()
end

function Screen:_char(ch)
  if self.mode ~= "new" then return end
  if self.focus ~= "name" and self.focus ~= "location" then self.focus = "name" end
  dialogs.insertField(self[self.focus], ch)
  self.error = nil
  self.canvas:markRenderDirty()
end

function Screen:applyTheme(theme)
  self.frame.background = theme.background
  self.canvas.background = theme.background
end

return M

local M = {}

local function wrap(text, width)
  local lines = {}
  width = math.max(1, width)
  for paragraph in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      if line == "" then line = word
      elseif #line + 1 + #word <= width then line = line .. " " .. word
      else lines[#lines + 1] = line; line = word end
      while #line > width do lines[#lines + 1] = line:sub(1, width); line = line:sub(width + 1) end
    end
    lines[#lines + 1] = line
  end
  return lines
end
M.wrap = wrap

local function overlay(root, onOutside)
  local w, h = root.width, root.height
  local layer = root:addFrame({ x = 1, y = 1, width = w, height = h, background = false, z = 900 })
  layer:onClick(function(_, _, x, y) if onOutside then onOutside(x, y) end end)
  return layer
end

local function shadow(layer, theme, x, y, w, h)
  if not theme.shadow then return end
  layer:addCanvas({
    x = x + 1, y = y + 1, width = w, height = h, z = 0,
    background = theme.shadow,
    draw = function() end,
  })
end
M.shadow = shadow

local function restoreFocus(root, previous)
  if previous and rawget(previous, "parent") then previous:focus() end
end

local function titleBar(buf, theme, title, width)
  buf:blit(1, 1, ((" " .. (title or "")) .. string.rep(" ", width)):sub(1, width),
    theme.dialogTitleForeground, theme.dialogTitleBackground)
end

function M.choose(root, theme, opts, callback)
  local previous = root.getFocused and root:getFocused()
  local layer = overlay(root)
  local buttons = opts.buttons or { "OK" }
  local selected = opts.default or 1

  local buttonsWidth = 0
  for _, b in ipairs(buttons) do buttonsWidth = buttonsWidth + #b + 3 end
  local width = math.min(root.width - 3, math.max(24, buttonsWidth + 2, #(opts.title or "") + 2))
  local message = wrap(opts.message or "", width - 2)
  local height = #message + 4
  local bx = math.floor((root.width - width) / 2) + 1
  local by = math.floor((root.height - height) / 2) + 1
  local hits = {}

  local closed = false
  local function close(index)
    if closed then return end
    closed = true
    layer:destroy()
    restoreFocus(root, previous)
    if callback then callback(index) end
  end

  shadow(layer, theme, bx, by, width, height)
  local box = layer:addCanvas({
    x = bx, y = by, width = width, height = height, z = 1,
    background = theme.dialogBackground,
    draw = function(self, buf)
      titleBar(buf, theme, opts.title, width)
      for i, line in ipairs(message) do
        buf:blit(2, 2 + i, line, theme.dialogForeground, theme.dialogBackground)
      end
      local x = math.max(2, math.floor((width - buttonsWidth) / 2) + 1)
      hits = {}
      for i, label in ipairs(buttons) do
        local text = " " .. label .. " "
        local active = i == selected
        buf:blit(x, height, text,
          active and theme.buttonActiveForeground or theme.buttonForeground,
          active and theme.buttonActiveBackground or theme.buttonBackground)
        hits[i] = { x, x + #text - 1 }
        x = x + #text + 1
      end
    end,
  })
  box:onClick(function(_, _, x, y)
    if y ~= height then return end
    for i, range in ipairs(hits) do
      if x >= range[1] and x <= range[2] then close(i) return end
    end
  end)
  box:onKey(function(_, key)
    if key == keys.enter or key == keys.numPadEnter then close(selected)
    elseif key == keys.left then selected = math.max(1, selected - 1); box:markRenderDirty()
    elseif key == keys.right or key == keys.tab then selected = math.min(#buttons, selected + 1); box:markRenderDirty()
    end
  end)
  box:onKeyUp(function(_, key)

    if key == (keys.escape or -1) then close(opts.cancel) end
  end)
  box:focus()
  return { close = function() close(opts.cancel) end }
end

local function editField(state, key)
  local text, cursor = state.text, state.cursor
  if key == keys.left then cursor = math.max(1, cursor - 1)
  elseif key == keys.right then cursor = math.min(#text + 1, cursor + 1)
  elseif key == keys.home then cursor = 1
  elseif key == keys["end"] then cursor = #text + 1
  elseif key == keys.backspace and cursor > 1 then
    text = text:sub(1, cursor - 2) .. text:sub(cursor); cursor = cursor - 1
  elseif key == keys.delete then
    text = text:sub(1, cursor - 1) .. text:sub(cursor + 1)
  else return false end
  state.text, state.cursor = text, cursor
  return true
end

local function insertField(state, str)
  state.text = state.text:sub(1, state.cursor - 1) .. str .. state.text:sub(state.cursor)
  state.cursor = state.cursor + #str
end

local function drawField(buf, theme, state, x, y, w, placeholder)
  local start = math.max(1, state.cursor - w + 1)
  local shown = state.text:sub(start, start + w - 1)
  buf:fill(x, y, w, 1, " ", theme.inputForeground, theme.inputBackground)
  if state.text == "" and placeholder then
    buf:blit(x, y, placeholder:sub(1, w), theme.inputPlaceholder, theme.inputBackground)
  else
    buf:blit(x, y, shown, theme.inputForeground, theme.inputBackground)
  end
  return x + state.cursor - start
end

M.editField, M.insertField, M.drawField = editField, insertField, drawField

function M.fuzzy(query, text)
  if query == "" then return 0 end
  local q, t = query:lower(), text:lower()
  local score, ti, prev = 0, 1, -1
  for qi = 1, #q do
    local c = q:sub(qi, qi)
    local found = t:find(c, ti, true)
    if not found then return nil end
    if found == prev + 1 then score = score + 5 end
    if found == 1 or t:sub(found - 1, found - 1):match("[%s%p]") then score = score + 3 end
    score = score + 1
    prev, ti = found, found + 1
  end
  return score - #t * 0.01
end

function M.filter(items, query)
  local scored = {}
  for i, item in ipairs(items) do
    local s = M.fuzzy(query, item.filterText or item.label)
    if s then scored[#scored + 1] = { item = item, score = s, index = i } end
  end
  if query ~= "" then
    table.sort(scored, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.index < b.index
    end)
  end
  local out = {}
  for i, e in ipairs(scored) do out[i] = e.item end
  return out
end

function M.quickPick(root, theme, items, opts, callback)
  opts = opts or {}
  local previous = root.getFocused and root:getFocused()
  local close
  local layer = overlay(root, function() close(nil) end)
  local tabs = opts.tabs
  local tabIndex = 1
  if tabs then
    for i, t in ipairs(tabs) do if t.id == opts.tab then tabIndex = i end end
  else
    tabs = { { id = "default", items = items, placeholder = opts.placeholder } }
  end
  local showTabs = opts.tabs ~= nil
  local top = showTabs and 1 or 0
  local width = math.min(root.width - 3, math.max(showTabs and 42 or 30, math.floor(root.width * 0.7)))
  local height = math.min(root.height - 3, showTabs and 14 or 12)
  local bx = math.floor((root.width - width) / 2) + 1
  local by = math.max(1, math.floor((root.height - height) / 2) + 1)
  local field = { text = opts.initial or "", cursor = #(opts.initial or "") + 1 }
  local filtered, selected, offset = {}, 1, 0
  local listRows = height - 1 - top
  local errorText
  local tabHits = {}

  local function refilter(keepSelection)
    local source = tabs[tabIndex].items
    errorText = nil
    if type(source) == "function" then
      local ok, result = pcall(source, field.text)
      if ok and type(result) == "table" then filtered = result
      else filtered = {}; errorText = ok and nil or tostring(result) end
    else
      filtered = M.filter(source or {}, field.text)
    end
    if not keepSelection then selected, offset = 1, 0 end
    selected = math.max(1, math.min(selected, #filtered))
  end
  if opts.selected then selected = opts.selected end
  refilter(opts.selected ~= nil)

  local closed = false
  function close(item)
    if closed then return end
    closed = true
    layer:destroy()
    restoreFocus(root, previous)
    if callback then callback(item, tabs[tabIndex].id) end
  end

  local function switchTab(delta)
    tabIndex = ((tabIndex - 1 + delta) % #tabs) + 1
    refilter()
  end

  local function isShift()
    return root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
  end

  shadow(layer, theme, bx, by, width, height)
  local box
  box = layer:addCanvas({
    x = bx, y = by, width = width, height = height, z = 1,
    background = theme.listBackground,
    draw = function(self, buf)
      local tab = tabs[tabIndex]

      if showTabs then
        local bg, fg = theme.dialogTitleBackground, theme.dialogTitleForeground
        buf:fill(1, 1, width, 1, " ", fg, bg)
        tabHits = {}

        local styles = {
          function(t) return " " .. t.title .. " " end,
          function(t) return t.title .. " " end,
          function(t) return t.title:sub(1, 3) .. " " end,
        }
        local style = styles[#styles]
        for _, candidate in ipairs(styles) do
          local total = 1
          for _, t in ipairs(tabs) do total = total + #candidate(t) end
          if total <= width then style = candidate; break end
        end
        local x = 2
        for i, t in ipairs(tabs) do
          local label = style(t)
          if x + #label - 1 > width then break end
          local active = i == tabIndex
          buf:blit(x, 1, label, active and theme.listForeground or fg, active and theme.listBackground or bg)
          tabHits[i] = { x, x + #label - 1 }
          x = x + #label
        end
        local hint = "Tab: next"
        if x + #hint + 1 <= width then buf:blit(width - #hint, 1, hint, theme.menuMuted or fg, bg) end
      end

      local fy = top + 1
      local title = (not showTabs and opts.title) and (" " .. opts.title .. " ") or ""
      local fieldWidth = width - 2
      if title ~= "" and #title + #field.text + 4 < width then fieldWidth = width - #title - 1 end
      buf:fill(1, fy, width, 1, " ", theme.inputForeground, theme.inputBackground)
      local cx = drawField(buf, theme, field, 2, fy, fieldWidth - 1, tab.placeholder or opts.placeholder)
      if fieldWidth < width - 2 then
        buf:blit(width - #title + 1, fy, title, theme.inputPlaceholder, theme.inputBackground)
      end
      if selected - offset > listRows then offset = selected - listRows end
      if selected - offset < 1 then offset = selected - 1 end
      for row = 1, listRows do
        local item = filtered[offset + row]
        local y = row + fy
        if item then
          local active = offset + row == selected
          local fg = active and theme.listSelectionForeground or theme.listForeground
          local mfg = active and theme.listSelectionForeground or theme.muted
          local bg = active and theme.listSelectionBackground or theme.listBackground
          local detail = item.detail and (tostring(item.detail) .. " ") or ""
          local room = width - #detail - (detail ~= "" and 1 or 0)
          buf:fill(1, y, width, 1, " ", fg, bg)
          local label = (" " .. item.label):sub(1, room)
          buf:blit(1, y, label, fg, bg)
          if item.hint and #label + 2 < room then
            buf:blit(#label + 2, y, tostring(item.hint):sub(1, room - #label - 2), mfg, bg)
          end
          if detail ~= "" then buf:blit(width - #detail + 1, y, detail:sub(1, width), mfg, bg) end
        elseif row == 1 then
          local text = errorText or (tab.empty and tab.empty(field.text)) or "No matches"
          buf:blit(2, y, text:sub(1, width - 2), theme.muted, theme.listBackground)
        end
      end
      require("pineapple.studio.ui.scrollbar").draw(buf, theme, width, fy + 1, listRows, #filtered, listRows, offset)
      self:setCursor(cx, fy, true, theme.inputForeground)
    end,
  })
  box:onClick(function(_, _, x, y)
    if showTabs and y == 1 then
      for i, hit in pairs(tabHits) do
        if x >= hit[1] and x <= hit[2] and i ~= tabIndex then
          tabIndex = i; refilter(); box:markRenderDirty()
        end
      end
      return
    end
    if y <= top + 1 then return end
    local index = offset + y - top - 1
    if filtered[index] then close(filtered[index]) end
  end)
  box:onScroll(function(_, dir)
    selected = math.max(1, math.min(#filtered, selected + dir)); box:markRenderDirty()
  end)
  box:onKey(function(_, key)
    if key == keys.enter or key == keys.numPadEnter then
      close(filtered[selected])
      return
    elseif key == keys.tab and showTabs then switchTab(isShift() and -1 or 1)
    elseif key == keys.up then selected = math.max(1, selected - 1)
    elseif key == keys.down then selected = math.min(math.max(1, #filtered), selected + 1)
    elseif key == keys.pageUp then selected = math.max(1, selected - listRows)
    elseif key == keys.pageDown then selected = math.min(math.max(1, #filtered), selected + listRows)
    elseif key == keys.backspace and field.text == "" then close(nil) return
    elseif editField(field, key) then refilter()
    else return end
    box:markRenderDirty()
  end)
  box:onKeyUp(function(_, key)
    if key == (keys.escape or -1) then close(nil) end
  end)
  box:onChar(function(_, ch) insertField(field, ch); refilter(); box:markRenderDirty() end)
  box:onPaste(function(_, text) insertField(field, text:gsub("\n", " ")); refilter(); box:markRenderDirty() end)
  box:focus()
  return {
    close = function() close(nil) end,
    tab = function() return tabs[tabIndex].id end,
    items = function() return filtered end,
  }
end

function M.prompt(root, theme, opts, callback)
  local previous = root.getFocused and root:getFocused()
  local close
  local layer = overlay(root, function() close(nil) end)
  local width = math.min(root.width - 3, math.max(34, #(opts.title or "") + 4))
  local message = wrap(opts.message or "", width - 2)
  local height = #message + 5
  local bx = math.floor((root.width - width) / 2) + 1
  local by = math.floor((root.height - height) / 2) + 1
  local field = { text = opts.default or "", cursor = #(opts.default or "") + 1 }

  local closed = false
  function close(value)
    if closed then return end
    closed = true
    layer:destroy()
    restoreFocus(root, previous)
    if callback then callback(value) end
  end

  shadow(layer, theme, bx, by, width, height)
  local box = layer:addCanvas({
    x = bx, y = by, width = width, height = height, z = 1,
    background = theme.dialogBackground,
    draw = function(self, buf)
      titleBar(buf, theme, opts.title, width)
      for i, line in ipairs(message) do
        buf:blit(2, 2 + i, line, theme.dialogForeground, theme.dialogBackground)
      end
      local fieldY = #message + 4
      local shown = field
      if opts.secret then shown = { text = string.rep("*", #field.text), cursor = field.cursor } end
      local cx = drawField(buf, theme, shown, 2, fieldY, width - 2)
      self:setCursor(cx, fieldY, true, theme.inputForeground)
      local hint = "Enter: OK  click outside: cancel"
      buf:blit(2, height, hint:sub(1, width - 2), theme.muted, theme.dialogBackground)
    end,
  })
  box:onKey(function(_, key)
    if key == keys.enter or key == keys.numPadEnter then close(field.text) return end
    if editField(field, key) then box:markRenderDirty() end
  end)
  box:onKeyUp(function(_, key)
    if key == (keys.escape or -1) then close(nil) end
  end)
  box:onChar(function(_, ch) insertField(field, ch); box:markRenderDirty() end)
  box:onPaste(function(_, text) insertField(field, text:gsub("\n", " ")); box:markRenderDirty() end)
  box:focus()
  return { close = function() close(nil) end }
end

function M.menu(root, theme, x, y, entries, opts, callback)
  opts = opts or {}
  local previous = root.getFocused and root:getFocused()
  local close
  local layer = overlay(root, function(cx, cy)
    close(nil)
    if opts.onOutside then opts.onOutside(cx, cy) end
  end)

  local labelWidth, detailWidth = 1, 0
  for _, e in ipairs(entries) do
    if not e.separator then
      labelWidth = math.max(labelWidth, #e.label)
      if e.detail then detailWidth = math.max(detailWidth, #e.detail) end
      if e.children then detailWidth = math.max(detailWidth, 1) end
    end
  end
  local width = labelWidth + 2 + (detailWidth > 0 and detailWidth + 2 or 0)
  width = math.min(width, root.width - 1)
  local height = math.min(#entries, root.height - y)

  if opts.flipX and x + width > root.width then x = opts.flipX - width end
  x = math.max(1, math.min(x, root.width - width))
  y = math.max(1, math.min(y, root.height - height))
  local selected = nil

  local closed = false
  local submenu
  function close(entry)
    if closed then return end
    closed = true
    if submenu then local sub = submenu; submenu = nil; sub.close() end
    layer:destroy()
    restoreFocus(root, previous)
    if callback then callback(entry) end
  end

  local function selectable(i)
    local e = entries[i]
    return e and not e.separator and not e.disabled
  end
  local function move(dir)
    local i = selected or (dir > 0 and 0 or #entries + 1)
    for _ = 1, #entries do
      i = i + dir
      if i < 1 then i = #entries elseif i > #entries then i = 1 end
      if selectable(i) then selected = i return end
    end
  end

  shadow(layer, theme, x, y, width, height)
  local box = layer:addCanvas({
    x = x, y = y, width = width, height = height, z = 1,
    background = theme.dropBackground,
    draw = function(_, buf)
      for row = 1, height do
        local e = entries[row]
        if e.separator then
          buf:blit(1, row, string.rep("-", width), theme.dropSeparator, theme.dropBackground)
        else
          local active = row == selected
          local fg = active and theme.menuActiveForeground or (e.disabled and theme.dropMuted or theme.dropForeground)
          local bg = active and theme.menuActiveBackground or theme.dropBackground
          local text = " " .. e.label
          text = text .. string.rep(" ", width - #text)
          buf:blit(1, row, text:sub(1, width), fg, bg)
          if e.children then
            buf:blit(width - 1, row, "\16", active and fg or theme.dropMuted, bg)
          elseif e.detail then
            buf:blit(width - #e.detail, row, e.detail, active and fg or theme.dropMuted, bg)
          end
        end
      end
    end,
  })

  local activate
  local function openSub(row)
    local e = entries[row]
    selected = row
    box:markRenderDirty()
    local function onOutside(cx, cy)
      if cx >= x and cx < x + width and cy >= y and cy < y + height then
        local r = cy - y + 1
        if r ~= row and selectable(r) then activate(r) end
      else
        close(nil)
      end
    end
    submenu = M.menu(root, theme, x + width, y + row - 1, e.children, {
      flipX = x, onOutside = onOutside,
      onLeft = function() box:focus() end,
    }, function(child)
      submenu = nil
      if child then close(child) elseif not closed then box:focus(); box:markRenderDirty() end
    end)
  end
  function activate(row)
    local e = entries[row]
    if e.children then openSub(row) else close(e) end
  end

  box:onClick(function(_, _, _, cy)
    if selectable(cy) then activate(cy) end
  end)
  box:onKey(function(_, key)
    if key == keys.down then move(1)
    elseif key == keys.up then move(-1)
    elseif key == keys.enter or key == keys.numPadEnter then
      if selected then activate(selected) end
      return
    elseif key == keys.right and selected and entries[selected].children then openSub(selected) return
    elseif key == keys.left and opts.onLeft then close(nil); opts.onLeft() return
    elseif key == keys.right and opts.onRight then close(nil); opts.onRight() return
    elseif key == keys.backspace then close(nil) return
    else return end
    box:markRenderDirty()
  end)
  box:onKeyUp(function(_, key)
    if key == (keys.escape or -1) then close(nil) end
  end)
  box:focus()
  return { close = function() close(nil) end, select = function(i) selected = i; box:markRenderDirty() end,
    open = function(i) activate(i) end, submenu = function() return submenu end }
end

return M

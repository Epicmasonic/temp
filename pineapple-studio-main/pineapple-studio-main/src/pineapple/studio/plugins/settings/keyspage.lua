local R = require("pineapple.studio.ui.rows")
local keymaps = require("pineapple.studio.core.keymaps")

local M = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function sameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function needsModifier(chord)
  if chord:find("ctrl+", 1, true) or chord:find("alt+", 1, true) then return false end
  local key = chord:match("([^+]+)$")
  if key:match("^f%d+$") or key == "insert" or key == "pause" or key == "scrollLock" then return false end
  return true
end

function M.new(ctx)
  local studio = ctx.studio
  local settings, ui, kb, commands = studio.settings, studio.ui, studio.keybindings, studio.commands
  local page = { id = "keys", label = "Keyboard Shortcuts", short = "Shortcuts", placeholder = "Search shortcuts" }

  local function custom() return copy(settings:get("keybindings.custom")) end

  local function label(cmd)
    local title = (cmd.title or cmd.id):gsub("%.%.%.$", "")
    return title
  end

  local function stopRecording()
    if page.cancelCapture then page.cancelCapture() end
    page.cancelCapture, page.recording = nil, nil
  end

  local function assign(id, value)
    local map = custom()
    map[id] = value
    if value ~= nil then

      kb:setOverrides(copy(map)); local withChange = kb:chordsFor(id)
      local base = copy(map); base[id] = nil
      kb:setOverrides(base); local without = kb:chordsFor(id)
      if sameList(withChange, without) then map[id] = nil end
    end
    settings:set("keybindings.custom", map)
    kb:setOverrides(settings:get("keybindings.custom") or {})
    ctx.dirty()
  end

  local function record(cmd)
    stopRecording()
    page.recording = cmd.id
    page.cancelCapture = kb:capture(function(chord)
      page.cancelCapture, page.recording = nil, nil
      if chord == "backspace" or chord == "delete" then
        assign(cmd.id, false)
        ui:notify(label(cmd) .. ": no shortcut", "info", 2)
        return
      end
      if needsModifier(chord) then
        ui:notify("Use Ctrl or Alt with that key (or an F key)", "warning", 3)
        ctx.dirty()
        return
      end
      local others = {}
      for _, other in ipairs(kb:commandsOn(chord)) do
        if other ~= cmd.id then
          local c = commands:get(other)
          others[#others + 1] = c and label(c) or other
        end
      end
      assign(cmd.id, chord)
      if #others > 0 then
        ui:notify(R.chordText(chord) .. " is also used by " .. table.concat(others, ", "), "warning", 4)
      else
        ui:notify(label(cmd) .. ": " .. R.chordText(chord), "info", 2)
      end
    end)
    ctx.dirty()
  end

  local function chooseKeymap(x, y)
    local current = settings:get("keybindings.keymap")
    local items = {}
    for _, k in ipairs(keymaps.list) do
      items[#items + 1] = { label = k.name, detail = k.id == current and "*" or nil, id = k.id }
    end
    ctx.popup(x or 2, y or 3, items, function(item)
      if item then settings:set("keybindings.keymap", item.id); ctx.dirty() end
    end)
  end

  local function cycleKeymap(delta)
    local current, index = settings:get("keybindings.keymap"), 1
    for i, k in ipairs(keymaps.list) do if k.id == current then index = i end end
    settings:set("keybindings.keymap", keymaps.list[((index - 1 + delta) % #keymaps.list) + 1].id)
    ctx.dirty()
  end

  function page.rows(w, query)
    local rows = {}
    local boxW = math.min(18, math.max(9, math.floor(w * 0.38)))
    local changes = custom()
    local changed = 0
    for _ in pairs(changes) do changed = changed + 1 end

    if query == "" then
      local pos = {}
      local it = {
        key = "keymap", title = "Keymap",
        description = "Use the keys you know from another IDE.",
        activate = function() chooseKeymap(pos.x, pos.y) end,
        cycle = cycleKeymap,
      }
      local longest = 0
      for _, k in ipairs(keymaps.list) do longest = math.max(longest, #k.name) end
      local bw, draw = R.box(keymaps.name(settings:get("keybindings.keymap")),
        math.max(boxW, math.min(longest + 4, w - 14)), { arrow = true },
        function(x, y) chooseKeymap(x, y) end)
      it.controlW = bw
      it.control = function(buf, x, y, cw, focused, hit) pos.x, pos.y = x, y; draw(buf, x, y, cw, focused, hit) end
      R.item(rows, it, w, ctx)
      if changed > 0 then
        local reset = {
          key = "resetAll", title = changed .. " shortcut" .. (changed == 1 and "" or "s") .. " changed by you",
          activate = function() settings:set("keybindings.custom", {}); ctx.dirty() end,
        }
        reset.controlW, reset.control = R.box("Reset all", math.min(boxW, 11), { button = true }, reset.activate)
        R.item(rows, reset, w, ctx)
      end
    end

    local groups, order = {}, {}
    for _, cmd in ipairs(commands:list()) do
      local chords = kb:chordsFor(cmd.id)
      local shown = {}
      for i, c in ipairs(chords) do shown[i] = R.chordText(c) end
      local text = (label(cmd) .. " " .. (cmd.category or "") .. " " .. cmd.id .. " " .. table.concat(shown, " ")):lower()
      local ok = true
      for word in query:lower():gmatch("%S+") do if not text:find(word, 1, true) then ok = false end end
      if ok then
        local cat = cmd.category or "Other"
        if not groups[cat] then groups[cat] = {}; order[#order + 1] = cat end
        groups[cat][#groups[cat] + 1] = { cmd = cmd, chords = shown }
      end
    end
    if #order == 0 then R.text(rows, "No commands match.", w, ctx) return rows end
    for _, cat in ipairs(order) do
      R.header(rows, cat, ctx)
      for _, entry in ipairs(groups[cat]) do
        local cmd = entry.cmd
        local recording = page.recording == cmd.id
        local own = changes[cmd.id] ~= nil
        local it = {
          key = cmd.id, title = label(cmd),
          activate = function() record(cmd) end,
          meta = own and "changed" or nil,
          link = own and { text = "reset", action = function() assign(cmd.id, nil) end } or nil,
        }
        local text = recording and "Press keys" or table.concat(entry.chords, ", ")
        it.controlW, it.control = R.box(text, boxW,
          { color = recording and function(t) return t.accent end or (text == "" and function(t) return t.muted end) or nil },
          function() record(cmd) end)
        R.item(rows, it, w, ctx)
      end
    end
    return rows
  end

  function page.commit() stopRecording() end
  function page.cancel() stopRecording(); ctx.dirty() end
  function page.dispose() stopRecording() end

  function page.record(id) record(commands:get(id)) end
  return page
end

return M

local dialogs = require("pineapple.studio.ui.dialogs")
local R = require("pineapple.studio.ui.rows")

local M = {}

local CATEGORY_NAMES = {
  editor = "Editor", workbench = "Workbench", explorer = "Explorer", files = "Files",
  run = "Run", terminal = "Terminal", imageViewer = "Image Viewer", problems = "Problems",
}

local function categoryOf(key)
  local prefix = key:match("^([^%.]+)%.") or "other"
  return CATEGORY_NAMES[prefix] or (prefix:sub(1, 1):upper() .. prefix:sub(2))
end

local function optionList(schema)
  local opts = schema.options
  if type(opts) == "function" then
    local ok, result = pcall(opts)
    opts = ok and result or nil
  end
  if type(opts) ~= "table" then return nil end
  local out = {}
  for i, o in ipairs(opts) do
    if type(o) == "table" then out[i] = { value = o.value, label = o.label or tostring(o.value) }
    else out[i] = { value = o, label = tostring(o) } end
  end
  return out
end
M.optionList = optionList

local function show(value)
  if value == nil then return "" end
  return tostring(value)
end

function M.new(ctx)
  local studio = ctx.studio
  local settings, ui = studio.settings, studio.ui
  local page = { id = "general", label = "General", placeholder = "Search settings", scope = "user" }

  local function entries(query)
    local list = {}
    for _, key in ipairs(settings:keys()) do
      local schema = settings:schema(key) or {}
      if schema.type ~= "table" and not schema.hidden and not (schema.userOnly and page.scope == "project") then
        local category = categoryOf(key)
        local text = ((schema.title or "") .. " " .. key .. " " .. (schema.description or "") .. " " .. category):lower()
        local matches = true
        for word in query:lower():gmatch("%S+") do
          if not text:find(word, 1, true) then matches = false end
        end
        if matches then list[#list + 1] = { key = key, schema = schema, category = category } end
      end
    end
    table.sort(list, function(a, b)
      if a.category ~= b.category then return a.category < b.category end
      return (a.schema.title or a.key) < (b.schema.title or b.key)
    end)
    return list
  end

  local function set(key, value)
    local ok, err = pcall(settings.set, settings, key, value, page.scope)
    if not ok then ui:notify((tostring(err):gsub("^.-:%d+: ", "")), "error") end
    ctx.dirty()
  end

  function page.commit()
    local e = page.editing
    if not e then return end
    page.editing = nil
    local schema = settings:schema(e.key) or {}
    local text = e.field.text
    if text == "" then set(e.key, nil) return end
    if schema.type == "number" then
      local n = tonumber(text)
      if not n then ui:notify((schema.title or e.key) .. " must be a number", "warning") ctx.dirty() return end
      set(e.key, n)
    else
      set(e.key, text)
    end
  end

  local function blocked() return page.scope == "project" and not ui:hasProject() end

  local function activate(entry, x, y)
    if blocked() then return end
    page.commit()
    local key, schema = entry.key, entry.schema
    local value = settings:get(key)
    local options = optionList(schema)
    if schema.type == "boolean" and not options then
      set(key, not value)
    elseif options then
      local items = {}
      for _, o in ipairs(options) do
        items[#items + 1] = { label = o.label, detail = o.value == value and "*" or nil, value = o.value }
      end
      ctx.popup(x or 2, y or 3, items, function(item) if item then set(key, item.value) end end)
    else
      local current = settings:inspect(key, page.scope)
      if current == nil then current = value end
      local text = show(current)
      page.editing = { key = key, field = { text = text, cursor = #text + 1 } }
      ctx.dirty()
    end
  end

  local function cycle(entry, delta)
    if blocked() then return end
    local key, schema = entry.key, entry.schema
    local options = optionList(schema)
    if schema.type == "boolean" and not options then set(key, not settings:get(key)) return end
    if not options then return end
    local value, index = settings:get(key), 1
    for i, o in ipairs(options) do if o.value == value then index = i end end
    set(key, options[((index - 1 + delta) % #options) + 1].value)
  end

  function page.setScope(scope)
    page.commit()
    page.scope = scope
    ctx.dirty()
  end

  function page.header()
    return {
      { label = " User ", active = page.scope == "user", action = function() page.setScope("user") end },
      { label = " Project ", active = page.scope == "project", action = function() page.setScope("project") end },
    }
  end

  function page.rows(w, query)
    local rows = {}
    if blocked() then
      R.text(rows, "Open a project to change its settings. Project settings are kept in the project's "
        .. ".pineapple/project.lua and override your own.", w, ctx)
      return rows
    end
    local list = entries(query)
    if #list == 0 then R.text(rows, "No settings match.", w, ctx) return rows end
    local fieldW = math.min(16, math.max(7, math.floor(w * 0.35)))
    local last
    for _, e in ipairs(list) do
      if e.category ~= last then
        R.header(rows, e.category, ctx)
        last = e.category
      end
      local key, schema = e.key, e.schema
      local own = settings:inspect(key, page.scope)
      local value = settings:get(key)
      local options = optionList(schema)
      local it = {
        key = key,
        title = schema.title or key,
        description = schema.description,

        meta = (own ~= nil and page.scope == "project") and "project value" or nil,
        metaColor = (own ~= nil and page.scope == "project") and function(t) return t.accent end or nil,
        link = own ~= nil and { text = "reset", action = function() page.commit(); set(key, nil) end } or nil,
        cycle = function(d) cycle(e, d) end,
      }
      local pos = {}
      it.activate = function() activate(e, pos.x, pos.y) end
      if schema.type == "boolean" and not options then
        it.controlW, it.control = R.checkbox(value == true, false, function() activate(e) end)
      elseif options then
        local label = show(value)
        for _, o in ipairs(options) do if o.value == value then label = o.label end end
        local w2, draw = R.box(label, fieldW, { arrow = true }, function(x, y) activate(e, x, y) end)
        it.controlW = w2
        it.control = function(buf, x, y, cw, focused, hit)
          pos.x, pos.y = x, y
          draw(buf, x, y, cw, focused, hit)
        end
      elseif page.editing and page.editing.key == key then
        it.controlW = fieldW
        it.control = function(buf, x, y, cw)
          local t = ctx.theme
          local ft = setmetatable({ inputBackground = t.fieldBackground or t.inputBackground }, { __index = t })
          ctx.cursor = { dialogs.drawField(buf, ft, page.editing.field, x, y, cw), y }
        end
      else
        it.controlW, it.control = R.box(show(value), fieldW, nil, function() activate(e) end)
      end
      R.item(rows, it, w, ctx)
    end
    return rows
  end

  function page.onKey(key)
    if not page.editing then return false end
    if key == keys.enter or key == keys.numPadEnter then page.commit()
    elseif not dialogs.editField(page.editing.field, key) then
      if key == keys.up or key == keys.down then page.commit() return false end
      return true
    end
    ctx.dirty()
    return true
  end
  function page.onChar(ch)
    if not page.editing then return false end
    dialogs.insertField(page.editing.field, ch)
    ctx.dirty()
    return true
  end
  function page.onPaste(text)
    if not page.editing then return false end
    dialogs.insertField(page.editing.field, (text:gsub("\n.*", "")))
    ctx.dirty()
    return true
  end
  function page.cancel() if page.editing then page.editing = nil; ctx.dirty() end end

  function page.activateKey(key)
    for _, e in ipairs(entries("")) do
      if e.key == key then activate(e, 2, 3) return true end
    end
    return false
  end
  return page
end

return M

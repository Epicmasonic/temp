local model = require("pineapple.studio.plugins.designer.model")

local B = { id = "bedrock" }

B.TYPES = { "Label", "Button", "TextBox", "SecureTextBox", "NumberBox", "ProgressBar",
  "ListView", "ScrollView", "View", "ImageView", "Separator" }
local CONTAINERS = { View = true, ScrollView = true, ListView = false }
function B.isContainer(t) return CONTAINERS[t] == true end

local DEFAULTS = {
  Button = { BackgroundColour = "lightGrey", TextColour = "black", Text = "", Align = "Center",
    ActiveBackgroundColour = "blue", ActiveTextColour = "white", Enabled = true, Toggle = false },
  Label = { TextColour = "black", BackgroundColour = "transparent", Text = "", Align = "Left" },
  TextBox = { BackgroundColour = "lightGrey", TextColour = "black", PlaceholderTextColour = "grey",
    Placeholder = "", Text = "" },
  SecureTextBox = { BackgroundColour = "lightGrey", TextColour = "black", PlaceholderTextColour = "grey",
    Placeholder = "", Text = "", MaskCharacter = "*" },
  NumberBox = { BackgroundColour = "lightGrey", Value = 1, Minimum = 1, Maximum = 99, Width = 7 },
  ProgressBar = { BackgroundColour = "lightGrey", BarColour = "blue", TextColour = "white",
    Value = 0, Maximum = 1, ShowText = false },
  ListView = { BackgroundColour = "white", TextColour = "black", HeadingColour = "lightGrey",
    SelectionBackgroundColour = "blue", SelectionTextColour = "white", CanSelect = false },
  ScrollView = { BackgroundColour = "transparent" },
  View = { BackgroundColour = "transparent" },
  ImageView = { Path = "" },
  Separator = { Colour = "grey" },
}
local NEW = {
  Label = { Text = "Label" }, Button = { Text = "Button" }, TextBox = { Width = 12, Placeholder = "Text" },
  SecureTextBox = { Width = 12 }, NumberBox = {}, ProgressBar = { Width = 12, Value = 0.5 },
  ListView = { Width = 14, Height = 6 }, ScrollView = { Width = 16, Height = 6 },
  View = { Width = 16, Height = 6, BackgroundColour = "lightGrey" }, ImageView = { Width = 8, Height = 5 },
  Separator = { Width = 1, Height = 5 },
}
local ORDER = { Type = 1, Name = 2, Text = 3, X = 4, Y = 5, Width = 6, Height = 7 }
local SIZE_KEYS = { X = "Width", Y = "Height", Width = "Width", Height = "Height" }

local COLOR_ORDER = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "grey",
  "lightGrey", "cyan", "purple", "blue", "brown", "green", "red", "black" }

local function toNode(t)
  local node = { type = t.Type or "View", name = t.Name, props = {} }
  for k, v in pairs(t) do
    if k ~= "Type" and k ~= "Name" and k ~= "Children" then node.props[k] = v end
  end
  if t.Children then
    node.children = {}
    for i, c in ipairs(t.Children) do node.children[i] = toNode(c) end
  end
  return node
end

function B.newModel()
  return { width = 51, height = 19, root = { BackgroundColour = "white" }, children = {} }
end

function B.parse(text)
  if not text:match("%S") then return B.newModel() end
  local data = textutils.unserialise(text)
  if type(data) ~= "table" or (data.Children == nil and data.Type == nil and next(data) ~= nil) then
    return nil, "not a Bedrock view"
  end
  local m = B.newModel()
  m.root = {}
  for k, v in pairs(data) do if k ~= "Children" then m.root[k] = v end end
  for i, c in ipairs(data.Children or {}) do m.children[i] = toNode(c) end
  return m
end

local function serialiseValue(v, indent)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local inner = indent .. "  "
  local parts = {}
  if #v > 0 then
    for _, item in ipairs(v) do parts[#parts + 1] = inner .. serialiseValue(item, inner) end
  else
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if a == "Children" then return false end
      if b == "Children" then return true end
      local oa, ob = ORDER[a] or 50, ORDER[b] or 50
      if oa ~= ob then return oa < ob end
      return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
      local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. serialiseValue(k, "") .. "]")
      parts[#parts + 1] = inner .. key .. " = " .. serialiseValue(v[k], inner)
    end
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function toTable(node)
  local t = { Type = node.type, Name = node.name }
  for k, v in pairs(node.props or {}) do t[k] = v end
  if node.children and #node.children > 0 then
    t.Children = {}
    for i, c in ipairs(node.children) do t.Children[i] = toTable(c) end
  end
  return t
end

function B.serialise(m)
  local t = {}
  for k, v in pairs(m.root or {}) do t[k] = v end
  t.Children = {}
  for i, c in ipairs(m.children) do t.Children[i] = toTable(c) end
  return serialiseValue(t, "") .. "\n"
end

function B.newNode(m, typeName)
  local name = model.uniqueName(m, typeName)
  name = name:sub(1, 1):upper() .. name:sub(2)
  local node = { type = typeName, name = name, props = model.copy(NEW[typeName] or {}) }
  node.props.X, node.props.Y = 2, 2
  return node
end

local function resolve(value, parentSize)
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end
  local total = 0
  for part in value:gmatch("[^,]+") do
    part = part:gsub("%s", "")
    if part:sub(-1) == "%" then
      total = total + math.ceil(parentSize * (tonumber(part:sub(1, -2)) or 0) / 100)
    else
      total = total + (tonumber(part) or 0)
    end
  end
  return total
end
B.resolve = resolve

local function shift(value, delta)
  if type(value) ~= "string" then return (tonumber(value) or 0) + delta end
  local pct, offset = nil, 0
  for part in value:gmatch("[^,]+") do
    part = part:gsub("%s", "")
    if part:sub(-1) == "%" then pct = part else offset = offset + (tonumber(part) or 0) end
  end
  offset = offset + delta
  if not pct then return offset end
  if offset == 0 then return pct end
  return pct .. "," .. offset
end
B.shift = shift

local function prop(node, key)
  local p = node.props or {}
  if p[key] ~= nil then return p[key] end
  local d = DEFAULTS[node.type]
  return d and d[key]
end

local function colour(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then
    if value == "transparent" then return nil end
    local c = colours[value] or colors[value]
    if type(c) == "number" then return c end
  end
  return nil
end
B.colorValue = colour

local function sizeOf(node, pw, ph)
  local p = node.props or {}
  local w = resolve(p.Width, pw)
  local h = resolve(p.Height, ph) or 1
  if not w then
    local text = tostring(prop(node, "Text") or "")
    if node.type == "Button" then w = #text + 2
    elseif node.type == "Label" then w = math.max(1, #text)
    else w = resolve((DEFAULTS[node.type] or {}).Width, pw) or 1 end
  end
  return math.max(1, w), math.max(1, h)
end

function B.build(area, m, ox, oy, theme)
  local rects = {}
  local canvas
  local function layout()
    rects = {}
    local function place(list, px, py, pw, ph)
      for _, n in ipairs(list or {}) do
        local x = resolve(prop(n, "X"), pw) or 1
        local y = resolve(prop(n, "Y"), ph) or 1
        local w, h = sizeOf(n, pw, ph)
        rects[n] = { px + x - 1, py + y - 1, w, h }
        if n.children then place(n.children, px + x - 1, py + y - 1, w, h) end
      end
    end
    place(m.children, 1, 1, m.width, m.height)
  end

  local function fill(buf, x, y, w, h, bg)
    if bg then buf:fill(x, y, w, h, " ", colors.white, bg) end
  end
  local function text(buf, x, y, s, fg, bg, maxW)
    if maxW and maxW < 1 then return end
    s = maxW and s:sub(1, maxW) or s
    if s ~= "" then buf:blit(x, y, s, fg or colors.black, bg) end
  end

  local function drawNode(buf, n)
    local r = rects[n]
    if not r then return end
    local x, y, w, h = r[1], r[2], r[3], r[4]
    local bg = colour(prop(n, "BackgroundColour"))
    local fg = colour(prop(n, "TextColour")) or colors.black
    local t = n.type
    if t == "Button" then
      fill(buf, x, y, w, h, bg)
      local s = tostring(prop(n, "Text") or "")
      local align = prop(n, "Align")
      local tx = x + 1
      if align == "Center" then tx = x + math.floor((w - #s) / 2) elseif align == "Right" then tx = x + w - #s - 1 end
      text(buf, tx, y - 1 + math.ceil(h / 2), s, fg, bg, w)
    elseif t == "Label" then
      fill(buf, x, y, w, h, bg)
      text(buf, x, y, tostring(prop(n, "Text") or ""), fg, bg, w)
    elseif t == "TextBox" or t == "SecureTextBox" then
      fill(buf, x, y, w, h, bg or colors.lightGray)
      local value = tostring(prop(n, "Text") or "")
      if t == "SecureTextBox" then value = string.rep(prop(n, "MaskCharacter") or "*", #value) end
      if value == "" then
        text(buf, x + 1, y, tostring(prop(n, "Placeholder") or ""), colour(prop(n, "PlaceholderTextColour")) or colors.gray, bg, w - 1)
      else
        text(buf, x + 1, y, value, fg, bg, w - 1)
      end
    elseif t == "NumberBox" then
      fill(buf, x, y, w, h, bg)
      text(buf, x, y, "-", colors.black, bg)
      text(buf, x + w - 1, y, "+", colors.black, bg)
      text(buf, x + 2, y, tostring(prop(n, "Value") or 1), fg, bg, w - 3)
    elseif t == "ProgressBar" then
      fill(buf, x, y, w, h, bg)
      local value, max = tonumber(prop(n, "Value")) or 0, tonumber(prop(n, "Maximum")) or 1
      local bw = math.floor(math.max(0, math.min(1, value / max)) * w + 0.5)
      if bw > 0 then fill(buf, x, y, bw, h, colour(prop(n, "BarColour")) or colors.blue) end
    elseif t == "Separator" then
      local ch = w > h and "-" or "|"
      local sc = colour(prop(n, "Colour")) or colors.gray
      for yy = y, y + h - 1 do text(buf, x, yy, string.rep(ch, w), sc, nil) end
    elseif t == "ImageView" then
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          buf:blit(xx, yy, " ", colors.white, (xx + yy) % 2 == 0 and colors.lightGray or colors.gray)
        end
      end
      text(buf, x, y, ("image"):sub(1, w), colors.white, colors.gray)
    elseif t == "ListView" then
      fill(buf, x, y, w, h, bg or colors.white)
      text(buf, x + 1, y, "Item 1", fg, bg, w - 1)
      if h > 2 then text(buf, x + 1, y + 2, "Item 2", fg, bg, w - 1) end
    elseif DEFAULTS[t] then
      fill(buf, x, y, w, h, bg)
    else

      fill(buf, x, y, w, h, bg or colors.gray)
      text(buf, x, y, t:sub(1, w), colors.white, bg or colors.gray)
    end
    for _, c in ipairs(n.children or {}) do drawNode(buf, c) end
  end

  canvas = area:addCanvas({
    x = ox, y = oy, width = m.width, height = m.height, z = 1,
    background = colour((m.root or {}).BackgroundColour) or colors.black,
    draw = function(_, buf)
      layout()
      for _, n in ipairs(m.children) do drawNode(buf, n) end
    end,
  })
  layout()
  local surface = {}
  function surface.rect(node)
    local r = rects[node]
    if not r then return nil end
    return r[1], r[2], r[3], r[4]
  end
  function surface.update() layout(); canvas:markRenderDirty() end
  function surface.moveTo(x, y) canvas.x, canvas.y = x, y end
  function surface.destroy() canvas:destroy() end
  function surface.parentSize(node)

    for _, e in ipairs(model.walk(m)) do
      if e.node == node then
        if e.parent then local r = rects[e.parent]; return r[3], r[4] end
        return m.width, m.height
      end
    end
    return m.width, m.height
  end
  return surface
end

function B.position(node, surface)
  local p = node.props or {}
  local _, _, w, h = surface.rect(node)
  return { X = p.X or 1, Y = p.Y or 1, Width = p.Width or w or 1, Height = p.Height or h or 1 }
end

function B.move(node, start, dx, dy)
  node.props = node.props or {}
  node.props.X = shift(start.X, dx)
  node.props.Y = shift(start.Y, dy)
end

function B.resize(node, start, dw, dh)
  node.props = node.props or {}
  node.props.Width = shift(start.Width, dw)
  node.props.Height = shift(start.Height, dh)
  if type(node.props.Width) == "number" then node.props.Width = math.max(1, node.props.Width) end
  if type(node.props.Height) == "number" then node.props.Height = math.max(1, node.props.Height) end
end

local function kindOf(key, value)
  if SIZE_KEYS[key] then return "size" end
  if key:find("Colou?r$") then return "color" end
  if type(value) == "boolean" then return "boolean" end
  if type(value) == "number" then return "number" end
  return "string"
end

function B.inspector(node)
  local rows, seen = {}, {}
  local function add(key)
    if seen[key] then return end
    seen[key] = true
    local own = node.props and node.props[key]
    local default = own == nil
    local value = own
    if default then value = (DEFAULTS[node.type] or {})[key] end
    rows[#rows + 1] = { name = key, kind = kindOf(key, value), value = value, default = default }
  end
  for _, k in ipairs({ "X", "Y", "Width", "Height" }) do add(k) end
  if (DEFAULTS[node.type] or {}).Text ~= nil or (node.props or {}).Text ~= nil then add("Text") end
  local rest = {}
  for k in pairs(DEFAULTS[node.type] or {}) do rest[#rest + 1] = k end
  for k in pairs(node.props or {}) do rest[#rest + 1] = k end
  table.sort(rest)
  for _, k in ipairs(rest) do add(k) end
  return rows
end

function B.rootRows(m)
  return { { name = "BackgroundColour", kind = "color", value = (m.root or {}).BackgroundColour } }
end

function B.setRoot(m, name, value)
  m.root = m.root or {}
  m.root[name] = value
end

function B.colorChoices()
  local out = { { label = "transparent", value = "transparent" } }
  for _, n in ipairs(COLOR_ORDER) do out[#out + 1] = { label = n, value = n } end
  return out
end

function B.colorLabel(v)
  if v == nil then return "none" end
  if type(v) == "number" then
    for _, n in ipairs(COLOR_ORDER) do if colours[n] == v then return n end end
  end
  return tostring(v)
end

local function parseObjectSource(src)
  local props, inherit = {}, nil
  for line in src:gmatch("[^\n]+") do
    if line:match("^%s*function") or line:match("=%s*function") then break end
    local key, value = line:match("^([%u][%w]*)%s*=%s*(.-)%s*$")
    if key then
      local v
      local str = value:match("^'(.*)'$") or value:match('^"(.*)"$')
      if str then v = str
      elseif value:match("^colou?rs%.(%w+)$") then v = value:match("^colou?rs%.(%w+)$")
      elseif tonumber(value) then v = tonumber(value)
      elseif value == "true" then v = true
      elseif value == "false" then v = false end
      if key == "Inherit" then inherit = v
      elseif v ~= nil and key ~= "Name" and key ~= "Parent" then props[key] = v end
    end
  end
  return props, inherit
end

local BASE_TYPES, BASE_DEFAULTS, BASE_CONTAINERS = {}, {}, {}
for i, t in ipairs(B.TYPES) do BASE_TYPES[i] = t end
for k, v in pairs(DEFAULTS) do BASE_DEFAULTS[k] = v end
for k, v in pairs(CONTAINERS) do BASE_CONTAINERS[k] = v end

function B.forProject(root)
  for k in pairs(DEFAULTS) do DEFAULTS[k] = nil end
  for k, v in pairs(BASE_DEFAULTS) do DEFAULTS[k] = v end
  for k in pairs(CONTAINERS) do CONTAINERS[k] = nil end
  for k, v in pairs(BASE_CONTAINERS) do CONTAINERS[k] = v end
  local types, seen = {}, {}
  for _, t in ipairs(BASE_TYPES) do types[#types + 1] = t; seen[t] = true end
  local custom = {}
  local function addType(name, props, inherit)
    if inherit and (inherit == "View" or inherit == "ScrollView" or CONTAINERS[inherit]) then CONTAINERS[name] = true end
    local merged = {}
    if inherit and DEFAULTS[inherit] then for k, v in pairs(DEFAULTS[inherit]) do merged[k] = v end end
    for k, v in pairs(props) do merged[k] = v end
    DEFAULTS[name] = merged
    if not seen[name] then seen[name] = true; custom[#custom + 1] = name end
  end
  local function scan(dir, depth)
    if depth > 3 or not fs.isDir(dir) then return end
    for _, name in ipairs(fs.list(dir)) do
      local path = fs.combine(dir, name)
      if fs.isDir(path) then
        if name == "Objects" then
          for _, f in ipairs(fs.list(path)) do
            local objName = f:match("^(%u[%w]*)%.lua$")
            if objName then
              local h = fs.open(fs.combine(path, f), "r")
              if h then
                local props, inherit = parseObjectSource(h.readAll() or "")
                h.close()
                addType(objName, props, inherit)
              end
            end
          end
        elseif name ~= "rom" and name:sub(1, 1) ~= "." then
          scan(path, depth + 1)
        end
      elseif name == "Bedrock" or name == "Bedrock.lua" then
        local h = fs.open(path, "r")
        local src = h and h.readAll() or ""
        if h then h.close() end
        for objName, body in src:gmatch('%["(%u[%w]*)"%]%s*=%s*%[%[(.-)%]%]') do
          if objName ~= "Drawing" and objName ~= "Helpers" and objName ~= "Object" and not BASE_DEFAULTS[objName] then
            local props, inherit = parseObjectSource(body)
            addType(objName, props, inherit)
          end
        end
      end
    end
  end
  if root then scan(root, 0) end
  table.sort(custom)
  for _, t in ipairs(custom) do types[#types + 1] = t end
  B.TYPES = types
  return B
end

return B

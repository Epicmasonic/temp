local M = {}

M.TYPES = { "Label", "Button", "Input", "Checkbox", "Switch", "ProgressBar", "Slider",
  "List", "Dropdown", "TextBox", "Frame" }
M.CONTAINERS = { Frame = true }

M.DEFAULTS = {
  Label = { text = "Label" },
  Button = { text = "Button" },
  Input = { placeholder = "Type here" },
  Checkbox = { text = "Option" },
  Switch = {},
  ProgressBar = { progress = 50 },
  Slider = { value = 50 },
  List = {},
  Dropdown = { text = "Select..." },
  TextBox = {},
  Frame = {},
}

M.COMMON = { "x", "y", "width", "height", "text", "foreground", "background" }

local SKIP = {
  z = true, position = true, alignSelf = true, shrink = true, minWidth = true, maxWidth = true,
  minHeight = true, maxHeight = true, name = true, offset = true, open = true, draggingMap = true,
  horizontalOffset = true, scrollX = true, scrollY = true, cursor = true, selected = true,
}

local COLOR_NAMES = {}
for name, value in pairs(colors) do
  if type(value) == "number" then COLOR_NAMES[value] = COLOR_NAMES[value] or name end
end
COLOR_NAMES[colors.gray] = "gray"; COLOR_NAMES[colors.lightGray] = "lightGray"
M.COLOR_NAMES = COLOR_NAMES
M.COLOR_ORDER = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
  "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }

local function isColorProp(name)
  return name == "foreground" or name == "background" or name:match("Color$") ~= nil
    or name:match("Background$") ~= nil or name:match("Foreground$") ~= nil
end
M.isColorProp = isColorProp

function M.new(width, height)
  return { width = width or 51, height = height or 19,
    background = colors.black, children = {} }
end

function M.walk(model)
  local out = {}
  local function visit(list, parent)
    for _, n in ipairs(list or {}) do
      out[#out + 1] = { node = n, parent = parent }
      if n.children then visit(n.children, n) end
    end
  end
  visit(model.children, nil)
  return out
end

function M.uniqueName(model, typeName)
  local base = typeName:sub(1, 1):lower() .. typeName:sub(2)
  local used = {}
  for _, e in ipairs(M.walk(model)) do used[e.node.name or ""] = true end
  local i = 1
  while used[base .. i] do i = i + 1 end
  return base .. i
end

function M.properties(classes, typeName)
  local cls = classes[typeName]
  if not cls then return {} end
  local defaults, props = cls.__defaults, cls.__props
  local list, seen = {}, {}
  local function add(name)
    if seen[name] or SKIP[name] then return end
    local meta = props[name]
    if not meta or meta.rawFunction then return end
    local def = defaults[name]
    local kind
    if isColorProp(name) then kind = "color"
    elseif type(def) == "number" or (type(def) == "function" and (name == "width" or name == "height")) then kind = "number"
    elseif type(def) == "string" then kind = "string"
    elseif type(def) == "boolean" then kind = "boolean"
    elseif def == nil or def == false then kind = "string"
    end
    if kind then seen[name] = true; list[#list + 1] = { name = name, kind = kind } end
  end
  for _, name in ipairs(M.COMMON) do add(name) end

  local rest, seenName = {}, {}
  local t = props
  while type(t) == "table" do
    for name in pairs(t) do
      if not seenName[name] then seenName[name] = true; rest[#rest + 1] = name end
    end
    local mt = getmetatable(t)
    t = mt and mt.__index
  end
  table.sort(rest)
  for _, name in ipairs(rest) do add(name) end
  return list
end

function M.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = M.copy(v) end
  return out
end

return M

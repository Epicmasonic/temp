
local model = require("pineapple.studio.plugins.designer.model")

return function(basalt)
  local classes = basalt.use("theme").classes
  local xml = basalt.use("xml")
  local B = { id = "basalt" }

  local SKIP = { Element = true, Container = true, BaseFrame = true, Collection = true,
    ContextMenu = true, Dialog = true, Toast = true, Program = true }
  local frameClass = classes.Frame
  B.TYPES = {}
  for name in pairs(classes) do
    if not SKIP[name] and frameClass and type(frameClass["add" .. name]) == "function" then
      B.TYPES[#B.TYPES + 1] = name
    end
  end
  table.sort(B.TYPES)

  function B.isContainer(t)
    local cls = classes[t]
    return cls ~= nil and type(cls.addLabel) == "function"
  end
  function B.newModel() return model.new() end

  local function valueFromXML(value)
    local number = tonumber(value)
    if number then return number end
    if value == "true" then return true end
    if value == "false" then return false end
    if value:sub(1, 1) == "#" then return basalt.rgb(value) end
    return value
  end

  local function typeFromTag(tag)
    return tag:sub(1, 1):upper() .. tag:sub(2)
  end

  function B.parse(text)
    if not text:match("%S") then return model.new() end
    local ok, roots = pcall(xml.parse, text)
    if not ok then return nil, tostring(roots) end
    local m = model.new()
    local nodes = roots
    if #roots == 1 and typeFromTag(roots[1].tag) == "Frame" then
      local root = roots[1]
      m.width = tonumber(root.attrs.width) or m.width
      m.height = tonumber(root.attrs.height) or m.height
      if root.attrs.background then m.background = valueFromXML(root.attrs.background) end
      nodes = root.children
    end

    local usedNames = {}
    local function nextName(typeName)
      local base = typeName:sub(1, 1):lower() .. typeName:sub(2)
      local index = 1
      while usedNames[base .. index] do index = index + 1 end
      local name = base .. index
      usedNames[name] = true
      return name
    end

    local function readNodes(xmlNodes)
      local out = {}
      for _, source in ipairs(xmlNodes or {}) do
        local typeName = typeFromTag(source.tag)
        if not classes[typeName] then
          error("Basalt XML: unknown element <" .. source.tag .. ">")
        end
        local props, name = {}, nil
        for key, value in pairs(source.attrs or {}) do
          if key == "name" then name = value
          else props[key] = valueFromXML(value) end
        end
        if source.text and props.text == nil and classes[typeName].__props.text then
          props.text = source.text
        end
        name = name or nextName(typeName)
        usedNames[name] = true
        local node = { type = typeName, name = name, props = props }
        if #source.children > 0 then node.children = readNodes(source.children) end
        out[#out + 1] = node
      end
      return out
    end

    local parsed, result = pcall(readNodes, nodes)
    if not parsed then return nil, tostring(result) end
    m.children = result
    return m
  end

  local function attributeValue(value)
    local text = tostring(value)
    if text:find("[&<>]") then
      error("Basalt XML does not support &, <, or > in attribute values")
    end
    if not text:find('"', 1, true) then return '"' .. text .. '"' end
    if not text:find("'", 1, true) then return "'" .. text .. "'" end
    error("Basalt XML cannot represent an attribute containing both quote types")
  end

  local function tagForType(typeName)
    return typeName:sub(1, 1):lower() .. typeName:sub(2)
  end

  function B.serialise(m)
    local out = {
      '<frame name="pineappleRoot" width=' .. attributeValue(m.width or 51)
        .. ' height=' .. attributeValue(m.height or 19)
        .. ' background=' .. attributeValue(m.background or colors.black) .. '>',
    }
    local function writeNodes(nodes, depth)
      for _, node in ipairs(nodes or {}) do
        local attrs = { "name=" .. attributeValue(node.name or model.uniqueName(m, node.type)) }
        local keys = {}
        for key in pairs(node.props or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
          if not key:match("^[%a_][%w_]*$") then error("Invalid XML attribute name: " .. key) end
          attrs[#attrs + 1] = key .. "=" .. attributeValue(node.props[key])
        end
        local indent = string.rep("  ", depth)
        local start = indent .. "<" .. tagForType(node.type) .. " " .. table.concat(attrs, " ")
        if node.children and #node.children > 0 then
          out[#out + 1] = start .. ">"
          writeNodes(node.children, depth + 1)
          out[#out + 1] = indent .. "</" .. tagForType(node.type) .. ">"
        else
          out[#out + 1] = start .. "/>"
        end
      end
    end
    writeNodes(m.children, 1)
    out[#out + 1] = "</frame>"
    return table.concat(out, "\n") .. "\n"
  end

  function B.newNode(m, typeName)
    local props = model.copy(model.DEFAULTS[typeName] or {})
    local cls = classes[typeName]
    if not model.DEFAULTS[typeName] and cls and cls.__defaults.text == "" then props.text = typeName end
    local node = { type = typeName, name = model.uniqueName(m, typeName), props = props }
    node.props.x, node.props.y = 2, 2
    return node
  end

  function B.build(area, m, ox, oy)
    local elements = {}
    local frame = area:addFrame({
      x = ox, y = oy, width = m.width, height = m.height, z = 1,
      background = m.background or colors.black,
    })
    local parents = {}
    local function add(list, parentEl, parentNode)
      for _, n in ipairs(list or {}) do
        local p = model.copy(n.props or {})
        for key in pairs(p) do
          if key:match("^on%u") then p[key] = nil end
        end
        p.name = n.name
        local ok, el = pcall(function() return parentEl["add" .. n.type](parentEl, p) end)
        if ok and el then
          elements[n] = el
          parents[n] = parentNode
          if n.children then add(n.children, el, n) end
        end
      end
    end
    add(m.children, frame, nil)
    local surface = {}
    function surface.rect(node)
      local el = elements[node]
      if not el then return nil end
      local x, y = el.x, el.y
      local p = parents[node]
      while p do
        local pe = elements[p]
        x, y = x + pe.x - 1, y + pe.y - 1
        p = parents[p]
      end
      return x, y, el.width, el.height
    end
    function surface.update(node)
      local el = elements[node]
      if not el then return end
      local props = node.props or {}
      for _, k in ipairs({ "x", "y", "width", "height" }) do
        if props[k] ~= nil then el[k] = props[k] end
      end
      area:markDirty()
    end
    function surface.moveTo(x, y) frame.x, frame.y = x, y end
    function surface.destroy() frame:destroy() end
    function surface.elementOf(node) return elements[node] end
    return surface
  end

  function B.position(node, surface)
    local el = surface.elementOf(node)
    local p = node.props or {}
    return { x = p.x or (el and el.x) or 1, y = p.y or (el and el.y) or 1,
      w = p.width or (el and el.width) or 1, h = p.height or (el and el.height) or 1 }
  end

  function B.move(node, start, dx, dy)
    node.props = node.props or {}
    node.props.x, node.props.y = start.x + dx, start.y + dy
  end

  function B.resize(node, start, dw, dh)
    node.props = node.props or {}
    node.props.width = math.max(1, start.w + dw)
    node.props.height = math.max(1, start.h + dh)
  end

  function B.inspector(node, surface)
    local rows = {}
    local cls = classes[node.type]
    local el = surface and surface.elementOf(node)
    for _, p in ipairs(model.properties(classes, node.type)) do
      local own = node.props and node.props[p.name]
      local value, default = own, false
      if own == nil then
        default = true
        value = el and el[p.name]
        if value == nil and cls then value = cls.__defaults[p.name] end
      end
      rows[#rows + 1] = { name = p.name, kind = p.kind, value = value, default = default }
    end
    return rows
  end

  function B.rootRows(m)
    return { { name = "background", kind = "color", value = m.background } }
  end

  function B.setRoot(m, name, value)
    if name == "background" then m.background = value or colors.black end
  end

  function B.colorChoices(isRoot)
    local out = {}
    if not isRoot then out[1] = { label = "none", value = false } end
    for _, n in ipairs(model.COLOR_ORDER) do out[#out + 1] = { label = n, value = colors[n] } end
    return out
  end

  function B.colorLabel(v)
    if v == false or v == nil then return "none" end
    return model.COLOR_NAMES[v] or tostring(v)
  end

  function B.colorValue(v)
    if type(v) == "number" then return v end
    return nil
  end

  return B
end

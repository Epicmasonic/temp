local M = {}

local function escape(s) return (s:gsub("%p", "%%%0")) end

function M.target(lines, line, col)
  local text = lines[line]
  if not text then return nil end

  for s, quote, mod, e in text:gmatch("()require%s*%(?%s*(['\"])([^'\"]+)%2%s*%)?()") do
    if col >= s and col <= e then return { kind = "require", module = mod } end
  end
  local s, e = col, col
  while s > 1 and text:sub(s - 1, s - 1):match("[%w_]") do s = s - 1 end
  while e <= #text and text:sub(e, e):match("[%w_]") do e = e + 1 end
  if e == s then

    if col > 1 and text:sub(col - 1, col - 1):match("[%w_]") then return M.target(lines, line, col - 1) end
    return nil
  end
  local name = text:sub(s, e - 1)
  if name:match("^%d") then return nil end
  local sep = text:sub(s - 1, s - 1)
  local base
  if sep == "." or sep == ":" then
    base = text:sub(1, s - 2):match("([%a_][%w_]*)$")
    if text:sub(s - 2, s - 2) == "." then base = nil end
  else
    sep = nil
  end
  return { kind = "name", name = name, base = base, sep = base and sep or nil, line = line, col = s }
end

function M.find(lines, target, fromLine)
  local name = target.name
  local n = escape(name)
  local found = {}
  local function add(i, col) found[#found + 1] = { line = i, col = col } end
  if target.base then
    local b = escape(target.base)
    for i, text in ipairs(lines) do
      local col = text:find("function%s+" .. b .. "[%.:]" .. n .. "%s*%(")
        or text:find("^%s*" .. b .. "%." .. n .. "%s*=")
      if col then add(i, (text:find(name, col, true))) end
    end
    if #found == 0 then

      for i, text in ipairs(lines) do
        local col = text:find("^%s*" .. n .. "%s*=[^=]")
        if col then add(i, (text:find(name, 1, true))) end
      end
    end
    return found
  end
  local patterns = {
    "local%s+function%s+" .. n .. "%s*%(",
    "^%s*function%s+" .. n .. "%s*%(",
    "local%s+[%w_,%s]-%f[%w_]" .. n .. "%f[^%w_][%w_,%s]-=",
    "local%s+[%w_,%s]-%f[%w_]" .. n .. "%s*$",
    "for%s+[%w_,%s]-%f[%w_]" .. n .. "%f[^%w_][%w_,%s]-[=i]",
    "function[%w_%.:%s]*%([^%)]-%f[%w_]" .. n .. "%f[^%w_]",
    "^%s*" .. n .. "%s*=[^=]",
  }
  for i, text in ipairs(lines) do
    local code = text:gsub("%-%-.*$", "")
    for _, p in ipairs(patterns) do
      local s = code:find(p)
      if s then
        local col = code:find("%f[%w_]" .. n .. "%f[^%w_]", s)
        if col and not (i == target.line and col == target.col) then add(i, col) end
        break
      end
    end
  end

  table.sort(found, function(a, b)
    local aAbove, bAbove = a.line <= (fromLine or 0), b.line <= (fromLine or 0)
    if aAbove ~= bAbove then return aAbove end
    if aAbove then return a.line > b.line end
    return a.line < b.line
  end)
  return found
end

function M.modulePaths(root, module)
  local rel = module:gsub("%.", "/")
  local out = {}
  for _, dir in ipairs({ "", "src", "lib" }) do
    out[#out + 1] = fs.combine(fs.combine(root, dir), rel .. ".lua")
    out[#out + 1] = fs.combine(fs.combine(root, dir), rel .. "/init.lua")
  end
  return out
end

return M

local M = {}

function M.files(ws, max, depth)
  max, depth = max or 2000, depth or 10
  local out = {}
  local function walk(dir, level)
    if level > depth or #out >= max then return end
    for _, entry in ipairs(ws:list(dir)) do
      if #out >= max then return end
      if entry.isDir then walk(entry.path, level + 1)
      else out[#out + 1] = entry.path end
    end
  end
  walk("", 0)
  return out
end

function M.lines(ws, path, maxBytes)
  local doc = ws.getDocument and ws:getDocument(path)
  if doc then return doc.lines end
  if not fs.exists(path) or fs.isDir(path) then return nil end
  if fs.getSize(path) > (maxBytes or 200000) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll() or ""
  h.close()
  local out = {}
  for line in (text:gsub("\r\n?", "\n") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  if #out > 1 and out[#out] == "" and text:sub(-1) == "\n" then out[#out] = nil end
  return out
end

local SYMBOL_PATTERNS = {
  "^%s*local%s+function%s+([%w_]+)%s*(%b())",
  "^%s*function%s+([%w_%.:]+)%s*(%b())",
  "^%s*local%s+([%w_]+)%s*=%s*function%s*(%b())",
  "^%s*([%w_%.]+)%s*=%s*function%s*(%b())",
}

function M.symbols(lines)
  local out = {}
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(SYMBOL_PATTERNS) do
      local name, params = line:match(pattern)
      if name then
        out[#out + 1] = { name = name, params = params, line = i, col = (line:find(name, 1, true) or 1) }
        break
      end
    end
  end
  return out
end

function M.grep(lines, query, caseSensitive, max)
  local out = {}
  if query == "" then return out end
  local q = caseSensitive and query or query:lower()
  for i, line in ipairs(lines) do
    local hay = caseSensitive and line or line:lower()
    local col = hay:find(q, 1, true)
    if col then
      out[#out + 1] = { line = i, col = col, text = line }
      if max and #out >= max then break end
    end
  end
  return out
end

function M.findAll(lines, query, caseSensitive, max)
  local out = {}
  if query == "" then return out end
  local q = caseSensitive and query or query:lower()
  max = max or 5000
  for i, line in ipairs(lines) do
    local hay = caseSensitive and line or line:lower()
    local start = 1
    while true do
      local s = hay:find(q, start, true)
      if not s then break end
      out[#out + 1] = { line = i, col = s, len = #query }
      if #out >= max then return out end
      start = s + #query
    end
  end
  return out
end

return M

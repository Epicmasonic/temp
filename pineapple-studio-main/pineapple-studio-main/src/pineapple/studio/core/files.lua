local M = {}

function M.read(path)
  local h, err = fs.open(path, "r")
  if not h then return nil, err or ("cannot open " .. path) end
  local text = h.readAll() or ""
  h.close()
  return text
end

function M.write(path, text)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h, err = fs.open(path, "w")
  if not h then return nil, err or ("cannot write " .. path) end
  h.write(text)
  h.close()
  return true
end

function M.readTable(path)
  if not fs.exists(path) then return {} end
  local text, err = M.read(path)
  if not text then return nil, err end
  if text:match("^%s*$") then return {} end
  local value = textutils.unserialise(text)
  if type(value) ~= "table" then return nil, path .. " is not a valid Lua table" end
  return value
end

function M.writeTable(path, value)
  return M.write(path, textutils.serialise(value))
end

function M.join(...)
  return "/" .. fs.combine(...)
end

return M

local M = {}

local HEX = "0123456789abcdef"

local function size(frames)
  local w, h = 0, 0
  for _, f in ipairs(frames) do
    h = math.max(h, #f)
    for _, row in ipairs(f) do w = math.max(w, #row[1]) end
  end
  return w, h
end

function M.nfp(text)
  local rows = {}
  for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    local bg = line:lower():gsub("[^0-9a-f]", " ")
    rows[#rows + 1] = { string.rep(" ", #bg), string.rep("0", #bg), bg }
  end
  while #rows > 0 and rows[#rows][3]:match("^%s*$") do rows[#rows] = nil end
  local w, h = size({ rows })
  return { width = w, height = h, frames = { rows }, format = "nfp" }
end

function M.nft(text)
  local rows = {}
  for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    local t, f, b = {}, {}, {}
    local fg, bg = "0", "f"
    local i = 1
    while i <= #line do
      local c = line:sub(i, i)
      if c == "\31" and i < #line then
        i = i + 1; fg = line:sub(i, i)
      elseif c == "\30" and i < #line then
        i = i + 1; bg = line:sub(i, i)
      else
        t[#t + 1] = c; f[#f + 1] = fg; b[#b + 1] = bg
      end
      i = i + 1
    end
    rows[#rows + 1] = { table.concat(t), table.concat(f), table.concat(b) }
  end
  while #rows > 0 and rows[#rows][1] == "" do rows[#rows] = nil end
  local w, h = size({ rows })
  return { width = w, height = h, frames = { rows }, format = "nft" }
end

function M.bimg(text)
  local data = textutils.unserialise(text)
  if type(data) ~= "table" then return nil, "not a valid bimg file" end
  local frames = {}
  for i, frame in ipairs(data) do
    if type(frame) ~= "table" then return nil, "frame " .. i .. " isn't a table" end
    local rows = { palette = frame.palette or data.palette }
    for j, row in ipairs(frame) do
      if type(row) ~= "table" or type(row[1]) ~= "string" then return nil, "frame " .. i .. ", row " .. j .. " is malformed" end
      rows[j] = { row[1], row[2] or string.rep("0", #row[1]), row[3] or string.rep("f", #row[1]) }
    end
    frames[i] = rows
  end
  if #frames == 0 then return nil, "the file has no frames" end
  local w, h = size(frames)
  local info = {}
  for _, key in ipairs({ "title", "author", "description", "creator", "date" }) do
    if type(data[key]) == "string" then info[key] = data[key] end
  end
  return {
    width = w, height = h, frames = frames, format = "bimg", info = info,
    secondsPerFrame = tonumber(data.secondsPerFrame) or 0.5,
    animated = data.animation == true or #frames > 1,
  }
end

function M.load(path, text)
  local ext = path:match("%.(%w+)$")
  ext = ext and ext:lower()
  if ext == "nfp" then return M.nfp(text) end
  if ext == "nft" then return M.nft(text) end
  if ext == "bimg" then return M.bimg(text) end
  return nil, "unknown image format"
end

local DEFAULTS = { 0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2, 0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
  0x999999, 0x4C99B2, 0xB266E5, 0x3366CC, 0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111 }

local function rgbOf(entry)
  if type(entry) == "number" then
    return math.floor(entry / 65536) % 256 / 255, math.floor(entry / 256) % 256 / 255, entry % 256 / 255
  elseif type(entry) == "table" then
    return entry[1] or 0, entry[2] or 0, entry[3] or 0
  end
end

function M.paletteMap(palette)
  local map = {}
  for i = 0, 15 do
    local c = HEX:sub(i + 1, i + 1)
    map[c] = c
    local r, g, b = rgbOf(palette and palette[i])
    if r then
      local best, bestD = c, math.huge
      for j, def in ipairs(DEFAULTS) do
        local dr, dg, db = rgbOf(def)
        local d = (r - dr) ^ 2 + (g - dg) ^ 2 + (b - db) ^ 2
        if d < bestD then best, bestD = HEX:sub(j, j), d end
      end
      map[c] = best
    end
  end
  return map
end

function M.colour(ch)
  local n = tonumber(ch, 16)
  return n and 2 ^ n or nil
end

return M

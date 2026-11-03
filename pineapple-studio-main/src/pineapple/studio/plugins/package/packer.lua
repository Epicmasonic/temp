local M = {}

M.PASTEBIN_KEY = "0ec2eb25b6166c0c27a394ae118ad829"
M.PASTEBIN_LIMIT = 512 * 1024
M.PASTEBIN_CHUNK_SIZE = 50000

local function excluder(patterns)
  local tests = {}
  for _, p in ipairs(patterns or {}) do
    p = p:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^/", "")
    if p ~= "" then
      local dirOnly = p:sub(-1) == "/"
      if dirOnly then p = p:sub(1, -2) end
      local lua = "^" .. p:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", "[^/]*"):gsub("%?", "[^/]") .. "$"
      tests[#tests + 1] = function(rel, name, isDir)
        if dirOnly and not isDir then return false end
        return rel:match(lua) ~= nil or name:match(lua) ~= nil
      end
    end
  end
  return function(rel, name, isDir)
    for _, t in ipairs(tests) do if t(rel, name, isDir) then return true end end
    return false
  end
end

local function readBinary(path)
  local h = fs.open(path, "rb")
  if not h then return nil end
  local data = h.readAll() or ""
  h.close()
  return data
end

function M.collect(root, opts)
  opts = opts or {}
  local yield = opts.yield or function() end
  local skip = {}
  for _, p in ipairs(opts.skip or {}) do skip[fs.combine(p)] = true end
  local excluded = excluder(opts.exclude)
  local files, total = {}, 0
  local function walk(dir, rel)
    local names = fs.list(dir)
    table.sort(names)
    for _, name in ipairs(names) do
      local path = fs.combine(dir, name)
      local r = rel == "" and name or (rel .. "/" .. name)
      local isDir = fs.isDir(path)
      if name:sub(1, 1) ~= "." and not skip[r] and not excluded(r, name, isDir) then
        if isDir then
          walk(path, r)
        else
          local data = readBinary(path)
          if #files % 10 == 9 then yield() end
          if data then
            files[#files + 1] = { path = r, data = data }
            total = total + #data
          end
        end
      end
    end
  end
  walk(root, "")
  return files, total
end

function M.quote(s)
  if not s:find("[^\t\n\32-\126]") then
    local level = 0
    while s:find("]" .. string.rep("=", level) .. "]", 1, true) do level = level + 1 end
    local eq = string.rep("=", level)

    return "[" .. eq .. "[\n" .. s .. "]" .. eq .. "]"
  end
  return '"' .. s:gsub('[%c"\\\128-\255]', function(c)
    if c == "\n" then return "\\n" end
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\%03d", c:byte())
  end) .. '"'
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.compress(s, yield)

  local dict, nextCode = {}, 256

  local digit = {}
  for i = 1, 64 do digit[i - 1] = B64:byte(i) end
  local bytes, n, chunks = {}, 0, {}
  local function emit(code)
    bytes[n + 1] = digit[(code - code % 64) / 64]
    bytes[n + 2] = digit[code % 64]
    n = n + 2
    if n >= 4096 then
      chunks[#chunks + 1] = string.char(table.unpack(bytes, 1, n))
      n = 0
    end
  end
  local w
  for i = 1, #s do
    if yield and i % 20000 == 0 then yield() end
    local b = s:byte(i)
    if w == nil then
      w = b
    else
      local key = w * 256 + b
      local code = dict[key]
      if code then
        w = code
      else
        emit(w)
        if nextCode < 4096 then dict[key] = nextCode; nextCode = nextCode + 1 end
        w = b
      end
    end
  end
  if w then emit(w) end
  if n > 0 then chunks[#chunks + 1] = string.char(table.unpack(bytes, 1, n)) end

  local text = table.concat(chunks)
  local lines = {}
  for i = 1, #text, 128 do lines[#lines + 1] = text:sub(i, i + 127) end
  return table.concat(lines, "\n")
end

M.DECOMPRESS_SOURCE = [[
local function decompress(text)
  text = text:gsub("%s", "")
  local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local value = {}
  for i = 1, 64 do value[B64:sub(i, i)] = i - 1 end
  local dict, nextCode, out, prev = {}, 256, {}, nil
  for i = 0, 255 do dict[i] = string.char(i) end
  for i = 1, #text, 2 do
    if i % 40000 == 0 and sleep then sleep(0) end -- big packages take a while; let CC breathe
    local code = value[text:sub(i, i)] * 64 + value[text:sub(i + 1, i + 1)]
    local entry = dict[code] or (prev .. prev:sub(1, 1))
    out[#out + 1] = entry
    if prev and nextCode < 4096 then
      dict[nextCode] = prev .. entry:sub(1, 1)
      nextCode = nextCode + 1
    end
    prev = entry
  end
  return table.concat(out)
end
]]

M.decompress = load(M.DECOMPRESS_SOURCE .. "\nreturn decompress", "=decompress")()

function M.join(files)
  local parts = {}
  for _, f in ipairs(files) do parts[#parts + 1] = f.path .. "\0" .. #f.data .. "\0" .. f.data end
  return table.concat(parts)
end

local SPLIT_SOURCE = [[
local function split(data)
  local files, pos = {}, 1
  while pos <= #data do
    local a = data:find("\0", pos, true)
    local b = data:find("\0", a + 1, true)
    local length = tonumber(data:sub(a + 1, b - 1))
    files[data:sub(pos, a - 1)] = data:sub(b + 1, b + length)
    pos = b + length + 1
  end
  return files
end
]]

local function filesBlock(files, compress, yield)
  if compress then
    return M.DECOMPRESS_SOURCE .. SPLIT_SOURCE ..
      "local FILES = split(decompress([==[\n" .. M.compress(M.join(files), yield) .. "\n]==]))\n"
  end
  local out = { "local FILES = {\n" }
  for _, f in ipairs(files) do
    out[#out + 1] = "  [" .. string.format("%q", f.path) .. "] = " .. M.quote(f.data) .. ",\n"
  end
  out[#out + 1] = "}\n"
  return table.concat(out)
end

local PROGRAM_RUNTIME = [==[
local args = { ... }
local outer = _ENV
local root = fs.getDir(shell and shell.getRunningProgram() or "")
local DIRS = {}
for path in pairs(FILES) do
  local d = fs.getDir(path)
  while d ~= "" and not DIRS[d] do DIRS[d] = true; d = fs.getDir(d) end
end

-- The packed path for a real one, if it is inside this program's folder.
local function packed(path)
  path = fs.combine(path)
  if root == "" then return path end
  if path == root then return "" end
  if path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
end
local function packedFile(path)
  local p = packed(path)
  if p and FILES[p] and not fs.exists(path) then return FILES[p], p end
end

local function handle(data, binary)
  local pos, h = 1, {}
  function h.readAll() local s = data:sub(pos); pos = #data + 1; return s end
  function h.readLine(keep)
    if pos > #data then return nil end
    local nl = data:find("\n", pos, true)
    local line = data:sub(pos, nl and (keep and nl or nl - 1) or #data)
    pos = nl and nl + 1 or #data + 1
    return line
  end
  function h.read(count)
    if pos > #data then return nil end
    if count == nil and binary then pos = pos + 1; return data:byte(pos - 1) end
    count = count or 1
    local s = data:sub(pos, pos + count - 1); pos = pos + count
    return s
  end
  function h.seek(whence, offset)
    local base = whence == "set" and 0 or whence == "end" and #data or pos - 1
    pos = math.max(0, base + (offset or 0)) + 1
    return pos - 1
  end
  function h.close() end
  return h
end

local vfs = setmetatable({}, { __index = fs })
function vfs.open(path, mode)
  local data = (mode == "r" or mode == "rb") and packedFile(path)
  if data then return handle(data, mode == "rb") end
  return fs.open(path, mode)
end
function vfs.exists(path)
  local p = packed(path)
  return fs.exists(path) or (p ~= nil and (FILES[p] ~= nil or DIRS[p] ~= nil or p == ""))
end
function vfs.isDir(path)
  local p = packed(path)
  return fs.isDir(path) or (p ~= nil and (DIRS[p] ~= nil or p == ""))
end
function vfs.getSize(path)
  local data = packedFile(path)
  if data then return #data end
  return fs.getSize(path)
end
function vfs.list(path)
  local p = packed(path)
  local virtualDir = p ~= nil and (p == "" or DIRS[p] ~= nil)
  if not virtualDir then return fs.list(path) end
  local seen, out = {}, {}
  if fs.isDir(path) then
    for _, name in ipairs(fs.list(path)) do seen[name] = true; out[#out + 1] = name end
  end
  local prefix = p == "" and "" or (p .. "/")
  for file in pairs(FILES) do
    if file:sub(1, #prefix) == prefix then
      local name = file:sub(#prefix + 1):match("^[^/]+")
      if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

local env = setmetatable({ fs = vfs, arg = args }, { __index = outer })
env._ENV = env
env._G = env
function env.loadfile(path, mode, e)
  local data, p = packedFile(path)
  if data then return load(data, "@/" .. fs.combine(root, p), mode, e or env) end
  return loadfile(path, mode, e or env)
end
function env.dofile(path)
  local fn = assert(env.loadfile(path))
  return fn()
end
local loaded = {}
function env.require(name)
  if loaded[name] ~= nil then return loaded[name] end
  local base = name:gsub("%.", "/")
  for _, candidate in ipairs({ base .. ".lua", base .. "/init.lua", base, "lib/" .. base .. ".lua", "lib/" .. base .. "/init.lua" }) do
    local data = FILES[candidate]
    if data and not fs.exists(fs.combine(root, candidate)) then
      local fn = assert(load(data, "@/" .. fs.combine(root, candidate), "t", env))
      local result = fn(name)
      if result == nil then result = true end
      loaded[name] = result
      return result
    end
  end
  return outer.require(name)
end

local main = assert(load(FILES[MAIN], "@/" .. fs.combine(root, MAIN), "t", env))
return main(table.unpack(args))
]==]

function M.program(files, opts)
  opts = opts or {}
  local main = opts.main or "main.lua"
  local found = false
  for _, f in ipairs(files) do if f.path == main then found = true end end
  if not found then error("the main file " .. main .. " isn't in the package", 2) end
  return table.concat({
    "-- " .. (opts.name or "program") .. ": a single-file program made with Pineapple Studio.\n",
    "-- Run it like any other program; the project's files are packed inside.\n",
    filesBlock(files, opts.compress, opts.yield),
    "local MAIN = " .. string.format("%q", main) .. "\n",
    PROGRAM_RUNTIME,
  })
end

local INSTALLER_RUNTIME = [==[
local args = { ... }
local yes = args[1] == "-y" or args[1] == "--yes"
local here = shell and shell.getRunningProgram() or ""
local target
if here == "" or here:sub(1, 4) == "rom/" or not fs.exists(here) then
  target = shell and shell.dir() or ""
else
  target = fs.getDir(here)
end

local paths = {}
for path in pairs(FILES) do paths[#paths + 1] = path end
table.sort(paths)
local existing = {}
for _, path in ipairs(paths) do
  if fs.exists(fs.combine(target, path)) then existing[#existing + 1] = path end
end

print(("Installing %s (%d files) into /%s"):format(NAME, #paths, target))
if #existing > 0 and not yes then
  print(#existing .. " file(s) will be replaced:")
  for i = 1, math.min(5, #existing) do print("  " .. existing[i]) end
  if #existing > 5 then print("  ...and " .. (#existing - 5) .. " more") end
  write("Continue? [y/N] ")
  local answer = read()
  if not answer or not answer:lower():match("^y") then print("Cancelled.") return false end
end

for _, path in ipairs(paths) do
  local full = fs.combine(target, path)
  if full ~= fs.combine(here) then
    local dir = fs.getDir(full)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = assert(fs.open(full, "wb"))
    h.write(FILES[path])
    h.close()
  end
end
-- Files fetched at install time (e.g. a library that isn't packed).
for _, d in ipairs(DOWNLOADS) do
  local full = fs.combine(target, d.path)
  if fs.exists(full) and d.size and fs.getSize(full) == d.size then
    print("Keeping " .. d.path)
  else
    write("Downloading " .. (d.name or d.path) .. "... ")
    local response, err
    if http then response, err = http.get(d.url, nil, true) else err = "HTTP is turned off" end
    if not response then
      printError("failed: " .. tostring(err))
      print("Download it from " .. d.url .. " and save it as /" .. full)
    else
      local data = response.readAll()
      response.close()
      local dir = fs.getDir(full)
      if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
      local h = assert(fs.open(full, "wb"))
      h.write(data)
      h.close()
      print("done")
    end
  end
end

print("Done.")
if MAIN then print("Start it with: " .. fs.combine(target, MAIN):gsub("%.lua$", "")) end
return true
]==]

function M.installer(files, opts)
  opts = opts or {}
  local function lit(s) return string.format("%q", s) end
  local downloads = { "local DOWNLOADS = {\n" }
  for _, d in ipairs(opts.downloads or {}) do
    downloads[#downloads + 1] = "  { path = " .. lit(d.path) .. ", url = " .. lit(d.url)
      .. (d.name and (", name = " .. lit(d.name)) or "") .. (d.size and (", size = " .. tonumber(d.size)) or "") .. " },\n"
  end
  downloads[#downloads + 1] = "}\n"
  return table.concat({
    "-- " .. (opts.name or "project") .. ": installer made with Pineapple Studio.\n",
    "-- Run it to install the files into the folder it is in (or the current\n",
    "-- folder with `pastebin run`). Needs nothing but CC: Tweaked.\n",
    filesBlock(files, opts.compress, opts.yield),
    table.concat(downloads),
    "local NAME = " .. lit(opts.name or "project") .. "\n",
    "local MAIN = " .. (opts.main and lit(opts.main) or "nil") .. "\n",
    INSTALLER_RUNTIME,
  })
end

function M.pastebinRequest(name, code)
  local encode = textutils.urlEncode
  local body = "api_option=paste&api_dev_key=" .. M.PASTEBIN_KEY .. "&api_paste_format=lua"
    .. "&api_paste_name=" .. encode(name) .. "&api_paste_code=" .. encode(code)
  return "https://pastebin.com/api/api_post.php", body,
    { ["Content-Type"] = "application/x-www-form-urlencoded" }
end

function M.pastebinResult(response)
  response = (response or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local id = response:match("^https?://pastebin%.com/(%w+)$")
  if id then return id end
  return nil, response ~= "" and response or "no answer from Pastebin"
end

function M.multipartLauncher(ids, encoded)
  if not ids or #ids == 0 then error("multipart launcher needs at least one paste", 2) end
  local quoted = {}
  for _, id in ipairs(ids) do quoted[#quoted + 1] = string.format("%q", id) end
  return table.concat({
    "-- Pineapple Studio multipart installer launcher.\n",
    "local IDS = { " .. table.concat(quoted, ", ") .. " }\n",
    "local ENCODED = " .. tostring(encoded == true) .. "\n",
    encoded and (M.DECOMPRESS_SOURCE .. "\n") or "",
    [[local parts = {}
for _, id in ipairs(IDS) do
  local response, err = http.get("https://pastebin.com/raw/" .. id)
  if not response then error("could not download installer part " .. id .. ": " .. tostring(err), 0) end
  local data = response.readAll()
  response.close()
  if ENCODED then data = decompress(data) end
  parts[#parts + 1] = data
end
local fn, err = load(table.concat(parts), "=pineapple-studio-installer", "t", _ENV)
if not fn then error(err, 0) end
return fn("-y")
]],
  })
end

function M.formatSize(bytes)
  if bytes < 1024 then return bytes .. " B" end
  return string.format("%.1f KB", bytes / 1024)
end

return M

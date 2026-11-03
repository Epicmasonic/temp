-- Storage for Local History. Each entry is the contents a file had just before a change,
-- labelled with the change that replaced it ("Saved", "AI Assistant", "Deleted", ...).
-- Layout under root: index.lua (paths -> entries, oldest first) and blobs/<id>.txt.
local files = require("pineapple.studio.core.files")

local M = {}

local Store = {}
Store.__index = Store

local MAX_FILE_SIZE = 64 * 1024
local MIN_FREE_SPACE = 16 * 1024

local function now()
  if os.epoch then return os.epoch("local") end
  return math.floor(os.time() * 1000)
end
M.now = now

-- options: maxEntries(), maxDays(), maxSizeKB() return the current limits.
function M.new(root, options)
  local self = setmetatable({ root = root, options = options or {} }, Store)
  self.indexPath = files.join(root, "index.lua")
  local ok, index = pcall(files.readTable, self.indexPath)
  if not ok or type(index) ~= "table" or type(index.files) ~= "table" then index = { files = {} } end
  index.nextId = tonumber(index.nextId) or 1
  self.index = index
  return self
end

function Store:_blob(id) return files.join(self.root, "blobs", tostring(id) .. ".txt") end

function Store:_save()
  return files.writeTable(self.indexPath, self.index)
end

local function limit(self, name, fallback)
  local fn = self.options[name]
  local value = fn and tonumber(fn()) or nil
  if not value or value < 1 then return fallback end
  return value
end

-- Entries for a path, newest first.
function Store:entries(path)
  local list, out = self.index.files[path] or {}, {}
  for i = #list, 1, -1 do out[#out + 1] = list[i] end
  return out
end

function Store:find(path, id)
  for _, e in ipairs(self.index.files[path] or {}) do
    if e.id == id then return e end
  end
end

function Store:read(entry)
  return files.read(self:_blob(entry.id))
end

-- Paths with history whose file no longer exists.
function Store:deletedPaths()
  local out = {}
  for path in pairs(self.index.files) do
    if not fs.exists(path) then out[#out + 1] = path end
  end
  table.sort(out)
  return out
end

-- coalesceMs: when the newest version has the same label and is younger than this, keep it
-- instead of adding another (used for auto-save, which runs after every pause in typing).
-- group: optional id shared by versions from one operation (e.g. one AI Assistant turn), so
-- they can be found and undone together; grouped versions are recorded even when they match
-- the previous version.
function Store:record(path, content, label, coalesceMs, group)
  if type(content) ~= "string" then return false end
  if #content > MAX_FILE_SIZE then return false, "file is too large for local history" end
  if fs.getFreeSpace and fs.getFreeSpace(fs.exists(self.root) and self.root or "/") < #content + MIN_FREE_SPACE then
    return false, "not enough disk space for local history"
  end
  local list = self.index.files[path] or {}
  local latest = list[#list]
  if not group and coalesceMs and latest and latest.label == label and now() - (latest.time or 0) < coalesceMs then
    return false
  end
  if not group and latest and latest.size == #content and files.read(self:_blob(latest.id)) == content then
    return false
  end
  local id = self.index.nextId
  self.index.nextId = id + 1
  local ok, err = files.write(self:_blob(id), content)
  if not ok then return false, err end
  list[#list + 1] = { id = id, time = now(), label = label or "Saved", size = #content,
    group = type(group) == "string" and group or nil }
  self.index.files[path] = list
  self:prune()
  self:_save()
  return true
end

-- Drops versions beyond the per-file count or age limits, then the oldest versions overall
-- until the total size fits.
function Store:prune()
  local maxEntries = limit(self, "maxEntries", 30)
  local maxBytes = limit(self, "maxSizeKB", 256) * 1024
  local cutoff = now() - limit(self, "maxDays", 14) * 86400000
  local all = {}
  for path, list in pairs(self.index.files) do
    for i, e in ipairs(list) do
      all[#all + 1] = { entry = e, drop = (e.time or 0) < cutoff or (#list - i + 1) > maxEntries }
    end
  end
  table.sort(all, function(a, b) return (a.entry.time or 0) > (b.entry.time or 0) end)
  local total, dropped, any = 0, {}, false
  for _, item in ipairs(all) do
    if not item.drop then
      total = total + (item.entry.size or 0)
      if total > maxBytes then item.drop = true end
    end
    if item.drop then
      dropped[item.entry] = true
      any = true
      pcall(fs.delete, self:_blob(item.entry.id))
    end
  end
  if not any then return end
  for path, list in pairs(self.index.files) do
    local kept = {}
    for _, e in ipairs(list) do if not dropped[e] then kept[#kept + 1] = e end end
    self.index.files[path] = #kept > 0 and kept or nil
  end
end

-- Moves history along with a renamed file or folder.
function Store:rename(from, to)
  local moving = {}
  for path in pairs(self.index.files) do
    if path == from or path:sub(1, #from + 1) == from .. "/" then moving[#moving + 1] = path end
  end
  if #moving == 0 then return end
  for _, path in ipairs(moving) do
    local target = to .. path:sub(#from + 1)
    local merged = self.index.files[target] or {}
    for _, e in ipairs(self.index.files[path]) do merged[#merged + 1] = e end
    table.sort(merged, function(a, b) return (a.time or 0) < (b.time or 0) end)
    self.index.files[path] = nil
    self.index.files[target] = merged
  end
  self:_save()
end

function Store:clear()
  for _, list in pairs(self.index.files) do
    for _, e in ipairs(list) do pcall(fs.delete, self:_blob(e.id)) end
  end
  self.index.files = {}
  self:_save()
end

return M

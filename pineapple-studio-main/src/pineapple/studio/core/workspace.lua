
local events = require("pineapple.studio.core.events")
local files = require("pineapple.studio.core.files")

local M = {}

local Workspace = {}
Workspace.__index = Workspace

local Document = {}
Document.__index = Document

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  if #lines == 0 then lines[1] = "" end
  return lines
end
M.splitLines = splitLines

function M.new(options)
  options = options or {}
  local self = setmetatable({
    root = files.join(options.root or "/"),
    events = events.new(options.onError),
    _docs = {},
    _state = { files = {} },
    _onError = options.onError,
  }, Workspace)
  return self
end

function Workspace:setRoot(root)
  self.root = files.join(root)
  self._docs = {}
  self:loadState()
  self.events:emit("rootChanged", self.root)
end

function Workspace:path(p)
  if p:sub(1, 1) == "/" then return files.join(p) end
  return files.join(self.root, p)
end

function Workspace:relative(p)
  p = files.join(p)
  if self.root == "/" then return p:sub(2) end
  if p == self.root then return "" end
  if p:sub(1, #self.root + 1) == self.root .. "/" then return p:sub(#self.root + 2) end
  return p
end

function Workspace:name()
  if self.root == "/" then return "/" end
  return fs.getName(self.root)
end

function Workspace:list(dir, showHidden)
  local abs = self:path(dir or "")
  if not fs.isDir(abs) then return {} end
  local out = {}
  for _, name in ipairs(fs.list(abs)) do
    if showHidden or name:sub(1, 1) ~= "." then
      local p = files.join(abs, name)
      out[#out + 1] = { name = name, path = p, isDir = fs.isDir(p) }
    end
  end
  table.sort(out, function(a, b)
    if a.isDir ~= b.isDir then return a.isDir end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function Workspace:exists(p) return fs.exists(self:path(p)) end
function Workspace:isDir(p) return fs.isDir(self:path(p)) end

function Workspace:readFile(p)
  return files.read(self:path(p))
end

-- info is optional and describes the write for listeners, e.g. { source = "AI Assistant" }.
-- "willWrite" fires before the file changes so listeners (such as Local History) can keep
-- the previous contents.
function Workspace:writeFile(p, text, info)
  local abs = self:path(p)
  local existed = fs.exists(abs)
  self.events:emit("willWrite", abs, text, info or {})
  local ok, err = files.write(abs, text)
  if not ok then return nil, err end
  self.events:emit(existed and "fileChanged" or "fileCreated", abs, info or {})
  return true
end

function Workspace:createFolder(p)
  local abs = self:path(p)
  if fs.exists(abs) then return nil, abs .. " already exists" end
  fs.makeDir(abs)
  self.events:emit("fileCreated", abs)
  return true
end

function Workspace:delete(p)
  local abs = self:path(p)
  if not fs.exists(abs) then return nil, abs .. " does not exist" end
  self.events:emit("willDelete", abs)
  fs.delete(abs)
  self.events:emit("fileDeleted", abs)
  return true
end

function Workspace:move(from, to)
  local a, b = self:path(from), self:path(to)
  if not fs.exists(a) then return nil, a .. " does not exist" end
  if a == b then return true end
  if fs.exists(b) then return nil, b .. " already exists" end
  if b:sub(1, #a + 1) == a .. "/" then return nil, "Can't move a folder into itself" end
  local moved, moveErr = pcall(fs.move, a, b)
  if not moved then return nil, tostring(moveErr) end
  if not fs.exists(b) then return nil, "Move failed" end

  local documents = {}
  for path, doc in pairs(self._docs) do
    if path == a or path:sub(1, #a + 1) == a .. "/" then
      documents[#documents + 1] = { path = path, doc = doc }
    end
  end
  for _, entry in ipairs(documents) do
    local oldPath = entry.path
    local newPath = b .. oldPath:sub(#a + 1)
    self._docs[oldPath] = nil
    self._docs[newPath] = entry.doc
    entry.doc.path = newPath
    entry.doc.events:emit("rename", entry.doc, oldPath)
  end
  self.events:emit("fileRenamed", a, b)
  return true
end

local function newDocument(ws, path, text)
  local doc = setmetatable({
    path = path,
    lines = splitLines(text),
    version = 0,
    savedVersion = 0,
    readOnly = fs.isReadOnly(path),
    events = events.new(ws._onError),
    _ws = ws,
    _refs = 0,
  }, Document)
  return doc
end

function Document:isDirty()
  return self.version ~= self.savedVersion
end

function Document:getText()
  return table.concat(self.lines, "\n")
end

function Document:setText(text)
  self.lines = splitLines(text)
  self:changed()
end

function Document:changed(info)
  local wasDirty = self:isDirty()
  self.version = self.version + 1
  self.events:emit("change", self, info)
  if not wasDirty then self.events:emit("dirty", self, true) end
end

function Document:save(info)
  if self.readOnly then return nil, self.path .. " is read-only" end
  local ok, err = self._ws:writeFile(self.path, self:getText(), info)
  if not ok then return nil, err end
  local wasDirty = self:isDirty()
  self.savedVersion = self.version
  self.events:emit("save", self)
  if wasDirty then self.events:emit("dirty", self, false) end
  return true
end

function Document:revert()
  local text, err = files.read(self.path)
  if not text then return nil, err end
  local wasDirty = self:isDirty()
  self.lines = splitLines(text)
  self.version = self.version + 1
  self.savedVersion = self.version
  self.events:emit("change", self, { reverted = true })
  if wasDirty then self.events:emit("dirty", self, false) end
  return true
end

function Document:on(name, fn)
  return self.events:on(name, fn)
end

function Document:name()
  return fs.getName(self.path)
end

function Workspace:openDocument(p)
  local abs = self:path(p)
  local doc = self._docs[abs]
  if not doc then
    if fs.isDir(abs) then return nil, abs .. " is a folder" end
    local text = ""
    if fs.exists(abs) then
      local t, err = files.read(abs)
      if not t then return nil, err end
      text = t
    end
    doc = newDocument(self, abs, text)
    self._docs[abs] = doc
    self.events:emit("documentOpened", doc)
  end
  doc._refs = doc._refs + 1
  return doc
end

function Workspace:getDocument(p)
  return self._docs[self:path(p)]
end

function Workspace:closeDocument(doc)
  doc._refs = doc._refs - 1
  if doc._refs <= 0 and self._docs[doc.path] == doc then
    self._docs[doc.path] = nil
    self.events:emit("documentClosed", doc)
  end
end

function Workspace:dirtyDocuments()
  local out = {}
  for _, doc in pairs(self._docs) do
    if doc:isDirty() then out[#out + 1] = doc end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

function Workspace:statePath()
  return files.join(self.root, ".pineapple", "state.lua")
end

function Workspace:loadState()
  local state = files.readTable(self:statePath())
  self._state = type(state) == "table" and state or {}
  self._state.files = self._state.files or {}
  return self._state
end

function Workspace:saveState()
  return files.writeTable(self:statePath(), self._state)
end

function Workspace:getState(key) return self._state[key] end
function Workspace:setState(key, value) self._state[key] = value end

function Workspace:getViewState(p)
  return self._state.files[self:relative(self:path(p))]
end

function Workspace:setViewState(p, state)
  self._state.files[self:relative(self:path(p))] = state
end

return M

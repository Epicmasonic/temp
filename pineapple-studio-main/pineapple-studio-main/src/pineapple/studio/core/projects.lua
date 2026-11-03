local disposable = require("pineapple.studio.core.disposable")
local files = require("pineapple.studio.core.files")

local M = {}

local Projects = {}
Projects.__index = Projects

M.MAX_RECENT = 8

function M.new(options)
  options = options or {}
  local self = setmetatable({
    _templates = {},
    _fileTemplates = {},
    _recentPath = options.dataDir and files.join(options.dataDir, "recent.lua") or nil,
    _recent = {},
  }, Projects)
  self:loadRecent()
  return self
end

function Projects:registerFileTemplate(template)
  if type(template) ~= "table" or type(template.id) ~= "string" then
    error("registerFileTemplate expects { id, title, extension, content }", 2)
  end
  if self._fileTemplates[template.id] then error("file template '" .. template.id .. "' is already registered", 2) end
  self._fileTemplates[template.id] = template
  return disposable.new(function()
    if self._fileTemplates[template.id] == template then self._fileTemplates[template.id] = nil end
  end)
end

function Projects:fileTemplates(folders)
  local out = {}
  for _, t in pairs(self._fileTemplates) do out[#out + 1] = t end
  for _, dir in ipairs(folders or {}) do
    if fs.isDir(dir) then
      for _, name in ipairs(fs.list(dir)) do
        local path = files.join(dir, name)
        if not fs.isDir(path) then
          local base, ext = name:match("^(.-)%.([^%.]+)$")
          out[#out + 1] = {
            id = "file:" .. path, title = base or name, extension = ext,
            description = "Template from " .. dir, order = 50,
            content = function() return files.read(path) or "" end,
          }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local oa, ob = a.order or 100, b.order or 100
    if oa ~= ob then return oa < ob end
    return (a.title or a.id) < (b.title or b.id)
  end)
  return out
end

function Projects:registerTemplate(template)
  if type(template) ~= "table" or type(template.id) ~= "string" or type(template.create) ~= "function" then
    error("registerTemplate expects { id, title, create }", 2)
  end
  if self._templates[template.id] then error("template '" .. template.id .. "' is already registered", 2) end
  self._templates[template.id] = template
  return disposable.new(function()
    if self._templates[template.id] == template then self._templates[template.id] = nil end
  end)
end

function Projects:templates()
  local out = {}
  for _, t in pairs(self._templates) do out[#out + 1] = t end
  table.sort(out, function(a, b)
    local oa, ob = a.order or 50, b.order or 50
    if oa ~= ob then return oa < ob end
    return (a.title or a.id) < (b.title or b.id)
  end)
  return out
end

function Projects:getTemplate(id)
  return self._templates[id]
end

function M.validateName(name)
  if type(name) ~= "string" or name:match("^%s*$") then return nil, "Enter a project name" end
  if name:find("[/\\:%*%?\"<>|]") then return nil, "The name can't contain / \\ : * ? \" < > |" end
  if name == "." or name == ".." then return nil, "Choose another name" end
  return true
end

function Projects:create(templateId, parent, name)
  local template = self._templates[templateId]
  if not template then return nil, "Unknown template '" .. tostring(templateId) .. "'" end
  local ok, msg = M.validateName(name)
  if not ok then return nil, msg end
  parent = files.join(parent or "/")
  if fs.exists(parent) and not fs.isDir(parent) then return nil, parent .. " is a file" end
  if parent:sub(1, 4) == "/rom" then return nil, "Can't create projects in /rom" end
  local folder = files.join(parent, name)
  if fs.exists(folder) then return nil, folder .. " already exists" end

  fs.makeDir(folder)
  local settingsTable = {}
  local project = {
    name = name,
    folder = folder,
    write = function(rel, text)
      local okWrite, err = files.write(files.join(folder, rel), text)
      if not okWrite then error(err, 0) end
    end,
    setting = function(key, value) settingsTable[key] = value end,
  }
  local created, err = pcall(template.create, folder, project)
  if not created then
    fs.delete(folder)
    return nil, "Template failed: " .. tostring(err)
  end
  if next(settingsTable) then
    files.writeTable(files.join(folder, ".pineapple", "project.lua"), settingsTable)
  end
  return folder
end

function Projects:loadRecent()
  local list = self._recentPath and files.readTable(self._recentPath) or {}
  self._recent = type(list) == "table" and list or {}
  return self._recent
end

local function saveRecent(self)
  if self._recentPath then files.writeTable(self._recentPath, self._recent) end
end

function Projects:addRecent(folder)
  folder = files.join(folder)
  for i = #self._recent, 1, -1 do
    if self._recent[i] == folder then table.remove(self._recent, i) end
  end
  table.insert(self._recent, 1, folder)
  while #self._recent > M.MAX_RECENT do table.remove(self._recent) end
  saveRecent(self)
end

function Projects:removeRecent(folder)
  folder = files.join(folder)
  for i = #self._recent, 1, -1 do
    if self._recent[i] == folder then table.remove(self._recent, i) end
  end
  saveRecent(self)
end

function Projects:recent()
  local out = {}
  for _, folder in ipairs(self._recent) do
    if fs.isDir(folder) then out[#out + 1] = folder end
  end
  return out
end

return M

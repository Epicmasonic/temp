local disposable = require("pineapple.studio.core.disposable")

-- Registry of functions the AI Assistant can offer to models.
--
-- Every tool has name, description and parameters (a JSON Schema), plus one of:
--   run(args, complete)    does the work and returns text or a serialisable table. To finish
--                          later (for example after asking the user), return ASYNC and call
--                          complete(result, err).
--   prepare(args, base)    a change tool: returns a proposed file change instead of making it,
--                          { path = absolutePath, newText = "..." }. base(path) gives the text
--                          the file will have after earlier changes in the same reply, or nil.
--                          The assistant collects every change from one reply into a single
--                          review and writes only what the user approves.
-- Optional metadata:
--   describe(args, result, err)  a short line for the chat's activity log
--   readOnly = true              the tool never changes anything
local M = {}
M.ASYNC = {}

local Registry = {}
Registry.__index = Registry

local function toolName(owner, name)
  local prefix = owner:lower():gsub("[^%w]+", "_"):gsub("_+$", "")
  local leaf = name:lower():gsub("[^%w_-]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  local full = prefix .. "_" .. leaf
  if #full > 64 then full = full:sub(1, 64) end
  return full
end

function M.new()
  return setmetatable({ _tools = {}, ASYNC = M.ASYNC }, Registry)
end

function Registry:register(owner, spec)
  if type(owner) ~= "string" or owner == "" then error("AI tool needs an owner", 2) end
  if type(spec) ~= "table" then error("AI tool must be a table", 2) end
  if type(spec.name) ~= "string" or spec.name == "" then error("AI tool needs a name", 2) end
  if type(spec.description) ~= "string" or spec.description == "" then
    error("AI tool '" .. spec.name .. "' needs a description", 2)
  end
  if type(spec.parameters) ~= "table" then error("AI tool '" .. spec.name .. "' needs a JSON schema", 2) end
  if type(spec.run) ~= "function" and type(spec.prepare) ~= "function" then
    error("AI tool '" .. spec.name .. "' needs a run or prepare function", 2)
  end
  if spec.describe ~= nil and type(spec.describe) ~= "function" then
    error("AI tool '" .. spec.name .. "': describe must be a function", 2)
  end

  local name = toolName(owner, spec.name)
  if name == "" or name:sub(-1) == "_" or not name:match("^[%w_-]+$") then error("AI tool name is invalid", 2) end
  if self._tools[name] then error("AI tool '" .. name .. "' is already registered", 2) end
  local entry = {
    name = name, leaf = spec.name, owner = owner, description = spec.description,
    parameters = spec.parameters, run = spec.run, prepare = spec.prepare,
    describe = spec.describe, readOnly = spec.readOnly == true,
  }
  self._tools[name] = entry
  return disposable.new(function()
    if self._tools[name] == entry then self._tools[name] = nil end
  end)
end

function Registry:get(name)
  return self._tools[name]
end

function Registry:list()
  local names, out = {}, {}
  for name in pairs(self._tools) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local tool = self._tools[name]
    out[#out + 1] = {
      type = "function",
      ["function"] = {
        name = tool.name,
        description = tool.description,
        parameters = tool.parameters,
      },
    }
  end
  return out
end

-- Runs a run-tool. Returns result, err, pending (true when it will call `completed` later).
function Registry:call(name, arguments, completed)
  local tool = self._tools[name]
  if not tool then return nil, "Unknown tool: " .. tostring(name) end
  if not tool.run then return nil, "Tool " .. name .. " proposes changes; use prepare" end
  local ok, result = pcall(tool.run, arguments or {}, completed)
  if not ok then return nil, tostring(result) end
  if result == M.ASYNC then return nil, nil, true end
  return result == nil and "success" or result
end

-- Asks a change tool for its proposed change: returns { path, newText } or nil, err.
function Registry:prepare(name, arguments, base)
  local tool = self._tools[name]
  if not tool then return nil, "Unknown tool: " .. tostring(name) end
  if not tool.prepare then return nil, "Tool " .. name .. " doesn't propose changes" end
  local ok, change, err = pcall(tool.prepare, arguments or {}, base)
  if not ok then return nil, tostring(change) end
  if type(change) ~= "table" then return nil, err or "The tool didn't propose a change" end
  if type(change.path) ~= "string" or type(change.newText) ~= "string" then
    return nil, "A proposed change needs a path and newText"
  end
  return change
end

return M

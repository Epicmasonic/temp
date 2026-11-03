local disposable = require("pineapple.studio.core.disposable")

local M = {}

local Registry = {}
Registry.__index = Registry

function M.new()
  return setmetatable({ _providers = {}, _order = 0 }, Registry)
end

function Registry:register(provider)
  if type(provider) ~= "table" then error("editor provider must be a table", 2) end
  if type(provider.id) ~= "string" then error("editor provider needs an id", 2) end
  if type(provider.score) ~= "function" then error("editor provider '" .. provider.id .. "' needs score(path)", 2) end
  if type(provider.create) ~= "function" then error("editor provider '" .. provider.id .. "' needs create()", 2) end
  if self._providers[provider.id] then error("editor provider '" .. provider.id .. "' is already registered", 2) end
  self._order = self._order + 1
  self._providers[provider.id] = { provider = provider, order = self._order }
  return disposable.new(function()
    local e = self._providers[provider.id]
    if e and e.provider == provider then self._providers[provider.id] = nil end
  end)
end

function Registry:get(id)
  local e = self._providers[id]
  return e and e.provider
end

local function safeScore(provider, path)
  local ok, s = pcall(provider.score, path)
  if not ok or type(s) ~= "number" then return 0 end
  return s
end

function Registry:candidates(path)
  local list = {}
  for _, e in pairs(self._providers) do
    local s = safeScore(e.provider, path)
    if s > 0 then list[#list + 1] = { provider = e.provider, score = s, order = e.order } end
  end
  table.sort(list, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)
  local out = {}
  for i, c in ipairs(list) do out[i] = c.provider end
  return out
end

function Registry:resolve(path)
  return self:candidates(path)[1]
end

return M

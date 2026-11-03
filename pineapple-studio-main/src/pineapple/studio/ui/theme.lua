local M = {}

local ALIASES = { light = "pineapple-light", dark = "pineapple-dark" }

M.DEFAULT = "pineapple-light"
M.BUILTIN = { "pineapple-light", "pineapple-dark", "frosty", "pineapple", "smoky", "midnight" }

local function resolve(value, basalt)
  if type(value) == "string" and value:match("^#%x%x%x%x%x%x$") then
    return basalt and basalt.rgb(value) or colors.cyan
  elseif type(value) == "table" then
    local out = {}
    for k, v in pairs(value) do out[k] = resolve(v, basalt) end
    return out
  end
  return value
end

function M.raw(id, depth)
  id = ALIASES[id] or id
  local ok, theme = pcall(require, "pineapple.studio.ui.themes." .. tostring(id))
  if not ok or type(theme) ~= "table" then return nil, "unknown theme '" .. tostring(id) .. "'" end
  if theme.extends and (depth or 0) < 5 then
    local base = M.raw(theme.extends, (depth or 0) + 1)
    if base then
      local merged = {}
      for k, v in pairs(base) do merged[k] = v end
      for k, v in pairs(theme) do
        if type(v) == "table" and type(base[k]) == "table" then
          local sub = {}
          for k2, v2 in pairs(base[k]) do sub[k2] = v2 end
          for k2, v2 in pairs(v) do sub[k2] = v2 end
          merged[k] = sub
        else
          merged[k] = v
        end
      end
      merged.extends = nil
      return merged
    end
  end
  return theme
end

function M.load(id, basalt)
  local theme = M.raw(id) or M.raw(M.DEFAULT)
  return resolve(theme, basalt)
end

function M.applyInto(target, theme)
  for k in pairs(target) do target[k] = nil end
  for k, v in pairs(theme) do target[k] = v end
  return target
end

function M.list()
  local out = {}
  for _, id in ipairs(M.BUILTIN) do
    local t = M.raw(id)
    if t then out[#out + 1] = { id = id, name = t.name or id, description = t.description } end
  end
  return out
end

return M

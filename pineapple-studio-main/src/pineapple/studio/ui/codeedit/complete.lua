local M = {}

local KEYWORDS = {
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto",
  "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
local KEYWORD_SET = {}
for _, k in ipairs(KEYWORDS) do KEYWORD_SET[k] = true end
M.KEYWORDS = KEYWORD_SET

function M.context(line, col)
  local before = line:sub(1, col - 1)
  local base, sep, prefix = before:match("([%a_][%w_%.]*)([%.:])([%w_]*)$")
  if base and not base:find("%.%.") and base:sub(-1) ~= "." then

    local charBefore = before:sub(#before - #prefix - #sep - #base, #before - #prefix - #sep - #base)
    if charBefore ~= "." and charBefore ~= ":" then
      return { kind = "member", base = base, sep = sep, prefix = prefix, start = col - #prefix }
    end
    return nil
  end
  prefix = before:match("[%a_][%w_]*$") or ""
  local charBefore = before:sub(#before - #prefix, #before - #prefix)
  local concat = before:sub(#before - #prefix - 1, #before - #prefix) == ".."
  if charBefore:match("[%w_%.:]") and not concat then return nil end
  return { kind = "name", prefix = prefix, start = col - #prefix }
end

local function resolve(env, path)
  local value = env
  for part in path:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    local ok, v = pcall(function() return value[part] end)
    if not ok then return nil end
    value = v
  end
  return value
end

local function kindOf(value)
  local t = type(value)
  if t == "function" then return "function" end
  if t == "table" then return "module" end
  return "value"
end

local function score(name, prefix)
  if prefix == "" then return 1 end
  if name == prefix then return nil end
  if name:sub(1, #prefix) == prefix then return 100 end
  local lname, lprefix = name:lower(), prefix:lower()
  if lname:sub(1, #lprefix) == lprefix then return 80 end
  if #prefix >= 2 and lname:find(lprefix, 1, true) then return 40 end
  return nil
end

function M.candidates(ctx, env)
  local found, out = {}, {}
  local function add(name, kind, sig, doc, source, bonus)
    local s = score(name, ctx.prefix)
    if not s then return end
    local existing = found[name]
    if existing then
      existing.sig = existing.sig or sig
      existing.doc = existing.doc or doc
      if kind ~= "local" and existing.kind == "local" then existing.kind = kind end
      return
    end
    local item = { name = name, kind = kind, sig = sig, doc = doc, source = source, score = s + (bonus or 0) }
    found[name] = item
    out[#out + 1] = item
  end
  local api, globals, lines = env.api or {}, env.globals or {}, env.lines or {}

  if ctx.kind == "member" then
    local base = ctx.base
    local known = api[base]
    if known then
      for name, info in pairs(known) do
        add(name, info.sig and "function" or "value", info.sig, info.doc, base, 2)
      end
    end
    local value = resolve(globals, base)
    if type(value) == "table" then
      for name, v in pairs(value) do
        if type(name) == "string" and name:match("^[%a_][%w_]*$") then
          local info = known and known[name]
          add(name, kindOf(v), info and info.sig, info and info.doc, base, 1)
        end
      end
    end

    local escaped = base:gsub("%p", "%%%0")
    for i, line in ipairs(lines) do
      for sepFound, name in line:gmatch(escaped .. "([%.:])([%a_][%w_]*)") do
        if i ~= env.line or name ~= ctx.prefix then
          local sig = line:match("function%s+" .. escaped .. "[%.:]" .. name .. "%s*(%b())")
          add(name, sig and "function" or "local", sig, nil, base)
        end
      end
    end
  else

    for i, line in ipairs(lines) do
      local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', ""):gsub("'[^']*'", "")
      for name in code:gmatch("[%a_][%w_]*") do
        if not KEYWORD_SET[name] and (i ~= env.line or name ~= ctx.prefix) then
          local sig = line:match("function%s+" .. name .. "%s*(%b())")
            or line:match("local%s+function%s+" .. name .. "%s*(%b())")
          add(name, sig and "function" or "local", sig, nil, nil, 3)
        end
      end
    end
    for name, info in pairs(api._G or {}) do add(name, info.sig and "function" or "value", info.sig, info.doc, nil, 2) end
    for name in pairs(api) do if name ~= "_G" then add(name, "module", nil, nil, nil, 2) end end
    for name, v in pairs(globals) do
      if type(name) == "string" and name:match("^[%a_][%w_]*$") then add(name, kindOf(v), nil, nil, nil, 1) end
    end
    for _, k in ipairs(KEYWORDS) do add(k, "keyword", nil, nil, nil, 0) end
  end

  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if #a.name ~= #b.name and ctx.prefix ~= "" then return #a.name < #b.name end
    return a.name < b.name
  end)
  return out
end

function M.insertText(item, nextChar)
  if item.kind == "function" and nextChar ~= "(" then
    local hasArgs = item.sig and item.sig ~= "()" and true or (item.sig == nil)
    return item.name .. "()", hasArgs and -1 or 0
  end
  return item.name, 0
end

return M

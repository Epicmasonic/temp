local lexer = require("pineapple.studio.ui.codeedit.lexer")

local M = {}

function M.syntax(lines)
  local text = table.concat(lines, "\n")
  local fn, err = load(text, "=chunk", "t", {})
  if fn then return nil end
  local line, message = tostring(err):match("^chunk:(%d+): (.*)$")
  line = tonumber(line) or 1
  message = message or tostring(err)
  line = math.max(1, math.min(line, #lines))
  local col, endCol = 1, math.max(1, #(lines[line] or ""))
  local near = message:match("near '(.-)'$")
  if near and lines[line] then
    local s = lines[line]:find(near, 1, true)
    if s then col, endCol = s, s + #near - 1 end
  elseif message:match("<eof>") then

    for i = #lines, 1, -1 do
      if lines[i]:match("%S") then line = i; break end
    end
    col, endCol = math.max(1, #lines[line]), math.max(1, #lines[line])
  end
  local indentEnd = #(lines[line] or ""):match("^%s*")
  if near == nil and not message:match("<eof>") then col = indentEnd + 1 end
  return { severity = "error", line = line, col = col, endCol = endCol, message = message }
end

local function allTokens(lines)
  local out, state = {}, nil
  for i, line in ipairs(lines) do
    local toks
    toks, state = lexer.tokenize(line, state)
    for _, t in ipairs(toks) do
      if t.type ~= "comment" then
        out[#out + 1] = { type = t.type, text = line:sub(t.from, t.to), line = i, from = t.from, to = t.to }
      end
    end
  end
  return out
end

local function isName(t) return t and (t.type == "ident" or t.type == "func" or t.type == "global") end

function M.declarations(tokens)
  local locals, globals = {}, {}
  local braces = 0
  for i, t in ipairs(tokens) do
    if t.type == "operator" then
      if t.text == "{" then braces = braces + 1 elseif t.text == "}" then braces = math.max(0, braces - 1) end
    elseif t.type == "keyword" and (t.text == "local" or t.text == "for") then

      local j = i + 1
      if tokens[j] and tokens[j].text == "function" then j = j + 1 end
      while isName(tokens[j]) do
        locals[tokens[j].text] = true
        if tokens[j + 1] and tokens[j + 1].text == "," then j = j + 2 else break end
      end
    elseif t.type == "keyword" and t.text == "function" then

      local j = i + 1
      if isName(tokens[j]) then
        if not (tokens[i - 1] and tokens[i - 1].text == "local") then globals[tokens[j].text] = true end
        while tokens[j + 1] and (tokens[j + 1].text == "." or tokens[j + 1].text == ":") do
          if tokens[j + 1].text == ":" then locals.self = true end
          j = j + 2
        end
        j = j + 1
      end
      if tokens[j] and tokens[j].text == "(" then
        j = j + 1
        while tokens[j] and tokens[j].text ~= ")" do
          if isName(tokens[j]) then locals[tokens[j].text] = true end
          j = j + 1
        end
      end
    elseif isName(t) and braces == 0 then

      local prev, nxt = tokens[i - 1], tokens[i + 1]
      local afterDot = prev and (prev.text == "." or prev.text == ":")
      if not afterDot and nxt and nxt.text == "=" then
        local j, isLocal = i - 1, false

        while tokens[j] and (tokens[j].text == "," or isName(tokens[j])) do j = j - 1 end
        if tokens[j] and tokens[j].text == "local" then isLocal = true end
        if not isLocal then globals[t.text] = true end
      end
    end
  end
  return locals, globals
end

local function distance(a, b)
  if math.abs(#a - #b) > 2 then return 99 end
  local prev = {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

function M.unknownGlobals(lines, known, tokens)
  tokens = tokens or allTokens(lines)
  local locals, globals = M.declarations(tokens)
  local out = {}
  local braces = 0
  for i, t in ipairs(tokens) do
    if t.type == "operator" then
      if t.text == "{" then braces = braces + 1 elseif t.text == "}" then braces = math.max(0, braces - 1) end
    elseif isName(t) then
      local name = t.text
      local prev, nxt = tokens[i - 1], tokens[i + 1]
      local field = prev and (prev.text == "." or prev.text == ":")
      local key = braces > 0 and nxt and nxt.text == "=" and prev and (prev.text == "{" or prev.text == "," or prev.text == ";")
      local label = (prev and (prev.text == "goto" or prev.text == "::"))
      if not field and not key and not label and not locals[name] and not globals[name] and not known[name] then
        local best, bestD
        local function consider(candidate)
          local d = distance(name, candidate)
          if d <= 2 and d < #name and (not bestD or d < bestD) then best, bestD = candidate, d end
        end
        for n in pairs(locals) do consider(n) end
        for n in pairs(globals) do consider(n) end
        for n in pairs(known) do if type(n) == "string" then consider(n) end end
        out[#out + 1] = {
          severity = "warning", line = t.line, col = t.from, endCol = t.to,
          message = "Unknown global '" .. name .. "'" .. (best and (", did you mean '" .. best .. "'?") or ""),
        }
      end
    end
  end
  return out
end

function M.knownGlobals(env, api)
  local known = { shell = true, multishell = true, arg = true, self = true, _ENV = true }
  for name in pairs(env or _G) do if type(name) == "string" then known[name] = true end end
  for name in pairs(lexer.GLOBALS) do known[name] = true end
  for name in pairs(api or {}) do if name ~= "_G" then known[name] = true end end
  for name in pairs((api or {})._G or {}) do known[name] = true end
  return known
end

function M.definedGlobals(lines)
  local _, globals = M.declarations(allTokens(lines))
  return globals
end

function M.check(lines, options)
  options = options or {}
  local err = M.syntax(lines)
  if err then return { err } end
  local known = {}
  for k in pairs(options.known or M.knownGlobals()) do known[k] = true end
  for k in pairs(options.extra or {}) do known[k] = true end
  return M.unknownGlobals(lines, known)
end

return M

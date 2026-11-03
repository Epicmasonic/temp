local M = {}

local KEYWORDS = {}
for w in ([[and break do else elseif end for function goto if in local not or
  repeat return then until while]]):gmatch("%a+") do KEYWORDS[w] = true end

local VALUES = { ["true"] = true, ["false"] = true, ["nil"] = true }

local GLOBALS = {}
for w in ([[print write read error assert pcall xpcall type tostring tonumber pairs
  ipairs next select setmetatable getmetatable rawget rawset rawequal rawlen
  require load loadfile dofile unpack sleep printError
  string table math coroutine os io fs term colors colours keys peripheral
  rednet redstone rs http textutils parallel shell multishell window settings
  turtle pocket commands disk gps paintutils vector bit32 utf8 debug _G _ENV
  self]]):gmatch("[%w_]+") do GLOBALS[w] = true end
M.KEYWORDS, M.VALUES, M.GLOBALS = KEYWORDS, VALUES, GLOBALS

local function sameState(a, b)
  if a == nil or b == nil then return a == b end
  return a.kind == b.kind and a.level == b.level
end
M.sameState = sameState

local function findLongClose(line, i, level)
  local close = "]" .. string.rep("=", level) .. "]"
  local s, e = line:find(close, i, true)
  return e
end

function M.tokenize(line, state)
  local tokens = {}
  local n = #line
  local i = 1

  local function add(kind, from, to)
    tokens[#tokens + 1] = { type = kind, from = from, to = to }
  end

  if state then
    local e = findLongClose(line, 1, state.level)
    if not e then
      if n > 0 then add(state.kind, 1, n) end
      return tokens, state
    end
    add(state.kind, 1, e)
    i = e + 1
  end

  local lastIdentEnd, lastIdentStart = nil, nil
  while i <= n do
    local c = line:sub(i, i)
    if c:match("%s") then
      local _, e = line:find("^%s+", i)
      i = e + 1
    elseif line:sub(i, i + 1) == "--" then
      local level = line:match("^%[(=*)%[", i + 2)
      if level then
        local e = findLongClose(line, i + 4 + #level, #level)
        if not e then
          add("comment", i, n)
          return tokens, { kind = "comment", level = #level }
        end
        add("comment", i, e)
        i = e + 1
      else
        add("comment", i, n)
        i = n + 1
      end
    elseif c == "[" and line:match("^%[=*%[", i) then
      local level = #line:match("^%[(=*)%[", i)
      local e = findLongClose(line, i + 2 + level, level)
      if not e then
        add("string", i, n)
        return tokens, { kind = "string", level = level }
      end
      add("string", i, e)
      i = e + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c then break
        else j = j + 1 end
      end
      if j > n then j = n end
      add("string", i, j)
      i = j + 1
    elseif c:match("%d") or (c == "." and line:sub(i + 1, i + 1):match("%d")) then
      local e
      if line:match("^0[xX]", i) then
        _, e = line:find("^0[xX][%x%.]*[pP]?[%+%-]?%x*", i)
      else
        _, e = line:find("^%d*%.?%d*[eE][%+%-]?%d+", i)
        if not e then _, e = line:find("^%d*%.?%d*", i) end
      end
      add("number", i, e)
      i = e + 1
    elseif c:match("[%a_]") then
      local _, e = line:find("^[%w_]+", i)
      local word = line:sub(i, e)
      local kind
      if KEYWORDS[word] then kind = "keyword"
      elseif VALUES[word] then kind = "value"
      elseif line:match("^%s*%(", e + 1) then kind = "func"
      elseif GLOBALS[word] and line:sub(i - 1, i - 1) ~= "." and line:sub(i - 1, i - 1) ~= ":" then kind = "global"
      else kind = "ident" end
      add(kind, i, e)
      i = e + 1
    else
      local op = line:match("^%.%.%.", i) or line:match("^[=~<>]=", i) or line:match("^%.%.", i)
        or line:match("^::", i) or line:match("^//", i) or line:match("^[<>][<>]", i)
      local len = op and #op or 1
      add("operator", i, i + len - 1)
      i = i + len
    end
  end
  return tokens, nil
end

local Highlighter = {}
Highlighter.__index = Highlighter

function M.highlighter(getLines, tokenize)
  return setmetatable({ _getLines = getLines, _tokenize = tokenize or M.tokenize,
    _tokens = {}, _endStates = {}, _valid = 1 }, Highlighter)
end

function Highlighter:invalidate(line)
  line = math.max(1, line or 1)
  if line < self._valid then self._valid = line end
end

function Highlighter:tokens(index)
  local ls = self._getLines()
  if index > #ls then return {} end
  if index >= self._valid then
    local i = self._valid
    while i <= index do
      local startState = i > 1 and self._endStates[i - 1] or nil
      local toks, endState = self._tokenize(ls[i], startState)
      self._tokens[i] = toks
      self._endStates[i] = endState
      i = i + 1
    end

    self._valid = index + 1
  end
  return self._tokens[index]
end

return M

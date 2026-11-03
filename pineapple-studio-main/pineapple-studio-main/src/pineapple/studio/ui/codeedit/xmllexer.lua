-- Line-based XML tokenizer for the code editor. Produces the same token shape and
-- carry-over state as the Lua lexer ({ type, from, to } tokens and { kind, level } states),
-- reusing the theme's syntax colours:
--   keyword  tag names         global  attribute names     string  attribute values, CDATA
--   comment  <!-- comments --> value   entities, <?xml ?>  operator < > / = punctuation
local M = {}

local NAME = "^[%w_:%-%.]+"

local function add(tokens, kind, from, to)
  if to >= from then tokens[#tokens + 1] = { type = kind, from = from, to = to } end
end

-- Tokenizes attributes inside an open tag, from position i. Returns the next position and,
-- when the tag doesn't close on this line, the state to carry into the next line.
local function tagBody(line, i, tokens)
  local n = #line
  while i <= n do
    local c = line:sub(i, i)
    if c:match("%s") then
      local _, e = line:find("^%s+", i)
      i = e + 1
    elseif line:sub(i, i + 1) == "/>" or line:sub(i, i + 1) == "?>" then
      add(tokens, "operator", i, i + 1)
      return i + 2, nil
    elseif c == ">" then
      add(tokens, "operator", i, i)
      return i + 1, nil
    elseif c == '"' or c == "'" then
      local close = line:find(c, i + 1, true)
      if not close then
        add(tokens, "string", i, n)
        return n + 1, { kind = "string", level = c:byte() }
      end
      add(tokens, "string", i, close)
      i = close + 1
    elseif c:match("[%w_:%-%.]") then
      local _, e = line:find(NAME, i)
      add(tokens, "global", i, e)
      i = e + 1
    else
      add(tokens, "operator", i, i)
      i = i + 1
    end
  end
  return i, { kind = "tag", level = 0 }
end

local function text(line, from, to, tokens)
  local i = from
  while i <= to do
    local s, e = line:find("&[#%w]+;", i)
    if not s or e > to then add(tokens, "ident", i, to) return end
    add(tokens, "ident", i, s - 1)
    add(tokens, "value", s, e)
    i = e + 1
  end
end

function M.tokenize(line, state)
  local tokens, n, i = {}, #line, 1

  if state then
    if state.kind == "comment" or state.kind == "cdata" then
      local close = state.kind == "comment" and "-->" or "]]>"
      local kind = state.kind == "comment" and "comment" or "string"
      local _, e = line:find(close, 1, true)
      if not e then add(tokens, kind, 1, n) return tokens, state end
      add(tokens, kind, 1, e)
      i = e + 1
    elseif state.kind == "string" then
      local close = line:find(string.char(state.level), 1, true)
      if not close then add(tokens, "string", 1, n) return tokens, state end
      add(tokens, "string", 1, close)
      local carry
      i, carry = tagBody(line, close + 1, tokens)
      if carry then return tokens, carry end
    elseif state.kind == "tag" then
      local carry
      i, carry = tagBody(line, 1, tokens)
      if carry then return tokens, carry end
    end
  end

  while i <= n do
    local lt = line:find("<", i, true)
    text(line, i, (lt or n + 1) - 1, tokens)
    if not lt then break end
    if line:sub(lt, lt + 3) == "<!--" then
      local _, e = line:find("-->", lt + 4, true)
      if not e then add(tokens, "comment", lt, n) return tokens, { kind = "comment", level = 0 } end
      add(tokens, "comment", lt, e)
      i = e + 1
    elseif line:sub(lt, lt + 8) == "<![CDATA[" then
      add(tokens, "operator", lt, lt + 8)
      local s, e = line:find("]]>", lt + 9, true)
      if not s then add(tokens, "string", lt + 9, n) return tokens, { kind = "cdata", level = 0 } end
      add(tokens, "string", lt + 9, s - 1)
      add(tokens, "operator", s, e)
      i = e + 1
    else
      local p = lt + 1
      local prefix = line:match("^[/?!]", p)
      if prefix then p = p + 1 end
      add(tokens, "operator", lt, p - 1)
      local s, e = line:find(NAME, p)
      if s then
        add(tokens, prefix == "?" and "value" or "keyword", s, e)
        p = e + 1
      end
      local carry
      i, carry = tagBody(line, p, tokens)
      if carry then return tokens, carry end
    end
  end
  return tokens, nil
end

return M

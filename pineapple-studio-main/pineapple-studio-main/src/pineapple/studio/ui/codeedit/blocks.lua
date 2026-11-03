local M = {}

local OPENERS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSERS = { ["end"] = true, ["until"] = true }
local BRACKETS = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local CLOSING = { [")"] = "(", ["]"] = "[", ["}"] = "{" }
M.OPENERS, M.CLOSERS = OPENERS, CLOSERS

local MAX_LINES = 5000

local function word(lines, i, tok) return lines[i]:sub(tok.from, tok.to) end

local function classify(lines, i, tok)
  local text = word(lines, i, tok)
  if tok.type == "keyword" then
    if OPENERS[text] then return "open", "keyword", text end
    if CLOSERS[text] then return "close", "keyword", text end
  elseif tok.type == "operator" then
    if BRACKETS[text] then return "open", text, text end
    if CLOSING[text] then return "close", CLOSING[text], text end
  end
  return nil
end

function M.unclosed(lines, tokens)
  local depth = 0
  for i = 1, math.min(#lines, MAX_LINES) do
    for _, tok in ipairs(tokens(i)) do
      local what, kind = classify(lines, i, tok)
      if kind == "keyword" then depth = depth + (what == "open" and 1 or -1) end
    end
  end
  return depth
end

function M.opensAt(line, lineTokens, col)
  local last, firstKeyword
  for _, tok in ipairs(lineTokens) do
    if tok.to < col and tok.type ~= "comment" then
      last = tok
      if tok.type == "keyword" and not firstKeyword then firstKeyword = line:sub(tok.from, tok.to) end
    end
  end
  if not last then return nil end
  local text = line:sub(last.from, last.to)
  if last.type == "operator" and BRACKETS[text] then return BRACKETS[text] end
  if last.type == "keyword" then
    if text == "then" then return firstKeyword == "elseif" and "indent" or "end" end
    if text == "do" then return "end" end
    if text == "repeat" then return "until" end
    if text == "else" then return "indent" end
  end

  if text == ")" then
    local before = line:sub(1, last.to)
    local fnStart = before:find("function%s*[%w_%.:]*%s*%b()$")
    if fnStart then
      for _, tok in ipairs(lineTokens) do
        if tok.from == fnStart and tok.type == "keyword" then return "end" end
      end
    end
  end
  return nil
end

function M.openerIndent(lines, tokens, index, closer)
  local kind = CLOSING[closer] or "keyword"
  local depth = 1
  for i = index - 1, math.max(1, index - MAX_LINES), -1 do
    local toks = tokens(i)
    for t = #toks, 1, -1 do
      local what, k = classify(lines, i, toks[t])
      if k == kind then
        depth = depth + (what == "close" and 1 or -1)
        if depth == 0 then return lines[i]:match("^[ \t]*") end
      end
    end
  end
  return nil
end

function M.enclosing(lines, tokens, line, outer)
  local opener, openerLine
  if not outer then
    local stack = {}
    for _, tok in ipairs(tokens(line)) do
      local what, kind = classify(lines, line, tok)
      if kind == "keyword" then
        if what == "open" then stack[#stack + 1] = tok
        elseif #stack > 0 then stack[#stack] = nil end
      end
    end
    if stack[1] then opener, openerLine = stack[1], line end
  end
  if not opener then
    local depth = 0

    for i = line - 1, math.max(1, line - MAX_LINES), -1 do
      local list = tokens(i)
      for t = #list, 1, -1 do
        local what, kind = classify(lines, i, list[t])
        if kind == "keyword" then
          if what == "close" then depth = depth + 1
          elseif depth == 0 then opener, openerLine = list[t], i break
          else depth = depth - 1 end
        end
      end
      if opener then break end
    end
  end
  if not opener then return nil end
  local _, other = M.match(lines, tokens, openerLine, opener.from + 1)
  return openerLine, other and other.line or #lines
end

function M.match(lines, tokens, line, col)
  local toks = tokens(line)
  local target

  for _, c in ipairs({ col - 1, col }) do
    for _, tok in ipairs(toks) do
      if c >= tok.from and c <= tok.to then
        local what = classify(lines, line, tok)
        local w = word(lines, line, tok)
        if what or (tok.type == "keyword" and (w == "while" or w == "for")) then target = tok break end
      end
    end
    if target then break end
  end
  if not target then return nil end

  local startTok, startLine = target, line
  local text = word(lines, line, target)
  local here = { line = line, from = target.from, to = target.to }

  if text == "while" or text == "for" then
    local found
    for i = line, math.min(#lines, line + 50) do
      for _, tok in ipairs(tokens(i)) do
        if (i > line or tok.from > target.to) and tok.type == "keyword" and word(lines, i, tok) == "do" then
          found = tok; startLine = i; break
        end
      end
      if found then break end
    end
    if not found then return nil end
    startTok = found
  end

  local what, kind = classify(lines, startLine, startTok)
  local depth = 0
  if what == "open" then
    for i = startLine, math.min(#lines, startLine + MAX_LINES) do
      for _, tok in ipairs(tokens(i)) do
        if i > startLine or tok.from >= startTok.from then
          local w2, k2 = classify(lines, i, tok)
          if k2 == kind then
            depth = depth + (w2 == "open" and 1 or -1)
            if depth == 0 then return here, { line = i, from = tok.from, to = tok.to } end
          end
        end
      end
    end
  else
    for i = startLine, math.max(1, startLine - MAX_LINES), -1 do
      local list = tokens(i)
      for t = #list, 1, -1 do
        local tok = list[t]
        if i < startLine or tok.from <= startTok.from then
          local w2, k2 = classify(lines, i, tok)
          if k2 == kind then
            depth = depth + (w2 == "close" and 1 or -1)
            if depth == 0 then
              local other = { line = i, from = tok.from, to = tok.to }

              if kind == "keyword" and word(lines, i, tok) == "do" then
                for t2 = t - 1, 1, -1 do
                  local w3 = word(lines, i, list[t2])
                  if list[t2].type == "keyword" and (w3 == "while" or w3 == "for") then
                    other = { line = i, from = list[t2].from, to = list[t2].to } break
                  end
                end
              end
              return here, other
            end
          end
        end
      end
    end
  end
  return nil
end

return M

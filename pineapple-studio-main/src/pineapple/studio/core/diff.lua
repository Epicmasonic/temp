-- Line-based text diff used for change reviews and Local History.
--   compute(old, new) -> ops: { kind = "same" | "del" | "add", text, old = line, new = line }
--   hunks(ops, context) -> the changed ops with `context` unchanged lines around them, and
--                          { kind = "gap" } rows where unchanged lines were skipped
--   stats(ops) -> added, removed
local M = {}

-- Above this many cells (changed old lines x changed new lines) the middle section is shown
-- as a whole replacement instead of a minimal diff, to keep memory and time bounded.
local MAX_CELLS = 100000

function M.lines(text)
  local out = {}
  if text == nil or text == "" then return out end
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if text:sub(-1) == "\n" then out[#out] = nil end
  return out
end

function M.compute(oldText, newText)
  local a, b = M.lines(oldText), M.lines(newText)
  local ops = {}
  local function push(kind, text, oldLine, newLine)
    ops[#ops + 1] = { kind = kind, text = text, old = oldLine, new = newLine }
  end

  local prefix = 0
  while prefix < #a and prefix < #b and a[prefix + 1] == b[prefix + 1] do prefix = prefix + 1 end
  local suffix = 0
  while suffix < #a - prefix and suffix < #b - prefix and a[#a - suffix] == b[#b - suffix] do
    suffix = suffix + 1
  end
  for i = 1, prefix do push("same", a[i], i, i) end

  local n, m = #a - prefix - suffix, #b - prefix - suffix
  if n > 0 and m > 0 and n * m <= MAX_CELLS then
    -- Longest common subsequence over the changed middle section.
    local width = m + 1
    local L = {}
    for i = n, 0, -1 do
      for j = m, 0, -1 do
        local index = i * width + j
        if i == n or j == m then
          L[index] = 0
        elseif a[prefix + i + 1] == b[prefix + j + 1] then
          L[index] = L[(i + 1) * width + j + 1] + 1
        else
          local down, right = L[(i + 1) * width + j], L[i * width + j + 1]
          L[index] = down >= right and down or right
        end
      end
    end
    local i, j = 0, 0
    while i < n and j < m do
      local oldLine, newLine = prefix + i + 1, prefix + j + 1
      if a[oldLine] == b[newLine] then
        push("same", a[oldLine], oldLine, newLine)
        i, j = i + 1, j + 1
      elseif L[(i + 1) * width + j] >= L[i * width + j + 1] then
        push("del", a[oldLine], oldLine, nil)
        i = i + 1
      else
        push("add", b[newLine], nil, newLine)
        j = j + 1
      end
    end
    for k = i, n - 1 do push("del", a[prefix + k + 1], prefix + k + 1, nil) end
    for k = j, m - 1 do push("add", b[prefix + k + 1], nil, prefix + k + 1) end
  else
    for k = 1, n do push("del", a[prefix + k], prefix + k, nil) end
    for k = 1, m do push("add", b[prefix + k], nil, prefix + k) end
  end

  for k = 1, suffix do push("same", a[#a - suffix + k], #a - suffix + k, #b - suffix + k) end
  return ops
end

function M.hunks(ops, context)
  context = context or 3
  local keep, any = {}, false
  for i, op in ipairs(ops) do
    if op.kind ~= "same" then
      any = true
      for k = math.max(1, i - context), math.min(#ops, i + context) do keep[k] = true end
    end
  end
  if not any then return {} end
  local rows, last = {}, 0
  for i, op in ipairs(ops) do
    if keep[i] then
      if i > last + 1 then rows[#rows + 1] = { kind = "gap" } end
      rows[#rows + 1] = op
      last = i
    end
  end
  if last < #ops then rows[#rows + 1] = { kind = "gap" } end
  return rows
end

function M.stats(ops)
  local added, removed = 0, 0
  for _, op in ipairs(ops) do
    if op.kind == "add" then added = added + 1 elseif op.kind == "del" then removed = removed + 1 end
  end
  return added, removed
end

return M

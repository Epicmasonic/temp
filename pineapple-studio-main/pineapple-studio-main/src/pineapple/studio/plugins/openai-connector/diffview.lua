-- Review tab for the changes from one AI reply: every file's diff in one place, a checkbox per
-- file, and Apply / Cancel. Closing the tab counts as Cancel.
local diff = require("pineapple.studio.core.diff")
local scrollbar = require("pineapple.studio.ui.scrollbar")

local M = {}

-- options.changes: { { label, oldText, newText, created } }
-- options.onDecide(included, closing): a list of booleans by change index, or nil when
-- cancelled; closing is true when the tab is already being closed.
function M.new(host, studio, options)
  local ui = studio.ui
  local self = { scroll = 0, changes = options.changes, answered = false }
  for _, change in ipairs(self.changes) do
    change.include = true
    local ops = diff.compute(change.oldText or "", change.newText)
    change.added, change.removed = diff.stats(ops)
    change.rows = diff.hunks(ops, 2)
  end
  local canvas

  local function buildLines()
    local out = {}
    for i, c in ipairs(self.changes) do
      out[#out + 1] = { kind = "file", index = i,
        text = ("[%s] %d. %s  +%d -%d%s"):format(c.include and "x" or " ", i, c.label, c.added, c.removed,
          c.created and "  (new file)" or "") }
      for _, r in ipairs(c.rows) do
        if r.kind == "gap" then
          out[#out + 1] = { kind = "gap", text = "  ..." }
        else
          local mark = r.kind == "add" and "+" or (r.kind == "del" and "-" or " ")
          out[#out + 1] = { kind = r.kind, text = mark .. " " .. (r.text:gsub("\t", "  ")) }
        end
      end
      if #c.rows == 0 then out[#out + 1] = { kind = "gap", text = "  (no changes to the text)" } end
      out[#out + 1] = { kind = "blank", text = "" }
    end
    return out
  end

  local function selectedCount()
    local n = 0
    for _, c in ipairs(self.changes) do if c.include then n = n + 1 end end
    return n
  end

  local function decide(apply, closing)
    if self.answered then return end
    self.answered = true
    local included
    if apply then
      included = {}
      for i, c in ipairs(self.changes) do included[i] = c.include end
      if selectedCount() == 0 then included = nil end
    end
    if options.onDecide then options.onDecide(included, closing == true) end
  end

  local function toggle(index)
    local c = self.changes[index]
    if not c or self.answered then return end
    c.include = not c.include
    canvas:markRenderDirty()
  end

  local function draw(_, buf)
    local t = ui:theme()
    local w, h = canvas.width, canvas.height
    local hbg, hfg = t.panelHeaderBackground, t.panelHeaderForeground
    buf:fill(1, 1, w, h, " ", t.foreground, t.editorBackground)
    buf:fill(1, 1, w, 1, " ", hfg, hbg)
    local title = ("Review AI Changes: %d file%s, %d selected"):format(#self.changes,
      #self.changes == 1 and "" or "s", selectedCount())
    buf:blit(2, 1, title:sub(1, math.max(0, w - 2)), hfg, hbg)

    local lines = buildLines()
    self.lines = lines
    local body = math.max(0, h - 2)
    self.scroll = math.max(0, math.min(self.scroll, #lines - body))
    local barW = #lines > body and 1 or 0
    for row = 1, body do
      local line = lines[self.scroll + row]
      if not line then break end
      local color = t.foreground
      if line.kind == "file" then color = t.accent
      elseif line.kind == "add" then color = colors.green
      elseif line.kind == "del" then color = colors.red
      elseif line.kind == "gap" then color = t.muted end
      buf:blit(2, row + 1, line.text:sub(1, math.max(0, w - 2 - barW)), color, t.editorBackground)
    end
    if barW == 1 then scrollbar.draw(buf, t, w, 2, body, #lines, body, self.scroll) end

    buf:fill(1, h, w, 1, " ", hfg, hbg)
    self.buttons = {}
    local x = 1
    for _, b in ipairs({ { " Apply ", true }, { " Cancel ", false } }) do
      local label, apply = b[1], b[2]
      local active = apply and selectedCount() > 0
      buf:blit(x, h, label, apply and (active and (t.tabActiveForeground or t.accentForeground or hfg) or t.muted) or hfg,
        apply and active and (t.tabActiveBackground or t.accent) or hbg)
      self.buttons[#self.buttons + 1] = { x1 = x, x2 = x + #label - 1, apply = apply }
      x = x + #label + 1
    end
    local hint = "Y apply  N/Esc cancel  1-9 or click a file: include"
    if x + #hint <= w then buf:blit(x + 1, h, hint, t.muted, hbg) end
  end

  canvas = host:addCanvas({
    x = 1, y = 1, width = function() return host.width end, height = function() return host.height end,
    background = ui:theme().editorBackground, draw = draw,
  })

  canvas:onClick(function(_, _, x, y)
    if y == canvas.height then
      for _, b in ipairs(self.buttons or {}) do
        if x >= b.x1 and x <= b.x2 then decide(b.apply) return end
      end
      return
    end
    local line = self.lines and self.lines[self.scroll + y - 1]
    if line and line.kind == "file" then toggle(line.index) end
  end)
  canvas:onKey(function(_, key)
    local page = math.max(1, canvas.height - 3)
    if key == keys.up then self.scroll = math.max(0, self.scroll - 1)
    elseif key == keys.down then self.scroll = self.scroll + 1
    elseif key == keys.pageUp then self.scroll = math.max(0, self.scroll - page)
    elseif key == keys.pageDown then self.scroll = self.scroll + page
    elseif key == keys.escape then decide(false) return
    else return end
    canvas:markRenderDirty()
  end)
  canvas:onChar(function(_, ch)
    if ch == "y" or ch == "Y" then decide(true)
    elseif ch == "n" or ch == "N" then decide(false)
    elseif ch:match("%d") then toggle(tonumber(ch)) end
  end)
  canvas:onScroll(function(_, direction)
    self.scroll = math.max(0, self.scroll + direction)
    canvas:markRenderDirty()
  end)
  canvas:focus()

  function self.focus() canvas:focus() end
  function self.cancel() decide(false) end
  function self.applyTheme() canvas.background = ui:theme().editorBackground; canvas:markRenderDirty() end
  function self.dispose()
    decide(false, true)
    canvas:destroy()
  end
  return self
end

return M

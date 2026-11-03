local dialogs = require("pineapple.studio.ui.dialogs")

local R = {}

local function bg(t) return t.editorBackground end

function R.blank(rows)
  rows[#rows + 1] = { draw = function() end }
end

function R.text(rows, text, w, ctx, opts)
  opts = opts or {}
  local indent = opts.indent or 0
  for _, line in ipairs(dialogs.wrap(text, math.max(4, w - indent))) do
    rows[#rows + 1] = { draw = function(buf, x, y)
      local t = ctx.theme
      buf:blit(x + indent, y, line, opts.color and opts.color(t) or t.muted, bg(t))
    end }
  end
end

function R.header(rows, text, ctx)
  rows[#rows + 1] = { draw = function(buf, x, y, w)
    local t = ctx.theme
    local s = text:sub(1, w)
    buf:blit(x, y, s, t.accent, bg(t))
    local rx = x + #s + 1
    if rx <= x + w - 1 then
      buf:blit(rx, y, string.rep("\140", x + w - rx), t.dividerForeground or t.muted, bg(t))
    end
  end }
end

function R.item(rows, it, w, ctx)
  local cw = it.controlW or 0
  local textW = math.max(4, cw > 0 and (w - cw - 2) or w)
  local controlOff = w - cw
  local titles = dialogs.wrap(it.title or "", textW)
  if #titles == 0 then titles = { "" } end
  for i, line in ipairs(titles) do
    local first = i == 1
    rows[#rows + 1] = {
      focusable = first and it.activate ~= nil, activate = first and it.activate or nil,
      cycle = first and it.cycle or nil, key = first and it.key or nil,
      draw = function(buf, x, y, _, focused, hit)
        local t = ctx.theme
        buf:blit(x, y, line, it.titleColor and it.titleColor(t) or t.foreground, bg(t))
        if first and it.control then it.control(buf, x + controlOff, y, cw, focused, hit) end
      end,
    }
  end
  if it.description and it.description ~= "" then

    local descW = textW >= 20 and textW or w
    local lines = dialogs.wrap(it.description, math.max(4, descW - 2))
    local max = it.maxLines or 4
    for i = 1, math.min(#lines, max) do
      local line = lines[i]
      if i == max and #lines > max then line = line:sub(1, math.max(1, descW - 3)) .. "~" end
      rows[#rows + 1] = { draw = function(buf, x, y)
        local t = ctx.theme
        buf:blit(x + 2, y, line, t.muted, bg(t))
      end }
    end
  end
  if it.meta or it.link then
    local link = it.link
    rows[#rows + 1] = { draw = function(buf, x, y, w2, _, hit)
      local t = ctx.theme
      if it.meta then
        local room = link and (textW - 2) or (w2 - 2)
        buf:blit(x + 2, y, it.meta:sub(1, math.max(0, room)), it.metaColor and it.metaColor(t) or t.muted, bg(t))
      end
      if link then
        local lx = x + (cw >= #link.text and controlOff + cw - #link.text or w2 - #link.text)
        buf:blit(lx, y, link.text, t.accent, bg(t))
        hit(lx, lx + #link.text - 1, link.action)
      end
    end }
  end
  if not it.compact then R.blank(rows) end
end

local function colors_(t, focused)
  if focused then return t.accentForeground, t.accent end
  return t.inputForeground, t.fieldBackground or t.inputBackground
end
R.controlColors = colors_

function R.checkbox(checked, locked, onClick)
  return 3, function(buf, x, y, _, focused, hit)
    local t = R.theme
    local fg, cbg = colors_(t, focused)
    if not focused and checked then fg = t.accent end
    buf:blit(x, y, locked and "[*]" or (checked and "[x]" or "[ ]"), fg, cbg)
    if onClick then hit(x, x + 2, onClick) end
  end
end

function R.radio(selected, onClick)
  return 3, function(buf, x, y, _, focused, hit)
    local t = R.theme
    local fg, cbg = colors_(t, focused)
    if not focused and selected then fg = t.accent end
    buf:blit(x, y, selected and "(*)" or "( )", fg, cbg)
    hit(x, x + 2, onClick)
  end
end

function R.box(label, w, opts, onClick)
  opts = opts or {}
  return w, function(buf, x, y, cw, focused, hit)
    local t = R.theme
    local fg, cbg = colors_(t, focused)
    if opts.color and not focused then fg = opts.color(t) end
    if opts.button and not focused then fg, cbg = t.accentForeground, t.accent end
    local text
    if opts.arrow then
      text = (" " .. label .. string.rep(" ", cw)):sub(1, cw - 2) .. "v "
    elseif opts.button then
      text = (" " .. label .. " "):sub(1, cw)
      text = text .. string.rep(" ", cw - #text)
    else
      text = (" " .. label .. string.rep(" ", cw)):sub(1, cw)
    end
    buf:blit(x, y, text, fg, cbg)
    if onClick then hit(x, x + cw - 1, function() onClick(x, y) end) end
  end
end

local KEY_NAMES = {
  comma = ",", period = ".", grave = "`", slash = "/", backslash = "\\", minus = "-", equals = "=",
  semicolon = ";", apostrophe = "'", leftBracket = "[", rightBracket = "]",
  pageup = "PgUp", pagedown = "PgDn", numpadenter = "NumEnter",
  one = "1", two = "2", three = "3", four = "4", five = "5", six = "6", seven = "7", eight = "8",
  nine = "9", zero = "0", space = "Space", enter = "Enter", backspace = "Backspace", tab = "Tab",
  insert = "Ins", delete = "Del",
}
function R.chordText(chord)
  if not chord then return "" end
  local parts = {}
  for part in chord:gmatch("[^+]+") do
    local k = KEY_NAMES[part:lower()]
    if not k then
      k = #part == 1 and part:upper() or (part:sub(1, 1):upper() .. part:sub(2))
    end
    parts[#parts + 1] = k
  end
  return table.concat(parts, "+")
end

return R

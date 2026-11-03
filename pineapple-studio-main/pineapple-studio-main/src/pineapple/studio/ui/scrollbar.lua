local M = {}

function M.thumb(height, total, visible, offset)
  if total <= visible or height < 1 then return nil end
  local size = math.max(1, math.floor(height * visible / total))
  local maxOffset = total - visible
  local start = math.floor((height - size) * offset / maxOffset + 0.5)
  return start, size
end

function M.draw(buf, theme, x, y, height, total, visible, offset)
  local start, size = M.thumb(height, total, visible, offset)
  if not start then return false end
  local track = theme.scrollbarTrack or colors.lightGray
  local thumb = theme.scrollbarThumb or colors.gray
  for row = 0, height - 1 do
    local on = row >= start and row < start + size
    buf:blit(x, y + row, " ", colors.white, on and thumb or track)
  end
  return true
end

function M.offsetAt(row, height, total, visible)
  if total <= visible then return 0 end
  local _, size = M.thumb(height, total, visible, 0)
  local ratio = (row - size / 2) / math.max(1, height - size)
  return math.max(0, math.min(total - visible, math.floor(ratio * (total - visible) + 0.5)))
end

return M

local R = require("pineapple.studio.ui.rows")
local themes = require("pineapple.studio.ui.theme")

local M = {}

function M.new(ctx)
  local settings = ctx.studio.settings
  local page = { id = "themes", label = "Themes", placeholder = "Search themes" }

  function page.rows(w, query)
    local rows = {}
    local current = settings:get("workbench.theme", themes.DEFAULT)
    local any = false
    for _, t in ipairs(themes.list()) do
      local text = (t.name .. " " .. t.id .. " " .. (t.description or "")):lower()
      local ok = true
      for word in query:lower():gmatch("%S+") do if not text:find(word, 1, true) then ok = false end end
      if ok then
        any = true
        local id = t.id
        local function pick() settings:set("workbench.theme", id); ctx.dirty() end
        local it = {
          key = id,
          title = t.name,
          titleColor = id == current and function(th) return th.accent end or nil,
          description = t.description,
          meta = id == current and "current theme" or nil,
          activate = pick,
        }
        it.controlW, it.control = R.radio(id == current, pick)
        R.item(rows, it, w, ctx)
      end
    end
    if not any then R.text(rows, "No themes match.", w, ctx) end
    return rows
  end
  return page
end

return M

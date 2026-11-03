local R = require("pineapple.studio.ui.rows")

local M = {}

local STATE_LABELS = {
  active = "active", inactive = "starts when needed", activating = "starting", failed = "failed to start",
  disabled = "off",
}

function M.new(ctx)
  local studio = ctx.studio
  local plugins, ui = studio.plugins, studio.ui
  local page = { id = "plugins", label = "Plugins", placeholder = "Search plugins" }

  local function entries(query)
    local out = {}
    for _, p in ipairs(plugins:list()) do
      local text = (p.name .. " " .. p.id .. " " .. (p.description or "")):lower()
      local ok = true
      for word in query:lower():gmatch("%S+") do
        if not text:find(word, 1, true) then ok = false end
      end
      if ok then out[#out + 1] = p end
    end
    table.sort(out, function(a, b)
      if a.builtin ~= b.builtin then return not a.builtin end
      if a.required ~= b.required then return b.required end
      return a.name:lower() < b.name:lower()
    end)
    return out
  end

  local function toggle(p)
    if p.required then ui:notify(p.name .. " is part of Studio and can't be turned off", "info", 3) return end
    if p.state == "disabled" or p.state == "failed" then
      plugins:enable(p.id)
      local now
      for _, q in ipairs(plugins:list()) do if q.id == p.id then now = q end end
      if now and now.state == "failed" then ui:notify(p.name .. " failed to start", "error", 4)
      else ui:notify(p.name .. " turned on", "info", 2) end
    else
      plugins:disable(p.id)
      ui:notify(p.name .. " turned off", "info", 2)
    end
    ctx.dirty()
  end

  local function reload()
    local n = plugins:rediscover()
    ui:notify(n > 0 and ("Found " .. n .. " new plugin" .. (n == 1 and "" or "s")) or "No new plugins", "info", 2)
    ctx.dirty()
  end

  function page.header()
    return { { label = " Reload ", button = true, action = reload } }
  end

  function page.rows(w, query)
    local rows = {}
    local list = entries(query)
    if #list == 0 then R.text(rows, "No plugins match.", w, ctx) end
    for _, p in ipairs(list) do
      local on = p.state ~= "disabled" and p.state ~= "failed"
      local function click() toggle(p) end
      local it = {
        key = p.id,
        title = p.name .. "  " .. (p.version or ""),
        description = p.description or p.id,
        meta = (p.required and "part of Studio" or (p.builtin and "built-in" or "your plugin"))
          .. " \7 " .. (STATE_LABELS[p.state] or p.state),
        metaColor = p.state == "failed" and function() return colors.red end or nil,
        activate = click,
        compact = p.error ~= nil,
      }
      it.controlW, it.control = R.checkbox(on, p.required, click)
      R.item(rows, it, w, ctx)
      if p.error then
        R.text(rows, "Error: " .. p.error:gsub("\n", " "), w - 5, ctx, { indent = 2, color = function() return colors.red end })
        R.blank(rows)
      end
    end
    local errors = plugins:errors()
    if #errors > 0 then
      R.header(rows, "Couldn't load", ctx)
      for _, e in ipairs(errors) do R.text(rows, e:gsub("\n", " "), w, ctx, { indent = 2 }) end
      R.blank(rows)
    end
    R.text(rows, "Your plugins go in " .. plugins:userFolder() .. ". Reload finds new ones.", w, ctx)
    return rows
  end

  function page.toggleId(id)
    for _, p in ipairs(plugins:list()) do if p.id == id then toggle(p) return true end end
    return false
  end
  return page
end

return M

local lint = require("pineapple.studio.core.lint")
local search = require("pineapple.studio.core.search")
local ccapi = require("pineapple.studio.ui.codeedit.ccapi")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws = studio.ui, studio.workspace
  local known = lint.knownGlobals(_G, ccapi)
  local results = {}
  local projectGlobals
  local panel

  local function isLua(path) return path:match("%.lua$") ~= nil end

  local function globalsOfProject()
    if projectGlobals then return projectGlobals end
    projectGlobals = {}
    for _, path in ipairs(search.files(ws, 500)) do
      if isLua(path) then
        local lines = search.lines(ws, path)
        if lines and not lint.syntax(lines) then
          for name in pairs(lint.definedGlobals(lines)) do projectGlobals[name] = true end
        end
      end
    end
    return projectGlobals
  end

  local function check(lines)
    if not studio.settings:get("problems.unknownGlobals", true) then
      local err = lint.syntax(lines)
      return err and { err } or {}
    end
    return lint.check(lines, { known = known, extra = globalsOfProject() })
  end

  local function refreshPanel()
    if panel then panel.canvas:markRenderDirty() end
    ui:refreshStatus()
  end

  local function checkEditor(e)
    local view = e.instance and e.instance.view
    if not view or e.doc.virtual or not isLua(e.doc.path) then return end
    local list = check(e.doc.lines)
    results[e.doc.path] = list
    view:setDiagnostics(list)
    refreshPanel()
  end

  local pending = {}
  local function schedule(e)
    if not pending[e] then
      pending[e] = studio.timers:debounce(0.4, function() checkEditor(e) end)
    end
    pending[e]()
  end

  local watched = {}
  local function watch(e)
    if watched[e] or e.doc.virtual or not isLua(e.doc.path) then return end
    watched[e] = true
    if e.store then
      e.store:add(e.doc:on("change", function() schedule(e) end))

      e.store:add(e.doc:on("save", function() projectGlobals = nil end))
    end
    checkEditor(e)
  end
  for _, e in ipairs(ui:editors()) do watch(e) end
  studio.events:on("editorOpened", watch)
  studio.events:on("editorClosed", function(e)
    watched[e] = nil
    if pending[e] then pending[e].cancel(); pending[e] = nil end
  end)
  ws:on("rootChanged", function() results, projectGlobals = {}, nil; refreshPanel() end)
  studio.settings:onChange("problems.unknownGlobals", function()
    for _, e in ipairs(ui:editors()) do checkEditor(e) end
  end)

  local function scanProject()
    projectGlobals = nil
    for _, path in ipairs(search.files(ws, 500)) do
      if isLua(path) then
        local lines = search.lines(ws, path)
        if lines then results[path] = check(lines) end
      end
    end
    for _, e in ipairs(ui:editors()) do checkEditor(e) end
    refreshPanel()
  end

  local function counts(list)
    local errors, warnings = 0, 0
    for _, d in ipairs(list or {}) do
      if d.severity == "error" then errors = errors + 1 else warnings = warnings + 1 end
    end
    return errors, warnings
  end

  local function rows()
    local out = {}
    local paths = {}
    for path, list in pairs(results) do if #list > 0 then paths[#paths + 1] = path end end
    table.sort(paths, function(a, b)
      local ea, eb = counts(results[a]), counts(results[b])
      if (ea > 0) ~= (eb > 0) then return ea > 0 end
      return a < b
    end)
    for _, path in ipairs(paths) do
      local list = {}
      for _, d in ipairs(results[path]) do list[#list + 1] = d end
      table.sort(list, function(a, b) return a.line < b.line or (a.line == b.line and a.col < b.col) end)
      for _, d in ipairs(list) do out[#out + 1] = { path = path, d = d } end
    end
    return out
  end

  ui:addPanel({
    id = "problems", title = "Problems", location = "bottom", order = 30,
    create = function(frame)
      local offset = 0
      local canvas
      canvas = frame:addCanvas({
        x = 1, y = 1,
        width = function() return frame.width end,
        height = function() return frame.height end,
        background = ui:theme().panelBackground,
        draw = function(_, buf)
          local t = ui:theme()
          local w, h = canvas.width, canvas.height
          local bg = t.panelBackground
          local list = rows()
          panel.rows = list
          offset = math.max(0, math.min(offset, #list - h))
          buf:fill(1, 1, w, h, " ", colors.white, bg)
          if #list == 0 then
            buf:blit(2, 1, ("No problems found"):sub(1, w - 1), colors.lightGray, bg)
          end
          for row = 1, h do
            local r = list[offset + row]
            if not r then break end
            local d = r.d
            local mark = d.severity == "error" and "E" or "W"
            local where = ws:relative(r.path) .. ":" .. d.line .. " "
            buf:blit(1, row, " " .. mark .. " ", colors.white, d.severity == "error" and colors.red or colors.orange)
            buf:blit(4, row, (" " .. where):sub(1, w - 3), colors.lightGray, bg)
            local x = 5 + #where
            if x <= w then buf:blit(x, row, d.message:sub(1, w - x + 1), colors.white, bg) end
          end
          require("pineapple.studio.ui.scrollbar").draw(buf, { scrollbarTrack = colors.gray, scrollbarThumb = colors.lightGray },
            w, 1, h, #list, h, offset)
        end,
      })
      canvas:onClick(function(_, _, x, y)
        if x == canvas.width and panel.rows and #panel.rows > canvas.height then
          offset = require("pineapple.studio.ui.scrollbar").offsetAt(y - 1, canvas.height, #panel.rows, canvas.height)
          canvas:markRenderDirty()
          return
        end
        local r = panel.rows and panel.rows[offset + y]
        if not r then return end
        local e = ui:openFile(r.path)
        if e and e.instance.view then e.instance.view:gotoLine(r.d.line, r.d.col); e.instance.view:focus() end
      end)
      canvas:onScroll(function(_, dir) offset = math.max(0, offset + dir); canvas:markRenderDirty() end)
      panel = { canvas = canvas }
      studio.events:on("themeChanged", function(t) canvas.background = t.panelBackground end)
      scanProject()
      return {
        focus = function() canvas:focus() end,
        refresh = scanProject,
        dispose = function() panel = nil end,
      }
    end,
  })

  ui:addStatusItem({
    id = "problems", align = "left", priority = 5,
    text = function()
      local e = ui:activeEditor()
      if not e or e.doc.virtual then return nil end
      local errors, warnings = counts(results[e.doc.path])
      if errors + warnings == 0 then return nil end
      local parts = {}
      if errors > 0 then parts[#parts + 1] = errors .. (errors == 1 and " error" or " errors") end
      if warnings > 0 then parts[#parts + 1] = warnings .. (warnings == 1 and " warning" or " warnings") end
      return table.concat(parts, ", ")
    end,
  })

  local function activeView()
    local e = ui:activeEditor()
    return e and e.instance.view
  end
  studio.commands:register("problems.show", function()
    ui:showPanel("problems")
    scanProject()
  end)
  local function step(delta)
    local v = activeView()
    if not v then return end
    local d = v:nextProblem(delta)
    if d then ui:notify(d.message, d.severity == "error" and "error" or "warning", 3)
    else ui:notify("No problems in this file", "info", 2) end
  end
  studio.commands:register("problems.next", function() step(1) end)
  studio.commands:register("problems.previous", function() step(-1) end)
end

return plugin

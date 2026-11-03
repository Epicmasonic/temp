
local termview = require("pineapple.studio.ui.termview")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws = studio.ui, studio.workspace
  local view, exited

  local function start()
    exited = false
    view:clear()
    local shellPath = "/rom/programs/shell.lua"
    local env = termview.programEnv(shellPath, ws:path(""), ui:shell())
    local fn, err = loadfile(shellPath, "t", env)
    if not fn then view:print(tostring(err), colors.red) return end
    view:run(fn)
  end

  ui:addPanel({
    id = "terminal", title = "Terminal", location = "bottom", order = 20,
    create = function(frame)
      view = termview.new(frame, {
        background = colors.black,
        onRawEvent = function(fn) return ui:onRawEvent(fn) end,
        onExit = function(v)
          exited = true
          v:print("[Shell exited - click to start a new one]", colors.lightGray)
        end,
        onLink = function(path, line)
          local editor = ui:openFile(path:sub(1, 1) == "/" and path or ("/" .. path))
          if editor and editor.instance.view then editor.instance.view:gotoLine(line) end
        end,
      })
      view.canvas:onClick(function() if exited then start() end end)
      start()
      return {
        focus = function() view:focus() end,
        dispose = function() view:dispose(); view = nil end,
      }
    end,
  })

  ws:on("rootChanged", function()
    if view then view:stop(true); start() end
  end)

  studio.commands:register("terminal.focus", function() ui:showPanel("terminal") end)
  studio.commands:register("terminal.restart", function()
    ui:showPanel("terminal")
    if view then view:stop(true); start() end
  end)
end

return plugin


local model = require("pineapple.studio.plugins.designer.model")
local designerView = require("designerview")
local basaltBackend = require("basaltbackend")
local bedrockBackend = require("bedrockbackend")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws = studio.ui, studio.workspace

  local function provider(id, title, pattern, makeBackend)
    studio.editors:register({
      id = id,
      title = title,
      score = function(path) return path:match(pattern) and 10 or 0 end,
      create = function(host, doc, opts)
        local backend = makeBackend(opts.studio)
        local view = designerView.new(host, doc, studio, backend, opts.theme)

        local instance = {
          designer = view,
          focus = function() view.focus() end,
          resize = function() view.layout() end,
          dispose = function() view.dispose() end,
          applyTheme = function(_, t) view.applyTheme(nil, t) end,
        }
        -- In Code mode, expose the text editor as `view` so the shared editor commands
        -- (find, select all, copy/cut, comment, move lines) act on it.
        view.onModeChange = function(codeView) instance.view = codeView end
        if view.mode == "code" then instance.view = view.code end
        return instance
      end,
    })
  end
  provider("pineapple.designer", "Basalt Designer", "%.xml$", function(s) return basaltBackend(s.basalt) end)
  provider("pineapple.bedrock-designer", "Bedrock Designer", "%.view$", function()
    return bedrockBackend.forProject(ws:path(""))
  end)

  local function activeDesigner()
    local e = ui:activeEditor()
    return e and e.instance.designer
  end
  local function onDesigner(fn)
    return function()
      local d = activeDesigner()
      if d then fn(d) end
    end
  end
  studio.commands:register("designer.undo", onDesigner(function(d) d.undoChange() end))
  studio.commands:register("designer.redo", onDesigner(function(d) d.redoChange() end))
  studio.commands:register("designer.delete", onDesigner(function(d) d.delete() end))
  studio.commands:register("designer.duplicate", onDesigner(function(d) d.duplicate() end))

end

return plugin

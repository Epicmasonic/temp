local settingsView = require("settingsview")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui = studio.ui

  local function open(page, scope)
    local editor = ui:openView({
      id = "settings", title = "Settings",
      create = function(host, opts) return settingsView.new(host, studio, opts.theme) end,
    })
    if editor then
      editor.instance.show(page, scope)
      editor.instance.focus()
    end
    return editor
  end

  studio.commands:register("settings.open", function() return open("general", "user") end)
  studio.commands:register("settings.project", function() return open("general", "project") end,
    { enabled = function() return ui:hasProject() end })
  studio.commands:register("settings.plugins", function() return open("plugins") end)
  studio.commands:register("settings.themes", function() return open("themes") end)
  studio.commands:register("settings.keybindings", function() return open("keys") end)
end

return plugin

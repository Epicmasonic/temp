
local plugin = {}

local BASALT_APP = [[
local basalt = require("basalt")
local xml = basalt.use("xml")

local main = basalt.getMainFrame()
local runningPath = shell.getRunningProgram()
local projectDir = fs.getDir(runningPath)
local xmlPath = fs.combine(projectDir, "ui/main.xml")
local clicks, clickLabel = 0, nil

local layout = xml.loadFile(main, xmlPath, {
  incrementClicks = function()
    clicks = clicks + 1
    clickLabel.text = "Clicks: " .. clicks
  end,
})
clickLabel = layout[1]:find("clickLabel")

basalt.run()
]]

local BASALT_XML = [[<frame name="app" width="51" height="19" background="32768">
  <label name="clickLabel" x="2" y="2" text="Clicks: 0"/>
  <button name="incrementButton" x="2" y="4" width="12" height="3" text="Click me" onClick="incrementClicks"/>
</frame>
]]

local function readBasaltBundle(pluginPath)
  local function read(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local text = handle.readAll()
    handle.close()
    return text
  end

  local candidates = {}
  if pluginPath then
    candidates[#candidates + 1] = fs.combine(pluginPath, "../../../../../lib/basalt/init.lua")
    candidates[#candidates + 1] = fs.combine(pluginPath, "../../../../../lib/basalt.lua")
  end
  for _, path in ipairs({ "/lib/basalt/init.lua", "/lib/basalt.lua", "/basalt.lua" }) do
    candidates[#candidates + 1] = path
  end
  for _, path in ipairs(candidates) do
    local source = read(path)
    if source then
      local licensePath = path:gsub("/init%.lua$", "/LICENSE")
      if licensePath == path then licensePath = path:gsub("%.lua$", "/LICENSE") end
      return source, read(licensePath)
    end
  end
end

local LUA_PROGRAM = [[
-- %s
-- Run it with F5 (this file) or F6 (the project's main file).

local function greet(name)
  print("Hello, " .. name .. "!")
end

greet("%s")
]]

local PLUGIN_MANIFEST = [[
return {
  id = "%s",
  name = "%s",
  version = "0.1.0",
  main = "main.lua",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "%s.hello", title = "Say Hello", category = "%s" },
    },
    menus = {
      { menu = "View", command = "%s.hello" },
    },
  },
}
]]

local PLUGIN_MAIN = [[
-- A Pineapple Studio plugin. ctx.studio is the plugin API: commands, editors,
-- workspace, settings, ui, timers, events, projects. Everything registered
-- through it is removed automatically when the plugin is turned off.

local plugin = {}

function plugin.activate(ctx)
  ctx.studio.commands:register("%s.hello", function()
    ctx.studio.ui:notify("Hello from %s!", "success")
  end)
end

return plugin
]]

local PLUGIN_README = [[
# %s

A Pineapple Studio plugin. To try it, copy this folder to
/.pineapple/studio/plugins/%s on the computer and restart Pineapple Studio.
Its command appears in the View menu and in the command palette (Ctrl+P).
]]

local function slug(name)
  local s = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s ~= "" and s or "plugin"
end

function plugin.activate(ctx)
  local projects = ctx.studio.projects

  projects:registerTemplate({
    id = "lua-program", order = 10,
    title = "Lua Program",
    description = "A main.lua that prints a greeting. F5 runs the open file, F6 runs main.lua.",
    create = function(_, p)
      p.write("main.lua", LUA_PROGRAM:format(p.name, p.name))
      p.setting("run.main", "main.lua")
    end,
  })

  projects:registerTemplate({
    id = "basalt-app", order = 20,
    title = "Basalt App",
    description = "A Basalt app that loads its XML layout from ui/main.xml.",
    create = function(_, p)
      p.write("main.lua", BASALT_APP)
      p.write("ui/main.xml", BASALT_XML)
      local basaltSource, basaltLicense = readBasaltBundle(ctx.plugin.path)
      if basaltSource then p.write("basalt.lua", basaltSource) end
      if basaltLicense then p.write("BASALT-LICENSE", basaltLicense) end
      if not basaltSource then
        p.write("BASALT-SETUP.txt", "Basalt was not found in this Pineapple Studio installation.\n"
          .. "Install Basalt 2.5 as basalt.lua in this project folder.\n")
      end
      p.setting("run.main", "main.lua")
    end,
  })

  projects:registerTemplate({
    id = "studio-plugin", order = 30,
    title = "Studio Plugin",
    description = "A plugin for Pineapple Studio itself: a manifest, a main module with one command, and a README.",
    create = function(_, p)
      local id = "user." .. slug(p.name)
      p.write("plugin.lua", PLUGIN_MANIFEST:format(id, p.name, id, p.name, id))
      p.write("main.lua", PLUGIN_MAIN:format(id, p.name))
      p.write("README.md", PLUGIN_README:format(p.name, slug(p.name)))
    end,
  })

  projects:registerTemplate({
    id = "empty", order = 90,
    title = "Empty Project",
    description = "Just a folder.",
    create = function() end,
  })
end

return plugin

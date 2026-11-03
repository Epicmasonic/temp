return {
  id = "pineapple.autosave",
  name = "Auto Save",
  version = "0.1.1",
  main = "main.lua",
  description = "Saves files automatically a moment after you stop typing.",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "autosave.toggle", title = "Toggle Auto Save", category = "File" },
    },
    menus = {
      { menu = "File", command = "autosave.toggle", group = "2" },
    },
    settings = {
      ["files.autoSave"] = { type = "boolean", default = false, title = "Save files automatically" },
      ["files.autoSaveDelay"] = { type = "number", default = 1, title = "Auto save delay",
        description = "Seconds after the last edit" },
    },
  },
}

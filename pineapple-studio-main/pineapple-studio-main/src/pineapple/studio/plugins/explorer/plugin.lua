return {
  id = "pineapple.explorer",
  name = "File Explorer",
  version = "0.2.0",
  main = "main.lua",
  description = "The project's files in the sidebar, with New File, Rename and Delete on right-click.",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "explorer.focus", title = "Show Explorer", category = "Explorer" },
      { id = "explorer.refresh", title = "Refresh", category = "Explorer" },
      { id = "explorer.newFile", title = "New File in Explorer...", category = "Explorer" },
      { id = "explorer.newFolder", title = "New Folder...", category = "Explorer" },
      { id = "explorer.rename", title = "Rename...", category = "Explorer" },
      { id = "explorer.delete", title = "Delete", category = "Explorer" },
      { id = "explorer.contextMenu", title = "Explorer Actions...", category = "Explorer" },
    },
    keybindings = {
      { key = "ctrl+e", command = "explorer.focus" },
      { key = "shift+f10", command = "explorer.contextMenu" },
      { key = "f2", command = "explorer.rename", when = "panelFocus:explorer" },
    },
    menus = {
    },
    settings = {
      ["explorer.showHidden"] = { type = "boolean", default = false, title = "Show hidden files" },
    },
  },
}

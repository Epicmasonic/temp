return {
  id = "pineapple.palette",
  name = "Search Everywhere",
  version = "0.2.0",
  main = "main.lua",
  description = "Search Everywhere: files, commands, functions and text in one popup.",
  contributes = {
    commands = {
      { id = "search.everywhere", title = "Search Everywhere...", category = "Go" },
      { id = "palette.show", title = "Command Palette...", category = "View" },
      { id = "file.open", title = "Go to File...", category = "Go" },
      { id = "search.symbols", title = "Go to Symbol...", category = "Go" },
      { id = "search.text", title = "Find in Files...", category = "Edit" },
    },
    keybindings = {
      { key = "ctrl+p", command = "search.everywhere" },
      { key = "ctrl+shift+p", command = "palette.show" },
      { key = "ctrl+o", command = "file.open" },
      { key = "ctrl+shift+o", command = "search.symbols" },
      { key = "ctrl+shift+f", command = "search.text" },
    },
    menus = {
      { menu = "View", command = "palette.show", group = "0" },
      { menu = "Edit", command = "search.text", group = "5" },
      { menu = "Go", command = "search.everywhere", group = "0" },
      { menu = "Go", command = "file.open", group = "1" },
      { menu = "Go", command = "search.symbols", group = "1" },
    },
  },
}

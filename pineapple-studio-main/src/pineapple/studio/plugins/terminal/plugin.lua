return {
  id = "pineapple.terminal",
  name = "Terminal",
  version = "0.1.0",
  main = "main.lua",
  description = "A CraftOS shell in the project folder (Ctrl+`).",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "terminal.focus", title = "Show Terminal", category = "View" },
      { id = "terminal.restart", title = "Restart Terminal", category = "View" },
    },
    keybindings = {
      { key = "ctrl+grave", command = "terminal.focus" },
    },
    menus = {
    },
  },
}

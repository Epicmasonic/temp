return {
  id = "pineapple.settings",
  name = "Settings",
  version = "0.1.1",
  main = "main.lua",
  description = "The Settings tab: general settings, plugins, themes and keyboard shortcuts.",
  required = true,
  contributes = {
    commands = {
      { id = "settings.open", title = "Settings...", category = "Settings" },
      { id = "settings.project", title = "Project Settings...", category = "Settings" },
      { id = "settings.plugins", title = "Plugins...", category = "Settings" },
      { id = "settings.themes", title = "Themes...", category = "Settings" },
      { id = "settings.keybindings", title = "Keyboard Shortcuts...", category = "Settings" },
    },
    keybindings = {
      { key = "ctrl+comma", command = "settings.open" },
    },
    menus = {
      { menu = "Studio", command = "settings.open", group = "1" },
      { menu = "Studio", command = "settings.plugins", group = "1" },
    },
  },
}

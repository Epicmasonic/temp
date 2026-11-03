return {
  id = "pineapple.problems",
  name = "Problems",
  version = "0.1.0",
  main = "main.lua",
  description = "Syntax errors and unknown globals as you type, and a Problems panel for the project.",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "problems.show", title = "Show Problems", category = "View" },
      { id = "problems.next", title = "Next Problem", category = "Go" },
      { id = "problems.previous", title = "Previous Problem", category = "Go" },
    },
    keybindings = {
      { key = "f2", command = "problems.next", when = "editorFocus" },
      { key = "shift+f2", command = "problems.previous", when = "editorFocus" },
    },
    menus = {
      { menu = "Go", command = "problems.next", group = "3" },
      { menu = "Go", command = "problems.previous", group = "3" },
    },
    settings = {
      ["problems.unknownGlobals"] = { type = "boolean", default = true, title = "Warn about unknown globals",
        description = "Names that are used but never defined, usually typos" },
    },
  },
}

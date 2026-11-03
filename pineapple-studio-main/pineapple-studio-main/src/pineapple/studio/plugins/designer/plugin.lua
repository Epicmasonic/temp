return {
  id = "pineapple.designer",
  name = "UI Designer",
  version = "0.2.0",
  main = "main.lua",
  description = "Drag-and-drop editors for Basalt XML layouts and Bedrock views (.view).",
  activation = { "onOpen:*.xml", "onOpen:*.view" },
  contributes = {
    commands = {
      { id = "designer.undo", title = "Undo (Designer)", category = "Designer", hidden = true },
      { id = "designer.redo", title = "Redo (Designer)", category = "Designer", hidden = true },
      { id = "designer.delete", title = "Delete Element", category = "Designer", hidden = true },
      { id = "designer.duplicate", title = "Duplicate Element", category = "Designer", hidden = true },
    },
    keybindings = {
      { key = "ctrl+z", command = "designer.undo", when = "activeEditor:pineapple.designer" },
      { key = "ctrl+y", command = "designer.redo", when = "activeEditor:pineapple.designer" },
      { key = "ctrl+shift+z", command = "designer.redo", when = "activeEditor:pineapple.designer" },
      { key = "ctrl+d", command = "designer.duplicate", when = "activeEditor:pineapple.designer" },
      { key = "ctrl+z", command = "designer.undo", when = "activeEditor:pineapple.bedrock-designer" },
      { key = "ctrl+y", command = "designer.redo", when = "activeEditor:pineapple.bedrock-designer" },
      { key = "ctrl+shift+z", command = "designer.redo", when = "activeEditor:pineapple.bedrock-designer" },
      { key = "ctrl+d", command = "designer.duplicate", when = "activeEditor:pineapple.bedrock-designer" },
    },
    fileTemplates = {
      { id = "designer.basalt", title = "Basalt UI Layout", extension = "xml", order = 20, group = "View",
        description = "Visual Basalt XML layout, loaded with basalt.use(\"xml\").loadFile", file = "templates/layout.xml" },
      { id = "designer.bedrock", title = "Bedrock View", extension = "view", order = 21, group = "View",
        description = "View for oeed's Bedrock (OneOS, Pineapple Studio)", file = "templates/view.view" },
    },
  },
}

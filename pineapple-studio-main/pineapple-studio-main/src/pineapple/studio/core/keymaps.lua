local M = {}

M.DEFAULT = "default"

M.list = {
  { id = "default", name = "Pineapple Studio", description = "Studio's own keys" },
  { id = "vscode", name = "VS Code", description = "Visual Studio Code's default keys" },
  { id = "intellij", name = "IntelliJ IDEA", description = "IntelliJ IDEA's default keys (Windows/Linux)" },
}

M.maps = {
  default = {},

  vscode = {
    ["search.everywhere"] = "ctrl+p",
    ["palette.show"] = { "ctrl+shift+p", "f1" },
    ["file.open"] = "ctrl+o",
    ["search.symbols"] = "ctrl+shift+o",
    ["search.text"] = "ctrl+shift+f",
    ["explorer.focus"] = "ctrl+shift+e",
    ["view.toggleSidebar"] = "ctrl+b",
    ["view.togglePanel"] = "ctrl+j",
    ["terminal.focus"] = "ctrl+grave",
    ["view.nextEditor"] = { "ctrl+pageDown", "ctrl+tab" },
    ["view.previousEditor"] = { "ctrl+pageUp", "ctrl+shift+tab" },
    ["file.close"] = { "ctrl+w", "ctrl+f4" },
    ["settings.open"] = "ctrl+comma",

    ["editor.find"] = "ctrl+f",
    ["editor.replace"] = "ctrl+h",
    ["editor.findNext"] = "f3",
    ["editor.findPrevious"] = "shift+f3",
    ["editor.gotoLine"] = "ctrl+g",
    ["editor.gotoDefinition"] = "f12",
    ["editor.navigateBack"] = "alt+left",
    ["editor.toggleComment"] = "ctrl+slash",
    ["editor.deleteLines"] = "ctrl+shift+k",
    ["editor.duplicateLines"] = "alt+shift+down",
    ["editor.moveLinesUp"] = "alt+up",
    ["editor.moveLinesDown"] = "alt+down",
    ["editor.complete"] = "ctrl+space",
    ["problems.next"] = "f8",
    ["problems.previous"] = "shift+f8",

    ["debug.file"] = "f5",
    ["debug.continue"] = "f5",
    ["debug.stepOver"] = "f10",
    ["debug.stepInto"] = "f11",
    ["debug.stepOut"] = "shift+f11",
    ["debug.stop"] = "shift+f5",
    ["debug.toggleBreakpoint"] = "f9",
    ["run.file"] = "ctrl+f5",
    ["run.stop"] = "shift+f5",
    ["run.fullscreen"] = false,
  },

  intellij = {

    ["search.everywhere"] = "ctrl+n",
    ["palette.show"] = "ctrl+shift+a",
    ["file.open"] = "ctrl+shift+n",
    ["search.symbols"] = "ctrl+alt+shift+n",
    ["search.text"] = "ctrl+shift+f",
    ["file.new"] = "alt+insert",
    ["project.new"] = false,
    ["explorer.focus"] = false,
    ["explorer.contextMenu"] = false,
    ["view.toggleSidebar"] = "alt+one",
    ["view.togglePanel"] = "ctrl+shift+f12",
    ["terminal.focus"] = "alt+f12",
    ["view.nextEditor"] = "alt+right",
    ["view.previousEditor"] = "alt+left",
    ["file.close"] = "ctrl+f4",
    ["settings.open"] = "ctrl+alt+s",

    ["editor.find"] = "ctrl+f",
    ["editor.replace"] = "ctrl+r",
    ["editor.redo"] = "ctrl+shift+z",
    ["designer.redo"] = "ctrl+shift+z",
    ["editor.gotoLine"] = "ctrl+g",
    ["editor.gotoDefinition"] = "ctrl+b",
    ["editor.navigateBack"] = "ctrl+alt+left",
    ["editor.toggleComment"] = "ctrl+slash",
    ["editor.deleteLines"] = "ctrl+y",
    ["editor.duplicateLines"] = "ctrl+d",
    ["editor.moveLinesUp"] = "alt+shift+up",
    ["editor.moveLinesDown"] = "alt+shift+down",
    ["editor.complete"] = "ctrl+space",
    ["problems.next"] = "f2",
    ["problems.previous"] = "shift+f2",

    ["run.file"] = "shift+f10",
    ["run.stop"] = "ctrl+f2",
    ["debug.file"] = "shift+f9",
    ["debug.continue"] = "f9",
    ["debug.stepOver"] = "f8",
    ["debug.stepInto"] = "f7",
    ["debug.stepOut"] = "shift+f8",
    ["debug.stop"] = "ctrl+f2",
    ["debug.toggleBreakpoint"] = "ctrl+f8",
  },
}

function M.get(id)
  return M.maps[id] or M.maps[M.DEFAULT]
end

function M.name(id)
  for _, k in ipairs(M.list) do if k.id == id then return k.name end end
  return id
end

return M

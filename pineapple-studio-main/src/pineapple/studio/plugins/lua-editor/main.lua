
local codeView = require("pineapple.studio.ui.codeedit.view")
local languages = require("pineapple.studio.ui.codeedit.languages")
local complete = require("pineapple.studio.ui.codeedit.complete")
local ccapi = require("pineapple.studio.ui.codeedit.ccapi")
local definition = require("pineapple.studio.ui.codeedit.definition")
local search = require("pineapple.studio.core.search")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui = studio.ui

  local function isLua(path) return type(path) == "string" and path:lower():match("%.lua$") ~= nil end

  local function completer(view, manual)
    if not studio.settings:get("editor.autocomplete", true) and not manual then return nil end
    local b = view.buffer
    local line = view.doc.lines[b.line]
    for _, tok in ipairs(view.highlighter:tokens(b.line)) do
      if (tok.type == "string" or tok.type == "comment") and tok.from < b.col and tok.to >= b.col - 1 then

        local closed = tok.type == "string" and tok.to == b.col - 1 and tok.to > tok.from
          and line:sub(tok.to, tok.to):match("[\"'%]]")
        if not closed then return nil end
      end
    end
    local ctx = complete.context(line, b.col)
    if not ctx then return nil end
    if ctx.kind == "name" and ctx.prefix == "" and not manual then return nil end

    if ctx.kind == "name" and complete.KEYWORDS[ctx.prefix] and not manual then return nil end
    local items = complete.candidates(ctx, { lines = view.doc.lines, api = ccapi, globals = _G, line = b.line })
    return items, ctx.start
  end
  local function insertText(item, nextChar)
    return complete.insertText(item, nextChar)
  end

  studio.editors:register({
    id = "pineapple.lua-editor",
    title = "Code Editor",
    score = function(path)
      if fs.isDir(path) then return 0 end
      return isLua(path) and 10 or 1
    end,
    create = function(host, doc, opts)
      local view = codeView.new(host, doc, {
        theme = opts.theme,
        tabSize = studio.settings:get("editor.tabSize", 2),
        language = languages.forPath(doc.path) or false,
        onCursor = function() ui:refreshStatus() end,
        completer = isLua(doc.path) and completer or nil,
        insertText = insertText,
        getClipboard = function() return ui:getClipboard() end,
        setClipboard = function(text) ui:setClipboard(text) end,
      })
      if isLua(doc.path) then
        view.onCtrlClick = function(v) studio.commands:execute("editor.gotoDefinition") end
      end
      view.onReplaced = function(n) ui:notify("Replaced " .. n .. " match" .. (n == 1 and "" or "es"), "info", 2) end
      return {
        view = view,
        focus = function() view:focus() end,
        getViewState = function() return view:getViewState() end,
        setViewState = function(_, s) view:setViewState(s) end,
        dispose = function() view:dispose() end,
        applyTheme = function(_, t) view:applyTheme(t) end,
      }
    end,
  })

  local function activeView()
    local e = ui:activeEditor()
    return e and e.instance.view
  end
  local function onView(method)
    return function()
      local v = activeView()
      if v then v[method](v) end
    end
  end
  local enabled = function() return activeView() ~= nil end

  studio.commands:register("editor.undo", onView("undo"), { enabled = enabled })
  studio.commands:register("editor.redo", onView("redo"), { enabled = enabled })
  studio.commands:register("editor.cut", onView("cut"), { enabled = enabled })
  studio.commands:register("editor.copy", onView("copy"), { enabled = enabled })
  studio.commands:register("editor.pasteInternal", onView("pasteInternal"), { enabled = enabled })
  studio.commands:register("editor.selectAll", onView("selectAll"), { enabled = enabled })
  studio.commands:register("editor.find", function()
    local v = activeView()
    if v then v:openFind(false) end
  end, { enabled = enabled })
  studio.commands:register("editor.replace", function()
    local v = activeView()
    if v then v:openFind(true) end
  end, { enabled = enabled })
  studio.commands:register("editor.findNext", function()
    local v = activeView()
    if v then v:findNext(1) end
  end, { enabled = enabled })
  studio.commands:register("editor.findPrevious", function()
    local v = activeView()
    if v then v:findNext(-1) end
  end, { enabled = enabled })
  studio.commands:register("editor.toggleComment", onView("toggleComment"), { enabled = enabled })
  studio.commands:register("editor.duplicateLines", onView("duplicateLines"), { enabled = enabled })
  studio.commands:register("editor.deleteLines", onView("deleteLines"), { enabled = enabled })
  studio.commands:register("editor.moveLinesUp", function()
    local v = activeView()
    if v then v:moveLines(-1) end
  end, { enabled = enabled })
  studio.commands:register("editor.moveLinesDown", function()
    local v = activeView()
    if v then v:moveLines(1) end
  end, { enabled = enabled })

  local history = {}

  local function reveal(path, line, col, length)
    local current = activeView()
    if current then
      history[#history + 1] = { path = current.doc.path, line = current.buffer.line, col = current.buffer.col }
      if #history > 50 then table.remove(history, 1) end
    end
    local e = ui:openFile(path)
    local v = e and e.instance.view
    if not v then return end
    if length then v:select(line, col, line, col + length) else v:gotoLine(line, col) end
    v:focus()
  end

  local function gotoDefinition()
    local v = activeView()
    if not v then return end
    local b = v.buffer
    local t = definition.target(v.doc.lines, b.line, b.col)
    if not t then ui:notify("Put the cursor on a name first", "info", 2) return end
    if t.kind == "require" then
      local root = studio.workspace:path("")
      for _, p in ipairs(definition.modulePaths(root, t.module)) do
        local abs = "/" .. fs.combine(p, "")
        if fs.exists(abs) and not fs.isDir(abs) then reveal(abs, 1, 1) return end
      end
      ui:notify("Module '" .. t.module .. "' isn't in this project", "info", 3)
      return
    end
    local found = definition.find(v.doc.lines, t, b.line)
    if #found > 0 then reveal(v.doc.path, found[1].line, found[1].col, #t.name) return end

    local items = {}
    for _, path in ipairs(search.files(studio.workspace, 1000)) do
      if isLua(path) and path ~= v.doc.path then
        local lines = search.lines(studio.workspace, path)
        for _, s in ipairs(lines and search.symbols(lines) or {}) do
          local last = s.name:match("([%w_]+)$")
          if s.name == t.name or last == t.name then
            items[#items + 1] = {
              label = s.name .. s.params, hint = studio.workspace:relative(path) .. ":" .. s.line,
              path = path, line = s.line, col = s.col + #s.name - #t.name,
            }
          end
        end
      end
    end
    if #items == 0 then ui:notify("No definition found for '" .. t.name .. "'", "info", 3) return end
    if #items == 1 then reveal(items[1].path, items[1].line, items[1].col, #t.name) return end
    ui:quickPick(items, { title = "Definitions", placeholder = "Choose a definition of " .. t.name }, function(item)
      if item then reveal(item.path, item.line, item.col, #t.name) end
    end)
  end

  studio.commands:register("editor.gotoDefinition", gotoDefinition, { enabled = enabled })
  studio.commands:register("editor.navigateBack", function()
    local pos = table.remove(history)
    if not pos then return end
    local e = ui:openFile(pos.path)
    local v = e and e.instance.view
    if v then v:gotoLine(pos.line, pos.col); v:focus() end
  end)

  studio.commands:register("editor.complete", function()
    local v = activeView()
    if v and v.completer then v:focus(); v:updateCompletion(true) end
  end, { enabled = enabled })
  studio.commands:register("editor.gotoLine", function()
    local v = activeView()
    if not v then return end
    ui:prompt({ title = "Go to Line", message = "Line number (1-" .. #v.doc.lines .. "):" }, function(text)
      local n = tonumber(text)
      if n then v:gotoLine(math.floor(n)); v:focus() end
    end)
  end, { enabled = enabled })

  studio.ui:addStatusItem({
    id = "editor.position", align = "right", priority = 10,
    text = function()
      local v = activeView()
      if not v then return nil end
      local b = v.buffer
      local text = "Ln " .. b.line .. ", Col " .. b.col
      if b:hasSelection() then text = text .. " (" .. #b:getSelectedText() .. " sel)" end
      return text
    end,
  })
  studio.ui:addStatusItem({
    id = "editor.language", align = "right", priority = 5,
    text = function()
      local e = ui:activeEditor()
      if not e or not e.instance.view then return nil end
      local language = e.instance.view.language
      return language and (language.title or language.id) or "Text"
    end,
  })
end

return plugin

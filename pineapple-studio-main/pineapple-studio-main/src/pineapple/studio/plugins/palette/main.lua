local search = require("pineapple.studio.core.search")
local dialogs = require("pineapple.studio.ui.dialogs")

local plugin = {}

local MAX_RESULTS = 200

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws = studio.ui, studio.workspace

  local function open(initialTab, initialText)

    local fileList, symbolList, lineCache

    local function relative(path) return ws:relative(path) end

    local function files()
      if fileList then return fileList end
      fileList = {}
      local openPaths, seen = {}, {}
      for _, e in ipairs(ui:editors()) do
        if not e.doc.virtual then openPaths[#openPaths + 1] = e.doc.path end
      end
      local function add(path, isOpen)
        if seen[path] then return end
        seen[path] = true
        local rel = relative(path)
        local folder = fs.getDir(rel)
        fileList[#fileList + 1] = {
          label = fs.getName(path), hint = folder ~= "" and folder or nil,
          filterText = rel, kind = "file", path = path, detail = isOpen and "open" or nil,
        }
      end
      for _, p in ipairs(openPaths) do add(p, true) end
      for _, p in ipairs(search.files(ws)) do add(p) end
      return fileList
    end

    local function linesOf(path)
      lineCache = lineCache or {}
      if lineCache[path] == nil then lineCache[path] = search.lines(ws, path) or false end
      return lineCache[path] or nil
    end

    local function symbols()
      if symbolList then return symbolList end
      symbolList = {}
      for _, f in ipairs(files()) do
        if f.path:match("%.lua$") then
          local lines = linesOf(f.path)
          for _, s in ipairs(lines and search.symbols(lines) or {}) do
            symbolList[#symbolList + 1] = {
              label = s.name .. s.params, filterText = s.name,
              hint = relative(f.path) .. ":" .. s.line,
              kind = "symbol", path = f.path, line = s.line, col = s.col,
            }
          end
        end
      end
      return symbolList
    end

    local function commandItems()
      local out = {}
      for _, cmd in ipairs(studio.commands:list()) do
        if cmd.id ~= "search.everywhere" and studio.commands:isEnabled(cmd.id) then
          local chord = studio.keybindings:chordFor(cmd.id)
          out[#out + 1] = {
            label = studio.commands:label(cmd), detail = chord and ui:shortChord(chord) or nil,
            kind = "command", id = cmd.id,
          }
        end
      end
      return out
    end

    local function capped(list)
      local out = {}
      for i = 1, math.min(#list, MAX_RESULTS) do out[i] = list[i] end
      return out
    end

    local function textSearch(query)
      if #query < 2 then return {} end
      local out = {}
      for _, f in ipairs(files()) do
        local lines = linesOf(f.path)
        if lines then
          for _, m in ipairs(search.grep(lines, query, false, MAX_RESULTS - #out)) do
            out[#out + 1] = {
              label = (m.text:gsub("^%s+", "")), hint = relative(f.path) .. ":" .. m.line,
              kind = "text", path = f.path, line = m.line, col = m.col, length = #query,
            }
          end
          if #out >= MAX_RESULTS then break end
        end
      end
      return out
    end

    local function everything(query)
      local cmds = commandItems()
      for _, c in ipairs(cmds) do c.detail = c.detail or "command" end
      if query == "" then
        local out = {}
        for _, f in ipairs(files()) do
          out[#out + 1] = f
          if #out >= 40 then break end
        end
        return out
      end
      local merged = {}
      local function add(list, kindLabel, bonus)
        for i, item in ipairs(list) do
          local s = dialogs.fuzzy(query, item.filterText or item.label)
          if s then
            merged[#merged + 1] = { item = item, score = s + bonus, order = #merged + i }
          end
        end
      end
      add(files(), "file", 1)
      add(symbols(), "symbol", 0)
      add(cmds, "command", 0.5)
      table.sort(merged, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
      end)
      local out = {}
      for i = 1, math.min(#merged, MAX_RESULTS) do
        local item = merged[i].item
        if item.kind == "symbol" then
          out[i] = { label = item.label, hint = item.hint, detail = "symbol", kind = item.kind,
            path = item.path, line = item.line, col = item.col }
        elseif item.kind == "file" then
          out[i] = { label = item.label, hint = item.hint, detail = "file", kind = item.kind, path = item.path }
        else
          out[i] = item
        end
      end
      return out
    end

    local tabs = {
      { id = "all", title = "All", items = everything, placeholder = "Search files, symbols, commands" },
      { id = "files", title = "Files", items = function(q) return capped(dialogs.filter(files(), q)) end,
        placeholder = "File name" },
      { id = "commands", title = "Commands", items = function(q) return dialogs.filter(commandItems(), q) end,
        placeholder = "Command" },
      { id = "symbols", title = "Symbols", items = function(q) return capped(dialogs.filter(symbols(), q)) end,
        placeholder = "Function name" },
      { id = "text", title = "Text", items = textSearch, placeholder = "Text in files",
        empty = function(q) return #q < 2 and "Type at least 2 characters" or "No matches" end },
    }

    ui:quickPick(nil, { tabs = tabs, tab = initialTab, initial = initialText }, function(item)
      if not item then return end
      if item.kind == "command" then
        local ok, err = pcall(studio.commands.execute, studio.commands, item.id)
        if not ok then ui:notify(tostring(err), "error") end
        return
      end
      local editor = ui:openFile(item.path)
      if editor and item.line then
        local view = editor.instance.view
        if view then
          view:gotoLine(item.line, item.col)
          if item.length then view:select(item.line, item.col, item.line, item.col + item.length) end
        end
      end
    end)
  end

  local function selectedText()
    local e = ui:activeEditor()
    local view = e and e.instance.view
    if view and view.buffer:hasSelection() then
      local text = view.buffer:getSelectedText()
      if not text:find("\n") then return text end
    end
    return nil
  end

  studio.commands:register("search.everywhere", function() open("all") end)
  studio.commands:register("palette.show", function() open("commands") end)
  studio.commands:register("file.open", function() open("files") end)
  studio.commands:register("search.symbols", function() open("symbols") end)
  studio.commands:register("search.text", function() open("text", selectedText()) end)
end

return plugin

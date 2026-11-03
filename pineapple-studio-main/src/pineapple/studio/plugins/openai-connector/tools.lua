-- The AI Assistant's built-in tools. Change tools (write_file, edit_file, restore_version)
-- only propose changes; the assistant reviews all of a reply's changes with the user at once.
local search = require("pineapple.studio.core.search")
local files = require("pineapple.studio.core.files")
local lint = require("pineapple.studio.core.lint")
local ccapi = require("pineapple.studio.ui.codeedit.ccapi")
local configModule = require("config")

local M = {}

-- Tools return everything they find: whole files, all matches, full program output. Large
-- results cost tokens and can fill the model's context, so read_file still accepts line ranges.

local function schema(properties, required)
  local s = { type = "object", additionalProperties = false }
  if properties and next(properties) then s.properties = properties end
  if required and #required > 0 then s.required = required end
  return s
end

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  if #lines > 1 and lines[#lines] == "" and text:sub(-1) == "\n" then lines[#lines] = nil end
  return lines
end
M.splitLines = splitLines

local function stamp(ms)
  local ok, text = pcall(os.date, "!%d %b %H:%M", math.floor((ms or 0) / 1000))
  return ok and text or "?"
end

local function globPattern(glob)
  local p = glob:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
  p = p:gsub("%*%*/?", "\1"):gsub("%*", "[^/]*"):gsub("%?", "[^/]"):gsub("\1", ".*")
  return "^" .. p .. "$"
end

-- options.approvals: a table the assistant resets per chat; approvals.run skips the run prompt.
-- options.stillWanted(complete): false once the request that started a tool was cancelled, so a
-- confirmation answered later doesn't act on it.
function M.register(studio, options)
  local ui, ws, settings, tools = studio.ui, studio.workspace, studio.settings, studio.tools
  local approvals = options.approvals
  local function wanted(complete)
    return not options.stillWanted or options.stillWanted(complete)
  end

  local function config() return configModule.read(settings) end

  local function safeRelative(path)
    path = path:gsub("\\", "/")
    if path:sub(1, 1) == "/" or path:match("^%a:") then return nil, "Use a project-relative path." end
    for part in path:gmatch("[^/]+") do
      if part == ".." then return nil, "The path must stay inside the project." end
    end
    return path
  end

  -- Project-relative paths always; absolute paths only when the user allowed outside access.
  local function resolve(path, allowRoot)
    if type(path) ~= "string" then return nil, "path must be a string" end
    path = path:gsub("\\", "/")
    if path == "" and allowRoot then
      if ui:hasProject() then return ws:path("") end
      return nil, "No project is open. Open one, or enable outside-project access and give an absolute path."
    end
    if path == "" then return nil, "path is required" end
    if path:sub(1, 1) == "/" then
      if not config().allowOutside then
        return nil, "Absolute paths are off. The user can enable 'Allow AI tools outside the project' in the assistant's menu."
      end
      return files.join(path)
    end
    local safe, err = safeRelative(path)
    if not safe then return nil, err end
    if not ui:hasProject() then return nil, "No project is open, so relative paths can't be used." end
    return ws:path(safe)
  end
  M.resolve = resolve

  local function label(path)
    local relative = ws:relative(path)
    if relative == "" or relative == path then return path end
    return relative
  end
  M.label = label

  -- The editor's text when the file is open, otherwise the file on disk (nil if missing).
  local function currentText(path)
    local doc = ws:getDocument(path)
    if doc then return doc:getText(), doc end
    if fs.exists(path) and not fs.isDir(path) then return files.read(path) end
    return nil
  end
  M.currentText = currentText

  local function argText(args, key) return type(args[key]) == "string" and args[key] or "" end

  -- Reading -----------------------------------------------------------------------------------

  tools:register({
    name = "list_files", readOnly = true,
    description = "List files and folders under a project-relative folder (the project root when path is omitted). "
      .. "Set recursive to include subfolders (hidden folders are skipped), and pattern to filter files, "
      .. "like *.lua or ui/*.xml (** matches across folders). Absolute paths work when outside-project access is on.",
    parameters = schema({
      path = { type = "string" }, recursive = { type = "boolean" }, pattern = { type = "string" },
    }),
    describe = function(args)
      local where = argText(args, "path") ~= "" and args.path or "the project"
      return "Listed " .. where .. (args.recursive and " recursively" or "")
        .. (argText(args, "pattern") ~= "" and (" matching " .. args.pattern) or "")
    end,
    run = function(args)
      local root, err = resolve(argText(args, "path"), true)
      if not root then return err end
      if not fs.isDir(root) then return "Folder not found: " .. label(root) end
      local glob = argText(args, "pattern")
      local pattern = glob ~= "" and globPattern(glob) or nil
      local matchPath = pattern and glob:find("/", 1, true)
      local out = {}
      local function relative(path)
        if root == "/" then return path:sub(2) end
        return path:sub(#root + 2)
      end
      local function visit(dir, depth)
        local ok, entries = pcall(fs.list, dir)
        if not ok then return end
        table.sort(entries)
        for _, name in ipairs(entries) do
          if not (args.recursive and name:sub(1, 1) == ".") then
            local path = files.join(dir, name)
            local isDir = fs.isDir(path)
            local subject = matchPath and relative(path) or name
            if not pattern or (not isDir and subject:match(pattern)) then
              out[#out + 1] = (isDir and "dir  " or "file ") .. label(path)
            end
            if isDir and args.recursive and depth < 8 then visit(path, depth + 1) end
          end
        end
      end
      visit(root, 0)
      return #out > 0 and table.concat(out, "\n") or "(nothing found)"
    end,
  })

  tools:register({
    name = "read_file", readOnly = true,
    description = "Read a text file (project-relative, or absolute when outside-project access is on). Returns "
      .. "the whole file, or only lines start_line to end_line when given. Open files are read as they are in the editor.",
    parameters = schema({
      path = { type = "string" }, start_line = { type = "integer" }, end_line = { type = "integer" },
    }, { "path" }),
    describe = function(args, result)
      local range = type(result) == "string" and result:match("^File: .- %((lines %d+%-%d+) of") or nil
      return "Read " .. argText(args, "path") .. (range and (" (" .. range .. ")") or "")
    end,
    run = function(args)
      local path, err = resolve(args.path, false)
      if not path then return err end
      if not fs.exists(path) or fs.isDir(path) then return "File not found: " .. label(path) end
      local lines = splitLines(currentText(path) or "")
      local first = math.max(1, math.floor(tonumber(args.start_line) or 1))
      local last = math.min(#lines, math.floor(tonumber(args.end_line) or #lines))
      if first > last then return label(path) .. " has " .. #lines .. " lines." end
      return ("File: %s (lines %d-%d of %d)\n%s"):format(label(path), first, last, #lines,
        table.concat(lines, "\n", first, last))
    end,
  })

  tools:register({
    name = "search_text", readOnly = true,
    description = "Search the project's text files for a literal phrase (case-insensitive). With outside-project "
      .. "access on, path can be an absolute file or folder to search instead.",
    parameters = schema({ query = { type = "string" }, path = { type = "string" } }, { "query" }),
    describe = function(args, result)
      local count = 0
      if type(result) == "string" and result ~= "No matches." then
        for _ in result:gmatch("[^\n]+") do count = count + 1 end
      end
      return ("Searched for '%s' (%d match%s)"):format(argText(args, "query"), count, count == 1 and "" or "es")
    end,
    run = function(args)
      local query = argText(args, "query")
      if query == "" then return "The search query is empty." end
      local paths
      if argText(args, "path") ~= "" then
        local root, err = resolve(args.path, false)
        if not root then return err end
        if not fs.exists(root) then return "Path not found: " .. label(root) end
        if fs.isDir(root) then
          paths = {}
          local function visit(dir, depth)
            if depth > 8 then return end
            for _, name in ipairs(fs.list(dir)) do
              if name:sub(1, 1) ~= "." then
                local p = files.join(dir, name)
                if fs.isDir(p) then visit(p, depth + 1) else paths[#paths + 1] = p end
              end
            end
          end
          pcall(visit, root, 0)
        else
          paths = { root }
        end
      else
        if not ui:hasProject() then return "No project is open." end
        paths = search.files(ws, math.huge)
      end
      local out = {}
      for _, path in ipairs(paths) do
        if not fs.isDir(path) then
          local text = currentText(path)
          if text then
            for _, match in ipairs(search.grep(splitLines(text), query, false, math.huge)) do
              out[#out + 1] = label(path) .. ":" .. match.line .. ": " .. match.text
            end
          end
        end
      end
      return #out > 0 and table.concat(out, "\n") or "No matches."
    end,
  })

  tools:register({
    name = "current_file", readOnly = true,
    description = "Read the active editor's current (possibly unsaved) contents, or only the selected text when "
      .. "there is a selection, with the cursor or selection line numbers.",
    parameters = schema({}),
    describe = function() return "Read the active editor" end,
    run = function()
      local editor = ui:activeEditor()
      if not editor then return "No file is open in the editor." end
      if editor.doc.virtual then return "The active editor is a Studio view, not a file." end
      local view = editor.instance and editor.instance.view
      local buffer = view and view.buffer
      local name = label(editor.doc.path)
      if buffer and buffer:hasSelection() then
        local l1, _, l2 = buffer:selection()
        return ("Selection in %s (lines %d-%d):\n%s"):format(name, l1, l2, buffer:getSelectedText())
      end
      local cursor = buffer and (" (cursor on line " .. buffer.line .. ")") or ""
      return "File: " .. name .. cursor .. "\n" .. editor.doc:getText()
    end,
  })

  tools:register({
    name = "screen_buffer", readOnly = true,
    description = "See what Pineapple Studio's screen shows right now, as text rows. Set colors to also get each "
      .. "row's foreground and background colour codes (much longer).",
    parameters = schema({ colors = { type = "boolean" } }),
    describe = function() return "Looked at the Studio screen" end,
    run = function(args)
      local buffer, err = ui:screenBuffer()
      if not buffer then return err end
      if args.colors then return buffer end
      local out = {}
      for _, line in ipairs(buffer.lines) do out[#out + 1] = (line.text:gsub("%s+$", "")) end
      return ("Screen %dx%d:\n%s"):format(buffer.width, buffer.height, table.concat(out, "\n"))
    end,
  })

  local knownGlobals
  tools:register({
    name = "get_problems", readOnly = true,
    description = "Check Lua files for syntax errors and unknown globals, like the Problems panel. "
      .. "Checks one file when path is given, otherwise the project's Lua files.",
    parameters = schema({ path = { type = "string" } }),
    describe = function(args, result)
      local count = 0
      if type(result) == "string" and not result:match("^No problems") then
        for _ in result:gmatch("[^\n]+") do count = count + 1 end
      end
      return "Checked " .. (argText(args, "path") ~= "" and args.path or "the project") .. " for problems (" .. count .. " found)"
    end,
    run = function(args)
      knownGlobals = knownGlobals or lint.knownGlobals(_G, ccapi)
      local targets = {}
      if argText(args, "path") ~= "" then
        local path, err = resolve(args.path, false)
        if not path then return err end
        if not fs.exists(path) then return "File not found: " .. label(path) end
        targets[1] = path
      else
        if not ui:hasProject() then return "No project is open." end
        for _, path in ipairs(search.files(ws, math.huge)) do
          if path:match("%.lua$") then targets[#targets + 1] = path end
        end
      end
      local projectGlobals = {}
      for _, path in ipairs(targets) do
        local text = currentText(path)
        local lines = text and splitLines(text)
        if lines and not lint.syntax(lines) then
          for name in pairs(lint.definedGlobals(lines)) do projectGlobals[name] = true end
        end
      end
      local out = {}
      for _, path in ipairs(targets) do
        local text = currentText(path)
        if text and path:match("%.lua$") then
          for _, d in ipairs(lint.check(splitLines(text), { known = knownGlobals, extra = projectGlobals })) do
            out[#out + 1] = ("%s:%d:%d: %s: %s"):format(label(path), d.line or 1, d.col or 1, d.severity or "error", d.message)
          end
        end
      end
      if #out == 0 then return "No problems found in " .. #targets .. " file" .. (#targets == 1 and "" or "s") .. "." end
      return table.concat(out, "\n")
    end,
  })

  tools:register({
    name = "cc_api", readOnly = true,
    description = "Look up the ComputerCraft / CC: Tweaked API: a module (\"turtle\"), a function (\"turtle.dig\", "
      .. "\"print\"), or part of a name to search for. Omit name to list modules.",
    parameters = schema({ name = { type = "string" } }),
    describe = function(args) return "Looked up " .. (argText(args, "name") ~= "" and args.name or "the CC API") end,
    run = function(args)
      local name = argText(args, "name"):gsub("^%s+", ""):gsub("%s+$", "")
      local function line(module, member, entry)
        local full = module == "_G" and member or (module .. "." .. member)
        return full .. (entry.sig or "") .. (entry.doc and (" - " .. entry.doc) or "")
      end
      local function sortedKeys(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
      end
      if name == "" then
        local modules = sortedKeys(ccapi)
        return "Modules: " .. table.concat(modules, ", ") .. " (_G holds global functions)"
      end
      local module, member = name:match("^([%w_]+)[%.:]([%w_]+)$")
      if module and ccapi[module] and ccapi[module][member] then
        return line(module, member, ccapi[module][member])
      end
      if ccapi[name] then
        local out = {}
        for _, key in ipairs(sortedKeys(ccapi[name])) do out[#out + 1] = line(name, key, ccapi[name][key]) end
        return table.concat(out, "\n")
      end
      if ccapi._G[name] then return line("_G", name, ccapi._G[name]) end
      local needle, out = name:lower():gsub("^.*[%.:]", ""), {}
      for _, mod in ipairs(sortedKeys(ccapi)) do
        for _, key in ipairs(sortedKeys(ccapi[mod])) do
          if key:lower():find(needle, 1, true) then out[#out + 1] = line(mod, key, ccapi[mod][key]) end
          if #out >= 20 then break end
        end
        if #out >= 20 then break end
      end
      if #out == 0 then return "Nothing in the CC API matches '" .. name .. "'." end
      return "No exact match. Similar:\n" .. table.concat(out, "\n")
    end,
  })

  tools:register({
    name = "layout_outline", readOnly = true,
    description = "Outline a UI layout file as an element tree with names, positions, sizes and text: "
      .. "Basalt .xml layouts or Bedrock .view files. Change layouts with edit_file.",
    parameters = schema({ path = { type = "string" } }, { "path" }),
    describe = function(args) return "Outlined layout " .. argText(args, "path") end,
    run = function(args)
      local path, err = resolve(args.path, false)
      if not path then return err end
      local text = currentText(path)
      if not text then return "File not found: " .. label(path) end
      local out = {}
      local function add(depth, text2) out[#out + 1] = string.rep("  ", depth) .. text2 end
      if path:match("%.xml$") then
        local ok, basalt = pcall(require, "basalt")
        if not ok or type(basalt) ~= "table" or not basalt.use then return "Basalt isn't available to parse the layout." end
        local parsed, roots = pcall(basalt.use("xml").parse, text)
        if not parsed then return "The layout doesn't parse: " .. tostring(roots) end
        local function walk(nodes, depth)
          for _, node in ipairs(nodes) do
            local attrs = {}
            local keys = {}
            for k in pairs(node.attrs or {}) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do attrs[#attrs + 1] = k .. "=" .. tostring(node.attrs[k]) end
            add(depth, "<" .. node.tag .. "> " .. table.concat(attrs, " ") .. (node.text and (" text: " .. node.text) or ""))
            walk(node.children or {}, depth + 1)
          end
        end
        walk(roots, 0)
      elseif path:match("%.view$") then
        local view = textutils.unserialise(text)
        if type(view) ~= "table" then return "The view doesn't parse as a Lua table." end
        local function walk(node, depth)
          local parts = { tostring(node.Type or "View") }
          for _, k in ipairs({ "Name", "X", "Y", "Width", "Height", "Text" }) do
            if node[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(node[k]) end
          end
          add(depth, table.concat(parts, " "))
          for _, child in ipairs(type(node.Children) == "table" and node.Children or {}) do walk(child, depth + 1) end
        end
        walk(view, 0)
      else
        return "layout_outline reads .xml (Basalt) and .view (Bedrock) files."
      end
      return table.concat(out, "\n")
    end,
  })

  -- Local History ------------------------------------------------------------------------------

  local function historyReady()
    return studio.commands:has("localHistory.entries") and studio.commands:has("localHistory.read")
  end

  tools:register({
    name = "file_history", readOnly = true,
    description = "List earlier versions of a file kept by Local History (newest first): id, time and what "
      .. "replaced it. Read one with read_version, or propose going back with restore_version.",
    parameters = schema({ path = { type = "string" } }, { "path" }),
    describe = function(args) return "Checked the history of " .. argText(args, "path") end,
    run = function(args)
      if not historyReady() then return "Local History is turned off." end
      local path, err = resolve(args.path, false)
      if not path then return err end
      local entries = studio.commands:execute("localHistory.entries", path) or {}
      if #entries == 0 then return "No earlier versions of " .. label(path) .. "." end
      local out = {}
      for i = 1, #entries do
        local e = entries[i]
        out[#out + 1] = ("id %d  %s  replaced by: %s  (%d bytes)"):format(e.id, stamp(e.time), e.label or "?", e.size or 0)
      end
      return "Versions of " .. label(path) .. ":\n" .. table.concat(out, "\n")
    end,
  })

  tools:register({
    name = "read_version", readOnly = true,
    description = "Read an earlier version of a file from Local History, by the id file_history gives.",
    parameters = schema({ path = { type = "string" }, id = { type = "integer" } }, { "path", "id" }),
    describe = function(args) return "Read version " .. tostring(args.id) .. " of " .. argText(args, "path") end,
    run = function(args)
      if not historyReady() then return "Local History is turned off." end
      local path, err = resolve(args.path, false)
      if not path then return err end
      local text = studio.commands:execute("localHistory.read", path, tonumber(args.id))
      if not text then return "No version " .. tostring(args.id) .. " of " .. label(path) .. "." end
      return "Version " .. tostring(args.id) .. " of " .. label(path) .. ":\n" .. text
    end,
  })

  -- Running and file operations (each asks the user) --------------------------------------------

  local function tail(text)
    text = text or ""
    return text ~= "" and text or "(no output)"
  end

  local function runReady() return studio.commands:has("run.capture") and studio.commands:has("run.status") end

  -- kind is "file" (target = path), "project" (target = nil) or "command" (target = command line).
  -- The program the assistant last left running is remembered in approvals.aiRunId, so only
  -- that one can be typed into or stopped by the assistant.
  local MAX_TIMEOUT = 600

  local function runProgram(kind, target, argLine, keepRunning, what, complete, timeoutSeconds)
    if not runReady() then return "The Run plugin is turned off." end
    local timeout = math.floor(math.max(1, math.min(MAX_TIMEOUT, tonumber(timeoutSeconds) or config().runTimeout)))
    local function go()
      local function done(result)
        local status
        if result.running then
          approvals.aiRunId = result.id
          status = "Still running after " .. timeout .. " seconds, so it was left running. "
            .. "Use program_output to watch it, program_input to type into it and stop_program to end it."
        elseif result.timedOut then
          status = "Stopped after " .. timeout .. " seconds because it was still running."
        elseif result.ok then
          status = "The program finished."
        else
          status = "The program ended with an error: " .. tostring(result.error or "unknown error")
        end
        complete(status .. "\nOutput:\n" .. tail(result.output))
      end
      local options = { keepRunning = keepRunning == true }
      if kind == "command" then
        studio.commands:execute("run.captureCommand", target, timeout, done, options)
      else
        studio.commands:execute("run.capture", target, argLine, timeout, done, options)
      end
    end
    if approvals.run or config().autoApprove then go() return tools.ASYNC end
    local after = keepRunning and ("If it's still running after " .. timeout .. " seconds it keeps running, and the assistant can type into it or stop it.")
      or ("It's stopped after " .. timeout .. " seconds if it's still running.")
    ui:choose({
      title = "Run Program",
      message = "The AI Assistant wants to run " .. what .. " in the Run panel. " .. after,
      buttons = { "Run", "Allow This Chat", "Cancel" }, default = 1, cancel = 3,
    }, function(choice)
      if not wanted(complete) then return end
      if choice == 2 then approvals.run = true end
      if choice == 1 or choice == 2 then go() else complete("The user declined to run the program.") end
    end)
    return tools.ASYNC
  end

  local function firstLine(result) return type(result) == "string" and result:match("^([^\n]*)") or "" end
  local function keepRunning() return { type = "boolean" } end
  local function timeoutSchema() return { type = "integer" } end
  local TIMEOUT_NOTE = " timeout_seconds (1-600) sets how long to wait; the default comes from the user's settings."

  tools:register({
    name = "run_file",
    description = "Run a Lua file in the Run panel and get its output (the user is asked first). args are "
      .. "command-line arguments, as typed in the shell. A program still running after a few seconds is "
      .. "stopped, unless keep_running is true: then it keeps running (for programs that wait for input or "
      .. "loop) and you can use program_output, program_screen, program_input, program_event and stop_program."
      .. TIMEOUT_NOTE,
    parameters = schema({ path = { type = "string" }, args = { type = "string" }, keep_running = keepRunning(),
      timeout_seconds = timeoutSchema() }, { "path" }),
    describe = function(args, result)
      return "Ran " .. argText(args, "path") .. (argText(args, "args") ~= "" and (" " .. args.args) or "") .. ": " .. firstLine(result)
    end,
    run = function(args, complete)
      local path, err = resolve(args.path, false)
      if not path then return err end
      if not fs.exists(path) or fs.isDir(path) then return "File not found: " .. label(path) end
      local argLine = argText(args, "args")
      return runProgram("file", path, argLine, args.keep_running, label(path) .. (argLine ~= "" and (" " .. argLine) or ""),
        complete, args.timeout_seconds)
    end,
  })

  tools:register({
    name = "run_project",
    description = "Run the project's main file in the Run panel and get its output (the user is asked first). "
      .. "Without args, the project's default arguments are used. keep_running works as in run_file." .. TIMEOUT_NOTE,
    parameters = schema({ args = { type = "string" }, keep_running = keepRunning(), timeout_seconds = timeoutSchema() }),
    describe = function(_, result) return "Ran the project: " .. firstLine(result) end,
    run = function(args, complete)
      if not ui:hasProject() then return "No project is open." end
      local argLine = type(args.args) == "string" and args.args or nil
      return runProgram("project", nil, argLine, args.keep_running,
        "the project" .. (argLine and argLine ~= "" and (" with " .. argLine) or ""), complete, args.timeout_seconds)
    end,
  })

  tools:register({
    name = "run_command",
    description = "Run a CraftOS shell command in the Run panel and get its output (the user is asked first), "
      .. "e.g. \"ls\", \"gps locate\" or \"id\". The first word is looked up on the shell's program path; use "
      .. "run_file for the project's own files. keep_running works as in run_file." .. TIMEOUT_NOTE,
    parameters = schema({ command = { type = "string" }, keep_running = keepRunning(), timeout_seconds = timeoutSchema() }, { "command" }),
    describe = function(args, result) return "Ran `" .. argText(args, "command") .. "`: " .. firstLine(result) end,
    run = function(args, complete)
      local command = argText(args, "command"):gsub("^%s+", ""):gsub("%s+$", "")
      if command == "" then return "The command is empty." end
      return runProgram("command", command, nil, args.keep_running, "the command `" .. command .. "`", complete,
        args.timeout_seconds)
    end,
  })

  local function status()
    if not runReady() then return nil, "The Run plugin is turned off." end
    return studio.commands:execute("run.status")
  end

  local function ownProgram()
    local s, err = status()
    if not s then return nil, err end
    if not s.running then return nil, "No program is running." end
    if not approvals.aiRunId or s.id ~= approvals.aiRunId then
      return nil, "The running program wasn't left running by you in this chat, so you can't control it."
    end
    return s
  end

  tools:register({
    name = "program_output", readOnly = true,
    description = "See the program in the Run panel: whether it's still running, and its output so far.",
    parameters = schema({}),
    describe = function(_, result) return "Checked the running program: " .. firstLine(result) end,
    run = function()
      local s, err = status()
      if not s then return err end
      local what = s.path and label(s.path) or "nothing has run yet"
      return (s.running and "Running: " or "Not running: ") .. what .. "\nOutput:\n" .. tail(s.output)
    end,
  })

  tools:register({
    name = "program_input",
    description = "Type text into the program you left running (with keep_running), as if the user typed it, "
      .. "then wait wait_seconds (default 1, at most 10) and return its output. enter (default true) presses "
      .. "Enter after the text.",
    parameters = schema({ text = { type = "string" }, enter = { type = "boolean" }, wait_seconds = { type = "number" } }),
    describe = function(args) return "Typed \"" .. argText(args, "text") .. "\"" .. (args.enter == false and "" or " + Enter") .. " into the program" end,
    run = function(args, complete)
      local s, err = ownProgram()
      if not s then return err end
      if not studio.commands:execute("run.input", s.id, argText(args, "text"), args.enter ~= false) then
        return "Couldn't type into the program; it may have just ended."
      end
      local wait = math.max(0.1, math.min(10, tonumber(args.wait_seconds) or 1))
      studio.timers:after(wait, function()
        local now = studio.commands:execute("run.status")
        complete((now.running and "Still running." or "The program has ended.") .. "\nOutput:\n" .. tail(now.output))
      end)
      return tools.ASYNC
    end,
  })

  tools:register({
    name = "stop_program",
    description = "Stop the program you left running (with keep_running) and return its final output.",
    parameters = schema({}),
    describe = function() return "Stopped the running program" end,
    run = function()
      local s, err = ownProgram()
      if not s then return err end
      studio.commands:execute("run.stopRun", s.id)
      approvals.aiRunId = nil
      return "Stopped.\nOutput:\n" .. tail(studio.commands:execute("run.status").output)
    end,
  })

  local function screenText(withColors)
    local screen = studio.commands:has("run.screen") and studio.commands:execute("run.screen")
    if not screen then return "The Run panel isn't open." end
    local out = { ("Run terminal %dx%d, cursor at %d,%d%s. Rows are numbered; x is the column within a row."):format(
      screen.width, screen.height, screen.cursor.x, screen.cursor.y, screen.cursor.blink and " (blinking)" or "") }
    for y, line in ipairs(screen.lines) do
      out[#out + 1] = ("%3d|%s"):format(y, (line.text:gsub("%s+$", "")))
      if withColors then
        out[#out + 1] = "   fg " .. line.fg
        out[#out + 1] = "   bg " .. line.bg
      end
    end
    if withColors then
      out[#out + 1] = "Colours are blit hex digits: 0 white, 1 orange, 2 magenta, 3 lightBlue, 4 yellow, 5 lime, "
        .. "6 pink, 7 gray, 8 lightGray, 9 cyan, a purple, b blue, c brown, d green, e red, f black."
    end
    return table.concat(out, "\n")
  end

  tools:register({
    name = "program_screen", readOnly = true,
    description = "See exactly what the Run terminal shows now, as numbered rows (the screen coordinates "
      .. "program_event uses). Set colors for each row's text and background colours. Useful for testing UIs.",
    parameters = schema({ colors = { type = "boolean" } }),
    describe = function() return "Looked at the Run terminal" end,
    run = function(args) return screenText(args.colors == true) end,
  })

  local MOUSE = { mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true, monitor_touch = true }

  -- Turns one { name, args } into the events to queue. "click" is mouse_click then mouse_up; key
  -- names like "enter" or "a" become key codes.
  local function expandEvent(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string" or not spec.name:match("^[%w_]+$") then
      return nil, "each event needs a name made of letters, digits and _"
    end
    local args = {}
    for i, v in ipairs(type(spec.args) == "table" and spec.args or {}) do args[i] = v end
    local name = spec.name
    if name == "click" then
      local button, x, y = tonumber(args[1]) or 1, tonumber(args[2]), tonumber(args[3])
      if not x or not y then return nil, "click needs args [button, x, y]" end
      return { { "mouse_click", button, x, y }, { "mouse_up", button, x, y } }
    end
    if MOUSE[name] then
      for i = 1, 3 do
        if args[i] ~= nil and name ~= "monitor_touch" then args[i] = tonumber(args[i]) or args[i] end
      end
    end
    if (name == "key" or name == "key_up") and type(args[1]) == "string" then
      local code = keys[args[1]]
      if not code then return nil, "unknown key name '" .. args[1] .. "'" end
      args[1] = code
      if name == "key" and args[2] == nil then args[2] = false end
    end
    local event = { name }
    for i, v in ipairs(args) do event[i + 1] = v end
    return { event }
  end

  tools:register({
    name = "program_event",
    description = "Send events to the program you left running (with keep_running), as if the user did them, "
      .. "then wait wait_seconds (default 0.5, at most 10) and return the Run terminal screen. Each event is "
      .. "{ name, args }: e.g. { name = \"click\", args = [1, x, y] } (mouse_click then mouse_up; button 1 left, "
      .. "2 right), mouse_click/mouse_up/mouse_drag [button, x, y], mouse_scroll [direction (-1 up, 1 down), x, y], "
      .. "key [key name like \"enter\" or \"up\", held], key_up [key name], char [character], paste [text], "
      .. "or any other event the program listens for. Coordinates are the screen's columns and rows, as "
      .. "program_screen shows them.",
    parameters = schema({
      events = { type = "array", items = { type = "object", properties = {
        name = { type = "string" },
        args = { type = "array", items = { type = { "string", "number", "boolean" } } },
      }, required = { "name" } } },
      wait_seconds = { type = "number" },
    }, { "events" }),
    describe = function(args)
      local names = {}
      for _, e in ipairs(type(args.events) == "table" and args.events or {}) do
        if type(e) == "table" then names[#names + 1] = tostring(e.name) end
      end
      return "Sent " .. table.concat(names, ", ") .. " to the program"
    end,
    run = function(args, complete)
      local s, err = ownProgram()
      if not s then return err end
      if type(args.events) ~= "table" or #args.events == 0 then return "events is empty." end
      local queue = {}
      for i, spec in ipairs(args.events) do
        local expanded, expandErr = expandEvent(spec)
        if not expanded then return "Event " .. i .. ": " .. expandErr end
        for _, e in ipairs(expanded) do queue[#queue + 1] = e end
      end
      for _, e in ipairs(queue) do
        if not studio.commands:execute("run.event", s.id, table.unpack(e)) then
          return "The program stopped before all events were sent.\n" .. screenText(false)
        end
      end
      local wait = math.max(0.1, math.min(10, tonumber(args.wait_seconds) or 0.5))
      studio.timers:after(wait, function()
        local now = studio.commands:execute("run.status")
        complete((now.running and "Sent. Still running.\n" or "Sent. The program has ended.\n") .. screenText(false))
      end)
      return tools.ASYNC
    end,
  })

  -- Showing things to the user ---------------------------------------------------------------------

  tools:register({
    name = "open_in_editor",
    description = "Open a file in the editor for the user, optionally at a line, e.g. to show them something.",
    parameters = schema({ path = { type = "string" }, line = { type = "integer" } }, { "path" }),
    describe = function(args) return "Opened " .. argText(args, "path") .. (args.line and (" at line " .. args.line) or "") end,
    run = function(args)
      local path, err = resolve(args.path, false)
      if not path then return err end
      if not fs.exists(path) or fs.isDir(path) then return "File not found: " .. label(path) end
      local editor = ui:openFile(path)
      if not editor then return "Couldn't open " .. label(path) .. "." end
      local line = tonumber(args.line)
      if line and editor.instance and editor.instance.view and editor.instance.view.gotoLine then
        editor.instance.view:gotoLine(math.max(1, math.floor(line)))
      end
      return "Opened " .. label(path) .. "."
    end,
  })

  tools:register({
    name = "project_info", readOnly = true,
    description = "Basic facts about the open project: its folder, main file and default run arguments, "
      .. "and the files open in the editor (with unsaved ones marked).",
    parameters = schema({}),
    describe = function() return "Checked the project" end,
    run = function()
      if not ui:hasProject() then return "No project is open." end
      local out = { "Project: " .. ws:name() .. " (" .. ws:path("") .. ")" }
      local main = settings:get("run.main")
      if not (main and ws:exists(main)) then
        main = nil
        for _, name in ipairs({ "main.lua", "startup.lua", "init.lua" }) do
          if ws:exists(name) then main = name break end
        end
      end
      out[#out + 1] = "Main file: " .. (main or "(none set)")
      local argLine = settings:get("run.args", "")
      out[#out + 1] = "Default run arguments: " .. ((argLine and argLine ~= "") and argLine or "(none)")
      local active = ui:activeEditor()
      local open = {}
      for _, e in ipairs(ui:editors()) do
        if not e.doc.virtual then
          open[#open + 1] = label(e.doc.path) .. (e.doc:isDirty() and " (unsaved)" or "") .. (e == active and " (active)" or "")
        end
      end
      out[#out + 1] = "Open files: " .. (#open > 0 and table.concat(open, ", ") or "(none)")
      if ws:exists(".pineapple/ai.md") then out[#out + 1] = "Project notes: .pineapple/ai.md" end
      return table.concat(out, "\n")
    end,
  })

  local function confirmThen(title, message, button, action, complete)
    if config().autoApprove then
      local ok, result = pcall(action)
      return ok and result or ("Failed: " .. tostring(result))
    end
    ui:choose({ title = title, message = message, buttons = { button, "Cancel" }, default = 2, cancel = 2 },
      function(choice)
        if not wanted(complete) then return end
        if choice ~= 1 then complete("The user declined.") return end
        local ok, result = pcall(action)
        complete(ok and result or ("Failed: " .. tostring(result)))
      end)
    return tools.ASYNC
  end

  tools:register({
    name = "rename_path",
    description = "Rename or move a file or folder (the user is asked first). Open editors follow the move.",
    parameters = schema({ from = { type = "string" }, to = { type = "string" } }, { "from", "to" }),
    describe = function(args, result)
      return "Rename " .. argText(args, "from") .. " to " .. argText(args, "to") .. ": " .. tostring(result or "")
    end,
    run = function(args, complete)
      local from, err = resolve(args.from, false)
      if not from then return err end
      local to, err2 = resolve(args.to, false)
      if not to then return err2 end
      if not fs.exists(from) then return "Not found: " .. label(from) end
      if fs.exists(to) then return label(to) .. " already exists." end
      return confirmThen("Rename", "The AI Assistant wants to rename " .. label(from) .. " to " .. label(to) .. ".",
        "Rename", function()
          local ok, moveErr = ws:move(from, to)
          if not ok then error(moveErr or "the move failed", 0) end
          return "Renamed."
        end, complete)
    end,
  })

  tools:register({
    name = "delete_path",
    description = "Delete a file or folder (the user is asked first). Local History keeps deleted files' "
      .. "contents so they can be restored.",
    parameters = schema({ path = { type = "string" } }, { "path" }),
    describe = function(args, result) return "Delete " .. argText(args, "path") .. ": " .. tostring(result or "") end,
    run = function(args, complete)
      local path, err = resolve(args.path, false)
      if not path then return err end
      if not fs.exists(path) then return "Not found: " .. label(path) end
      if path == ws:path("") then return "The project folder itself can't be deleted." end
      local doc = ws:getDocument(path)
      if doc and doc:isDirty() then return "The file has unsaved editor changes." end
      local what = fs.isDir(path) and ("the folder " .. label(path) .. " and everything in it") or label(path)
      return confirmThen("Delete", "The AI Assistant wants to delete " .. what .. ".", "Delete", function()
        local ok, deleteErr = ws:delete(path)
        if not ok then error(deleteErr or "the delete failed", 0) end
        return "Deleted."
      end, complete)
    end,
  })

  -- Change tools ---------------------------------------------------------------------------------

  -- base(path) is the text from earlier changes in the same reply; makeText(old) returns the new
  -- text (old is nil for a new file).
  local function propose(pathArg, base, makeText)
    local path, err = resolve(pathArg, false)
    if not path then return nil, err end
    if fs.isDir(path) then return nil, "That path is a folder." end
    if fs.exists(path) and fs.isReadOnly(path) then return nil, "The file is read-only." end
    local doc = ws:getDocument(path)
    if doc and doc:isDirty() then
      return nil, "The file has unsaved editor changes. Ask the user to save or discard them first."
    end
    local old = base(path)
    if old == nil then old = currentText(path) end
    local newText, makeErr = makeText(old)
    if not newText then return nil, makeErr end
    return { path = path, newText = newText }
  end

  tools:register({
    name = "write_file",
    description = "Create a file or replace a whole file. The user reviews all changes from your reply in one "
      .. "diff before anything is written. To change part of a file, edit_file is shorter.",
    parameters = schema({ path = { type = "string" }, content = { type = "string" } }, { "path", "content" }),
    prepare = function(args, base)
      if type(args.content) ~= "string" then return nil, "content must be text." end
      return propose(args.path, base, function() return args.content end)
    end,
  })

  tools:register({
    name = "edit_file",
    description = "Replace one exact, unique piece of text in a file. Read the file first and include enough "
      .. "surrounding text that old_text matches once. The user reviews the diff before it's written.",
    parameters = schema({
      path = { type = "string" }, old_text = { type = "string" }, new_text = { type = "string" },
    }, { "path", "old_text", "new_text" }),
    prepare = function(args, base)
      if type(args.old_text) ~= "string" or type(args.new_text) ~= "string" then
        return nil, "old_text and new_text must be text."
      end
      if args.old_text == "" then return nil, "old_text is empty. Use write_file to create or replace a file." end
      return propose(args.path, base, function(old)
        if old == nil then return nil, "File not found." end
        local first = old:find(args.old_text, 1, true)
        if not first then return nil, "old_text wasn't found. Read the file again; it may have changed." end
        if old:find(args.old_text, first + 1, true) then
          return nil, "old_text matches more than once. Include more surrounding text."
        end
        return old:sub(1, first - 1) .. args.new_text .. old:sub(first + #args.old_text)
      end)
    end,
  })

  tools:register({
    name = "restore_version",
    description = "Propose putting a file back to an earlier Local History version (ids from file_history). "
      .. "The user reviews the diff first.",
    parameters = schema({ path = { type = "string" }, id = { type = "integer" } }, { "path", "id" }),
    prepare = function(args, base)
      if not historyReady() then return nil, "Local History is turned off." end
      local path, err = resolve(args.path, false)
      if not path then return nil, err end
      local text = studio.commands:execute("localHistory.read", path, tonumber(args.id))
      if not text then return nil, "No version " .. tostring(args.id) .. " of that file." end
      return propose(args.path, base, function() return text end)
    end,
  })
end

return M

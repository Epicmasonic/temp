local files = require("pineapple.studio.core.files")
local storeModule = require("store")
local historyView = require("historyview")

local plugin = {}

local MAX_FOLDER_FILES = 200
local AUTOSAVE_WINDOW_MS = 5 * 60 * 1000

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws, settings = studio.ui, studio.workspace, studio.settings
  if not ctx.storage then
    ctx.log("No plugin storage folder; local history is off")
    return
  end

  local store = storeModule.new(files.join(ctx.storage, "history"), {
    maxEntries = function() return settings:get("localHistory.maxEntries", 30) end,
    maxDays = function() return settings:get("localHistory.maxDays", 14) end,
    maxSizeKB = function() return settings:get("localHistory.maxSizeKB", 256) end,
  })

  local function enabled() return settings:get("localHistory.enabled", true) ~= false end

  -- Project metadata (.pineapple) and Studio's own data aren't worth keeping versions of.
  local function tracked(path)
    if path:find("/%.pineapple/") then return false end
    if path:sub(1, #ctx.storage + 1) == ctx.storage .. "/" then return false end
    return true
  end

  local function remember(path, label)
    if not enabled() or not tracked(path) or not fs.exists(path) or fs.isDir(path) then return end
    local text = files.read(path)
    if text then store:record(path, text, label) end
  end

  ws:on("willWrite", function(path, newText, info)
    if not enabled() or not tracked(path) or not fs.exists(path) or fs.isDir(path) then return end
    local old = files.read(path)
    if old == nil or old == newText then return end
    local source = (info and info.source) or "Saved"
    store:record(path, old, source, source == "Auto-save" and AUTOSAVE_WINDOW_MS or nil, info and info.group)
  end)

  ws:on("willDelete", function(path)
    if not fs.isDir(path) then remember(path, "Deleted") return end
    local count = 0
    local function walk(dir)
      for _, name in ipairs(fs.list(dir)) do
        if count >= MAX_FOLDER_FILES then return end
        local child = files.join(dir, name)
        if fs.isDir(child) then walk(child)
        else
          count = count + 1
          remember(child, "Deleted")
        end
      end
    end
    pcall(walk, path)
  end)

  -- Open history views, by file path, so they refresh after the file changes.
  local views = {}
  local function eachView(path, fn)
    for viewPath, set in pairs(views) do
      if viewPath == path or viewPath:sub(1, #path + 1) == path .. "/" then
        for view in pairs(set) do fn(view, viewPath) end
      end
    end
  end
  local function refresh(path) eachView(path, function(view) pcall(view.refresh) end) end

  ws:on("fileChanged", refresh)
  ws:on("fileCreated", refresh)
  ws:on("fileDeleted", refresh)
  ws:on("fileRenamed", function(from, to)
    store:rename(from, to)
    local moved = {}
    eachView(from, function(view, viewPath) moved[#moved + 1] = { view = view, from = viewPath } end)
    for _, m in ipairs(moved) do
      local target = to .. m.from:sub(#from + 1)
      views[m.from][m.view] = nil
      if not next(views[m.from]) then views[m.from] = nil end
      views[target] = views[target] or {}
      views[target][m.view] = true
      pcall(m.view.setPath, target)
    end
  end)

  local function openHistory(path)
    ui:openView({
      id = "local-history:" .. path,
      title = "History: " .. fs.getName(path),
      create = function(host)
        local view = historyView.new(host, studio, { path = path, store = store })
        views[view.path] = views[view.path] or {}
        views[view.path][view] = true
        view.onDispose = function()
          for viewPath, set in pairs(views) do
            set[view] = nil
            if not next(set) then views[viewPath] = nil end
          end
        end
        return view
      end,
    })
  end

  -- A folder's history is the files deleted from it (at any depth); picking one opens its
  -- history, where Revert brings it back.
  local function deletedFrom(folder)
    local items = {}
    for _, deleted in ipairs(store:deletedPaths()) do
      if folder == "/" or deleted:sub(1, #folder + 1) == folder .. "/" then
        local latest = store:entries(deleted)[1]
        items[#items + 1] = {
          label = ws:relative(deleted),
          detail = latest and ("deleted " .. historyView.stamp(latest.time)) or nil,
          path = deleted,
        }
      end
    end
    local name = ws:relative(folder)
    if name == "" then name = "the project" end
    if #items == 0 then
      ui:notify("No files deleted from " .. name .. " are in Local History", "info", 3)
      return
    end
    ui:quickPick(items, { title = "Deleted from " .. name, placeholder = "Deleted file to see or restore" },
      function(item) if item then openHistory(item.path) end end)
  end

  -- From the Explorer, path is what was right-clicked (the project folder for empty space):
  -- a file shows its versions, a folder its deleted files.
  local function show(path)
    if type(path) ~= "string" or path == "" then
      local editor = ui:activeEditor()
      if not editor or editor.doc.virtual then ui:notify("Right-click a file or folder in the Explorer to see its history", "info") return end
      path = editor.doc.path
    end
    path = ws:path(path)
    if fs.isDir(path) then deletedFrom(path) else openHistory(path) end
  end

  studio.commands:register("localHistory.show", show)

  -- From the Explorer, path is what was right-clicked: only files deleted from that folder
  -- (or the clicked file's folder) are listed.
  -- Kept for the command palette: deleted files anywhere in the project.
  studio.commands:register("localHistory.deleted", function()
    deletedFrom(ui:hasProject() and ws:path("") or "/")
  end)

  studio.commands:register("localHistory.clear", function()
    ui:choose({
      title = "Clear Local History",
      message = "Delete every saved version of every file? This can't be undone.",
      buttons = { "Clear", "Cancel" }, default = 2, cancel = 2,
    }, function(choice)
      if choice ~= 1 then return end
      store:clear()
      for path in pairs(views) do refresh(path) end
      ui:notify("Local History cleared", "success", 2)
    end)
  end)

  -- For other plugins: list versions of a file (newest first) and read one.
  studio.commands:register("localHistory.entries", function(path)
    if type(path) ~= "string" then return {} end
    local out = {}
    for _, e in ipairs(store:entries(ws:path(path))) do
      out[#out + 1] = { id = e.id, time = e.time, label = e.label, size = e.size, group = e.group }
    end
    return out
  end)
  studio.commands:register("localHistory.read", function(path, id)
    if type(path) ~= "string" then return nil end
    local entry = store:find(ws:path(path), tonumber(id))
    return entry and store:read(entry) or nil
  end)
end

return plugin

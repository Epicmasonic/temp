
local plugin = {}

local showMenu

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, ws = studio.ui, studio.workspace
  local tree
  local expanded = {}
  local lastButton = 1
  local hint
  local drag

  ui:onRawEvent(function(event, button)
    if event == "mouse_click" then
      lastButton = button
      if button == 1 and studio.keybindings:isDown("ctrl") then lastButton = 2 end
    end
  end)

  local function nodeFor(entry)
    local node = { text = entry.name, path = entry.path, isDir = entry.isDir }
    if entry.isDir then
      node.children = {}
      node.expanded = false
    end
    return node
  end

  local function load(node)
    node.children = {}
    for _, entry in ipairs(ws:list(node.path, studio.settings:get("explorer.showHidden"))) do
      local child = nodeFor(entry)
      node.children[#node.children + 1] = child
      if child.isDir and expanded[child.path] then
        child.expanded = true
        load(child)
      end
    end
    node.loaded = true
  end

  local function rebuild()
    if not tree then return end
    local root = { path = ws:path("") }
    load(root)
    local selectedPath = tree.selected and tree.selected.path
    tree.nodes = root.children
    if hint then hint.visible = #root.children == 0 end
    if selectedPath then
      local function find(nodes)
        for _, n in ipairs(nodes) do
          if n.path == selectedPath then return n end
          if n.children then local f = find(n.children) if f then return f end end
        end
      end
      local n = find(root.children)
      if n then tree:select(n, false) end
    end
    tree:markDirty()
  end

  local function targetFolder()
    local sel = tree and tree.selected
    if not sel then return ws:path("") end
    if sel.isDir then return sel.path end
    return "/" .. fs.getDir(sel.path)
  end

  function showMenu(x, y)

    local entries = { { label = "New File...", command = "explorer.newFile" } }
    local groups, order = {}, {}
    for _, t in ipairs(ui:fileTemplates()) do
      if t.group then
        if not groups[t.group] then groups[t.group] = {}; order[#order + 1] = t.group end
        local g = groups[t.group]
        g[#g + 1] = { label = t.title or t.id, detail = t.extension and ("." .. t.extension) or nil, template = t.id }
      end
    end
    for _, name in ipairs(order) do
      entries[#entries + 1] = { label = "New " .. name, children = groups[name] }
    end
    entries[#entries + 1] = { label = "New Folder...", command = "explorer.newFolder" }
    if tree and tree.selected then
      entries[#entries + 1] = { separator = true }
      entries[#entries + 1] = { label = "Rename...", detail = "F2", command = "explorer.rename" }
      entries[#entries + 1] = { label = "Delete", detail = "Del", command = "explorer.delete" }
    end

    -- Entries other plugins add with { menu = "explorer/context", when = "file" | "folder" }.
    -- Their command receives the clicked path.
    local sel = tree and tree.selected
    local contributed = {}
    for _, m in ipairs(studio.plugins:menus("explorer/context")) do
      if studio.commands:has(m.command) then
        local fits = m.when == nil
          or (sel ~= nil and ((m.when == "file" and not sel.isDir) or (m.when == "folder" and sel.isDir)))
        if fits then
          local cmd = studio.commands:get(m.command)
          contributed[#contributed + 1] = { label = cmd.title or cmd.id, command = m.command, withPath = true }
        end
      end
    end
    if #contributed > 0 then
      entries[#entries + 1] = { separator = true }
      for _, entry in ipairs(contributed) do entries[#entries + 1] = entry end
    end
    entries[#entries + 1] = { separator = true }
    entries[#entries + 1] = { label = "Refresh", command = "explorer.refresh" }
    ui:popupMenu(x, y, entries, function(entry)
      if not entry then return end
      if entry.template then
        local folder = targetFolder()
        expanded[folder] = true
        ui:newFile(folder, entry.template)
      elseif entry.withPath then
        studio.commands:execute(entry.command, sel and sel.path or ws:path(""))
      else
        studio.commands:execute(entry.command)
      end
    end)
  end

  local function selectedRow()
    if not tree or not tree.selected then return 1 end
    local row = 0
    local function walk(nodes)
      for _, n in ipairs(nodes) do
        row = row + 1
        if n == tree.selected then return true end
        if n.children and n.expanded and walk(n.children) then return true end
      end
    end
    if not walk(tree.nodes or {}) then return 1 end
    return math.max(1, row - (tree.offset or 0))
  end

  local function nodeAtRow(y)
    if not tree or y < 1 or y > tree.height then return nil end
    local row = (tree.offset or 0) + y
    local visible = {}
    local function walk(nodes)
      for _, node in ipairs(nodes or {}) do
        visible[#visible + 1] = node
        if node.children and node.expanded then walk(node.children) end
      end
    end
    walk(tree.nodes)
    return visible[row]
  end

  local function moveInto(source, folder)
    if not source or not folder or not folder.isDir then return end
    local from = source.path:gsub("/+$", "")
    local into = folder.path:gsub("/+$", "")
    if source.isDir and (into == from or into:sub(1, #from + 1) == from .. "/") then
      ui:notify("Can't move a folder into itself", "warning")
      return
    end
    local destination = "/" .. fs.combine(into, fs.getName(from))
    if destination == from then return end

    local oldExpanded = expanded
    local nextExpanded = {}
    for path, isOpen in pairs(oldExpanded) do
      if isOpen then
        if path == from or path:sub(1, #from + 1) == from .. "/" then
          nextExpanded[destination .. path:sub(#from + 1)] = true
        else
          nextExpanded[path] = true
        end
      end
    end
    nextExpanded[into] = true
    expanded = nextExpanded

    local ok, err = ws:move(from, destination)
    if not ok then
      expanded = oldExpanded
      ui:notify(err or "Couldn't move item", "error")
      return
    end
    rebuild()
    local function find(nodes)
      for _, node in ipairs(nodes or {}) do
        if node.path == destination then return node end
        if node.children then
          local found = find(node.children)
          if found then return found end
        end
      end
    end
    local moved = find(tree.nodes)
    if moved then tree:select(moved, false) end
  end

  studio.ui:addPanel({
    id = "explorer",
    title = "Explorer",
    create = function(frame)
      local theme = ui:theme()
      tree = frame:addTree({
        x = 1, y = 1,
        width = function() return frame.width end,
        height = function() return frame.height end,
        background = theme.sidebarBackground,
        foreground = theme.sidebarForeground,
        selectionBackground = theme.sidebarSelection,
        selectionForeground = theme.sidebarSelectionForeground,
      })
      studio.events:on("themeChanged", function(t)
        tree.background = t.sidebarBackground
        tree.foreground = t.sidebarForeground
        tree.selectionBackground = t.sidebarSelection
        tree.selectionForeground = t.sidebarSelectionForeground
      end)
      tree:on("toggle", function(_, node, isOpen)
        expanded[node.path] = isOpen or nil
        if isOpen and not node.loaded then load(node); tree:markDirty() end
      end)
      tree:on("select", function(_, node)
        if not node or lastButton ~= 1 then return end
        if node.isDir then
          tree:toggle(node)
        else
          ui:openFile(node.path)
        end
      end)

      tree:on("click", function(self, btn, x, y)
        if btn == 1 and lastButton == 1 then
          local source = nodeAtRow(y)
          if source and source == tree.selected then
            local _, count = tree:getNodeSize()
            if not (tree.scrollbar ~= "hidden" and count > tree.height and x == tree.width) then
              drag = { source = source }
              return
            end
          end
        end
        drag = nil
        if btn ~= 2 and lastButton ~= 2 then return end
        local _, count = tree:getNodeSize()
        if (tree.offset or 0) + y > count then
          tree.selected = false
          tree:markDirty()
        end
        local ax, ay = self:getAbsolutePosition()
        showMenu(ax + x - 1, ay + y)
      end)
      tree:on("drag", function(_, btn, _, y)
        if not drag or btn ~= 1 or lastButton ~= 1 then return end
        drag.started = true
        local target = nodeAtRow(y)
        if y < 1 or y > tree.height then
          drag.target = nil
        elseif not target then
          drag.target = { path = ws:path(""), isDir = true, isRoot = true }
        elseif target.isDir then
          drag.target = target
        else
          local parent = fs.getDir(target.path)
          if parent == "" then parent = "/" else parent = "/" .. parent end
          drag.target = { path = parent, isDir = true, isRoot = true }
        end
        if drag.target and not drag.target.isRoot then tree:select(drag.target, false) end
      end)
      tree:on("clickUp", function(_, btn)
        if btn ~= 1 then return end
        local finished = drag
        drag = nil
        if finished and finished.started and finished.target then
          moveInto(finished.source, finished.target)
        end
      end)
      hint = frame:addCanvas({
        x = 1, y = 1, height = 4, z = 2, visible = false,
        width = function() return frame.width end,
        background = theme.sidebarBackground,
        draw = function(_, buf)
          local t = ui:theme()
          local lines = { "", " Empty folder.", " Right-click to", " add files." }
          for i, line in ipairs(lines) do buf:blit(1, i, line:sub(1, frame.width), t.muted, t.sidebarBackground) end
        end,
      })
      hint:onClick(function(self, _, x, y)
        local ax, ay = self:getAbsolutePosition()
        tree.selected = false
        showMenu(ax + x - 1, ay + y)
      end)
      tree:on("key", function(_, key)
        if key == keys.delete and tree.selected then studio.commands:execute("explorer.delete") end
      end)
      rebuild()
      return {
        focus = function() tree:focus() end,
        refresh = rebuild,
      }
    end,
  })

  ws:on("rootChanged", function()
    expanded = {}
    if tree then tree.selected = false end
    rebuild()
  end)
  for _, name in ipairs({ "fileCreated", "fileDeleted", "fileRenamed" }) do
    ws:on(name, rebuild)
  end
  studio.settings:onChange("explorer.showHidden", rebuild)

  studio.commands:register("explorer.focus", function() ui:showPanel("explorer") end)
  studio.commands:register("explorer.contextMenu", function()
    ui:showPanel("explorer")
    if not tree then return end
    local ax, ay = tree:getAbsolutePosition()
    showMenu(ax + 2, ay + selectedRow())
  end)
  studio.commands:register("explorer.refresh", rebuild)

  local function create(kind)
    local folder = targetFolder()
    ui:prompt({ title = kind == "file" and "New File" or "New Folder",
      message = "Name (in " .. (ws:relative(folder) ~= "" and ws:relative(folder) or "project root") .. "):" },
      function(name)
        if not name or name == "" then return end
        local path = "/" .. fs.combine(folder, name)
        if fs.exists(path) then ui:notify(name .. " already exists", "warning") return end
        expanded[folder] = true
        if kind == "file" then
          local ok, err = ws:writeFile(path, "")
          if not ok then ui:notify(err, "error") return end
          ui:openFile(path)
        else
          local ok, err = ws:createFolder(path)
          if not ok then ui:notify(err, "error") end
        end
      end)
  end
  studio.commands:register("explorer.newFile", function()
    local folder = targetFolder()
    expanded[folder] = true
    studio.commands:execute("file.new", folder)
  end)
  studio.commands:register("explorer.newFolder", function() create("folder") end)

  studio.commands:register("explorer.rename", function()
    local sel = tree and tree.selected
    if not sel then ui:notify("Select a file first", "info") return end
    ui:prompt({ title = "Rename", message = "New name:", default = fs.getName(sel.path) }, function(name)
      if not name or name == "" or name == fs.getName(sel.path) then return end
      local target = "/" .. fs.combine(fs.getDir(sel.path), name)
      local ok, err = ws:move(sel.path, target)
      if not ok then ui:notify(err, "error") end
    end)
  end)

  studio.commands:register("explorer.delete", function()
    local sel = tree and tree.selected
    if not sel then ui:notify("Select a file first", "info") return end
    ui:choose({ title = "Delete", message = "Delete " .. ws:relative(sel.path) .. "? This can't be undone.",
      buttons = { "Delete", "Cancel" }, default = 2, cancel = 2 }, function(choice)
      if choice ~= 1 then return end
      for _, e in ipairs(ui:editors()) do
        local p = e.doc.path
        if p == sel.path or p:sub(1, #sel.path + 1) == sel.path .. "/" then ui:closeEditor(e) end
      end
      local ok, err = ws:delete(sel.path)
      if not ok then ui:notify(err, "error") end
    end)
  end)
end

return plugin

local R = require("pineapple.studio.ui.rows")
local scrollbar = require("pineapple.studio.ui.scrollbar")

local M = {}

function M.new(host, P, theme)
  local studio, packer = P.studio, P.packer
  local ui, settings = studio.ui, studio.settings
  local self = { scroll = 0, hits = {} }
  local canvas
  local function dirty() if canvas then canvas:markRenderDirty() end end
  local ctx = { theme = theme }

  local function pickMain(x, y)
    local items = {}
    local root = studio.workspace:path("")
    local function walk(dir, rel)
      for _, name in ipairs(fs.list(dir)) do
        local path = fs.combine(dir, name)
        local r = rel == "" and name or (rel .. "/" .. name)
        if name:sub(1, 1) ~= "." then
          if fs.isDir(path) then walk(path, r)
          elseif name:match("%.lua$") then items[#items + 1] = { label = r, detail = r == P.mainFile() and "*" or nil, path = r } end
        end
      end
    end
    walk(root, "")
    table.sort(items, function(a, b) return a.label < b.label end)
    ui:quickPick(items, { title = "Main File", placeholder = "The file that runs" }, function(item)
      if item then P.set("run.main", item.path); dirty() end
      canvas:focus()
    end)
  end

  local function listFiles()
    local list = P.files()
    local items = {}
    for _, f in ipairs(list) do items[#items + 1] = { label = f.path, detail = packer.formatSize(#f.data) } end
    if #items == 0 then items[1] = { label = "(no files)" } end
    ui:quickPick(items, { title = "Files in the package", placeholder = "Hidden files, .pineapple and excluded files are left out" },
      function() canvas:focus() end)
  end

  local function editExclude()
    local current = table.concat(settings:get("package.exclude") or {}, ", ")
    ui:prompt({ title = "Leave Out", message = "Files or folders to leave out (comma separated, * wildcards, folder/):",
      default = current }, function(text)
      if text == nil then canvas:focus() return end
      local list = {}
      for part in text:gmatch("[^,]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then list[#list + 1] = part end
      end
      P.set("package.exclude", list)
      canvas:focus(); dirty()
    end)
  end

  local function editDownloads()
    local list = P.downloads()
    local items = { { label = "Add a download...", add = true } }
    for i, d in ipairs(list) do items[#items + 1] = { label = d.path, detail = "remove", index = i } end
    ui:quickPick(items, { title = "Download at install", placeholder = "Add, or pick one to remove" }, function(item)
      if not item then canvas:focus() return end
      if item.add then
        ui:prompt({ title = "Download", message = "URL to download (e.g. a raw GitHub file):" }, function(url)
          if not url or url == "" then canvas:focus() return end
          local guess = url:match("([^/?#]+)$") or "file.lua"
          ui:prompt({ title = "Download", message = "Save it as (relative to where it installs):", default = guess },
            function(path)
              if path and path ~= "" then
                local copy = {}
                for i, d in ipairs(list) do copy[i] = d end
                copy[#copy + 1] = { path = path, url = url }
                P.set("package.downloads", copy)
              end
              canvas:focus(); dirty()
            end)
        end)
      else
        local copy = {}
        for i, d in ipairs(list) do if i ~= item.index then copy[#copy + 1] = d end end
        P.set("package.downloads", copy)
        canvas:focus(); dirty()
      end
    end)
  end

  local function editOutput()
    ui:prompt({ title = "Save To", message = "Package file, relative to the project:", default = P.output() },
      function(text)
        if text and text ~= "" then P.set("package.output", text) end
        canvas:focus(); dirty()
      end)
  end

  local function rows(w)
    local out = {}
    local format = settings:get("package.format") or "installer"

    local saved = P.results.saved
    if saved then
      R.text(out, "Saved " .. saved.path .. " (" .. packer.formatSize(saved.size) .. ").", w, ctx,
        { color = function(t) return t.foreground end })
    end
    local paste = P.results.paste
    if paste then
      R.text(out, "On Pastebin as pastebin.com/" .. paste.id .. ". On any computer, type:", w, ctx,
        { color = function(t) return t.foreground end })
      local cmd = paste.format == "installer" and ("pastebin run " .. paste.id)
        or ("pastebin get " .. paste.id .. " " .. paste.name)
      R.text(out, cmd, w, ctx, { indent = 2, color = function(t) return t.accent end })
    end
    if not saved and not paste then
      R.text(out, "Save writes the package into the project; Upload puts it on Pastebin and shows the "
        .. "command to type on another computer.", w, ctx)
    end
    R.blank(out)

    local fieldW = math.min(22, math.max(10, math.floor(w * 0.4)))
    R.header(out, "Format", ctx)
    for _, f in ipairs({
      { "installer", "Installer", "One file that installs the project into the folder it is in (or the current "
        .. "folder with pastebin run). Runs on any computer; Studio isn't needed." },
      { "program", "Single-file program", "The whole project in one file that runs as is. Its modules and "
        .. "files are read from inside it." },
    }) do
      local id = f[1]
      local function pick() P.set("package.format", id); dirty() end
      local it = { title = f[2], description = f[3], activate = pick }
      it.controlW, it.control = R.radio(format == id, pick)
      R.item(out, it, w, ctx)
    end

    R.header(out, "Options", ctx)
    local main = P.mainFile()
    local pos = {}
    local mainItem = { title = "Main file", activate = function() pickMain() end,
      description = format == "program" and "What the program runs." or "The installer says how to start it." }
    local mw, mdraw = R.box(main or "(choose)", fieldW, { arrow = true }, function() pickMain() end)
    mainItem.controlW = mw
    mainItem.control = function(buf, x, y, cw, focused, hit) pos.x, pos.y = x, y; mdraw(buf, x, y, cw, focused, hit) end
    R.item(out, mainItem, w, ctx)

    local compress = settings:get("package.compress") == true
    local function toggle() P.set("package.compress", not compress); dirty() end
    local c = { title = "Compress", activate = toggle,
      description = "Smaller but not readable; for big projects or Pastebin's 512 KB limit." }
    c.controlW, c.control = R.checkbox(compress, false, toggle)
    R.item(out, c, w, ctx)

    local list, total = P.files()
    local f = { title = "Files", activate = listFiles,
      description = "Hidden files (.pineapple, .git) are always left out.",
      link = { text = "leave out...", action = editExclude } }
    f.controlW, f.control = R.box(#list .. " files, " .. packer.formatSize(total), fieldW, nil, listFiles)
    R.item(out, f, w, ctx)

    if format == "installer" then
      local downloads = P.downloads()
      local d = { title = "Download at install", activate = editDownloads,
        description = "Files the installer fetches instead of packing, e.g. a library like Basalt." }
      d.controlW, d.control = R.box(#downloads == 0 and "none" or (#downloads .. " file" .. (#downloads == 1 and "" or "s")),
        fieldW, nil, editDownloads)
      R.item(out, d, w, ctx)
    end

    local o = { title = "Save to", activate = editOutput }
    o.controlW, o.control = R.box(P.output(), fieldW, nil, editOutput)
    R.item(out, o, w, ctx)

    return out
  end

  local function draw(_, buf)
    local w, h = canvas.width, canvas.height
    local t = ctx.theme
    R.theme = t
    local bg = t.editorBackground
    buf:fill(1, 1, w, h, " ", t.foreground, bg)
    local hits = {}
    self.hits = hits

    local bandBg = t.panelHeaderBackground
    local tall = h >= 22
    local titleY = tall and 2 or 1
    local buttonsY = titleY + 2
    local bandH = buttonsY + 1
    buf:fill(1, 1, w, bandH, " ", t.panelHeaderForeground, bandBg)
    buf:blit(3, titleY, "Package", t.accent, bandBg)
    buf:blit(12, titleY, P.projectName():sub(1, math.max(0, w - 13)), t.panelHeaderForeground, bandBg)
    local function button(x, label, action, focused)
      local fg, b2 = t.accentForeground, t.accent
      if focused then fg, b2 = t.accent, t.accentForeground end
      buf:blit(x, buttonsY, label, fg, b2)
      hits[#hits + 1] = { x1 = x, x2 = x + #label - 1, y = buttonsY, action = action }
      return x + #label + 2
    end
    local busy = P.results.working or P.results.uploading
    local bx = button(3, P.results.working and " Packing... " or " Save ", function() if not busy then P.save() end end)
    local up = P.results.uploading and " Uploading... " or (w >= 30 and " Upload to Pastebin " or " Upload ")
    button(bx, up, function() if not busy then P.upload() end end)

    local top = bandH + 2
    local contentX, contentW = 3, w - 5
    local list = rows(contentW)
    local focusables = {}
    for i, r in ipairs(list) do if r.focusable then focusables[#focusables + 1] = i end end
    self.focusables = focusables
    local focusRow = self.focusIndex and self.keyboard and focusables[self.focusIndex]
    local visible = h - top + 1
    if focusRow then
      if focusRow - 1 < self.scroll then self.scroll = math.max(0, focusRow - 2) end
      if focusRow + 2 > self.scroll + visible then self.scroll = focusRow + 2 - visible end
    end
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, #list - visible)))
    self.maxScroll = math.max(0, #list - visible)
    for r = 1, visible do
      local i = self.scroll + r
      local row = list[i]
      if not row then break end
      local y = top + r - 1
      local function hit(x1, x2, action) hits[#hits + 1] = { x1 = x1, x2 = x2, y = y, action = action } end
      row.draw(buf, contentX, y, contentW, i == focusRow, hit)
    end
    self.rows = list
    self.bar = { x = w, y = top, height = visible, total = #list, visible = visible }
    scrollbar.draw(buf, t, w, top, visible, #list, visible, self.scroll)
  end

  canvas = host:addCanvas({
    x = 1, y = 1,
    width = function() return host.width end,
    height = function() return host.height end,
    background = theme.editorBackground,
    draw = draw,
  })
  canvas:onClick(function(_, _, x, y)
    self.keyboard = false
    local bar = self.bar
    if bar and x == bar.x and y >= bar.y and bar.total > bar.visible then
      self.scroll = scrollbar.offsetAt(y - bar.y, bar.height, bar.total, bar.visible); dirty() return
    end
    for _, hit in ipairs(self.hits) do
      if y == hit.y and x >= hit.x1 and x <= hit.x2 then hit.action(); dirty() return end
    end
  end)
  canvas:onScroll(function(_, dir)
    self.scroll = math.max(0, math.min(self.maxScroll or 0, self.scroll + dir * 2)); dirty()
  end)
  canvas:onKey(function(_, key)
    local n = #(self.focusables or {})
    if key == keys.up or key == keys.down then
      self.keyboard = true
      if not self.focusIndex then self.focusIndex = key == keys.down and 1 or n
      else self.focusIndex = math.max(1, math.min(n, self.focusIndex + (key == keys.up and -1 or 1))) end
    elseif key == keys.enter or key == keys.numPadEnter then
      self.keyboard = true
      self.focusIndex = self.focusIndex or 1
      local row = self.rows and self.rows[(self.focusables or {})[self.focusIndex] or 0]
      if row and row.activate then row.activate() end
    else
      return
    end
    dirty()
  end)
  local sub = settings:onChange("*", dirty)

  self.element = canvas
  function self.refresh() dirty() end
  function self.focus() canvas:focus(); dirty() end
  function self.applyTheme(_, t) ctx.theme = t; canvas.background = t.editorBackground; dirty() end
  function self.dispose()
    if P.view == self then P.view = nil end
    if sub and sub.dispose then sub:dispose() end
    canvas:destroy()
  end
  P.view = self
  return self
end

return M

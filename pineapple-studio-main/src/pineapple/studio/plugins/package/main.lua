local packer = require("pineapple.studio.plugins.package.packer")
local packageView = require("pineapple.studio.plugins.package.packageview")

local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local ui, settings = studio.ui, studio.settings
  local function ws() return studio.workspace end

  local P = { studio = studio, packer = packer, results = {} }

  local function changed()
    if P.view then P.view.refresh() end
  end

  function P.projectName()
    local root = ws():path("")
    local name = fs.getName(root)
    return (name == "" or name == "root") and "project" or name
  end

  function P.mainFile()
    local configured = settings:get("run.main")
    if configured and configured ~= "" and fs.exists(ws():path(configured)) then return configured end
    for _, name in ipairs({ "main.lua", "startup.lua", "init.lua" }) do
      if fs.exists(ws():path(name)) then return name end
    end
    return nil
  end

  function P.output()
    local out = settings:get("package.output")
    if not out or out == "" then out = "build/" .. P.projectName() .. ".lua" end
    return out
  end

  function P.set(key, value)
    local ok, err = pcall(settings.set, settings, key, value, ui:hasProject() and "project" or "user")
    if not ok then ui:notify(tostring(err), "error") end
  end

  function P.files()
    return packer.collect(ws():path(""), { exclude = settings:get("package.exclude") or {}, skip = { P.output() } })
  end

  function P.downloads() return settings:get("package.downloads") or {} end

  function P.runTask(fn, done)
    if P.sync then
      local ok, a, b = pcall(fn, function() end)
      done(ok, a, b)
      return
    end

    local co = coroutine.create(fn)
    local hook, timer
    local function step()
      local ok, a, b = coroutine.resume(co, coroutine.yield)
      if coroutine.status(co) == "dead" then
        if hook then hook:dispose() end
        done(ok, a, b)
      else
        timer = os.startTimer(0)
      end
    end
    hook = ui:onRawEvent(function(event, id) if event == "timer" and id == timer then step() end end)
    step()
  end

  function P.build(done)
    local format = settings:get("package.format") or "installer"
    local main = P.mainFile()
    if format == "program" and not main then
      done(nil, "Pick the main file first (it's what the program runs)")
      return
    end
    P.results.working = true
    changed()
    P.runTask(function(yield)
      local list = packer.collect(ws():path(""), { exclude = settings:get("package.exclude") or {},
        skip = { P.output() }, yield = yield })
      if #list == 0 then error("The project has no files to pack", 0) end
      local opts = { name = P.projectName(), main = main, compress = settings:get("package.compress") == true,
        yield = yield, downloads = P.downloads() }
      return (format == "program" and packer.program or packer.installer)(list, opts), list
    end, function(ok, source, list)
      P.results.working = nil
      changed()
      if ok then done(source, list) else done(nil, (tostring(source):gsub("^.-:%d+: ", ""))) end
    end)
  end

  function P.save(done)
    P.build(function(source, err)
      if not source then
        ui:notify(err, "warning", 4)
        if done then done(nil, err) end
        return
      end
      local rel = P.output()
      local ok, werr = ws():writeFile(ws():path(rel), source)
      if not ok then
        ui:notify(tostring(werr), "error")
        if done then done(nil, werr) end
        return
      end
      P.results.saved = { path = rel, size = #source }
      ui:notify("Saved " .. rel .. " (" .. packer.formatSize(#source) .. ")", "info", 3)
      changed()
      if done then done(rel) end
    end)
  end

  function P.pastebin(name, text, done)
    local api = P.http or http
    if not api then
      done(nil, "HTTP is turned off on this computer (enable it in the CC: Tweaked config)")
      return
    end
    if #text > packer.PASTEBIN_LIMIT then
      done(nil, "Too big for Pastebin (" .. packer.formatSize(#text) .. ", the limit is 512 KB); try Compress")
      return
    end
    local url, body, headers = packer.pastebinRequest(name, text)
    local hook
    hook = ui:onRawEvent(function(event, u, handle, failResponse)
      if u ~= url then return end
      if event == "http_success" then
        hook:dispose()
        local response = handle.readAll()
        handle.close()
        done(packer.pastebinResult(response))
      elseif event == "http_failure" then
        hook:dispose()
        local detail = handle
        if failResponse then pcall(function() detail = failResponse.readAll(); failResponse.close() end) end
        done(nil, "Couldn't reach Pastebin: " .. tostring(detail or "no connection"))
      end
    end)
    local ok, err = pcall(api.request, url, body, headers)
    if not ok then hook:dispose(); done(nil, tostring(err)) end
  end

  function P.upload(finished)
    P.build(function(source, err)
      if not source then
        ui:notify(err, "warning", 4)
        if finished then finished(nil, err) end
        return
      end
      P.results.uploading = true
      changed()
      local format = settings:get("package.format") or "installer"
      P.pastebin(P.projectName() .. (format == "installer" and " installer" or ""), source, function(id, uerr)
        P.results.uploading = false
        if id then
          P.results.paste = { id = id, format = format, name = P.projectName() }
          ui:notify("Uploaded to pastebin.com/" .. id, "info", 4)
        else
          P.results.paste = nil
          ui:notify(uerr, "error", 6)
        end
        changed()
        if finished then finished(id, uerr) end
      end)
    end)
  end

  local function hasProject() return ui:hasProject() end

  studio.commands:register("package.open", function()
    local editor = ui:openView({
      id = "package", title = "Package",
      create = function(host, opts) return packageView.new(host, P, opts.theme) end,
    })
    if editor then editor.instance.focus() end
    return editor
  end, { enabled = hasProject })
  studio.commands:register("package.save", function() P.save() end, { enabled = hasProject })
  studio.commands:register("package.upload", function() P.upload() end, { enabled = hasProject })

  studio.commands:register("package.uploadFile", function()
    local e = ui:activeEditor()
    if not e or e.doc.virtual then return end
    local name = fs.getName(e.doc.path)
    ui:notify("Uploading " .. name .. "...", "info", 2)
    P.pastebin(name, e.doc:getText(), function(id, err)
      if id then
        ui:choose({ title = "Uploaded to Pastebin",
          message = name .. " is at pastebin.com/" .. id .. "\nGet it on any computer with:\npastebin get " .. id .. " " .. name,
          buttons = { "OK" } })
      else
        ui:notify(err, "error", 6)
      end
    end)
  end, { enabled = function()
    local e = ui:activeEditor()
    return e ~= nil and not e.doc.virtual
  end })

  plugin.api = P
end

return plugin

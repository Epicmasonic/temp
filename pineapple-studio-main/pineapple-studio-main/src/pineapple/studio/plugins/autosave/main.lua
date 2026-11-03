local plugin = {}

function plugin.activate(ctx)
  local studio = ctx.studio
  local watchers = {}

  local function watch(doc)
    if watchers[doc] then return end
    local save = studio.timers:debounce(studio.settings:get("files.autoSaveDelay", 1), function()
      if studio.settings:get("files.autoSave") and doc:isDirty() and not doc.readOnly then
        local ok, err = doc:save({ source = "Auto-save" })
        if not ok then studio.ui:notify(err, "error") end
      end
    end)
    watchers[doc] = { save = save, listener = doc:on("change", function() save() end) }
  end

  local function unwatch(doc)
    local w = watchers[doc]
    if not w then return end
    w.listener:dispose()
    w.save.cancel()
    watchers[doc] = nil
  end

  studio.workspace:on("documentOpened", watch)
  studio.workspace:on("documentClosed", unwatch)
  for _, e in ipairs(studio.ui:editors()) do
    if not e.doc.virtual then watch(e.doc) end
  end

  ctx.subscriptions:add(function()
    for doc in pairs(watchers) do unwatch(doc) end
  end)

  studio.commands:register("autosave.toggle", function()
    local on = not studio.settings:get("files.autoSave")
    studio.settings:set("files.autoSave", on)
    studio.ui:notify("Auto save " .. (on and "on" or "off"), "info")
  end)

  studio.ui:addStatusItem({
    id = "autosave", align = "right", priority = 1,
    text = function() return studio.settings:get("files.autoSave") and "Auto" or nil end,
  })
end

return plugin

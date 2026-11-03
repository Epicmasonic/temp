return {
  id = "pineapple.local-history",
  name = "Local History",
  version = "0.1.0",
  main = "main.lua",
  description = "Keeps earlier versions of files changed in Studio, so changes can be reviewed and reverted.",
  activation = { "onStartup" },
  contributes = {
    commands = {
      { id = "localHistory.show", title = "Show Local History", category = "File" },
      { id = "localHistory.deleted", title = "Restore Deleted File...", category = "File" },
      { id = "localHistory.clear", title = "Clear Local History...", category = "File" },
      -- For other plugins (e.g. the AI Assistant): entries(path) and read(path, id).
      { id = "localHistory.entries", title = "Local History Entries", hidden = true },
      { id = "localHistory.read", title = "Read Local History Entry", hidden = true },
    },
    menus = {
      { menu = "explorer/context", command = "localHistory.show" },
    },
    settings = {
      ["localHistory.enabled"] = { type = "boolean", default = true, title = "Keep local history",
        description = "Save the previous version of a file whenever Studio changes it" },
      ["localHistory.maxEntries"] = { type = "number", default = 30, title = "Local history versions per file" },
      ["localHistory.maxDays"] = { type = "number", default = 14, title = "Days to keep local history" },
      ["localHistory.maxSizeKB"] = { type = "number", default = 256, title = "Local history size limit (KB)",
        description = "Oldest versions are removed first; computer disks are small" },
    },
  },
}

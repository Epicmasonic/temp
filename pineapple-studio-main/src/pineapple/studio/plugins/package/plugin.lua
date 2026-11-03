return {
  id = "pineapple.package",
  name = "Package & Share",
  version = "0.1.0",
  main = "main.lua",
  description = "Packs the project into a single-file program or a standalone installer; saves it, or uploads it to Pastebin for `pastebin run`.",
  contributes = {
    commands = {
      { id = "package.open", title = "Package Project...", category = "Package" },
      { id = "package.save", title = "Save Package", category = "Package" },
      { id = "package.upload", title = "Upload Package to Pastebin", category = "Package" },
      { id = "package.uploadFile", title = "Upload Current File to Pastebin", category = "Package" },
    },
    menus = {
      { menu = "File", command = "package.open", group = "4" },
      { menu = "File", command = "package.uploadFile", group = "4" },
    },
    settings = {
      ["package.format"] = { type = "string", default = "installer", title = "Package format",
        description = "What Package Project builds",
        options = { { value = "installer", label = "Installer" }, { value = "program", label = "Single-file program" } } },
      ["package.compress"] = { type = "boolean", default = false, title = "Compress packages",
        description = "Smaller, but not readable; for big projects or Pastebin's 512 KB limit" },
      ["package.output"] = { type = "string", title = "Package file",
        description = "Where Save Package writes, relative to the project (default build/<project>.lua)" },
      ["package.exclude"] = { type = "table", default = { "build/" }, hidden = true,
        title = "Files and folders left out of packages" },
      ["package.downloads"] = { type = "table", default = {}, hidden = true,
        title = "Files the installer downloads: { { path = ..., url = ... } }" },
    },
  },
}

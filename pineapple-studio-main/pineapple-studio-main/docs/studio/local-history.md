# Local History

Studio keeps earlier versions of files it changes, so you can see what changed and go back.
Right-click a file in the Explorer and choose **Show Local History** to see its versions. On a folder (or the empty
space below the files, for the whole project) the same item lists files deleted from it; pick one to open its
history and Revert to bring it back.

A version is saved just before Studio writes or deletes a file: editor saves, auto-save, approved AI Assistant
edits, reverts, and deletes from the Explorer. Each version is labelled with the change that replaced it.
Auto-saves within five minutes of each other share one version. Changes made outside Studio (for example by a
running program or the shell) aren't recorded.

The history tab lists versions newest first. **This change** shows what that change did; **Compare to now** shows
the difference between that version and the file today. **Revert** (or `R`) restores the selected version; the
contents it replaces are kept as a new version, so a revert can itself be reverted.

History is stored in Studio's data folder, not the project. Limits are in Settings: versions per file (30), days
to keep (14) and total size (256 KB), since computer disks are small. Files over 64 KB aren't recorded.

## For plugins

Writes that go through `studio.workspace:writeFile(path, text, info)` or `document:save(info)` can describe
themselves with `info.source`, which becomes the version's label:

```lua
doc:save({ source = "My Plugin" })
```

Other plugins can read history through commands:

```lua
local versions = studio.commands:execute("localHistory.entries", path)  -- newest first: { id, time, label, size }
local text = studio.commands:execute("localHistory.read", path, versions[1].id)
```

Plugins can also add entries to the Explorer's context menu with `menu = "explorer/context"`; `when` is
`"file"` or `"folder"`, and the command receives the clicked path.

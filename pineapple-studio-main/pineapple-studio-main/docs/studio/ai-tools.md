# AI tools for Studio plugins

Plugins can register functions for the AI Assistant to offer to compatible models. The model receives each
tool's name, description and JSON Schema; Studio runs the tool when the model calls it.

Register tools during plugin activation:

```lua
function plugin.activate(ctx)
  ctx.studio.tools:register({
    name = "project_summary",
    description = "Return a short summary of the current project.",
    parameters = { type = "object", properties = {}, additionalProperties = false },
    readOnly = true,
    describe = function(args, result) return "Summarised the project" end,
    run = function(args)
      return "Project summary"
    end,
  })
end
```

Studio prefixes each tool name with a normalised plugin ID, so two plugins can use the same short name. The
registration is removed automatically when the plugin is disabled. `run` receives the decoded arguments and
may return text or a serialisable table.

Optional fields:

- `describe(args, result, err)` returns the short line shown in the chat's activity log, such as
  "Read main.lua (lines 1-80)". Without it the chat shows "Used project_summary".
- `readOnly = true` marks tools that never change anything.

## Tools that wait

Tools that need the user (a confirmation, a program run) can finish later. Accept a second `complete(result, err)`
argument and return `ctx.studio.tools.ASYNC`:

```lua
run = function(args, complete)
  ctx.studio.ui:choose({ title = "Allow?", buttons = { "Yes", "No" } }, function(choice)
    complete(choice == 1 and "Done" or "The user declined.")
  end)
  return ctx.studio.tools.ASYNC
end
```

## Change tools

A tool that changes a file should propose the change instead of writing it, by implementing `prepare` instead
of `run`. The assistant collects every change from one model reply, shows them to the user in a single review,
and writes only the files the user approves (recorded in Local History as "AI Assistant").

```lua
ctx.studio.tools:register({
  name = "add_header",
  description = "Add a licence header to a Lua file.",
  parameters = {
    type = "object", properties = { path = { type = "string" } },
    required = { "path" }, additionalProperties = false,
  },
  prepare = function(args, base)
    local path = ctx.studio.workspace:path(args.path)
    local text = base(path) or ctx.studio.workspace:readFile(path)
    if not text then return nil, "File not found" end
    return { path = path, newText = "-- MIT licence\n" .. text }
  end,
})
```

`base(path)` returns the file's text after earlier changes in the same reply (or nil), so several changes to one
file combine. Return `nil, message` to refuse; the message goes back to the model.

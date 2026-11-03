# AI Assistant

The AI Assistant is a chat panel (Ctrl+Alt+I, or "Open AI Assistant" in the command palette) for any
OpenAI-compatible model API:
OpenAI, OpenRouter, a local Ollama or LM Studio server, or anything else with `/chat/completions`.

## Setting it up

Open the panel's `=` menu and choose Configure Provider. Pick a preset, enter the API key if it needs one (hidden as you type), then pick
a model from the provider's list or type one. These settings are stored in your user settings only; a project
can't change the URL, model, key or file access. CC: Tweaked blocks `localhost` by default, so local servers
work in CraftOS-PC or with an HTTP rule allowing them. Requests that fail with HTTP 429 or 5xx are retried with
backoff.

## What it can do

- Read the project: list files (recursively, with patterns like `*.lua`), read whole files or line ranges,
  search, read the active editor and selection, see project facts, and look at the Studio screen. Results
  aren't cut short, so reading big files uses more tokens.
- Check Lua files for problems, look up the CC: Tweaked API, outline Basalt and Bedrock layouts, and read Local
  History versions.
- Propose file changes. All changes from one reply open in one review tab; tick the files to keep and Apply (Y),
  or Cancel (N/Esc). Nothing is written without that.
- Run a file, the project or a shell command (such as `ls` or `gps locate`), after you agree, and read its
  output. It waits up to the time limit (Settings, 15 seconds by default; it can ask for up to 600 for a run),
  then stops the program, because many CC programs never end on their own. It can instead keep the program
  running and test it like a user: see the Run terminal's screen (with colours), click, drag and scroll, press
  keys, type text, then stop it. It can only control programs it started in the current chat. "Allow This
  Chat" skips the question for the rest of the chat.
- Open a file in the editor at a line, to show you something.
- Rename or delete files, after you agree. Local History keeps deleted files.

Each tool use appears as a short line in the chat. There's no limit on how many tools one reply uses.

The whole conversation is sent with every request until you start a New Chat. If it grows past what the model
can take, the chat says so; start a New Chat to continue. Long chats also make the saved chat file larger,
which matters on a computer's small disk. While the assistant works, the button beside the input is a
red square: click it (or press Esc) to stop the reply. When idle, it's a send arrow.

## Auto-approve

Auto-approve (in the panel's `=` menu, or Settings) lets the assistant apply its file changes and run programs,
commands, renames and deletes without asking. It asks you once before turning on. Changed and deleted files are
still recorded in Local History, so "Undo these changes" keeps working.

## Undoing changes

After a reply changes files, the chat shows "Undo these changes". It restores every file from that reply using
Local History (and deletes files it created), and warns if you've edited them since. Undo Last AI Changes in
the panel's `=` menu and `/undo` do the same. Local History doesn't keep files over 64 KB, so changes to those
can't be undone this way. Older changes can be reverted from each file's Local History.

## Typing

Enter sends; Shift+Enter adds a line. Up and Down move between lines, then through earlier prompts.
Code blocks in replies are highlighted and have Copy and Insert (into the active editor) buttons.
`/undo` undoes the latest AI changes, `/new` starts a new chat and `/help` lists these.

## Project notes

A project can describe itself to the assistant in `.pineapple/ai.md`: its
structure, conventions, how to run it. The notes are added to every request as context. They can't grant
permissions or change the assistant's rules.

## Testing with a script

For testing Studio itself, choose "Offline test script" as the provider and point it at a Lua file that returns
assistant messages, one per request:

```lua
{
  replies = {
    { tool_calls = { { id = "1", type = "function", ["function"] = {
      name = "pineapple_openai_connector_read_file", arguments = "{\"path\":\"main.lua\"}" } } } },
    { content = "main.lua prints hello." },
  },
}
```

New Chat starts the script from the first reply again.

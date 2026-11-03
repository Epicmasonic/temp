# Pineapple Studio

The ultimate, most feature-rich IDE for ComputerCraft and CC: Tweaked.

Pineapple Studio is designed to make editing in-game a better experience than using an out-of-game
IDE: write, run, debug, design, and package Lua projects without leaving Minecraft.

## Installation

Clone the repository into the CraftOS computer's root folder

```sh
git clone git@gitlab.com:quarrydev/pineapple-studio.git
```

and then launch Pineapple Studio from the CraftOS shell:
```sh
pineapple-studio/src/bin/studio
```

## Features

- Extensible plugin system for adding commands, editors, panels, menus, settings, and project templates
- Lua editor with syntax highlighting, autocomplete, diagnostics, code folding, and go-to-definition, plus XML highlighting
- Integrated runner (with program arguments and per-project defaults), terminal, project search, and debugger with breakpoints and stepping
- Visual UI designers for Basalt and Bedrock, with a Code view for editing the layout source
- Local History: earlier versions of every file Studio changes, with diffs, revert, and restoring deleted files ([docs](docs/studio/local-history.md))
- AI Assistant for OpenAI-compatible APIs that can read, run, and test your project and propose reviewed, undoable edits ([docs](docs/studio/ai-assistant.md))
- Project wizard with Lua, Basalt, Studio plugin, and empty project templates
- Adaptable, dockable workspace that works across different screen sizes
- Themes and customizable keyboard shortcuts, including Pineapple Studio, VS Code, and IntelliJ keymaps
- Package projects as installers or single-file programs, with optional Pastebin sharing
- Image viewer for `.nfp`, `.nft`, and `.bimg` files
- And many more!

## Disclaimer

Pineapple Studio is beta software. It may contain bugs, incomplete features, and breaking changes.
Keep backups of important projects and report issues with steps to reproduce them. The software works best on larger than the default 51x19 resolution screens

## Credits

- [Basalt 2.5](https://github.com/Pyroxenium/Basalt2), by Pyroxenium, is bundled under the MIT license; see [`lib/basalt/LICENSE`](lib/basalt/LICENSE).
- [Bedrock](https://github.com/oeed/Bedrock), originally developed by oeed.
- Thanks to the [CC: Tweaked](https://tweaked.cc/) and [CraftOS-PC](https://www.craftos-pc.cc/) projects.

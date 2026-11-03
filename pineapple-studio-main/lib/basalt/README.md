# Basalt (vendored)

[Basalt 2.5](https://github.com/Pyroxenium/Basalt2/tree/basalt2.5) by Pyroxenium, MIT licence (see `LICENSE`,
taken from the repository's `main` branch; the `basalt2.5` branch has no licence file of its own).

| | |
|---|---|
| Branch / commit | `basalt2.5` @ `4372b70c0d34cf0cc2687b1f67776e1de025c888` (2026-08-21) |
| Version string | `2.5.0-dev` |
| File | `bundle/basalt.lua` (readable single-file build), saved here as `init.lua` so `require("basalt")` finds it |
| SHA-256 | `e327ddafdc999b4066bb4ad3dcfe1c72f200d02c718b627de22ebe4583ebf00d` |
| Docs | https://basalt.madefor.cc/2.5/ |

Basalt 2.5 has no tagged release yet, so this is pinned to a commit. We use the readable bundle during
development because its error traces point at real line numbers. Releases can switch to
`bundle/basalt.min.lua` (193 KB) or `bundle/basalt.compressed.lua` (68 KB).

To update: download `bundle/basalt.lua` from a newer `basalt2.5` commit, replace `init.lua`, update this
table and check that Studio and the Basalt designer still work in CraftOS-PC.

## Notes for Pineapple Studio code

- Don't edit `init.lua`. Studio-specific behaviour belongs in Studio's own code.
- The bundle doesn't expose `core/class`, so Basalt element classes can't be subclassed from outside.
  Custom widgets (e.g. the code editor) are built from a `Canvas` element (custom `draw` callback)
  plus its public events (`click`, `drag`, `scroll`, `key`, `char`, `paste`, `focus`, `blur`).
- `basalt.use("theme").classes` gives access to the element classes and their property metadata
  (`Class.__props`, `Class.__defaults`), which the Studio designer can use.

# Folder Structure

```
mythforge/
├── godot/                     # ← THE GAME. Everything that runs is under here.
│   ├── project.godot          # autoload registry, main scene
│   ├── docs/                  # this documentation set — source of truth
│   ├── autoload/              # singletons: one system per file (see Architecture.md)
│   ├── scenes/                # .tscn: main_menu, game, forge/, combat/, ui/
│   ├── scripts/               # scene scripts, same basename as their scene
│   ├── ui/                    # MythButton, MythPlate, MythIcon… the design system
│   ├── data/                  # shipped game data (JSON is the truth)
│   │   └── tables.json · spells.json · bestiary.json · worlds.json · class_lore.json
│   ├── assets/                # sfx, music, fonts, icon library
│   ├── addons/nobodywho/      # the GDExtension (binary fetched, not committed)
│   ├── baked/                 # pre-baked world zips (release assets, gitignored)
│   ├── tools/                 # in-editor bake tools (icons, preview bar)
│   ├── spike3d/               # 3D character spike — not in the shipped path
│   └── tests/                 # the harnesses (see Testing.md)
├── scripts/                   # developer tooling: art bakes, engine fetchers, installer
├── installer/                 # Inno Setup script + bootstrap for a clean machine
├── docs/                      # repo-level notes: code style, troubleshooting
├── build/                     # third-party 3D asset packs (local, gitignored)
├── dist/                      # export output (gitignored)
└── play-mythforge.cmd         # run the project from source in the editor runtime
```

## Conventions

- A new system is a new autoload file, registered in `project.godot` and
  documented in [Architecture.md](Architecture.md). Scene scripts orchestrate UI;
  they do not hold rules.
- Game data changes go in `godot/data/*.json` and are committed.
- Nothing generated at runtime lives in the repo — it goes to `user://`.
- Screenshots and scratch files go to the session scratchpad, never committed.

## `user://`

`%APPDATA%/Godot/app_userdata/Mythforge` in the editor; the exe's own folder
when shipped.

```
user://
├── models/        # the .gguf files: narrator, encoder, whisper
├── saves/         # <adventure>.json · adventures.json · _global.json
├── saves_test/    # the harnesses' own drawer — never the player's
├── memory/        # campaign memory: beats + vectors, per adventure
├── chapters/      # narrated save-points, per adventure
├── worlds/        # compiled world packages (art + data)
├── art/  tiles/   # generated art cache + sidecars, LRU-budgeted
├── heroes.json    # banked heroes
└── session.cfg    # settings: chosen narrator, UI prefs
```

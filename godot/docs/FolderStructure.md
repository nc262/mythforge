# Folder Structure

```
mythforge/                     # repo root — the FastAPI backend (frozen API)
├── routes/ src/ core/         # backend (see repo-root docs/ for its own set)
├── static/js/characterStudio.js  # LEGACY web client — reference only, never edit
├── scripts/
│   ├── extract_studio_data.mjs   # one-time JS→JSON data extraction
│   └── make_sfx.py               # synthesized SFX generator
├── play-mythforge.cmd         # double-click launcher (desktop shortcut targets this)
└── godot/                     # ← THE GAME (this project)
    ├── project.godot          # autoload registry, main scene
    ├── docs/                  # THIS documentation set — source of truth
    ├── autoload/              # singletons: one system per file (see Architecture)
    ├── scenes/                # .tscn: login, main_menu, game, ui/backdrop
    ├── scripts/               # scene scripts, same basename as their scene
    ├── data/                  # extracted game data (JSON = truth; JS is legacy)
    │   ├── tables.json        # classes, heritages, conditions, feats, vendors…
    │   ├── spells.json  bestiary.json  worlds.json  class_lore.json
    ├── assets/sfx/            # synthesized .wav (regenerate via make_sfx.py)
    └── tests/                 # runnable checks (see TestingChecklist.md)
        ├── self_check.tscn    # unit: rules/tags/combat sim — must stay green
        ├── e2e_stream.tscn    # live: two GM turns, throwaway session
        ├── playthrough.tscn   # live: full 24-system gauntlet
        └── screenshot.tscn    # visual: scene → PNG (MF_SHOT_* env)
```

## Conventions
- New system = new autoload file, registered in `project.godot`, documented
  in Architecture.md. No logic in scene scripts beyond UI orchestration.
- Extracted data changes are made in `godot/data/*.json` (commit them), never
  in the legacy JS.
- Runtime caches live under `user://` (session.cfg, art/) — never in-repo.
- Screenshots/scratch → the session scratchpad, never committed.
```
user://  (per-user, %APPDATA%/Godot/app_userdata/Mythforge)
├── session.cfg   # auth cookie, session map, last adventure, settings
└── art/          # cached generated key art + NPC portraits
```

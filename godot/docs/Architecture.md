# Architecture

## System overview
```
Godot 4.7 client (this repo, godot/)          Windows desktop, GDScript
   │  HTTP + SSE (127.0.0.1:7000)
FastAPI backend (repo root, python)           persistence · LLM · media
   ├── Ollama (:11434)                        narration + extractors + embeddings
   ├── ComfyUI-ZLUDA via bridge (:8101→:8188) SDXL image generation
   └── studio_world_state.json + presets.json durable state (server = truth)
```
The client renders and RESOLVES; the backend stores and GENERATES. The
backend is treated as frozen API surface (changes there need their own
review) — the client adapts to it, not vice versa.

## Client layers (autoload singletons)
| Autoload | File | Owns |
|---|---|---|
| `Ui` | autoload/skin.gd | design tokens, runtime Theme, per-world palettes, reduce-motion |
| `Api` | autoload/api_client.gd | cookie auth, JSON/form calls, **SSE streaming** (raw HTTPClient), image bytes |
| `GameState` | autoload/game_state.gd | character/session, world-state kinds (sheet/inv/clock/…), rests, economy mutations |
| `Rules` | autoload/rules_engine.gd | pure math: dice, checks, AC, XP, items, casting; loads `data/*.json` |
| `Tags` | autoload/tag_parser.gd | the `[[tag]]` protocol parser + prose fallbacks |
| `Composer` | autoload/prompt_composer.gd | per-turn context envelope, GM persona composition, tone directive |
| `Combat` | autoload/combat.gd | initiative, attacks, enemy AI, death saves, victory/XP |
| `Chronicle` | autoload/chronicle.gd | memory beats + recall, codex/quest extractors |
| `Art` | autoload/art_cache.gd | generated key art / portraits, user://art cache |
| `Sfx` | autoload/sfx.gd | synthesized sound effects |

## Scenes
`login.tscn` → `main_menu.tscn` (title / worlds / detail / companions /
settings views) → `game.tscn` (the table: bubbles, panels, combat, dice).
Shared: `ui/backdrop.tscn` (living sky). Harnesses in `tests/`.

## Data flow — one player turn (DM mode)
1. Player text → `Chronicle.recall(msg)` (embedded beat search)
2. `Composer.envelope()` = sheet + clock + pack + spells + recalled beats +
   codex + quests + GM tone directive + MECHANICS PROTOCOL + message
3. `Api.stream_chat` → SSE deltas → bubble (tags stripped live)
4. On done: `Tags.parse` → world tags mutate `GameState` (each mutation
   PUTs its kind to the server) → check tag arms the roll bar
5. Roll → `Rules.resolve_check` → result streams back as the next message
6. `Chronicle.record` stores the exchange as a memory beat

## State model
Server-side world state is per-character-id **kinds**: `sheet, inv, combat,
clock, quests, codex, mem, bmap, gm, world, notes` (+ `_global`: `cworlds,
cstories, rel`). `GameState.save_kind` writes through on every mutation —
there is no client-only state that matters.

## The AI boundary (constitutional)
The model may: narrate, speak NPCs, describe, propose mechanics **via tags**.
The model may not: state numeric outcomes, decide rolls, change state.
Enforcement: the protocol text in every envelope + all mutation paths go
through typed tag handlers + prose-regex fallbacks exist only for
roll-calls and combat-starts (never for state changes without a tag).

## Finite state machine (`Mode`, autoload/state_manager.gd) — M1 ✅
The authoritative game-flow controller. 20 declared states (MainMenu,
Settings, Loading, CharacterCreation, Exploration, Dialogue, Combat, Death,
Victory, GameOver, LevelUp, Merchant, Inventory, CharacterSheet, Crafting,
Camp, LongRest, Travel, Cutscene, Pause), each with an **allowed-action
set** and a **declared transition list**. Every player action passes
`Mode.can(action)`; every mode change goes through `Mode.enter()` (illegal
transitions warn loudly but never hard-lock). `Mode.busy` mirrors streams —
it blocks all actions in any state without changing mode. States without
gameplay yet (Crafting, Travel, Pause…) are declared placeholders per the
no-simplification rule; they gain wiring as their systems land (see
FeatureMatrix). Self-check asserts gating, busy blocking, and that every
declared exit targets a declared state.

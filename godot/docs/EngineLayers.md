# Engine Layers & the game.gd split (A0)

The architecture is sound; this documents the **layer map** (principle #8) and
the **ordered, low-risk strategy** for splitting the `game.gd` god-script
(principle #3). The split is behavior-preserving refactoring — it proceeds one
cohesive extraction at a time, each verified and playtested, never a big-bang.

## 1. The layers (allowed dependency directions)

Dependencies point **downward only**; nothing lower reaches up into a view.

```
   ┌───────────────────────── UI / Views ─────────────────────────┐
   │ scenes/*  ·  ui/myth_*  ·  the play screen & its panels       │
   └───────────────▲───────────────────────────────▲──────────────┘
                   │ reads state, calls services    │ opens
   ┌───────────────┴──────── Gameplay services ─────┴──────────────┐
   │ GameState · Combat · Rules · WorldSkin · Mode(FSM)            │
   └───────────────▲───────────────────────────────▲──────────────┘
                   │                                │
   ┌───────────────┴──── AI ────┐   ┌── Generation ─┴──┐   ┌── Persist ──┐
   │ Composer · Tags · Chronicle │  │ Art → sd.cpp     │   │ GameState   │
   │ LocalGM · LocalMemory       │  │                  │   │ files       │
   └─────────────────────────────┘  └──────────────────┘   └─────────────┘
```

- **Views** may read Gameplay state and call services; services must NOT call
  back into a specific view (use signals, as the extracted windows already do).
- **AI** (Composer/Tags/Chronicle) never mutates gameplay directly — only the
  `[[tag]]` protocol, applied by the engine, changes state. This is the invariant.
- **Generation** (Art) is a leaf service and the only one that opens a socket.

Known upward/cross reaches to unwind over time (tracked, not blocking):
`Rules.attack_mod → GameState.inv` (pass inv explicitly), `Composer →
GameState/Chronicle/Rules` (fine as read-only service calls), and the big one:
`game.gd` does UI **and** gameplay **and** AI orchestration in one ~1.5k-line file.

## 2. The pattern (already proven in this codebase)

Screens are ALREADY separate scene scripts the play screen just opens:
`character_screen.gd` (THE MENU — the pack merged into its Gear tab, retiring
`inventory_window.gd`), `skill_tree.gd`, `lore_book.gd`, `world_map.gd`. Each:
- builds its own UI, reads `GameState`/`Rules`/`Art` directly,
- **emits a signal** for the few actions that must re-enter the play screen
  (e.g. `travel_requested`, `world_created`), which `game.gd` wires on open.

**A0 = keep applying this exact pattern** to the dialog builders still inline in
`game.gd`. No new architecture — the same seam, more of it.

## 3. What's still inline in game.gd (extraction backlog, by coupling)

Lowest coupling first — do them in this order; each is one commit + a playtest.

| Extract → new scene | Lines (approx) | Couples to | Signal(s) back |
|---|---|---|---|
| `_open_shop` → `merchant_window.gd` | ~120 | GameState buy/sell/haggle, Rules stock | `traded(summary)` → GM note |
| `_open_journal` → fold into `lore_book.gd` (Quests/Chronicle already there) | ~90 | Chronicle, chapters | — (retire the inline one) |
| `_open_chronicle` / `_open_atlas` → `lore_book`/`world_map` | ~80 | chapters, world.here | `travel(place)` |
| `_tune_gm` / `_save_chapter` → `gm_panel.gd` | ~70 | gm kind, chapters | `retuned` |
| `_level_up_ceremony` → `levelup_window.gd` | ~110 | Rules level tables, sheet | `chose(choices)` |
| reactions overlay → `reaction_prompt.gd` | ~60 | Combat pending | `chose(kind)` |

**Stays in game.gd** (the play-screen core — the streaming state machine and
its direct view): `_stream`/`_on_delta`/`_flush_stream`/`_on_done`, the language
gate, `_apply_world_tags`/`_apply_presentation_tags`, `_render_combat`/init rail,
the input bar, bubbles, the dice moment. These ARE the play screen; they don't
belong in a sibling window.

Target: `game.gd` shrinks from ~1.5k to ~700–800 lines of genuine play-screen
logic, with each window independently testable via the gallery/screenshot harness.

## 4. Safety rules for each extraction

1. **Behavior-preserving only** — no feature change in the same commit.
2. Move the builder verbatim into a new scene; replace game.gd's method body with
   `instantiate → connect signal → add_child/popup`.
3. Any call the window made to a game.gd helper (`_say_system`, `_stream`, `_bb`)
   becomes a **signal** the window emits and game.gd handles — never a back-reference.
4. Verify: headless import + `self_check` green, then open the window in a live
   run and exercise its actions (buy/sell, travel, level-up) before the next one.
5. One extraction per commit + exe rebuild, so any regression is bisectable.

## 5. Why this is foundational

Every future system (merchant v2, crafting recipes, quest journal, controller
focus per screen) lands in a **window**, not the god-script. Shrinking `game.gd`
to the play-screen core makes each of those a small, isolated, testable scene —
and keeps the streaming/tag core (the part that must stay correct) small and
legible. The split is the enabler for the whole "component-driven gameplay"
direction without an ECS rewrite.

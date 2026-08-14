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
`game.gd` does UI **and** gameplay **and** AI orchestration in one file — **3,062
lines across 106 functions**, measured 2026-08-14.

## 2. The pattern (already proven in this codebase)

Screens are ALREADY separate scene scripts the play screen just opens:
`character_screen.gd` (THE MENU — the pack merged into its Gear tab, retiring
`inventory_window.gd`), `skill_tree.gd`, `lore_book.gd`, `world_map.gd`. Each:
- builds its own UI, reads `GameState`/`Rules`/`Art` directly,
- **emits a signal** for the few actions that must re-enter the play screen
  (e.g. `travel_requested`, `world_created`), which `game.gd` wires on open.

**A0 = keep applying this exact pattern** to the dialog builders still inline in
`game.gd`. No new architecture — the same seam, more of it.

## 3. The extraction backlog — DONE, and it did not shrink the file

**All six rows of the original backlog shipped.** `merchant_window.gd`,
`levelup_window.gd`, `reaction_prompt.gd`, `gm_tuner.gd`, and the folds into
`lore_book.gd` / `world_map.gd` all exist; `_open_shop` and `_level_up_ceremony`
are now exactly the prescribed four lines — instantiate, connect, add_child,
popup. `game.gd` opens ten windows this way.

The seam worked. **The eleven sibling windows total 3,340 lines — more than
`game.gd` itself.** What did not happen is the target: the file was ~1.5k lines
when that plan was written and is **3,062 now**. Extraction moved roughly 600
lines out while the play screen grew by more than twice that.

So the old table is deleted rather than kept. It listed six rows that were all
complete and a target that had been missed by 4×, which reads as a plan when it
is a record — and this project has already thrown away one drifting tracker for
exactly that reason (see [Backlog.md](Backlog.md), the 107-row matrix).

### What is actually inline now (measured 2026-08-14, top of the file by size)

| Function | Lines | Verdict |
|---|---|---|
| `_ready` | ~~215~~ **20** | **split 2026-08-14** — see §3a |
| `_create_hero` | ~~136~~ **57** | **sheet construction moved to `GameState.new_hero_sheet` 2026-08-14** — see §3b |
| `_apply_world_tags` | 123 | **stays** — the tag protocol is the play screen |
| `_on_done` | 98 | **stays** — the streaming state machine |
| `_free_check` | 98 | dice-menu dispatch on magic ids (700–799 recipes, 900/903, 910+) |
| `_on_sheet_action` | 96 | sheet-action dispatch |
| `_render_sheet` / `_render_combat` | 82 / 81 | **stays** — the play screen's direct view |

### 3a. The second seam: a phase list, not a new file

`_ready` was the largest function in the project and the obvious candidate to
extract — but **a cross-file extraction here would have broken this document's
own rule 3.** A `screen_builder.gd` would need to reach back into ~15 member
vars and ~20 private methods of `game.gd`; that is a back-reference, which the
window pattern forbids precisely because it is not a seam, it is a tangle.

So the seam is *inside* the file, and it is about **order**, not location:

```gdscript
func _ready() -> void:
	theme = Ui.theme
	_wire_signals()          # engine + panel signals, and every button on the bar
	_build_chrome()          # the widgets this screen owns: init rail, mood wash
	_open_the_room()         # campaign name, hero in her seat, world music, key art
	if not GameState.is_dm():
		_open_companion_table()   # the boot ENDS here for that persona
		return
	await _open_the_adventure()   # hydrate, party, HUD, and the mode the save left
```

**This is not tidying — it is the fix for a bug class.** PL-4 lived in that
215-line wall: `_open_the_adventure` renders a persisted fight (entering Combat)
and then decided the mode a few lines later, throwing it away. Ten lines apart
in a wall is invisible; two named phases in a list are not.

The split was safe to do verbatim because **no local crosses a section** —
checked before the cut, not after. `self_check` asserts both properties that
make it worth anything: `_ready` stays under 30 lines, and the phases stay in
order (chrome builds what the room paints into). Both mutation-tested — inline
26 lines back into the boot, or swap two phases, and it names which.

The file grew by 40 lines doing this, and that is the honest trade: five
function headers and their docstrings bought a boot sequence you can read.

### 3b. The third seam: pure rules leave the screen entirely

`_create_hero` mixed two jobs. Seventy-nine lines of it were **pure**: ability
priority, heritage bonuses, skill dedup, class features, a caster's first slots —
rules about what a hero *is*, reading `Rules` tables and returning a Dictionary.
The rest is screen work: commit the sheet, hand out the kit, narrate.

The pure half is now `GameState.new_hero_sheet()`. **Not `Rules`** — Rules
reaching into GameState is the upward dependency §1 already wants unwound, and
GameState owns `DEFAULT_SHEET`, so calling Rules from there is the sanctioned
direction. Putting it in Rules would have moved the tangle, not cut it.

**The payoff is a test, not a line count.** Character creation had no direct
check because it lived in a UI script; `self_check` now builds sheets and asserts
the look persists, a level-1 Fighter has features, a Wizard leaves with slots, a
Fighter's best roll goes to STR, and skills are deduped.

**And this is where the greps died.** Three assertions — two in `self_check`, one
in `ui_playthrough` — tested this by searching `game.gd` for `s["sex"]` and
`class_features_upto`. All three went red on a move that changed no behaviour
whatever, which is the tell that they were asserting **where code lived**. They
are behavioural now. The one that stayed a source check is the kit floor, where
the defect genuinely is a call site.

One caution earned here: the first dedup assertion passed with the dedup
**deleted**, because the Dwarf Fighter it used shares no skill with anything.
238 of the table's class/heritage/background combinations collide; it had picked
one of the few that do not. It now uses Fighter+Elf+Soldier — perception from
heritage, athletics from background — and asserts that the case still collides,
so it cannot quietly decay into decoration.

**The window seam is exhausted.** Nothing left is a dialog with its own screen:
what remains is the streaming/tag core the original plan explicitly protected,
two dispatch routers wired to `_stream`/`_say_me`/`_render_sheet`, and a long
`_ready` whose locals become the file's shared state. Shrinking further needs a
**different** seam — a builder for construction, a table for the dispatchers —
and choosing one is an architecture decision, not a mechanical extraction. It is
not scheduled here until someone picks it deliberately.

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

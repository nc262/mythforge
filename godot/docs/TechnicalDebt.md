# Technical Debt

Deliberate shortcuts, each with its ceiling and its upgrade path. Grep
`ponytail:` in sources for the in-code markers.

Paying debt follows the same workflow as a feature: plan → document → land with
a check. A new shortcut adds a row here in the same commit.

| Debt | Where | Ceiling | Upgrade path |
|---|---|---|---|
| `game.gd` is a god-script (~2.8k lines: streaming, tags, combat view, panels) | `scripts/game.gd` | every new system lands in the one file that must stay correct | keep extracting windows — the seam and the order are in [EngineLayers.md](EngineLayers.md) |
| `_streaming` mirrors `Mode.busy` | `scripts/game.gd` | two sources for one fact | delete the alias during the next `game.gd` extraction |
| Mode drift self-heal | `game.gd._can_fight` | combat clicks force-enter Combat when the FSM has drifted; the real bug is hidden, not fixed | declare Combat a legal target from every in-game state |
| `user://tiles` fills for a **player-forged** world | `user://tiles` | a world you forge yourself pours its own terrain — minutes of GPU, and the one art pour a player can still trigger | none available: nobody can pre-bake a world that does not exist yet. The six shipped worlds each carry 272 tiles in the package, so the install itself pours nothing. Deliberately **not** solved by shrinking tiles: see [Terrain.md](Terrain.md) |
| Nothing warns when a bulk generation exceeds the art budget | `art_cache._enforce_budget` | the tile pour queued ~1.3 GB against a 700 MB LRU and churned for hours at net-zero growth, evicting every portrait on the way, silently | log evictions, and refuse a queue whose declared total exceeds the budget rather than thrashing |
| Object tiles carry an opaque dark-grey background | tile bake | a boulder pasted into a snowfield brings its own grey square | composite the object over the cell's ground role at draw time, or key the flat background out at bake time |
| A world package unpacks MISSING files only, never changed ones | `world_compiler._unpack_baked` | a package that **replaces** an asset (rather than adding one) is invisible to anyone who already unpacked that world | deliberate: overwriting would clobber a player's own `Compiler.reforge` output. Adding files works, which covers the normal case. A genuine asset replacement needs a stamp in `world.json` and an explicit re-extract |
| The envelope is rebuilt as strings every turn | `prompt_composer.gd` | fine at today's size; grows with the campaign | the per-section budgeter is already in place — widen it when a section outgrows its cap |
| Regenerating the opening video takes ~35 min/clip | `scripts/make_opening_video.py` | a developer cost only — the video ships pre-built, so no player ever pays it | none needed unless the opening changes |

## Paid, kept for the pattern

- **Terrain sampler was a colour heuristic.** `lay_battlefield()` builds the
  field from roles and the painting follows the field, so there is nothing left
  to misread. See [Terrain.md](Terrain.md).
- **State writes were fire-and-forget with a retry queue.** A save is a file;
  `save_kind` writes it, write-then-rename. The queue existed to survive a
  network that was never there.
- **Both forges duplicated a ~60-line stage scaffold.** `ui/forge_flow.gd` is
  the base; every forge is stage content only.
- **`world_map` carried its own pan/zoom.** It uses the shared `MythCamera`.

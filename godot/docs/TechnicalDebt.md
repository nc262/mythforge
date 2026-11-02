# Technical Debt

Deliberate shortcuts, each with its ceiling and its upgrade path. Grep
`ponytail:` in sources for the in-code markers.

Paying debt follows the same workflow as a feature: plan → document → land with
a check. A new shortcut adds a row here in the same commit.

| Debt | Where | Ceiling | Upgrade path |
|---|---|---|---|
| `game.gd` is a god-script (**3,062 lines, 106 functions** — streaming, tags, combat view, panels) | `scripts/game.gd` | every new system lands in the one file that must stay correct | **The window seam is spent.** All six rows of [EngineLayers.md](EngineLayers.md)'s backlog shipped — the eleven sibling windows now total 3,340 lines, more than `game.gd` — and the file still grew from ~1.5k to 3,062 against a 700–800 target, because new play-screen code landed here faster than dialogs left. What remains is the streaming/tag core that plan deliberately protected, two dispatch routers, and a 215-line `_ready`. Going further needs a **different** seam (a builder for construction, a table for the dispatchers), which is an architecture choice and is **not scheduled** until someone picks one |
| `user://tiles` fills for a **player-forged** world | `user://tiles` | a world you forge yourself pours its own terrain — minutes of GPU, and the one art pour a player can still trigger | none available: nobody can pre-bake a world that does not exist yet. The six shipped worlds each carry 272 tiles in the package, so the install itself pours nothing. Deliberately **not** solved by shrinking tiles: see [Terrain.md](Terrain.md) |
| A world package unpacks MISSING files only, never changed ones | `world_compiler._unpack_baked` | a package that **replaces** an asset (rather than adding one) is invisible to anyone who already unpacked that world | deliberate: overwriting would clobber a player's own `Compiler.reforge` output. Adding files works, which covers the normal case. A genuine asset replacement needs a stamp in `world.json` and an explicit re-extract |
| The envelope is rebuilt as strings every turn | `prompt_composer.gd` | fine at today's size; grows with the campaign | the per-section budgeter is already in place — widen it when a section outgrows its cap |
| Regenerating the opening video takes ~35 min/clip | `scripts/make_opening_video.py` | a developer cost only — the video ships pre-built, so no player ever pays it | none needed unless the opening changes |

## Paid, kept for the pattern

- **Object tiles carried an opaque dark-grey background.** The row was **stale**
  — the fix had already shipped, as the second of the three problems named in
  `board_paint.gd`'s own header, and nothing here noticed. `_key_background`
  averages the four corners (a single sample picked up grain and left a dark halo
  round one boulder), keys anything within tolerance to transparent, and feathers
  the rim so the object is not a cut-out. Measured on fimbulreach: **boulder
  68.5 %, crates 78.3 % transparent; grass and dirt 0.0 %**.

  What was genuinely missing was a check. `self_check` now asserts **both**
  directions, because "an object tile has some transparency" also passes for a
  keyer that has erased the boulder along with its background — so the ground
  roles are asserted fully opaque in the same breath, and the object is asserted
  not to be *mostly* gone. Mutation-tested by disabling the keying: boulder drops
  68.5 % → 0.0 % and the harness goes red.

- **Terrain sampler was a colour heuristic.** `lay_battlefield()` builds the
  field from roles and the painting follows the field, so there is nothing left
  to misread. See [Terrain.md](Terrain.md).
- **State writes were fire-and-forget with a retry queue.** A save is a file;
  `save_kind` writes it, write-then-rename. The queue existed to survive a
  network that was never there.
- **Both forges duplicated a ~60-line stage scaffold.** `ui/forge_flow.gd` is
  the base; every forge is stage content only.
- **`world_map` carried its own pan/zoom.** It uses the shared `MythCamera`.
- **`_streaming` mirrored `Mode.busy`, and the copy had already drifted.** The
  row said "two sources for one fact" and filed it behind a `game.gd`
  extraction. It was not cosmetic: `_leave_to_hall` cleared `_streaming` and
  forgot `Mode.busy`, which is an **autoload** and survives the scene change. So
  leaving to the Hall mid-reply stranded `busy = true` forever, and because
  `Mode.can()` short-circuits on busy, the **next adventure refused every message
  the player typed** — shake, deny, no explanation — until the app was restarted.
  `_streaming` is gone; one flag cannot disagree with itself. `self_check` guards
  both halves: no second flag, and nothing may cancel a stream without clearing
  `Mode.busy`. Both mutation-tested, the second by restoring the original bug.
- **Mode drift into Combat was healed, not fixed.** `_start_combat` never
  touched the FSM at all — entering Combat happened inside `_render_combat`, so
  the state change was a side effect of **drawing**, and the machine's own map
  never described how a fight begins. Dialogue, Merchant, Victory and Camp had no
  Combat exit, so every ambush mid-conversation was an undeclared transition that
  `Mode.enter` warned about and performed anyway.

  Fixed at the cause: `_start_combat` enters Combat itself, and the four states
  declare the exit. The rule is **derived, not listed** — `self_check` walks the
  machine and asserts that any state allowing `send_message` can reach Combat,
  because the GM can answer any message with a fight. A fifth state added later
  fails the day it lands rather than repeating this quietly. `GameOver` is the
  exception and is asserted as one.

  `_can_fight`'s net stays, and now `push_warning`s when it fires. Deleting it
  would trade a silent heal for a silent *failure* — a drifted FSM would make the
  attack button do nothing, with no message, which is the one thing that gate
  exists to prevent.
- **Eviction was completely silent.** `_enforce_budget` deleted paintings and
  printed nothing, which is why R10 ran for *hours* rather than minutes before
  anyone noticed the hero portraits were gone. It now reports every round, and
  names the pathology once a session has evicted more than the entire budget:
  at that point the cache is a treadmill, not a cache. `self_check` asserts the
  LRU order, the counting, the warning, and that a terrain tile still never
  enters the LRU — that last one is the R10 regression guard, and breaking it
  turns the harness red.

  **The proposed "refuse a queue whose declared total exceeds the budget" was
  deliberately not built.** Nothing declares a total: `request()` and `ensure()`
  enqueue one key at a time. Refusing would mean inventing a batch API no caller
  uses and guessing an average painting's weight, then rejecting real work on the
  guess — and turning a slow success into a hard failure. The thrash detector
  needs no estimate, because it counts bytes that were actually thrown away.

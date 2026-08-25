# Invariants

Rules that must hold across the WHOLE repo, each with the check that enforces it.

**Why this file exists.** The codebase carries **147** references to past incidents
(`RCA`, `R6-…`, `PY-…`, `BLANK-…`) and, before this file, **21** structural checks.
The knowledge was written down every time and enforced almost never — so the same
root cause kept reappearing somewhere new, five times in one day:

- `env_resolved` scoped env art keys by world family. `race-`, `item-`, `beast-`
  and `map-` did not, so one world was served another's paintings.
- `item_tex` asked the compiled package before the cache. Five other sites spelled
  that fallback by hand in three different ways, two of them wrong in opposite
  directions.
- `roster_art`'s own comment calls itself *"the fourth appearance of this session's
  root cause"*. The fifth was found the same afternoon.
- The character screen's re-strike reported progress. The forge's copy did not.
- `item_flavor()` already trimmed a style anchor to its medium clause. The world
  backdrop prompt did not, and painted a signboard instead of a fjord.

Every one of those was **already documented at the site of the fix**, and a comment
is only discoverable if you are already reading that file.

## THE RULE THIS FILE IMPOSES

**An RCA comment without a check is unfinished work.** When you write "this cost us
X", you write the assertion in the same commit, and you add the row here. A row
with no check in the Check column belongs in *Not yet enforced* below, where it is
visibly a gap rather than invisibly a comment.

## Enforced

| Invariant | Check | What it cost |
|---|---|---|
| An art key whose PROMPT carries `world_flavor()` must carry the world family in the KEY. Build keys with `Art.race_key`/`item_key`/`beast_key`/`map_key`/`class_key`/`bg_key` — never by hand | `self_check` — *"art key '%s' is reused across worlds"* | A Tiefling painted in Embervale served back in Neonspire. The key was hand-spelled in six places; five drifted |
| A world's key art is asked for with `Art.world_tex()` — the compiled package FIRST, then the cache. Never spell that fallback inline | `self_check` — *"%s spells the key-art fallback by hand"* | Fifth appearance of one root cause. `world_forge` asked the cache only, `adventure_forge` the package only |
| Every world in `worlds.json` must be in `WorldSkin.BUILTIN` | `self_check` — *"shipped world '%s' is not in WorldSkin.BUILTIN"* | saltmarsh fell to the `fantasy` default and wore Embervale's entire art set |
| Generated art is PERMANENT. Nothing deletes a painting to reclaim space | `self_check` — *"_evict is back"* | Nothing regenerates from a sidecar, so eviction was deletion. A banked hero's face is unrecoverable — its source scratch key is overwritten |
| A derived image prompt stays inside SDXL's first 77-token chunk | `self_check` — *"prompt is ~%d tokens — past chunk 0"* | Past chunk 0 text never reaches the POOLED style vector, so worlds drift apart by different amounts |
| A style anchor must not lead with a concrete object noun, and is trimmed to its medium clause for landscapes | `self_check` (token budget) + `Art.world_prompt` comment | Three renders of fimbulreach: `rune-carved wood` got painted as a signboard, twice, before the anchor was trimmed |
| Guard on IN FLIGHT, not on FINISHED, before announcing work | `self_check` — *"_auto_portrait must skip a portrait already in flight"* | "Painting Cael Mercer…" printed twice; `has_art` is only true ~20 s later |
| A long operation must say it is working AND restore itself on failure | `self_check` — *"the re-strike must say it is working"*, *"func _on_quench_progress"* | 25 s of silence reads as failure. A failed paint emits no `art_ready`, so the naive fix hangs the button for the session |
| The narrator warms before the image engine is started | `self_check` — *"the image engine is started BEFORE the narrator warms"* | The engine's first image takes 6.6 GB it never returns |
| Cast art keys (`npc-`, `foe-`) carry the world too — `Art.npc_key()` / `foe_key()`, never by hand | `self_check` — *"builds a cast art key by hand"* | PY-28. Filed as nine sites; it was **fourteen**, and following the rule turned up a SIXTH leaking prefix (`foe-`, whose prompt carries `subject_style("char")`) |
| `--vae-tiling` on every path that LAUNCHES sd-server | `verify.ps1` — *"launches sd-server without --vae-tiling"* | 36.2 s of a 50.4 s image, for a pixel-identical result at the same seed |
| Never paint while the narrator talks — `Art.hold` set around the stream and released on every exit | `self_check` — *"nothing holds the art queue while the narrator streams"* | 3.5 s to 6.1 s per turn. VRAM peaked at 15310/16384, so nothing was evicted: they contend for shaders |
| Godot's RegEx is PCRE2 — a backslash-u escape does not exist there | `self_check` — *"uses a backslash-u escape in a RegEx"* | A pattern compiles clean and then silently matches nothing |
| **Never `call_deferred()` a lambda that captures nodes.** Defer a METHOD and pass the nodes as arguments, so the call site can check them | `pl5_probe` in the gate — dresses five dialogs and frees each in the same frame | PL-5. Nine wrong diagnoses over a year. A deferred lambda is bound to no object, so Godot cannot cancel it when the node dies |
| The Adventure Forge asks for the WORLD before the hero, and publishes it before spawning the child forge | `self_check` — *"the Adventure Forge asks for the hero before the world"* | PY-27. Kit, body and portrait were committed for a world nobody had chosen — the upstream half of PY-21, PY-22 and PY-23 |
| Card prose is cut with `Ui.trim()`, never `.left(N)` — at a word, with an ellipsis | `self_check` — *"truncates card prose with .left()"* | PY-11. "quiet adventu", "stolen blueprt", "answer them i" — the best writing in the game, amputated on four screens |
| Every dialog is dressed with `Ui.dress_dialog()`, and that assigns `theme` — a Window does not inherit one | `self_check` — *"is a dialog that never gets dressed"*, *"dress_dialog does not give the dialog the theme"* | PY-12. Three of five dialogs were never dressed, and the dressed ones still had engine-grey innards |
| A control that paints itself in `_draw()` calls `Ui.repaint_on_skin(self)` — a theme change does not invalidate it | `self_check` — *"paints itself but never repaints on a skin change"* | PY-14. 13 of 14 self-drawn controls never asked: themed widgets went magenta in Neon Spire while the toolbar, sliders and HP bar stayed gold |
| A trailing GM instruction that does NOT move the player carries `GameState.here_pin()`; one that does must not | `self_check` — *"is a stay-put instruction with no location pin"* | PY-7. The GM answered a merchant exchange and an Insight roll by inventing a new place. The pin existed for rest paths only |
| A world family may REPLACE era-locked item forms; universal shapes are shared | `self_check` — *"a cyber world is still offered"* | PY-23. Neon Spire shipped halberds, mail coifs and kite shields and offered no pistol, rifle or deck at all |
| An image prompt DESCRIBES what should be there; it never forbids. And the chart's ground is per family | `self_check` — *"the chart prompt still says"*, *"a megacity and a green valley get the same chart ground"* | PY-26. Every world got "open country", so a vertical megacity was a river valley — and the forbidding prompt produced "a painted city and two misspelled cartouches" |
| A compiled world overlays its accent PAIR, not just the primary | `self_check` — *"the secondary accent is not derived from the world's own"* | PY-14. Neon Spire ran an orange primary from its pack beside a magenta secondary from the palette — two unrelated hues, neither the authored cyan. Found by screenshot, not source |
| Models are matched by NAME, not position | `self_check` + `verify.ps1` | Picking the wrong one fails silently rather than loudly |

## Not yet enforced — these are gaps, not decisions

| Invariant | What it cost | Why there is no check yet |
|---|---|---|
| **Never one model call that both invents and serialises** | Three wrong diagnoses; 95.8 s and a failure vs 1.5 s split in two | A grammar and a sampler chain REPLACE each other in NobodyWho. Hard to assert mechanically; needs a rule about which call sites may pass a schema |
| **Never return silently from a function that was asked to do work** | `request()` returned with no signal when it had no prompt, so half the worlds could never have key art and it looked like it worked | Not mechanically checkable in general; the specific case now pushes a warning |

## Known limits, measured

**Positive description beats forbidding, but does not suppress text.** The chart
prompt used to end "no buildings, no settlements, no text labels"; describing the
ground instead fixed the picture (a megacity renders as a city, verified by
eye) — and the repainted Neon Spire chart STILL carries glowing pseudo-lettering
along a canal. The real route is an endpoint change, not more wording:
`/v1/images/generations` accepts no `negative_prompt` field at all; only
`/sdapi/v1/txt2img` does, and the game already speaks that dialect for img2img
(`art_cache.gd:I2I_PATH`). Read from the sdcpp routes at our pinned commit.

**A prompt fix does not reach a world that ships a BAKED image.** `world_map`
draws `Compiler.chart_art()` — the pack's own `art/chart.png` — and only falls
back to the cache when there is none. That is correct (package before cache, the
rule above) and it means changing a PROMPT changes nothing for a compiled world
until its pack is re-baked. PY-26's city chart was verified in the cache and the
game still drew the baked valley. Check which path a screen actually reads before
believing a prompt fix landed.

## This file is CHECKED against reality

Rows go stale. Three of these did, within an hour of the file being written — they
sat in "Not yet enforced" while their checks were being committed the same
session. That is exactly the "looks like information" failure that got a 107-row
feature matrix deleted from this repo.

So `self_check` parses this file: **every check name quoted in the Enforced table
must actually exist** in `tests/self_check.gd` or `scripts/verify.ps1`. A row that
claims a check it does not have turns the gate red, so adding a row is not free —
the check comes first.

*It cannot verify the reverse:* that a rule under "Not yet enforced" really has no
check. Moving a row up when you write its check is still a human step, and it is
the step that failed within the hour.

## PL-5 — SOLVED 2026-08-24, and how

Nine wrong diagnoses over a year, four more disproven in one day. It was never a
leaked signal connection. It was **the only deferred lambda in the codebase**:
`skin.gd:_cap_panel_content` ended with `apply.call_deferred()`, and `apply`
captured `dlg` and `content` — the index-0/index-1 PAIR every report described.
Free the dialog before the next idle and both captures are dead when Godot
rebinds them.

**Why nine people looked straight at it and saw nothing.** `apply` opens with
`if not is_instance_valid(dlg) or not is_instance_valid(content): return`. That
guard reads as correct and is useless here: Godot validates captures when the
Callable is INVOKED, before any body runs. A guard inside the lambda can never
prevent this error. The fix had to move to the call site, into a method taking
the nodes as ARGUMENTS — arguments are checkable, captures are not.

**What found it, after four theories that could not:** elimination by
measurement, in this order.

1. Count every autoload signal's connections at the start and end of a
   playthrough. **None grew** — so the whole "an unowned lambda stays connected
   and later fires" family is false, not merely unproven.
2. Add the root `Window`, which outlives every scene and is not an autoload.
   **Still none.**
3. Therefore the lambda is invoked by something that is NOT a connection.
   `grep` for deferred lambdas returned exactly one line.
4. Build the scenario on purpose: dress five dialogs, free each in the frame it
   was dressed. **10 errors, 10/10 runs, indices alternating 0,1** — the first
   deterministic reproduction in the bug's life. Zero after the fix.

**The lesson worth more than the fix.** Every earlier attempt, mine included,
proposed a mechanism and then looked for agreement. Twenty-plus clean runs were
read as evidence on both sides of every theory. What worked was ruling mechanisms
OUT with a census that could not lie, until only one candidate remained — and
then making it fail on demand before fixing it.

`pl5_probe` stays in the gate. It exists to fail.


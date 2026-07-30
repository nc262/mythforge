# Known Issues

Rows are deleted only after the fix ships **and** a harness covers the
regression. Player-facing bugs live in [Backlog.md](Backlog.md); this file is
for the ones that are structural, accepted, or upstream.

| # | Issue | Impact | Workaround | Fix plan |
|---|---|---|---|---|
| 1 | `Rules.attack_mod` couples to `GameState.inv()` when `inv` is omitted at a call site | a subtly wrong bonus if a caller forgets | pass `inv` everywhere (done at every known site) | a typed context object when `game.gd` is next split |
| 2 | Harness screenshots need a windowed run — headless cannot render | no visual diffs in CI | the local screenshot harness | accepted; CI was never going to have a GPU |
| 3 | Godot 4.7 prints benign RID/StringName leak noise at headless shutdown | log noise only | grep-filtered in the harnesses | upstream |
| 4 | The Pack's leather surface reads flat at a glance — the stitch detail is subtle at 1× | polish gap against the other rituals | — | a material refinement pass |
| 5 | Tale and world are coupled — you cannot pick a tale and then choose its world | a requested flow is missing | Free Roam lets you pick any world | a design decision: world-agnostic tales that the GM re-skins, vs an explicit two-step world→tale |
| 6 | The `everyday` baked world is sparse — 2 weapon forms → 30 items, 6 icons | thin loot in that one world | acceptable for a modern setting | `Compiler.reforge` its assets, or hand-author more `weapon_forms` |
| 7 | A cold forge is still a real minute — six sequential model calls, ~57 s measured | slow world creation on first play | play a pre-baked world (instant) | hardware-bound; see [Performance.md](Performance.md) |

## Kept for the pattern, not for the bug

**Controls do not clip `_draw` by default.** The battle-board's cover-fit
underlay painted outside its own rect and flooded the chat column — which read
as "the map replaced the text". Any cover-fit painter needs
`clip_contents = true`, and the screenshot harness catches it now. The same
missing flag was later the "random grey rectangle" over the minimap.

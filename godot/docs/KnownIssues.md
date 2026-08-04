# Known Issues

**Limitations that will not be fixed, and why.** Anything that *could* be worked
on lives in [Backlog.md](Backlog.md); deliberate shortcuts with an upgrade path
live in [TechnicalDebt.md](TechnicalDebt.md). This page exists so those two do
not slowly fill with things nobody intends to do.

| # | Issue | Why it stays |
|---|---|---|
| 1 | Harness screenshots need a windowed run — headless cannot render | CI was never going to have a GPU. The local screenshot harness covers it, and `--mf-worlds` covers the one export failure that mattered |
| 2 | Godot 4.7 prints benign RID/StringName leak noise at headless shutdown | Upstream, cosmetic, grep-filtered in the harnesses |
| 3 | A cold forge is a real minute — six sequential model calls, ~57 s measured | Hardware-bound. Play a pre-baked world for an instant start; see [Performance.md](Performance.md) |
| 4 | The Pack's leather surface reads flat at 1× — the stitch detail is subtle | Polish against a bar the other rituals set. Real, and not worth a pass on its own |
| 5 | The model can be asked for a shape it will not draw | Prompt fidelity has a ceiling. Item icons name their silhouette (`Rules.shape_clause`) and drop the atmosphere clause, which is as far as prompting goes — the rest needs a different image engine |
| 6 | No scale bar on the Atlas | Locations are percentages of a painted chart, not positions on ground. A scale would be a drawn lie |
| 7 | Flanking is not implemented | An optional 5e rule that makes positioning strictly worse for a solo player with engine-moved companions, and that every table argues about. Not an oversight |

## Kept for the pattern, not for the bug

**Controls do not clip `_draw` by default.** The battle board's cover-fit
underlay painted outside its own rect and flooded the chat column — which read
as "the map replaced the text". Any cover-fit painter needs
`clip_contents = true`. The same missing flag later produced the "random grey
rectangle" over the minimap. The screenshot harness catches it now.

**A `ScrollContainer` sizes its child to the child's minimum.** So
`ALIGNMENT_CENTER` on a page inside one does nothing, and any layout fix that
assumes spare vertical space is a no-op that looks like a change.

**`Button` never consults a script's `_get_minimum_size()`.** Its native
implementation wins, so a `class_name X extends Button` that overrides the
virtual has written dead code. Set `custom_minimum_size` instead.

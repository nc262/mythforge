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
| 5 | **Size within a category cannot be drawn.** A short sword comes back a sword | Measured 2026-08-04, not assumed. An icon is one object on an empty background, so there is no forearm in frame and no sword to be shorter than — there is nothing to measure against. Three clauses were rendered for "Shortblade": the relative one, "a gladius: a short broad stabbing sword", and "a wakizashi". All three returned a full-length sword; the last returned two. Category shapes DO work (axe, bow, shield, bottle, ring — 6 of 8 correct), so `Rules.shape_clause` now names only those. A LoRA might fix it, at multi-GB of download, for a distinction ~20 px wide in a socket |
| 6 | No scale bar on the Atlas | Locations are percentages of a painted chart, not positions on ground. A scale would be a drawn lie |
| 7 | Flanking is not implemented | An optional 5e rule that makes positioning strictly worse for a solo player with engine-moved companions, and that every table argues about. Not an oversight |
| 8 | The chart plate still paints faint decorative text on some worlds | Same ceiling as #5, and measured: "no text labels" produced text on **three of six** worlds, twice misspelled (`FIMBULACH`, `BRASHEVEN`). Negative instructions inside a positive prompt do not work. Positive framing ("pristine untouched wilderness, ages before anyone settled it") plus a 13 % margin crop killed the painted **city**, the frames and the corner cartouches — the parts that actually contradicted the pins. What is left is small, low-contrast and reads as cartographic character. Prompting further does not converge |
| 9 | The installer is unsigned, so SmartScreen warns | An OV certificate is a few hundred dollars a year against no revenue. Documented instead: the [README](../../README.md#install--play) tells a player to click **More info → Run anyway**, and says why. Self-signing is not a cheaper version of this — it earns no SmartScreen reputation, so it changes nothing a player sees |

## Kept for the pattern, not for the bug

**Controls do not clip `_draw` by default.** The battle board's cover-fit
underlay painted outside its own rect and flooded the chat column — which read
as "the map replaced the text". Any cover-fit painter needs
`clip_contents = true`. The same missing flag later produced the "random grey
rectangle" over the minimap. The screenshot harness catches it now.

**A `ScrollContainer` sizes its child to the child's minimum.** So
`ALIGNMENT_CENTER` on a page inside one does nothing, and any layout fix that
assumes spare vertical space is a no-op that looks like a change.

**A negative instruction inside a positive prompt does not work.** "no text
labels" produced text on three of six charts, twice misspelled; "no buildings,
no settlements" produced a whole painted city. What works is describing the
thing you want as a positive subject ("pristine untouched wilderness, ages
before anyone settled it") and then removing the rest deterministically — a
crop, a mask — rather than asking the model to withhold it.

**A modifier that matches before the noun shadows it.** `Rules.shape_clause`
scanned its list in order, so `Shortbow` matched "short" and was described as a
blade. A lookup table keyed on substrings has an implicit priority, and it is
list order — which is invisible at the call site and looks like nothing at all.

**A child that fills leaves nothing to centre.** A glyph-led system line put an
`EXPAND_FILL` Label beside its icon in an `ALIGNMENT_CENTER` HBox — so the label
ate the row, its text centred in the middle, and the glyph stranded at the far
edge. The code reads as though the pair is centred. `SHRINK` is not the fix
either: an autowrapped Label's minimum width is its longest **word**, so the text
collapses to a column. Give it an explicit width and left-align inside it.

**`Button` never consults a script's `_get_minimum_size()`.** Its native
implementation wins, so a `class_name X extends Button` that overrides the
virtual has written dead code. Set `custom_minimum_size` instead.

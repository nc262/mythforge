# Backlog

What is actually open, and why. Resolved work is not kept here — the code is the
record of what shipped. Priority **P1** (blocks play) → **P4** (nice to have);
effort **S/M/L**.

## Nothing is open.

Every reported defect — P1 through P4 — was audited against the code, fixed, and
left a check behind that FAILS if it returns. Each was verified by reverting the
fix and watching the check fail. Nothing here was marked done on inspection.

**Four of them were mis-reported**, and the only reason that was caught is that
they were *rendered* rather than reasoned about:

| Filed as | Actually |
|---|---|
| "Skills/Powers/Story leave ~700 px empty" | A horizontal problem — centred headers at x=820 over left-aligned text at x=400. Vertical centring is a no-op in a ScrollContainer and would have been wrong anyway. |
| "a Shortblade drawn as a cruciform arming sword" | The shipped prompt drew **a lit candle on a hilt** — `world_flavor()` ends in "candlelit" and at 512 px the atmosphere clause becomes the subject. The filed bug was the second, smaller half. |
| "Time divider printed for the first long rest only" | The divider only ever came from the `[[time]]` **tag**, so it appeared when the GM remembered. Rests move the clock inside the engine and printed nothing. |
| "The Atlas is decoration — no names, legend, compass" | It has all three. What it *didn't* have was distinguishable pins: two pairs of kinds shared a colour, and gold/ember are 0.165 apart — yellow beside orange at 8 px. |

The last one was **my own regression**, introduced two commits earlier and passed
by my own check, which asserted every kind *had* a colour rather than that the
colours *differed*. Kinds now carry a shape as well as a colour, which also
survives being printed, dimmed, or seen by someone who won't agree about the
orange one.

## The Atlas — what's left is enhancement, not defect

The map has names, a legend, a compass, roads, fog, quest pull, click-to-travel
and a real painted chart. These would make it better; none is broken:

| # | Item | P | E |
|---|---|---|---|
| AT-2 | Roads are inferred (a spanning tree over known places), not authored. Real edges would let a road be blocked, dangerous, or seasonal | P4 | M |
| AT-3 | No region zoom — the chart cannot go realm → city → street | P4 | L |
| AT-4 | Chart art is generated from place *names*, so the painting and the pin positions are two independent inventions | P4 | L |

**No scale bar, deliberately.** Locations are percentages of a painted chart, not
positions on ground. A scale would be a drawn lie.

## Presentation and copy

Empty. Both remaining items were settled by looking rather than reasoning —
screenshots for the layout, generated icons for the art — and the screenshots
disagreed with the report in ways that changed the fix. Notes kept because the
method is the point:

**UI-5 was not an empty-space problem.** Centring the pages vertically is a
no-op (a ScrollContainer sizes its child to the child's minimum, so there is no
spare height to centre within) and would have been wrong anyway — a page of a
book starts at the top. What actually read as broken was horizontal: a centred
`MythHeader` at x=820 over left-aligned body text at x=400, so the heading
floated free of the thing it was heading. A 620 px reading column fixed it.

**UI-7 was two defects, and the reported one was the smaller.** Measured against
the real engine: the shipped prompt drew *a lit candle mounted on a hilt*,
because `world_flavor()` ends in "candlelit" and on a 512 px icon the atmosphere
clause becomes the SUBJECT. Removing it produced a blade — with the wrong
silhouette, which is the bug as filed. Both halves were needed.

## Not built

- **TTS narration.** Client wiring exists; there is no local voice engine in the
  stack. It needs one chosen and shipped, the same way the narrator and whisper
  were.
- **A true 3D character** (CharacterRender.md, Stage C). Paused on an
  asset-sourcing decision: commissioned, generated, or a bought pack.
- **A first-run tutorial.** There is a how-to card; there is no guided first
  session. The forge ritual carries the weight of teaching today, which works
  for making a hero and not at all for the first check the GM calls for.
- **World Skin palette from the model.** Families are deterministic today; the
  Worldsmith could emit palette hexes and merge them through the contrast clamp
  that is already in place.

## Deliberately skipped

**Flanking.** It is an optional 5e rule, it makes positioning strictly worse for
a solo player with companions the engine moves, and every table that uses it
argues about it. Not an oversight.

## Parked (FutureIdeas)

Relationship/reputation web · engine-verified quest objectives · world-sim depth
(NPC goals, seasons, festivals) · camp mode with banter · animated 3D dice ·
cinematic finale slideshow + stats · photo/share mode · Steam achievements and
Workshop · co-op party with voice.

## What has never been tested

A coverage gap, not a clean bill of health: spells in play (needs a caster
played through), merchants (never met one in a real session), the Lore Book
filling over a long campaign, equip/unequip with a real inventory, and the tone
knobs at their extremes.

## The method note worth keeping

The sharpest lesson this project has produced: the character-sheet tab rail
drew correctly, screenshotted beautifully and passed every visual audit — while
four of its nine buttons were reported unclickable. The harnesses assert screens
are *reachable*; audits assert they *look right*. Neither asserted that a drawn
control is **clickable** or an offered action is **legal**. `click_driver` now
asks what a mouse asks — which control is topmost at this point — because that
blind spot is where the expensive bugs live.

Its sibling: a metric that scores broken output as fine is worse than no metric.
Assert what the *failure* looks like, not what a good answer looks like.

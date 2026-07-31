# Backlog

What is actually open, and why. Resolved work is not kept here — the code is the
record of what shipped. Priority **P1** (blocks play) → **P4** (nice to have);
effort **S/M/L**.

## Play systems — gaps a player runs into

| # | Item | P | E |
|---|---|---|---|
| PS-4 | Each long rest costs a full dawn-to-dawn day; no way to rest without losing one | P4 | M |
| PS-5 | Time divider printed for the first long rest only | P4 | S |

Audited against the code 2026-07-30/31, high priority first. Every P1 (identity,
rest-place continuity, invented consequences, the frozen backdrop), the three P2
play-system gaps (level-1 class features, the starting-kit floor, the kit the
Quenching promises) and nine of the eleven presentation items were confirmed
still present, fixed, and each left a check behind that FAILS if the defect
returns — verified by reverting each fix and watching it fail. See
`_check_one_identity`, `_check_rest_place`, `_check_scene_follows_mood`,
`_check_forge_grants_features`, `_check_refusals_land_near_the_button` and the
envelope/mood/feature/kit/tag assertions in `self_check`.

## The Atlas

| # | Item | P | E |
|---|---|---|---|
| AT-1 | **The Atlas is decoration, not a map** — no names, legend, compass, scale, roads or POIs; one unlabelled dot, and a fjord drawn as scattered lakes | P2 | L |

Not attempted. "Make it a real map" is a design question before it is a code
one, and it deserves its own session rather than a guess appended to a sweep.

## Presentation and copy

| # | Item | P | E |
|---|---|---|---|
| UI-5 | Skills / Powers / Story leave ~700 px empty below a cramped top block | P3 | S |
| UI-7 | Item icon contradicts the item — a "Shortblade" drawn as a cruciform arming sword | P3 | S |

**These two need eyes, not a guess.** Skills is already a two-column grid, so
the "cramped block" is not the layout defect the report implies — the empty
space is short content in a tall panel, and what to put there is a design call.
UI-7 is prompt fidelity: the compiled catalogue path already passes each form's
own shape words, so the mismatch belongs to the legacy per-name icon path, and
"make the model draw a short blade" is not something to fake a fix for. Both
want a screenshot and a decision.

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

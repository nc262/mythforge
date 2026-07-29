# Playtest R11 — the baked board, played

First real-exe run of the R10 terrain work. Saltmarsh Reach, Free Roam, Corin
Vale (Human Fighter, banked), Adventurer difficulty, replies set to Brief.

## R10 worked

The board draws its tiles from the world package and **the mechanics match the
paint**. Every green patch carries a cover dot; every dark square carries the
impassable hatch; they are the same squares. The complaint that opened this
work — *"random terrain red squares that do not coordinate at all with the
underlying images"* — is gone, because the overlay and the ground are now the
same data instead of two guesses about a stretched painting.

Saltmarsh's open ground rendered as `dirt`, confirming the world-id and
open-ground fixes in play.

## R11-01 — the GM adjudicates fights, not the engine (P0)

**This is the root cause of R9-01, and it is much larger than a missing guard.**

Observed, in order, with both combatants unmoved at opposite ends of the board
(col 2 vs col 13 — eleven squares, 55 ft):

| | |
|---|---|
| `*attack roll* → d20 17 +5 = 22 — hit! (AC 14)` | melee, at 55 ft |
| `*attack roll* → d20 20 +5 = 25 — critical hit!` | **natural 20 crit** |
| Samuel Jenkins | **17/17 — untouched** |
| the action-bar `attack` link | still offered, never spent |

The engine's `Combat.player_attack()` is correct: it checks reach before
spending the budget, rolls against AC, applies damage, doubles crit dice. It is
simply **not the code that runs**. The GM narrates "make an attack roll", and
`tag_parser._atk_re` — `(attack roll|roll to hit|make an attack|roll an
attack)` — turns that into a **generic check**. A check has no concept of
reach, no target, no AC, no damage and no action economy. It rolls a d20 and
prints it.

So the fight is theatre: the dice are real and nothing they say is applied.

The R9-01 guard I added to `player_attack()` is genuinely there and genuinely
correct — `self_check` proves it every run. It never fires in play because
nothing reaches it. Fixing the guard again would change nothing; the tag path
has to stop resolving attacks, and combat has to route to the engine.

This is precisely the split the Director asked for: *"all these mechanics
should be built in to the engine not based on the gm — the gm should only be
story dialogue."*

## R11-02 — the grid draws 5-ft squares as 2:1 rectangles (P1)

Measured on screen: cells are ~75 x 40 px. Every tile is stretched to double
width, and a grid whose distance rule is Chebyshev is being drawn in a shape
where a diagonal step is not the same length as an orthogonal one. The art was
baked square; the board should draw it square.

## R11-03 — the board is clipped, and the minimap sits on top of it (P1)

The bottom row(s) fall behind the composer. The minimap overlaps both the board
and the action bar — `End turn ›` renders as `nd turn ›` and the HP readouts
are half-hidden behind it. R9-05 confirmed and worse than logged: it covers
controls, not just text.

## R11-04 — terrain patches have hard rectangular edges (P2)

Undergrowth reads as a sharp green rectangle dropped on the dirt, with no
transition. Mechanically correct, visually pasted. Related to the opaque
backgrounds already filed for object tiles.

## Confirmed on sight, already logged

| id | note |
|---|---|
| R9-08 | `destiny: 15.0, 14.0, 13.0, 10.0, 10.0, 9.0` — floats |
| R9-10 | a banked hero still routes through The Quenching |
| R9-12 | the Party stage is one toggle; all four Difficulty cards share the sword glyph |
| R9-09 | House Rules placeholder clipped mid-word: `(or leave the table's r` |
| R9-07 | no CONTINUE on the title — the save still is not written |
| R8-27 | opening turn ~135 s **with replies set to Brief** |

## New, small

- **The Preview never names the world.** It lists tale, hero and difficulty, but
  a player choosing Saltmarsh Reach is never shown it.
- **All three tales share the Free Roam subtitle** — "wander it as you please"
  appears under The Tide-Debt and What the Nets Dragged Up too.
- **The hero roster shows flag glyphs where portraits belong** — fallout of the
  art-cache eviction; the portrait regenerated as a different face at The
  Quenching, as predicted.

# Backlog

What is actually open, and why. Resolved work is not kept here — the code is the
record of what shipped. Priority **P1** (blocks play) → **P4** (nice to have);
effort **S/M/L**.

## Identity — one hero, three different faces

| # | Item | P | E |
|---|---|---|---|
| ID-1 | **The portrait and the paper doll are different people.** The round portrait and the full-body doll are separate diffusion renders with no shared seed or identity anchor, so the hero's face changes between two views of the same character | P1 | L |

The habit behind it is deriving the likeness at the point of use instead of
carrying one identity. Every future render of a character has to hang off one
anchor, or this comes back per surface.

## Continuity — the GM forgets where you are and what happened

| # | Item | P | E |
|---|---|---|---|
| CN-1 | **Location breaks across a long rest** — camped at the barrow-mound, woke in the mead-hall guest room with no travel between them | P1 | M |
| CN-2 | **The GM invents consequences that never happened** ("vitality lost in battle", no battle fought) | P2 | M |
| CN-3 | **Sleeping somewhere hostile has no consequence** — two rests in an opened barrow with a hostile figure watching, nothing happened | P2 | M |
| CN-4 | **The scene backdrop never changes** — one plate across four days, three weather states and four locations | P2 | M |

## Play systems — gaps a player runs into

| # | Item | P | E |
|---|---|---|---|
| PS-1 | A level-1 Fighter has **no class features** — Powers shows only the heritage trait, mislabelled as a class feature and duplicated on Story | P2 | M |
| PS-2 | **Starting equipment is one weapon** — no armour, shield, pack or rations | P2 | M |
| PS-3 | Equipped weapon contradicts the kit — Quenching said Longsword, combat swung a Korvul Black Iron Hammer | P2 | S |
| PS-4 | Each long rest costs a full dawn-to-dawn day; no way to rest without losing one | P4 | M |
| PS-5 | Time divider printed for the first long rest only | P4 | S |

## The Atlas

| # | Item | P | E |
|---|---|---|---|
| AT-1 | **The Atlas is decoration, not a map** — no names, legend, compass, scale, roads or POIs; one unlabelled dot, and a fjord drawn as scattered lakes | P2 | L |

## Presentation and copy

| # | Item | P | E |
|---|---|---|---|
| UI-1 | Raw parser tags leak into prose — `[[Perception`, `[Active Perception]` rendered verbatim | P2 | S |
| UI-2 | Destiny labels overlap their nodes; four nodes all named "Gift of Growth" | P2 | S |
| UI-3 | Forge card text clipped in three places | P2 | S |
| UI-4 | Choosing a banked hero still routes through The Quenching — a forge step where nothing is forged | P2 | S |
| UI-5 | Skills / Powers / Story leave ~700 px empty below a cramped top block | P3 | S |
| UI-6 | Item context menu spawns clipped at the window edge and does not flip | P3 | S |
| UI-7 | Item icon contradicts the item — a "Shortblade" drawn as a cruciform arming sword | P3 | S |
| UI-8 | The "choose a world" hint prints ~250 px below the button that refused | P3 | S |
| UI-9 | The Party stage is one toggle on a full screen; all four Difficulty cards use the same sword glyph | P3 | S |
| UI-10 | Quenching summary line is low-contrast grey over bright forge art | P3 | S |
| UI-11 | `MythPortrait` has no empty state — an empty ring while unpainted | P3 | S |

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

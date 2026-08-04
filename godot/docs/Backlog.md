# Backlog

**The single list of open work.** If something could be worked on, it is here.
Resolved work is not kept — the code is the record of what shipped.

Three neighbours, so nothing has two homes:

- [KnownIssues.md](KnownIssues.md) — limitations that will **not** be fixed, and why.
- [TechnicalDebt.md](TechnicalDebt.md) — deliberate shortcuts, each with its ceiling.
- [Testing.md](Testing.md) — what the harnesses can and cannot prove, including coverage gaps.

Priority **P1** (blocks play) → **P4** (nice to have); effort **S/M/L**.

---

## Play and correctness

| # | Item | P | E |
|---|---|---|---|
| PL-1 | **Tale and world are coupled** — you cannot pick a tale and then choose its world. Free Roam lets you pick any world, so the flow exists but not the order players expect. Needs a design call: world-agnostic tales the GM re-skins, vs an explicit two-step world→tale | P2 | M |
| PL-2 | `Rules.attack_mod` falls back to `GameState.inv()` when a caller omits `inv`. Every known call site passes it, so this is latent rather than live — but a future caller that forgets gets a subtly wrong bonus and no error | P3 | S |
| PL-3 | The `everyday` world is content-thin — 2 weapon forms yield 30 items and 6 icons. Fine-ish for a modern setting, poor next to its siblings. `Compiler.reforge` its assets, or hand-author more `weapon_forms` | P3 | M |

## The Atlas

The map has names, a legend with distinct marks, a compass, roads, fog, quest
pull, click-to-travel and a painted chart. What follows would make it better;
none of it is broken.

| # | Item | P | E |
|---|---|---|---|
| AT-2 | Roads are **inferred** (a spanning tree over known places), not authored. Real edges would let a road be blocked, dangerous, or seasonal | P4 | M |
| AT-3 | No region zoom — the chart cannot go realm → city → street | P4 | L |
| AT-4 | Chart art is generated from place **names**, so the painting and the pin positions are two independent inventions | P4 | L |

**No scale bar, deliberately.** Locations are percentages of a painted chart,
not positions on ground. A scale would be a drawn lie.

## Distribution

| # | Item | P | E |
|---|---|---|---|
| DI-1 | **The installer has never run on a clean machine.** The biggest risk in the download, and not something the harnesses can reach | P2 | M |
| DI-2 | `Mythforge-Setup.iss` has never been compiled — needs Inno Setup 6 | P3 | S |
| DI-3 | The tile library is ~1.3 GB generated per install. A release either ships it or makes every player pour it. Upgrade: bake it into a world package at release time (see [Terrain.md](Terrain.md) for why shrinking tiles is the wrong answer) | P3 | L |
| DI-4 | An unsigned installer trips SmartScreen. Code-sign it, or document the "More info → Run anyway" click | P4 | S |

## Not built

Each with the reason it is not merely undone:

- **TTS narration.** The client wiring exists; there is no local voice engine in
  the stack. It needs one chosen and shipped the way the narrator and whisper
  were — speech goes in today, nothing comes out.
- **A true 3D character** ([CharacterRender.md](CharacterRender.md), Stage C).
  Paused on an asset-sourcing decision: commissioned, generated, or a bought
  pack. `spike3d/` holds the experiments; nothing in the shipped path uses them.
- **A first-run tutorial.** There is a how-to card. The forge ritual carries the
  teaching today, which works for making a hero and not at all for the first
  check the GM calls for.
- **World Skin palette from the model.** Families are deterministic; the
  Worldsmith could emit palette hexes and merge them through the contrast clamp
  that already exists.
- **Co-op.** No networking design exists, and the local-first architecture is
  not obviously compatible with one.

## Parked

Relationship/reputation web · engine-verified quest objectives · world-sim depth
(NPC goals, seasons, festivals) · camp mode with banter · animated 3D dice ·
cinematic finale slideshow · photo/share mode · Steam achievements and Workshop.

---

## The audit that emptied this list

Every reported defect — P1 through P4 — was audited against the code between
2026-07-30 and 2026-08-04, fixed, and left a check that FAILS if it returns.
Each was verified by reverting the fix and watching the check fail. Nothing was
marked done on inspection.

**Five were mis-reported**, and the only reason that was caught is that they
were *rendered* rather than reasoned about:

| Filed as | Actually |
|---|---|
| "Skills/Powers/Story leave ~700 px empty" | A horizontal problem — centred headers at x=820 over left-aligned text at x=400. Vertical centring is a no-op in a ScrollContainer and would have been wrong anyway. |
| "a Shortblade drawn as a cruciform arming sword" | The shipped prompt drew **a lit candle on a hilt** — `world_flavor()` ends in "candlelit", and at 512 px the atmosphere clause becomes the subject. The filed bug was the smaller half. |
| "Time divider on the first long rest only" | The divider only ever came from the `[[time]]` **tag**, so it appeared when the GM remembered. Rests move the clock inside the engine and printed nothing. |
| "The Atlas is decoration — no names, legend, compass" | It had all three. What it lacked was distinguishable pins — and that was a regression introduced during this very audit. |
| "Two front-ends, 9% of the repo is the game" | True at the time, and the workspace it measured is gone. |

## The method notes worth keeping

**Assert what the failure looks like, not what a good answer looks like.** A
metric that scores broken output as fine is worse than no metric. Three did:
a vocabulary score rated three identical sunset openings 19 % "OK"; a word
splitter dropped words under four characters so "air" never reached the
atmosphere detector; a sanity check accepted `#:7A288A` as a material.

**A test that cannot tell whether the feature is plugged in is not testing the
feature.** The GM-model check re-implemented its ranking inline and passed for
weeks while the picker wrote to a key nothing read. The Atlas colour check
asserted every kind *had* a colour, never that the colours *differed* — and let
two duplicated pairs through.

**Render it.** Five of the last dozen fixes changed shape once the thing was
screenshotted or generated. Reading the code told the wrong story every time.

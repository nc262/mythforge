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

Empty. All three items were audited on 2026-08-04 and none survived — see the
mis-reported table below. `Rules.attack_mod` now requires its `inv` argument, so
a caller that forgets it fails to compile rather than silently returning the
unarmed number.

## The Atlas

The map has names, a legend with distinct marks, a compass, fog, quest pull,
click-to-travel, a painted chart, and **named roads that change what travel
costs** (AT-2, done 2026-08-04). What follows would make it better; none of it
is broken.

| # | Item | P | E |
|---|---|---|---|
| AT-3 | No region zoom — the chart cannot go realm → city → street | P4 | L |

**No scale bar, deliberately.** Locations are percentages of a painted chart,
not positions on ground. A scale would be a drawn lie.

**The chart plate is ground, not a map** (AT-4, done 2026-08-04). It paints
terrain, water and coast and nothing that claims a position — so the engine's
pins and named roads are the only statement about where anything is, and the
paper cannot disagree with them. Asking the model for a *layout* was never the
answer: a spatial arrangement is strictly harder than a silhouette, and
[KnownIssues](KnownIssues.md) #5 already records how that ends.

## Distribution

| # | Item | P | E |
|---|---|---|---|
| DI-1 | **`bootstrap.ps1` has never run on a clean machine** — ~10 GB of downloads, GPU detection, three models and the image engine. Narrowed on 2026-08-04: the *installer* is now proven (compile → silent install → uninstall, no residue), so what is left is specifically the first-run fetch. Still the biggest risk in the download, and still not something the harnesses can reach | P2 | M |

## Not built

Each with the reason it is not merely undone:

- **TTS narration.** The client wiring exists; there is no local voice engine in
  the stack. It needs one chosen and shipped the way the narrator and whisper
  were — speech goes in today, nothing comes out.
- **A true 3D character** ([CharacterRender.md](CharacterRender.md), Stage C).
  Paused on an asset-sourcing decision: commissioned, generated, or a bought
  pack. `spike3d/` holds the experiments; nothing in the shipped path uses them.
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

**Eight were mis-reported**, and the only reason that was caught is that they
were *rendered or measured* rather than reasoned about. The whole Play section
was stale: all three of its rows described code that had already changed.

| Filed as | Actually |
|---|---|
| "Skills/Powers/Story leave ~700 px empty" | A horizontal problem — centred headers at x=820 over left-aligned text at x=400. Vertical centring is a no-op in a ScrollContainer and would have been wrong anyway. |
| "a Shortblade drawn as a cruciform arming sword" | The shipped prompt drew **a lit candle on a hilt** — `world_flavor()` ends in "candlelit", and at 512 px the atmosphere clause becomes the subject. The filed bug was the smaller half. |
| "Time divider on the first long rest only" | The divider only ever came from the `[[time]]` **tag**, so it appeared when the GM remembered. Rests move the clock inside the engine and printed nothing. |
| "The Atlas is decoration — no names, legend, compass" | It had all three. What it lacked was distinguishable pins — and that was a regression introduced during this very audit. |
| "Two front-ends, 9% of the repo is the game" | True at the time, and the workspace it measured is gone. |
| "The `everyday` world is content-thin — 2 weapon forms, 30 items, 6 icons" | Measured against the shipped packs: **1310 catalogue entries** (2nd of six), 9 creatures (tied 1st), 25 icons, 471 images. `weapon_forms` is not in *any* pack — forms stopped being the seed's job, and 30 handcrafted weapon shapes across 7 families now always apply. The row was describing a world format that no longer exists. |
| "Tale and world are coupled — you cannot pick a tale then choose its world" | Fixed on 2026-07-22 by `913184a`, *before the audit that filed the row*. Both entrances are world-first: the menu's `_show_worlds()` announces "Step 1 of 3 — world › campaign › hero", and the Adventure Forge runs `_stage_campaign_world()` → `_stage_campaign_tale()`. The one tale-first path is the Campaign Shelf, which exists **on purpose** to browse premises across every world, and whose cards carry their world. |
| "`Rules.attack_mod` falls back to `GameState.inv()`" | It defaulted to `{}` — so a caller who forgot `inv` got the *unarmed* number, not a stale one. Real bug, wrong mechanism. Fixed by making `inv` required; the check is the compiler. |
| "The tile library is ~1.3 GB generated per install — ship it or make every player pour it" | Already shipped. Every world package carries **272 tiles across 170 roles, ~220 MB**; six worlds is the 1.3 GB the row was counting. `bootstrap.ps1` already downloads them and `board_paint._tile()` reads the package first. `user://tiles` fills only for a world the **player forges**, where generation is the only option there is. |

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

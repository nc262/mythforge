# The Great Bake — pre-render everything knowable

Director's call (2026-07-23): *"lets spend time rendering all the pre built
worlds and styles… you said only like 300 objects rendered before, I want
thousands… 10 materials, 10 enchantments, 6 rarities is already ~600 combos out
of only 26 generated pieces… yes lets pre bake literally as much as possible."*

Accepted, including the cost: this runs for hours per world, and that is fine.
It buys back the GPU during play (see [Performance.md](Performance.md) §1, §7).

---

## The model is already right — the volume is not

`world_compiler._build_catalogue` says it out loud:

> Treatments are applied at roll time, not baked, so this stays a browsable
> spine (hundreds) that rolls into thousands.

**Generated (pixels):** form × material.
**Composed (draw time):** rarity glow, treatment/enchantment overlay, tint.

That is exactly the Director's arithmetic — a few hundred generations carrying
tens of thousands of distinct items. Nothing about the approach needs changing.

### What is actually baked today

| World | PNGs |
|-------|------|
| embervale | 87 |
| neonspire | 87 |
| saltmarsh | 82 |
| everyday | **33** |

## The gap, and it is a big one

`_forms()` iterates exactly two kinds:

```gdscript
for kind in ["weapon", "armor"]:
```

But the game has **thirteen worn slots** — head · neck · cloak · chest · hands ·
waist · legs · feet · ring ×2 · main-hand · off-hand · shield
(`Rules.EQUIP_SLOTS`). Eleven of the thirteen have **no forms at all**, which is
why the Gear tab renders eleven identical grey diamonds (UXAudit R5, VIS-15) and
why a world's catalogue is 30–90 items instead of thousands.

## The target

| | now | target |
|---|---|---|
| slots with forms | 2 | **13** |
| forms per slot | ~3 | **6–8** |
| forms total | ~6 | **~90** |
| materials | 2–6 | **10** |
| **generated images / world** | ~85 | **~900** |
| rarities | 6 | 6 |
| treatments | few | **10** |
| **catalogue entries / world** | ~500 | **~54 000** |

900 generations → 54 000 items. Four worlds: **~3 600 images, ~216 000 items.**

At the ~22–27 s per icon measured on this box: **~6.5 h per world, ~26 h for
four.** Accepted. It runs once, ships in the zips, and every player who
downloads the game gets all of it for free — no GPU time on their machine, no
art competing with their narrator.

## Work, in order

| # | Item | Notes |
|---|------|-------|
| B1 | Extend `_forms()` past weapon/armor to all 13 slots; add `<slot>_forms` to the seed schema and the fallbacks | Unblocks everything else. Also kills the eleven-grey-diamonds defect. |
| B2 | Raise the seed's material ask to 10 and treatments to 10 | Prompt work; watch that the 8B still returns usable asset language (the 3B provably cannot — it returned *sharpening stones* for weapon forms). |
| B3 | Handcrafted fallback form set per slot, shipped in `tables.json` | So a weak model or a failed seed can never produce a 33-PNG world again. |
| B4 | Make the bake **resumable and idempotent** — skip keys already on disk, checkpoint per form×material | Non-negotiable at 6 h a world; a crash at hour five must not restart. |
| B5 | Run it for the four shipped worlds, re-zip, re-export | The long pour. |
| B6 | Vendor stock icons in the same pass (Performance §7 A1) | They are a constant in `tables.json`. |
| B7 | Verify composition holds at volume — rarity glow + treatment overlay over 900 bases, spot-checked per slot | The whole model depends on composed variants reading as distinct. |

## Two things to decide before B5 burns a day of GPU

1. **Enchantment overlays don't exist yet.** Rarity is already a draw-time glow.
   Treatments are applied at roll time to *names and stats* — not, as far as I
   can see, to the *icon*. If a Flaming Cutlass and a Frost Cutlass must look
   different, that overlay layer is new work and it belongs before the pour, not
   after.
2. **Slot silhouettes are a separate, cheaper win.** Eleven empty slots need one
   ghosted shape each — 11 images total, not 900. Worth doing first so the Gear
   tab stops looking broken while the big bake runs.

---

## Director's refinement (2026-07-23): material chooses the form

> *"a leather chest piece will look different than a steel chest piece, not just
> in texture but a completely different style — one is almost like a shirt, the
> other full-on armor… and there is more than just sword weapons, we need ranged,
> blunt etc."*

This breaks the flat form × material grid, and it should. **"Chest plate in
leather" is incoherent.** A leather chest is a jerkin; a steel chest is a
cuirass. The shape follows the material class, so the grid must be *filtered*,
not multiplied.

### The model

Every form carries a **material class** it accepts; every material carries the
class it belongs to. `_build_catalogue` crosses only compatible pairs.

| class | materials like | chest forms | notes |
|-------|----------------|-------------|-------|
| `soft` | cloth, hide, leather, sailcloth | jerkin, vest, padded coat, robe | reads as clothing |
| `mail` | chain, scale, ring | mail shirt, scale vest, chain coat | flexible metal |
| `rigid` | iron, steel, brine-iron, chrome | cuirass, breastplate, plate harness | full armour |
| `exotic` | bone, chitin, crystal, salvage | carapace, bound-plate | per-world flavour |

Same rule everywhere: a `soft` head form is a hood or a wrap, a `rigid` one is a
helm. A `soft` hands form is wraps or gloves; `rigid` is gauntlets.

**This raises quality *and* count.** Ten materials no longer produce ten
repaints of one silhouette — they produce four genuinely different silhouettes,
each in the materials that suit it.

### Weapon families

`weapon` is currently one bucket, and the seed reaches for blades. It needs
families, each with its own shapes:

`blade` · `axe` · `blunt` · `polearm` · `ranged` · `thrown` · `exotic`

6–8 shapes per family across 7 families ≈ **~50 weapon forms alone**, before
materials. That is where the Director's "thousands" actually comes from.

### Work this adds, before B5

| # | Item | Effort |
|---|------|--------|
| C1 | `class` tag on every form; `class` on every material (seed schema + fallbacks) | S |
| C2 | `_build_catalogue` crosses only compatible (form, material) pairs | S |
| C3 | Expand `SLOT_FORMS` per class — soft/mail/rigid/exotic variants per slot | M (table work) |
| C4 | Weapon families with 6–8 shapes each | M (table work) |
| C5 | Seed prompt asks for materials **with their class**, so world-invented materials slot in correctly | S |

C1+C2 are the mechanism and must land before C3/C4 make the tables large —
otherwise the first pour bakes incoherent pairs at scale.

## B2, measured — the 8B has a budget, and forms were the wrong thing to spend it on

Run live against the real backend (`llama3.1:8b`, `complete_json`), 2026-07-23.

**First attempt — ask for 10 materials + 10 treatments on the existing schema:**

| | asked | embervale returned |
|---|---|---|
| materials | 10 | **8** |
| treatments | 10 | **4** |
| weapon_forms | 6 | **3** |
| armor_forms | 4 | **2** (one of them `leather_greaves` — a *legs* piece) |

The JSON parsed cleanly both calls, with no trailing-comma repair. So this was
never a format problem and a smaller model would not have helped (the 3B cannot
do asset language at all). It is a **capacity** problem: a bigger ask made the
model worse at *everything in the object at once*, including the parts that used
to work.

**The fix was to take work away, not to change model.** `weapon_forms` and
`armor_forms` were cut from the schema entirely — they are no longer the seed's
job now that 30 weapon shapes across 7 families and 40 worn-slot shapes ship
handcrafted, with a floor under armour. What the seed is uniquely needed for is
what a world is *made of* and what happens to it, so it now spends its whole
budget there.

**Second attempt — materials + treatments + naming only:**

| world | materials | treatments | classes seen | clean JSON |
|-------|-----------|------------|--------------|------------|
| embervale | **10** | **10** | rigid 5 · soft 3 · mail 1 · exotic 1 | yes |
| neonspire | **10** | **10** | rigid 4 · mail 3 · soft 2 · exotic 1 | yes |
| everyday | **10** | **10** | rigid 4 · soft 2 · mail 2 · exotic 2 | yes |
| saltmarsh | **10** | **10** | rigid 3 · soft 3 · mail 2 · exotic 2 | yes |

4/4, on the nose, every class represented, 8/8 calls clean. ~130–160 s per call.

The treatment names it invents are world-flavoured rather than literal
(`flarescarred`, `char_worn`, `wearwrinkled`, `galvoxidized`), which the tint
matcher was too literal to catch — `TREATMENT_TINTS` keyword lists were widened
to the vocabulary the models actually produce.

## Two worlds added for the pour (Director, mid-bake)

The four shipped worlds are fantasy / cyber / pirate / modern — no Norse, no
steampunk, though both are fully-built visual families in `WorldSkin` (palette,
currency, art anchor, skill-tree name, vendor fallback). Two built-in worlds were
added so the default set covers them:

- **Fimbulreach** (`norse`) — black fjords, rune-carved longhouses, draugr and
  ice-jotun. Cast: a shieldmaiden, a völva, a mead-hall skald. Two campaigns.
- **Brasshaven** (`steam`) — soot-black spires, gaslit fog, dirigibles and
  boiler-warrens. Cast: an inventor, a Yard inspector, an aether-baron. Two
  campaigns.

Both are registered in `WorldSkin.BUILTIN` (so id-only family lookups resolve
before `remember()` runs) and carry `skin_family` on the record as a belt-and-
suspenders. They pour through the identical pipeline; `bake_worlds.gd` skips the
four already POPULATED and paints only these two on its next run — exactly the
B4 resume path, used on purpose.

## The pour, finished

All six worlds baked, verified, and shipped. Every one: **0 truncated PNGs, 0
catalogue entries with a missing icon.**

| World | family | PNGs | items | creatures | zip |
|-------|--------|------|-------|-----------|-----|
| embervale | fantasy | 285 | 1 150 | 9 | 239 MB |
| neonspire | cyber | 268 | 1 075 | 8 | 231 MB |
| everyday | modern | 315 | 1 310 | 9 | 253 MB |
| saltmarsh | pirate | 315 | 1 310 | 7 | 255 MB |
| fimbulreach | norse | 325 | 1 370 | 5 † | 255 MB |
| brasshaven | steam | 289 | 1 175 | 8 | 244 MB |

**~1 800 images, 7 390 catalogue entries, 1.4 GB of zips**, in ~11 h of GPU.
Exported: `dist/Mythforge.exe`, **1.6 GB**, all six bundled (under the 2 GB
GitHub release-asset cap).

† fimbulreach poured with **2** creatures where its siblings gave 7–9 — the 8B
underdelivering on one stage, the creature-side of exactly the hole `FALLBACK_FORMS`
plugged for forms. A world with two monsters repeats itself in every fight, so
`_stage_creatures` now has a **floor**: below 5, merge in the family fallbacks
(never replacing what the model actually invented, deduped by slug).
`tests/topup_creatures.gd` applies it to worlds already on disk and paints only
the missing portraits — deliberately not a Reforge, which would forget and
repaint every one. fimbulreach went 2 → 5 with its two original beasts' pixels
untouched; the other five worlds were correctly left alone.

## Status

**B1–B7 done.**

| # | State |
|---|-------|
| B1 | done — 13 slots have forms |
| B2 | **done, verified live** — 10 materials + 10 treatments, 4/4 worlds (above) |
| B3 | done — `FALLBACK_FORMS` floor + handcrafted `SLOT_FORMS` |
| B4 | **done** — see below |
| B5 | **DONE** — all six worlds poured, verified, zipped, exported |
| B6 | done — vendor stock baked by `_stage_vendor_icons` into `art/icons/` |
| B7 | done — spot-checked across classes and worlds (below) |
| C1–C5 | done |

### B4 — how the bake survives a kill

The file on disk **is** the journal; there is no second bookkeeping file to fall
out of sync with it.

- `_await_art` returns immediately if the destination already exists in the world
  package. One guard, so it covers every stage — parts, wares, biomes, portraits,
  maps — not just the one that motivated it. A Reforge is exempt: it means
  "repaint this on purpose".
- Both PNG writes (`Compiler._adopt_to` and `Art._pump`) write to `*.part` and
  rename on success. A kill mid-write can therefore never leave a truncated file
  under the name the skip-check trusts. `bake_zip.py` refuses to ship `*.part`.
- `compile_seed(world, resume := true)` reuses the stored style, assets,
  creatures and NPCs instead of re-asking the model — a fresh seed would invent
  different material and creature ids and orphan every icon already painted.
- `bake_worlds.gd` skips a world that is already POPULATED, and watches the
  pending count so it can tell "slow" from "stalled" (20 min without an image
  landing → move on and say so, rather than hanging on the 40-minute ceiling that
  was far too short for a multi-hour world anyway).
- A world resumed with nothing left to paint still settles to POPULATED —
  previously nothing would ever tick the counter down to trigger it.

**Proven by killing it, not by reading it.** embervale, mid-pour, hard kill:

| | first run | after kill + restart |
|---|---|---|
| time to reach the art queue | 496 s (4 LLM calls) | **5 s** (0 calls — stored seed) |
| images queued | 807 | **266** |
| PNGs on disk | 19 | 19, **none repainted** |
| truncated PNGs / stray `*.part` | — | **0 / 0** |

266 is exactly the 285 owed minus the 19 already painted.

### Two defects the pour itself surfaced

Both were found by watching the first run's numbers, and both would have been
expensive to discover afterwards.

**1. A world could be declared POPULATED with 400 images unqueued.**
`Art.request` answers its callback *synchronously* for a key it already has
cached. During `_start_background_art` that let `_bg_pending` dip to zero between
two stages — the world was marked POPULATED, and the bake harness walked on to
the next world while this one's art was still being enqueued, painting two worlds
at once on one GPU. `_bg_adopt` now refuses to settle the state while `_background`
is still true; `_start_background_art` settles it once, at the end. A cold art
cache hides this completely, which is why it had never shown up.

**2. The armoury painted 770 icons to back 230 items.**
`_stage_parts` crossed the **unfiltered** form × material grid while
`_build_catalogue` crossed the class-filtered one — so two thirds of every pour
was leather cuirasses and steel hoods that no catalogue entry could ever
reference. Measured on embervale: **807 images queued, 267 owed.** The art stage
now applies the same `_form_takes` test as the catalogue.

**~3.7 h of GPU per world, ~15 h across the four, spent painting unreachable art.**

### What a world actually costs, now that both are fixed

| | per world |
|---|---|
| forms | 77 (30 weapon · 40 worn-slot · 7 armour) |
| materials | 10 |
| form × material, **class-filtered** | **230** |
| \+ key art, 6 biomes, 6 battle maps, 8 creatures, 6 NPCs, 28 wares | 55 |
| **images** | **~285** |
| catalogue entries (× 5 rarities) | **1 150** |
| × 10 rolled treatments at draw time | **11 500 presentations** |

~2 h per world at the measured ~25 s an icon; **~8 h for four**, not the 26 h
this document first estimated. The earlier figure assumed the unfiltered grid —
the class filter is what makes the pour affordable, and it raises quality at the
same time, exactly as the Director's refinement predicted.

embervale, measured end to end: **5 329 s (1 h 29 m)**, 285 PNGs, 1 150 items,
**0 truncated files, 0 catalogue entries with a missing icon**. That last number
is the real proof the art stage and the catalogue now agree.

### B7 — does it hold up at volume

Spot-checked across classes. It does, and it is the Director's refinement made
literal: `jerkin.coarse_hides` is a fur-trimmed leather **coat**;
`cuirass.brine_iron` is full **plate**. Not one silhouette in two textures —
two different objects, which is the entire point of C1–C4.

The matte holds too: corners fully transparent, alpha-0 covering ~50 % of a chest
piece and ~93 % of a blade, so the icons cut out cleanly against any panel.

No incoherent pairs exist to find — `cuirass.coarse_hides` was never painted,
because the filter now governs the art stage as well as the catalogue.

### Ship weight — Director's call: ship full 1024

Icons are baked at 1024×1024 and render at 64–96 px (`myth_socket` /
`myth_card`), so the shipped pixels are ~11–16× oversampled on the longest edge.
The cost is real and was put to the Director explicitly:

| | old set | this pour |
|---|---|---|
| embervale.zip | 91 MB | **239 MB** |
| four zips | ~320 MB | **~950 MB** |
| exe | 443 MB | **~1.2–1.4 GB** |

**Decided: ship at full resolution** — no downscale at zip time. Future-proof
against a larger icon or a detail/zoom view, at roughly 3× the download. If that
ever needs revisiting, the lever is a downscale inside `bake_zip.py` only; the
full-res masters stay in `user://worlds/` regardless, so it is reversible without
re-pouring.

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

## Status

Planned, not started. B1–B4 are the build; B5 is the pour. Nothing has been
generated yet — the numbers above are targets, not results.

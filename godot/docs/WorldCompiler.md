# The World Compiler — technical design

**Status: design only. No code written.**
Directive (2026-07-21): *a World is no longer data, it is a compiled game
package.* Guiding principle: **"Generate once. Play forever."**

This document specifies the pipeline, its storage, its runtime, its upgrade
path, and — bluntly — where the ambition must bend to physics.

---

## 0. The governing constraint

Everything in this design is downstream of one number.

**Mythforge generates images serially on one local GPU.** The Art Director
(VS-1 Batch 3) enforces single-flight precisely because concurrent jobs on one
card produced garbage. So compile time is:

```
compile_time  ≈  images × seconds_per_image
```

At a measured ~1.3 MB per 1024² PNG and an assumed **T = 10 s/image** (SDXL,
local AMD — to be measured, see §12):

| Budget | Images affordable |
|---|---|
| 5 minutes | ~30 |
| 10 minutes | ~60 |
| 30 minutes | ~180 |
| 60 minutes | ~360 |

**The directive asks for tens of thousands of items. The GPU affords ~180.**

That gap is not a problem — it is the entire design. Every stage below exists
to turn ~180 generated images into tens of thousands of *believable distinct
things*, via composition, palette, treatment, and reuse. The Borderlands
insight is correct; this document is how it lands in a 2D game.

**Corollary:** any stage that cannot justify its image budget gets cut. Image
budget is the project's scarcest resource and is allocated explicitly in §12.

### One honest scope correction

The brief asks creature kits to contain **animations**, and speaks of
**models**. Mythforge is a 2D illustrated game — portraits, item icons,
backdrops, map art. There are no rigs, no skeletons, no sprite sheets, and
building them is a different project.

The faithful 2D translation, which this design adopts:

| Asked for | Delivered as |
|---|---|
| animations | procedural motion on 2D art — the MIL vocabulary (breathe, pulse, lunge, impact, fly_to) already does this |
| models | layered portrait/icon compositions with variant parts |
| body / head / armor / accessories | composition layers on a registered silhouette |

Nothing else in the brief needs correcting.

---

## 1. Production methods — the decision rule

Four ways to obtain any asset. **Choose the cheapest one that is honest.**

| Method | Cost | Use when |
|---|---|---|
| **Reused** | free | the asset already exists for this world, or is world-agnostic |
| **Handcrafted** | one-off human/dev cost, ships in the exe | it is *structural* — needed by every world, must never be missing, and can be neutral (frames, UI chrome, fallback type icons, the drawn glyph library) |
| **Procedurally assembled** | ~1 ms CPU | the variation is combinatorial — items, NPC outfits, tactical layouts, palettes, wear/rarity treatments |
| **AI-generated** | **10 s of the world's scarcest resource** | the thing must be *unique and seen closely*: the world's key art, its style anchor, hero/major-NPC portraits, legendaries, boss art, biome plates |

**The rule, stated once:**

> AI generation buys *identity*. Composition buys *quantity*. Handcraft buys
> *reliability*. Never spend one where another suffices.

Applied to the brief's own examples:

| Content | Method | Why |
|---|---|---|
| World key art, biome plates | **AI** | pure identity; seen full-screen |
| World Style Guide | **LLM** (text, not image) | cheap, and it steers everything else |
| Weapon/armour part layers | **AI, small set** | the world's design language; ~30 images buys thousands of items |
| The 20,000 swords themselves | **Procedural** | layer + tint + treatment; zero GPU |
| Common item icons (dagger, rope, torch) | **Handcrafted** *fallback* + AI *world skin* | must never be a star (playtest #16) |
| Architecture/dungeon/village kits | **AI, small set** | reused across every scene in that world |
| Creature species base | **AI, one per species** | identity |
| Creature world-variants (Pirate Orc) | **Procedural** over the base | palette + accessory layers |
| NPC role outfits | **Procedural** over a body base | 12 roles × palettes, not 12 generations |
| Tactical layouts | **Handcrafted data** + procedural skin | geometry is gameplay, not art |
| UI frames/buttons | **Handcrafted, world-tinted** | already true — `material_sb` proves it |
| Legendaries, named weapons, boss drops | **AI, on demand** | *this is where uniqueness creates delight* |

---

## 2. Pipeline overview

Ten stages, but only three tiers that matter operationally:

```
TIER A — THE SEED (text only, ~60 s, no GPU)
  S1  World Style Guide          LLM → style.json
  S2  Asset Language             LLM → parts manifest, palettes, motifs

TIER B — THE IDENTITY (GPU, the expensive part)
  S3  Key art + biome plates     AI  → the world you SEE
  S4  Part libraries             AI  → blades, guards, grips, fabrics…
  S5  Kit plates                 AI  → architecture, dungeon, village…
  S6  Creature species bases     AI  → one per species
  S7  NPC body/outfit bases      AI  → a few bodies, many procedural outfits

TIER C — THE ASSEMBLY (CPU, seconds, no GPU)
  S8  Item catalogue             compose parts → 10,000s of items
  S9  Tactical layout skinning   handcrafted geometry + world materials
  S10 UI theming                 palette + material roles → the whole interface
```

**Tier A gates everything.** Nothing may be generated before the Style Guide
exists, because the Style Guide is what stops each image from guessing what
"pirate" means independently — the root cause of style drift (§11 R2).

**Tier C costs nothing** and can re-run any time, which is what makes reforge
cheap (§10).

### Stage dependency graph

```
S1 Style Guide
 ├─→ S2 Asset Language ──→ S4 Parts ──→ S8 Item catalogue
 │                          │
 ├─→ S3 Key art ────────────┼─→ S5 Kits ──→ S9 Tactical skinning
 │        │                 │
 │        └─→ (playable)    ├─→ S6 Creatures
 │                          └─→ S7 NPCs
 └─→ S10 UI theming (needs only palette + materials — runs at 60 s)
```

Only S1 → S2 → S4 → S8 is a hard chain. Everything else fans out, so stages
can be reordered by *what the player will see first* (§4).

---

## 3. Stage specifications

### S1 — World Style Guide *(LLM, ~20 s, no GPU)*

The permanent source of truth. Extends today's `WorldSkin.FAMILIES` from eight
hardcoded families to a generated document per world, with the family as its
prior rather than its ceiling.

```jsonc
{
  "id": "cw-elyrien-8f21", "name": "Elyrien", "family": "fantasy",
  "version": 1, "compiler": "1.0.0",
  "visual":    { "language": "…", "lighting": "…", "weather": […], "motifs": […] },
  "palette":   { "ink": "#…", "gold": "#…", "materials": { "steel": "#…" } },
  "materials": ["ash wood", "bronze", "wolf leather", "iron"],
  "iconography": { "symbols": […], "engravings": […] },
  "architecture": { "forms": […], "roofs": […], "ornament": […] },
  "wardrobe":  { "commoner": …, "noble": …, "military": … },
  "arms":      { "blade_forms": […], "guard_forms": […], "wraps": […] },
  "bestiary":  { "species": […], "adaptation_rules": "…" },
  "flora_fauna": […],
  "culture":   { "naming": …, "customs": …, "taboos": … },
  "audio":     { "direction": "…", "instruments": […] },
  "ui":        { "panel_material": "stone", "page_material": "parchment", … },
  "prompt_anchor": "… 30-60 words appended to EVERY image prompt …"
}
```

`prompt_anchor` is the load-bearing field: one shared clause in every prompt
plus a fixed style seed is the primary defence against drift.

### S2 — Asset Language *(LLM, ~20 s, no GPU)*

Turns the Style Guide into a **parts manifest**: exactly which layers to
generate and how they may legally combine.

```jsonc
{
  "weapon.sword": {
    "layers": ["blade", "guard", "grip", "pommel"],
    "blade":  [{"id":"leaf","prompt":"…"}, {"id":"straight",…}, …],   // 4
    "guard":  [ … 3 ], "grip": [ … 3 ], "pommel": [ … 3 ],
    "materials": ["iron","bronze","bone"],       // tints, free
    "treatments": ["clean","worn","blooded"],    // overlays, free
    "rarity": ["common","uncommon","rare","epic","legendary"]
  }
}
```

**The arithmetic that justifies the whole design:**

```
13 generated part images (4+3+3+3)
 × 4×3×3×3 = 108 silhouettes
 × 3 materials = 324
 × 3 treatments = 972
 × 5 rarity treatments = 4,860 distinct swords
```

Repeat for axe, bow, staff, armour, shield → **~60 part images ⇒ >20,000
items.** That is the brief's "tens of thousands", bought for ten minutes of GPU.

### S3 — Key art + biome plates *(AI, ~8 images)*
World key art, 4–6 biome plates (forest/mountain/harbour/ruin/interior/night).
Biome plates are the reskin source for tactical maps (S9) and the backdrop
source for scenes — this is why battle maps stop needing runtime generation.

### S4 — Part libraries *(AI, ~40–60 images)*
Generated **in registration**: identical canvas, identical camera, identical
neutral lighting, transparent or flat background, the part centred on a fixed
anchor. See §11 R1 — this is the design's single largest technical risk, and
§5 specifies the two-tier fallback.

### S5 — Kit plates *(AI, ~12–20 images)*
Architecture, dungeon, village, forest, harbour, temple, ship, road,
furniture, decoration. Used as scene backdrops, Lore Book art, and map skins.

### S6 — Creature species *(AI, ~10–16 images)*
One base per species. **World adaptation is procedural**: the Pirate Orc is
the Orc base + pirate palette + accessory layer from S4, not a new generation.
That is the brief's Orc→Pirate/Cyber/Norse/Horror chain, delivered for one
image instead of five.

### S7 — NPC bases *(AI, ~8–12 images)*
A small set of body/portrait bases (build × age bracket). The twelve roles —
guard, merchant, farmer, priest… — are **wardrobe compositions** from S2/S4,
not twelve generations each.

### S8 — Item catalogue *(CPU, ~2 s)*
Enumerates the legal combination space into `items.json`: stable ids, display
names (from the culture/naming rules), stat rolls, and a **recipe** naming its
layers. No pixels stored — icons are composed on demand and memo-cached (§7).

### S9 — Tactical layouts *(handcrafted data + CPU skin)*
**Geometry is gameplay and must not be AI-generated.** A shipped library of
~40 hand-authored layouts as data — cover, elevation, water, bridges, walls,
vegetation, hazards, LOS blockers, spawns, objectives. Compilation *skins*
them with the world's materials and biome plates. Combat starts instantly, and
the engine already understands the terrain because the terrain is authored,
not inferred from pixels (which is what today's colour-heuristic sampler does).

### S10 — UI theming *(CPU, instant)*
Extends the existing material-role system: panel/page/frame/button materials,
palette, iconography accents. A pirate world never shows fantasy leather.

---

## 4. Progressive playability — the answer to the 30-minute wall

**This is the highest-risk part of the directive.** A 30-minute block before
play is, for a first-time player, worse than today's runtime hitches: they
cannot tell "compiling" from "hung", and they have not yet been given a reason
to care about this world.

Design response — **the world is playable long before it is finished:**

| Milestone | Elapsed | State |
|---|---|---|
| **Seeded** | ~60 s | Style Guide + Asset Language exist. UI already themed. |
| **Presentable** | ~3 min | Key art + 2 biome plates. **World is playable.** |
| **Furnished** | ~12 min | Parts, item catalogue, kits. Loot and scenes are world-true. |
| **Populated** | ~25 min | Creatures, NPCs, tactical skins. Compile complete. |

- Play unlocks at **Presentable**; the rest continues in the background, and
  the Art Director yields to gameplay requests (lane `NOW` pre-empts compile).
- The forge shows honest per-stage progress with world-aware copy — the
  brief's own "Raising mountains… / Arguing with gravity…" belongs here, one
  line per real stage, never a fake timer.
- A world carries `compile_state` (`seeded|presentable|furnished|populated`),
  so the Library can show it and the runtime resolver knows what to expect.
- **Compile is resumable**: a stage journal records each completed step, so a
  crash, a quit, or "play now, finish later" all recover.

---

## 5. Modular asset system & composition rules

### Layer model

An item icon is composed:

```
base tint (material palette)
  → part layers, z-ordered by the manifest
  → treatment overlay (wear / blood / frost / neon bleed)
  → rarity treatment (rim light, glow, frame)
```

All CPU, all ~1 ms, all cacheable.

### Registration — and the fallback that de-risks it

Layer composition only works if parts share a canvas, scale, and anchor.
Diffusion models do not naturally honour that. **Two tiers, and Tier 1 ships
first:**

| Tier | Method | Robustness |
|---|---|---|
| **T1 — Palette & treatment** *(ship this)* | ~20 whole-item base icons per world; vary by material tint, wear overlay, rarity frame | **High.** No registration needed. ~20 images ⇒ 20 × 6 × 5 = **600 distinct icons** |
| **T2 — True part layering** *(prototype)* | parts generated on a fixed silhouette template (img2img/ControlNet over a shipped mask) | **Medium.** Needs a spike to prove alignment before it is trusted |

T1 alone already ends "a staff renders as a star". T2 multiplies it to five
figures. **Recommendation: implement T1 in the first pass, spike T2 in
parallel, promote it only when a side-by-side proves it.**

### Naming

Item display names come from the Style Guide's culture/naming rules composed
with the recipe — "Bronze Leaf-Blade of the Ash Coast" — so names vary with
the same combinatorics as the art, for free.

---

## 6. Storage strategy

### Two tiers — the correction this design forces

Today there is **one 700 MB global LRU**, which would cheerfully evict a
world's item parts to make room for a scene backdrop. That is wrong:

> **Compiled world assets are not a cache. They are content.**

| Tier | Contents | Eviction |
|---|---|---|
| **Content** — `user://worlds/<id>/` | everything the compiler produced | **never**, except on explicit world delete/archive |
| **Cache** — `user://cache/` | runtime one-offs: scene paintings, hero portraits, ad-hoc art | LRU, budgeted (today's behaviour, retained) |

### Footprint

At 1.3 MB per 1024² PNG, a fully compiled world at ~150 images ≈ **195 MB**.
Five worlds ≈ **1 GB**. Mitigations, in order of value:

1. **Right-size by role** — an item part does not need 1024². Parts at 512²
   (~350 KB) and 256² (~90 KB) cut the parts library ~10×.
2. **WebP for parts** — lossless WebP is typically 25–35 % smaller than PNG.
3. **Archive a world** — keep `world.json` + key art, drop the rest; reforge
   restores it. Worlds become cheap to keep, expensive only while loved.
4. **Per-world budget + a Library-visible size**, so the player owns the tradeoff.

### Folder layout

```
user://
  worlds/<world_id>/
    world.json            # style guide + manifests + compile_state + versions
    compile.journal       # resumable per-stage record
    art/
      key.png  biome/*.png
      parts/<slot>/<family>/<id>.webp
      kits/<kit>/*.webp
      creatures/<species>/base.webp
      npc/<body>/*.webp
      maps/world.png  maps/skins/<biome>.webp
      unique/<slug>.png          # legendaries, named NPCs — AI one-offs
    data/
      items.json  layouts.json  naming.json
    recipes/<asset_id>.json      # prompt · seed · model · workflow · version
  cache/                          # LRU, runtime one-offs only
  saves/                          # untouched by compilation (see §10)
```

`recipes/` generalises today's per-asset sidecars, which already record
prompt, seed, model, and workflow — **reforge is possible because that data is
already being written.**

---

## 7. Runtime asset lookup

One resolver, one fallback chain, **never a dead end**:

```
resolve(kind, id):
  1  world content     worlds/<id>/…            ← compiled, world-true
  2  composed          compose(recipe) → memo   ← CPU, ~1 ms
  3  family default    engine family art        ← shipped
  4  engine default    handcrafted neutral art  ← shipped, always exists
  5  drawn glyph       MythIcon by TYPE         ← sword/shield/potion, never a star
```

Rules:
- The resolver is **synchronous and total** — it always returns something
  drawable. No screen ever waits, and no screen ever shows a placeholder that
  lies about what the thing is (playtest #16's root cause).
- If a better tier arrives later (compile finishes, unique art lands), the
  Art Director's existing `art_ready`/callback routing upgrades it in place.
- Step 4 is why **handcrafted defaults still ship** even in a world-compiler
  architecture: they are the floor that makes every other tier optional.

---

## 8. Caching strategy

| Layer | What | Lifetime |
|---|---|---|
| **Compiled content** | stage outputs | world lifetime |
| **Composition memo** | assembled icons | session, LRU by count |
| **Texture memo** | decoded `ImageTexture` | session (exists today) |
| **Runtime cache** | scene art, portraits | LRU by bytes (exists today) |
| **Negative cache** | "this failed" | session — never retry a failing prompt in a loop |

Rule: **an asset is generated at most once per world per pipeline version.**
The recipe hash is the identity; identical recipes never re-spend GPU.

---

## 9. Compilation control

- **Serial, always** — one GPU, enforced by the Art Director.
- **Pre-emptible** — a gameplay request (lane `NOW`) jumps the compile queue;
  compile resumes after. Playing during compilation stays responsive.
- **Resumable** — the journal makes crash/quit/resume free.
- **Cancellable** — abandoning a compile keeps what was made; the world stays
  at its achieved `compile_state`.
- **Budgeted** — the player picks *Quick* (~5 min, presentable), *Standard*
  (~15 min, furnished), *Deep* (~30 min+, populated). The budget maps to §12's
  allocation table.

---

## 10. Reforge architecture

Worlds as living assets, upgraded as models improve, without restarting
campaigns.

**The enabling invariant — stable logical ids, swappable pixels:**

> Everything in the game refers to assets by **logical id**
> (`item:sword/leaf/bronze`, `creature:orc`), never by file path. Reforge
> replaces the pixels behind an id. Nothing that references it needs to know.

**What versions:** `world.json` carries `compiler` (pipeline version) and each
recipe carries the model, workflow, seed, and prompt used.

**Reforge = diff + re-run:**

```
for asset in world:
    if recipe.compiler_version < current  or  recipe.model != preferred:
        re-generate into a NEW file, keep the old until the new one lands
```

- **Scoped**: reforge only architecture, or only equipment, or only creatures —
  matching the brief's list.
- **Atomic per asset**: a failed reforge leaves the old art in place.
- **Preserved absolutely**: lore, campaigns, characters, chronicles, and player
  progress live in **server state** (`state/<cid>/…`) and the adventure index —
  a *different namespace* that the compiler never writes. This separation
  already exists, which is why reforge is safe by construction.
- **Style continuity**: reforge reuses the original Style Guide and seeds
  unless the player explicitly asks for a restyle, so a world stays itself.

---

## 11. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| **R1** | **Part registration fails** — layers don't align, composites look broken | **High** | Tier the ambition (§5): ship T1 palette/treatment, spike T2 layering, promote only on proof |
| **R2** | **Style drift** across a long compile | **High** | `prompt_anchor` in every prompt · fixed style seed · generate a family in one contiguous run · a reference plate for img2img if available |
| **R3** | **The 30-minute wall** reads as a hang | **High** | Progressive playability (§4) · honest per-stage progress · play at *Presentable* |
| **R4** | **Disk growth** — 200 MB/world | Medium | Right-size by role · WebP · archive · visible per-world size |
| **R5** | **Compile failure mid-way** | Medium | Journal + resume · per-stage atomicity · a world is always *usable* at its achieved state |
| **R6** | **GPU contention** with the storyteller | Medium | Already solved: single-flight + lanes; compile yields to `NOW` |
| **R7** | **Model/workflow drift breaks reforge** | Medium | Recipes record model + workflow + seed; reforge is opt-in per scope |
| **R8** | **Combinatorial slop** — 20,000 items that all feel the same | **Medium-High** | Curate: name generation from culture rules, rarity gates on part families, and a cap on how many variants actually *drop* |
| **R9** | Scope creep — the compiler swallows the project | Medium | Stage the delivery (§13); T1 first; nothing ships without the harness green |

### Bottlenecks, ranked

1. **GPU serial time — dominates by two orders of magnitude.** Everything else
   is rounding error. Optimise here or nowhere.
2. LLM calls for S1/S2 — ~40 s total, once.
3. Composition CPU — ~1 ms/icon, irrelevant.
4. Disk I/O — irrelevant.

**Therefore:** the only optimisations that matter are *generating fewer
images* and *making each image buy more*. That is exactly what §1's decision
rule and §5's layer model do.

---

## 12. Estimated compilation times

Image budget per profile (T = 10 s/image; **T must be measured before
committing** — if the real number is 20 s, halve every count):

| Stage | Quick | Standard | Deep |
|---|---|---|---|
| S1–S2 Style + Language (LLM) | 40 s | 40 s | 60 s |
| S3 Key art + biomes | 3 | 6 | 8 |
| S4 Parts | 8 | 30 | 60 |
| S5 Kits | 4 | 12 | 20 |
| S6 Creatures | 3 | 10 | 16 |
| S7 NPC bases | 2 | 6 | 12 |
| S8–S10 (CPU) | ~3 s | ~3 s | ~3 s |
| **Images** | **20** | **64** | **116** |
| **≈ Time** | **~4 min** | **~12 min** | **~21 min** |
| **Items yielded** | ~600 | ~5,000 | >20,000 |

---

## 13. Scalability & delivery

**Scales well:** worlds are independent packages; more worlds = more disk, not
more coupling. Composition is O(1) per icon. Adding a new item family is a
manifest edit plus a handful of images.

**Watch:** total disk across many worlds (§6), and the item catalogue's size in
memory once it reaches five figures (stream it, don't hold it all).

**Suggested delivery order** — each step independently shippable, harness green:

1. **Shipped engine defaults + resolver** (§7 steps 3–5). *Kills playtest #16
   immediately, with zero GPU, and becomes the floor everything else stands on.*
2. **S1 Style Guide** — generated, consulted by existing prompt builders.
3. **Storage split** — content vs cache (§6); stop the LRU eating worlds.
4. **S3 + S10** — key art, biomes, UI theming. World identity, cheaply.
5. **T1 item variation** (§5) — palette/treatment over base icons.
6. **S9 tactical layouts** — handcrafted geometry; instant combat.
7. **Progressive compile + forge sequence** (§4) with the Library showing state.
8. **T2 layering spike** → promote if it proves out.
9. **Reforge** (§10) once ≥2 pipeline versions exist to test against.

Steps 1–3 alone deliver most of the felt benefit — "the world already has its
things" — before a single minute of compile time is spent.

---

## 14. Open questions for the Director

1. **Measure T first.** One timed batch of 10 images decides whether the
   budgets above are right or need halving. *Recommend doing this before
   committing to any stage counts.*
2. **Quick / Standard / Deep** — accept these three, or a single fixed budget?
3. **T1-only, or fund the T2 spike now?** T1 is safe; T2 is the difference
   between hundreds and tens of thousands of icons.
4. **Does compile block play?** This design says no (§4). Confirm.
5. **Disk ceiling** — what's an acceptable per-world footprint on your box?

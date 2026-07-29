# Terrain — tiles in the cells, walls on the borders

Design for the battle map rewrite (R10). Replaces `Combat.bake_terrain()`, the
colour heuristic that guessed mechanics from a generated painting.

## Why the old model cannot be repaired

The pipeline ran backwards: paint a picture, then infer mechanics from pixels.
Three failures, all structural:

1. **Ambiguity.** A 3×3 colour average cannot tell a snowfield from a stone
   wall — they have nearly the same mean colour. On Fimbulreach the rule
   `avg.s < 0.14 and luma > 0.2` classified *open snow* as impassable.
2. **Coordinate mismatch.** `battle_grid._draw()` draws the painting
   **cover-fit** (scaled to fill, overflow cropped, centred) while
   `bake_terrain()` sampled the **whole image stretched** across 16×10. At the
   measured play size (~1155×370 widget, 1024×1024 map) the player saw only
   source rows ~347–675 while the baker sampled rows 0–1024. The overlay was
   describing part of a painting that was not on screen.
3. **Walls are not cells.** A wall occupies the *border between* two squares.
   A cell-fill model can only approximate it by eating a whole 5 ft square,
   which makes rooms unbuildable and corners meaningless.

Assembling from tiles inverts the pipeline: choose the layout, then render it.
Every cell and every edge knows what it is **because it was placed**. The
heuristic is deleted, not tuned, and the coordinate mismatch cannot exist
because there is no separate painting to align against.

## The two layers

### Cells — what is *in* the square

| Field | Meaning |
|---|---|
| `role` | tile identity (`snowdrift`, `stone_floor`, `boulder`…) |
| `move` | `1` normal · `2` difficult · `0` impassable |
| `cover` | `none` / `half` / `three_quarters` granted to an occupant |
| `blocks_los` | a pillar or dense thicket fills the square *and* the sight line |
| `hazard` | optional: on-enter or start-of-turn effect |
| `variant` | which painted variant of the role to draw |

### Edges — what is *between* two squares

Stored on the **north** and **west** edge of each cell only, so every border has
exactly one owner. A 16×10 grid therefore has 16×11 horizontal + 17×10 vertical
= **346** addressable edges, with no duplicates to keep in sync.

Key form: `"x,y,N"` and `"x,y,W"`.

| Kind | Blocks move | Blocks sight | Cover | Note |
|---|---|---|---|---|
| `wall` | yes | yes | — | the common case |
| `low_wall` | no (costs 1 extra) | no | half | vaultable |
| `railing` | no (costs 1 extra) | no | half | |
| `window` | yes | no | three_quarters | shoot through, cannot pass |
| `arrow_slit` | yes | no | three_quarters | |
| `door` | when `closed` | when `closed` | — | stateful; openable, lockable, breakable |
| `curtain` | no | yes | — | the inverse of a window |
| `fence` | no (costs 1 extra) | no | half | |
| `cliff` | one-way | no | — | descend freely, climb costs |
| `open` | no | no | none | the default; not stored |

## Mechanics this requires

Replacing "is this cell blocked" with an edge model touches more than movement.
The full list, so none of it is discovered late:

- **`can_step(from, to)`** — destination cell passable **and** the shared edge
  passable **and** unoccupied. Replaces every `terrain_at(c) == "block"` test.
- **Diagonal corner-cutting** — 5e forbids moving diagonally when *both*
  orthogonal edges of the corner block. Without this, walls leak at every corner.
- **`move_cost(cell, edge)`** — difficult terrain doubles; vaulting a low wall
  or fence adds. Water already doubles today and must keep doing so.
- **`has_los(a, b)`** — a ray that tests **edge crossings**, not cell contents.
  Endpoints exempt: standing in rubble gives you cover, it does not blind you.
- **`cover_between(a, b)`** — 5e's real rule is corner-to-corner: trace from
  each corner of the attacker's square to each corner of the target's. All four
  clear → none. Some blocked → half. Most blocked → three-quarters. This
  replaces today's `in_cover()`, which only asks "am I next to foliage".
- **Adjacency** — "next to" must mean *reachable*, not merely neighbouring. Two
  cells either side of a wall are **not** adjacent: no melee, no opportunity
  attack. Today `adjacent()` is pure Chebyshev distance and would let a hero
  stab through a wall.
- **Opportunity attacks** — follow from the corrected adjacency, free.
- **Pathfinding** — `enemy_approach()` currently steps toward the hero and will
  walk into walls. Needs an edge-aware A*, or it will look stupid immediately.
- **Doors as state** — open/close/lock/break are actions, which means an edge
  can change mid-fight and any cached sight must invalidate.
- **Elevation** (deferred) — high ground and ranged sight over low walls. Noted
  so the schema leaves room; not in the first pass.

## Rendering

- **Cells** draw a baked square tile per role+variant.
- **Edges do NOT use baked sprites.** A wall drawn on a border is a thin strip
  with corner joins; generated art will never tile cleanly at that scale, and
  edges are exactly where seams are most visible. Draw them procedurally —
  a line of the right thickness, filled with a small baked **material swatch**
  per world (stone, timber, ice, riveted brass). Always seamless, near-zero GPU,
  and it reads correctly at any zoom.
- **Square cells.** The widget must letterbox to the grid's 16:10 aspect. At the
  measured play size cells were 72×37 px — 2:1 rectangles — which makes
  Chebyshev distance look wrong even when it is right.

## The bake — ~1,000 tiles

Roles × worlds × variants, the same shape as the item bake's form × material
grid. **40 roles × 6 worlds × 4 variants = 960**, plus ~60 edge material
swatches ≈ **1,020**.

Four variants per role is the point: a snowfield that repeats one tile reads as
wallpaper.

**Open ground (10)** — grass_short · grass_wild · dirt · sand · snow ·
ice_smooth · stone_floor · wood_floor · cobble · leaf_litter

**Difficult (8)** — mud · scree · snowdrift · undergrowth · shallow_water ·
rubble_field · reeds · bog

**Impassable fills (7)** — boulder · rock_outcrop · chasm · deep_water ·
hazard_pool · dense_thicket · wreck

**Cover objects (7)** — crates · pillar · statue · cart · table · brazier ·
debris_pile

**Features (8)** — stairs_up · stairs_down · bridge · shore_edge · grate ·
well · pit_trap · rune_circle

**Edge materials (10 × 6 worlds)** — stone · timber · ice · brass · low_wall ·
railing · door · window · curtain · cliff

## Layout templates

Cells and edges are assembled from a **stencil**, not scattered randomly, or
fights read as noise. A dozen archetypes — hall interior, cave mouth, shore,
ridge, street, courtyard, bridge, clearing, cellar, deck, crossroads, ruin —
each a 16×10 pattern of roles and edges. At fight time the engine picks the
stencil matching the scene and fills it with tiles skinned to the current world.
A cave in Fimbulreach and a cave in Brasshaven share a stencil and share nothing
else.

`Combat.set_terrain_spec()` already parses a `[[terrain]]` tag and is currently
dead code — the GM never emits it. Under this design the GM picks the *stencil*
and dresses the fiction. Narration, not adjudication.

## Order of work

1. **Engine model first, no art.** Cells + edges, `can_step`, corner rule,
   `has_los`, `cover_between`, edge-aware adjacency and pathfinding, all under
   `self_check` assertions. The art must serve a spec that is already proven.
2. **Placeholder renderer** — flat colours per role, walls as lines. Confirms
   the map is legible before any GPU time is spent.
3. **One stencil, one world, ~12 roles** — the seam test. Look at it.
4. Full bake across six worlds if the seams hold.
5. Delete `bake_terrain()` and the colour heuristic.
6. **Ship the tiles in the world package**, not the runtime cache.

Steps 1–3 cost no GPU and are where the risk actually lives.

## Where tiles live

`worlds/<world>/art/tiles/<role>-<variant>.png` — 136 per world, beside
`creatures/`, `npc/`, `maps/` and `icons/`, zipped by `scripts/bake_zip.py` and
extracted on first run. The world is implied by the package, so it is not in the
filename. `Compiler.tile_art()` resolves them; `battle_grid` asks the package
first and falls back to the global art cache only for a world compiled at
runtime.

This is not a new idea — it is the rule the project already had, in
`art_cache.gd`: *"the worlds ship pre-baked and runtime art is now reserved for
what the player invents."* The tile system was written against the older
generate-on-demand pattern and had to be brought in line. `art_cache.beast_tex`
carries an RCA for the identical mistake with creatures.

Cost: packages roughly double, ~250 → ~500 MB each, ~3 GB for the six.
Deliberate. If that ever needs to come down, the lever is **WebP q90 inside the
package** — measured 6.5x smaller at identical 1024 resolution — not shrinking
the masters.

**A world id is `world.json`'s `id`, never the display name.** "Saltmarsh Reach"
is `saltmarsh`. Keyed as `saltmarsh-reach`, `WORLD_GROUND` silently fell through
to embervale's default and 136 tiles were baked under a world that does not
exist at runtime. `self_check` now asserts every `WORLD_GROUND` entry names real
roles and that `open` is move-1 — the second half catching `open: "mud"`, which
made 90% of a saltmarsh clearing difficult ground.

## What the bake taught us

Two prompt shapes, not one. Surfaces want *"seamless tileable top-down overhead
texture of X"*. Objects want the opposite — asking for "one boulder, seamless
tileable" returns a pebble field, because the tiling instruction wins and turns
the object into wallpaper.

Objects then failed twice more before working:

- *"a single boulder … no horizon, no sky"* returned a **landscape photograph**,
  mountains and sea included. The negatives sat at the tail and lost to the noun
  at the head. Leading with the camera fixed it: *"top-down orthographic game
  asset sprite, camera directly overhead pointing straight down, single isolated
  X centred on a plain flat dark grey background"*.
- **Tall objects still failed.** A statue came back as a wall plaque with a face;
  a column came back as five scattered blocks; a table came back as decking that
  reads as the `bridge` role. Overhead, a tall thing has no top face worth
  seeing, so the model either tilts it upright or multiplies it to fill the
  square. The squat objects — boulder, brazier, firepit, chasm, crates — had no
  such trouble. **Rule: a top-down object tile must describe something squat or
  fallen.** `pillar`, `statue` and `table` are now toppled.

All three failures reported success in the log. The only thing that told them
apart was opening the PNG — and at 64 px, the cell size that actually ships,
some 1024 px "failures" read fine and one apparent success (`table`) read as the
wrong role entirely. **Judge tiles at cell size, not at bake size.**

## RCA: the pour that could never finish

The full pour ran for hours and stalled at ~434 tiles of 816. It was not slow —
it was producing a tile every 17 s the whole time. It was being eaten.

`art_cache.gd` is an LRU with a 700 MB budget. 816 tiles at ~1.6 MB is ~1.3 GB,
so once the directory hit 700 MB every finished tile evicted an older one. Net
growth went to zero and `has_art()` kept going false for evicted keys, so the
wait loop could never reach 816. It would have run to its 6-hour timeout.

Two things made this hard to see:

- **The obvious metric lied.** Counting files showed +1 in three minutes, which
  reads as "slow GPU". Counting *writes* in the same window showed 10. Growth
  and production are different measurements, and only the second one was true.
- **An early count was wrong in the other direction.** `grep -c '^tile-'` counts
  the `.json` sidecars too, so 782 "tiles" was really 417 PNGs. That inflated
  figure is why the pour looked nearly done when it was barely half.

Collateral: before reaching equilibrium the pour evicted **every other painting
in the game** — hero portraits, battle maps, item art. Eviction deletes the
sidecar as well as the PNG, so regenerated art comes back with a fresh seed and
a different face. That art is not recoverable.

Fix: tiles are a fixed library that must be present all at once, which is the
opposite of what an LRU is for. They now live in `user://tiles/`, outside the
manifest and the budget. That fix is independent of tile size — it works at any
resolution, because tiles no longer count against the budget at all.

Tiles are kept at the model's native 1024, ~1.3 GB for the full set. An earlier
pass downsampled them to 256 ("~3x a grid cell, under 100 MB") and that was a
false economy: disk is the cheapest thing in this stack, a 4K fullscreen cell is
~150 px so the headroom is worth having, and resizing is a one-way door — the
detail only comes back with another GPU pour. The 395 tiles shrunk during that
pass were re-poured at full resolution.

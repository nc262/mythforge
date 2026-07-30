# The Battle Board — research, and a real plan

Written after R11, where the Director's verdict was *"I don't think this is
playable."* That is correct. This document establishes how turn-based tactical
games actually build a board, then plans against it. Nothing here is
implemented yet.

## What I got wrong, structurally

I generated 816 tiles before establishing how a tactical board is composed. The
result is that **the library is the wrong shape of asset**.

Every tile I baked is a *centre fill* — a square of grass, a square of dirt. A
tileset that blends needs **transition tiles**, and I have zero. That is the
whole reason a patch of undergrowth reads as a green rectangle pasted onto the
dirt (R11-04). No amount of prompt tuning fixes it, because the missing thing
is not a better square — it is the pieces *between* squares.

Two more things I hand-rolled that the engine or the industry already solved:

- **Godot has terrain autotiling built in.** `TileMapLayer` + TileSet terrain
  sets pick edge and corner tiles automatically as cells are painted, driven by
  per-tile 3x3 peering bits, with `set_cells_terrain_connect()` for procedural
  use. I wrote `draw_texture_rect` in a `_draw()` loop instead.
- **Grid opacity has a known-good default.** Foundry VTT ships **0.2**. Mine is
  **0.07** — roughly a third of it, which is precisely the Director's "I don't
  see a small overlay grid to blur the borders". At 0.07 the seams between tiles
  read as accidents; at 0.2 the grid reads as deliberate structure and *hides*
  the seams by giving the eye a reason for them.

## What the research says

### Blending is a solved problem, and the cheap solution is dual-grid

| scheme | tiles needed | notes |
|---|---|---|
| Blob (S-V2E2) | **47** of 256 combos | the classic autotile set |
| Wang / edge (S-E2) | 16 | edge-matched |
| Marching squares (S-V2) | 16, or 6 with symmetry | corner-matched |
| **Dual grid** | **5 + rotations** | ~87% fewer assets |

**Dual grid is the one to use.** Two overlapping grids: the *logical* grid holds
terrain roles (what the rules read), and the *display* grid is offset by **half
a cell**, so each display tile sits over the corners of four logical cells. It
looks at those four corners and picks one of five shapes — empty, corner, edge,
diagonal, inner-corner, full — rotated as needed. Because the display tile's
corners land on logical cell *centres*, there is never an ambiguous
partially-covered tile, so transitions are seamless by construction.

This matters enormously for cost: the five shapes are **geometry, not art**.
They are alpha masks. They can be drawn procedurally or generated once as small
greyscale PNGs — no diffusion, no GPU hours. The 816 baked tiles stay exactly as they
are and become the *base fills*; blending is a mask layer on top.

### Readability comes from the art, not from overlays

The VTT guidance is blunt about this: *is it clear whether each grid square is
passable?* If you bake the answer into the map, players do not have to ask
during combat. That is the argument against my permanent hatching — a boulder
should read as impassable **because it looks like a boulder**, not because a
red X has been stamped over the art. I spent four GPU hours painting terrain and
then defaced it with a diagram.

### Tactical overlays are contextual, not permanent

Across XCOM 2, Fire Emblem and VTT range modules the convention is consistent:
movement range and threat range appear **on selection or hover** and disappear
otherwise. Range overlays account for walls and difficult terrain rather than
drawing a naive radius. Enemies reachable without moving get a distinct ring.
Nothing is painted on the board while the player is just looking at it.

## The plan

Phased so each phase is playable on its own. Phases 1–3 need no GPU.

### Phase 1 — make the board legible (no new art)

1. **Square the cells.** R11-02: cells currently draw ~75x40. A 5-ft grid whose
   distance rule is Chebyshev must be square, or a diagonal lies. Size the board
   from `min(width/COLS, height/ROWS)` and centre it.
2. **Grid to 0.2 alpha**, the VTT default, drawn *over* the tiles.
3. **Delete the permanent mechanical overlay** — the hatching and the drag
   stripes. Impassability reads from the art.
4. **Movement overlay on selection only**: when it is the player's turn and they
   select move, tint reachable cells (the existing edge-aware `reachable()`
   flood already computes this correctly, respecting walls and difficult
   terrain). Light, low-alpha, and gone the moment the action resolves.
   Blocked-but-adjacent cells tint light red, as the Director asked.
5. **Hide the minimap during combat.** It is an exploration affordance; it
   currently covers the composer, the dice tray and the action bar (R11-03).
6. **Fix the composer chrome** — the green wash behind the input.

### Phase 2 — blending, via dual grid (no new art)

7. Add a display layer offset half a cell, sampling the four logical corners.
8. Author the five mask shapes procedurally.
9. Terrain priority order (water < mud < dirt < grass < stone) so the softer
   material always feathers over the harder one, giving a consistent look.

### Phase 3 — the fight has to be real

10. **R11-01 is P0 and blocks everything else.** The GM must stop resolving
    attacks. `tag_parser._atk_re` should not turn "make an attack roll" into a
    generic check while a fight is live; combat routes to
    `Combat.player_attack()`, which already checks reach, rolls against AC,
    applies damage and doubles crit dice — and is currently never called.
11. **Foes need faces.** Samuel Jenkins renders as a letter in a red circle
    because he is GM-invented and has no package art. This is the *correct* use
    of runtime generation — a portrait for what the player's story invented —
    and it is exactly the case the art cache exists to serve.

### Phase 4 — consider TileMapLayer

Once the board is legible, evaluate replacing the hand-rolled `_draw()` with
`TileMapLayer` + terrain sets. It is the engine's own answer and brings
autotiling, but it means restructuring how tiles are addressed. Not worth doing
before Phase 1 proves the layout.

## What does not change

The edge model, `reachable()`, `has_los()`, `cover_between()`, the 5e corner
rules and the stencils are all correct and stay. R11 proved the mechanical layer
matches the paint. The problem is entirely in presentation and in who rolls the
dice.

## Sources

- [Godot 4 TileMapLayer tutorial](https://codingquests.io/blog/godot-4-tilemaplayer-tutorial)
- [Setting up autotiling with Terrains](https://uhiyama-lab.com/en/notes/godot/terrains-autotile-setup/)
- [Classification of Tilesets — BorisTheBrave](https://www.boristhebrave.com/2021/11/14/classification-of-tilesets/)
- [Dual Tilemap Autotiling Technique — Excalibur.js](https://excaliburjs.com/blog/Dual%20Tilemap%20Autotiling%20Technique/)
- [Autotiling interactive guide — Red Blob Games](https://www.redblobgames.com/articles/autotile/claude/)
- [Foundry VTT Content Creation Style Guide](https://foundryvtt.com/article/content-creation-guide/)
- [Combat Range Overlay — Foundry VTT](https://foundryvtt.com/packages/combat-range-overlay)
- [Tactical RPG Movement — GDQuest](https://www.gdquest.com/tutorial/godot/2d/tactical-rpg-movement/)
- [Smart Terrain Designs for VTT Battle Maps](https://www.runicdice.com/blogs/news/smart-terrain-designs-for-virtual-tabletop-maps)

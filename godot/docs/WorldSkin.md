# World Skin (M-B) — the per-campaign visual language

The engine had no concept of a per-campaign look: `Ui.PALETTES` knew three
built-in worlds and everything else fell back to fantasy; `material_sb` only
made steel/leather/brass/oak; `Art.world_flavor()` returned "high fantasy" for
any custom world. The **World Skin** is the missing abstraction: one descriptor,
resolved deterministically from the world, that every surface reads.

> Autoload is named **`WorldSkin`**, not `Skin` — `Skin` is a built-in Godot
> class (mesh skinning) and shadows an autoload of the same name.

## The contract

A **family** (`WorldSkin.FAMILIES`) carries everything a surface needs:

```
family → {
  palette:  <Ui.PALETTES key>          # drives the whole theme via Ui.apply()
  currency: "gold" | "credits" | …      # GameState.currency()
  art:      "<style suffix>"            # (verbose) generated-art direction
  materials: {steel,leather,brass,oak → plate}   # Ui.material_sb() role remap
  flavor:   {map, pack, book, world}    # nouns + Art.world_flavor() (flavor.world)
}
```

Families today: `fantasy · cyber · everyday · space · steam · pirate · horror ·
norse`. Plus `WorldSkin.MUSIC` (family → ambient track) and `BUILTIN` (world_id →
family for the three shipped worlds).

## Resolution (deterministic — the LLM never gates a valid skin)

`WorldSkin.family_of(world)`:
1. built-in id → its family (`embervale`→fantasy, `neonspire`→cyber, `everyday`→everyday);
2. a stored `world.skin_family` wins (frozen at World Forge seal);
3. else keyword-match `kind + tagline + lore` against `KEYWORDS` (first hit wins);
4. else `fantasy`.

A process-global cache (`_by_id`) keeps play cheap. It is **warmed at the main
menu** (`_refresh` remembers every world) and **frozen at World Forge seal**
(`world.skin_family = family_of(world)`), so an id-only lookup in play resolves
correctly. `WorldSkin.remember(world)` populates it; `family_for_id`,
`skin_for_id`, `music_for_id` read it.

## How each surface consumes it

| Surface | Reads |
|---|---|
| Whole theme (buttons, panels, borders, text) | `Ui.apply(world_id)` → skin palette → `_build()` |
| Menu world cards | `WorldSkin.skin_for_id(wid).palette` |
| MythButton plates | `Ui.material_sb(role)` → `skin.materials[role]` |
| Generated art (portraits, scenes, maps, world) | `Art.world_flavor()` → `skin.flavor.world` |
| Currency label everywhere | `GameState.currency()` → `skin.currency` |
| Ambient music | `WorldSkin.music_for_id()` |
| Scene-repaint prompt | `Art.world_flavor()` |

## Shipped vs. deferred

**Slice 1 (shipped, `ffb7e19`):** the resolver + cache, five new reference
palettes, skin-driven theme/currency/art/music/flavor, `material_sb` role remap
(auto-tinted to the palette), self-check on the resolver.

**Slice 2 (next):**
- Bespoke procedural material textures — glass/holo, neon, copper, carbon,
  canvas — so cyber/steam buttons read as their material, not tinted forged-metal.
- Per-theme `MythIcon` variants (a compass/scroll reads fine cross-genre; a full
  cyber/steam icon set is the content task).
- **Contrast-clamp** — required before any LLM-refined palette lands, so a
  generated palette can never fall below legibility minima. (Not needed yet: the
  eight authored family palettes are hand-checked.)

## Extending

- **New family:** add to `FAMILIES` (+ a palette in `Ui.PALETTES` under its
  `palette` key), add keywords to `KEYWORDS`, add a `MUSIC` entry.
- **LLM-refined palette (future):** the worldsmith may emit a `skin` block
  (palette hexes + art style); merge it over the derived family, then
  contrast-clamp. The deterministic family remains the always-valid floor.

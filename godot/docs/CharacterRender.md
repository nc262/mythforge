# Character Render (M-F) — the paper doll & the asset pipeline

Issue 5 asked for a fully rendered character whose equipment shows live. True 3D
(rigged meshes + modular per-theme equipment) is a large **content** commitment,
so per the Director it is **paused**. What ships is **Stage A: a full-body paper
doll driven entirely by the generated-art asset pipeline** — no new asset store,
no commissioned meshes.

## The asset pipeline (the decision)

**Assets are generated, cached, and skinned — never hand-authored or 3D.** The
paper doll reuses the exact `Art.ensure → the image engine → user://art` path that
already paints portraits, scenes, maps, and item icons:

- **The body:** `herobody-<cid>` — a full-body figure prompted from the hero's
  race/class/name + the names of everything currently equipped, in the active
  **World Skin's** art style (`Art.world_flavor()`). Painted once, cached; a
  **"Re-render with current gear"** button re-prompts it after a loadout change
  (kept manual because each generation costs GPU time the narrator also needs).
  Until it lands, the head-and-shoulders portrait stands in.
- **The pieces:** each equipped item shows its `item-<slug>` icon (already
  generated on loot via `Art.ensure_item_icon`).

This means a cyberpunk hero renders in chrome-and-neon, a fantasy hero in
plate-and-cloak — the figure inherits the world for free, and there is nothing to
ship but prompts.

## Equipment slots (the mechanics)

The four-slot system (weapon/armor/shield/offhand) grew to a full **thirteen**
worn slots so there is real gear to find and wear:

`head · neck · cloak · chest(armor) · hands · waist · legs · feet · ring ×2 ·
main-hand · off-hand · shield`

- `Rules.item_type` classifies any item name into the right slot (boots→feet,
  helm/hood/crown→head, amulet/pendant→neck, ring→ring, gloves/gauntlets→hands,
  belt/sash→waist, leggings/breeches→legs, cloak/cape/mantle→cloak) before the
  generic armour test. `Rules.EQUIP_SLOTS` / `TYPE_SLOTS` / `WEARABLE` are the
  single source of truth.
- `GameState.toggle_equip` fills the right slot, sends a second light weapon to
  the off-hand, and lets rings occupy either finger (toggle off from whichever
  holds them).
- Accessories are **cosmetic until magical** (`acBonus` only at epic/legendary),
  so a full kit doesn't inflate AC; `Rules.eff_ac` already sums every worn slot.
- The GM's `[[loot name="…"]]` needs no change — any boots/ring/helm it grants
  now equips into its slot automatically.

## The doll UI

A **Gear** tab on the character sheet: the generated body flanked by two columns
of slot sockets (+ a hands row beneath), each socket showing the worn piece's
icon. **Tap a slot** → a picker of pack items that fit it → equip/unequip; the
doll rebuilds and the AC line updates. Sockets reuse `MythSocket`.

## Deferred — Stage C (true 3D), only on an explicit asset decision

A `SubViewport` + rigged base meshes + modular equipment with attachment sockets
+ per-theme material sets. Gate: **how are the meshes sourced** (commissioned vs.
generated-3D vs. a bought asset pack)? Until that's answered, Stage A is the
shipping character render.

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

## Stage C (true 3D) — the gate is answered, the engine side is built

**The sourcing question was: commissioned, generated, or bought.** The answer is
**CC0 packs on the Rigify humanoid**, and the reason is in `spike3d`: Rigify maps
1:1 onto Godot's `SkeletonProfileHumanoid`, which is the hub every other humanoid
— Mixamo, VRM, hand-sculpted, *generated* — retargets through. Choosing it does
not just buy one pack, it makes every future source compatible.

### What is measured

| Fact | Where |
|---|---|
| Costume must live in the **mesh**; prompting a base body drifts on every repose | spike, `4a2ca33` |
| Race and sex are **bone scale on one mesh** — 9 heritages × 2 sexes, not 18 bodies | `spike3d/heritage_bodies.gd` |
| Material is a **shader input**, so form × material is addition, not multiplication | spike, `e3c3b26` |
| A poured material needs **triplanar** — a game mesh's UV atlas scrambles it | same |
| The outline pass is what makes it read as **drawn rather than rendered** | spike, `4a2ca33` |
| KayKit (41 bones) and Quaternius (53, Rigify) are **not interchangeable** | rig probe, 2026-08-04 |

### The method (`scenes/char3d/modular_doll.gd`)

The one every game uses: body split into zones, each garment its own skinned
mesh, all bound to **one** skeleton — Unreal's Leader Pose Component; in Godot,
several `MeshInstance3D` pointing at the same `Skeleton3D`.

- **Rigid** pieces (helm, sword, shield) ride a `BoneAttachment3D`; no skinning.
- **Fitted** pieces (chest, leggings) are skinned to the same skeleton — sourced
  pre-skinned, or weight-transferred from the base body in Blender
  (`Data Transfer → Vertex Groups`), which is the standard garment workflow.
- **Poke-through** is solved by hiding body zones, not by masks or shaders,
  because these bodies already arrive split. A garment declares what it covers.
- Zones are recomputed from the **whole loadout** every change. Toggling
  incrementally leaves a leg hidden when the leggings come off but the boots
  stay — invisible until a player undresses in an order nobody tested.
- Every rig fact is **data** (`RIGS`), because the rig will change.

Verified against the real CC0 body in `spike3d`, and rendered: bare → helm
(head mesh gone, no face through the visor) → helm+cape → full kit → undressed.

### What is still needed

Two free CC0 downloads, both gated behind itch.io's session so they cannot be
fetched by script:

- **Universal Base Characters** — 6 bodies, 20 hairstyles, the rig the animation
  library in `spike3d` already matches
- **Modular Character Outfits – Fantasy** — 12 outfits, **62 parts**

Genres those do not cover (cyber, contemporary, steam) are generated locally —
image-to-3D, then weight-transferred onto the same rig. That is what the Rigify
choice buys.

**Rendered slots:** head, chest, hands, legs, feet, cloak, main-hand, off-hand,
shield. Rings, amulets and belts stay icons — they are invisible under a sleeve
at this size and cost nothing by being left out.

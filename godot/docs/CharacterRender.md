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

### The three surfaces, one doll

Settled by the Director: the character is a **tabletop figurine**, not a hero
render. This game calls itself the table on every other surface — *"the table
keeps the tally"*, *"leave the table"* — so a miniature is the object the fiction
already says is there. It also sets the fidelity bar honestly: nobody asks a
28 mm mini to be photoreal, and the low-poly CC0 body reads as a deliberate
sculpt at that size rather than as a cheap character.

| Surface | Framing | Cost |
|---|---|---|
| **Gear page** (`DollView`) | Full figure, **breathing and jiggling**, drag to turn | Free, **instant** on equip, and only while the page is open |
| **Battle board** | Small figurine, one held frame | Free, cached per loadout |
| **Scenes** | Painted hero, **painted over** the doll's render | One GPU pass, on demand — measured 5.9 s |

The scene hero is img2img over the figurine, not a prompt describing the same
person. The spike measured why: costume in the PROMPT drifts on every repose —
three poses gave three different rangers — while costume in the MESH survives
both reposing and stylisation. Feeding the render in means identity, pose and
every worn piece are decided by geometry and diffusion only supplies surface.

Two details, both paid for once already in `scripts/stylize_render.py`:

- **The alpha must come back.** sd-server returns RGB, so the viewport's free
  cut-out dies in the round trip; the render's own alpha is re-applied, leaving
  the silhouette geometry's to decide.
- **The matte is mid-dark, never black or transparent.** On black the model
  paints black rim-light into the edges; on white, haze.

Denoise is the whole dial, measured on this stack: **≤0.35** painterly with
identity held exactly · **0.45** silhouette held, details re-invented · **≥0.55**
fully re-imagined, identity gone. It ships at 0.35.

The Gear page previously showed a *generated painting* of the body, so putting on
a helmet was a request to the image engine and a wait. That is the right picture
for a scene and the wrong one for a fitting room. The painting is not deleted —
it moved to the job it is good at, still commissioned by the same button.

`SubViewport.UPDATE_WHEN_VISIBLE`, never `ALWAYS`: a viewport left rendering
behind a hidden tab is GPU nobody can see, and on this machine the narrator and
the image engine already fight over one card. `DollView._process` goes further
and stops the animation and the springs as well, because a viewport that is not
drawing still has a 70-bone skeleton being re-posed behind it, once per garment.

### One surface lives, the others are held frames

The board token and the painted scene hero are **one captured frame**; the Gear
page **runs**. That split is the whole reason both can be good at once — the
token is rendered once per loadout into an `ImageTexture` and the board is free
to repaint every frame over it, while the page the player is staring at gets an
idle loop and soft-tissue simulation.

So the doll has two entry points that are deliberately not the same call:

| | Plays | Springs | Used by |
|---|---|---|---|
| `stand()` | first clip on `stand`, then **pauses** | off | board token, scene hero, forge preview |
| `live()` | first clip on `live`, looping | **on** | Gear page only |

**The clip names in those lists are Godot's, not Blender's.** UAL2 ships
`Idle_Shield_Loop`; Godot's glTF importer reads the `_Loop` suffix as a loop-mode
hint, sets the mode from it and *strips it from the name*. A list written from
the Blender clip list therefore matches nothing and does so **silently** — the
figure simply keeps whatever pose it already had, which reads as a design
decision rather than a lookup that found no clip.

### Soft tissue — shape and jiggle are the same five bones

The pack's base body has **no shape keys** (`o.data.shape_keys is None`,
measured), so there was nothing to blend towards a bust, a seat or a paunch. The
old `chest` knob scaled `spine_03`, which widens an entire ribcage: it passed
every assertion and never once made a chest.

`scripts/add_jiggle_bones.py` adds five bones — `breast_l/r`, `glute_l/r`,
`belly` — to the body **and to all twenty-three garments**, weighting each to a
hand-sized patch of flesh by radial falloff and taking that weight back off the
joints already holding it. One change buys both halves:

- **Shape** — `apply_build` scales the bone evenly and the patch swells. Nothing
  hangs off these bones, so an even scale is a radial swell, which is what a bust
  *is*. Knobs: **Chest**, **Seat**, **Belly**, span 0.45 each.
- **Motion** — `SpringBoneSimulator3D` simulates the same bone. Each is a
  one-bone chain whose tip is synthesised by `extend_end_bone`, which is why no
  leaf bones had to be added to the rig.

Weighting the **garments** is not optional. Hidden-surface removal deletes the
skin under the cloth, so a jiggle that moved only the skin would be invisible
right up until it punched through.

The bone positions are **measured, never typed**: the seed is the most forward
(or most rearward) vertex in a height band, so it lands on the real surface of
whichever body it is run against. Male and female seed differently, which is why
the script runs once per sex.

Spring constants were chosen off a four-point sweep in `tests/jiggle_shot.gd` —
peak pixel displacement 0.518 / 0.540 / 0.677 / 0.740 from tightest to loosest.
The looser end keeps paying, so the limit is taste rather than range; the shipped
values sit one notch back from the point where flesh starts reading as rubber.

### The world's cloth — what the pack does not cover

The outfit pack is fantasy, and there is no CC0 sibling for any other genre:
Quaternius ships exactly one modular outfit pack. So four world families —
**cyber, everyday, space, steam** — would otherwise put a cyberpunk fixer in a
peasant's brown wool.

They wear the fantasy cut in the world's own **poured cloth** instead. This is
the material spike's model finally wired in: a material is a *shader input*, so
form × material is addition rather than multiplication, and one tileable texture
per family covers every garment from any source. `_dye()` in `modular_doll.gd`,
`assets3d/cloth/world_cloth.gdshader`, poured by `scripts/pour_materials.py`.

Three things make it read as clothing rather than as paint:

- **Triplanar, never UV.** A garment's atlas is laid out for its own painted
  texture; a tileable material pushed through it arrives stretched and scrambled.
- **The garment's own albedo survives as LUMINANCE.** Every strap, lace and seam
  is painted into that texture and it is the only record of the tailoring. The
  shader keeps its light and dark and replaces only the hue, with a floor at
  0.55 — without the floor a dark cloth times a dark albedo compounds to
  near-black, and the first render was a figure smeared with soot.
- **Tiling is 2.5 object-space repeats**, chosen off a rendered sweep. The
  spike's 0.25 was tuned on another mesh and puts one thigh-sized blotch per
  limb; 9.0 looks finer standing still and aliases to mush at the 256 px the
  figurine actually renders at.

The four fantasy-ish families — fantasy, pirate, horror, norse — are deliberately
**not** in the table. The pack was authored for them, and pouring a material over
a good texture only costs the detail painted into it.

**This fixes the substance and not the silhouette**, and that is the honest
limit: a Neon Spire hero is in grey technical weave, still in a sleeveless tunic
with thigh straps. A real cut needs new geometry, and image-to-3D is not
available here — this whole stack is Vulkan *because* there is no CUDA on this
machine, and the image-to-3D models are CUDA-only.

#### Pouring cloth, which is not like pouring a material

Leather and bronze sit on tables in the training data, so "seamless tileable
flat lay of …" is enough. Cloth never does — it is draped on a body, sewn into a
garment, or stretched across a wall — so the same phrasing returns the *context*
rather than the substance. Measured, over six rounds and forty pours:

| Asked for | Came back as |
|---|---|
| "flat lay of technical synthetic twill" | glossy satin drapery |
| "flat lay of ripstop nylon" | an architectural moulding |
| "flat lay of waxed canvas" | a tiled brick wall, then a chrome object |
| "extreme macro close-up of woven fabric" | macro *photography* — shallow depth, drama, folds |

Four things fix it, and the script carries each with the failure it prevents:

1. **"flatbed scan", not "flat lay".** A scan is a physical process that cannot
   have folds, drama or depth, and the model knows its output.
2. **Say DENIM.** Of every attempt, only the ones naming denim or canvas twill
   rendered as fabric at all. Colour and thread vary; the weave noun does not.
3. **Claim the frame** — "full frame edge to edge, one continuous piece" — or the
   scan arrives as cut swatches with white paper between them.
4. **Search the seed against a fold metric.** Prompt words move the odds; they do
   not decide it. `fold_score()` shrinks the image to 16×16, so every thread
   averages away and only shape survives, and takes the deviation: flat weave
   2–7, folded garment 24–38, and nothing has ever landed between.

Exposure is corrected at bake time by `lift_value()`, because the two demands
cannot both be prompted: a flat evenly-lit denim scan **is** dark, and every
candidate above value 100 scored 60–90 on folds, since a highlight means a fold.
The lift is a **gamma**, not a multiply — lifting 15 to 130 by multiplication
clips everything above 32 to white, and that came out on the figurine as
camouflage.

**Rendered slots:** head, chest, hands, legs, feet, cloak, main-hand, off-hand,
shield. Rings, amulets and belts stay icons — they are invisible under a sleeve
at this size and cost nothing by being left out.

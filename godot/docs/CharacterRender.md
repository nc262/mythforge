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
| `live()` | an idle on `live`, looping, interrupted by gestures | **on** | Gear page only |

**The clip names in those lists are Godot's, not Blender's.** UAL2 ships
`Idle_Shield_Loop`; Godot's glTF importer reads the `_Loop` suffix as a loop-mode
hint, sets the mode from it and *strips it from the name*. A list written from
the Blender clip list therefore matches nothing and does so **silently** — the
figure simply keeps whatever pose it already had, which reads as a design
decision rather than a lookup that found no clip.

### The skin's own surface

The pack's skin ships a **normal map and a roughness map**, and its material
references both. The hidden-surface shader replaced that material the moment any
garment went on — and sampled albedo alone, with a hard-coded flat roughness. So
a bare hero rendered with pores and a dressed one rendered like painted plastic.
That is every hero, always, on every surface in the game, and nothing failed
because nothing was looking.

The shader carries both through now, and it is applied **even bare**, which
matters for a second reason: it is the one material the skin always wears, so it
is the only place a skin tone can live. Ten tones, multiplied over the pack's
albedo so freckles, lips and brows survive — a flat fill gives a hero the face of
a mannequin dipped in paint.

Four of the ten are not human colours at all. `crimson`, `violet`, `verdant` and
`azure` are there because **a tint is what makes a tiefling possible on one base
body**: horns and a tail are geometry and can be attached, but without the skin
a tiefling is a human wearing horns.

The eyebrows go with the hair. They are the BODY's mesh, not a worn piece, on
the same `MI_Hair` material the wigs use — tinting only the worn hair gave every
hero white eyebrows over black hair.

### Horns, and heritage on one body

No free pack ships a horn, and a horn is a swept tube, which is arithmetic.
`scripts/author_horns.py` grows four — ram, swept, spire, nub — as rings along a
curve that pitches back as it climbs, tapering to a point, with ridges as a sine
on the radius. That last term costs nothing and is the difference between a horn
and a traffic cone.

**They need no new mechanism.** Every vertex is weighted to `Head` at 1.0, so as
far as the doll is concerned a horn IS a garment: worn through `_wear_file`,
following the skull through every animation, with no socket, no bone attachment
and no second code path.

**The roots are seeded, not typed.** The two skulls sit 43 mm apart — the same
gap that made `Hair_BuzzedFemale` render as bald — so a horn placed by hand on
one head floats above the other. Each root is the surface vertex furthest along
a direction from the head's own centre, which lands correctly whatever the skull
is shaped like. The first render put that direction out on the TEMPLES and the
result read as a bull; horns want the brow ridge, and forward-and-inward is the
whole difference.

**A hood does not take them off.** Hair is hidden under a hood; horns are part of
the head, and a tiefling who loses their horns to a hat is not a tiefling.
`self_check` asserts it, so nobody "fixes" it later.

Horn colour is its own palette, not the hair's — bone-white over crimson is a
different character from black, and neither should follow what the hero did with
their hair.

### The tail

Five bones onto the BODY's own skeleton, and a mesh skinned across them —
`scripts/author_tail.py` does both, rewriting the body in place the way
`add_jiggle_bones` does.

Putting the bones on the shared skeleton rather than giving the tail a private
armature is the entire trick. `SpringBoneSimulator3D` is already hanging off that
skeleton, already tuned, so a chain rooted at `tail_01` and ending at `tail_05`
is **one entry in a table** and the tail sways with no new simulation, no second
skeleton to keep in step and no attachment maths. A private armature would have
needed all three.

The garments did NOT need re-exporting. A garment's skin binds to the bones it
names and none of them names a tail, so extra bones are inert to everything that
does not reference them — only the two bodies were rewritten.

It takes the SKIN's tint rather than its own: a crimson tiefling with a beige
tail reads as a costume.

**No clip in either animation library touches a tail bone** — they were baked
long before the bones existed. That makes the proof free: every millimetre
`tail_05` moves from its rest is the spring and nothing else, so `jiggle_shot`
asserts on exactly that rather than on a picture.

So the shipped body now reaches a **tiefling** (crimson, horns, tail) and most of
the way to a **dragonborn** (verdant or azure, horns, tail). What a dragonborn
still lacks is scales and a snout. Scales are a surface and therefore reachable —
the skin shader already samples albedo, normal and roughness and multiplies a
tint, so a tiling scale pattern is one more sampler. **A snout is the wall, and it was measured rather than assumed.**

First, the distinction that matters: **face bones drive expression, not shape.**
A jaw that opens, a brow that furrows, an eyelid that closes — they move a head
you already have. Scaling a jaw bone on a human skull gives a human with a large
jaw, because the vertices are still arranged as a human face. A dragonborn's head
is a different SHAPE, and shape is geometry.

The head does have the topology for it: 1,691 vertices above `neck_01`, 833 of
them in the face. So `scripts/forge_head.py` tried the trick the wardrobe uses —
deform the body's own head, leave the UVs alone, and every mask, texture, garment
and bone binding survives untouched. That reasoning holds.

**The execution does not.** Pushing a weighted band of vertices forward INFLATES
a face rather than sculpting one: the result is a smooth featureless dome with
the eyes, which are their own mesh and correctly did not move, buried inside it.
A muzzle needs the jaw separated from the skull, a bridge built between them, and
the eye sockets held back while everything around them travels. That is sculpting
logic, not a displacement field.

`tests/head_shot.tscn` renders any candidate head beside the human control, close
and in profile, which is what a next attempt should be judged against. What it
would take is one of: a sculpted draconic head sourced or authored as its own
mesh and seamed to the neck; or a different base body that ships one — and a
different base body means re-baking every mask and re-fitting the wardrobe.

### The neck, and the four rules it took

Every torso garment was deleting the throat, so the head sat straight on the
shoulders and you could see down inside the collar from behind. The cause was
proximity: the mask hides skin within 3.5 cm of cloth, and a throat is within
3.5 cm of a collar that stands clear of it.

Three rules were written to fix that and none did.

| Rule | Result |
|---|---|
| Reject hits on any open-edge face | The tunic's laced placket is an open edge too — the whole chest came back bare |
| Reject them only from the outward side | A collar is a TUBE: skin above it is *inside* that tube, so the side test reads "under cloth" and never fires |
| Require the skin be ENCLOSED — a fan of rays, most finding cloth | A collar does surround a throat sideways; only the opening above escapes. Still ate it |
| Tighten the distance to 1.2 cm | Saved the neck, put the legs straight through the trousers |

All four were general answers to a specific problem. **Nothing in this wardrobe
covers a throat** — the collars stand off it and the hood is a shell around the
skull with its whole front open. So `neck_line` excludes everything above
`neck_01` by REGION, taken from the rig so a different body carries its own
line, and the entire class of bug stops being reachable. With that in place
there was nothing left for a clever proximity rule to do, and all of them were
deleted.

**And none of the three had ever actually been tested.** `Image.save()` with a
relative path writes nothing and reports nothing, so every re-bake for four days
was a no-op and every measurement was taken against stale PNGs. The bake now
checks the file exists afterwards. The lesson is the repo's own, again: the
render was identical three times running, and that was the evidence.

`jiggle_shot` renders each garment on the neck at close range with a `_raw`
control beside it — the same loadout with masking off. That control is what
finally separated "the mask is eating it" from "the collar just looks like
that", after an hour of tuning a bake that was not being written.

### Hair, which was in the repo all along

Five cuts and a beard ship with the base characters, skinned to the same 65
bones — and were wired to **nothing**. Every figurine this project has ever
rendered was bald, and nobody caught it, because bald is a perfectly plausible
thing for a character to be.

They are appearance, not equipment: `apply_look` sets them once at build from
the sheet, they are not in `RENDERED_SLOTS`, and `wear_inventory` never touches
them. Mechanically each is a garment on the shared skeleton, so it rides
`_wear_file` with the dye switched off — hair is not cut from the world's cloth,
and pouring denim over it turns a hero's head into a hat.

**A hood eats the hair.** No mask needed: hair is its own mesh, so hiding it is
a boolean. The beard stays, because a hood does not cover a chin.

**The tint IS the hair colour.** The pack authors its hair near-white so any
colour can multiply onto it, so leaving the tint bright is not "as authored", it
is platinum — the first render gave a party of silver-haired seventy-year-olds.
Six palette entries rather than free RGB, so a player cannot pick a hair that
vanishes into the hood they later put on.

### Soft tissue — a morph for the shape, a bone for the swing

The pack's base body shipped with **no shape keys** (`o.data.shape_keys is None`,
measured), so there was nothing to blend towards a bust, a seat or a paunch. The
first `chest` knob scaled `spine_03`, which widens an entire ribcage: it passed
every assertion and never once made a chest.

`scripts/add_jiggle_bones.py` adds five bones — `breast_l/r`, `glute_l/r`,
`belly` — to the body **and to all twenty-three garments**, weighting each to a
hand-sized patch of flesh by radial falloff and taking that weight back off the
joints already holding it. Weighting the garments is not optional: hidden-surface
removal deletes the skin under the cloth, so a jiggle that moved only the skin
would be invisible right up until it punched through.

Those bones then did **both** jobs — scaled for shape, simulated for motion —
and the second job quietly paid for the first. `SpringBoneSimulator3D` reads a
chain's rest length and radius, so scaling a bone to make a fuller bust also
retunes its physics: a hero at the top of the slider jiggled differently from one
at the bottom, for no reason a player could name. So the two are now split.

- **Shape** is a **morph**, authored by `scripts/author_shapes.py`: `Chest`,
  `Seat`, `Belly`, each a measured bulge seeded off `spine_03` / `spine_01` /
  `pelvis` so the male and female skeletons place their own. Godot's blend-shape
  values are not clamped to 0–1, so one key per axis spans flat to full — a knob
  at 0 sends −1 and a knob at 100 sends +1.
- **Motion** is the bone, at its authored rest, doing nothing but swinging.

**The garments carry the same keys, and they were not authored twice.** Each is
bound to the body with Blender's **Surface Deform** modifier, the body's key is
driven to 1, and where the cloth ends up is read back and stored as a key of the
same name. The tunic was *measured following the skin*, not given a matching
falloff and hoped to agree — which is why its `Seat` key lives on its back at hip
height and its `Chest` key does not. `_apply_morphs()` pushes every value onto
every mesh on the doll by name, so a boot that has no `Chest` is simply not moved
and needs no table saying so.

Two things about Blender's shape keys cost a day between them, and neither is
documented anywhere obvious:

- **`shape_key_add()` hands back a key already at value 1.0.** glTF stores morph
  weights, so an un-zeroed key ships a permanently inflated body — and every
  garment bound afterwards binds to that inflated body, making its morph target
  the difference between two wrong shapes. The first run wrote a tunic that
  answered a chest bulge with *nothing* and answered a seat bulge on its **front**.
- **Surface Deform perturbs nearly every vertex by a few microns**, even where the
  body did not move. Count the response at a millimetre; at the float noise floor
  every key reports half the mesh and all three look identical.

Bone positions and bulge centres are **measured, never typed** — the seed is the
most forward (or rearward) vertex in a height band, or a named joint — so both
scripts run once per sex and land on whichever body they are given.

### The life of the figure

An idle on repeat is a screensaver. What reads as alive is an idle that keeps
being **interrupted**: the hero shakes the stance out, swings the sword, nods,
hails someone, hops, and goes back to standing there. `_gesture()` fires every
2.6–6.5 s, picks a sequence, plays it with a 0.22 s cross-fade and returns to
the idle when it ends.

Which pool depends on what is in the hand — a hero holding a sword who never
swings it reads as a mannequin holding a sword, and one swinging an empty fist
reads as a bug. A third pool, the spell set, is added only when
`Rules.caster_level` says this hero casts, so a Barbarian never throws an arcane
flourish at nothing and a half-caster Ranger still can.

The idle is picked **at random** per build from every clip on the `live` list
that exists and loops, so two heroes on two save files do not hold the identical
stance.

**Three animation libraries.** Two sourced, one written here. UAL2 is situational
— farming, zombies, sword combos — and ships no neutral idle at all, which is
why the figure used to stand in a sword guard regardless. UAL1 has the plain
idles, a spell set and the punches, but its Godot export is **Rigify**: 53 bones
sharing exactly one (`root`) with the 65-bone rig. `scripts/retarget_anim.py`
bakes it across, transferring each bone's **delta from rest** rather than its
world rotation — copy world rotations directly and every limb twists, because
the two rigs roll their arm bones differently.

And between them those 86 clips contain **no wave, shrug, bow or look-around**:
they are locomotion and task libraries, and the social emotes a character needs
while standing still are not in them. So `scripts/author_gestures.py` writes
nine, on the shipping rig, from measured bone axes and a base pose borrowed off
frame 0 of the idle. See [assets3d/SOURCE.md](../assets3d/SOURCE.md).

**A repeated entry in a pool is a weight.** The pool is picked from uniformly,
so `LookAround` and `ShiftWeight` are listed twice — the figure fidgets more
often than it performs, which is the right ratio for something a player has open
while reading a stat block.

Deliberately **not** an `AnimationTree`. A state machine earns its keep when
transitions are conditional and gameplay drives them; this is one state with a
random excursion out of it and straight back, and the whole director is twenty
lines.

**Rotation and gesture never interfere.** The player drags a `Node3D` pivot
*above* the doll; the clips move bones *inside* the skeleton. Turning the figure
mid-swing has always worked and needed no code — it is rendered in
`jiggle_shot` rather than asserted.

Three things had to be measured rather than assumed, and each cost a render:

- **The clip list was chosen by auditing all 43 as contact strips**
  (`tests/gesture_shot.tscn`), never off their names. `ClimbUp_1m`, `Shield_Dash`
  and the whole `Slide` family walk the figure clean out of frame;
  `Hit_Knockback` ends flat on its back below the bottom edge. None of that is
  visible in a name. The rule for inclusion is that a clip must **start and end
  near standing** — `Sword_Regular_A/B/C` are combo links that finish mid-swing,
  so only the assembled `_Combo` versions are used.
- **Every gesture must be a one-shot.** `animation_finished` never fires for a
  looping clip, so one loop in the table does not misbehave, it stops the
  director **dead** and the figure freezes on the last thing it did. `self_check`
  asserts this, because Godot decides loop mode from a suffix it then strips, so
  you cannot read it off the table.
- **The travel is on `pelvis`, not `root`.** That rules out
  `root_motion_track`, which would strip the whole track — and the pelvis track
  is not only travel, it carries the crouch and the weight drop. `PlantFeet`
  returns X and Z to the bind pose each frame and leaves Y alone, so the hero
  still lunges without ending up somewhere else.

Even planted, a combo reaches a foot above the hero's own head, so the Gear
page's camera margin was swept against its real 230x336 frame: 0.54 and 0.62
both crop the blade, **0.70** is the first value where nothing touches an edge,
0.78 buys nothing more. The resting figure pays about a fifth of its size — the
right way round, since a smaller hero reads fine and a beheaded one reads as a
bug. The board token and forge preview keep their tighter margins; they never
gesture.

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

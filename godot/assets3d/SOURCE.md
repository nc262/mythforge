# The character assets — all CC0, all one rig

Downloaded 2026-08-05 from Quaternius (https://quaternius.com), **CC0 / public
domain, no attribution required, commercial use fine**.

| Folder | Pack | What |
|---|---|---|
| `bodies/` | Universal Base Characters | Base bodies, plus 5 hairstyles and a beard rigged to the head bone |
| `outfits/` | Modular Character Outfits – Fantasy | Per-slot garments: Body, Arms, Legs, Feet, Head_Hood, Pauldrons |
| `anim/` | Universal Animation Library 2 | 43 situational clips, already on the 65-bone skeleton |
| `anim/UAL1_Retargeted.glb` | Universal Animation Library **1** | 43 more, **retargeted** here from Rigify — see below |
| `anim/Authored.glb` | **none — written here** | 9 emotes no free library ships |
| `weapons/` | Fantasy RPG weapons | Rigid props for the hand bones — no skin weights needed |

`cloth/` and `anim/Authored.glb` are the exceptions: they are **made here, not
downloaded**. Four tileable
weaves poured by `scripts/pour_materials.py` for the world families the outfit
pack does not dress, plus the shader that pours them. See
[docs/CharacterRender.md](../docs/CharacterRender.md).

## Why these three and not the ones already in `spike3d/`

**Three incompatible rigs were measured before anything was committed:**

| Rig | Bones | Naming |
|---|---|---|
| KayKit Adventurers (`spike3d/models`) | 41 | `hips`, `upperarm.l`, `handslot.l` |
| Quaternius Universal Animation Library (`spike3d/models`) | 53 | Rigify `DEF-hips`, `DEF-upper_arm.L` |
| **These three packs** | **65** | Unreal-style `pelvis`, `spine_01`, `Head` |

Bodies, every modular garment, and the animation library all share **65 bones at
100 %** — verified by loading each and comparing bone names, not by trusting the
"Humanoid Rig, retargetable" line on the store page. Against the older rigs they
share exactly **1** bone (`root`).

So a garment from `outfits/` drops onto a body from `bodies/` and is driven by a
clip from `anim/` with nothing in between. That is the whole reason to prefer
this family over the KayKit knight, which is now only a test fixture.

## The hair

`bodies/Hairstyles/Rigged to Head Bone/` holds **five cuts and a beard**, each
skinned to the same 65 bones as everything else — so they are worn through the
same code path the wardrobe uses, with nothing new underneath. Eyebrows and eyes
are NOT among them: the bodies already carry both as their own meshes, and
wearing the pack's standalone brow meshes as well gives every hero two sets.

`Hair_Buzzed` and `Hair_BuzzedFemale` are **one cut authored twice**, not two
styles — the same 466-vertex shell, 43 mm apart, because the female head is
43 mm lower. Offered as separate choices, whichever was cut for the other body
sinks under the scalp and renders as bald.

The hair texture is authored near-white so any colour can multiply onto it,
which means the TINT IS THE HAIR COLOUR and leaving it bright is not "as
authored" — it is platinum. The first render of this gave a party of
silver-haired seventy-year-olds.

## The second animation library, and why it needed baking

UAL2 is a SITUATIONAL set — farming, fishing, zombies, sword combos, a phone
call. It has **no neutral idle at all**, which is why the Gear page used to stand
in a sword guard whether or not a sword was held, and nothing for a hero who
casts.

UAL1 has the plain idles, a four-clip spell set, punches, a hop and a dance. Same
author, same CC0 licence, and it was **already in `spike3d/models`** — but as
`AnimationLibrary_Godot_Standard.gltf`, which is the **Rigify** export: 53 bones
named `DEF-hips`, `DEF-upper_arm.L`. It shares exactly one bone (`root`) with the
65-bone rig everything else uses, so its clips did nothing at all — silently,
because Godot matches tracks by name and a track that resolves to nothing is not
an error.

`scripts/retarget_anim.py` bakes it onto the shipping rig. The mapping is 1:1
(hips + three spines + neck + head, shoulders off the last spine), and the
transfer is the delta from rest rather than the world rotation — copying world
rotations directly twists every limb, because the two rigs roll their arm bones
differently. Output is `anim/UAL1_Retargeted.glb`, 3.2 MB, 43 clips, attached as
a second named animation library so the two `A_TPose` clips do not collide.

## The emotes nobody ships

Between them the two libraries give **86 clips and not one wave, shrug, bow or
look-around**. They are locomotion and task libraries — running, farming,
fishing, swimming, zombie walks — and the social emotes a character needs while
standing still are simply not in them. The free mocap sets that do have gestures
are thousands of clips of walking with a few usable seconds buried inside; the
good hand-made packs want an account or money.

A wave is eight keyframes on four bones. `scripts/author_gestures.py` writes
nine — Wave, Shrug, Bow, Cheer, Stretch, Beckon, LookAround, HandsOnHips,
ShiftWeight — straight onto the shipping rig, 0.9 MB.

Two things make that tractable and neither was guessed. The bone axes were
**measured** by rotating each 40° and asking where its tail went (`Y` is the
bone's own length and does not move it; `X+` swings forward; `Z+` raises the
LEFT arm and lowers the RIGHT). And the base pose is **borrowed** — the rig's
rest is a T-pose, so a gesture authored from rest opens with the arms straight
out sideways; frame 0 of the retargeted `Idle_Loop` is a person standing with
their arms down, so that is sampled and every gesture is a delta on top, which
also means each clip starts and ends exactly where the idle lives.

The numbers came off two rendered passes, not one. The first draft's Beckon and
ShiftWeight were invisible and its Wave reached only chest height.

## What was left out, and why

- **FBX and OBJ exports** — the glTF (Godot) export is the one Godot imports.
- **Normal, ORM, AO and roughness maps** — the character shader is toon: it bands
  the diffuse term and samples albedo only, so those maps are never read. They
  were 10–13 MB each.
- **`UAL2_Standard_RM.glb`** — the root-motion variant. A figurine on a stand
  never travels, so the in-place set is the right one.
- **Every texture above 1024 px was downsampled to 1024.** The figurine renders
  at 256 px and the Gear page at 230×336; 4K albedo is more than the eye is ever
  given. This took the folder from **244 MB to 65 MB** with no visible change.

Textures are referenced by filename from inside each `.gltf`, so they cannot
simply be deleted — dropping a normal map does not save space, it breaks the
import. That was found the direct way, by breaking it.

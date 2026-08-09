# Figurine — session handoff, 2026-08-07

Where the 3D character work actually stands, what is committed, what is broken,
and the traps that cost a round each so nobody pays for them twice.

Branch `claude/keen-lovelace-1c04a9`. Read
[CharacterRender.md](CharacterRender.md) for the design; this is the state.

---

## The decision that blocked the next phase — settled

**The base body has no shape keys.** Measured, not assumed:
`Superhero_Male_FullBody` is 7,281 vertices / 12,566 faces, and
`o.data.shape_keys` is `None` on every mesh in it.

That used to block full body configuration entirely. It no longer does, because
the answer was not to find a body with morphs — it was to add **five bones**.

| Want | Works | How |
|---|---|---|
| Burly fighter | **Yes** | `apply_build` scales bones, and every garment is skinned to the same rig, so the clothes follow for free |
| Taller / shorter, broader, heavier | **Yes** | same mechanism |
| Visible bust, seat, paunch | **Yes** | `scripts/add_jiggle_bones.py` adds `breast_l/r`, `glute_l/r`, `belly` to the body and all 23 garments; the Chest / Seat / Belly knobs scale them |
| Jiggle | **Yes** | the *same* five bones, simulated by `SpringBoneSimulator3D` on the Gear page |

One rig change bought both halves, which is why it was worth doing rather than
swapping the base body and re-fitting the whole wardrobe.

### And the surface split, also settled

**The board token is a held frame; the Gear page runs.** The token is rendered
once per loadout into an `ImageTexture` and the board repaints freely over it;
the page the player is looking at gets a looping idle and live springs, and stops
both the moment it is hidden. `stand()` and `live()` are the two entry points and
they are deliberately not the same call.

## What is committed and working

| Commit | What |
|---|---|
| `f11d147` | **Hidden surface removal** — the skin under the cloth is not drawn |
| `c346a4c` | Garment forge: subdivision, girth bands, shrinkwrap fit |
| `4f8a6f5` | MSAA 8x + FXAA at 1280 in `doll_shot`; the cloth-swell era (now deleted) |
| `35886d0` | `garment_forge.py` — deform the pack's garments into new ones |
| `edd7df3` | `garment_probe.py` — proves a garment survives Blender with its skin |
| `fea04cc` | The world's poured cloth for cyber / everyday / space / steam |

All three offline harnesses pass: `self_check`, `click_driver`, `ui_playthrough`.
Desktop build is current.

### The tools, and where they live

| Tool | Does |
|---|---|
| `scripts/bake_body_masks.py` | Bakes the per-garment coverage mask. **Owns the coverage rule** — `figurine_render.py` imports `covered_vertices` from it rather than copying, deliberately |
| `scripts/garment_forge.py` | `measure` / `fit` / `build`. Deforms pack garments into new ones |
| `scripts/garment_probe.py` | Round-trips a garment and asserts the skin survived |
| `scripts/figurine_render.py` | Path-traces the figurine in Cycles as a painted miniature |
| `scripts/pour_materials.py` | Generates the tileable world cloths |
| `scripts/retarget_anim.py` | Bakes an animation library from another rig onto this one. The route for ANY new humanoid clips |
| `scripts/author_gestures.py` | Writes the emotes no library ships, from keyframe tables. Bone axes are MEASURED, base pose BORROWED off the idle |
| `scripts/add_jiggle_bones.py` | Adds the five soft-tissue bones to the body and all 23 garments, and weights them. **Rewrites the .gltf files in place.** Run once per sex |

Binaries, because neither is on PATH and one is not installed at all:

```
C:\Users\cptahabb\Documents\Code\blender\blender-5.2.0-windows-x64\blender.exe
%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe
```

Blender is a **portable unzip**, not an install: `download.blender.org` returns
403 from this machine, so it came from the Berkeley OCF mirror.

---

## What is broken or unfinished

1. **The Cycles render is in bind pose.** `figurine_render.py` never loads
   `assets3d/anim/UAL2_Standard.glb`, so the figure stands with its arms out.
   The doll's `stand()` picks `Sword_Block` from a preference list; the same
   clip needs applying here.
2. **One sliver of skin on the right calf**, where the boot's top rim and the
   trouser hem overlap and each exempts the other's neighbourhood.
3. **The normal / ORM / roughness maps were deleted**, and that was a mistake:
   `SOURCE.md` justifies it with "the character shader is toon", but the toon
   shader was a spike that never shipped and the doll renders standard PBR. Every
   surface is flat albedo with shader-level roughness only. Re-fetch them.
4. **Textures were downsampled to 1024** with "no visible change" — true at
   230x336 on the Gear page, false at 1280 and false in Cycles.
5. **The emotes are hand-keyframed, and read as it.** Nine of them, authored
   because no free library ships a wave, and they hold up at Gear-page size —
   but they are 4–7 poses interpolated, with none of the settle, overlap or
   secondary motion mocap gives you for free. The route to better is more keys
   per clip in `author_gestures.py`, or a mocap set through
   `retarget_anim.py`, which now takes any humanoid library on any rig.

Closed since the last handoff: the masks were stale (re-baked, all 23, with the
side-aware rim rule) and `figurine_render.py` was uncommitted.

## Traps, each of which cost a round

**Coverage — "is this vertex inside the garment" is the wrong question.** Skin
that pokes through is *by definition outside* the cloth, so an inside test
excludes precisely the vertices causing the bug. It changed the count by 31 out
of 7,281. Proximity regardless of side is the answer.

**But proximity lies at a garment's OPEN EDGE.** A neck vertex well above a high
collar is still within 3.5 cm of that collar's rim, so the figurine loses its
neck. Rejecting every rim hit swings past it — the tunic's laced front placket
is an open edge too, so the whole chest gets exempted and the bare torso
returns. The rule that works is **side-aware**: reject a rim hit only when the
skin is on the outward side of it. Face counts across the three versions:
10,182 (no rim rule) → 8,576 (reject all rims) → 9,610 (side-aware).

**Never `face.select` then `bpy.ops.mesh.delete(type="FACE")`.** Selecting a face
in object mode also selects its vertices, and the operator then deletes every
face whose corners are selected — it cascades far past what was asked. Use
`bmesh.ops.delete`.

**Carving geometry strands islands.** Scraps in the armpit that no garment
covered but that are now attached to nothing. Sweep islands under ~40 faces —
but **only on meshes that were actually carved**, or it deletes the eyes and the
eyebrows, which are small separate meshes legitimately made of little islands.

**`Skin` is not the autoload for `skin.gd` — `Ui` is.** Getting it wrong is a
*parse* error, and a Godot harness with a parse error hangs forever instead of
failing. `--check-only --script` catches it, but does not register autoloads, so
it reports every autoload as "identifier not found" — that part is the checker's
limit, not your code.

**Running the project does not import new assets.** `--headless --path <p>
--import` does. Without it the game silently sees no texture and no mask.

**Read the render, not the log.** Two runs printed the same face count and I
concluded a fix had not worked. It had; I never reopened the image.

**A gesture that loops does not misbehave, it stops the director dead.**
`animation_finished` never fires for a looping clip, so the figure freezes on
the last thing it did and never idles again. Which clips loop is not readable
from the table, because Godot sets loop mode from a `_Loop` suffix it strips —
so `self_check` asserts every gesture clip exists AND ends.

**Cycles on this machine:** `HIP` is the working compute device, and the AgX look
is named `AgX - Base Contrast` — `AgX - Medium Contrast` does not exist and
throws.

**The clip names in Blender are not the clip names in Godot.** UAL2 ships
`Idle_Shield_Loop`; Godot's glTF importer reads the `_Loop` suffix as a loop-mode
hint, sets the mode from it and STRIPS IT FROM THE NAME. A preference list
written off the Blender clip list matches nothing and says nothing — the figure
keeps whatever pose it already had, which looks like a decision. Half a round
went into "why is `live()` not playing", and the original list had been right.

**You cannot diff two runs of a real-time animation.** Springs-on and springs-off
never land on the same phase, so the difference image is a glowing outline of the
whole figure and the jiggle is buried inside it. Freeze the pose and turn the
figure instead: springs-off is then perfectly static and every moving pixel is
the simulation.

**Adding a vertex group is only half of adding a weight.** Skinning is a weighted
average, so the joints already holding that vertex have to give up exactly as
much as the new bone takes. Skip the rescale and the mesh does not tear, it
DRIFTS — and it drifts more every time the script is re-run, which is why
`paint()` drops any previous pass and re-normalises before it starts.

---

## Measured numbers worth keeping

| Fact | Value |
|---|---|
| Body | 7,281 verts, 12,566 faces, **no shape keys** |
| Shared skeleton | 65 bones, 100 % across bodies, garments and the animation library |
| Garment density | legs 656 · body 2,825 · arms 3,315 · boots 10,174 — wildly uneven, which is why the trousers read as a faceted tube until subdivided to 3,534 |
| Coverage, full ranger kit | 5,906 / 7,281 vertices = 81 %. That is correct — a dressed figure is mostly cloth |
| Cloth pour | fold metric: flat weave 2–7, folded garment 24–38, nothing between |
| Figurine tiling | 2.5 object-space repeats, chosen off a rendered sweep |

---

## If picking this up cold

1. Pose the Cycles render — it is the only thing still standing in bind pose.
2. Re-fetch the normal / ORM maps and the full-resolution textures.
3. Give `live()` more than one clip.

**Never edit the asset .gltf files by hand.** `scripts/add_jiggle_bones.py`
rewrites all 25 of them IN PLACE, with `export_keep_originals` so the PNGs beside
them are untouched. Re-running it is safe — it drops any previous pass and
re-normalises first — but hand edits will be overwritten.

# Figurine — session handoff, 2026-08-07

Where the 3D character work actually stands, what is committed, what is broken,
and the traps that cost a round each so nobody pays for them twice.

Branch `claude/keen-lovelace-1c04a9`. Read
[CharacterRender.md](CharacterRender.md) for the design; this is the state.

---

## The decision that blocks the next phase

**The base body has no shape keys.** Measured, not assumed:
`Superhero_Male_FullBody` is 7,281 vertices / 12,566 faces, and
`o.data.shape_keys` is `None` on every mesh in it.

That is the whole gate on full body configuration:

| Want | Works today | Why |
|---|---|---|
| Burly fighter | **Yes** | `apply_build` scales bones, and every garment is skinned to the same 65 bones, so the clothes follow for free |
| Taller / shorter, broader, heavier | **Yes** | same mechanism |
| Visible bust, glutes, muscle definition | **No** | those are *surface shape*, not bone scale. This rig has no bones for them and the body has no morphs to blend |

The `chest` knob scales `spine_03`, which widens a whole ribcage. It broadens a
torso; it does not sculpt a bust. Do not let the slider imply otherwise.

**So the first question next session is whether to keep this base body at all.**
"Burly fighters and curvaceous bards" is a body-with-morphs requirement, and
this body has none. Everything below is still useful either way — the coverage
rule, the forge and the render path are body-agnostic — but the wardrobe fit and
the masks are baked per body and would be redone.

### And a tension to resolve before building anything

**Jiggle physics and offline path-traced quality pull in opposite directions.**
The figurine went offline into Cycles *because* it is static — that is what buys
the lighting and the subdivision. Jiggle is a real-time simulation of something
moving. You can have:

- a **cached path-traced still** — best quality, no motion of any kind, or
- a **real-time posed figure** with spring bones and jiggle — motion, at the
  fidelity Godot's forward renderer gives, which is what was rejected, or
- **both, on different surfaces** — the Gear page live and jiggling, the board
  token and scene hero pre-rendered.

The third is the only one that gets both, and it is a real decision, not a
detail. Godot 4 has `PhysicalBoneSimulator3D` for the real-time half; there are
no jiggle bones in this rig today, so they would have to be added to the
skeleton and weighted, which is a rig change and therefore a garment change.

---

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
3. **The in-game masks are stale.** The side-aware rim fix landed in
   `bake_body_masks.py` *after* the 19 masks were baked, so
   `assets3d/masks/*.png` still carry the old rule — they hide the neck. Re-bake
   before shipping.
4. **The normal / ORM / roughness maps were deleted**, and that was a mistake:
   `SOURCE.md` justifies it with "the character shader is toon", but the toon
   shader was a spike that never shipped and the doll renders standard PBR. Every
   surface is flat albedo with shader-level roughness only. Re-fetch them.
5. **Textures were downsampled to 1024** with "no visible change" — true at
   230x336 on the Gear page, false at 1280 and false in Cycles.
6. **`scripts/figurine_render.py` is uncommitted**, along with the rim fix in
   `bake_body_masks.py`.

---

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

**Cycles on this machine:** `HIP` is the working compute device, and the AgX look
is named `AgX - Base Contrast` — `AgX - Medium Contrast` does not exist and
throws.

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

1. Re-bake the masks (the rim fix is in the script, not in the PNGs).
2. Commit `figurine_render.py`.
3. Decide the base body — that gates full body configuration entirely.
4. Decide the live-vs-baked split before touching jiggle, because it decides
   whether the figurine is a cached still or a simulated one.

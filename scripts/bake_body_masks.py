"""Bake a HIDDEN-SURFACE mask per garment: which skin does this piece cover?

THE TECHNIQUE, and it is the one production modular-character systems use.
The body under a shirt is not pushed away from the cloth — it is not drawn at
all. Reallusion's Character Creator ships it as the Hide Body Mesh tool and
stores the visibility ON THE GARMENT, to be reapplied whenever that garment is
worn; Roblox patented the same thing for layered avatar clothing; WoW calls the
pieces geosets; VRoid calls the texture a skin mask.

It matters that this is not a tuning improvement over pushing the cloth out. It
is a different KIND of answer. Shrinkwrap and a swelled garment both enforce
separation in ONE pose, and skinning then moves the two surfaces by different
weights, so every new pose is a fresh chance to interpenetrate — which is
exactly what happened here: the thigh cleared and the knee tore. Absent
geometry cannot poke through anything, in any pose, ever. If it needs tuning to
survive standing still it cannot survive animation.

The body is a single mesh, so the geometry-splitting variant is unavailable and
this is the mask variant: a greyscale image in the body's own UV layout, white
where the skin is covered. The body shader discards those fragments.

COVERAGE TEST. For each body vertex, cast a ray along its own outward normal and
ask whether it hits the garment within a short distance. That phrasing is chosen
for open surfaces: a garment is a tube, open at the neck, cuffs and hem, so
"inside the mesh" is not defined for it, while "there is cloth directly outside
this piece of skin" always is. The distance cap is what stops a ray from the
chin registering the trousers it eventually reaches.

    blender --background --python scripts/bake_body_masks.py -- <body.gltf> <out_dir> <garment.gltf...>
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

PX = 512
## How far outside a piece of skin cloth may be and still count as covering it.
## In body units, where the figure is ~1.75 tall — so about 6 cm. Too small and
## a loose sleeve stops hiding the arm inside it; too large and the ray from a
## shoulder finds the trousers.
MAX_DIST = 0.06
## How close cloth has to be for the skin to count as covered.
##
## THIS IS THE WHOLE FIX FOR THE NECK, and it took a control render to see.
## Hidden-surface removal exists to stop skin poking THROUGH cloth, and skin only
## pokes through where the cloth is TIGHT. A collar stands 2-3 cm off the throat
## and a hood a good 4 cm off the skull: nothing pokes through either, so neither
## needs a single vertex deleted — and deleting them is what left a ragged hole
## under the jaw with the inside of the collar showing through it.
##
## Tightening this to 1.2 cm did save the neck, and put the legs straight
## through the trousers: loose cloth that genuinely covers still has to mask, so
## distance alone cannot separate the two cases. The NECK LINE below does.
##
## The side test is the trap, and it cost a whole bake to see: an "is this
## vertex inside the garment" check excludes precisely the vertices that cause
## poke-through, because skin that pokes through is by definition OUTSIDE the
## cloth. Hiding only the properly-tucked-in skin fixes nothing visible.
##
## So proximity regardless of side — but CLOSE proximity, not generous.
## Overridable, and only because a SECOND body proved one value does not serve
## both. The rule below assumes skin sits inside cloth and pokes through where
## the cloth is tight — true of a garment modelled against the body wearing it,
## and false of a garment refitted onto a different torso, where the skin can
## stand clear OUTSIDE the cloth and never come within 3.5 cm of it. The
## shipping body keeps 0.035; a candidate can be baked and MEASURED at another
## value (tests/body_audit.tscn, goal G6) instead of the number being argued
## about.
NEAR = float(os.environ.get("MASK_NEAR", "0.035"))
## Pixels of dilation. The mask is sampled per fragment, so a boundary that is
## exactly right in UV space still shows a rim of skin where a texel straddles
## the garment's edge. Growing it closes that without eating visible skin.
GROW = 2


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def skinned(objs) -> list:
    return [o for o in objs if o.type == "MESH" and o.vertex_groups]


def biggest(objs):
    best = None
    for o in skinned(objs):
        if best is None or len(o.data.vertices) > len(best.data.vertices):
            best = o
    return best


def _import(path: str) -> list:
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in keep]


def neck_line(objs) -> float:
    """Height of the base of the neck, from the rig rather than from a guess.

    NOTHING IN THIS WARDROBE COVERS A THROAT. Not the tunics, whose collars stand
    2-3 cm clear of it, and not the hood, which is a shell around the skull with
    its whole front open. So no garment may delete a single vertex above this
    line, and the entire class of "the hero has no neck" bugs stops being
    reachable.

    That is a stronger statement than any distance rule, and it is the one that
    is actually true: a rule tuned to spare the throat let the legs through the
    trousers, and a rule tuned to catch the legs ate the throat. This is not a
    threshold to be balanced, it is a region to be excluded.

    Taken from `neck_01`, so a different body of a different height carries its
    own line with it.
    """
    for o in objs:
        if o.type != "ARMATURE":
            continue
        b = o.data.bones.get("neck_01")
        if b is not None:
            return (o.matrix_world @ b.matrix_local).translation.z
    return 1e9


def covered_vertices(body, garment, above: float = 1e9) -> np.ndarray:
    """Boolean per body vertex: is this skin underneath this garment?

    TWO tests, because either alone is wrong.

    The RAY along the vertex's own outward normal answers "is there cloth
    directly outside this skin". On its own it is far too strict: it only fires
    where the cloth happens to sit along that exact normal, and the first bake
    caught 562 of 7281 vertices under a full tunic and produced a mask with
    holes in the middle of the chest.

    PROXIMITY fills those in — and proximity is where the neck was lost.

    THE NECK, AND WHY TWO EARLIER RULES COULD NOT SAVE IT. A vertex on the throat
    sits a couple of centimetres above a high collar, well clear of any cloth,
    and is still within 3.5 cm of that collar's rim. Proximity alone therefore
    calls it covered and the figurine's head sits straight on its shoulders.

    Rejecting every hit that lands on a rim face swings past it: the tunic's
    laced front placket is an open edge too, so the whole chest gets exempted and
    the bare torso comes back. Rejecting rim hits only from the OUTWARD side —
    which is what shipped, and which measured 100 % of the male neck still
    eaten — cannot work either, because a collar is a TUBE: skin above it is
    inside that tube's radius, so the side test reads "under cloth" and the
    exemption never fires at all.

    WHAT THIS DELIBERATELY NO LONGER DOES is reason about rims, sides or
    enclosure. Three rules were written to stop proximity eating the throat — a
    rim exemption, a side-aware rim exemption, and a fan of rays measuring how
    enclosed each vertex is — and each one either still ate the neck or started
    putting the legs through the trousers. They were all attacking a general
    problem to fix a specific one.

    `neck_line` fixes the specific one, exactly and permanently. With the throat
    excluded by REGION there is nothing left for a clever proximity rule to
    solve, so the clever proximity rules are gone and this is back to the two
    tests that always worked on the body.
    """
    # LOCAL space throughout. Every mesh in this pack is authored against the
    # same origin — `measure` and `fit` both compare raw vertex coordinates and
    # get coherent numbers — and the world matrices were checked and are
    # identity, so this is the same frame either way and the simpler one.
    n = len(body.data.vertices)
    out = np.zeros(n, dtype=bool)
    for i, v in enumerate(body.data.vertices):
        o = v.co
        if o.z >= above:
            continue      # the throat and the head: see `neck_line`
        d = Vector(v.normal).normalized()
        # Start a hair off the skin so a coincident surface does not self-hit.
        if garment.ray_cast(o + d * 0.0005, d, distance=MAX_DIST)[0]:
            out[i] = True
            continue
        ok, loc, _nrm, _face = garment.closest_point_on_mesh(o, distance=NEAR)
        out[i] = ok and (o - loc).length <= NEAR
    return out


def rasterize(body, covered: np.ndarray, px: int) -> np.ndarray:
    """Paint covered triangles into the body's UV layout.

    A triangle counts as covered when ANY of its three corners is, and it is
    filled solid. Interpolating instead would leave a soft edge that the
    shader's threshold turns back into a ragged boundary — the exact artefact
    the whole exercise is removing.
    """
    mesh = body.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active
    if uv is None:
        raise SystemExit("the body has no UV layer to bake into")
    img = np.zeros((px, px), dtype=np.uint8)

    ys, xs = np.mgrid[0:px, 0:px]
    for tri in mesh.loop_triangles:
        if not any(covered[vi] for vi in tri.vertices):
            continue
        p = np.array([[uv.data[li].uv[0] * (px - 1),
                       (1.0 - uv.data[li].uv[1]) * (px - 1)] for li in tri.loops])
        x0, y0 = np.floor(p.min(axis=0)).astype(int)
        x1, y1 = np.ceil(p.max(axis=0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, px - 1), min(y1, px - 1)
        if x1 < x0 or y1 < y0:
            continue
        sx, sy = xs[y0:y1 + 1, x0:x1 + 1], ys[y0:y1 + 1, x0:x1 + 1]
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w0 = ((by - cy) * (sx - cx) + (cx - bx) * (sy - cy)) / den
        w1 = ((cy - ay) * (sx - cx) + (ax - cx) * (sy - cy)) / den
        inside = (w0 >= -0.002) & (w1 >= -0.002) & (w0 + w1 <= 1.002)
        img[y0:y1 + 1, x0:x1 + 1][inside] = 255
    return img


def grow(img: np.ndarray, px_amount: int) -> np.ndarray:
    out = img.copy()
    for _ in range(px_amount):
        m = out
        out = np.maximum.reduce([
            m,
            np.roll(m, 1, 0), np.roll(m, -1, 0),
            np.roll(m, 1, 1), np.roll(m, -1, 1),
        ])
    return out


def save(img: np.ndarray, path: str) -> None:
    px = img.shape[0]
    im = bpy.data.images.new("mask", px, px, alpha=False)
    rgb = (img.astype(np.float32) / 255.0)
    # Blender images are bottom-up and RGBA float.
    flat = np.zeros((px, px, 4), dtype=np.float32)
    flat[..., 0] = flat[..., 1] = flat[..., 2] = rgb[::-1]
    flat[..., 3] = 1.0
    im.pixels.foreach_set(flat.ravel())
    im.file_format = "PNG"
    im.filepath_raw = path
    im.save()
    bpy.data.images.remove(im)
    # AND CHECK IT LANDED. `Image.save()` with a RELATIVE filepath writes
    # nothing and says nothing — Blender resolves it against the blend file,
    # which in a --background run is nowhere. Three separate rules were baked,
    # measured and rendered against masks four days old before this was noticed,
    # because every step in between reported success.
    if not os.path.exists(path):
        raise SystemExit("mask was not written: %s" % path)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    body_path, out_dir, garment_paths = argv[0], os.path.abspath(argv[1]), argv[2:]
    os.makedirs(out_dir, exist_ok=True)

    for gp in garment_paths:
        clear()
        body_objs = _import(body_path)
        body = biggest(body_objs)
        above = neck_line(body_objs)
        garment_objs = skinned(_import(gp))
        if body is None or not garment_objs:
            raise SystemExit("missing body or garment in %s" % gp)
        cov = np.zeros(len(body.data.vertices), dtype=bool)
        for g in garment_objs:
            cov |= covered_vertices(body, g, above)
        img = grow(rasterize(body, cov, PX), GROW)
        stem = os.path.splitext(os.path.basename(gp))[0]
        dst = os.path.join(out_dir, stem + "_mask.png")
        save(img, dst)
        print("MASK %-34s %5d/%5d verts covered  %5.1f%% of texels"
              % (stem, int(cov.sum()), len(cov), 100.0 * (img > 127).mean()))


if __name__ == "__main__":
    main()

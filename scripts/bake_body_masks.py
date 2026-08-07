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
## How close cloth has to be for the skin to count as covered, REGARDLESS of
## which side of it that skin is on.
##
## The side test is the trap, and it cost a whole bake to see: an "is this
## vertex inside the garment" check excludes precisely the vertices that cause
## poke-through, because skin that pokes through is by definition OUTSIDE the
## cloth. Hiding only the properly-tucked-in skin fixes nothing visible.
##
## So proximity alone, and generously. Hiding a sliver of skin just beyond a
## hem is invisible — cloth is there. Leaving one poking vertex is the bug.
NEAR = 0.035
## Pixels of dilation. The mask is sampled per fragment, so a boundary that is
## exactly right in UV space still shows a rim of skin where a texel straddles
## the garment's edge. Growing it closes that without eating visible skin.
GROW = 3


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


def rim_faces(garment) -> set:
    """Faces touching an OPEN edge — the neck hole, the cuffs, the hem.

    A garment is a tube, and its openings are where the proximity test lies. A
    neck vertex sitting comfortably ABOVE a high collar is still within 3.5 cm
    of that collar's rim, so proximity alone calls it covered and the figurine
    loses its neck. Cuffs and hems fail the same way, just less visibly.

    An edge with one adjacent face is a border. Rejecting proximity hits that
    land on a border face draws the line where the cloth actually stops.
    """
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(garment.data)
    out = {f.index for e in bm.edges if len(e.link_faces) == 1 for f in e.link_faces}
    bm.free()
    return out


def covered_vertices(body, garment) -> np.ndarray:
    """Boolean per body vertex: is this skin underneath this garment?

    TWO tests, because either alone is wrong.

    The RAY along the vertex's own outward normal answers "is there cloth
    directly outside this skin", which is the right question for an open
    surface — a garment is a tube, open at neck, cuffs and hem, so "inside the
    mesh" is undefined for it. On its own it is far too strict: it only fires
    where the cloth happens to sit along that exact normal, and the first bake
    caught 562 of 7281 vertices under a full tunic and produced a mask with
    holes in the middle of the chest.

    The SIGNED DISTANCE fills those in. Take the closest point on the garment;
    if it is near, and this vertex lies BEHIND the garment's surface there, the
    skin is inside the cloth. That is the standard cloth-body interpenetration
    test, and it does not care which way the vertex happens to face.

    Either one is enough to hide the skin. Hiding a little too much is
    invisible; hiding too little is the bug being fixed.
    """
    # LOCAL space throughout. Every mesh in this pack is authored against the
    # same origin — `measure` and `fit` both compare raw vertex coordinates and
    # get coherent numbers — and the world matrices were checked and are
    # identity, so this is the same frame either way and the simpler one.
    n = len(body.data.vertices)
    out = np.zeros(n, dtype=bool)
    rim = rim_faces(garment)
    for i, v in enumerate(body.data.vertices):
        o = v.co
        d = Vector(v.normal).normalized()
        # Start a hair off the skin so a coincident surface does not self-hit.
        if garment.ray_cast(o + d * 0.0005, d, distance=MAX_DIST)[0]:
            out[i] = True
            continue
        ok, loc, nrm, face = garment.closest_point_on_mesh(o, distance=NEAR)
        if not ok or (o - loc).length > NEAR:
            continue
        # Proximity to a garment's OPEN EDGE does not mean covered — but only
        # from the outside of it. Skin inside a collar is under cloth and must
        # go; skin above the collar is bare and must stay, and both are within
        # 3.5 cm of the same rim.
        #
        # Rejecting every rim hit outright was tried and swings too far the
        # other way: the tunic's laced front placket is an open edge too, so the
        # whole chest was exempted and the bare torso came back.
        if face in rim and (o - loc).dot(nrm) > 0.0:
            continue
        out[i] = True
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


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    body_path, out_dir, garment_paths = argv[0], argv[1], argv[2:]
    os.makedirs(out_dir, exist_ok=True)

    for gp in garment_paths:
        clear()
        body = biggest(_import(body_path))
        garment_objs = skinned(_import(gp))
        if body is None or not garment_objs:
            raise SystemExit("missing body or garment in %s" % gp)
        cov = np.zeros(len(body.data.vertices), dtype=bool)
        for g in garment_objs:
            cov |= covered_vertices(body, g)
        img = grow(rasterize(body, cov, PX), GROW)
        stem = os.path.splitext(os.path.basename(gp))[0]
        dst = os.path.join(out_dir, stem + "_mask.png")
        save(img, dst)
        print("MASK %-34s %5d/%5d verts covered  %5.1f%% of texels"
              % (stem, int(cov.sum()), len(cov), 100.0 * (img > 127).mean()))


if __name__ == "__main__":
    main()

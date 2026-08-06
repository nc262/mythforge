"""Author garments by EDITING the pack's, which is what keeps the skin.

The CC0 outfit pack is fantasy and there is no CC0 sibling for any other genre,
so the non-fantasy wardrobe has to be made. Generating a mesh is the obvious
route and the wrong one: a generated mesh arrives unrigged, unfitted, unsplit
and with blob topology, so the cheap part is done and every expensive part —
skin weights onto a 65-bone rig — is still ahead.

The pack's garments are ALREADY skinned to that rig. So every garment here is a
DEFORMATION of one of them: vertices move, and nothing else does. Vertex groups,
weights, topology, UVs and the material are untouched by construction, which is
why `garment_probe.py` passing once is enough for all of them.

That is also the honest ceiling. Deformation can make a boot a shoe and a legging
a trouser; it cannot grow a collar that was never modelled. Where a cut needs
geometry that does not exist, it is not in the table.

    blender --background --python scripts/garment_forge.py -- measure <gltf...>
    blender --background --python scripts/garment_forge.py -- build <recipe> <in> <out>
"""
import sys

import bpy
from mathutils import Vector


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def garments() -> list:
    """The skinned meshes, which is the only kind this tool touches.

    Blender's glTF importer leaves an unskinned Icosphere behind on every
    import; a garment always carries vertex groups, so that is the filter.
    """
    return [o for o in bpy.data.objects if o.type == "MESH" and o.vertex_groups]


def measure(path: str) -> None:
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    print("\n### %s" % path.replace("\\", "/").split("/")[-1])
    for ob in garments():
        co = [v.co for v in ob.data.vertices]
        lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
        hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
        print("  %-30s verts %5d  x[%6.3f %6.3f]  y[%6.3f %6.3f]  z[%6.3f %6.3f]"
              % (ob.name, len(co), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        # Where the mass sits up the piece. A boot's shaft, a tunic's hem and a
        # sleeve's cuff are all "the part above height k", and k is not
        # guessable — it has to be read off the distribution.
        span = hi.z - lo.z
        if span > 1e-6:
            bins = [0] * 10
            for c in co:
                bins[min(9, int((c.z - lo.z) / span * 10))] += 1
            print("       z-profile %s" % " ".join("%3d%%" % (100 * b / len(co)) for b in bins))


# ── Deformation primitives ──────────────────────────────────────────────────
# Each moves vertices and nothing else. No vertex is added, removed, reordered
# or reweighted, which is what makes every garment here inherit the pack's skin
# for free — and what makes one passing round-trip probe cover all of them.


def _bounds(ob):
    co = [v.co for v in ob.data.vertices]
    return (min(c.z for c in co), max(c.z for c in co))


def _ramp(t: float) -> float:
    """Smooth 0..1, so a deformation blends in instead of creasing.

    A linear ramp leaves a visible hard ring where the affected band starts —
    on a trouser leg it reads as a seam that is not in the texture.
    """
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def taper_shaft(ob, z_cut: float, keep: float, pinch: float) -> None:
    """Turn a tall boot into a low shoe by collapsing its shaft onto the ankle.

    Everything above `z_cut` is pulled down into a band `keep` tall and squeezed
    inward by `pinch`, so the shaft becomes a cuff rather than a hole. Vertices
    are moved, never deleted: deleting them would leave the top of the shoe
    open, and would be the one edit that does change topology.
    """
    lo, hi = _bounds(ob)
    if hi <= z_cut:
        return
    span = hi - z_cut
    for v in ob.data.vertices:
        if v.co.z <= z_cut:
            continue
        t = (v.co.z - z_cut) / span
        v.co.z = z_cut + keep * span * t
        s = 1.0 - (1.0 - pinch) * _ramp(t)
        v.co.x *= s
        v.co.y *= s


def stretch_down(ob, new_bottom: float, from_z: float) -> None:
    """Lengthen a garment downward — a legging becomes a full trouser.

    Only the part below `from_z` moves, and it is remapped rather than
    translated, so the waist stays exactly where the body expects it.

    The weights at the new hem still belong to the calf rather than the ankle,
    because weights are deliberately not touched. On a figurine in a held stance
    that is invisible; it would show as slightly stiff cloth on a walk cycle,
    which this doll does not have.
    """
    lo, hi = _bounds(ob)
    if from_z <= lo or new_bottom >= lo:
        return
    for v in ob.data.vertices:
        if v.co.z >= from_z:
            continue
        t = (from_z - v.co.z) / (from_z - lo)   # 0 at from_z, 1 at the old hem
        v.co.z = from_z - t * (from_z - new_bottom)


def girth(ob, z_lo: float, z_hi: float, factor: float) -> None:
    """Widen or narrow a band, about the piece's own centre line at that height.

    About the CENTRE, not the origin: a trouser leg sits off to one side of x=0,
    so scaling about the origin moves both legs apart instead of making either
    baggier. That was the first version and it produced a man doing the splits.
    """
    co = [v.co for v in ob.data.vertices]
    band = [c for c in co if z_lo <= c.z <= z_hi]
    if not band:
        return
    # Two centres, one per side, so a paired piece stays paired.
    left = [c for c in band if c.x < 0.0]
    right = [c for c in band if c.x >= 0.0]
    cl = sum((c.x for c in left), 0.0) / len(left) if left else 0.0
    cr = sum((c.x for c in right), 0.0) / len(right) if right else 0.0
    cy = sum((c.y for c in band), 0.0) / len(band)
    for v in ob.data.vertices:
        if not (z_lo <= v.co.z <= z_hi):
            continue
        # Feather by depth into the band so the change has no hard edge.
        d = min(v.co.z - z_lo, z_hi - v.co.z) / max((z_hi - z_lo) * 0.5, 1e-6)
        f = 1.0 + (factor - 1.0) * _ramp(d)
        cx = cl if v.co.x < 0.0 else cr
        v.co.x = cx + (v.co.x - cx) * f
        v.co.y = cy + (v.co.y - cy) * f


OPS = {"taper_shaft": taper_shaft, "stretch_down": stretch_down, "girth": girth}

# ── Recipes ─────────────────────────────────────────────────────────────────
# Numbers are in the body's own units, where the figure is ~1.75 tall, the feet
# sit at 0 and the waist is ~1.05. They come from `measure`, not from taste.
RECIPES = {
    # The peasant "feet" piece is a mid-calf boot (z to 0.448). Everyday, cyber
    # and space all want a shoe, which tops out at the ankle, ~0.12.
    "shoes": [("taper_shaft", {"z_cut": 0.115, "keep": 0.10, "pinch": 0.82})],
    # Leggings stop at mid-calf (0.403) because a fantasy boot covers the rest.
    # With a shoe underneath that leaves a bare shin, so the trouser has to run
    # to the ankle on its own.
    "trousers": [
        ("stretch_down", {"new_bottom": 0.105, "from_z": 0.70}),
        ("girth", {"z_lo": 0.15, "z_hi": 0.80, "factor": 1.30}),
    ],
    "trousers_slim": [
        ("stretch_down", {"new_bottom": 0.105, "from_z": 0.70}),
        ("girth", {"z_lo": 0.15, "z_hi": 0.80, "factor": 1.06}),
    ],
    # A flight suit is the same trouser held tight to the leg.
    "suit_legs": [
        ("stretch_down", {"new_bottom": 0.115, "from_z": 0.70}),
        ("girth", {"z_lo": 0.15, "z_hi": 0.90, "factor": 0.94}),
    ],
}


def build(recipe: str, src: str, dst: str) -> None:
    if recipe not in RECIPES:
        raise SystemExit("unknown recipe: %s (have %s)" % (recipe, ", ".join(sorted(RECIPES))))
    clear()
    bpy.ops.import_scene.gltf(filepath=src)
    targets = garments()
    if not targets:
        raise SystemExit("no skinned mesh in %s" % src)
    for ob in targets:
        before = _bounds(ob)
        for op_name, kw in RECIPES[recipe]:
            OPS[op_name](ob, **kw)
        ob.data.update()
        print("  %-28s z %.3f..%.3f -> %.3f..%.3f" % ((ob.name,) + before + _bounds(ob)))
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLTF_SEPARATE",
                              export_skins=True, export_animations=False)
    print("FORGE wrote %s (%s)" % (dst, recipe))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    if argv[0] == "measure":
        for p in argv[1:]:
            measure(p)
        return
    if argv[0] == "build":
        build(argv[1], argv[2], argv[3])
        return
    raise SystemExit("unknown mode: %s" % argv[0])


if __name__ == "__main__":
    main()

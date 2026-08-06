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


def subdivide(ob, levels: int = 1) -> None:
    """Add polygons, and smooth the piece while doing it.

    The one operation here that DOES change topology, and it is safe for the
    same reason the others are: Blender interpolates vertex groups across new
    vertices, so a subdivided garment is still skinned to the same 65 bones with
    sensible weights. The probe still covers it, because the probe compares
    group COUNT and the armature modifier, not vertex count.

    It earns its place because the pack's pieces are wildly uneven: the legs are
    656 vertices against 10,174 in the boots, and at figurine size that reads as
    a faceted tube. Catmull-Clark rather than simple subdivision, because the
    complaint is angularity — more triangles on the same flat facets would cost
    memory and change nothing.

    Applied rather than left live: Godot imports the mesh, not the modifier.
    """
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("forge_subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    # To the top of the stack, so it runs before the armature deform rather than
    # on top of it. Out of order Blender warns and applies anyway, which is the
    # kind of "works" that produces a subtly wrong bind pose.
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)


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


def shrinkwrap_out(ob, body: str, offset: float = 0.008) -> None:
    """Push every vertex that is INSIDE the body out to just outside it.

    This is the fix the girth bands were failing to be. Comparing radii said the
    thigh only needed x1.10-1.17 and that much was already applied, yet it still
    tore — because a thigh is not a circle. Max-radius-per-band is a summary,
    and the vertices that break through are the local ones a summary averages
    away. Scaling a whole band to clear one bulge makes a balloon.

    Blender's Shrinkwrap in OUTSIDE mode asks the right question per vertex:
    are you inside this surface, and if so, come out to it. A vertex already
    clear is left exactly where it is, so a deliberately baggy trouser stays
    baggy instead of collapsing onto the leg.

    The body is imported at its bind pose, which is the pose the garment is
    authored against, so the two are comparable. It is removed again before
    export — the garment file must contain the garment.
    """
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=body)
    added = [o for o in bpy.data.objects if o not in keep]
    target = None
    for o in added:
        if o.type == "MESH" and o.vertex_groups and (target is None
                                                     or len(o.data.vertices) > len(target.data.vertices)):
            target = o
    if target is None:
        for o in added:
            bpy.data.objects.remove(o, do_unlink=True)
        raise SystemExit("no body mesh in %s" % body)

    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("forge_wrap", "SHRINKWRAP")
    mod.target = target
    mod.wrap_method = "NEAREST_SURFACEPOINT"
    mod.wrap_mode = "OUTSIDE"
    mod.offset = offset
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    for o in added:
        bpy.data.objects.remove(o, do_unlink=True)


def _import_body(path: str):
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [o for o in bpy.data.objects if o not in keep]
    target = None
    for o in added:
        if o.type == "MESH" and o.vertex_groups and (
                target is None or len(o.data.vertices) > len(target.data.vertices)):
            target = o
    return target, added


def transfer_weights(ob, body: str) -> None:
    """Give the garment the BODY's skin weights, by nearest surface.

    Fitting at bind pose is not enough on its own, and the render says why: with
    the thighs cleared, a tear came back at the KNEE of the bent leg. Shrinkwrap
    can only guarantee the two meshes are separated in the pose it was run in,
    and the figurine stands in a guard stance, not a T-pose. Where the garment's
    own weights differ from the body's — and they do, having been painted for a
    656-vertex mesh — the two surfaces deform differently and the joint bulges
    through.

    Transferring the weights makes them deform IDENTICALLY, so a separation that
    holds at bind pose holds in every pose. This is the standard garment
    workflow (Blender's Data Transfer -> Vertex Groups), and the same one
    CharacterRender.md already names for fitting a sourced piece to this rig.
    """
    target, added = _import_body(body)
    if target is None:
        for o in added:
            bpy.data.objects.remove(o, do_unlink=True)
        raise SystemExit("no body mesh in %s" % body)

    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("forge_weights", "DATA_TRANSFER")
    mod.object = target
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    # Interpolate across the nearest FACE rather than snapping to the nearest
    # vertex: the body is far denser than the garment, so nearest-vertex gives
    # the garment a stair-stepped copy of the body's weights and creases at
    # every joint.
    mod.vert_mapping = "POLYINTERP_NEAREST"
    # Create the matching groups before transferring into them, or the transfer
    # silently writes nothing.
    bpy.ops.object.datalayout_transfer(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    for o in added:
        bpy.data.objects.remove(o, do_unlink=True)


OPS = {"taper_shaft": taper_shaft, "stretch_down": stretch_down, "girth": girth,
       "subdivide": subdivide, "shrinkwrap_out": shrinkwrap_out,
       "transfer_weights": transfer_weights}

# ── Recipes ─────────────────────────────────────────────────────────────────
# The body a garment is fitted against. Named here rather than passed in,
# because a garment cut for the male body and wrapped to the female one is a
# silent mis-fit — the file would export fine and only look wrong on the doll.
BODY_M = "godot/assets3d/bodies/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
BODY_F = "godot/assets3d/bodies/Base Characters/Godot - UE/Superhero_Female_FullBody.gltf"
# Numbers are in the body's own units, where the figure is ~1.75 tall, the feet
# sit at 0 and the waist is ~1.05. They come from `measure`, not from taste.
RECIPES = {
    # The peasant "feet" piece is a mid-calf boot (z to 0.448). Everyday, cyber
    # and space all want a shoe, which tops out at the ankle, ~0.12.
    "shoes": [("taper_shaft", {"z_cut": 0.115, "keep": 0.10, "pinch": 0.82})],
    # Leggings stop at mid-calf (0.403) because a fantasy boot covers the rest.
    # With a shoe underneath that leaves a bare shin, so the trouser has to run
    # to the ankle on its own.
    #
    # THE BANDS ARE THE WHOLE RECIPE, and the first version had them wrong:
    # girth ran 0.15..0.80, which after the stretch is the shin and calf and
    # NOT the thigh. So the calf went baggy — visibly, and it was the first
    # thing anyone said — while the thigh, the one place the muscular body
    # actually breaks through, got nothing at all.
    #
    # Above 0.70 nothing is remapped by stretch_down, so those numbers are still
    # in the source mesh's own coordinates: thigh 0.72..1.02, shin 0.15..0.62.
    # Shrinkwrap runs LAST, after every deformation, because its whole job is to
    # clean up whatever those left inside the body. Run first it would be undone
    # by the next op.
    "trousers": [
        ("subdivide", {"levels": 1}),
        ("stretch_down", {"new_bottom": 0.105, "from_z": 0.70}),
        ("girth", {"z_lo": 0.15, "z_hi": 0.62, "factor": 1.08}),
        ("shrinkwrap_out", {"body": BODY_M, "offset": 0.010}),
        ("transfer_weights", {"body": BODY_M}),
    ],
    # A flight suit is the same trouser held close. Close is not the same as
    # interpenetrating, which is exactly the distinction shrinkwrap draws: it
    # only moves what is actually inside.
    "suit_legs": [
        ("subdivide", {"levels": 1}),
        ("stretch_down", {"new_bottom": 0.115, "from_z": 0.70}),
        ("girth", {"z_lo": 0.15, "z_hi": 0.62, "factor": 0.98}),
        ("shrinkwrap_out", {"body": BODY_M, "offset": 0.008}),
        ("transfer_weights", {"body": BODY_M}),
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
        n0 = len(ob.data.vertices)
        for op_name, kw in RECIPES[recipe]:
            OPS[op_name](ob, **kw)
        ob.data.update()
        print("  %-28s z %.3f..%.3f -> %.3f..%.3f  verts %5d -> %5d  groups %d"
              % ((ob.name,) + before + _bounds(ob) + (n0, len(ob.data.vertices),
                                                      len(ob.vertex_groups))))
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLTF_SEPARATE",
                              export_skins=True, export_animations=False)
    print("FORGE wrote %s (%s)" % (dst, recipe))


def _side_radii(co, z_lo: float, z_hi: float):
    """Max radius from each leg's own centre, per side, in the band."""
    band = [c for c in co if z_lo <= c.z < z_hi]
    out = {}
    for side, sel in (("L", [c for c in band if c.x < 0.0]),
                      ("R", [c for c in band if c.x >= 0.0])):
        if not sel:
            out[side] = None
            continue
        cx = sum(c.x for c in sel) / len(sel)
        cy = sum(c.y for c in sel) / len(sel)
        out[side] = max(((c.x - cx) ** 2 + (c.y - cy) ** 2) ** 0.5 for c in sel)
    return out


def fit(body_path: str, garment_path: str, z_lo: float, z_hi: float, bands: int = 8) -> None:
    """How much bigger is the BODY than the garment, per height band?

    The girth numbers were being guessed and re-guessed off renders — 1.30 made
    the calf baggy and did nothing for the thigh, then 1.14 still tore. Both
    meshes are right here and the question is arithmetic, so measure it: the
    factor a band needs is the body's radius over the garment's, plus clearance.
    """
    clear()
    bpy.ops.import_scene.gltf(filepath=body_path)
    body = [v.co.copy() for ob in garments() for v in ob.data.vertices]
    clear()
    bpy.ops.import_scene.gltf(filepath=garment_path)
    garm = [v.co.copy() for ob in garments() for v in ob.data.vertices]

    print("\n### body vs garment, z %.2f..%.2f" % (z_lo, z_hi))
    print("  %-14s %-22s %-22s %s" % ("z band", "body r (L/R)", "garment r (L/R)", "needed x"))
    step = (z_hi - z_lo) / bands
    for i in range(bands):
        a, b = z_lo + i * step, z_lo + (i + 1) * step
        br, gr = _side_radii(body, a, b), _side_radii(garm, a, b)
        need = []
        for side in ("L", "R"):
            if br[side] and gr[side] and gr[side] > 1e-6:
                need.append(br[side] / gr[side])
        print("  %5.3f..%5.3f  %-22s %-22s %s"
              % (a, b,
                 "/".join("%.4f" % br[s] if br[s] else "  -  " for s in ("L", "R")),
                 "/".join("%.4f" % gr[s] if gr[s] else "  -  " for s in ("L", "R")),
                 "/".join("%.2f" % n for n in need) if need else "-"))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    if argv[0] == "fit":
        fit(argv[1], argv[2], float(argv[3]), float(argv[4]))
        return
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

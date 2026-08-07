"""Add SOFT-TISSUE BONES to the shared skeleton, and weight the body and every
garment to them.

WHY BONES AND NOT SHAPE KEYS. The pack's base body ships with
`shape_keys is None` — measured, not assumed — so there is nothing to blend
towards a bust or a glute. Adding morphs would mean sculpting them by hand on
two bodies and then again on twenty garments, because a morph on the skin does
not move the shirt over it.

A bone does both jobs at once and costs one change:

  SHAPE   scale the bone and the flesh weighted to it swells. That is the
          `bust` / `glutes` / `belly` knobs, and it is the same mechanism
          `apply_build` already uses for height and girth.
  MOTION  spring-simulate the bone and the flesh jiggles. Godot ships
          SpringBoneSimulator3D for exactly this and needs no leaf bone —
          `extend_end_bone` synthesises the tip.

And because every garment is skinned to the SAME named bones, weighting the
garments here too means the cloth swells and jiggles with the body underneath.
Skip that and a bust pushes straight through a tunic — which is the one failure
the hidden-surface mask cannot save you from, since the mask deletes the skin
under the cloth and would delete the jiggle with it.

The bone POSITIONS are measured off the body, never typed: the seed is the most
forward (or most rearward) vertex in a height band, which lands on the actual
surface whatever the body is shaped like. Then the head is set INSIDE that
surface, so scaling pushes the surface out rather than dragging it inward.

    blender --background --python scripts/add_jiggle_bones.py -- <body.gltf> [garment.gltf...]

The first path is the body — it is measured AND rewritten. Every later path is
a garment, rewritten with the same bones so it follows. Rewriting IN PLACE is
deliberate: see `rig` below.

RUN IT ONCE PER SEX. The male and female bodies are different shapes, so the
seeds land in different places, and a garment cut for one is only ever worn by
that one. Running it twice on the same file is harmless — an existing bone is
left where it is and the weights are recomputed from the same geometry.
"""
import os
import sys

import bpy
from mathutils import Vector

## name, parent, height band to seed in, which side, which way it faces,
## how far inside the surface the head sits, falloff radius, bone length,
## and how far out along X to look (keeps a chest bone off the arm).
##
## `face` is +1 for the back of the body and -1 for the front. In this pack's
## armature space Z is up and -Y is forward: the toe bones run to y = -0.13.
SPEC = [
    #  name        parent      z_lo   z_hi  side  face  inset  radius  length  x_cap
    ("breast_l", "spine_03", 1.330, 1.470,  +1,   -1,  0.050,  0.105,  0.090, 0.19),
    ("breast_r", "spine_03", 1.330, 1.470,  -1,   -1,  0.050,  0.105,  0.090, 0.19),
    ("glute_l",  "pelvis",   0.930, 1.045,  +1,   +1,  0.055,  0.120,  0.090, 0.22),
    ("glute_r",  "pelvis",   0.930, 1.045,  -1,   +1,  0.055,  0.120,  0.090, 0.22),
    ("belly",    "spine_01", 1.080, 1.200,   0,   -1,  0.055,  0.110,  0.090, 0.16),
]

## The most a soft-tissue bone may take from the joints that were already
## holding a vertex. At 1.0 a breast vertex would stop following the spine
## entirely and the chest would tear off when the figure twists.
MAX_TAKE = 0.85


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def _import(path: str) -> list:
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in keep]


def skinned(objs) -> list:
    return [o for o in objs if o.type == "MESH" and o.vertex_groups]


def armature(objs):
    for o in objs:
        if o.type == "ARMATURE":
            return o
    return None


def seed(verts, z_lo, z_hi, side, face, x_cap) -> Vector:
    """The point on the surface this bone is the shape of.

    Measured rather than typed, because the male and female bodies are not the
    same shape and a garment is not the same shape as either. The most forward
    vertex in the chest band IS the bust, whatever size it happens to be.
    """
    band = [v for v in verts
            if z_lo <= v.z < z_hi and abs(v.x) <= x_cap
            and (side == 0 or (v.x > 0) == (side > 0))]
    if not band:
        return None
    # `face` is -1 at the front, so face*y is smallest at the front — take the
    # extreme in the direction the bone points.
    return min(band, key=lambda v: v.y * -face).copy()


def plan(body_verts) -> list:
    """Bone name → (head, tail, centre, radius, face, x_cap), from the body."""
    out = []
    for name, parent, z_lo, z_hi, side, face, inset, radius, length, x_cap in SPEC:
        s = seed(body_verts, z_lo, z_hi, side, face, x_cap)
        if s is None:
            print("  SKIP %s — no vertices in its band" % name)
            continue
        if side == 0:
            s.x = 0.0
        # The head sits INSIDE the surface, against the facing. Put it ON the
        # surface instead and scaling the bone slides the skin sideways along
        # itself rather than pushing it out — the bust gets wider, not fuller.
        head = s - Vector((0.0, face * inset, 0.0))
        tail = head + Vector((0.0, face * length, 0.0))
        out.append((name, parent, head, tail, radius, face, x_cap))
        print("  %-9s seed %6.3f %6.3f %6.3f   head %6.3f %6.3f %6.3f"
              % (name, s.x, s.y, s.z, head.x, head.y, head.z))
    return out


def add_bones(arm, bones) -> None:
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for name, parent, head, tail, _r, _f, _x in bones:
        if name in eb:
            continue
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.parent = eb.get(parent)
        # NOT connected: a connected bone drags its head onto the parent's tail,
        # which would move the breast bone into the middle of the neck.
        b.use_connect = False
        b.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")


def paint(ob, bones) -> int:
    """Weight this mesh to the new bones, taking the weight from whoever held it.

    The rescale is the load-bearing half. Skinning is a weighted average, so
    adding a group without removing that much from the others leaves the vertex
    over-weighted and it drifts away from the body on the first pose. Every
    existing group on an affected vertex is scaled by (1 - what the new bones
    took), which keeps the partition of unity exact.
    """
    verts = ob.data.vertices
    # A previous pass, dropped so this is IDEMPOTENT. Without it the second run
    # scales the existing joints by (1 - take) a second time and the vertex ends
    # up under-weighted — which does not tear, it SHRINKS, and shows up as the
    # figure quietly losing a chest three passes later.
    for name, *_ in bones:
        old = ob.vertex_groups.get(name)
        if old is not None:
            ob.vertex_groups.remove(old)
    for v in verts:
        s = sum(ge.weight for ge in v.groups)
        if s > 0.0 and abs(s - 1.0) > 1e-4:
            for ge in v.groups:
                ge.weight /= s

    new = {name: [0.0] * len(verts) for name, *_ in bones}
    for i, v in enumerate(verts):
        for name, _p, head, _t, radius, face, x_cap in bones:
            if abs(v.co.x) > x_cap:
                continue
            # Only flesh on the side the bone faces. Without this a chest bone
            # reaches through the ribcage and grabs the shoulder blade, and the
            # back dimples inward when the bust is dialled up.
            if (v.co.y - head.y) * face < -0.02:
                continue
            d = (v.co - head).length
            if d >= radius:
                continue
            t = 1.0 - d / radius
            new[name][i] = t * t * (3.0 - 2.0 * t)   # smoothstep, so no crease at the rim

    groups = {}
    for name in new:
        groups[name] = ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name)
    touched = 0
    for i, v in enumerate(verts):
        total = sum(new[nm][i] for nm in new)
        if total <= 0.0:
            continue
        k = (MAX_TAKE / total) if total > MAX_TAKE else 1.0
        total *= k
        # Mutate the EXISTING elements in place first; adding a group to a
        # vertex appends to v.groups, so collecting after would rescale the new
        # weights along with the old ones.
        for ge in v.groups:
            if ob.vertex_groups[ge.group].name in new:
                continue
            ge.weight *= (1.0 - total)
        for nm in new:
            if new[nm][i] > 0.0:
                groups[nm].add([i], new[nm][i] * k, "REPLACE")
        touched += 1
    return touched


def rig(path: str, bones) -> None:
    clear()
    objs = _import(path)
    arm = armature(objs)
    meshes = skinned(objs)
    if arm is None or not meshes:
        raise SystemExit("no armature or no skinned mesh in %s" % path)
    add_bones(arm, bones)
    hit = sum(paint(ob, bones) for ob in meshes)
    # IN PLACE, and with the images left alone.
    #
    # The first pass wrote GLB into a parallel folder, which embeds a private
    # copy of every texture per garment: 43 MB of shared PNGs became 74 MB of
    # duplicates, all of which would ship. `export_keep_originals` writes only
    # the geometry and leaves the .gltf pointing at the PNGs already beside it,
    # so this costs nothing and the rig profile needs no new paths. The pack's
    # own files ARE the rigged files now — git holds the originals.
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE",
                              export_keep_originals=True,
                              export_skins=True, export_animations=False)
    print("RIG %-34s %4d verts weighted  %d bones" % (
        os.path.basename(path), hit, len(arm.data.bones)))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    body, garments = argv[0], argv[1:]

    clear()
    objs = _import(body)
    verts = [v.co.copy() for ob in skinned(objs) for v in ob.data.vertices]
    print("### %s — %d verts" % (os.path.basename(body), len(verts)))
    bones = plan(verts)
    if not bones:
        raise SystemExit("nothing to add")

    # The body is measured first and written LAST, so a crash part-way through
    # the wardrobe leaves the body un-rigged too rather than leaving a body with
    # bones the clothes have never heard of.
    for p in garments + [body]:
        rig(p, bones)


if __name__ == "__main__":
    main()

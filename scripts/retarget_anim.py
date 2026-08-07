"""Bake a RIGIFY animation library onto the 65-bone Unreal-named rig this game
actually uses, so both Quaternius animation libraries are available to one doll.

WHY THIS EXISTS. UAL2 — the library already shipping — is a SITUATIONAL set:
farming, fishing, zombies, sword combos, a phone call. It has no neutral idle at
all, which is why the Gear page stands in a sword guard, and nothing for a hero
who casts. UAL1 has `Idle_Loop`, `Idle_Talking_Loop`, `Idle_Torch_Loop`,
`Dance_Loop`, a four-clip spell set and a punch set — and it is the same author,
the same CC0 licence, and already on disk.

What it is NOT is the same skeleton. UAL1's Godot export is Rigify: 53 bones
named `DEF-hips`, `DEF-upper_arm.L`. The bodies, the garments and UAL2 are 65
bones named `pelvis`, `upperarm_l`. They share exactly one bone (`root`), so a
clip from one does nothing at all on the other — silently, because Godot matches
tracks by name and a track that resolves to nothing is not an error.

THE MATH, and it is worth stating because the tempting version is wrong.

Copying each source bone's WORLD rotation onto its counterpart twists every
limb, because the two rigs' rest orientations differ per bone: Rigify rolls its
arm bones differently from Unreal, so "match this world rotation" asks the
target to hold a pose its rest never described. What transfers correctly is the
DELTA FROM REST:

    world_dst = world_src @ rest_src⁻¹ @ rest_dst

which reads as: take how far the source has moved from its own rest, and apply
that much movement to the destination's rest. It is exact when the two rest
poses agree in shape, which these do — both ship an `A_TPose` and both stand in
it.

Then, rather than hand each result to Blender and ask it to re-evaluate the
chain (a `view_layer.update()` per bone per frame — 150,000 of them for this
library), the local basis is solved directly, parents first:

    basis(b) = (world(parent) @ rest_world(parent)⁻¹ @ rest_world(b))⁻¹ @ world(b)

Same answer, one pass, no dependency graph.

SCALE is handled by scaling the whole source armature so the two hips sit at the
same height before any of this. Rotations do not care; the pelvis TRANSLATION
does, and a library baked at the wrong scale gives a hero who bobs through the
floor on a jump.

    blender --background --python scripts/retarget_anim.py -- <src.gltf> <dst_rig.glb> <out.glb>
"""
import os
import sys

import bpy
from mathutils import Matrix

## Rigify DEF-bone → Unreal bone. The two chains correspond one for one:
## hips + three spines + neck + head, shoulders hanging off the last spine.
##
## Unreal's `*_04_leaf_*` finger tips and `ball_leaf_*` have no Rigify
## counterpart and are deliberately absent — they stay at rest, which is where
## they already were, and inventing motion for them is how a hand gets a sixth
## knuckle.
BONES = {
    "DEF-hips": "pelvis",
    "DEF-spine.001": "spine_01",
    "DEF-spine.002": "spine_02",
    "DEF-spine.003": "spine_03",
    "DEF-neck": "neck_01",
    "DEF-head": "Head",
}
for _s, _d in (("L", "l"), ("R", "r")):
    BONES["DEF-shoulder.%s" % _s] = "clavicle_%s" % _d
    BONES["DEF-upper_arm.%s" % _s] = "upperarm_%s" % _d
    BONES["DEF-forearm.%s" % _s] = "lowerarm_%s" % _d
    BONES["DEF-hand.%s" % _s] = "hand_%s" % _d
    BONES["DEF-thigh.%s" % _s] = "thigh_%s" % _d
    BONES["DEF-shin.%s" % _s] = "calf_%s" % _d
    BONES["DEF-foot.%s" % _s] = "foot_%s" % _d
    BONES["DEF-toe.%s" % _s] = "ball_%s" % _d
    for _finger, _name in (("f_index", "index"), ("f_middle", "middle"),
                           ("f_pinky", "pinky"), ("f_ring", "ring"),
                           ("thumb", "thumb")):
        for _j in (1, 2, 3):
            BONES["DEF-%s.0%d.%s" % (_finger, _j, _s)] = "%s_0%d_%s" % (_name, _j, _d)

## Clips that are no use to a figurine on a stand and only bloat the export.
## `_RM` are the root-motion duplicates of clips already here; `A_TPose` is the
## rest pose, which is what the figure looks like when something has gone wrong.
SKIP = {"A_TPose", "Roll_RM", "Sword_Attack_RM"}

## Where a bake parks its name until the source action it was named after has
## been deleted. See `bake`.
TMP = "RT__"


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def _import(path: str) -> list:
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in keep]


def armature(objs):
    for o in objs:
        if o.type == "ARMATURE":
            return o
    return None


def rest_world(ob) -> dict:
    """Every bone's REST matrix in world space."""
    return {b.name: ob.matrix_world @ b.matrix_local for b in ob.data.bones}


def hip_height(ob, name: str) -> float:
    b = ob.data.bones.get(name)
    return abs((ob.matrix_world @ b.matrix_local).translation.z) if b else 1.0


def order_by_depth(ob, names) -> list:
    """Parents before children, so a bone's basis can be solved from its
    parent's already-known world matrix in a single pass."""
    def depth(n):
        d, b = 0, ob.data.bones[n]
        while b.parent is not None:
            d, b = d + 1, b.parent
        return d
    return sorted([n for n in names if n in ob.data.bones], key=depth)


def bake(src, dst, action, order, r_src, r_dst):
    """Bake one source action onto the destination rig as a new action."""
    src.animation_data.action = action
    scene = bpy.context.scene
    f0, f1 = (int(round(v)) for v in action.frame_range)
    scene.frame_start, scene.frame_end = f0, f1

    dst.animation_data_create()
    # Named out of the way for now. The source action still holds the clean
    # name, and Blender would silently hand this one `Idle_Loop.001` — which
    # then ships, and the gesture table stops matching anything.
    baked = bpy.data.actions.new(TMP + action.name)
    baked.use_fake_user = True
    dst.animation_data.action = baked

    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        world = {}
        for sb in order:
            db = BONES[sb]
            if db not in dst.pose.bones:
                continue
            # The delta from the source's own rest, applied to the target's.
            w = (src.matrix_world @ src.pose.bones[sb].matrix) \
                @ r_src[sb].inverted() @ r_dst[db]
            world[db] = w
            pb = dst.pose.bones[db]
            parent = pb.parent
            if parent is not None and parent.name in world:
                # basis = (parent_world @ rest_parent⁻¹ @ rest_self)⁻¹ @ self_world
                ref = world[parent.name] @ r_dst[parent.name].inverted() @ r_dst[db]
            else:
                ref = r_dst[db]
            pb.matrix_basis = ref.inverted() @ w
            pb.rotation_mode = "QUATERNION"
            pb.keyframe_insert("location", frame=f, group=db)
            pb.keyframe_insert("rotation_quaternion", frame=f, group=db)
    return baked


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    src_path, dst_path, out_path = argv[0], argv[1], argv[2]

    clear()
    src = armature(_import(src_path))
    # WHOSE ACTIONS ARE WHOSE. Both files bring their own, into one pool, and
    # the first pass baked all of them — including UAL2's, which mean nothing on
    # a Rigify skeleton and came out as 30 clips of a figure standing at rest.
    # Snapshot before the second import, and the question stops being ambiguous.
    src_actions = list(bpy.data.actions)
    dst = armature(_import(dst_path))
    if src is None or dst is None:
        raise SystemExit("need an armature in both files")
    # The destination's own clips are already shipping in their own file.
    for a in list(bpy.data.actions):
        if a not in src_actions:
            bpy.data.actions.remove(a)

    # Match the two rigs' scale BEFORE anything is measured off them. Rotations
    # do not care; the pelvis translation does, and a library baked at the wrong
    # scale gives a hero who bobs through the floor on every jump.
    ratio = hip_height(dst, "pelvis") / max(hip_height(src, "DEF-hips"), 1e-6)
    src.scale = (ratio, ratio, ratio)
    bpy.context.view_layer.update()
    print("### scale %.4f  (src hips %.3f -> dst pelvis %.3f)"
          % (ratio, hip_height(src, "DEF-hips") / ratio, hip_height(dst, "pelvis")))

    missing = [d for d in BONES.values() if d not in dst.data.bones]
    if missing:
        raise SystemExit("target rig is missing %d mapped bones: %s"
                         % (len(missing), ", ".join(missing[:8])))

    r_src, r_dst = rest_world(src), rest_world(dst)
    order = order_by_depth(src, list(BONES))

    src.animation_data_create()
    done = []
    for a in [x for x in src_actions if x.name not in SKIP]:
        baked = bake(src, dst, a, order, r_src, r_dst)
        done.append((baked, a.name))
        print("  %-26s %3d frames" % (a.name, int(a.frame_range[1] - a.frame_range[0]) + 1))

    # Now the originals can go, which frees the clean names for the bakes.
    dst.animation_data.action = None
    for a in src_actions:
        bpy.data.actions.remove(a)
    for baked, name in done:
        baked.name = name

    # Only the destination goes out, and only with what was just baked.
    bpy.ops.object.select_all(action="DESELECT")
    dst.select_set(True)
    for ob in dst.children:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = dst
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
                              use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True)
    print("RETARGET wrote %d clips -> %s" % (len(done), out_path))


if __name__ == "__main__":
    main()

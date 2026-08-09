"""Author the emotes no free library ships, straight onto the shipping rig.

WHY AUTHOR RATHER THAN SOURCE. Between them the two Quaternius libraries give 86
clips and not one wave, shrug, bow or look-around: they are LOCOMOTION AND TASK
libraries — running, farming, fishing, swimming, zombie walks — and the social
emotes a character needs while standing still are simply not in them. The free
mocap sets that do have gestures are thousands of clips of walking with a
handful of usable seconds buried in them, and the good hand-made packs want an
account or money.

A wave is eight keyframes on four bones. Author it.

TWO THINGS MAKE THIS TRACTABLE, and neither was guessed.

FIRST, the axes were MEASURED rather than assumed, by rotating each bone 40° and
asking where its tail went:

    Y   is the bone's own length — a twist, and the tail does not move at all
    X+  swings the tail FORWARD  (BACKWARD on the legs, which point down)
    Z+  raises the LEFT arm and lowers the RIGHT — mirrored, as bone rolls are

SECOND, the base pose is BORROWED, not typed. The rig's rest is a T-pose, so a
gesture authored from rest starts with the arms straight out sideways and reads
as a mannequin being puppeted. Frame 0 of the retargeted `Idle` is a person
standing with their arms down, so that is sampled and every gesture is a DELTA
on top of it — which also means each clip starts and ends exactly where the idle
lives, so the cross-fade back has nothing to travel.

    blender --background --python scripts/author_gestures.py -- <rig.glb> <out.glb>
"""
import math
import os
import sys

import bpy
from mathutils import Euler

FPS = 30

## The clip whose first frame is "a person standing there", used as the base
## pose for everything below. Any arms-down idle would do.
##
## Named as BLENDER sees it, which is not how Godot does: Godot's glTF importer
## reads the `_Loop` suffix as a loop-mode hint and strips it, so the clip that
## is `ual1/Idle` in the game is `Idle_Loop` in the file.
BASE_CLIP = "Idle_Loop"

## Gestures, as (seconds, {bone: (x, y, z) degrees}) — a DELTA from the base
## pose, applied in the bone's own frame. Bones absent from a keyframe hold the
## base pose, so a wave says nothing about the legs and the legs stay put.
##
## Every gesture starts and ends at the base pose. That is not tidiness: the
## director cross-fades back to an idle when a gesture ends, and a clip that
## finishes somewhere else has to travel during the blend, which reads as the
## figure being yanked.
GESTURES = {
    # A wave. The arm comes up and the FOREARM rocks — waving from the shoulder
    # is a man signalling an aircraft, not a person saying hello.
    "Wave": [
        (0.00, {}),
        (0.35, {"clavicle_r": (14, 0, 0), "upperarm_r": (-26, 0, -112),
                "lowerarm_r": (6, 0, -46)}),
        (0.60, {"clavicle_r": (14, 0, 0), "upperarm_r": (-26, 0, -112),
                "lowerarm_r": (6, -26, -46), "hand_r": (0, 0, -20)}),
        (0.85, {"clavicle_r": (14, 0, 0), "upperarm_r": (-26, 0, -112),
                "lowerarm_r": (6, 26, -46), "hand_r": (0, 0, 20)}),
        (1.10, {"clavicle_r": (14, 0, 0), "upperarm_r": (-26, 0, -112),
                "lowerarm_r": (6, -26, -46), "hand_r": (0, 0, -20)}),
        (1.35, {"clavicle_r": (14, 0, 0), "upperarm_r": (-26, 0, -112),
                "lowerarm_r": (6, 26, -46), "hand_r": (0, 0, 20)}),
        (1.80, {}),
    ],
    # A shrug. Shoulders up, palms turning out, head dipping between them.
    "Shrug": [
        (0.00, {}),
        (0.30, {"clavicle_r": (42, 0, 0), "clavicle_l": (42, 0, 0),
                "upperarm_r": (0, 0, 20), "upperarm_l": (0, 0, -20),
                "lowerarm_r": (0, -60, -58), "lowerarm_l": (0, 60, 58),
                "neck_01": (14, 0, 0), "Head": (10, 0, 0)}),
        (0.80, {"clavicle_r": (42, 0, 0), "clavicle_l": (42, 0, 0),
                "upperarm_r": (0, 0, 20), "upperarm_l": (0, 0, -20),
                "lowerarm_r": (0, -60, -58), "lowerarm_l": (0, 60, 58),
                "neck_01": (14, 0, 0), "Head": (10, 0, 0)}),
        (1.20, {}),
    ],
    # Looking about. The head leads, the chest follows a beat later — a head
    # that turns alone on a locked torso is what an owl does.
    "LookAround": [
        (0.00, {}),
        (0.45, {"Head": (0, 42, 0), "neck_01": (0, 18, 0), "spine_03": (0, 10, 0)}),
        (0.95, {"Head": (0, 42, 0), "neck_01": (0, 18, 0), "spine_03": (0, 10, 0)}),
        (1.60, {"Head": (0, -46, 0), "neck_01": (0, -20, 0), "spine_03": (0, -11, 0)}),
        (2.10, {"Head": (0, -46, 0), "neck_01": (0, -20, 0), "spine_03": (0, -11, 0)}),
        (2.60, {}),
    ],
    # A bow. From the hips, not the neck.
    "Bow": [
        (0.00, {}),
        (0.55, {"spine_01": (26, 0, 0), "spine_02": (14, 0, 0), "spine_03": (8, 0, 0),
                "neck_01": (10, 0, 0), "Head": (8, 0, 0),
                "upperarm_r": (-14, 0, 10), "upperarm_l": (-14, 0, -10)}),
        (0.95, {"spine_01": (26, 0, 0), "spine_02": (14, 0, 0), "spine_03": (8, 0, 0),
                "neck_01": (10, 0, 0), "Head": (8, 0, 0),
                "upperarm_r": (-14, 0, 10), "upperarm_l": (-14, 0, -10)}),
        (1.55, {}),
    ],
    # Both fists up. Short, because a hero who celebrates for two seconds looks
    # like a hero who has forgotten what they were celebrating.
    "Cheer": [
        (0.00, {}),
        (0.28, {"clavicle_r": (16, 0, 0), "clavicle_l": (16, 0, 0),
                "upperarm_r": (-24, 0, -120), "upperarm_l": (-24, 0, 120),
                "lowerarm_r": (0, 0, -40), "lowerarm_l": (0, 0, 40),
                "spine_03": (-8, 0, 0), "Head": (-10, 0, 0)}),
        (0.46, {"clavicle_r": (16, 0, 0), "clavicle_l": (16, 0, 0),
                "upperarm_r": (-24, 0, -104), "upperarm_l": (-24, 0, 104),
                "lowerarm_r": (0, 0, -55), "lowerarm_l": (0, 0, 55),
                "spine_03": (-6, 0, 0), "Head": (-8, 0, 0)}),
        (0.64, {"clavicle_r": (16, 0, 0), "clavicle_l": (16, 0, 0),
                "upperarm_r": (-24, 0, -122), "upperarm_l": (-24, 0, 122),
                "lowerarm_r": (0, 0, -38), "lowerarm_l": (0, 0, 38),
                "spine_03": (-8, 0, 0), "Head": (-10, 0, 0)}),
        (1.15, {}),
    ],
    # Hands on hips, weight onto one leg. The idle a character strikes when they
    # are waiting for you to make up your mind.
    "HandsOnHips": [
        (0.00, {}),
        (0.40, {"upperarm_r": (6, 0, 42), "upperarm_l": (6, 0, -42),
                "lowerarm_r": (0, -72, -104), "lowerarm_l": (0, 72, 104),
                "spine_01": (0, 0, -5), "spine_03": (0, 0, 4)}),
        (1.10, {"upperarm_r": (6, 0, 42), "upperarm_l": (6, 0, -42),
                "lowerarm_r": (0, -72, -104), "lowerarm_l": (0, 72, 104),
                "spine_01": (0, 0, -5), "spine_03": (0, 0, 4)}),
        (1.55, {}),
    ],
    # A stretch — arms up and back, the thing a body does after standing still.
    "Stretch": [
        (0.00, {}),
        (0.65, {"clavicle_r": (14, 0, 0), "clavicle_l": (14, 0, 0),
                "upperarm_r": (12, 0, -135), "upperarm_l": (12, 0, 135),
                "lowerarm_r": (0, 0, -20), "lowerarm_l": (0, 0, 20),
                "spine_02": (-12, 0, 0), "spine_03": (-10, 0, 0), "Head": (-14, 0, 0)}),
        (1.15, {"clavicle_r": (14, 0, 0), "clavicle_l": (14, 0, 0),
                "upperarm_r": (12, 0, -135), "upperarm_l": (12, 0, 135),
                "lowerarm_r": (0, 0, -20), "lowerarm_l": (0, 0, 20),
                "spine_02": (-12, 0, 0), "spine_03": (-10, 0, 0), "Head": (-14, 0, 0)}),
        (1.85, {}),
    ],
    # Beckoning: come here. Arm forward, hand curling twice.
    "Beckon": [
        (0.00, {}),
        (0.30, {"clavicle_r": (10, 0, 0), "upperarm_r": (-58, 0, -74),
                "lowerarm_r": (26, 0, -52), "hand_r": (-30, 0, 0)}),
        (0.52, {"clavicle_r": (10, 0, 0), "upperarm_r": (-58, 0, -74),
                "lowerarm_r": (52, 0, -72), "hand_r": (32, 0, 0)}),
        (0.74, {"clavicle_r": (10, 0, 0), "upperarm_r": (-58, 0, -74),
                "lowerarm_r": (26, 0, -52), "hand_r": (-30, 0, 0)}),
        (0.96, {"clavicle_r": (10, 0, 0), "upperarm_r": (-58, 0, -74),
                "lowerarm_r": (52, 0, -72), "hand_r": (32, 0, 0)}),
        (1.45, {}),
    ],
    # Weight shifting hip to hip. Not a gesture so much as PUNCTUATION — the
    # thing a real person does when nothing in particular is happening.
    "ShiftWeight": [
        (0.00, {}),
        (0.70, {"pelvis": (0, 0, 9), "spine_01": (0, 0, -15), "spine_02": (0, 0, 8),
                "spine_03": (0, 0, 6), "Head": (0, 0, 5), "neck_01": (0, 0, 4),
                "thigh_r": (0, 0, 9), "thigh_l": (0, 0, 9)}),
        (1.60, {"pelvis": (0, 0, 9), "spine_01": (0, 0, -15), "spine_02": (0, 0, 8),
                "spine_03": (0, 0, 6), "Head": (0, 0, 5), "neck_01": (0, 0, 4),
                "thigh_r": (0, 0, 9), "thigh_l": (0, 0, 9)}),
        (2.30, {}),
    ],
}


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def armature(objs):
    for o in objs:
        if o.type == "ARMATURE":
            return o
    return None


def sample_base(arm) -> dict:
    """Frame 0 of the base idle, as a quaternion per bone.

    Borrowed rather than typed. The rig's REST is a T-pose, and a gesture
    authored from there starts with the arms straight out sideways — which is
    not a pose any character holds, so every clip would open by snapping the
    arms down.
    """
    act = bpy.data.actions.get(BASE_CLIP)
    if act is None:
        raise SystemExit("no '%s' action to take the base pose from; have %s"
                         % (BASE_CLIP, ", ".join(sorted(a.name for a in bpy.data.actions))[:200]))
    arm.animation_data_create()
    arm.animation_data.action = act
    bpy.context.scene.frame_set(int(act.frame_range[0]))
    bpy.context.view_layer.update()
    out = {}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        out[pb.name] = pb.rotation_quaternion.copy()
    arm.animation_data.action = None
    return out


def author(arm, name: str, keys: list, base: dict):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for seconds, pose in keys:
        f = max(1, int(round(seconds * FPS)) + 1)
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            q = base.get(pb.name)
            if q is None:
                continue
            delta = pose.get(pb.name)
            if delta is not None:
                # POST-multiplied, so the numbers in the table read in the
                # bone's own frame: "raise this arm", not "raise this arm given
                # wherever the idle happened to leave it".
                e = Euler([math.radians(v) for v in delta], "XYZ")
                pb.rotation_quaternion = q @ e.to_quaternion()
            else:
                pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
    return act


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    rig_path, out_path = argv[0], argv[1]

    clear()
    bpy.context.scene.render.fps = FPS
    # Ease in and out of every key. Set as the PREFERENCE rather than fixed up
    # afterwards: Blender 5 moved actions to slots and layers, so the old
    # `action.fcurves` no longer exists and reaching the curves means walking
    # layers → strips → channelbag for no gain. The default is what is wanted.
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "BEZIER"
    bpy.context.preferences.edit.keyframe_new_handle_type = "AUTO_CLAMPED"
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=rig_path)
    arm = armature([o for o in bpy.data.objects if o not in keep])
    if arm is None:
        raise SystemExit("no armature in %s" % rig_path)
    bpy.context.view_layer.objects.active = arm

    base = sample_base(arm)
    borrowed = list(bpy.data.actions)

    made = []
    for name in sorted(GESTURES):
        act = author(arm, name, GESTURES[name], base)
        made.append(act)
        print("  %-14s %2d keys  %5.2f s" % (name, len(GESTURES[name]),
                                             GESTURES[name][-1][0]))

    # The rig arrived carrying the library it was sampled from; exporting that
    # too would ship a third copy of every clip.
    arm.animation_data.action = None
    for a in borrowed:
        bpy.data.actions.remove(a)

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for ob in arm.children:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
                              use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True)
    print("AUTHOR wrote %d gestures -> %s" % (len(made), out_path))


if __name__ == "__main__":
    main()

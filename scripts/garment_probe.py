"""Can a pack garment survive a Blender round-trip with its skin intact?

THE question before any garment work, because everything downstream assumes it.
The pack's clothes are already skinned to the 65-bone rig the bodies and the
animation library share, and that skinning is the expensive part — the whole
reason to EDIT an existing garment rather than generate a new one is that its
vertex weights come along for free.

If a plain import → export loses the armature modifier, renames a bone, or drops
a vertex group, then editing is not cheaper than generating and the plan is
wrong. Run this first, and read the numbers rather than trusting the round-trip.

    blender --background --python scripts/garment_probe.py -- <in.gltf> <out.gltf>
"""
import sys

import bpy


def clear() -> None:
    """Empty the scene, belt and braces."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def report(tag: str) -> dict:
    out = {"meshes": [], "armatures": []}
    for ob in bpy.data.objects:
        # Skinned meshes only. Blender's glTF importer leaves a 42-vertex
        # Icosphere behind on every import — verified not to be in the file,
        # which has exactly one mesh — and it is neither a garment nor ours to
        # explain. A garment always carries vertex groups, so that is the filter.
        if ob.type == "MESH" and not ob.vertex_groups:
            continue
        if ob.type == "MESH":
            out["meshes"].append({
                "name": ob.name,
                "verts": len(ob.data.vertices),
                "groups": len(ob.vertex_groups),
                # The armature MODIFIER is what actually makes a mesh deform.
                # A mesh can keep every vertex group and still go rigid if this
                # is lost, which is exactly the failure worth naming.
                "armature_mod": any(m.type == "ARMATURE" for m in ob.modifiers),
                "materials": [m.name for m in ob.data.materials if m],
            })
        elif ob.type == "ARMATURE":
            out["armatures"].append({
                "name": ob.name,
                "bones": len(ob.data.bones),
                "sample": sorted(b.name for b in ob.data.bones)[:6],
            })
    print("\n=== %s ===" % tag)
    for m in out["meshes"]:
        print("  mesh %-28s verts %6d  groups %3d  armature_mod %s  mats %s"
              % (m["name"], m["verts"], m["groups"], m["armature_mod"], m["materials"]))
    for a in out["armatures"]:
        print("  arma %-28s bones %3d  %s" % (a["name"], a["bones"], a["sample"]))
    return out


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]

    clear()
    bpy.ops.import_scene.gltf(filepath=src)
    before = report("IMPORTED %s" % src)

    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLTF_SEPARATE",
        # Skinning is the entire point of the exercise; the defaults are right
        # but naming them here means a Blender upgrade that changes a default
        # breaks loudly at this line rather than silently in the game.
        export_skins=True,
        export_animations=False,
        use_selection=False,
    )

    clear()
    bpy.ops.import_scene.gltf(filepath=dst)
    after = report("ROUND-TRIPPED %s" % dst)

    # Compare the numbers, do not eyeball the log. A probe whose verdict is "the
    # output looks similar" is the kind of check that passes while broken.
    ok = True
    bm = {m["name"]: m for m in before["meshes"]}
    am = {m["name"]: m for m in after["meshes"]}
    if len(bm) != len(am):
        print("FAIL: mesh count %d -> %d" % (len(bm), len(am)))
        ok = False
    for nm, b in bm.items():
        a = am.get(nm)
        if a is None:
            print("FAIL: mesh '%s' did not survive" % nm)
            ok = False
            continue
        for key in ("groups", "armature_mod", "materials"):
            if b[key] != a[key]:
                print("FAIL: %s.%s %s -> %s" % (nm, key, b[key], a[key]))
                ok = False
        # Vertex count is NOT an invariant across a glTF round-trip and asserting
        # it was the probe's first wrong answer: glTF stores one attribute set
        # per vertex, so every vertex on a UV seam or a split normal is
        # duplicated on export. Peasant_Body went 3006 -> 3020, which is 0.5 %
        # and the same geometry. What must never happen is LOSS, or growth big
        # enough to mean the mesh was triangulated differently.
        if a["verts"] < b["verts"]:
            print("FAIL: %s lost vertices %d -> %d" % (nm, b["verts"], a["verts"]))
            ok = False
        elif a["verts"] > b["verts"] * 1.10:
            print("FAIL: %s grew more than 10%% %d -> %d" % (nm, b["verts"], a["verts"]))
            ok = False
        elif a["verts"] != b["verts"]:
            print("  note: %s %d -> %d verts (seam split, +%.1f%%)"
                  % (nm, b["verts"], a["verts"],
                     100.0 * (a["verts"] - b["verts"]) / b["verts"]))
    bb = {a["name"]: a["bones"] for a in before["armatures"]}
    ab = {a["name"]: a["bones"] for a in after["armatures"]}
    if sorted(bb.values()) != sorted(ab.values()):
        print("FAIL: bone counts %s -> %s" % (sorted(bb.values()), sorted(ab.values())))
        ok = False

    print("\nPROBE %s" % ("OK — skin survives the round-trip" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

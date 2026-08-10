"""Path-trace the figurine as a PAINTED MINIATURE, offline, in Cycles.

The figurine is static — a handful of poses, no live turning — and that is
precisely the licence to stop rendering it in a real-time engine. Godot's
forward renderer with one directional light is why it read as an early-2000s
game; Cycles with real global illumination, contact shadows and a studio HDRI is
why a photograph of a miniature reads as a photograph.

WHAT THIS CAN AND CANNOT DO, stated up front because it decides everything: it
cannot add geometry, so it cannot make a 7,300-vertex body into a lifelike
human. It does not need to. A real 28 mm figure HAS simplified forms — that is
what a miniature is — and what sells the photograph is the surface: matte
acrylic over primer, a little edge wear, soft light with real occlusion in the
folds, and a shallow depth of field that says "small object, close lens".

    blender --background --python scripts/figurine_render.py -- <out.png> <body.gltf> <garment.gltf...>
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# THE SAME coverage rule the game's masks are baked from, imported rather than
# copied. Two definitions of "is this skin under that garment" is how the
# offline render and the live figurine start disagreeing about where the holes
# are, and the one that is wrong is whichever nobody looked at last.
from bake_body_masks import covered_vertices, neck_line  # noqa: E402

SAMPLES = 160
RES = 1024
## Subdivision is free here — nothing animates this, and Cycles does not care
## about vertex count. It is the cheapest fidelity in the whole script: the
## pack's legs are 656 vertices and read as a faceted tube without it.
SUBDIV = 2
## Smallest run of connected skin faces worth keeping after the carve. Below
## this it is a stranded scrap in an armpit, not anatomy — the head is 1,541
## vertices and the hands hundreds, so nothing real comes close to the floor.
ISLAND_MIN = 40


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def skinned(objs) -> list:
    return [o for o in objs if o.type == "MESH" and o.vertex_groups]


def imp(path: str) -> list:
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in keep]


def paint(ob, is_skin: bool) -> None:
    """Re-shade a mesh as painted resin, keeping its own albedo as the paint.

    The pack's textures are flat hand-painted colour with no normal or roughness
    map — I deleted those, which is a separate mistake — so the surface has to
    come from the SHADER instead. Acrylic on primer is matte with a faint sheen,
    never the plastic gloss a default PBR material gives it.
    """
    for slot in ob.material_slots:
        mat = slot.material
        if mat is None or not mat.use_nodes:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        bsdf.inputs["Roughness"].default_value = 0.62 if is_skin else 0.78
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.28
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
        # A painted mini is opaque resin, not skin: no subsurface. Adding it is
        # the classic mistake that makes a figurine look like a waxwork.
        if "Subsurface Weight" in bsdf.inputs:
            bsdf.inputs["Subsurface Weight"].default_value = 0.0


def strip_covered(body, garment_objs) -> int:
    """DELETE the skin the garments cover, rather than masking it.

    Offline, hidden-surface removal gets to be literal. The game masks the skin
    in a shader because a texture is all it can hand the GPU per frame; here the
    faces can simply go, which costs nothing to path-trace, has no mask
    resolution to alias against, and cannot leave a seam where a texel straddles
    the garment's edge.

    A face goes if ANY of its corners is covered — the same aggressive rule the
    game's masks use, and for the same reason: a boundary face is under the hem
    either way, and leaving one poking vertex is the entire bug.

    Done with bmesh, not with select-then-operator. Setting `face.select` in
    object mode also selects that face's VERTICES, and `mesh.delete(type=FACE)`
    then removes every face whose corners are all selected — which cascades far
    past the faces asked for. The first attempt deleted 10,112 faces and took
    the whole head with it.
    """
    import bmesh

    # The neck line matters MORE here than in the game. A mask only discards
    # fragments; this deletes faces outright, so skin carved off the throat is
    # not a dark patch, it is a hole you can see the inside of the skull through.
    above = neck_line(list(bpy.data.objects))
    cov = np.zeros(len(body.data.vertices), dtype=bool)
    for g in garment_objs:
        cov |= covered_vertices(body, g, above)

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    doomed = [f for f in bm.faces if any(cov[v.index] for v in f.verts)]
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")

    # Then sweep the orphans. Carving the skin away leaves small islands
    # stranded — a few faces in the armpit that no garment covered but that are
    # now attached to nothing, floating beside the sleeve like litter. They are
    # invisible in a mask (the shader just does not draw the texels around them)
    # and obvious once the geometry is really gone.
    #
    # ONLY where something was actually carved. Run unconditionally it deletes
    # the eyes and the eyebrows, which are small separate meshes that were never
    # cut and are legitimately made of little islands.
    stray = []
    if not doomed:
        bm.to_mesh(body.data)
        bm.free()
        return 0
    bm.faces.ensure_lookup_table()
    seen: set = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        island, queue = [], [f]
        seen.add(f.index)
        while queue:
            cur = queue.pop()
            island.append(cur)
            for e in cur.edges:
                for nb in e.link_faces:
                    if nb.index not in seen:
                        seen.add(nb.index)
                        queue.append(nb)
        if len(island) < ISLAND_MIN:
            stray += island
    if stray:
        bmesh.ops.delete(bm, geom=stray, context="FACES")

    bm.to_mesh(body.data)
    bm.free()
    return len(doomed) + len(stray)


def smooth(ob) -> None:
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("mini_subsurf", "SUBSURF")
    mod.levels = SUBDIV
    mod.render_levels = SUBDIV
    for p in ob.data.polygons:
        p.use_smooth = True


def studio(target: Vector, height: float) -> None:
    """Three-point studio light plus a soft world fill, sized to the subject."""
    world = bpy.data.worlds.new("studio")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.05, 0.055, 0.07, 1.0)
    bg.inputs[1].default_value = 1.0

    def lamp(name, loc, energy, size, warm):
        d = bpy.data.lights.new(name, "AREA")
        d.energy = energy
        d.size = size
        d.color = warm
        o = bpy.data.objects.new(name, d)
        bpy.context.collection.objects.link(o)
        o.location = loc
        dirv = (target - Vector(loc)).normalized()
        o.rotation_euler = dirv.to_track_quat("-Z", "Y").to_euler()
        return o

    # Big and close, because a soft key is what stops raking shadows reading as
    # 3D-render-default. Sizes are in the figure's own units.
    lamp("key",  (height * 0.9, -height * 1.0, height * 1.35), 340.0, height * 0.9,
         (1.0, 0.96, 0.90))
    lamp("fill", (-height * 1.1, -height * 0.7, height * 0.75), 90.0, height * 1.1,
         (0.86, 0.90, 1.0))
    lamp("rim",  (-height * 0.5, height * 1.2, height * 1.2), 200.0, height * 0.5,
         (0.95, 0.97, 1.0))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    out, body_path, garments = argv[0], argv[1], argv[2:]

    clear()
    body_objs = skinned(imp(body_path))
    garment_objs = []
    for g in garments:
        garment_objs += skinned(imp(g))

    # BEFORE subdividing. The coverage test runs against the authored geometry
    # the masks were baked from, and deleting whole faces is far cheaper on the
    # original than on a mesh already 16x denser.
    for b in body_objs:
        gone = strip_covered(b, garment_objs)
        print("STRIP %-26s %d faces removed" % (b.name, gone))

    meshes = [(o, True) for o in body_objs] + [(o, False) for o in garment_objs]
    for ob, is_skin in meshes:
        smooth(ob)
        paint(ob, is_skin)

    # Frame from the real geometry, not from a guessed number.
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob, _ in meshes:
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    centre = (lo + hi) * 0.5
    height = hi.z - lo.z

    # The plinth. A miniature photographed floating in space reads as a render;
    # standing on something, with a contact shadow, reads as an object.
    bpy.ops.mesh.primitive_cylinder_add(radius=height * 0.19, depth=height * 0.035,
                                        location=(centre.x, centre.y,
                                                  lo.z - height * 0.0175))
    base = bpy.context.active_object
    bm = bpy.data.materials.new("plinth")
    bm.use_nodes = True
    pb = bm.node_tree.nodes["Principled BSDF"]
    pb.inputs["Base Color"].default_value = (0.07, 0.07, 0.08, 1.0)
    pb.inputs["Roughness"].default_value = 0.85
    base.data.materials.append(bm)

    studio(centre, height)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 85.0            # a portrait lens; wide angles say "game camera"
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 4.0
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    # DERIVED from the lens, not guessed. `height * 2.3` cut the feet off, and
    # the distance that frames a subject depends on the focal length — change
    # the lens for a nicer look and a hardcoded distance silently re-crops.
    # Subject spans the figure plus its plinth, with a margin for the shadow.
    subject = height + height * 0.035
    vfov = 2.0 * math.atan(cam_data.sensor_width * 0.5 / cam_data.lens)
    dist = (subject * 1.16 * 0.5) / math.tan(vfov * 0.5)
    ang = math.radians(18.0)
    cam.location = (centre.x + dist * math.sin(ang) * 0.9,
                    centre.y - dist * math.cos(ang),
                    centre.z + height * 0.10)
    cam.rotation_euler = (centre - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    cam_data.dof.focus_object = meshes[0][0]
    bpy.context.scene.camera = cam

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:
        sc.cycles.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("HIP", "ONEAPI", "OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = d.type in (kind, "CPU")
                    print("CYCLES device: %s" % kind)
                    break
            except (TypeError, AttributeError):
                continue
    except Exception as exc:                      # noqa: BLE001 - report and go on
        print("CYCLES: falling back to CPU (%s)" % exc)
        sc.cycles.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"       # filmic; Standard blows the key out
    sc.view_settings.look = "AgX - Base Contrast"
    sc.render.filepath = out
    sc.render.image_settings.file_format = "PNG"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("FIGURINE wrote %s" % out)


if __name__ == "__main__":
    main()

"""Grow a tail: five bones onto the shared skeleton, and a mesh skinned to them.

WHY THE BONES GO ON THE BODY'S OWN SKELETON, rather than the tail carrying a
private armature of its own. Godot's `SpringBoneSimulator3D` is already hanging
off that skeleton, tuned, for the soft tissue — a chain rooted at `tail_01` and
ending at `tail_05` is one more entry in a table, and the tail sways with no new
simulation, no second skeleton to keep in step, and no code at all beyond the
entry. A private armature would need its own simulator, its own update order and
its own attachment maths.

The garments do NOT need re-exporting for this. A garment's skin binds to the
bones it names, and none of them names a tail; extra bones on the skeleton are
inert to everything that does not reference them. Only the BODIES are rewritten,
so their skeletons carry the chain for the tail mesh to bind against.

SEEDED, LIKE THE HORNS. The root is the rearmost point of the pelvis at hip
height, found on the body rather than typed, because the two bodies are not the
same shape and a tail that starts inside one starts outside the other.

    blender --background --python scripts/author_tail.py -- <body.gltf> <out.glb>

Rewrites the body IN PLACE (adding the bones) and writes the tail mesh beside it.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

## Where the chain hangs from, and what the bones are called. `pelvis` is the
## root of the legs too, so a tail on it inherits the hips exactly as it should.
PARENT = "pelvis"
BONES = ["tail_01", "tail_02", "tail_03", "tail_04", "tail_05"]

## Segment lengths, root to tip. Uneven on purpose: a tail that tapers in equal
## steps reads as a machine part, and the long middle is where the sway lives.
SEGMENTS = [0.115, 0.130, 0.120, 0.100, 0.080]
## Degrees each joint droops relative to the one before. The chain leaves the
## hips almost level and hangs by the tip.
DROOP = [10.0, 14.0, 17.0, 20.0]

## Radius at each joint, plus the tip. Dragon rather than cat: thick at the hips.
RADII = [0.052, 0.043, 0.033, 0.024, 0.015, 0.005]
SIDES = 10
## Rings per segment. Three keeps the silhouette smooth through the droop
## without paying for geometry nobody sees at 230x336.
RINGS = 3


def clear() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)


def _import(path: str) -> list:
	keep = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	return [o for o in bpy.data.objects if o not in keep]


def biggest(objs):
	best = None
	for o in objs:
		if o.type == "MESH" and o.vertex_groups:
			if best is None or len(o.data.vertices) > len(best.data.vertices):
				best = o
	return best


def armature(objs):
	for o in objs:
		if o.type == "ARMATURE":
			return o
	return None


def root_point(body, arm) -> Vector:
	"""The rearmost point of the hips, at hip height — where a tail leaves.

	Measured, because the two bodies are not the same shape and a tail seeded on
	one starts inside the other. Sunk 15 mm in, so the first ring is buried and
	there is no seam where it meets the back.
	"""
	b = arm.data.bones.get(PARENT)
	if b is None:
		raise SystemExit("no '%s' bone to hang a tail from" % PARENT)
	z = (arm.matrix_world @ b.matrix_local).translation.z
	band = [v.co for v in body.data.vertices
			if abs(v.co.z - z) < 0.055 and abs(v.co.x) < 0.06]
	if not band:
		raise SystemExit("no hips at z=%.3f" % z)
	back = max(band, key=lambda v: v.y)     # +Y is behind, in this pack's space
	return Vector((0.0, back.y - 0.015, back.z))


def joints(root: Vector) -> list:
	"""The chain's joint positions, root to tip."""
	out = [root.copy()]
	pos = root.copy()
	# Starts level and slightly back, then droops.
	d = Vector((0.0, 1.0, -0.12)).normalized()
	for i, seg in enumerate(SEGMENTS):
		pos = pos + d * seg
		out.append(pos.copy())
		if i < len(DROOP):
			# NEGATIVE about +X. Right-hand rule takes +Y towards +Z, so a
			# positive angle here lifts the tail instead of dropping it — the
			# first run grew one that rose 15 cm above its own root.
			d = Matrix.Rotation(math.radians(-DROOP[i]), 4, Vector((1.0, 0.0, 0.0))) @ d
			d.normalize()
	return out


def add_bones(arm, js: list) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	eb = arm.data.edit_bones
	prev = eb.get(PARENT)
	for i, name in enumerate(BONES):
		b = eb.get(name) or eb.new(name)
		b.head, b.tail = js[i], js[i + 1]
		b.parent = prev
		# CONNECTED down the chain, so the spring simulator sees one continuous
		# limb rather than five bones that happen to be near each other.
		b.use_connect = i > 0
		b.use_deform = True
		prev = b
	bpy.ops.object.mode_set(mode="OBJECT")


def build_mesh(name: str, js: list, arm):
	"""A tapered tube following the chain, skinned across it with a soft blend."""
	verts, faces, weights = [], [], []
	steps = []
	for i in range(len(BONES)):
		for r in range(RINGS):
			steps.append((i, float(r) / float(RINGS)))
	steps.append((len(BONES) - 1, 1.0))

	for seg, t in steps:
		a, b = js[seg], js[seg + 1]
		pos = a.lerp(b, t)
		d = (b - a).normalized()
		side = d.cross(Vector((0.0, 0.0, 1.0)))
		if side.length < 1e-5:
			side = Vector((1.0, 0.0, 0.0))
		side.normalize()
		up = d.cross(side).normalized()
		r0, r1 = RADII[seg], RADII[seg + 1]
		r = r0 + (r1 - r0) * t
		for k in range(SIDES):
			ang = 2.0 * math.pi * k / SIDES
			# Slightly taller than wide: a tail with a round section reads as a
			# rope, and a dragon's is deeper top-to-bottom.
			verts.append(pos + side * (math.cos(ang) * r * 0.86)
						 + up * (math.sin(ang) * r * 1.14))
			# The blend: this ring belongs mostly to its own bone and leans on the
			# next one as it approaches the joint. Without it every joint creases.
			weights.append((seg, t))
	for i in range(len(steps) - 1):
		for k in range(SIDES):
			p = i * SIDES + k
			q = i * SIDES + (k + 1) % SIDES
			faces.append((p, q, q + SIDES, p + SIDES))
	tip = len(verts)
	verts.append(js[-1])
	weights.append((len(BONES) - 1, 1.0))
	last = (len(steps) - 1) * SIDES
	for k in range(SIDES):
		faces.append((last + k, last + (k + 1) % SIDES, tip))

	me = bpy.data.meshes.new(name)
	me.from_pydata([tuple(v) for v in verts], [], [list(f) for f in faces])
	me.validate()
	for p in me.polygons:
		p.use_smooth = True
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)

	groups = {b: ob.vertex_groups.new(name=b) for b in BONES}
	for vi, (seg, t) in enumerate(weights):
		near = min(1.0, t * 1.35)          # lean on the next bone near the joint
		groups[BONES[seg]].add([vi], 1.0 - near * 0.5, "REPLACE")
		if seg + 1 < len(BONES):
			groups[BONES[seg + 1]].add([vi], near * 0.5, "REPLACE")
		else:
			groups[BONES[seg]].add([vi], 1.0, "REPLACE")

	ob.parent = arm
	mod = ob.modifiers.new("Armature", "ARMATURE")
	mod.object = arm

	mat = bpy.data.materials.new("MI_Tail")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = (0.55, 0.42, 0.35, 1.0)
		bsdf.inputs["Roughness"].default_value = 0.72
	me.materials.append(mat)
	return ob


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:]
	body_path, out_path = argv[0], argv[1]

	clear()
	objs = _import(body_path)
	body, arm = biggest(objs), armature(objs)
	if body is None or arm is None:
		raise SystemExit("need a skinned body and its armature in %s" % body_path)

	js = joints(root_point(body, arm))
	add_bones(arm, js)
	tail = build_mesh("Tail", js, arm)
	print("  root %6.3f %6.3f %6.3f  tip %6.3f %6.3f %6.3f  %d verts" % (
		js[0].x, js[0].y, js[0].z, js[-1].x, js[-1].y, js[-1].z,
		len(tail.data.vertices)))

	# The TAIL goes out on its own, worn like any other piece.
	os.makedirs(os.path.dirname(out_path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	tail.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
							  use_selection=True, export_skins=True,
							  export_animations=False)

	# And the BODY is rewritten so its skeleton carries the chain for the tail
	# to bind against. In place, images untouched — same contract as
	# add_jiggle_bones, and for the same reason.
	bpy.data.objects.remove(tail, do_unlink=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=body_path, export_format="GLTF_SEPARATE",
							  export_keep_originals=True,
							  export_skins=True, export_animations=False)
	print("TAIL %s -> %s  (+%d bones on the body)" % (
		os.path.basename(body_path), os.path.basename(out_path), len(BONES)))


if __name__ == "__main__":
	main()

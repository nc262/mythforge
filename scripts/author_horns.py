"""Grow horns on the shipping rig, seeded off the actual skull.

WHY THIS IS CHEAP. A horn needs no new mechanism at all: skin every vertex to
the `Head` bone at weight 1 and it is, as far as the doll is concerned, a
garment — worn through the same `_wear_file` the hair goes through, following
the head through every animation for free. No socket maths, no bone attachment,
no second code path.

WHY IT IS SEEDED AND NOT TYPED. The male and female skulls sit 43 mm apart —
that is what made `Hair_BuzzedFemale` render as bald when it was offered as a
separate style — so a horn placed by hand on one head floats off the other. The
root is found by asking the BODY: take the head's own centre, and walk to the
surface vertex furthest along an up-and-out-and-back direction. That lands on
the upper temple whatever shape the skull is.

THE SHAPE is a swept tube: rings of vertices along a curve that pitches
backwards as it climbs, tapering to a point. Ridges are a sine on the radius,
which costs one term and is the difference between a horn and a traffic cone.

    blender --background --python scripts/author_horns.py -- <body.gltf> <out.glb>
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

## Which bone carries them. Every vertex is weighted to this one and nothing
## else, so the horns are rigid relative to the skull — which is what a horn is.
BONE = "Head"

## Where on the skull to root them, as a direction from the head's own centre:
## out to the side, back, and up. Walked to the surface, so the number is a
## direction rather than a position and survives a different head.
## Rendered once at (0.62, 0.30, 0.72) — out on the TEMPLES, above the ears,
## which reads as a bull rather than a tiefling. Forward and inward is the
## difference: horns want the brow ridge, not the side of the skull.
ROOT_DIR = Vector((0.44, -0.26, 0.86))

## rings along the horn, and vertices around each ring. 9x8 is 72 vertices per
## horn — the whole pair costs less than a boot buckle, and at Gear-page size a
## rounder ring is invisible.
SEGS = 9
SIDES = 8

## name → how it grows.
##   length  metres, tip to root, along the curve
##   base    radius at the root
##   curl    total degrees the axis pitches BACKWARD over the length
##   flare   total degrees it also swings OUTWARD
##   ridges  how many bands of thickness; 0 is a smooth sweep
##   rough   how deep those bands cut, as a fraction of the radius
GROWTH = {
	# The classic tiefling: heavy, ridged, curling back over the skull.
	"ram":      {"length": 0.19, "base": 0.027, "curl": 168.0, "flare": 16.0,
				 "ridges": 7, "rough": 0.16},
	# Long, clean, swept back — the one that reads at board-token size.
	"swept":    {"length": 0.22, "base": 0.022, "curl": 84.0, "flare": 12.0,
				 "ridges": 0, "rough": 0.0},
	# Straight up and slightly out. Oryx, demon-prince, deliberately severe.
	# 0.30 m at 12 degrees of flare came out as a pair of antennae leaving the
	# frame. Shorter, and near-vertical rather than splayed.
	"spire":    {"length": 0.19, "base": 0.020, "curl": 18.0, "flare": 4.0,
				 "ridges": 4, "rough": 0.08},
	# Short and blunt. For a hero who would rather not be stared at.
	"nub":      {"length": 0.075, "base": 0.026, "curl": 40.0, "flare": 14.0,
				 "ridges": 3, "rough": 0.13},
}


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


def head_root(body, arm, side: int):
	"""Where the horn leaves the skull, and which way it sets off.

	Measured off the body rather than typed: the surface vertex furthest along
	an up-and-out-and-back direction from the head's own centre.
	"""
	b = arm.data.bones.get(BONE)
	if b is None:
		raise SystemExit("no '%s' bone to hang horns from" % BONE)
	base_z = (arm.matrix_world @ b.matrix_local).translation.z
	skull = [v.co for v in body.data.vertices if v.co.z > base_z + 0.03]
	if not skull:
		raise SystemExit("no skull above the head bone")
	centre = sum(skull, Vector()) / len(skull)
	d = Vector((ROOT_DIR.x * side, ROOT_DIR.y, ROOT_DIR.z)).normalized()
	root = max(skull, key=lambda v: (v - centre).dot(d))
	# Sunk a few millimetres in, so the horn grows OUT of the skull rather than
	# balancing on it with a visible seam underneath.
	return root - d * 0.010, d


def grow(root: Vector, axis: Vector, side: int, g: dict) -> tuple:
	"""One horn, as (verts, faces). A swept tube along a pitching curve."""
	verts, faces = [], []
	# The curve bends BACKWARD (+Y here) and outward (±X) as it climbs, so the
	# rotation axes are taken from the horn's own frame rather than the world's.
	up = axis.normalized()
	out = Vector((float(side), 0.0, 0.0))
	side_ax = up.cross(out)
	if side_ax.length < 1e-5:
		side_ax = Vector((0.0, 1.0, 0.0))
	side_ax.normalize()

	pos = root.copy()
	dir_ = up.copy()
	step = g["length"] / float(SEGS - 1)
	for i in range(SEGS):
		t = float(i) / float(SEGS - 1)
		# Taper to a point, with the fall weighted to the tip so the horn keeps
		# its mass low — a linear taper reads as a cone.
		r = g["base"] * (1.0 - t) ** 1.45
		if g["ridges"] > 0:
			r *= 1.0 + g["rough"] * math.sin(t * math.pi * g["ridges"] * 2.0)
		# A ring perpendicular to the current direction.
		u = dir_.cross(side_ax).normalized()
		w = dir_.cross(u).normalized()
		for k in range(SIDES):
			a = 2.0 * math.pi * k / SIDES
			verts.append(pos + (u * math.cos(a) + w * math.sin(a)) * r)
		if i < SEGS - 1:
			pitch = math.radians(g["curl"] / (SEGS - 1))
			yaw = math.radians(g["flare"] / (SEGS - 1)) * side
			dir_ = (Matrix.Rotation(pitch, 4, side_ax)
					@ Matrix.Rotation(yaw, 4, Vector((0.0, 0.0, 1.0)))) @ dir_
			dir_.normalize()
			pos = pos + dir_ * step
	# Quads between consecutive rings, then a fan to close the tip.
	for i in range(SEGS - 1):
		for k in range(SIDES):
			a = i * SIDES + k
			b = i * SIDES + (k + 1) % SIDES
			faces.append((a, b, b + SIDES, a + SIDES))
	tip = len(verts)
	verts.append(pos)
	last = (SEGS - 1) * SIDES
	for k in range(SIDES):
		faces.append((last + k, last + (k + 1) % SIDES, tip))
	return verts, faces


def build(name: str, body, arm, g: dict):
	"""Both horns as ONE mesh, skinned entirely to the head bone."""
	verts, faces = [], []
	for side in (1, -1):
		root, axis = head_root(body, arm, side)
		v, f = grow(root, axis, side, g)
		off = len(verts)
		verts.extend(v)
		faces.extend([tuple(i + off for i in q) for q in f])

	me = bpy.data.meshes.new(name)
	me.from_pydata([tuple(v) for v in verts], [], [list(q) for q in faces])
	me.validate()
	# Smooth, or every ring reads as a facet at this poly count.
	for p in me.polygons:
		p.use_smooth = True
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)

	# ONE group, weight 1, on the head. That is the whole rig for a horn.
	grp = ob.vertex_groups.new(name=BONE)
	grp.add(list(range(len(me.vertices))), 1.0, "REPLACE")
	ob.parent = arm
	mod = ob.modifiers.new("Armature", "ARMATURE")
	mod.object = arm

	mat = bpy.data.materials.new("MI_Horn_%s" % name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = (0.29, 0.25, 0.22, 1.0)
		bsdf.inputs["Roughness"].default_value = 0.52
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

	made = []
	for name in sorted(GROWTH):
		ob = build(name, body, arm, GROWTH[name])
		made.append(ob)
		print("  %-8s %d verts  length %.3f  curl %3.0f" % (
			name, len(ob.data.vertices), GROWTH[name]["length"], GROWTH[name]["curl"]))

	# One file per style, so a hero wears exactly the pair they chose. Exporting
	# them together would put all four on the same skull.
	os.makedirs(os.path.dirname(out_path), exist_ok=True)
	stem = out_path[:-4] if out_path.endswith(".glb") else out_path
	for ob in made:
		bpy.ops.object.select_all(action="DESELECT")
		ob.select_set(True)
		arm.select_set(True)
		bpy.context.view_layer.objects.active = arm
		dst = "%s_%s.glb" % (stem, ob.name)
		bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB",
								  use_selection=True, export_skins=True,
								  export_animations=False)
		print("HORN wrote %s" % os.path.basename(dst))


if __name__ == "__main__":
	main()

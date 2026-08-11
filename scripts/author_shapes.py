"""Give the body SHAPE KEYS, and give every garment the same ones.

WHY THIS EXISTS. `rules_engine.gd` has declared `chest`, `seat` and `belly`
knobs for a while and none of them could do anything, because the only tool the
doll had was BONE SCALE — and there is no bone in a chest. Scaling `spine_03`
thickens the whole ribcage and the shoulders with it. Shape is geometry, and
geometry means moving vertices.

WHY THE GARMENTS FOLLOW FOR FREE, which is the part that decides whether this is
affordable. A shape key on the body alone gives a hero whose chest grows THROUGH
their tunic. The fix is the one every modular-character pipeline uses: bind the
garment to the body with Blender's **Surface Deform** modifier, push the body's
key to 1, and read back where the garment ended up. That readback becomes a
shape key on the garment with the SAME NAME, so the doll sets one value on
everything it is wearing and the whole silhouette moves together.

Surface Deform binds each garment vertex to the body's surface, so this is not a
proportional falloff applied twice and hoped to match — the cloth is following
the actual skin. That is why a tunic hem stays a hem instead of drifting.

WHAT IT DOES NOT DISTURB:
  * UVs do not move, so every baked mask in `masks/` stays valid
  * vertex groups and weights are untouched, so the 65-bone skin still binds
  * topology is untouched, so `garment_probe.py` still covers these pieces

Keys are authored to blend BOTH WAYS. Godot's blend-shape values are not clamped
to 0..1, so a knob at 0 sends -1 and a knob at 100 sends +1: one key per axis
covers flat-to-full rather than needing a pair.

    blender --background --python scripts/author_shapes.py -- <body.gltf> <garment.gltf...>

Rewrites every file IN PLACE, images untouched — same contract as
`add_jiggle_bones.py`, and for the same reason.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

## Each key is a bulge: an anchor bone, an offset up or down from it, and an
## ellipse of influence in the body's own vertical/lateral plane. Seeded off the
## SKELETON rather than typed as heights, because the male and female bodies do
## not put their ribs in the same place — the same mistake that rendered
## `Hair_BuzzedFemale` bald.
##
##   bone/dz  where the centre of the bulge sits
##   rz/rx    falloff radii, vertical and lateral
##   push     metres of travel at full strength
##   spread   how much of that travel goes sideways instead of front/back;
##            0 is a pure swelling forward, 1 pushes as much out as out-front
##   side     which face of the body it lives on: -1 front (-Y), +1 back (+Y)
KEYS = {
	# The bust/pectoral mass, over the upper ribs.
	"Chest": dict(bone="spine_03", dz=0.030, rz=0.135, rx=0.150,
				  push=0.052, spread=0.45, side=-1),
	# The abdomen, low and centred, no lateral spread — a belly is not wider.
	"Belly": dict(bone="spine_01", dz=-0.020, rz=0.150, rx=0.135,
				  push=0.055, spread=0.15, side=-1),
	# The seat. Wider than it is deep, and it carries the hips with it.
	"Seat":  dict(bone="pelvis", dz=-0.025, rz=0.120, rx=0.165,
				  push=0.048, spread=0.60, side=+1),
}

## Vertices beyond this from the centre line are limbs, not torso. Without it
## the Chest ellipse catches the inside of a T-posed upper arm and the hero
## grows a lump on each bicep.
ARM_X = 0.24


def clear() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)


def _import(path: str) -> list:
	keep = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	return [o for o in bpy.data.objects if o not in keep]


def skinned(objs) -> list:
	"""The meshes that carry a skin. The importer leaves an Icosphere behind."""
	return [o for o in objs if o.type == "MESH" and o.vertex_groups]


def biggest(objs):
	got = skinned(objs)
	return max(got, key=lambda o: len(o.data.vertices)) if got else None


def armature(objs):
	for o in objs:
		if o.type == "ARMATURE":
			return o
	return None


def smooth(t: float) -> float:
	t = max(0.0, min(1.0, t))
	return t * t * (3.0 - 2.0 * t)


def anchor(arm, spec: dict) -> float:
	b = arm.data.bones.get(spec["bone"])
	if b is None:
		raise SystemExit("no '%s' bone to anchor a shape key on" % spec["bone"])
	return (arm.matrix_world @ b.matrix_local).translation.z + spec["dz"]


def offsets(mesh, z0: float, spec: dict) -> dict:
	"""index -> where that vertex moves at full strength, for one key."""
	out = {}
	for v in mesh.vertices:
		if abs(v.co.x) > ARM_X:
			continue
		# Only the face of the body this bulge lives on. Without it a chest key
		# inflates the back of the ribs by the same amount.
		if spec["side"] < 0 and v.co.y > 0.02:
			continue
		if spec["side"] > 0 and v.co.y < -0.02:
			continue
		r = math.hypot((v.co.z - z0) / spec["rz"], v.co.x / spec["rx"])
		w = smooth(1.0 - r)
		if w <= 0.001:
			continue
		d = Vector((0.0, float(spec["side"]), 0.0))
		if spec["spread"] > 0.0 and abs(v.co.x) > 1e-5:
			d = d + Vector((math.copysign(spec["spread"], v.co.x), 0.0, 0.0))
		out[v.index] = d.normalized() * (spec["push"] * w)
	return out


def strip(ob) -> None:
	"""Drop the keys this script owns, so a re-run replaces rather than stacks.

	Named removal rather than `shape_key_clear()`, because clearing would also
	take any key the pack shipped — none do today, but a wardrobe piece that
	arrives with its own morph should not be quietly flattened by a re-bake.
	"""
	sk = ob.data.shape_keys
	if sk is None:
		return
	for name in list(KEYS):
		kb = sk.key_blocks.get(name)
		if kb is not None:
			ob.shape_key_remove(kb)
	sk = ob.data.shape_keys
	if sk is not None and len(sk.key_blocks) == 1:
		ob.shape_key_remove(sk.key_blocks[0])


def zero(sk):
	"""Park a freshly added key at rest, and let it travel both ways.

	`shape_key_add()` hands back a key already at **value 1.0**, which is the
	single most expensive thing on this page. Left alone it costs twice: glTF
	stores morph weights, so the body ships permanently inflated — and every
	garment bound afterwards binds to that inflated body, so its morph target is
	the difference between two wrong shapes. The first run of this script wrote
	a tunic that answered a chest bulge with nothing and answered a seat bulge on
	its FRONT, and this one line is the whole reason.
	"""
	sk.value = 0.0
	sk.slider_min, sk.slider_max = -1.0, 1.0
	return sk


def key_body(body, arm) -> dict:
	"""Add every key to the body. Returns name -> vertices moved."""
	strip(body)
	if body.data.shape_keys is None:
		body.shape_key_add(name="Basis", from_mix=False)
	moved = {}
	for name in KEYS:
		spec = KEYS[name]
		delta = offsets(body.data, anchor(arm, spec), spec)
		sk = zero(body.shape_key_add(name=name, from_mix=False))
		for i, d in delta.items():
			sk.data[i].co = body.data.vertices[i].co + d
		moved[name] = len(delta)
	return moved


def bind(garment, body) -> bool:
	"""Bind the garment to the body's surface. False if Blender refused."""
	# The ARMATURE has to be out of the way at both ends. Surface Deform binds
	# against the evaluated surface, and a body still being posed by its rest
	# armature is a different surface from the one the garment was modelled on.
	for ob in (garment, body):
		for m in ob.modifiers:
			if m.type == "ARMATURE":
				m.show_viewport = False
	mod = garment.modifiers.new("Refit", "SURFACE_DEFORM")
	mod.target = body
	bpy.context.view_layer.objects.active = garment
	bpy.ops.object.surfacedeform_bind(modifier=mod.name)
	return mod.is_bound


def transfer(garment, body) -> dict:
	"""Give the garment a shape key per body key, by watching it follow."""
	if garment.data.shape_keys is None:
		garment.shape_key_add(name="Basis", from_mix=False)
	got = {}
	keys = body.data.shape_keys.key_blocks
	for name in KEYS:
		keys[name].value = 1.0
		dg = bpy.context.evaluated_depsgraph_get()
		co = [v.co.copy() for v in garment.evaluated_get(dg).data.vertices]
		keys[name].value = 0.0
		sk = zero(garment.shape_key_add(name=name, from_mix=False))
		# Counted at a MILLIMETRE, not at the float noise floor. Surface Deform
		# perturbs almost every vertex by a few microns even where the body did
		# not move, so a 1e-5 threshold reports half the mesh for every key and
		# all three keys look identical.
		n = 0
		for i, c in enumerate(co):
			if (c - sk.data[i].co).length > 1e-3:
				n += 1
			sk.data[i].co = c
		got[name] = n
	return got


def unbind(garment) -> None:
	for m in list(garment.modifiers):
		if m.type == "SURFACE_DEFORM":
			garment.modifiers.remove(m)
	for m in garment.modifiers:
		if m.type == "ARMATURE":
			m.show_viewport = True


def write(path: str) -> None:
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE",
							  export_keep_originals=True, export_skins=True,
							  export_morph=True, export_animations=False)
	if not os.path.exists(path):
		raise SystemExit("shape keys were not written: %s" % path)


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:]
	body_path, garment_paths = argv[0], argv[1:]

	# ── the body ────────────────────────────────────────────────────────────
	clear()
	objs = _import(body_path)
	body, arm = biggest(objs), armature(objs)
	if body is None or arm is None:
		raise SystemExit("need a skinned body and its armature in %s" % body_path)
	moved = key_body(body, arm)
	print("SHAPES %s" % os.path.basename(body_path))
	for name in KEYS:
		print("  %-6s %4d/%d verts  push %.3f" % (
			name, moved[name], len(body.data.vertices), KEYS[name]["push"]))
	write(body_path)

	# ── every garment, one fresh scene each ─────────────────────────────────
	for gp in garment_paths:
		clear()
		bobjs = _import(body_path)
		body = biggest(bobjs)
		gobjs = _import(gp)
		pieces = skinned(gobjs)
		if not pieces:
			print("  SKIP %-40s (nothing skinned)" % os.path.basename(gp))
			continue
		report = []
		for g in pieces:
			# BEFORE the bind, not after. A re-run finds the previous run's keys
			# still on the piece, and Surface Deform would take its bind against
			# a garment those keys had already deformed.
			strip(g)
			if not bind(g, body):
				raise SystemExit("Surface Deform refused to bind %s in %s" % (g.name, gp))
			got = transfer(g, body)
			unbind(g)
			report.append("%s %s" % (g.name, "/".join(
				"%s:%d" % (k, got[k]) for k in KEYS)))
		# The BODY is only here as a surface to follow; it must not be written
		# into the garment file, or every worn piece drags a second hero along.
		for ob in bobjs:
			bpy.data.objects.remove(ob, do_unlink=True)
		write(gp)
		print("  REFIT %-40s %s" % (os.path.basename(gp), "  ".join(report)))


if __name__ == "__main__":
	main()

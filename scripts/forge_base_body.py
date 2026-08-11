"""Put the MakeHuman base mesh on OUR rig, in OUR rest pose.

WHY. The pack's body is 7,281 vertices with 833 of them in the face, and it is
that way because it was free — not because a figurine wants it. A muzzle was
impossible on it (`forge_head.py` is the negative result), and at Gear-page size
the face is a smooth mask. MakeHuman's base is **13,380 vertices, every one of
them a quad**, and was explicitly released **CC0 in September 2020** — the notice
is in the head of `base.obj` itself, naming Data Collection AB, Joel Palmius and
Jonas Hauquier. It is a morph-target base, so its topology is built to deform.

THE ONE HARD PART is that the two meshes do not stand the same way. Our rig's
rest is a hard T-pose; MakeHuman's base is an **A-pose, measured at roughly 50
degrees** down from the shoulder. Transferring skin weights by proximity across
that gap is hopeless — the new body's forearms hang where the old body's ribs
are, so every arm vertex would be skinned to the spine.

Nobody has to guess at the difference, because MakeHuman ships its whole skeleton
inside the mesh as **joint cubes** — 125 little boxes named `joint-l-elbow`,
`joint-neck` and so on. Their centroids are the joint positions. So:

  1. our rig is POSED into MakeHuman's stance, by aiming each bone down the
     direction its own two joint cubes give
  2. our body is evaluated in that pose, and the weights are transferred to the
     new mesh while the two are lying on top of each other
  3. the new mesh is UN-POSED — every vertex pushed back through the inverse of
     the skinning matrix that put it there — so it lands in our T-pose rest

After (3) the mesh and the armature agree again, which is the whole requirement:
a bind pose has to equal the rest pose or every clip plays through a twist. And
because the armature is untouched, every animation, spring, garment, horn and
tail still binds exactly as it did.

Only the ARMS actually move. The spine and the legs are within a few degrees of
vertical in both, which is why the mapping below can be flat and measured rather
than iterative.

    blender --background --python scripts/forge_base_body.py -- <base.obj> <ours.gltf> <out.gltf>
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

## our bone -> (joint cube at its head, joint cube at its tail). The bone is
## rotated so it points from the first at the second. Bones absent here keep
## their rest orientation and simply inherit whatever their parent did.
AIM = {
	"pelvis":     ("joint-pelvis", "joint-spine-4"),
	"spine_01":   ("joint-spine-4", "joint-spine-3"),
	"spine_02":   ("joint-spine-3", "joint-spine-2"),
	"spine_03":   ("joint-spine-2", "joint-spine-1"),
	"neck_01":    ("joint-neck", "joint-head"),
	"Head":       ("joint-head", "joint-head-2"),
	"clavicle_l": ("joint-l-clavicle", "joint-l-shoulder"),
	"upperarm_l": ("joint-l-shoulder", "joint-l-elbow"),
	"lowerarm_l": ("joint-l-elbow", "joint-l-hand"),
	"hand_l":     ("joint-l-hand", "joint-l-hand-2"),
	"clavicle_r": ("joint-r-clavicle", "joint-r-shoulder"),
	"upperarm_r": ("joint-r-shoulder", "joint-r-elbow"),
	"lowerarm_r": ("joint-r-elbow", "joint-r-hand"),
	"hand_r":     ("joint-r-hand", "joint-r-hand-2"),
	"thigh_l":    ("joint-l-upper-leg", "joint-l-knee"),
	"calf_l":     ("joint-l-knee", "joint-l-ankle"),
	"foot_l":     ("joint-l-ankle", "joint-l-foot-1"),
	"thigh_r":    ("joint-r-upper-leg", "joint-r-knee"),
	"calf_r":     ("joint-r-knee", "joint-r-ankle"),
	"foot_r":     ("joint-r-ankle", "joint-r-foot-1"),
}

## Where the two skeletons are pinned to each other before anything is aimed.
## The pelvis rather than the feet: a hip is one joint both rigs agree on, while
## a heel depends on how the toes were modelled.
ANCHOR = ("joint-pelvis", "pelvis")

## Godot's glTF path takes four influences per vertex. Transferred weights
## routinely land on six or seven, and the ones past four are noise.
MAX_INFLUENCE = 4


# ── reading the OBJ ─────────────────────────────────────────────────────────
# Done as TEXT, before Blender sees the file, because Blender's OBJ importer
# drops `g` groups entirely — and without them there is no way to tell the body
# from the 125 joint cubes and 46 clothing helpers sharing the same mesh.


def obj_groups(path: str) -> tuple:
	"""(vertex positions, group name -> the vertex indices its faces use)."""
	verts, groups, cur = [], {}, ""
	with open(path, "r", encoding="utf-8", errors="ignore") as fh:
		for line in fh:
			if line.startswith("v "):
				p = line.split()
				verts.append(Vector((float(p[1]), float(p[2]), float(p[3]))))
			elif line.startswith("g "):
				cur = line[2:].strip()
			elif line.startswith("f "):
				s = groups.setdefault(cur, set())
				for tok in line[2:].split():
					s.add(int(tok.split("/")[0]) - 1)
	return verts, groups


def joints(verts: list, groups: dict) -> dict:
	"""Joint cube name -> its centroid. That IS MakeHuman's skeleton."""
	out = {}
	for g, idx in groups.items():
		if g.startswith("joint") and idx:
			out[g] = sum((verts[i] for i in idx), Vector()) / len(idx)
	return out


def clear() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)


def _import(path: str) -> list:
	keep = set(bpy.data.objects)
	if path.lower().endswith(".obj"):
		bpy.ops.wm.obj_import(filepath=path)
	else:
		bpy.ops.import_scene.gltf(filepath=path)
	return [o for o in bpy.data.objects if o not in keep]


def biggest(objs):
	got = [o for o in objs if o.type == "MESH" and o.vertex_groups]
	return max(got, key=lambda o: len(o.data.vertices)) if got else None


def armature(objs):
	for o in objs:
		if o.type == "ARMATURE":
			return o
	return None


def strip_to_body(ob, keep: set) -> None:
	"""Delete everything that is not the body — helpers, and the joint cubes."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.verts.ensure_lookup_table()
	drop = [v for v in bm.verts if v.index not in keep]
	bmesh.ops.delete(bm, geom=drop, context="VERTS")
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


# ── placing MakeHuman in our space ──────────────────────────────────────────


def fit(mh, js: dict, body, arm) -> dict:
	"""Scale and shift MakeHuman onto us. Returns the moved joints.

	THE ROTATION IS NOT OURS TO DO. Blender's OBJ importer leaves the file's
	vertices Y-up and puts the quarter turn to Z-up on the OBJECT MATRIX instead.
	Rotating the mesh data as well turns the body through a full half circle, and
	the only symptom is that a weight transfer afterwards skins the fingertips to
	the feet — which is exactly where they now are. So the importer's own matrix
	is baked into the data and reused for the joints, and nothing is rotated by
	hand.
	"""
	bpy.ops.object.select_all(action="DESELECT")
	mh.select_set(True)
	bpy.context.view_layer.objects.active = mh
	rot = mh.matrix_world.copy()
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

	mz = [v.co.z for v in mh.data.vertices]
	oz = [v.co.z for v in body.data.vertices]
	scale = (max(oz) - min(oz)) / (max(mz) - min(mz))

	pin = arm.data.bones.get(ANCHOR[1])
	if pin is None:
		raise SystemExit("no '%s' bone to pin the new body to" % ANCHOR[1])
	dst = (arm.matrix_world @ pin.matrix_local).translation
	shift = dst - (rot @ js[ANCHOR[0]]) * scale

	m = Matrix.Translation(shift) @ Matrix.Scale(scale, 4)
	mh.data.transform(m)
	mh.data.update()
	# Smooth, and not as a flourish: an OBJ arrives flat-shaded, so every face
	# owns its own normals and the glTF exporter splits every shared vertex to
	# carry them. 13,380 vertices went out as 53,512 — four per quad, more than
	# the body it was meant to replace, for a facetted render.
	for p in mh.data.polygons:
		p.use_smooth = True
	print("  fit: scale %.4f  shift %6.3f %6.3f %6.3f" % (
		scale, shift.x, shift.y, shift.z))
	return {k: m @ (rot @ v) for k, v in js.items()}


# ── posing our rig into MakeHuman's stance ──────────────────────────────────


def pose_like(arm, js: dict) -> dict:
	"""Aim every mapped bone down its joint pair. Returns bone -> world matrix.

	Solved PARENT-FIRST and analytically, the same way `retarget_anim.py` does
	it, so nothing depends on the depsgraph having caught up between bones.
	"""
	rest = {b.name: b.matrix_local for b in arm.data.bones}
	order = []

	def walk(b):
		order.append(b)
		for c in b.children:
			walk(c)

	for b in arm.data.bones:
		if b.parent is None:
			walk(b)

	world = {}
	for b in order:
		if b.parent is None:
			base = arm.matrix_world @ rest[b.name]
		else:
			base = world[b.parent.name] @ rest[b.parent.name].inverted() @ rest[b.name]
		pair = AIM.get(b.name)
		if pair is not None and pair[0] in js and pair[1] in js:
			want = (js[pair[1]] - js[pair[0]])
			if want.length > 1e-6:
				# A bone points down its own local +Y. Rotate about the HEAD, so
				# the joint stays put and only the direction changes.
				have = (base.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
				q = have.rotation_difference(want.normalized())
				head = base.translation.copy()
				base = (Matrix.Translation(head) @ q.to_matrix().to_4x4()
						@ Matrix.Translation(-head) @ base)
				# DIRECTION ONLY, never length. Scaling each bone to the spacing
				# of its two joint cubes looks like the obvious next step and is
				# wrong twice: the two rigs already agree on the arm to within a
				# millimetre (0.4947 m against 0.4955, shoulder to wrist), and
				# the bones that are NOT limbs have tails set by convention
				# rather than anatomy — `Head` runs to the crown here and to the
				# eyes there, so matching its length scaled the skull by two and
				# stood the figure 2.15 m tall.
		world[b.name] = base

	for b in order:
		pb = arm.pose.bones[b.name]
		if b.parent is None:
			ref = arm.matrix_world @ rest[b.name]
		else:
			ref = world[b.parent.name] @ rest[b.parent.name].inverted() @ rest[b.name]
		pb.matrix_basis = ref.inverted() @ world[b.name]
	bpy.context.view_layer.update()
	return world


def span(ob) -> float:
	"""Arm span. The one number that says which pose a body is standing in."""
	co = [v.co for v in ob.data.vertices]
	return max(c.x for c in co) - min(c.x for c in co)


# ── the transfer, and undoing the pose ──────────────────────────────────────


def bone_heat(mh, arm) -> int:
	"""Skin the new body by BONE HEAT, against a rig standing where it stands.

	NOT by proximity to our own body's surface, which is the obvious way and
	fails on this exact pose. MakeHuman's base stands with its arms about fifty
	degrees down, which puts each hand alongside the corresponding thigh — so a
	nearest-surface transfer skinned the fingers to `thigh_r` and `pelvis`, and
	the un-pose then swung the shoulder up to the T-pose while leaving the hand
	behind. Both arms rendered as flat triangular sheets fanned between the two.
	Nothing about the maths was wrong; the question "what is nearest" simply has
	the wrong answer where two body parts touch.

	Bone heat solves over the MESH'S OWN SURFACE rather than through the air, so
	a hand cannot borrow weight from a thigh it is merely resting against — there
	is no path along the skin from one to the other.

	It has to weigh against an armature whose REST is MakeHuman's stance, because
	that is the shape the vertices are actually in, so the pose is applied as rest
	on a throwaway copy. Bone names are untouched, so the groups it writes bind to
	the real rig unchanged.
	"""
	dup = arm.copy()
	dup.data = arm.data.copy()
	dup.name = "HeatRig"
	bpy.context.collection.objects.link(dup)
	for pb in dup.pose.bones:
		pb.matrix_basis = arm.pose.bones[pb.name].matrix_basis.copy()
	bpy.context.view_layer.update()

	bpy.ops.object.select_all(action="DESELECT")
	dup.select_set(True)
	bpy.context.view_layer.objects.active = dup
	bpy.ops.object.mode_set(mode="POSE")
	bpy.ops.pose.select_all(action="SELECT")
	bpy.ops.pose.armature_apply()
	bpy.ops.object.mode_set(mode="OBJECT")

	bpy.ops.object.select_all(action="DESELECT")
	mh.select_set(True)
	dup.select_set(True)
	bpy.context.view_layer.objects.active = dup
	bpy.ops.object.parent_set(type="ARMATURE_AUTO")

	# The groups are what we came for; the binding is thrown away and remade
	# against the real rig once the mesh has been un-posed onto it.
	for m in list(mh.modifiers):
		if m.type == "ARMATURE":
			mh.modifiers.remove(m)
	mh.parent = None
	bpy.data.objects.remove(dup, do_unlink=True)
	return len(mh.vertex_groups)


def unpose(mh, arm, world: dict) -> float:
	"""Push every vertex back through the pose that is holding it.

	Skinning is `v_posed = sum(w * pose * rest^-1) * v_rest`. The tempting way
	back is to build that same weighted sum and invert it — and it tears. Where a
	vertex's weights straddle a big rotation, an armpit split between `spine_03`
	and `upperarm_l` across fifty degrees, the averaged matrix is very nearly
	singular and its inverse throws the vertex somewhere else entirely. The first
	run rendered each arm as a flat triangular sheet fanned from the shoulder to
	a hand left behind, and that is what it was.

	So the INVERSES are blended, not the matrices — the same linear blend run
	backwards, one well-conditioned rotation at a time. Do this and the new mesh
	stands in OUR T-pose while never having been modelled in it.
	"""
	rest = {b.name: b.matrix_local for b in arm.data.bones}
	skin = {}
	for name in rest:
		if name in world:
			skin[name] = rest[name] @ world[name].inverted()
	idx = {g.index: g.name for g in mh.vertex_groups}
	# What the transfer actually produced, reported rather than assumed: a
	# vertex with no weight cannot be un-posed and will be left standing in
	# MakeHuman's stance while everything around it moves.
	bare = sum(1 for v in mh.data.vertices if not v.groups)
	tip = max(mh.data.vertices, key=lambda v: abs(v.co.x))
	top = sorted(((g.weight, idx.get(g.group, "?")) for g in tip.groups), reverse=True)[:3]
	print("  weights: %d/%d vertices bare; outermost vertex -> %s" % (
		bare, len(mh.data.vertices),
		", ".join("%s %.2f" % (n, w) for w, n in top) or "NOTHING"))
	moved = 0.0
	for v in mh.data.vertices:
		acc = Vector((0.0, 0.0, 0.0))
		total = 0.0
		for g in v.groups:
			m = skin.get(idx.get(g.group))
			if m is None or g.weight <= 0.0:
				continue
			acc += (m @ v.co) * g.weight
			total += g.weight
		if total <= 1e-6:
			continue
		before = v.co.copy()
		v.co = acc / total
		moved = max(moved, (v.co - before).length)
	mh.data.update()
	return moved


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:]
	obj_path, ours_path, out_path = argv[0], argv[1], argv[2]

	clear()
	verts, groups = obj_groups(obj_path)
	js = joints(verts, groups)
	body_idx = groups.get("body")
	if not body_idx:
		raise SystemExit("no 'body' group in %s" % obj_path)
	print("MAKEHUMAN %d joints, body uses %d of %d vertices" % (
		len(js), len(body_idx), len(verts)))

	mh = [o for o in _import(obj_path) if o.type == "MESH"][0]
	strip_to_body(mh, body_idx)
	print("  stripped to %d verts / %d faces (%d quads)" % (
		len(mh.data.vertices), len(mh.data.polygons),
		sum(1 for p in mh.data.polygons if len(p.vertices) == 4)))

	ours = _import(ours_path)
	body, arm = biggest(ours), armature(ours)
	if body is None or arm is None:
		raise SystemExit("need a skinned body and its armature in %s" % ours_path)

	js = fit(mh, js, body, arm)
	world = pose_like(arm, js)
	# How far the pose actually had to travel, which is the number that says
	# whether the two rigs were worth reconciling at all.
	for nm in ("upperarm_l", "lowerarm_l", "thigh_l"):
		b = arm.data.bones[nm]
		a = (arm.matrix_world @ b.matrix_local).to_3x3() @ Vector((0, 1, 0))
		c = world[nm].to_3x3() @ Vector((0, 1, 0))
		print("  aimed %-11s %5.1f degrees" % (nm, math.degrees(a.angle(c))))

	print("  our body posed to %.3f span (rest %.3f)" % (
		span(mh), span(body)))
	print("  skinned to %d vertex groups by bone heat" % bone_heat(mh, arm))

	moved = unpose(mh, arm, world)
	print("  un-posed, furthest vertex travelled %.3f m" % moved)

	# Back to rest, and the new mesh is bound to it.
	for pb in arm.pose.bones:
		pb.matrix_basis = Matrix()
	bpy.context.view_layer.update()

	bpy.ops.object.select_all(action="DESELECT")
	mh.select_set(True)
	bpy.context.view_layer.objects.active = mh
	bpy.ops.object.vertex_group_limit_total(limit=MAX_INFLUENCE)
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)
	mh.name = "MakeHuman_Body"
	mh.parent = arm
	mod = mh.modifiers.new("Armature", "ARMATURE")
	mod.object = arm

	# The OLD body goes; this file is the new one, on the same skeleton.
	bpy.data.objects.remove(body, do_unlink=True)
	os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLTF_SEPARATE",
							  export_skins=True, export_animations=False)
	if not os.path.exists(out_path):
		raise SystemExit("new body was not written: %s" % out_path)
	print("FORGED %s  %d verts" % (os.path.basename(out_path), len(mh.data.vertices)))


if __name__ == "__main__":
	main()

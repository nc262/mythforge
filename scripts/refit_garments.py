"""Refit the wardrobe onto a different body, without re-modelling anything.

WHY IT IS NEEDED. Dress the MakeHuman candidate in the pack's ranger tunic and
its chest and belly come straight THROUGH the cloth. That is not a mask failing:
a mask deletes skin that a garment covers, and this skin is not covered, it is
OUTSIDE. MakeHuman's torso is simply a different shape from the body the tunic
was modelled against, and no amount of hidden-surface work hides geometry
sitting in front of the cloth.

HOW, and it is the same trick `author_shapes.py` already proved on this exact
wardrobe. A garment is bound to the OLD body with Blender's Surface Deform, the
old body is then deformed into the shape of the NEW one, and wherever the cloth
ends up is read back and kept. The cloth is measured following the skin rather
than scaled by a rule and hoped to fit.

The old body is moved onto the new one by SHRINKWRAP, which is available here for
the one reason it usually is not: both bodies are standing in the same T-pose by
this point, so "the nearest point on the other surface" means what it sounds
like. `forge_base_body.py` is what makes that true.

WHAT SURVIVES. Only vertex positions move — no vertex is added, removed,
reordered or reweighted — so the skin weights, the vertex groups, the UVs, the
material and the 65-bone binding all come through untouched. That is the same
guarantee `garment_forge.py` relies on, and it is why one passing round-trip
probe covers every piece here.

WRITTEN BESIDE THE ORIGINALS with a suffix, never over them. The pack body still
ships and still wears the originals; a refitted piece is only worn by the body it
was refitted for. Same folder rather than a subfolder because glTF writes texture
URIs as bare filenames, so a piece moved one directory down stops finding its own
maps.

    blender --background --python scripts/refit_garments.py -- <old.gltf> <new.gltf> <suffix> <garment.gltf...>
"""
import os
import sys

import bpy


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


def biggest(objs):
	got = skinned(objs)
	return max(got, key=lambda o: len(o.data.vertices)) if got else None


def quiet(ob) -> None:
	"""Take the armature out of the way. Both bodies are in their rest pose and
	must stay there — a garment bound against a posed surface is bound wrong."""
	for m in ob.modifiers:
		if m.type == "ARMATURE":
			m.show_viewport = False


def bind(garment, body) -> bool:
	mod = garment.modifiers.new("Refit", "SURFACE_DEFORM")
	mod.target = body
	bpy.context.view_layer.objects.active = garment
	bpy.ops.object.surfacedeform_bind(modifier=mod.name)
	return mod.is_bound


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:]
	old_path, new_path, suffix, garments = argv[0], argv[1], argv[2], argv[3:]

	for gp in garments:
		clear()
		oldobjs = _import(old_path)
		old = biggest(oldobjs)
		newobjs = _import(new_path)
		new = biggest(newobjs)
		if old is None or new is None:
			raise SystemExit("need a skinned body in both %s and %s" % (old_path, new_path))
		quiet(old)
		quiet(new)

		gobjs = _import(gp)
		pieces = skinned(gobjs)
		if not pieces:
			print("  SKIP %-40s (nothing skinned)" % os.path.basename(gp))
			continue
		for g in pieces:
			quiet(g)
			if not bind(g, old):
				raise SystemExit("Surface Deform refused to bind %s in %s" % (g.name, gp))

		# BOUND FIRST, THEN THE BODY MOVES. Surface Deform takes its bind against
		# the target as it stands, so the shrinkwrap has to come after every bind
		# — add it first and the garment binds to a body already wearing the new
		# shape, and then follows nothing at all.
		sw = old.modifiers.new("ToNewBody", "SHRINKWRAP")
		sw.target = new
		sw.wrap_method = "NEAREST_SURFACEPOINT"

		report = []
		dg = bpy.context.evaluated_depsgraph_get()
		for g in pieces:
			co = [v.co.copy() for v in g.evaluated_get(dg).data.vertices]
			moved = sum(1 for i, c in enumerate(co)
						if (c - g.data.vertices[i].co).length > 1e-3)
			far = max(((c - g.data.vertices[i].co).length
					   for i, c in enumerate(co)), default=0.0)
			for i, c in enumerate(co):
				g.data.vertices[i].co = c
			g.data.update()
			for m in list(g.modifiers):
				if m.type == "SURFACE_DEFORM":
					g.modifiers.remove(m)
			for m in g.modifiers:
				if m.type == "ARMATURE":
					m.show_viewport = True
			report.append("%s %d/%d max %.3f" % (
				g.name, moved, len(co), far))

		# The bodies were only ever scaffolding; neither belongs in the file.
		for ob in oldobjs + newobjs:
			bpy.data.objects.remove(ob, do_unlink=True)

		stem, ext = os.path.splitext(gp)
		dst = stem + suffix + ext
		bpy.ops.object.select_all(action="SELECT")
		bpy.ops.export_scene.gltf(filepath=dst, export_format="GLTF_SEPARATE",
								  export_keep_originals=True, export_skins=True,
								  export_morph=True, export_animations=False)
		if not os.path.exists(dst):
			raise SystemExit("refitted garment was not written: %s" % dst)
		print("REFIT %-40s %s" % (os.path.basename(dst), "  ".join(report)))


if __name__ == "__main__":
	main()

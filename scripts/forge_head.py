"""Forge a DRACONIC head out of the human one, by moving vertices.

THIS DOES NOT WORK YET, AND THE RENDER IS WHY. Kept because the reasoning below
is right and the harness that judges it (tests/head_shot.tscn) is worth having —
but what it currently produces is a smooth featureless dome with the eyes buried
inside it. Pushing a band of vertices forward INFLATES a face; it does not sculpt
one. A muzzle needs the jaw separated from the skull, a bridge built between
them, and the eye sockets held back while everything around them moves — that is
sculpting logic, not a displacement field, and no amount of tuning the weights
below will get there. See godot/docs/CharacterRender.md.

WHY NOT FACE BONES. Face bones drive expression — a jaw that opens, a brow that
furrows, an eyelid that closes. They move a head you already have. They cannot
make a muzzle: scaling a jaw bone on a human skull gives a human with a large
jaw, because the vertices are still arranged as a human face. A dragonborn's
head is a different SHAPE, and shape is geometry.

WHY NOT A SEPARATE HEAD MESH BOLTED ON. It would work, and it would cost the
seam: a second mesh meeting the neck needs its own matching silhouette, its own
skin tone, and its own hidden-surface handling where the two overlap. Every one
of those is a thing to get wrong at 230x336.

SO: DEFORM THE BODY'S OWN HEAD, which the wardrobe pipeline already does to
garments (scripts/garment_forge.py). Vertices move; the UV layout does NOT. That
one fact is what makes this cheap —

  * every baked mask stays valid, because masks live in UV space
  * the skin texture still lands where it did, so no texture is re-authored
  * the garments still fit, because nothing below the neck is touched
  * the skeleton is untouched, so every clip, spring and garment still binds

The eyes are their OWN mesh and are deliberately left alone. A muzzle growing
forward from between them puts the eyes high and to the sides of the skull,
which is where a lizard's are.

    blender --background --python scripts/forge_head.py -- <body.gltf> <out_dir>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

## name → how far to push the face out, and how it hangs.
##   reach   metres the snout extends forward
##   drop    metres the muzzle sinks as it goes, so it is not a beak
##   taper   how much the muzzle narrows toward the tip, 0-1
##   jaw     extra drop under the mouth line, for a heavy lower jaw
##   brow    metres the brow ridge pushes forward over the eyes
SHAPES = {
	"drake":  {"reach": 0.105, "drop": 0.022, "taper": 0.30, "jaw": 0.016, "brow": 0.020},
	"saurian": {"reach": 0.070, "drop": 0.014, "taper": 0.24, "jaw": 0.010, "brow": 0.014},
	"wyrm":   {"reach": 0.145, "drop": 0.030, "taper": 0.36, "jaw": 0.022, "brow": 0.026},
}

## The face's own landmarks, measured on this pack in `main` rather than typed:
## the muzzle band is anchored between the mouth and the bridge of the nose.
MOUTH_DZ = -0.055     # below the eye centre
BRIDGE_DZ = 0.020     # above it
## How far back the influence reaches. Beyond this the skull is left alone, or
## the whole head stretches and the character turns into a horse.
BACK_Y = 0.020
## Lateral half-width of the muzzle at the skull.
HALF_X = 0.080


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


def eye_centre(objs) -> Vector:
	for o in objs:
		if o.type == "MESH" and o.name.lower().startswith("eyes"):
			co = [v.co for v in o.data.vertices]
			return sum(co, Vector()) / len(co)
	raise SystemExit("no eye mesh to anchor the muzzle against")


def smooth(t: float) -> float:
	t = max(0.0, min(1.0, t))
	return t * t * (3.0 - 2.0 * t)


def weight(co: Vector, eye: Vector) -> float:
	"""How much of the muzzle this vertex is part of, 0-1.

	Three falloffs multiplied: forward of the skull, within the muzzle's height
	band, and near the centre line. Multiplied rather than added so a vertex has
	to satisfy all three — added, the ears join in.
	"""
	# Forward: full at the nose, nothing by the ears.
	f = smooth((BACK_Y - co.y) / (BACK_Y + 0.105))
	# Height: the band between the mouth and the bridge, softened at both edges.
	lo, hi = eye.z + MOUTH_DZ, eye.z + BRIDGE_DZ
	if co.z < lo:
		g = smooth(1.0 - (lo - co.z) / 0.070)
	elif co.z > hi:
		g = smooth(1.0 - (co.z - hi) / 0.055)
	else:
		g = 1.0
	# Sideways: the muzzle is narrow.
	l = smooth(1.0 - (abs(co.x) - HALF_X * 0.35) / HALF_X)
	return f * g * l


def forge(body, eye: Vector, s: dict) -> int:
	moved = 0
	for v in body.data.vertices:
		w = weight(v.co, eye)
		if w <= 0.001:
			continue
		moved += 1
		# FORWARD is -Y in this pack, and the push is the whole muzzle.
		v.co.y -= s["reach"] * w
		# Sink as it goes, so the snout hangs rather than pointing.
		v.co.z -= s["drop"] * w
		# The lower jaw is heavier than the top.
		if v.co.z < eye.z + MOUTH_DZ:
			v.co.z -= s["jaw"] * w
		# Narrow toward the tip: the taper is proportional to how far out the
		# vertex has just been pushed, so the tip pinches and the root does not.
		v.co.x *= 1.0 - s["taper"] * w
		# A brow ridge, so the eyes end up UNDER something rather than sitting on
		# a smooth slope. Only just above the eye line, and only at the front.
		if eye.z < v.co.z < eye.z + 0.055 and v.co.y < eye.y + 0.02:
			v.co.y -= s["brow"] * smooth(1.0 - (v.co.z - eye.z) / 0.055)
	body.data.update()
	return moved


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:]
	body_path, out_dir = argv[0], os.path.abspath(argv[1])
	os.makedirs(out_dir, exist_ok=True)
	stem = os.path.splitext(os.path.basename(body_path))[0]

	for name in sorted(SHAPES):
		clear()
		objs = _import(body_path)
		body = biggest(objs)
		if body is None:
			raise SystemExit("no skinned body in %s" % body_path)
		eye = eye_centre(objs)
		n = forge(body, eye, SHAPES[name])
		dst = os.path.join(out_dir, "%s_%s.gltf" % (stem, name))
		bpy.ops.object.select_all(action="SELECT")
		# SEPARATE with the images left alone, so the forged body points at the
		# same PNGs the human one does. The UVs did not move, so the texture
		# still lands exactly where it did.
		bpy.ops.export_scene.gltf(filepath=dst, export_format="GLTF_SEPARATE",
								  export_keep_originals=True,
								  export_skins=True, export_animations=False)
		if not os.path.exists(dst):
			raise SystemExit("head was not written: %s" % dst)
		print("HEAD %-28s %4d verts moved  reach %.3f" % (
			os.path.basename(dst), n, SHAPES[name]["reach"]))


if __name__ == "__main__":
	main()

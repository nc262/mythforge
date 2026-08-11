extends Node
## AUDIT a base body against the six things it has to be true about.
##
## This exists because the candidate body was judged by LOOKING at it for most
## of a day. Renders answer "does this seem right", which is not a question with
## a wrong answer — a bare figure on a black background hid a uv error, and the
## one measurement taken by hand scored a KNOWN-GOOD pairing at 57% broken,
## because a nearest-surface normal test is not defined for an open garment like
## a tunic. Every goal below is instead a number with a threshold, and the pack
## body is run first as the control: a check the shipping body fails is a check
## that is wrong, not a body that is.
##
## Windowed, because G6 needs the renderer. Prints a table and asserts.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/body_audit.tscn
##
##   G1 RIG      every bone the pack body has, name for name
##   G2 SKIN     no vertex left unweighted
##   G3 STANCE   height and arm span within tolerance of the pack body
##   G4 EYES     the eye mesh sits in the skull, not floating off it
##   G5 MASKS    a real mask for every garment worn — present, and not blank
##   G6 CLOTHED  no skin visible through cloth
##
## G6 IS THE ONE THAT MATTERS and it is measured without any colour heuristic:
## render the dressed figure twice, once normally and once with the skin mesh
## HIDDEN, and count the pixels that change inside the torso. A hero whose
## clothes cover them looks identical either way, because nothing of them was
## showing. Every changed pixel is skin that was visible through the cloth.
const OUT := "user://audit"
const SIZE := 900
const BODY := "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_Male_FullBody%s.gltf"
const SHAPES := ["", "_makehuman"]
const DRESS := {"armor": "ranger", "legs": "ranger", "feet": "ranger", "hands": "ranger"}
const REFIT := {
	"armor": "res://assets3d/outfits/Modular Parts/Male_Ranger_Body_makehuman.gltf",
	"legs": "res://assets3d/outfits/Modular Parts/Male_Ranger_Legs_makehuman.gltf",
	"feet": "res://assets3d/outfits/Modular Parts/Male_Ranger_Feet_Boots_makehuman.gltf",
	"hands": "res://assets3d/outfits/Modular Parts/Male_Ranger_Arms_makehuman.gltf",
}

## The torso, as fractions of the framed figure. Deliberately NOT the whole
## silhouette: the head, the neck and the hands are skin that is SUPPOSED to
## show, and counting them would make a correct hero fail. Vertically this
## starts below the collar and stops above the hem; horizontally it keeps to the
## centre, because at this pose the hands hang at the sides inside the same band.
const TORSO := {"x0": 0.36, "x1": 0.64, "y0": 0.30, "y1": 0.46}
## A pixel counts as changed when any channel moves by more than this. Antialiasing
## along a silhouette edge moves pixels by a little in both renders, so a floor
## below the eye's threshold keeps edge shimmer out of the count.
const DELTA := 0.06
## Ceiling for G6, in pixels of the torso window. Calibrated against the SHIPPING
## body, which is the only figure known to be correct — see the printed control.
const POKE_MAX := 400

## G3 tolerances, as a fraction of the pack body's own measurement.
const STANCE_TOL := 0.06

var _vp: SubViewport = null
var _doll: ModularDoll = null
var _cam: Camera3D = null
var _fail: Array = []
var _pack := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_8X
	add_child(_vp)
	_doll = ModularDoll.new()
	_vp.add_child(_doll)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_vp.add_child(_cam)

	for shape in SHAPES:
		await _audit(shape)

	print("")
	if _fail.is_empty():
		print("BODY-AUDIT OK — %d bodies, six goals each" % SHAPES.size())
	else:
		for f in _fail:
			printerr("BODY-AUDIT FAIL: %s" % f)
		printerr("BODY-AUDIT FAILED — %d of %d checks" % [_fail.size(), SHAPES.size() * 6])
	get_tree().quit(0 if _fail.is_empty() else 1)


func _check(who: String, goal: String, ok: bool, detail: String) -> void:
	print("  %-11s %-8s %-4s %s" % [who, goal, "ok" if ok else "FAIL", detail])
	if not ok:
		_fail.append("%s %s — %s" % [who, goal, detail])


func _audit(shape: String) -> void:
	var who := "pack" if shape == "" else shape.substr(1)
	var path: String = BODY % shape
	if not ResourceLoader.exists(path):
		_check(who, "LOAD", false, "missing %s" % path)
		return
	print("\n%s" % who)
	_doll.sex = "male"
	_doll.mask_dir = "res://assets3d/masks/makehuman/" if shape != "" \
		else ModularDoll.MASK_DIR
	_doll.build(load(path))
	_doll.apply_look({"hair": "", "beard": "", "horns": "", "skin": "tan"})

	var body := _skin_mesh()
	var control := shape == ""

	# ── G1 RIG ──────────────────────────────────────────────────────────────
	var bones := {}
	for i in _doll.skeleton.get_bone_count():
		bones[_doll.skeleton.get_bone_name(i)] = true
	if control:
		_pack["bones"] = bones
		_check(who, "G1 RIG", bones.size() > 60, "%d bones" % bones.size())
	else:
		var missing: Array = []
		for b in _pack.get("bones", {}):
			if not bones.has(b):
				missing.append(b)
		_check(who, "G1 RIG", missing.is_empty(),
			"%d bones, %d missing%s" % [bones.size(), missing.size(),
				"" if missing.is_empty() else " " + str(missing.slice(0, 4))])

	# ── G2 SKIN ─────────────────────────────────────────────────────────────
	# A vertex with no weight is pinned at the origin the moment the rig moves,
	# which reads as a spike through the figure and only in certain poses.
	var bare := 0
	var verts := 0
	if body != null:
		var arrays: Array = body.mesh.surface_get_arrays(0)
		var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := 4 if w.size() % 8 != 0 else 8
		verts = w.size() / per
		for v in verts:
			var s := 0.0
			for k in per:
				s += w[v * per + k]
			if s < 0.001:
				bare += 1
	_check(who, "G2 SKIN", body != null and bare == 0,
		"%d/%d unweighted" % [bare, verts])

	# ── G3 STANCE ───────────────────────────────────────────────────────────
	var box: AABB = body.get_aabb() if body != null else AABB()
	if control:
		_pack["h"] = box.size.y
		_pack["w"] = box.size.x
		_check(who, "G3 STANCE", box.size.y > 1.0,
			"height %.3f span %.3f" % [box.size.y, box.size.x])
	else:
		var dh: float = absf(box.size.y - _pack["h"]) / _pack["h"]
		var dw: float = absf(box.size.x - _pack["w"]) / _pack["w"]
		_check(who, "G3 STANCE", dh < STANCE_TOL and dw < STANCE_TOL,
			"height %.3f (%+.1f%%) span %.3f (%+.1f%%)" % [
				box.size.y, dh * 100.0, box.size.x, dw * 100.0])

	# ── G4 EYES ─────────────────────────────────────────────────────────────
	# The eyes must be INSIDE the skull's own bounding box. Floating brows and
	# eyes standing proud of a differently shaped head were invisible until a
	# close render, and are a number: is the eye centre within the head's box.
	var eyes := _named("eyes")
	var head_top: float = box.position.y + box.size.y
	var seated := false
	var eye_y := 0.0
	if eyes != null and body != null:
		var eb: AABB = eyes.global_transform * eyes.get_aabb()
		eye_y = eb.position.y + eb.size.y * 0.5
		# Eyes sit in the upper tenth of a standing figure; well below that and
		# they have been left behind by a head that moved.
		seated = eye_y > head_top - 0.16 and eye_y < head_top
	_check(who, "G4 EYES", seated,
		"eye %.3f vs crown %.3f" % [eye_y, head_top])

	# ── G5 MASKS ────────────────────────────────────────────────────────────
	var worn := _dress(shape)
	var bad: Array = []
	for slot in worn:
		var img: Image = _doll._mask_for(str(worn[slot]))
		if img == null:
			bad.append("%s:absent" % slot)
			continue
		# Present is not enough: an all-black mask hides nothing and an all-white
		# one deletes the whole body, and both load without complaint.
		var white := 0
		var step := 8
		var seen := 0
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				seen += 1
				if img.get_pixel(x, y).r > 0.5:
					white += 1
		var frac := float(white) / maxf(1.0, float(seen))
		if frac < 0.005 or frac > 0.95:
			bad.append("%s:%.0f%%" % [slot, frac * 100.0])
	_check(who, "G5 MASKS", bad.is_empty(),
		"%d worn, %s" % [worn.size(), "all sane" if bad.is_empty() else str(bad)])

	# ── G6 CLOTHED ──────────────────────────────────────────────────────────
	_doll.frame_camera(_cam, 1.0, 0.60)
	var dressed := await _grab("%s_dressed" % who)
	if body != null:
		body.visible = false
	var without := await _grab("%s_noskin" % who)
	if body != null:
		body.visible = true
	var poke := _diff(dressed, without)
	if control:
		_pack["poke"] = poke
	_check(who, "G6 CLOTHED", poke <= POKE_MAX,
		"%d px of skin through cloth (ceiling %d)" % [poke, POKE_MAX])


## Pixels inside the torso window that change when the skin mesh is hidden.
## Those are pixels the skin was drawing, which is the definition of showing
## through — no colour matching, no threshold on what "skin" looks like.
func _diff(a: Image, b: Image) -> int:
	var x0 := int(TORSO["x0"] * a.get_width())
	var x1 := int(TORSO["x1"] * a.get_width())
	var y0 := int(TORSO["y0"] * a.get_height())
	var y1 := int(TORSO["y1"] * a.get_height())
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > DELTA or absf(p.g - q.g) > DELTA \
					or absf(p.b - q.b) > DELTA or absf(p.a - q.a) > DELTA:
				n += 1
	return n


func _dress(shape: String) -> Dictionary:
	for slot in ModularDoll.RENDERED_SLOTS:
		_doll.equip(str(slot), "")
	var worn := {}
	for slot in DRESS:
		if shape == "":
			if _doll.equip(str(slot), str(DRESS[slot])):
				worn[slot] = _doll._worn_file.get(slot, "")
		else:
			var p: String = REFIT.get(slot, "")
			if p != "" and ResourceLoader.exists(p) \
					and _doll.equip_scene(str(slot), load(p), true):
				worn[slot] = p
	return worn


func _skin_mesh() -> MeshInstance3D:
	var best: MeshInstance3D = null
	for mi in _doll._all_meshes(_doll):
		if mi.mesh == null:
			continue
		if best == null or mi.mesh.get_surface_count() > 0 \
				and _verts(mi) > _verts(best):
			best = mi
	return best


func _verts(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	var a: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	return v.size()


func _named(prefix: String) -> MeshInstance3D:
	for mi in _doll._all_meshes(_doll):
		if mi.name.to_lower().begins_with(prefix):
			return mi
	return null


func _grab(stem: String) -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, stem])
	return img

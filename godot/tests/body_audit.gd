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
##   G7 INTACT   no skin deleted where nothing covers it
##   G8 BUILT     the wardrobe still covers at every setting of the build knobs
##
## G6 IS THE ONE THAT MATTERS and it is measured without any colour heuristic:
## render the dressed figure twice, once normally and once with the skin mesh
## HIDDEN, and count the pixels that change inside the torso. A hero whose
## clothes cover them looks identical either way, because nothing of them was
## showing. Every changed pixel is skin that was visible through the cloth.
const OUT := "user://audit"
const SIZE := 900
const BODY := "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_%s_FullBody%s.gltf"
## body suffix, sex. The pack's own two are the controls; a candidate is
## compared against the pack body OF ITS OWN SEX, since a female pack body is
## not a defect for being narrower than a male one.
const SHAPES := [["", "male"], ["", "female"], ["_makehuman", "male"]]
## Bodies that are still CANDIDATES. Their goals are measured and printed like
## any other, but they do not fail the run — nothing in the game loads them, and
## a suite that is permanently red is a suite people stop reading. What they must
## never do is go quiet: the summary always says how many candidate goals are
## unmet, so adopting one means making those numbers pass first.
const CANDIDATE := {"_makehuman": true}
## BOTH cuts, because one wardrobe covering a body says nothing about the other.
## The peasant set is looser and hangs differently, which is exactly the case a
## mask baked against a fitted tunic is least likely to survive.
const OUTFITS := {
	"ranger": {"armor": "ranger", "legs": "ranger", "feet": "ranger", "hands": "ranger"},
	"peasant": {"armor": "peasant", "legs": "peasant", "feet": "peasant", "hands": "peasant"},
}
## The candidate has only the ranger set refitted onto it; peasant on that body
## would be measuring an unrefitted garment and calling the body guilty.
const CANDIDATE_OUTFITS := ["ranger"]
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
## Ceiling for G7. Larger than G6's because it reads the WHOLE frame rather than
## a window, and because a mask edge that lands a texel inside the cloth line is
## a hairline nobody sees — a real hole is thousands of pixels, not dozens.
## How many times the hole mask is eroded before anything is counted. See _holes.
const EROSION := 2
## Ceiling for G7, at twice the shipping body's own 353. The first value here was
## 900, chosen against a ONE-pass erosion that scored the pack at 727 — and the
## hole map showed that 727 to be a two-pixel rim down the inner arm, so the
## ceiling had been calibrated against an artifact and would have admitted a real
## defect of the same size.
const HOLE_MAX := 700

## G3 tolerances, as a fraction of the pack body's own measurement.
const STANCE_TOL := 0.06

## The builds G8 checks, as the player can actually set them. Both ends of every
## slider at once first, because a wardrobe that survives all-minimum and
## all-maximum survives the box they define; then the three that move the most
## flesh on their own, since a knob can be alone in pushing skin through a seam.
## Clip, and how far into it to hold. A wardrobe that covers a figure standing
## still is the easy half — the old swelled-garment approach passed standing and
## tore at the knee the moment the rig moved, so a pose sweep is the check that
## would have caught it. Names are searched across every library and a missing
## one is skipped, since the two animation packs do not share a naming scheme.
const POSES := {
	"stand":  ["Sword_Block", 0.0],
	"swing":  ["Sword_Regular_Combo", 0.55],
	"idle":   ["Idle_Loop", 0.40],
	"cast":   ["Spell_Simple_Enter", 0.35],
	"wave":   ["Wave", 0.45],
}

const BUILDS := {
	"lean":   {"height": 0, "build": 0, "frame": 0, "weight": 0,
			   "chest": 0, "seat": 0, "belly": 0},
	"heavy":  {"height": 100, "build": 100, "frame": 100, "weight": 100,
			   "chest": 100, "seat": 100, "belly": 100},
	"stout":  {"height": 0, "build": 100, "frame": 100, "weight": 100},
	"belly":  {"belly": 100},
	"chest":  {"chest": 100},
	"seat":   {"seat": 100},
}

var _vp: SubViewport = null
var _doll: ModularDoll = null
var _cam: Camera3D = null
var _fail: Array = []
var _soft: Array = []
var _who := ""
var _pack := {}
var _holes_at := {}


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

	for row in SHAPES:
		await _audit(str(row[0]), str(row[1]))

	print("")
	for s2 in _soft:
		print("BODY-AUDIT candidate not ready: %s" % s2)
	if _fail.is_empty():
		print("BODY-AUDIT OK — %d bodies, eight goals each%s" % [
			SHAPES.size(),
			"" if _soft.is_empty() else "  (%d candidate goal(s) unmet)" % _soft.size()])
	else:
		for f in _fail:
			printerr("BODY-AUDIT FAIL: %s" % f)
		printerr("BODY-AUDIT FAILED — %d of %d checks" % [_fail.size(), SHAPES.size() * 8])
	get_tree().quit(0 if _fail.is_empty() else 1)


func _check(who: String, goal: String, ok: bool, detail: String) -> void:
	var soft: bool = who.begins_with("makehuman")
	var tag := "ok" if ok else ("cand" if soft else "FAIL")
	print("  %-11s %-11s %-5s %s" % [who, goal, tag, detail])
	if ok:
		return
	if soft:
		_soft.append("%s %s — %s" % [who, goal, detail])
	else:
		_fail.append("%s %s — %s" % [who, goal, detail])


func _audit(shape: String, sex: String) -> void:
	var who := ("pack" if shape == "" else shape.substr(1)) + "-" + sex.substr(0, 1)
	var path: String = BODY % [sex.capitalize(), shape]
	if not ResourceLoader.exists(path):
		_check(who, "LOAD", false, "missing %s" % path)
		return
	print("\n%s" % who)
	_doll.sex = sex
	_doll.mask_dir = "res://assets3d/masks/makehuman/" if shape != "" \
		else ModularDoll.MASK_DIR
	_doll.build(load(path))
	_doll.apply_look({"hair": "", "beard": "", "horns": "", "skin": "tan"})

	var body := _skin_mesh()
	var control := shape == ""
	var ctl: Dictionary = _pack.get(sex, {})

	# ── G1 RIG ──────────────────────────────────────────────────────────────
	var bones := {}
	for i in _doll.skeleton.get_bone_count():
		bones[_doll.skeleton.get_bone_name(i)] = true
	if control:
		ctl["bones"] = bones
		_pack[sex] = ctl
		_check(who, "G1 RIG", bones.size() > 60, "%d bones" % bones.size())
	else:
		var missing: Array = []
		for b in ctl.get("bones", {}):
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
		ctl["h"] = box.size.y
		ctl["w"] = box.size.x
		_pack[sex] = ctl
		_check(who, "G3 STANCE", box.size.y > 1.0,
			"height %.3f span %.3f" % [box.size.y, box.size.x])
	else:
		var dh: float = absf(box.size.y - ctl["h"]) / ctl["h"]
		var dw: float = absf(box.size.x - ctl["w"]) / ctl["w"]
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

	# ── G5 to G8, ONCE PER OUTFIT ───────────────────────────────────────────
	# One wardrobe covering a body says nothing about the other. The peasant cut
	# is looser and hangs differently, which is the case a mask baked against a
	# fitted tunic is least likely to survive.
	var cuts: Array = CANDIDATE_OUTFITS if not control else OUTFITS.keys()
	for cut in cuts:
		var worn := _dress(shape, str(cut))
		var tag := "%s/%s" % [who, cut]

		# ── G5 MASKS ────────────────────────────────────────────────────────
		var bad: Array = []
		for slot in worn:
			var img: Image = _doll._mask_for(str(worn[slot]))
			if img == null:
				bad.append("%s:absent" % slot)
				continue
			# Present is not enough: an all-black mask hides nothing and an
			# all-white one deletes the whole body, and both load without
			# complaint.
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
		_check(tag, "G5 MASKS", bad.is_empty(),
			"%d worn, %s" % [worn.size(), "all sane" if bad.is_empty() else str(bad)])

		# ── G6 CLOTHED ──────────────────────────────────────────────────────
		# FRAMED ONCE per configuration. Both captures of a pair must share a
		# camera or the diff compares two different pictures.
		_doll.stand()
		_doll.frame_camera(_cam, 1.0, 0.60)
		var dressed := await _grab("%s_%s_dressed" % [who, cut])
		if body != null:
			body.visible = false
		var without := await _grab("%s_%s_noskin" % [who, cut])
		if body != null:
			body.visible = true
		var poke := _diff(dressed, without, "%s_%s" % [who, cut])
		_check(tag, "G6 CLOTHED", poke <= POKE_MAX,
			"%d px of skin through cloth (ceiling %d)" % [poke, POKE_MAX])

		# ── G8 BUILT, across every build AND every pose ─────────────────────
		# EVERY HERO IS SOMEWHERE ELSE ON THESE SLIDERS, and none of them stands
		# still. Seven knobs are open at the forge and the mask is baked ONCE,
		# against a neutral body in a rest pose. The old swelled-garment approach
		# passed standing and tore at the knee the moment the rig moved, so the
		# pose half of this sweep is the one that would have caught it.
		var worst := 0
		var worst_at := "-"
		var tried := 0
		for pose in POSES:
			if not _pose(str(pose)):
				continue
			# THE BUILD'S OWN CONTRIBUTION, not the absolute count. A pose puts
			# skin legitimately in front of cloth — during a sword swing the hand
			# and forearm cross the chest, inside the torso window — and an
			# absolute count calls that poke-through. The shipping body scored
			# 7,804 px at 'heavy/swing' on the first run for exactly that reason.
			# Measuring the same pose at neutral first and subtracting cancels
			# every artifact the pose itself creates, and what is left is the one
			# thing this goal is asking: does moving the sliders break the cover.
			_doll.apply_build(Rules.hero_body({"race": "Human", "sex": sex}))
			_doll.frame_camera(_cam, 1.0, 0.60)
			var base_on := await _grab("%s_%s_base_%s" % [who, cut, pose])
			if body != null:
				body.visible = false
			var base_off := await _grab("%s_%s_base_%s_noskin" % [who, cut, pose])
			if body != null:
				body.visible = true
			var base := _diff(base_on, base_off)

			for preset in BUILDS:
				_doll.apply_build(Rules.hero_body({"race": "Human", "sex": sex,
					"build": BUILDS[preset]}))
				tried += 1
				# RE-FRAMED per configuration: the torso window is fractions of
				# the frame, and `height` at 0 shrinks the figure to 0.86, which
				# slides that window off the torso and onto bare arm.
				_doll.frame_camera(_cam, 1.0, 0.60)
				var on := await _grab("%s_%s_%s_%s" % [who, cut, preset, pose])
				if body != null:
					body.visible = false
				var off := await _grab("%s_%s_%s_%s_noskin" % [who, cut, preset, pose])
				if body != null:
					body.visible = true
				var d := _diff(on, off) - base
				if d > worst:
					worst = d
					worst_at = "%s/%s" % [preset, pose]
		_check(tag, "G8 BUILT", worst <= POKE_MAX,
			"%d configs, worst +%d px over the same pose at '%s' (ceiling %d)" % [
				tried, worst, worst_at, POKE_MAX])

		# BACK TO NEUTRAL AND STANDING before anything else is measured. The
		# sweep above leaves the doll wearing the last build it tried, in the
		# last pose it held, and G7 read 879 px in that state against 353 in
		# this one — a number about the seat slider at full, not about the mask.
		_doll.apply_build(Rules.hero_body({"race": "Human", "sex": sex}))
		_doll.stand()

		# ── G7 INTACT ───────────────────────────────────────────────────────
		# The mask cutting too much reads as a HOLE — at a wrist, at a throat —
		# and G6 cannot see it: deleting skin that was never showing changes
		# nothing when the skin is hidden. So it needs its own picture.
		_doll.frame_camera(_cam, 1.0, 0.60)
		var clothed := await _grab("%s_%s_clothed" % [who, cut])
		_garments(false)
		var masked := await _grab("%s_%s_maskedskin" % [who, cut])
		_garments(true)
		for slot in ModularDoll.RENDERED_SLOTS:
			_doll.equip(str(slot), "")
		var naked := await _grab("%s_%s_bare" % [who, cut])
		_who = "%s_%s" % [who, cut]
		var holes := _holes(naked, masked, clothed)
		var band := []
		for k in _holes_at:
			if int(_holes_at[k]) > 0:
				band.append("%s %d" % [k, _holes_at[k]])
		_check(tag, "G7 INTACT", holes <= HOLE_MAX,
			"%d px deleted with nothing over it (ceiling %d)%s" % [
				holes, HOLE_MAX, "" if band.is_empty() else "  [" + ", ".join(band) + "]"])



## A hole: skin the bare figure draws, the masked figure does not, and no cloth
## covers. Read over the WHOLE frame, not the torso window — the places a greedy
## mask shows first are the wrist and the throat, and both are outside it.
## ERODED BY ONE, and the shipping body is why. Counted raw, it scored 1,491 —
## and the shipping body is the one figure known to be correct, so that was the
## CHECK being wrong. The pixels are a one-deep rim: along every garment edge the
## cloth silhouette and the skin silhouette land a pixel apart, antialiasing puts
## both at partial alpha, and a hard 0.5 threshold calls the sliver a hole. Around
## a whole dressed figure that is a thousand pixels of nothing.
##
## A hole you can SEE is a region. Requiring the four neighbours to qualify too
## erases a rim exactly and leaves anything with an interior untouched.
func _holes(bare: Image, masked: Image, clothed: Image) -> int:
	var w := bare.get_width()
	var h := bare.get_height()
	var raw := PackedByteArray()
	raw.resize(w * h)
	# A MAP, not just a tally. Bands narrow "where" down to a fifth of the figure
	# and no further, and the difference between a hole in a chest and a sliver
	# of background seen through an armpit is a shape, not a count. Written
	# beside the captures as `<body>_holes.png`: the figure in grey, every
	# counted pixel in red.
	var map := Image.create(w, h, false, Image.FORMAT_RGBA8)
	map.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var lost := bare.get_pixel(x, y).a > 0.5 \
				and masked.get_pixel(x, y).a <= 0.5 \
				and clothed.get_pixel(x, y).a <= 0.5
			raw[y * w + x] = 1 if lost else 0
			if bare.get_pixel(x, y).a > 0.5:
				map.set_pixel(x, y, Color(0.30, 0.30, 0.32, 1.0))
			elif clothed.get_pixel(x, y).a > 0.5:
				map.set_pixel(x, y, Color(0.16, 0.20, 0.16, 1.0))
	# WHERE, not just how many. A count sends you back to looking at the picture
	# to find out whether it is a wrist, a throat or a whole torso — which is the
	# habit this harness exists to break. Reported as bands down the figure,
	# because the fix differs completely by region.
	# ERODED TWICE, not once. One pass was calibrated against the shipping body's
	# 727 — and the hole map showed what that 727 actually is: a two-pixel rim
	# down the inner arm and across the armpit, where the sleeve's silhouette and
	# the arm's differ by a hair. A ceiling set to admit that admits anything. A
	# second pass erases a 2-deep rim and leaves the candidate's real areas —
	# bands down both inner arms, a wedge at the crotch — standing.
	for _pass in EROSION:
		var next := raw.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				if raw[y * w + x] == 0:
					continue
				if raw[(y - 1) * w + x] == 0 or raw[(y + 1) * w + x] == 0 \
						or raw[y * w + x - 1] == 0 or raw[y * w + x + 1] == 0:
					next[y * w + x] = 0
		raw = next

	var n := 0
	_holes_at = {"head": 0, "chest": 0, "waist": 0, "legs": 0, "feet": 0}
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if raw[y * w + x] == 1:
				n += 1
				var f := float(y) / float(h)
				var band := "feet"
				if f < 0.26:
					band = "head"
				elif f < 0.40:
					band = "chest"
				elif f < 0.52:
					band = "waist"
				elif f < 0.80:
					band = "legs"
				_holes_at[band] = int(_holes_at[band]) + 1
				map.set_pixel(x, y, Color(1.0, 0.15, 0.15, 1.0))
	map.save_png("%s/%s_holes.png" % [OUT, _who])
	return n


func _garments(v: bool) -> void:
	for slot in _doll._extern:
		var n = _doll._extern[slot]
		if n is Node3D:
			n.visible = v


## Pixels inside the torso window that change when the skin mesh is hidden.
## Those are pixels the skin was drawing, which is the definition of showing
## through — no colour matching, no threshold on what "skin" looks like.
func _diff(a: Image, b: Image, dump := "") -> int:
	var x0 := int(TORSO["x0"] * a.get_width())
	var x1 := int(TORSO["x1"] * a.get_width())
	var y0 := int(TORSO["y0"] * a.get_height())
	var y1 := int(TORSO["y1"] * a.get_height())
	# The window itself, drawn on request. A count inside a rectangle is only as
	# honest as the rectangle, and this is the picture that says whether what is
	# being counted is a belly through a tunic or a hand in front of one.
	var map: Image = null
	if dump != "":
		map = Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
		map.fill(Color(0, 0, 0, 0))
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			# CLOTH MUST BE BEHIND IT. Skin drawing over cloth is poke-through;
			# skin drawing over BACKGROUND is a hero the vendor cut that way, and
			# the female ranger set is exactly that — a bare midriff and open
			# shoulders. Without this clause the check calls a costume a defect,
			# which is what it did: 1,116 px against the male's 66, every pixel
			# of it skin that is supposed to show.
			var behind := q.a > 0.5
			var hit := behind and (absf(p.r - q.r) > DELTA or absf(p.g - q.g) > DELTA \
					or absf(p.b - q.b) > DELTA or absf(p.a - q.a) > DELTA)
			if map != null:
				map.set_pixel(x, y, Color(1, 0.15, 0.15, 1) if hit
					else Color(0.25, 0.25, 0.28, 1))
			if hit:
				n += 1
	if map != null:
		map.save_png("%s/%s_poke.png" % [OUT, dump])
	return n


func _dress(shape: String, cut: String) -> Dictionary:
	for slot in ModularDoll.RENDERED_SLOTS:
		_doll.equip(str(slot), "")
	var want: Dictionary = OUTFITS[cut]
	var worn := {}
	for slot in want:
		if shape == "":
			if _doll.equip(str(slot), str(want[slot])):
				worn[slot] = _doll._worn_file.get(slot, "")
		else:
			var p: String = REFIT.get(slot, "")
			if p != "" and ResourceLoader.exists(p) \
					and _doll.equip_scene(str(slot), load(p), true):
				worn[slot] = p
	return worn


## Hold one frame of one clip. Returns false when the library has no such name,
## which is normal rather than an error: the two animation packs do not share a
## naming scheme, and a pose this rig does not have is skipped, never faked.
func _pose(name: String) -> bool:
	var spec: Array = POSES[name]
	var ap := _doll._play([str(spec[0])])
	if ap == null:
		return false
	var extra := float(spec[1])
	if extra > 0.0:
		ap.advance(extra)
	ap.pause()
	return true


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

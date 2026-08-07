extends Node
## Dev harness — does the FIGURE LIVE? Two claims, and neither one is a boolean.
##
##   SHAPE   a slider called Chest makes a chest. The old `chest` knob scaled
##           spine_03, which widens a whole ribcage: it was doing something, it
##           passed every assertion, and it never once made a bust. The only
##           test that could have caught that is a picture of 0 beside 100.
##   MOTION  flesh keeps moving after the bone stops. A still cannot show that,
##           so this renders a STRIP of consecutive frames and then measures the
##           same run twice — springs off, springs on — and prints how far apart
##           the two are. A jiggle that is wired up but doing nothing scores 0
##           and looks exactly like a pass in every other harness.
##
## Windowed only; headless uses a dummy rasterizer and every capture is blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/jiggle_shot.tscn
const OUT := "user://jiggle"
const SIZE := 1024

## The soft-tissue knobs, each at the two ends and the middle, and the angle
## that actually shows it. A seat judged from the front is a test of nothing.
const KNOBS := [
	["chest", -22.0],
	["belly", 84.0],
	["seat", 158.0],
]
const VALUES := [0, 50, 100]

## Dressed as well as bare, because the whole reason the garments were re-rigged
## is that a bust under a tunic has to move the tunic. Bare proves the body;
## dressed proves the wardrobe followed.
const DRESS := {"armor": "ranger", "legs": "ranger", "feet": "ranger", "hands": "ranger"}

## Frames in the motion strip, and how many rendered frames to let pass between
## captures. 4 is enough for the spring to have moved visibly and few enough
## that sixteen captures still cover most of a 60-frame idle loop.
const STRIP := 16
const EVERY := 4

var _vp: SubViewport = null
var _doll: ModularDoll = null
var _pivot: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	add_child(_vp)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_doll = ModularDoll.new()
	_pivot.add_child(_doll)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.5
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, -140, 0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.fov = 34.0

	for who in ["female", "male"]:
		await _shape_sheet(who)
	# Standing still first, then being TURNED — because the Gear page has both
	# and they are not the same test. An idle loop moves the spine by a couple of
	# degrees; a drag swings the whole figure through ninety, and that is the
	# motion a player actually causes.
	await _motion(false, 220.0)
	await _motion(true, 220.0)
	_score()
	await _alive()
	print("JIGGLE done — %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()


## One image per knob per value, bare and dressed. The point of comparison is
## `_50`: if 0 and 100 both look like it, the bone is not moving the mesh.
func _shape_sheet(who: String) -> void:
	_doll.sex = who
	_doll.build(load(_doll.body_path()))
	for pair in KNOBS:
		var knob := str(pair[0])
		_pivot.rotation_degrees.y = float(pair[1])
		for dressed in [false, true]:
			for slot in ModularDoll.RENDERED_SLOTS:
				_doll.equip(slot, "")
			if dressed:
				for slot in DRESS:
					_doll.equip(str(slot), str(DRESS[slot]))
			for v in VALUES:
				# Only the knob under test moves. Sweeping several at once makes
				# a picture that proves something changed and nothing about what.
				_doll.apply_build({knob: Rules.build_factor(knob, v)})
				_doll.frame_camera(_cam, 1.0, 0.52)
				var stem := "%s_%s_%s_%d" % [who, knob, "worn" if dressed else "bare", v]
				await _grab(stem)


## Turn the figure and watch the flesh lag behind it.
##
## THE POSE IS FROZEN ON PURPOSE. The obvious test — run the idle twice, once
## with springs and once without, and diff the frames — does not work, and the
## first attempt at it lit up the entire silhouette. Two runs of a real-time
## animation never land on the same phase, so the diff is dominated by the whole
## body being a few milliseconds apart, and the jiggle is lost inside it.
##
## Held still, springs-off is perfectly static. Every pixel that changes is then
## the simulation and nothing else, and the number means what it says.
func _motion(springs: bool, spin: float) -> void:
	_doll.sex = "female"
	_doll.build(load(_doll.body_path()))
	for slot in DRESS:
		_doll.equip(str(slot), str(DRESS[slot]))
	# Dialled up, because a jiggle you have to hunt for is not evidence of one.
	_doll.apply_build({
		"chest": Rules.build_factor("chest", 100),
		"seat": Rules.build_factor("seat", 100),
		"belly": Rules.build_factor("belly", 78),
	})
	_pivot.rotation_degrees.y = -22.0
	_doll.frame_camera(_cam, 1.0, 0.52)
	if _doll.skeleton != null:
		var sim := _doll.skeleton.get_node_or_null("Jiggle")
		if sim == null:
			push_error("JIGGLE: no simulator on the skeleton — the body has no soft-tissue bones")
		else:
			# The SHIPPED settings, never overridden here. A harness that tunes
			# the thing it is measuring is measuring the harness.
			sim.active = springs
	var tag := "on" if springs else "off"
	for i in STRIP:
		for _f in EVERY:
			# The turn is applied per RENDERED frame, not per capture. A spring
			# integrates every frame, so handing it the whole ninety degrees in
			# one step would teleport the figure and tell us nothing about how it
			# behaves under a drag.
			_pivot.rotation_degrees.y += spin / float(STRIP * EVERY)
			await get_tree().process_frame
		await _grab("motion_%s_%02d" % [tag, i])


## The Gear page as the player sees it: idle running, springs live. Nothing is
## measured here — it is the strip you look at.
func _alive() -> void:
	_doll.sex = "female"
	_doll.build(load(_doll.body_path()))
	for slot in DRESS:
		_doll.equip(str(slot), str(DRESS[slot]))
	_doll.apply_build({
		"chest": Rules.build_factor("chest", 100),
		"seat": Rules.build_factor("seat", 100),
		"belly": Rules.build_factor("belly", 78),
	})
	_pivot.rotation_degrees.y = -22.0
	_doll.frame_camera(_cam, 1.0, 0.52)
	_doll.live()
	var ap := _doll._find_anim(_doll._body)
	print("JIGGLE live clip=%s playing=%s" % [
		"none" if ap == null else ap.current_animation, ap != null and ap.is_playing()])
	for i in STRIP:
		for _f in EVERY:
			await get_tree().process_frame
		await _grab("alive_%02d" % i)


## How far apart the two runs are, per frame, in mean absolute luminance.
##
## THE NUMBER IS THE TEST. Everything else here can pass with the simulator
## wired up and inert: the node exists, the bones resolve, the strip renders,
## and every frame is identical to the springs-off run. Reading the log instead
## of the render has cost this project a round more than once — so read the
## render, arithmetically.
func _score() -> void:
	var total := 0.0
	var peak := 0.0
	var seen := 0
	for i in STRIP:
		var a := Image.load_from_file("%s/motion_on_%02d.png" % [OUT, i])
		var b := Image.load_from_file("%s/motion_off_%02d.png" % [OUT, i])
		if a == null or b == null:
			continue
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		var sum := 0.0
		var hi := 0.0
		# Every 4th pixel each way. A 1024x1024 pair is a million comparisons in
		# GDScript per frame, and the answer does not change.
		for y in range(0, a.get_height(), 4):
			for x in range(0, a.get_width(), 4):
				var d := absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
				sum += d
				hi = maxf(hi, d)
		var mean := sum / float((a.get_height() / 4) * (a.get_width() / 4))
		total += mean
		peak = maxf(peak, hi)
		seen += 1
	if seen > 0:
		print("JIGGLE springs move mean %.5f of the picture, peak pixel %.3f, over %d frames"
			% [total / float(seen), peak, seen])
		assert(peak > 0.15, "JIGGLE: the springs are wired up and inert")


func _grab(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, stem])

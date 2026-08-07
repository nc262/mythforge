extends Node
## Dev harness — AUDITION every clip in the library, because the names lie.
##
## `Idle_Rail_Call` might be a wave or it might be a man leaning on a fence
## shouting. `NinjaJump_Start` might be a skip or it might carry the figure clean
## out of frame. The gesture list the Gear page plays from has to be chosen by
## looking, and the alternative — picking off the names and finding out in the
## game — is how `Idle_FoldArms` got picked as the guard stance that hides the
## weapon you just equipped.
##
## Writes one contact strip per clip: SHOTS frames evenly across its length, so a
## clip that translates shows the figure walking out of the frame and a clip that
## does nothing shows five identical cells.
##
## Windowed only; headless captures are blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/gesture_shot.tscn
const OUT := "user://gestures"
const CELL := 320
const SHOTS := 6

## Dressed and armed — a sword swing judged on an empty hand tells you nothing
## about whether the blade stays in shot.
const DRESS := {"armor": "ranger", "legs": "ranger", "feet": "ranger",
	"hands": "ranger", "weapon": "sword"}

var _vp: SubViewport = null
var _doll: ModularDoll = null
var _cam: Camera3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL, CELL)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var pivot := Node3D.new()
	pivot.rotation_degrees.y = -24.0
	_vp.add_child(pivot)
	_doll = ModularDoll.new()
	pivot.add_child(_doll)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.fov = 34.0

	_doll.sex = "female"
	_doll.build(load(_doll.body_path()))
	for slot in DRESS:
		_doll.equip(str(slot), str(DRESS[slot]))
	# Framed ONCE, on the standing pose, and never re-framed per clip. Reframing
	# would silently re-centre a clip that travels, which is exactly the thing
	# this harness exists to catch.
	_doll.frame_camera(_cam, 1.0, 0.62)

	var ap := _doll._find_anim(_doll._body)
	if ap == null:
		push_error("GESTURE: no AnimationPlayer")
		get_tree().quit()
		return
	var names := ap.get_animation_list()
	names.sort()
	for nm in names:
		await _strip(ap, str(nm))
	print("GESTURE audited %d clips — %s" % [names.size(), ProjectSettings.globalize_path(OUT)])
	get_tree().quit()


## SHOTS frames evenly across one clip, side by side in a single PNG.
func _strip(ap: AnimationPlayer, nm: String) -> void:
	var clip := ap.get_animation(nm)
	if clip == null:
		return
	var sheet := Image.create(CELL * SHOTS, CELL, false, Image.FORMAT_RGBA8)
	ap.play(nm)
	for i in SHOTS:
		# `seek` with update=true, so the pose is applied NOW rather than on the
		# next process tick — otherwise every capture is one frame stale and the
		# last one is a frame that never existed.
		ap.seek(clip.length * (float(i) / float(SHOTS - 1)) * 0.999, true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(CELL * i, 0))
	ap.stop()
	# A clip from a named library arrives as "ual1/Idle", and the slash is a
	# directory that does not exist rather than part of a filename.
	sheet.save_png("%s/%s.png" % [OUT, nm.replace("/", "__")])

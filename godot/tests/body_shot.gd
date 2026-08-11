extends Node
## Dev harness — a candidate base body DRESSED, which is the only test that counts.
##
## Everything rendered of the MakeHuman body so far has been a bare figure on a
## black background, and that is precisely the condition under which a uv error
## hides. The new body wears OUR uv layout, transferred rather than its own, so
## that the twenty masks in `masks/` keep working — hidden-surface removal reads
## them BY UV, NOT BY POSITION. If that transfer is approximately right rather
## than part-for-part, a naked render looks perfect and a dressed one has skin
## coming through the tunic.
##
## So: both bodies, bare and dressed, front and back. The bare pair says whether
## the skin lands; the dressed pair says whether the MASK lands, and they are not
## the same question.
##
## Windowed only; headless captures are blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/body_shot.tscn
const OUT := "user://bodies"
const SIZE := 900
const BODY := "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_Male_FullBody%s.gltf"
## "" is the pack's body and must be FIRST — it is the control, and the mask
## cutting correctly on it is what makes a bad cut on the other one legible.
const SHAPES := ["", "_makehuman"]
const DRESS := {"armor": "ranger", "legs": "ranger", "feet": "ranger", "hands": "ranger"}

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
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, -138, 0)
	fill.light_energy = 0.55
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_vp.add_child(_cam)

	for shape in SHAPES:
		var path: String = BODY % shape
		if not ResourceLoader.exists(path):
			push_error("BODY: missing %s" % path)
			continue
		_doll.sex = "male"
		_doll.build(load(path))
		_doll.apply_look({"hair": "", "beard": "", "horns": "", "skin": "tan"})
		for dressed in [false, true]:
			for slot in ModularDoll.RENDERED_SLOTS:
				_doll.equip(str(slot), "")
			if dressed:
				for slot in DRESS:
					_doll.equip(str(slot), str(DRESS[slot]))
			# FRONT and BACK. A tunic hides the chest either way, but the seat
			# and the shoulder blades are where a mask that is a few texels out
			# shows first, and nothing rendered so far has looked at the back.
			for yaw in [0.0, 180.0]:
				_pivot.rotation_degrees.y = yaw
				_doll.frame_camera(_cam, 1.0, 0.60)
				await _grab("body%s_%s_%d" % [
					shape if shape != "" else "_pack",
					"worn" if dressed else "bare", int(yaw)])
		print("BODY %s rendered" % (shape if shape != "" else "_pack"))
	print("BODIES done — %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _grab(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("%s/%s.png" % [OUT, stem])

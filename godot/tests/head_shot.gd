extends Node
## Dev harness — the FORGED HEADS, close, in profile and three-quarter.
##
## Its own scene rather than another pass inside jiggle_shot, which is already
## thirteen minutes long: a head is iterated on, and an iteration you have to
## wait a quarter of an hour for is an iteration you stop doing.
##
## Windowed only; headless captures are blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/head_shot.tscn
const OUT := "user://heads"
const SIZE := 900
const BODIES := "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_%s_FullBody%s.gltf"
## "" is the pack's own head and must be FIRST — a candidate is judged against
## the face it is meant to replace, not against an idea of one.
##
## The three displaced heads `forge_head.py` made are gone and so are their
## entries: pushing a band of vertices forward inflates a face, it does not
## sculpt one, and all three rendered as smooth domes with the eyes buried. What
## is left is a real alternative — MakeHuman's CC0 base, put on this rig by
## scripts/forge_base_body.py. 13,380 quads against 7,281 mixed, and a face with
## enough geometry to have features at all.
const SHAPES := ["", "_makehuman"]

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
	key.rotation_degrees = Vector3(-28, 38, 0)
	key.light_energy = 1.7
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-6, -132, 0)
	fill.light_energy = 0.55
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_vp.add_child(_cam)

	for who in ["male", "female"]:
		for shape in SHAPES:
			var path: String = BODIES % [who.capitalize(), shape]
			if not ResourceLoader.exists(path):
				push_error("HEAD: missing %s" % path)
				continue
			_doll.sex = who
			_doll.build(load(path))
			# Bare, bald, and no brows. A muzzle judged under a fringe is a
			# muzzle judged under a fringe.
			_doll.apply_look({"hair": "", "beard": "", "horns": "",
				"skin": "verdant" if shape != "" else "tan"})
			var top := _top_y()
			var eye := _eye_y()
			print("HEAD %s%s  top %.3f  eyes %.3f" % [who, shape, top, eye])
			for yaw in [-8.0, -90.0]:
				_pivot.rotation_degrees.y = yaw
				# Framed on the EYES, not the crown. `_top_y` is the highest
				# point of anything visible, which on a bald head is the crown
				# — aiming there and pulling in half a metre fills the frame
				# with forehead, which is exactly what the first run rendered.
				_cam.position = Vector3(0.0, eye + 0.01, 0.62)
				_cam.look_at(Vector3(0.0, eye - 0.03, 0.0), Vector3.UP)
				await _grab("head_%s%s_%d" % [who, shape if shape != "" else "_human",
					int(-yaw)])
	print("HEADS done — %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()


## The eye mesh's own height — the one landmark on a head that is always where
## you think it is, whatever has been done to the muzzle around it.
func _eye_y() -> float:
	for mi in _doll._all_meshes(_doll):
		if not mi.name.to_lower().begins_with("eyes"):
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		return box.position.y + box.size.y * 0.5
	return _top_y() - 0.12


func _top_y() -> float:
	var top := -1e9
	for mi in _doll._all_meshes(_doll):
		if not mi.visible:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		top = maxf(top, box.position.y + box.size.y)
	return top


func _grab(stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("%s/%s.png" % [OUT, stem])

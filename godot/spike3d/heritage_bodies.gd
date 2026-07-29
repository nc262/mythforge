extends Node
## SPIKE — nine heritages, two sexes, from ONE mesh.
##
## The claim being tested: race and sex are bone SCALE on a single shared
## skeleton, not eighteen bodies. If that holds, equipment is authored per body
## TIER and follows the scaling for free, and the combinatorial explosion that
## makes 90 forms x 9 races x 2 sexes = 1,620 meshes never happens.
##
## Reads the same data the rules read — Rules.body_profile() /
## Rules.heritage_size() — so what you see here is what combat resolves against.
## Nothing about the look is authored in this file.
##
## Run WINDOWED (headless renders blank):
##   Godot_v4.7-stable_win64.exe --path godot res://spike3d/heritage_bodies.tscn

const MODEL := "res://spike3d/models/AnimationLibrary_Godot_Standard.gltf"
const OUT := "user://spike3d"
const SIZE := 640

## Rigify DEF- naming, which is what this rig uses and what makes it portable:
## Rigify maps 1:1 onto Godot's SkeletonProfileHumanoid, the hub every other
## humanoid (Mixamo, VRM, hand-sculpted, generated) retargets through. Groups,
## not individual bones, so a rig with a different spine subdivision still works.
const GROUPS := {
	"head": ["DEF-head"],
	"leg": ["DEF-thigh.L", "DEF-thigh.R", "DEF-shin.L", "DEF-shin.R"],
	"arm": ["DEF-upper_arm.L", "DEF-upper_arm.R", "DEF-forearm.L", "DEF-forearm.R"],
	"girth": ["DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003"],
	"shoulder": ["DEF-shoulder.L", "DEF-shoulder.R"],
}

var _vp: SubViewport
var _root: Node3D
var _skel: Skeleton3D
var _cam: Camera3D
var _rest: Dictionary = {}   # bone idx -> rest Transform3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build()
	await get_tree().process_frame
	if _skel == null:
		push_error("SPIKE: no skeleton")
		get_tree().quit(1)
		return
	var races := ["Human", "Elf", "Dwarf", "Halfling", "Half-Orc", "Tiefling",
			"Dragonborn", "Gnome", "Half-Elf"]
	for sex in ["male", "female"]:
		for race in races:
			_apply_body(race, sex)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var p := Rules.body_profile(race, sex)
			print("  %-11s %-6s size=%-6s tier=%-7s h=%.2f girth=%.2f" % [
				race, sex, Rules.heritage_size(race), Rules.body_tier(race),
				p["height"], p["girth"]])
			_shoot("body_%s_%s" % [sex, race.to_lower().replace("-", "")])
	print("SPIKE: wrote to ", ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var packed: PackedScene = load(MODEL)
	if packed == null:
		return
	_root = packed.instantiate()
	_vp.add_child(_root)
	_skel = _find_skel(_root)
	if _skel != null:
		for i in _skel.get_bone_count():
			_rest[i] = _skel.get_bone_pose(i)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-32, 28, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.light_color = Color(0.6, 0.7, 1.0)
	fill.rotation_degrees = Vector3(-12, -130, 0)
	_vp.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.39, 0.48)
	e.ambient_light_energy = 0.9
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_frame_fixed()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f != null:
			return f
	return null


func _bone(nm: String) -> int:
	return _skel.find_bone(nm)


## Scale by GROUP, from the heritage profile. Height is applied to the root node
## rather than a bone: scaling the hips would drag the feet through the floor,
## and every pose in the animation library assumes the feet are on the ground.
func _apply_body(race: String, sex: String) -> void:
	for i in _rest:
		_skel.set_bone_pose(i, _rest[i])
	var p := Rules.body_profile(race, sex)
	for g in GROUPS:
		var f := float(p.get(g, 1.0))
		if is_equal_approx(f, 1.0):
			continue
		for nm in GROUPS[g]:
			var bi := _bone(nm)
			if bi < 0:
				continue
			var t := _skel.get_bone_pose(bi)
			# Bone scale COMPOUNDS into children — scaling the chest uniformly
			# stretched the arms hanging off it, so Half-Orc and Dragonborn came
			# out with both thicker torsos and longer arms. Girth is therefore
			# width and depth only (X/Z), never length (Y). Limbs are the reverse:
			# length only. Head is the one group that scales evenly, because
			# nothing meaningful hangs below it.
			match g:
				"head":
					t = t.scaled_local(Vector3.ONE * f)
				"girth", "shoulder":
					t = t.scaled_local(Vector3(f, 1.0, f))
				_:
					t = t.scaled_local(Vector3(1.0, f, 1.0))
			_skel.set_bone_pose(bi, t)
	_root.scale = Vector3.ONE * float(p["height"])


## Frame every body against the SAME camera. Deliberate: a per-body fit would
## normalise away the height differences, which are the entire point.
##
## Set ONCE at build time, not per shot. Calling this inside _shoot() moved the
## camera and then captured in the same breath, so the first render came back
## with the camera still at the origin — Human male was off-frame while every
## later body looked fine, because each was silently using the previous frame's
## camera. Size 2.6 rather than 2.1 so the tallest (Dragonborn, Half-Orc) keep
## their heads: girth scales up the spine chain and adds height with it.
func _frame_fixed() -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.6
	_cam.global_position = Vector3(0.0, 1.05, 3.2)
	_cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)


func _shoot(name: String) -> void:
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])

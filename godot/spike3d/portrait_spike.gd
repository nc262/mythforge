extends Node
## SPIKE — can a 3D character carry portraits and tokens for this game?
##
## The question this answers is NOT "can Godot render a mesh" (obviously) but the
## one that actually decides the approach: does a 3D character sit convincingly
## next to hand-painted 2D worlds, and which shading treatment gets it there.
##
## It renders ONE mesh in SEVERAL poses. That is the whole argument for 3D over
## diffusion identity tricks: these outputs are not "the same character
## preserved", they are the same vertices. Nothing can drift between them.
##
## Run it windowed — headless uses a dummy rasterizer and every capture comes
## back blank:
##   Godot_v4.7-stable_win64.exe --path godot res://spike3d/portrait_spike.tscn
##
## Writes PNGs to user://spike3d/ and quits.

const MODEL := "res://spike3d/models/Knight.glb"
const OUT := "user://spike3d"
const SIZE := 1024

## Set true to render a ladder of camera distances instead of the real sheet.
const CALIBRATE := false
## Chosen by looking at that ladder, not derived: 5.0 was tight on the helmet,
## 8.0 had drifted to half-body. Units are multiples of head size.
const PORTRAIT_DIST := 6.5

## Toon treatment. Bands the diffuse term and adds a rim light, sampling the
## model's OWN albedo so the character keeps its colours — a plain
## material_override would paint it flat grey and answer a different question.
const TOON := """
shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform int bands = 3;
uniform float rim_amount = 0.55;
uniform vec4 rim_col : source_color = vec4(1.0, 0.86, 0.62, 1.0);

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	SPECULAR = 0.1;
	ROUGHNESS = 0.85;
}

void light() {
	// Quantise N.L into flat bands — the single thing that reads as "drawn"
	// rather than "rendered".
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = floor(ndl * float(bands) + 0.5) / float(bands);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * max(stepped, 0.22);

	// Rim: catches the silhouette so the character separates from a busy
	// painted background instead of sinking into it.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = smoothstep(1.0 - rim_amount, 1.0, rim) * ndl;
	DIFFUSE_LIGHT += rim_col.rgb * rim * 0.9;
}
"""

var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _anim: AnimationPlayer
var _originals: Dictionary = {}   # MeshInstance3D -> Array[Material]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build()
	await get_tree().process_frame
	if _root == null:
		push_error("SPIKE: model failed to load")
		get_tree().quit(1)
		return

	var poses := _pick_poses()
	_diagnose()
	if CALIBRATE:
		# Calibrate on an UPRIGHT pose. The first ladder ran on Death_A and every
		# rung looked broken for a reason that had nothing to do with distance.
		_pose("Idle")
		await RenderingServer.frame_post_draw
		_apply("toon")
		for m in [5.0, 6.5, 8.0, 10.0, 13.0]:
			_frame_portrait(m)
			await _shoot("cal_%0.1f" % m)
		get_tree().quit()
		return
	print("SPIKE: animations found = %d, using %s" % [
		(_anim.get_animation_list().size() if _anim else 0), str(poses)])

	# Portrait framing (head and shoulders) and token framing (whole figure,
	# looked down on) — the two surfaces this game actually shows.
	for shot in [{"n": "portrait", "fn": Callable(self, "_frame_portrait")},
			{"n": "token", "fn": Callable(self, "_frame_token")}]:
		for treat in ["pbr", "toon"]:
			_apply(treat)
			for p in poses:
				_pose(p)
				# The skeleton must settle BEFORE the camera is placed — framing
				# reads bone positions, and a Death pose puts the head somewhere
				# an unposed rig never predicts.
				await RenderingServer.frame_post_draw
				shot["fn"].call()
				await _shoot("%s_%s_%s" % [shot["n"], treat, p.to_lower().replace(" ", "_")])

	print("SPIKE: wrote to ", ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true          # composite over painted 2D later
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X      # low-poly silhouettes alias badly without it
	add_child(_vp)

	var packed: PackedScene = load(MODEL)
	if packed == null:
		return
	_root = packed.instantiate()
	_vp.add_child(_root)
	_anim = _find_anim(_root)
	_cache_materials(_root)

	# Three-point-ish rig. Key from front-left, cool fill from the right so the
	# shadow side does not go dead black against a dark background.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.shadow_enabled = true
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.62, 0.72, 1.0)
	fill.rotation_degrees = Vector3(-15, -120, 0)
	_vp.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS      # keeps transparent_bg honest
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.40, 0.50)
	e.ambient_light_energy = 0.9
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_vp.add_child(_cam)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


## Keep every mesh's original materials so the PBR pass can be restored after
## the toon pass overwrites them.
func _cache_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mats: Array = []
		for i in n.mesh.get_surface_count():
			mats.append(n.mesh.surface_get_material(i))
		_originals[n] = mats
	for c in n.get_children():
		_cache_materials(c)


func _apply(treatment: String) -> void:
	for mi in _originals:
		var mats: Array = _originals[mi]
		for i in mats.size():
			if treatment == "pbr":
				mi.set_surface_override_material(i, null)
				continue
			var sh := Shader.new()
			sh.code = TOON
			var sm := ShaderMaterial.new()
			sm.shader = sh
			var src = mats[i]
			# Carry the original albedo across; without this the toon pass is a
			# grey statue and proves nothing about art direction.
			if src is StandardMaterial3D:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("albedo_col", src.albedo_color)
			mi.set_surface_override_material(i, sm)


## Deliberately DISSIMILAR poses. The first cut of this matched "Idle" three
## times over and produced three near-identical frames, which demonstrates
## nothing — the claim being tested is that the character survives being moved,
## so the poses have to actually differ.
func _pick_poses() -> Array:
	if _anim == null:
		return []
	var all := _anim.get_animation_list()
	print("SPIKE: available animations:\n  ", ", ".join(PackedStringArray(all)))
	var want := ["Death", "Attack", "Spellcast", "Cheer", "Sit", "Run", "Block", "Idle"]
	var out: Array = []
	for w in want:
		if out.size() >= 4:
			break
		for a in all:
			if a.findn(w) >= 0 and not out.has(a):
				out.append(a)
				break
	if out.is_empty() and all.size() > 0:
		out.append(all[0])
	return out


## Park the rig at one frame of an animation. Deliberately a static sample, not
## playback: a portrait is one moment, and a fixed seek is reproducible.
func _pose(anim_name: String) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	var a := _anim.get_animation(anim_name)
	_anim.play(anim_name)
	_anim.seek(a.length * 0.45, true)
	_anim.pause()


## Prefer BONE positions over mesh AABBs. A skinned mesh reports its bind-pose
## box, so a character lying down in a Death pose still measures as standing —
## which framed the token shot off-centre until this was fixed.
func _bounds() -> AABB:
	var skel := _find_skel(_root)
	if skel != null and skel.get_bone_count() > 0:
		var box := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
		for i in skel.get_bone_count():
			box = box.expand(skel.global_transform * skel.get_bone_global_pose(i).origin)
		# Bones sit inside the silhouette; pad so armour and weapons are not clipped.
		return box.grow(maxf(box.size.y * 0.12, 0.05))
	var mbox := AABB()
	var first := true
	for mi in _originals:
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if first:
			mbox = b
			first = false
		else:
			mbox = mbox.merge(b)
	return mbox


## Find the head by asking the SKELETON, not by guessing a fraction of the
## bounding box. The first cut used `position.y + size.y * 0.86` and framed the
## top of the helmet, because a skinned mesh's AABB is the bind pose and does not
## track where the head actually is once posed. The rig knows; ask it.
func _head_point() -> Vector3:
	var skel := _find_skel(_root)
	if skel != null:
		for want in ["head", "neck", "spine"]:
			for i in skel.get_bone_count():
				if skel.get_bone_name(i).to_lower().find(want) >= 0:
					return skel.global_transform * skel.get_bone_global_pose(i).origin
	var b := _bounds()
	return Vector3(b.get_center().x, b.position.y + b.size.y * 0.86, b.get_center().z)


## Measure before guessing. Two framings were wrong in a row because the model's
## real scale was assumed rather than read.
func _diagnose() -> void:
	var b := _bounds()
	var skel := _find_skel(_root)
	print("SPIKE: bounds pos=%s size=%s" % [b.position, b.size])
	print("SPIKE: head_point=%s  skeleton=%s bones=%d" % [
		_head_point(), ("yes" if skel else "NO"), (skel.get_bone_count() if skel else 0)])
	if skel:
		var names: Array = []
		for i in mini(skel.get_bone_count(), 40):
			names.append(skel.get_bone_name(i))
		print("SPIKE: bones: ", ", ".join(PackedStringArray(names)))


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f != null:
			return f
	return null


## `mult` scales the camera pull-back. It is a parameter rather than a constant
## because two hand-picked values framed the chest and the top of the helmet —
## CALIBRATE renders a ladder of them so the right one is chosen by looking.
func _frame_portrait(mult := PORTRAIT_DIST) -> void:
	# Head size from the rig — as a 3D DISTANCE, not a Y difference. Using
	# `head.y - chest.y` collapsed to ~0 on the Death pose (the knight is lying
	# down, so those bones share a height), which drove the camera inside the
	# mesh. Bone separation is the same whatever the pose; height is not.
	var head := _head_point()
	var chest := _bone_point("chest")
	var head_h: float = maxf(head.distance_to(chest) * 1.5, 0.12)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 32.0
	var dist: float = head_h * mult
	# Offset along the character's OWN up axis, so a portrait of a fallen
	# character still frames the face rather than the ground above it.
	var up: Vector3 = (head - chest).normalized()
	if up.length() < 0.5:
		up = Vector3.UP
	var target: Vector3 = head + up * (head_h * 0.22)
	_cam.global_position = target + Vector3(dist * 0.42, dist * 0.10, dist)
	_cam.look_at(target, Vector3.UP)


func _bone_point(want: String) -> Vector3:
	var skel := _find_skel(_root)
	if skel != null:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).to_lower() == want:
				return skel.global_transform * skel.get_bone_global_pose(i).origin
	return Vector3.ZERO


func _frame_token() -> void:
	var b := _bounds()
	var target := b.get_center()
	# Tokens read best looked down on — enough tilt to feel like a board piece,
	# not so much it becomes a true top-down and loses the face entirely.
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = b.size.y * 1.22
	var d: float = maxf(b.size.y * 2.0, 2.0)
	_cam.global_position = target + Vector3(0.0, d * 0.72, d * 0.72)
	_cam.look_at(target, Vector3.UP)


func _shoot(name: String) -> void:
	# Two frames: one for the pose/material change to land, one for the render
	# target to actually contain it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("  wrote %s (%dx%d)" % [name, img.get_width(), img.get_height()])

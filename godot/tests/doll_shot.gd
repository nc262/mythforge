extends Node
## Dev harness — RENDER the modular doll, because "the head mesh is hidden" is a
## boolean and "the helmet does not float above a headless neck" is a picture.
## Windowed only; headless uses a dummy rasterizer and every capture is blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/doll_shot.tscn
const BODY := "res://spike3d/models/Knight.glb"
const OUT := "user://doll"
const SIZE := 640

## Each frame: a label and the loadout to wear. The bare pass is first on
## purpose — if the doll cannot be UNDRESSED the rest proves nothing.
const SHOTS := [
	["bare", {}],
	["helm", {"head": "knight_helm"}],
	["helm_cape", {"head": "knight_helm", "cloak": "knight_cape"}],
	["full", {"head": "knight_helm", "cloak": "knight_cape",
		"weapon": "sword_1h", "shield": "round"}],
	["undressed", {"cloak": "knight_cape"}],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var doll := ModularDoll.new()
	vp.add_child(doll)
	doll.build(load(BODY))

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.2)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	vp.add_child(cam)

	for shot in SHOTS:
		for slot in ModularDoll.RENDERED_SLOTS:
			doll.equip(slot, "")
		for slot in shot[1]:
			if not doll.equip(str(slot), str(shot[1][slot])):
				push_error("DOLL: could not equip %s = %s" % [slot, shot[1][slot]])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png("%s/%s.png" % [OUT, shot[0]])
		print("DOLL wrote %s  hidden=%s" % [shot[0], str(doll.hidden_zones())])
	print("DOLL: wrote to ", ProjectSettings.globalize_path(OUT))
	get_tree().quit(0)

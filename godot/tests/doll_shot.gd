extends Node
## Dev harness — RENDER the modular doll, because "the head mesh is hidden" is a
## boolean and "the helmet does not float above a headless neck" is a picture.
## Windowed only; headless uses a dummy rasterizer and every capture is blank.
##   Godot_v4.7-stable_win64.exe --path godot res://tests/doll_shot.tscn
const OUT := "user://doll"
const SIZE := 640

## Each frame: a label and the loadout to wear. The bare pass is first on
## purpose — if the doll cannot be UNDRESSED the rest proves nothing, and with
## this rig "bare" is the question: does clothing actually cover the skin?
const SHOTS := [
	["bare", {}],
	["shirt", {"armor": "peasant"}],
	["dressed", {"armor": "peasant", "legs": "peasant", "feet": "peasant", "hands": "peasant"}],
	["ranger", {"armor": "ranger", "legs": "ranger", "feet": "ranger",
		"hands": "ranger", "head": "hood"}],
	["armed", {"armor": "ranger", "legs": "ranger", "feet": "ranger",
		"weapon": "sword", "shield": "heater"}],
	["twohand", {"armor": "ranger", "legs": "ranger", "feet": "ranger",
		"weapon": "claymore"}],
	# ONE dagger, nothing else in either hand. The Gear page appeared to show two
	# blades for a single equipped dagger and I could not tell at 40 px whether
	# that was real; this is the frame that answers it.
	["dagger_only", {"weapon": "dagger"}],
	["spear", {"armor": "ranger", "legs": "ranger", "feet": "ranger", "weapon": "spear"}],
]

## Rendered a second time as the other sex — the pack ships a full garment set
## per body and the two are different cuts, not one mesh scaled.
const SEXES := ["male", "female"]

## One loadout under every poured cloth. Four world families have no wardrobe of
## their own and wear the fantasy cut in the world's substance instead; whether
## that reads as a jumpsuit or as a ranger dipped in paint is a PICTURE, not a
## boolean, and no assertion in self_check can see it.
##
## "" is the undyed control and must be first — without it there is nothing to
## judge the other four against, and a dye that silently did nothing would look
## like a pass.
const CLOTH_FAMILIES := ["", "cyber", "everyday", "space", "steam"]
const CLOTH_FIT := {"armor": "ranger", "legs": "ranger", "feet": "ranger",
	"hands": "ranger"}

## Tile density sweep, one family, so the scale is CHOSEN from a picture rather
## than inherited. The spike's 0.25 was tuned on another mesh entirely and puts
## about one blotch per thigh on this body.
const CLOTH_SCALES := [0.25, 1.0, 2.5, 5.0, 9.0]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var doll := ModularDoll.new()
	vp.add_child(doll)
	doll.build(load(doll.body_path()))

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	# add_child BEFORE look_at: look_at resolves against the tree, and off-tree it
	# errors and leaves the camera pointing wherever it started.
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 34.0
	doll.frame_camera(cam, 1.0, 0.52)

	for who in SEXES:
		doll.sex = who
		doll.build(load(doll.body_path()))
		doll.frame_camera(cam, 1.0, 0.52)
		for shot in SHOTS:
			for slot in ModularDoll.RENDERED_SLOTS:
				doll.equip(slot, "")
			for slot in shot[1]:
				if not doll.equip(str(slot), str(shot[1][slot])):
					push_error("DOLL: could not equip %s = %s (%s)" % [slot, shot[1][slot], who])
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var stem: String = str(shot[0]) if who == "male" else ("%s_f" % shot[0])
			img.save_png("%s/%s.png" % [OUT, stem])
			print("DOLL wrote %s" % stem)
	doll.sex = "male"
	doll.build(load(doll.body_path()))
	doll.frame_camera(cam, 1.0, 0.52)
	for fam in CLOTH_FAMILIES:
		# BEFORE equipping, not after: the dye is applied as each garment is
		# worn, so a family set afterwards changes nothing and the sheet would
		# come out as five identical rangers that looked like a pass.
		doll.family = str(fam)
		for slot in ModularDoll.RENDERED_SLOTS:
			doll.equip(slot, "")
		for slot in CLOTH_FIT:
			if not doll.equip(str(slot), str(CLOTH_FIT[slot])):
				push_error("DOLL: could not equip %s for family %s" % [slot, fam])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dyed := vp.get_texture().get_image()
		var tag: String = str(fam) if fam != "" else "undyed"
		dyed.save_png("%s/cloth_%s.png" % [OUT, tag])
		print("DOLL wrote cloth_%s" % tag)

	doll.family = "cyber"
	for sc in CLOTH_SCALES:
		doll.cloth_scale = float(sc)
		for slot in ModularDoll.RENDERED_SLOTS:
			doll.equip(slot, "")
		for slot in CLOTH_FIT:
			doll.equip(str(slot), str(CLOTH_FIT[slot]))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var swept := vp.get_texture().get_image()
		swept.save_png("%s/scale_%s.png" % [OUT, str(sc).replace(".", "_")])
		print("DOLL wrote scale_%s" % sc)

	print("DOLL: wrote to ", ProjectSettings.globalize_path(OUT))
	get_tree().quit(0)

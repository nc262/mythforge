extends Node
## R10 step 3 — the seam test.
##
## Bakes a small batch of terrain tiles for ONE world and lays them side by side
## so the only question that reasoning cannot answer gets answered: do
## independently generated tiles butt together, or does the field read as a
## quilt? Run this BEFORE pouring ~960.
##
##   godot --path godot res://tests/bake_tiles.tscn -- <world> <variants>

const OUT := "user://tiles"

## What each role should look like from directly overhead. Kept deliberately
## plain: a tile is a surface, not a scene. Anything with a horizon, a light
## direction or a hero-shot composition will not tile.
const LOOK := {
	"snow": "wind-packed snow",
	"snowdrift": "deep drifted snow with soft ridges",
	"ice": "cracked pale lake ice",
	"stone_floor": "worn flagstone paving",
	"wood_floor": "aged plank flooring",
	"rubble": "broken stone rubble and grit",
	"outcrop": "bare fractured rock",
	"boulder": "a large rounded boulder",
	"shallows": "shallow water over pale gravel",
	"deep_water": "deep dark cold water",
	"thicket": "dense dark evergreen foliage from above",
	"scree": "loose slate scree",
}


func _prompt(role: String, world: String, v: int) -> String:
	return ("seamless tileable top-down overhead texture of %s, %s, "
		+ "photographed straight down, flat even ambient light, no shadows cast, "
		+ "no horizon, no sky, no objects, no creatures, no grid, no text, "
		+ "uniform detail across the whole square, variation %d") % [
			str(LOOK[role]), Art.world_flavor_for(world) if Art.has_method("world_flavor_for") else Art.world_flavor(), v]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var argv := OS.get_cmdline_user_args()
	var world := str(argv[0]) if argv.size() > 0 else "fimbulreach"
	var variants := int(argv[1]) if argv.size() > 1 else 2
	GameState.character["world_id"] = world
	var want: Array = []
	for role in LOOK:
		for v in range(1, variants + 1):
			want.append(["tile-%s-%s-%d" % [role, world, v], role, v])
	print("baking %d tiles for %s" % [want.size(), world])
	var t0 := Time.get_ticks_msec()
	for job in want:
		var key := str(job[0])
		if Art.has_art(key):
			continue
		Art.ensure(key, _prompt(str(job[1]), world, int(job[2])), "1024x1024", true)
	var done := 0
	while done < want.size():
		await get_tree().create_timer(2.0).timeout
		done = 0
		for job in want:
			if Art.has_art(str(job[0])):
				done += 1
		if (Time.get_ticks_msec() - t0) > 1800000:
			print("!! timed out with %d/%d" % [done, want.size()])
			break
		print("  %d/%d  (%ds)" % [done, want.size(), (Time.get_ticks_msec() - t0) / 1000])
	# The actual question: lay each role 3x3 and look for the seam.
	for job in want:
		if int(job[2]) != 1 or not Art.has_art(str(job[0])):
			continue
		var src := Image.load_from_file(Art.path_for(str(job[0])))
		if src == null:
			continue
		src.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		var sheet := Image.create(768, 768, false, src.get_format())
		for gx in 3:
			for gy in 3:
				sheet.blit_rect(src, Rect2i(0, 0, 256, 256), Vector2i(gx * 256, gy * 256))
		sheet.save_png("%s/seam-%s.png" % [OUT, str(job[1])])
	print("seam sheets in ", ProjectSettings.globalize_path(OUT))
	get_tree().quit()

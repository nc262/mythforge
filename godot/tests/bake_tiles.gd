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
const ALL_WORLDS := ["fimbulreach", "embervale", "brasshaven", "neonspire", "saltmarsh-reach", "everyday"]

## What each role should look like from directly overhead. Kept deliberately
## plain: a tile is a surface, not a scene. Anything with a horizon, a light
## direction or a hero-shot composition will not tile.
const LOOK := {
	# open ground
	"grass": "short cropped turf",
	"grass_wild": "long unmown meadow grass",
	"dirt": "packed bare earth",
	"sand": "fine wind-rippled sand",
	"snow": "wind-packed snow",
	"ice": "cracked pale lake ice",
	"stone_floor": "worn flagstone paving",
	"wood_floor": "aged plank flooring",
	"cobble": "rounded cobblestone paving",
	"leaf_litter": "fallen leaves on forest floor",
	# difficult
	"mud": "churned wet mud with puddles",
	"scree": "loose slate scree",
	"snowdrift": "deep drifted snow with soft ridges",
	"undergrowth": "tangled low brush and bracken",
	"shallows": "shallow clear water over pale gravel",
	"rubble": "broken stone rubble and grit",
	"reeds": "dense marsh reeds",
	"bog": "peat bog with dark standing water",
	# impassable fills
	"boulder": "one large rounded boulder filling the square",
	"outcrop": "bare fractured rock",
	"chasm": "a black open fissure dropping into darkness",
	"deep_water": "deep dark cold water",
	"thicket": "dense dark evergreen foliage from above",
	"wreck": "a splintered wooden wreck",
	# cover objects
	"crates": "stacked wooden crates and barrels",
	"pillar": "the top of a stone column",
	"statue": "a weathered stone statue seen from above",
	"table": "a heavy wooden table from above",
	"brazier": "an iron brazier of burning coals",
	"debris": "a heap of scattered debris",
	# features
	"stairs": "worn stone steps",
	"bridge": "weathered plank bridge decking",
	"shore_edge": "wet shingle where water meets land",
	"firepit": "a ring of stones round a burning fire",

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
	var variants := int(argv[0]) if argv.size() > 0 else 4
	var worlds: Array = argv.slice(1) if argv.size() > 1 else ALL_WORLDS
	var want: Array = []
	for world in worlds:
		for role in LOOK:
			for v in range(1, variants + 1):
				want.append(["tile-%s-%s-%d" % [role, world, v], role, v, world])
	print("baking %d tiles across %d worlds" % [want.size(), worlds.size()])
	var t0 := Time.get_ticks_msec()
	var queued := 0
	for job in want:
		var key := str(job[0])
		if Art.has_art(key):
			continue
		GameState.character["world_id"] = str(job[3])   # flavour follows the world
		Art.ensure(key, _prompt(str(job[1]), str(job[3]), int(job[2])), "1024x1024", true)
		queued += 1
	print("  %d already on disk, %d queued" % [want.size() - queued, queued])
	var done := 0
	while done < want.size():
		await get_tree().create_timer(2.0).timeout
		done = 0
		for job in want:
			if Art.has_art(str(job[0])):
				done += 1
		if (Time.get_ticks_msec() - t0) > 21600000:
			print("!! timed out with %d/%d" % [done, want.size()])
			break
		print("  %d/%d  (%ds)" % [done, want.size(), (Time.get_ticks_msec() - t0) / 1000])
	# The actual question: lay each role 3x3 and look for the seam.
	for job in want:
		if int(job[2]) != 1 or str(job[3]) != str(worlds[0]) or not Art.has_art(str(job[0])):
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

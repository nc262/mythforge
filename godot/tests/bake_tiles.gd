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
## A boulder is not a surface. Asking for "one large boulder, seamless tileable"
## gave back a repeating pebble field — the tiling instruction won and turned the
## object into wallpaper. These roles get the OPPOSITE prompt: one thing,
## centred, whole, and explicitly not repeating.
const OBJECTS := ["boulder", "wreck", "crates", "pillar", "statue", "table", "brazier", "firepit", "chasm"]
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
	"boulder": "large weathered granite boulder",
	"outcrop": "bare fractured rock",
	"chasm": "jagged fissure opening into darkness",
	"deep_water": "deep dark cold water",
	"thicket": "dense dark evergreen foliage from above",
	"wreck": "splintered wooden boat wreck",
	# cover objects
	"crates": "stack of wooden crates and a barrel",
	"pillar": "broken stone column",
	"statue": "weathered stone statue on a plinth",
	"table": "heavy wooden trestle table",
	"brazier": "iron brazier of burning coals",
	"debris": "a heap of scattered debris",
	# features
	"stairs": "worn stone steps",
	"bridge": "weathered plank bridge decking",
	"shore_edge": "wet shingle where water meets land",
	"firepit": "ring of stones round a burning campfire",

}


func _prompt(role: String, world: String, v: int) -> String:
	var flavour := Art.world_flavor()
	if role in OBJECTS:
		# Lead with the CAMERA and the isolation, not the subject. "a single
		# boulder ... no horizon" produced a scenic landscape photograph with a
		# sky: the negatives sat at the tail and lost to the noun at the head.
		# Naming it a game asset shot orthographically from above is what makes
		# it an asset rather than a picture of a place.
		return ("top-down orthographic game asset sprite, camera directly overhead "
			+ "pointing straight down, single isolated %s centred on a plain flat "
			+ "dark grey background, entire object inside the frame, %s style, "
			+ "flat even studio light, no cast shadow, no ground, no landscape, "
			+ "no horizon, no sky, no scenery, no perspective, not a photograph, "
			+ "no repetition, no other objects, no text, variation %d") % [
				str(LOOK[role]), flavour, v]
	return ("seamless tileable top-down overhead texture of %s, %s, "
		+ "photographed straight down, flat even ambient light, no shadows cast, "
		+ "no horizon, no sky, no objects, no creatures, no grid, no text, "
		+ "uniform detail across the whole square, variation %d") % [
			str(LOOK[role]), flavour, v]


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

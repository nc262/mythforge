extends Node
## R10 step 2 — look at the layouts before spending a single GPU hour.
## Lays every stencil for a world and saves a PNG of each, so the map can be
## judged for legibility while the tiles are still flat colour.

const OUT := "user://stencils"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var grid := preload("res://scenes/combat/battle_grid.gd").new()
	grid.custom_minimum_size = Vector2(Combat.MAP_COLS * 64, Combat.MAP_ROWS * 64)
	grid.size = grid.custom_minimum_size
	add_child(grid)
	# A fight must be live or the grid draws nothing.
	Combat.enter("Goblin")
	Combat.ensure_positions()
	var argv := OS.get_cmdline_user_args()
	var world := str(argv[0]) if argv.size() > 0 else "fimbulreach"
	GameState.character["world_id"] = world
	# Where does the paint come from? A default world must answer "package".
	var from_pack := 0
	var from_cache := 0
	var missing := 0
	for role in Combat.ROLES:
		for v in range(1, 5):
			if Compiler.tile_art(world, str(role), v) != null:
				from_pack += 1
			elif Art.has_art("tile-%s-%s-%d" % [role, world, v]):
				from_cache += 1
			else:
				missing += 1
	print("%s tiles — package %d, runtime cache %d, missing %d" % [
		world, from_pack, from_cache, missing])
	for stencil in Combat.STENCILS:
		var c := Combat.data()
		c.erase("cells")
		Combat.save(c)
		Combat.lay_battlefield(stencil, world, 1)
		grid.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s-%s.png" % [OUT, stencil, world])
		# A cheap legibility report: how much of the field is unusable, and does
		# the hero have anywhere to go?
		var blocked := 0
		var rough := 0
		for x in Combat.MAP_COLS:
			for y in Combat.MAP_ROWS:
				if Combat._impassable([x, y]):
					blocked += 1
				elif Combat._difficult([x, y]):
					rough += 1
		var total: int = Combat.MAP_COLS * Combat.MAP_ROWS
		var reach: int = Combat.reachable(Combat.cell_of("pc"), 6).size()
		print("%-9s blocked %2d%%  difficult %2d%%  edges %3d  reachable-in-6 %d" % [
			stencil, blocked * 100 / total, rough * 100 / total, Combat.edges().size(), reach])
	print("saved to ", ProjectSettings.globalize_path(OUT))
	get_tree().quit()

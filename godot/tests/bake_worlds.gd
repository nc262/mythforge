extends Node
## Dev tool: compile every built-in world through the World Compiler so the game
## can ship them PRE-BAKED (world-true items/creatures/art, zero forge wait).
## Sequential (one GPU); waits for each world to reach POPULATED before the next.
##   godot --headless --path godot res://tests/bake_worlds.tscn
## Needs a reachable backend + GPU (auth is off, so no login required).

const POP := "populated"


func _ready() -> void:
	Compiler.stage_started.connect(func(s, human): print("    ▶ %-12s %s" % [s, human]))
	if not await Api.auth_ok():
		# auth is off, so this should pass; if not, the backend is down.
		print("BAKE: backend not reachable — aborting"); get_tree().quit(1); return

	var worlds: Array = Rules.builtin_worlds()
	print("=== baking %d built-in worlds ===" % worlds.size())
	for w in worlds:
		var wid := str(w.get("id", ""))
		if wid == "":
			continue
		print("\n--- %s (%s) ---" % [str(w.get("name", wid)), wid])
		var t0 := Time.get_ticks_msec()
		# compile_seed writes the data seed then backgrounds the art; poll until
		# the last image lands (POPULATED) before moving to the next world.
		await Compiler.compile_seed(w.duplicate(true))
		var guard := 0
		while Compiler.compile_state(wid) != POP and guard < 4800:   # ~40 min ceiling
			await get_tree().create_timer(0.5).timeout
			guard += 1
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		print("--- %s → %s in %.0fs (%d items, %d creatures) ---" % [
			wid, Compiler.compile_state(wid), secs,
			Compiler.catalogue_for(wid).size(), Compiler.creatures_for(wid).size()])

	print("\n=== BAKE COMPLETE ===")
	get_tree().quit(0)

extends Node
## Dev tool: compile every built-in world through the World Compiler so the game
## can ship them PRE-BAKED (world-true items/creatures/art, zero forge wait).
## Sequential (one GPU); waits for each world to reach POPULATED before the next.
##   godot --headless --path godot res://tests/bake_worlds.tscn
## Needs the narrator model and the image engine (scripts/start-image-sdcpp.ps1).
##
## RESUMABLE (AssetBake B4). The pour is hours per world, so this is written to be
## killed and re-run:
##   · a world already POPULATED is skipped outright;
##   · compile_seed(resume) reuses the stored style/assets/creatures/npcs rather
##     than re-asking the model, which would invent new ids and orphan every icon
##     already painted;
##   · each image is skipped if its file is already in the world package, and
##     those files are written atomically, so a half-written PNG is never
##     mistaken for a finished one.
## Re-running after a kill therefore costs one seed round-trip and picks up
## exactly where it stopped.

const POP := "populated"
const TICK := 5.0        # seconds between progress polls
const STALL_TICKS := 240 # give up on a world after 20 min with no image landing


func _ready() -> void:
	Compiler.stage_started.connect(func(s, human): print("    ▶ %-12s %s" % [s, human]))
	if not LocalGM.available():
		print("BAKE: no narrator — %s" % LocalGM.why_unavailable()); get_tree().quit(1); return
	if not await Services.warm_art(15.0):
		print("BAKE: image engine down — run scripts/start-image-sdcpp.ps1"); get_tree().quit(1); return

	var worlds: Array = Rules.builtin_worlds()
	print("=== baking %d built-in worlds ===" % worlds.size())
	var incomplete := 0
	for w in worlds:
		var wid := str(w.get("id", ""))
		if wid == "":
			continue
		if Compiler.compile_state(wid) == POP:
			print("\n--- %s: already POPULATED — skipping ---" % wid)
			continue
		print("\n--- %s (%s) ---" % [str(w.get("name", wid)), wid])
		var t0 := Time.get_ticks_msec()
		# compile_seed writes the data seed then backgrounds the art; poll until
		# the last image lands (POPULATED) before moving to the next world.
		await Compiler.compile_seed(w.duplicate(true), true)
		var last := -1
		var stall := 0
		while Compiler.compile_state(wid) != POP:
			await get_tree().create_timer(TICK).timeout
			var left := Compiler.pending_art(wid)
			if left != last:
				last = left
				stall = 0
				print("    … %4d images left (%.0fs elapsed)" % [
					left, (Time.get_ticks_msec() - t0) / 1000.0])
				continue
			stall += 1
			if stall >= STALL_TICKS:
				print("    ! stalled with %d left — moving on; re-run to resume" % left)
				incomplete += 1
				break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		print("--- %s → %s in %.0fs (%d items, %d creatures) ---" % [
			wid, Compiler.compile_state(wid), secs,
			Compiler.catalogue_for(wid).size(), Compiler.creatures_for(wid).size()])

	print("\n=== BAKE %s ===" % ("COMPLETE" if incomplete == 0 else "INCOMPLETE (%d world(s) stalled — re-run)" % incomplete))
	get_tree().quit(0 if incomplete == 0 else 2)

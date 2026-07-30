extends Node
## Dev tool: apply the bestiary FLOOR to an already-baked world.
##   godot --headless --path godot res://tests/topup_creatures.tscn
##
## `fimbulreach` poured with 2 creatures where its siblings got 7-9 — the 8B
## underdelivered on that one stage, and a world with two monsters repeats itself
## in every fight. The floor now lives in `_stage_creatures`, but that only helps
## worlds baked from here on; this walks any world already on disk, merges the
## family fallbacks into its roster (never replacing what the model actually
## invented), and paints ONLY the portraits that are missing.
##
## Deliberately not a Reforge: reforge sets `_reforging`, which forgets each key
## and repaints every portrait. We want the opposite — keep the pixels that exist,
## add the ones that don't.

const FLOOR := 5


func _ready() -> void:
	if not await Services.warm_art(15.0):
		print("TOPUP: image engine down — run scripts/start-image-sdcpp.ps1"); get_tree().quit(1); return
	for w in Rules.builtin_worlds():
		var wid := str(w.get("id", ""))
		if wid == "" or Compiler.compile_state(wid) == "":
			continue
		var have: Array = Compiler.creatures_for(wid)
		if have.size() >= FLOOR:
			print("  %-14s %d creatures — fine" % [wid, have.size()])
			continue
		var pack := Compiler.read_pack(wid)
		var style: Dictionary = pack.get("style", {}) if pack.get("style") is Dictionary else {}
		var seen := {}
		for c in have:
			seen[str((c as Dictionary).get("slug", ""))] = true
		var added := 0
		for c in Compiler._fallback_creatures(style):
			if not seen.has(str(c.get("slug", ""))):
				have.append(c)
				added += 1
		if added == 0:
			continue
		print("\n--- %s: %d → %d creatures (+%d) ---" % [wid, have.size() - added, have.size(), added])
		Compiler._write(wid, "data/creatures.json", have)
		pack["creature_count"] = have.size()
		Compiler._write(wid, "world.json", pack)
		# Paints only what's missing (the _await_art skip guard covers the rest).
		Compiler.current_world = wid
		await Compiler._stage_portrait_art(wid, have, "creature")
		print("--- %s done: %d creatures ---" % [wid, Compiler.creatures_for(wid).size()])
	print("\n=== TOPUP COMPLETE ===")
	get_tree().quit(0)

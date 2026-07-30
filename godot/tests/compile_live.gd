extends Node
## Dev harness (real model + GPU): run a full World Compiler pass end-to-end so
## the art halves actually generate, and report what landed in the world package.
##   godot --headless --path godot res://tests/compile_live.tscn
## Needs the narrator model and the image engine (scripts/start-image-sdcpp.ps1).

func _ready() -> void:
	# NOT test_mode — this drives the real model and the real GPU.
	Compiler.stage_started.connect(func(s, human): print("  ▶ %-12s %s" % [s, human]))
	Compiler.stage_done.connect(func(s, ok): print("  %s %-12s" % ["✓" if ok else "✗", s]))

	if not LocalGM.available():
		print("COMPILE-LIVE: no narrator — %s" % LocalGM.why_unavailable())
		get_tree().quit(1)
		return
	if not await Services.warm_art(15.0):
		print("COMPILE-LIVE: image engine down — run scripts/start-image-sdcpp.ps1")
		get_tree().quit(1)
		return

	var world := {
		"id": "cw-gpuproof-0722", "name": "Saltmarsh Reach",
		"kind": "drowned pirate coast",
		"tagline": "where the tide keeps its secrets",
		"lore": "A shattered archipelago of sunken forts and salt-bleached wrecks, ruled by tide-pirates and the drowned things that envy them.",
	}
	print("=== compiling '%s' (real model + GPU) ===" % world["name"])
	var t0 := Time.get_ticks_msec()
	var pack: Dictionary = await Compiler.compile_seed(world)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("=== compile_state=%s in %.0fs ===" % [str(pack.get("compile_state", "?")), secs])

	_report(str(world["id"]))
	get_tree().quit(0)


func _report(wid: String) -> void:
	var base := Compiler.world_dir(wid)
	print("--- package: %s ---" % base)
	var counts := {"art": 0, "art/parts": 0, "art/creatures": 0, "art/npc": 0}
	for sub in counts.keys():
		var d := DirAccess.open("%s/%s" % [base, sub])
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png"):
				counts[sub] += 1
				var full := "%s/%s/%s" % [base, sub, f]
				var img := Image.load_from_file(full)
				var tag := ""
				if img != null:
					# Report alpha presence. There is no matting step in the engine,
					# so opaque is expected — this is here to catch the day one
					# arrives and silently starts producing something else.
					var has_alpha := img.detect_alpha() != Image.ALPHA_NONE
					tag = " [%dx%d %s]" % [img.get_width(), img.get_height(), "RGBA" if has_alpha else "opaque"]
				print("    %s/%s%s" % [sub, f, tag])
	print("--- counts: key/biomes=%d parts=%d creatures=%d npcs=%d ---" % [
		counts["art"], counts["art/parts"], counts["art/creatures"], counts["art/npc"]])
	# Data halves
	print("--- data: %d items, %d creatures, %d npcs, kits=%s ---" % [
		Compiler.catalogue_for(wid).size(), Compiler.creatures_for(wid).size(),
		Compiler.npcs_for(wid).size(), str(not Compiler.kit_for(wid, "warrior").is_empty())])

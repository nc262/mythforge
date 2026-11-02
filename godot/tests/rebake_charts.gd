extends Node
## Repaint ONE image per compiled world: the chart.
##
## `bake_worlds` skips a POPULATED world outright and skips any image already in
## the package, which is right for a resumable hours-long pour and useless when a
## prompt CHANGES. PY-26 changed the chart prompt, and every shipped world is
## compiled, so all six still carry a chart painted from the old wording.
##
## Six images, not six hours. The armoury is untouched on purpose — this is the
## cheap half, and it wants looking at before the expensive half runs.
##
##   godot --headless --path godot res://tests/rebake_charts.tscn
##
## Needs only the image engine (scripts/start-image-sdcpp.ps1) — no narrator: the
## seed data is already stored, and only a picture is being replaced.

const TIMEOUT_S := 90.0


func _ready() -> void:
	await get_tree().process_frame
	if not await Services.warm_art(15.0):
		print("REBAKE: image engine down — run scripts/start-image-sdcpp.ps1")
		get_tree().quit(1)
		return

	var done := 0
	var failed: Array = []
	for w in Rules.builtin_worlds():
		var wid := str(w.get("id", ""))
		if wid == "" or not Compiler.is_compiled(wid):
			continue
		var name := WorldSkin.world_name(wid)
		# The world has to be CURRENT: chart_ground() and the style anchor both
		# read GameState, so painting neonspire's chart while embervale is loaded
		# would produce embervale's ground under neonspire's name.
		GameState.character = {"id": "dm-rebake", "world_id": wid}
		Ui.apply(wid)
		var key := "chart-" + wid.validate_filename()
		Art.forget(key)                    # the cache copy, if any
		var dest := "%s/art/chart.png" % Compiler.world_dir(wid)
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dest))
		var prompt := Art.chart_prompt(wid, name)
		print("--- %s: %s" % [wid, prompt])
		Art.request(key, prompt, {"size": "1024x1024", "negative": Art.CHART_NEG,
			"lane": Art.Lane.NOW})
		var t0 := Time.get_ticks_msec()
		while not Art.has_art(key) and (Time.get_ticks_msec() - t0) / 1000.0 < TIMEOUT_S:
			await get_tree().create_timer(2.0).timeout
		if not Art.has_art(key):
			failed.append(wid)
			print("    ! %s never painted in %.0fs" % [wid, TIMEOUT_S])
			continue
		# Into the PACKAGE, because that is what `world_map` reads — the cache is
		# only the fallback for a world that was never compiled.
		var img := Image.load_from_file(Art.path_for(key))
		if img == null or img.is_empty() or img.save_png(dest) != OK:
			failed.append(wid)
			print("    ! %s painted but did not land in the package" % wid)
			continue
		done += 1
		print("    %s -> %s (%.0fs)" % [wid, dest, (Time.get_ticks_msec() - t0) / 1000.0])

	if failed.is_empty():
		print("REBAKE-CHARTS OK %d world(s)" % done)
		get_tree().quit(0)
		return   # quit() REQUESTS a quit; it does not stop this function. Without
		         # this the success path fell straight through and printed
		         # INCOMPLETE after OK, exiting 1 on a clean run.
	print("REBAKE-CHARTS INCOMPLETE — %d done, failed: %s" % [done, ", ".join(failed)])
	get_tree().quit(1)

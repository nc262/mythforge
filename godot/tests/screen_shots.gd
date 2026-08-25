extends Node
## WINDOWED screenshots of the screens a headless harness cannot judge.
##
## Three rows sat open as "needs eyes" — PY-12 (dialogs rendering in engine grey),
## PY-14 (a world accent applied to themed widgets but not self-drawn ones),
## PY-19 (dead vertical space) — and two more were committed as "not verified
## visually", which is an honest label and a debt. `body_audit` already proves the
## mechanism works: it runs windowed and saves its viewport, "because a headless
## capture comes back blank — the dummy rasterizer draws nothing".
##
## So this builds the real screens, in a real window, under a chosen world skin,
## and writes PNGs. It asserts NOTHING. Judging a picture is what it exists to
## make possible, not something it should pretend to do.
##
##   Godot_v4.7-stable_win64.exe --path godot res://tests/screen_shots.tscn -- --world=neonspire
##
## Writes to user://shots/<world>/*.png and prints each path.

const OUT := "user://shots"
var _world := "neonspire"
var _dir := ""
var _taken: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--world="):
			_world = str(a).trim_prefix("--world=")
	if DisplayServer.get_name() == "headless":
		print("SHOTS SKIPPED — headless draws nothing; run this windowed")
		get_tree().quit(0)
		return

	_dir = "%s/%s" % [OUT, _world]
	DirAccess.make_dir_recursive_absolute(_dir)
	Ui.apply(_world)
	GameState.character = {"id": "dm-shots", "name": "Shot Subject", "world_id": _world}
	GameState.state = {"world": {"here": "%s, the near ground" % WorldSkin.world_name(_world)}}
	await get_tree().process_frame

	# WHAT THE PALETTE ACTUALLY IS, before judging any picture by eye.
	print("SHOTS palette  gold=%s  gold_soft=%s  amethyst=%s  ember=%s" % [
		Ui.c("gold").to_html(false), Ui.c("gold_soft").to_html(false),
		Ui.c("amethyst").to_html(false), Ui.c("ember").to_html(false)])
	print("SHOTS skin     palette=%s  family=%s  compiled=%s" % [
		str(WorldSkin.skin_for_id(_world).get("palette", "?")),
		WorldSkin.family_for_id(_world), Compiler.is_compiled(_world)])
	if Compiler.is_compiled(_world):
		print("SHOTS pack     colors=%s" % str(Compiler.style_for(_world).get("colors", {})))

	# PY-14 — the accent split: themed widgets went magenta in Neon Spire while
	# the self-drawn toolbar, sliders and HP bar stayed gold. Both kinds are on
	# the Record, so one frame settles it.
	await _shot_scene("res://scenes/ui/character_screen.gd", "record")

	# PY-12 — three dialogs were never dressed, and a Window inherits no theme,
	# so panels inside ANY dialog fell back to engine grey. Session Zero was the
	# worst of them.
	await _shot_scene("res://scenes/ui/gm_tuner.gd", "session_zero")
	await _shot_scene("res://scenes/ui/levelup_window.gd", "levelup")

	# PY-19 — dead vertical space, at real proportions. The mechanical layer is
	# already correct (the chat Scroll expands), so the question is where the
	# space SHOULD go, which is a picture question.
	await _shot_scene("res://scenes/ui/skill_tree.gd", "skill_tree")
	await _shot_scene("res://scenes/ui/world_map.gd", "world_map")

	# PY-20 — no code cause was found for the maximize button, so record what the
	# window actually reports before and after asking for it.
	var before := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	await get_tree().process_frame
	await get_tree().process_frame
	var after := DisplayServer.window_get_mode()
	print("SHOTS window mode: %d -> %d (maximized == %d), resizable=%s" % [
		before, after, DisplayServer.WINDOW_MODE_MAXIMIZED,
		not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED)])
	DisplayServer.window_set_mode(before)

	print("SHOTS OK %d written to %s" % [_taken.size(), _dir])
	for t in _taken:
		print("   ", t)
	get_tree().quit(0)


## Is every pixel the same? A flat frame means nothing drew, and counting it is
## how the first run of this reported five successes and wrote five grey squares.
func _is_flat(img: Image) -> bool:
	var first := img.get_pixel(0, 0)
	var w := img.get_width()
	var h := img.get_height()
	for i in 40:
		var x := int((float(i) / 40.0) * float(w - 1))
		var y := int((float(i) / 40.0) * float(h - 1))
		if img.get_pixel(x, y) != first:
			return false
	return true


## Build one screen the way the game builds it, let it settle, save the frame.
func _shot_scene(path: String, stem: String) -> void:
	var scr = load(path)
	if not (scr is GDScript and scr.can_instantiate()):
		print("SHOTS skip %s — did not compile" % path)
		return
	var node = scr.new()
	get_tree().root.add_child(node)
	# A DIALOG IS ITS OWN WINDOW, AND ITS OWN VIEWPORT. The first version of this
	# grabbed `get_viewport()` — the MAIN window — for every screen, so the three
	# dialogs captured the empty root and it wrote five blank greys while printing
	# "SHOTS OK 5 written". A harness that reports success for nothing is the
	# thing this file exists to stop, so it now captures the node's OWN viewport
	# when the node is a Window, and refuses to count a frame it cannot prove.
	var vp: Viewport = node if node is Window else get_viewport()
	if node is Window:
		node.popup_centered()
	elif node is Control:
		# GIVE A CONTROL THE WHOLE WINDOW, or the shot lies about layout. Mounted
		# bare, a Control sizes to its own minimum and leaves the rest of the frame
		# empty — which reads exactly like the dead space PY-19 reports, while
		# being an artefact of this harness. The game gives these screens a full
		# rect; so must this.
		(node as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		print("SHOTS %s — nothing rendered" % stem)
	elif _is_flat(img):
		print("SHOTS %s — captured a FLAT frame (nothing drew); not counted" % stem)
	else:
		var p := "%s/%s.png" % [_dir, stem]
		if img.save_png(p) == OK:
			_taken.append(ProjectSettings.globalize_path(p))
	if is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame

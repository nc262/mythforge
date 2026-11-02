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
var _asked := 0        # shots requested
var _skipped := 0      # shots this world legitimately has no subject for


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
	# `here` must be a REAL place or the you-are-here ring has nothing to sit on.
	var _first := ""
	for _l in GameState.places():
		if _l is Dictionary and str(_l.get("name", "")) != "":
			_first = str(_l["name"])
			break
	# A PARTIAL STATE, so the shot shows all three fog tiers at once. `here` plus
	# one visited neighbour, one merely heard of, and the rest unknown — a shot
	# with fog off (as this had) can only ever prove the VISITED drawing works.
	var _rest: Array = []
	for _l2 in GameState.places():
		if _l2 is Dictionary and str(_l2.get("name", "")) != _first:
			_rest.append(str(_l2["name"]))
	GameState.state = {"world": {
		"here": _first,
		"seen": [_first] + (_rest.slice(0, 1) if _rest.size() > 0 else []),
		"heard": _rest.slice(0, 3),
	}}
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

	# AT-5 — both local tiers, because the fog rule DIFFERS between them and a
	# shot of one proves nothing about the other. A settled place shows every
	# street; an unsettled one shows the room you stand in and its exits.
	await _shot_scene("res://scenes/ui/place_map.gd", "place_town")
	await _shot_scene("res://scenes/ui/place_map.gd", "place_ruin")

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

	# REFUSE TO REPORT SUCCESS FOR A SHORTFALL. This printed "SHOTS OK 5" when
	# `local_map.gd` failed to compile and both place-map shots came back flat —
	# the count was honest and the WORD was not, and a green line is what gets
	# read. A skipped shot must be said out loud (`_skipped`); anything else
	# missing is a failure.
	if _taken.size() + _skipped < _asked:
		print("SHOTS FAILED — asked for %d, wrote %d, deliberately skipped %d" % [
			_asked, _taken.size(), _skipped])
		for t in _taken:
			print("   ", t)
		get_tree().quit(1)
		return
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
	_asked += 1
	var scr = load(path)
	if not (scr is GDScript and scr.can_instantiate()):
		print("SHOTS skip %s — did not compile" % path)
		return
	var node = scr.new()
	# FEED THE ATLAS WHAT THE GAME FEEDS IT. `world_map` keeps its pins, roads,
	# regions and fog in member vars that `_open_world_map` fills in; mounted bare
	# it drew nothing but the paper, so every shot of it was a picture of terrain
	# with no map on it — and the screens PY-19 and P4 need judged are exactly the
	# ones made of those pins. Mirrors game.gd:2780.
	if stem.begins_with("place_"):
		# ANY SETTLED KIND, not "settlement" alone. `LocalMap.SETTLED_KINDS` is
		# what decides whether the town generator runs, and only one of six
		# shipped worlds carries a place of kind "settlement" — so five of them
		# printed "no 'settlement' place to look inside" and the town tier went
		# unlooked-at in every world but Saltmarsh. A tavern gets a town plan too.
		var town := stem == "place_town"
		var want := "settlement" if town else "ruin"
		var nm := ""
		var knd := ""
		for _p in GameState.places():
			if not (_p is Dictionary):
				continue
			var k := str(_p.get("kind", ""))
			var hit := LocalMap.TOWN_KINDS.has(k) if town else k == want
			if hit:
				nm = str(_p["name"])
				knd = k
				if k == want:
					break            # prefer a true settlement when there is one
		if nm == "":
			# Not every world ships both kinds — say so rather than write a shot
			# of an empty screen and let it read as a success.
			print("SHOTS %s — this world has no '%s' place to look inside" % [stem, want])
			_skipped += 1
			node.queue_free()
			return
		# A LIVE PROBLEM, so the clock in the margin is actually exercised. A shot
		# of a town with no trouble cannot show whether that drawing works.
		if town:
			GameState.set_trouble(nm, "press-gangs are taking men off the quay", 6)
			GameState.tick_trouble(nm, 2)
		node.lm = LocalMap.for_place(GameState.world_id(), nm, knd)
		node.here_room = str(node.lm.nodes[0]["name"])
		node.walked = [str(node.lm.nodes[0]["name"])]
	if stem == "world_map":
		node.locations = GameState.places()
		node.regions = GameState.regions()
		var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
		node.here = str(wd.get("here", ""))
		node.seen = wd.get("seen") if wd.get("seen") is Array else []
		node.fog = true      # AT-6 — fog ON, or the shot cannot show HEARD at all
		# AT-9 — HOVER THE PLACE YOU ARE STANDING IN, so the place card is drawn.
		# A shot with nothing hovered cannot show whether the card is legible —
		# and the old hover measured 1.05:1 on parchment, which is exactly the
		# kind of thing only a rendered frame reveals.
		for hi in node.locations.size():
			if node.locations[hi] is Dictionary and str(node.locations[hi].get("name", "")) == node.here:
				node._hover = hi
				break
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
		# AND THE REAL SIZE. `custom_minimum_size` (680x430 on both maps) wins
		# over an anchor preset on a bare Control, so every map shot ever taken
		# was at that minimum — a third of the window — while the game now opens
		# the Atlas at up to 1500x940. Judging a city grid at the wrong scale is
		# judging a different picture, and the graph-paper complaint was partly
		# an artefact of this line missing.
		(node as Control).custom_minimum_size = Vector2.ZERO
		(node as Control).size = get_viewport().get_visible_rect().size
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

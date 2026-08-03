extends Control
## The minimap — a corner whisper of the chart during exploration: the world's
## painted map (or key art) under a scrim, lamp-dots for known places, the
## you-are-here ring breathing. Click it to open the Atlas. Draw-only; all
## truth lives in GameState/Rules.

signal open_atlas

var _phase := 0.0


func _ready() -> void:
	# The chart is drawn COVER-FIT, so it is always larger than this box on one
	# axis and spilled outside the frame — a slab of map floating over the scene
	# with a border round part of it. That is the "random rectangle on the
	# minimap"; it was never a panel, it was this map escaping its box.
	clip_contents = true
	custom_minimum_size = Vector2(190, 124)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "The chart — click to open the Atlas (Ctrl+M)"
	set_process(not Ui.reduce_motion)
	Art.art_ready.connect(func(_k): queue_redraw())


## Round-5 blocker: this floats above the transcript, and with no chart painted
## it is an empty outlined box that covered live story text, the combat roll bar
## and the composing status for a whole session. An empty frame is worth nothing
## and costs the player words — so it only exists once it has a chart to show.
func _has_chart() -> bool:
	var wid := GameState.world_id().validate_filename()
	# R6 BLANK-02: a baked world ships six overhead plates, so ask the compiler
	# before deciding the player gets no map. This box was empty in play not
	# because the art was missing but because nobody looked where it lives.
	return Compiler.chart_art(GameState.world_id()) != null \
		or Art.has_art("chart-" + wid) or Art.has_art(wid)


## R11-03, properly this time. game.gd set `_mini_map.visible = false` when a
## fight began — and this line put it straight back, every frame, because
## `visible` is reassigned here unconditionally. A caller cannot win an argument
## with a _process that runs sixty times a second, so the rule belongs where the
## assignment is: the chart hides itself during combat.
func _process(delta: float) -> void:
	visible = _has_chart() and not Combat.active()
	if not visible:
		return
	_phase += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_atlas.emit()


func _draw() -> void:
	var art: Texture2D = Compiler.chart_art(GameState.world_id())
	if art == null:
		art = Art.texture_for("chart-" + GameState.world_id().validate_filename())
	if art == null:
		art = Art.texture_for(GameState.world_id())
	if art != null:
		var tsize := Vector2(art.get_width(), art.get_height())
		var s := maxf(size.x / tsize.x, size.y / tsize.y)
		draw_texture_rect(art, Rect2((size - tsize * s) / 2.0, tsize * s), false, Color(0.8, 0.78, 0.85))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night2"), 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.35))
	var world = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	var here := str(world.get("here", ""))
	var seen: Array = world.get("seen") if world.get("seen") is Array else []
	var fog := bool(GameState.rule("fog", true))
	# R12-05 — the chart had no dots and no you-are-here ring because it read the
	# wrong list. `Rules.world_locations()` is the world package's STATIC gazetteer;
	# the places the tale actually visits are recorded in `state.world.places`,
	# with their own x/y. A save proves it: here = "Moonwhisper's Cottage", eight
	# places recorded, and not one of them in the package list — so every entry
	# failed the `nm == here` test and the map drew empty.
	#
	# `seen` is also never written (0 entries across every save on this machine),
	# which under fog hid everything the `here` test did not already catch. The
	# recorded places ARE the discovered ones — that is why they were recorded —
	# so they count as seen.
	var places: Array = GameState.places()
	for l in places:
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", ""))
		var known: bool = seen.has(nm)
		if fog and nm != here and not known:
			continue
		var p := Vector2(float(l.get("x", 50)) / 100.0 * size.x, float(l.get("y", 50)) / 100.0 * size.y)
		if nm == here:
			var breathe := (1.5 * sin(_phase * 1.6)) if not Ui.reduce_motion else 0.0
			draw_circle(p, 3.0, Ui.c("gold"))
			draw_arc(p, 6.0 + breathe, 0, TAU, 20, Color(Ui.c("gold_soft"), 0.9), 1.5)
		else:
			draw_circle(p, 2.2, Color(Ui.c("ink_soft"), 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 1.5)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(Ui.c("gold"), 0.3), false, 1.0)

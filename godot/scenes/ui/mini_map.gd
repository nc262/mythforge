extends Control
## The minimap — a corner whisper of the chart during exploration: the world's
## painted map (or key art) under a scrim, lamp-dots for known places, the
## you-are-here ring breathing. Click it to open the Atlas. Draw-only; all
## truth lives in GameState/Rules.

signal open_atlas

var _phase := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(190, 124)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "The chart — click to open the Atlas (Ctrl+M)"
	set_process(not Ui.reduce_motion)
	Art.art_ready.connect(func(_k): queue_redraw())


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_atlas.emit()


func _draw() -> void:
	var art := Art.texture_for("chart-" + GameState.world_id().validate_filename())
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
	for l in Rules.world_locations(GameState.world_id()):
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", ""))
		if fog and nm != here and not seen.has(nm):
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

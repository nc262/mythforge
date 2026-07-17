class_name MythStageRail extends Control
## MDL: the journey's rune-stones — one per stage, joined by a thread that
## lights as you advance. Past stones are clickable (go back); the current
## stone glows and names itself; the road ahead sits dim but visible.

signal stage_clicked(i: int)

var titles: Array = []
var current := 0


func _init(t: Array = []) -> void:
	titles = t
	custom_minimum_size = Vector2(0, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_stage(i: int) -> void:
	current = clampi(i, 0, titles.size() - 1)
	queue_redraw()


func _stone_x(i: int) -> float:
	var span := minf(72.0, size.x / maxf(float(titles.size()), 1.0))
	return size.x / 2.0 + (i - (titles.size() - 1) / 2.0) * span


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in titles.size():
			if i < current and absf(e.position.x - _stone_x(i)) < 18.0 and absf(e.position.y - size.y * 0.4) < 16.0:
				stage_clicked.emit(i)
				return


func _draw() -> void:
	var y := size.y * 0.4
	var font := get_theme_default_font()
	for i in titles.size() - 1:
		var lit := i < current
		draw_line(Vector2(_stone_x(i) + 9, y), Vector2(_stone_x(i + 1) - 9, y),
			Color(Ui.c("gold"), 0.7) if lit else Color(Ui.c("ink_dim"), 0.3), 1.4, true)
	for i in titles.size():
		var p := Vector2(_stone_x(i), y)
		var r := 7.0 if i == current else 5.0
		var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		if i < current:
			draw_colored_polygon(dia, Color(Ui.c("gold"), 0.9))
		elif i == current:
			draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(Ui.c("gold"), 0.35))
			draw_colored_polygon(dia, Ui.c("gold_soft"))
			var t := str(titles[i])
			var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, p + Vector2(-sz.x / 2.0, 24), t, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Ui.c("gold_soft"))
		else:
			draw_polyline(dia + PackedVector2Array([dia[0]]), Color(Ui.c("ink_dim"), 0.55), 1.2, true)

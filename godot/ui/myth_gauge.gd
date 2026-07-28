class_name MythGauge extends Control
## MDL: a drawn strap gauge (capacity, HP, XP) — rim-lit fill, centered
## caption. Never a stock ProgressBar.

var value := 0.0
var maximum := 1.0
var fill_role := "gold"
var caption := ""
## R8-21 — a FULL HP strap drawn in `danger` red reads as critical damage at a
## glance; 12/12 looked like a hero about to die. When this is on, the fill
## grades with the fraction, so colour and value can never disagree.
var grade_by_fill := false


func _init(cap := "", role := "gold") -> void:
	caption = cap
	fill_role = role
	custom_minimum_size = Vector2(120, 18)


func set_value(v: float, m: float) -> void:
	value = v
	maximum = maxf(m, 0.001)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 1.0)
	var frac := clampf(value / maximum, 0.0, 1.0)
	var col: Color = Ui.c(fill_role)
	if grade_by_fill:
		# Bloodied stays red, hale reads gold, and the walk between is smooth —
		# no new palette keys, no threshold that lies at the boundary.
		col = Ui.c("danger").lerp(Ui.c("gold"), clampf((frac - 0.25) / 0.45, 0.0, 1.0))
	if frac > 0.0:
		var fr := Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2))
		draw_rect(fr, Color(col.darkened(0.25), 0.9))
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, 2)), Color(col, 0.8))
	if caption != "":
		var font := get_theme_default_font()
		var t := "%s %d / %d" % [caption, int(value), int(maximum)]
		var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(font, Vector2((size.x - sz.x) / 2.0, size.y / 2.0 + 4), t,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Ui.c("ink_soft"))

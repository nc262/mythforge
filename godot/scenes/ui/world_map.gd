extends Control
## The world map: the world's key art as parchment, its charted places as
## glowing marks (x/y are 0–100 percentages), you-are-here ringed in gold.
## Click a mark to set off. Draws entirely from data — no state of its own.

signal travel_requested(place: String)

var locations: Array = []
var here := ""
var _hover := -1

const KIND_COLOR := {"tavern": "gold", "shop": "gold_soft", "landmark": "amethyst", "wilds": "danger", "home": "ink_soft"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(640, 400)


func _pos_of(l: Dictionary) -> Vector2:
	return Vector2(float(l.get("x", 50)) / 100.0 * size.x, float(l.get("y", 50)) / 100.0 * size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hover
		_hover = -1
		for i in locations.size():
			if _pos_of(locations[i]).distance_to(event.position) < 22:
				_hover = i
		if _hover != prev:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hover >= 0 and str(locations[_hover].get("name", "")) != here:
			travel_requested.emit(str(locations[_hover].get("name", "")))


func _draw() -> void:
	# The land itself: key art dimmed under a scrim, night vignette at edges.
	var art := Art.texture_for(GameState.world_id())
	if art != null:
		draw_texture_rect(art, Rect2(Vector2.ZERO, size), false, Color(0.75, 0.72, 0.8, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.45))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
	var font := get_theme_default_font()
	for i in locations.size():
		var l: Dictionary = locations[i]
		if not (l is Dictionary):
			continue
		var p := _pos_of(l)
		var col: Color = Ui.c(KIND_COLOR.get(str(l.get("kind", "")), "ink_soft"))
		var is_here: bool = str(l.get("name", "")) == here
		draw_circle(p, 7.0 if i == _hover else 5.0, Color(col, 0.9))
		draw_arc(p, 9.0, 0, TAU, 24, Color(col, 0.5), 1.5)
		if is_here:
			draw_arc(p, 13.0, 0, TAU, 24, Ui.c("gold_soft"), 2.5)
		var nm := str(l.get("name", ""))
		var sz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var tp := p + Vector2(-sz.x / 2, -14)
		draw_string(font, tp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0, 0, 0, 0.8))
		draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Ui.c("ink") if i == _hover or is_here else Ui.c("ink_soft"))
	if _hover >= 0:
		var l2: Dictionary = locations[_hover]
		var lore := str(l2.get("lore", "")).left(80)
		var p2 := _pos_of(l2)
		draw_string(font, Vector2(clampf(p2.x - 120, 8, size.x - 260), minf(p2.y + 26, size.y - 10)),
			lore, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Ui.c("gold_soft"))

extends Control
## 🗺 The living map (docs/rituals/WorldMap.md): the world's chart as living
## paper — wheel-zoom into it, drag to pan, cloud shadows drifting. Visited
## places sit lamp-lit and named; the unknown waits under fog. Quest
## destinations pulse gold; hovering a place draws the road from here.
## Draws entirely from data — no state of its own beyond the camera.

signal travel_requested(place: String)

var locations: Array = []
var here := ""
var seen: Array = []          # visited place names (world.seen + here)
var quest_text := ""          # active quest prose — matched against names
var _hover := -1
var _zoom := 1.0
var _cam := Vector2.ZERO      # pan offset in screen px (post-zoom)
var _dragging := false
var _drag_moved := false
var _phase := 0.0

const KIND_COLOR := {"tavern": "gold", "shop": "gold_soft", "landmark": "amethyst", "wilds": "danger", "home": "ink_soft"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true  # cover-fit paper must never flood the neighbors
	custom_minimum_size = Vector2(680, 430)
	set_process(not Ui.reduce_motion)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _known(nm: String) -> bool:
	return nm == here or seen.has(nm)


func _questward(nm: String) -> bool:
	return nm != "" and quest_text != "" and quest_text.to_lower().contains(nm.to_lower())


## Map-space (0..size) → screen-space under the camera.
func _to_screen(p: Vector2) -> Vector2:
	return p * _zoom + _cam


func _to_map(p: Vector2) -> Vector2:
	return (p - _cam) / _zoom


func _pos_of(l: Dictionary) -> Vector2:
	return Vector2(float(l.get("x", 50)) / 100.0 * size.x, float(l.get("y", 50)) / 100.0 * size.y)


func _clamp_cam() -> void:
	_cam.x = clampf(_cam.x, size.x * (1.0 - _zoom), 0.0)
	_cam.y = clampf(_cam.y, size.y * (1.0 - _zoom), 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
			else:
				_dragging = false
				if not _drag_moved and _hover >= 0:
					var nm := str(locations[_hover].get("name", ""))
					if nm != here:
						travel_requested.emit(nm)
	elif event is InputEventMouseMotion:
		if _dragging and _zoom > 1.001:
			_cam += event.relative
			_drag_moved = _drag_moved or event.relative.length() > 2.0
			_clamp_cam()
			queue_redraw()
			return
		var mp := _to_map(event.position)
		var prev := _hover
		_hover = -1
		for i in locations.size():
			if _pos_of(locations[i]).distance_to(mp) < 22.0 / _zoom:
				_hover = i
		if _hover != prev:
			queue_redraw()


func _zoom_at(at: Vector2, factor: float) -> void:
	var before := _to_map(at)
	_zoom = clampf(_zoom * factor, 1.0, 2.6)
	_cam = at - before * _zoom
	_clamp_cam()
	queue_redraw()


func _draw() -> void:
	draw_set_transform(_cam, 0.0, Vector2(_zoom, _zoom))
	# The paper: parchment chart preferred, key art as the fallback land.
	var art := Art.texture_for("chart-" + GameState.world_id().validate_filename())
	if art == null:
		art = Art.texture_for(GameState.world_id())
	if art != null:
		draw_texture_rect(art, Rect2(Vector2.ZERO, size), false, Color(0.78, 0.75, 0.82, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.4))
	# Cloud shadows drift across the land.
	if not Ui.reduce_motion:
		for spec in [[0.13, 90.0, 0.31, 260.0], [0.61, -60.0, 0.72, 340.0]]:
			var cx := fposmod(size.x * float(spec[0]) + _phase * float(spec[1]), size.x + 400.0) - 200.0
			var cs := float(spec[3])
			draw_texture_rect(Ui.glow_tex(), Rect2(Vector2(cx, size.y * float(spec[2]) - cs / 2.0), Vector2(cs, cs)),
				false, Color(0, 0, 0.02, 0.10))
	var font := get_theme_default_font()
	var here_p := Vector2.ZERO
	for l in locations:
		if l is Dictionary and str(l.get("name", "")) == here:
			here_p = _pos_of(l)
	# The hovered road: a dashed line walking from here toward the choice.
	if _hover >= 0 and here_p != Vector2.ZERO:
		var target := _pos_of(locations[_hover])
		if target.distance_to(here_p) > 8.0:
			var steps := int(target.distance_to(here_p) / 14.0) + 2
			var walk := fmod(_phase * 0.8, 1.0)
			for i in steps:
				var t := (float(i) + walk) / float(steps)
				if t > 1.0:
					continue
				var p := here_p.lerp(target, t) + Vector2(0, -sin(t * PI) * 14.0)
				draw_circle(p, 1.8, Color(Ui.c("gold_soft"), 0.75 * (1.0 - t * 0.3)))
	for i in locations.size():
		var l: Dictionary = locations[i]
		if not (l is Dictionary):
			continue
		var p := _pos_of(l)
		var nm := str(l.get("name", ""))
		var is_here := nm == here
		var known := _known(nm)
		if not known:
			# Fog: the unknown sleeps under a cloud — a rumor, not a name.
			draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(34, 34), Vector2(68, 68)), false, Color(0.02, 0.02, 0.05, 0.55))
			draw_circle(p, 4.0 if i == _hover else 3.0, Color(Ui.c("ink_dim"), 0.75))
			var q := "?"
			var qs := font.get_string_size(q, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, p + Vector2(-qs.x / 2.0, -10), q, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(Ui.c("ink_dim"), 0.9))
			continue
		var col: Color = Ui.c(KIND_COLOR.get(str(l.get("kind", "")), "ink_soft"))
		var pulse := (0.5 + 0.5 * sin(_phase * 2.2)) if not Ui.reduce_motion else 0.5
		# Quest pull: the destination beats gold on the paper.
		if _questward(nm) and not is_here:
			draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(30, 30), Vector2(60, 60)), false, Color(Ui.c("gold"), 0.16 + 0.14 * pulse))
			var star := "✦"
			var ss := font.get_string_size(star, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			draw_string(font, p + Vector2(-ss.x / 2.0, -16), star, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(Ui.c("gold"), 0.8 + 0.2 * pulse))
		# The lamp of a known place.
		draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(col, 0.22))
		draw_circle(p, 7.0 if i == _hover else 5.0, Color(col, 0.95))
		draw_arc(p, 9.0, 0, TAU, 24, Color(col, 0.5), 1.5)
		if is_here:
			var breathe := (2.0 * sin(_phase * 1.6)) if not Ui.reduce_motion else 0.0
			draw_arc(p, 13.0 + breathe, 0, TAU, 28, Ui.c("gold_soft"), 2.5)
		var sz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var tp := p + Vector2(-sz.x / 2.0, -14)
		draw_string(font, tp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0, 0, 0, 0.8))
		draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Ui.c("ink") if i == _hover or is_here else Ui.c("ink_soft"))
	# Hover lore (known places tell their story; the fog only whispers).
	if _hover >= 0:
		var l2: Dictionary = locations[_hover]
		var nm2 := str(l2.get("name", ""))
		var lore := (str(l2.get("lore", "")).left(80)) if _known(nm2) else "somewhere unknown — the road will teach you"
		var p2 := _pos_of(l2)
		draw_string(font, Vector2(clampf(p2.x - 120, 8, size.x - 260), minf(p2.y + 26, size.y - 10)),
			lore, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Ui.c("gold_soft"))
	# The compass rose, steady in the corner regardless of the camera.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var cpos := Vector2(size.x - 40, size.y - 40)
	draw_arc(cpos, 16, 0, TAU, 32, Color(Ui.c("gold"), 0.55), 1.5)
	draw_arc(cpos, 12, 0, TAU, 32, Color(Ui.c("gold"), 0.25), 1.0)
	for d in 4:
		var ang := d * PI / 2.0
		var tip := cpos + Vector2(sin(ang), -cos(ang)) * (14.0 if d == 0 else 10.0)
		draw_line(cpos, tip, Color(Ui.c("gold"), 0.8 if d == 0 else 0.4), 1.5 if d == 0 else 1.0)
	var ns := font.get_string_size("N", HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	draw_string(font, cpos + Vector2(-ns.x / 2.0, -18), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(Ui.c("gold"), 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
extends Control
## AT-5 — THE INSIDE OF A PLACE: a town's streets, a ruin's rooms.
##
## The Atlas one scale down, and deliberately the same visual language — hollow
## marks for what is only glimpsed, filled for what has been walked, a breathing
## ring on where you stand. A player who has read the world map can read this
## without being taught it twice.
##
## Draws entirely from `LocalMap` (the generated data) and GameState (what has
## been walked). No state of its own beyond the camera and the hover.

signal enter_room(room: String)

var lm: LocalMap = null
var here_room := ""
var walked: Array = []
var _hover := -1
var _camera := MythCamera.new()
var _phase := 0.0

## Role -> the mark it wears. Colour AND shape, the rule KIND_MARK follows on the
## world map for the same reason: a shape survives being dimmed, printed, or seen
## by someone who will not agree with us about the orange one.
const ROLE_MARK := {
	"square":  {"col": "gold",          "shape": "square"},
	"inn":     {"col": "gold",          "shape": "dot"},
	"shop":    {"col": "ember",         "shape": "ring"},
	"hall":    {"col": "ink",           "shape": "square"},
	"homes":   {"col": "ink_dim",       "shape": "square"},
	"quay":    {"col": "amethyst",      "shape": "diamond"},
	"gate":    {"col": "amethyst_deep", "shape": "diamond"},
	"entry":   {"col": "gold",          "shape": "ring"},
	"chamber": {"col": "ink_soft",      "shape": "dot"},
	"vault":   {"col": "danger",        "shape": "diamond"},
	"side":    {"col": "ink_dim",       "shape": "dot"},
}


func _ready() -> void:
	Ui.repaint_on_skin(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(680, 430)
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _here_idx() -> int:
	return lm.index_of(here_room) if lm != null else -1


func _pos_of(n: Dictionary) -> Vector2:
	return Vector2(float(n.get("x", 50)) / 100.0 * size.x, float(n.get("y", 50)) / 100.0 * size.y)


func _gui_input(event: InputEvent) -> void:
	if lm == null or _camera.handle(event, self):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _camera.drag_moved or _hover < 0:
			return
		# ONLY WHERE THE PLAYER COULD ACTUALLY GO. A room merely scouted is
		# enterable — that is the entire point of scouting — but one still unknown
		# is not on the map at all, so there is nothing to click.
		if lm.state_of(_hover, _here_idx(), walked) > 0:
			enter_room.emit(str(lm.nodes[_hover]["name"]))
	elif event is InputEventMouseMotion:
		var mp := _camera.to_map(event.position)
		var was := _hover
		_hover = -1
		for i in lm.nodes.size():
			if lm.state_of(i, _here_idx(), walked) == 0:
				continue
			if _pos_of(lm.nodes[i]).distance_to(mp) < 20.0 / _camera.zoom:
				_hover = i
				break
		if was != _hover:
			queue_redraw()


func _draw() -> void:
	if lm == null:
		return
	draw_set_transform(_camera.cam, 0.0, Vector2(_camera.zoom, _camera.zoom))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night2"), 0.92))
	var font := get_theme_default_font()
	var hi := _here_idx()

	# The ways between rooms, under everything. A way to a room still unknown is
	# not drawn: it would say "there is something through here", which is exactly
	# what the player has not earned yet.
	for e in lm.edges:
		var a := int(e[0])
		var b := int(e[1])
		var sa := lm.state_of(a, hi, walked)
		var sb := lm.state_of(b, hi, walked)
		if sa == 0 or sb == 0:
			continue
		var faint: float = 0.5 if (sa == 2 and sb == 2) else 0.24
		draw_line(_pos_of(lm.nodes[a]), _pos_of(lm.nodes[b]),
			Color(Ui.c("ink_dim"), faint), 2.0 if lm.settled else 1.6, true)

	for i in lm.nodes.size():
		var n: Dictionary = lm.nodes[i]
		var st := lm.state_of(i, hi, walked)
		if st == 0:
			continue                       # unknown: nothing, as on the world map
		var p := _pos_of(n)
		var m = ROLE_MARK.get(str(n.get("role", "")), {"col": "ink_soft", "shape": "dot"})
		var col: Color = Ui.c(str(m["col"]))
		var is_here := i == hi
		if st == 1:
			# STATE 1 MEANS TWO DIFFERENT THINGS, and drawing it one way was a
			# bug the screenshot caught: the town footer said "every street in
			# sight" over five UNNAMED rings.
			#
			# In a SETTLED place, un-walked means "you can see it from here and
			# read the sign" — there are residents and signage, which is the
			# whole reason a town is not fogged. So it keeps its name, just
			# unlit.
			#
			# In an UNSETTLED one it means "you can see the doorway, not the
			# room" — nobody is there to tell you what is through it, so it is
			# a shape and nothing more.
			draw_arc(p, 7.0, 0, TAU, 22, Color(col, 0.55 if i == _hover else 0.36), 1.2)
			_draw_mark(p, str(m["shape"]), Color(col, 0.45 if lm.settled else 0.26), 3.4)
			if lm.settled:
				var snm := str(n.get("name", ""))
				var ssz := font.get_string_size(snm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
				var stp := p + Vector2(-ssz.x / 2.0, -12)
				draw_string(font, stp + Vector2(1, 1), snm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0, 0, 0, 0.75))
				draw_string(font, stp, snm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
					Color(Ui.c("ink_soft"), 0.95 if i == _hover else 0.72))
			continue
		draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(18, 18), Vector2(36, 36)),
			false, Color(col, 0.20))
		_draw_mark(p, str(m["shape"]), Color(col, 0.95), 7.0 if i == _hover else 5.0)
		if is_here:
			var breathe := (2.0 * sin(_phase * 1.6)) if not Ui.reduce_motion else 0.0
			draw_arc(p, 12.0 + breathe, 0, TAU, 26, Ui.c("gold_soft"), 2.2)
		var nm := str(n.get("name", ""))
		var sz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var tp := p + Vector2(-sz.x / 2.0, -13)
		draw_string(font, tp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0, 0, 0, 0.8))
		draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			Ui.c("ink") if (i == _hover or is_here) else Ui.c("ink_soft"))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# What this place IS, said once in the corner — a town has no fog and a
	# barrow does, and the player should not have to infer which from the pins.
	var note := "every street in sight" if lm.settled else "only what you have walked, and what it opens onto"
	draw_string(font, Vector2(12, size.y - 12), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 11,
		Color(Ui.c("ink_dim"), 0.8))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 1.5)


## The same five marks the Atlas draws, so a shape means one thing in this game.
func _draw_mark(at: Vector2, shape: String, col: Color, r: float) -> void:
	match shape:
		"ring":
			draw_arc(at, r, 0, TAU, 20, col, maxf(1.5, r * 0.42), true)
		"square":
			draw_rect(Rect2(at - Vector2(r, r) * 0.86, Vector2(r, r) * 1.72), col)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(0, -r * 1.2), at + Vector2(r * 1.1, 0),
				at + Vector2(0, r * 1.2), at + Vector2(-r * 1.1, 0)]), col)
		_:
			draw_circle(at, r, col)

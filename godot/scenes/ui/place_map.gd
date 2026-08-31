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
	var font := get_theme_default_font()
	var hi := _here_idx()
	_draw_ground()
	if lm.settled:
		_draw_town(hi)
	else:
		_draw_rooms(hi)

	# The ways between rooms, under everything. A way to a room still unknown is
	# not drawn: it would say "there is something through here", which is exactly
	# what the player has not earned yet.
	for e in (lm.edges if not lm.settled else []):
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


## ── THE GROUND, from the SAME palette as the world chart ─────────────────────
##
## A local map on flat black was a diagram. It takes its earth, its water and its
## stone from `WorldTerrain.PAPER` for this world's family, so a cyber district
## is concrete where a fantasy village is earth — and a town's ground matches the
## country it stands in, which is the whole reason the tiers share a field.
func _pal(role: String) -> Color:
	var fam := WorldSkin.family_for_id(GameState.world_id())
	var pap: Dictionary = WorldTerrain.PAPER.get(fam, WorldTerrain.PAPER["fantasy"])
	return Color(str(pap.get(role, "444444")))


func _draw_ground() -> void:
	# A SITE IS NOT A MEADOW. The unsettled ground took the world's land colour,
	# so The Sunken Fort had a grass floor between its stone rooms. Inside a
	# barrow the ground the player has not reached is DARK — that is what the fog
	# is — and a lit room floor has to read against it.
	if not lm.settled:
		draw_rect(Rect2(Vector2.ZERO, size), Ui.c("night").darkened(0.35))
		return
	draw_rect(Rect2(Vector2.ZERO, size), _pal("low").darkened(0.42))
	if lm.settled and lm.water_dir != Vector2.ZERO:
		# THE SHORE FACES THE SEA. `water_dir` is the direction of the nearest
		# water cell on the WORLD map, so a quay town's harbour is on the side the
		# chart says the water is. A local map that put the sea wherever it liked
		# would contradict the map you clicked through to get here.
		var d := lm.water_dir
		var n := d.orthogonal()
		var c := Vector2(50, 50) + d * lm.water_at
		var pts := PackedVector2Array()
		# ACROSS THE PLATE, not far beyond it. Sampling +/-130 units put seven of
		# the nine points off-map, so the visible shore was the flat middle of the
		# curve and the wobble never showed. 24 samples over 150 units puts most
		# of them where the player can see them.
		for k in 24:
			var t := (float(k) / 23.0 - 0.5) * 150.0
			# A wobbled shoreline, not a ruled edge — the same reason the region
			# marches wander rather than run straight.
			# Two frequencies, or the "wobble" is a sine wave and reads as one.
			var ph := float(absi(hash(lm.place)) % 1000) * 0.01
			var wob := sin(float(k) * 0.62 + ph) * 5.5 + sin(float(k) * 1.53 + ph * 2.1) * 2.4
			pts.append(_pct(c + n * t + d * wob))
		pts.append(_pct(c + n * 120.0 + d * 400.0))
		pts.append(_pct(c - n * 120.0 + d * 400.0))
		draw_colored_polygon(pts, _pal("shallow").darkened(0.15))
		draw_polyline(pts.slice(0, 24), _pal("strand"), 2.5, true)


func _pct(p: Vector2) -> Vector2:
	return Vector2(p.x / 100.0 * size.x, p.y / 100.0 * size.y)


## Streets first, then what stands along them — the order they were built in.
func _draw_town(_hi: int) -> void:
	for st in lm.streets:
		var scr := PackedVector2Array()
		for q in st:
			scr.append(_pct(q))
		draw_polyline(scr, _pal("strand").darkened(0.30), 7.0, true)
		draw_polyline(scr, _pal("strand").lightened(0.10), 4.0, true)
	for b in lm.buildings:
		var body: Color = _pal("high") if bool(b["big"]) else _pal("hill")
		var quad := _footprint(b, Vector2.ZERO)
		# A shadow offset down-right, which is where the light is not — the same
		# north-west lighting the world chart's hillshade uses, so the two tiers
		# agree about where the sun is.
		draw_colored_polygon(_footprint(b, Vector2(1.6, 1.6)), Color(0.05, 0.04, 0.04, 0.5))
		draw_colored_polygon(quad, body)
		draw_polyline(quad + PackedVector2Array([quad[0]]), body.lightened(0.20), 1.0, true)


## A building's four corners, turned to face its street.
func _footprint(b: Dictionary, off: Vector2) -> PackedVector2Array:
	var at: Vector2 = b["at"]
	var hs: Vector2 = (b["size"] as Vector2) * 0.5
	var a: float = float(b["ang"])
	var ux := Vector2(cos(a), sin(a))
	var uy := ux.orthogonal()
	var out := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(_pct(at + ux * (hs.x * c.x) + uy * (hs.y * c.y)) + off)
	return out


## A ruin is ROOMS WITH WALLS, and the corridor between two of them is a passage
## rather than a line on a floor. Only what the fog allows: an unknown room has
## no rectangle, because it has no shape the player could know.
func _draw_rooms(hi: int) -> void:
	for e in lm.edges:
		var a := int(e[0])
		var b := int(e[1])
		if lm.state_of(a, hi, walked) == 0 or lm.state_of(b, hi, walked) == 0:
			continue
		var pa := _pct(Vector2(float(lm.nodes[a]["x"]), float(lm.nodes[a]["y"])))
		var pb := _pct(Vector2(float(lm.nodes[b]["x"]), float(lm.nodes[b]["y"])))
		draw_line(pa, pb, _pal("strand").darkened(0.62), 9.0, true)
		draw_line(pa, pb, _pal("hill").darkened(0.34), 6.0, true)
	for i in lm.rooms.size():
		var st := lm.state_of(i, hi, walked)
		if st == 0:
			continue
		var r: Rect2 = lm.rooms[i]
		var scr_r := Rect2(_pct(r.position), _pct(r.position + r.size) - _pct(r.position))
		# A scouted room is an OUTLINE — you have seen the doorway and know there
		# is a space beyond it, not what fills it.
		if st == 1:
			draw_rect(scr_r, Color(_pal("strand"), 0.30), false, 1.5)
			continue
		draw_rect(scr_r, _pal("hill").darkened(0.28))
		draw_rect(scr_r, _pal("strand").darkened(0.20), false, 2.0)


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

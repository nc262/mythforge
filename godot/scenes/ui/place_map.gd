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
var _paper: ColorRect = null
const PAPER_SHADER := preload("res://ui/local_paper.gdshader")

## Role -> the mark it wears. Colour AND shape, the rule KIND_MARK follows on the
## world map for the same reason: a shape survives being dimmed, printed, or seen
## by someone who will not agree with us about the orange one.
## A room role said in the ATLAS OWN vocabulary: every `shape` here is a kind
## that `MapInk` already draws, so a hall inside a town wears the silhouette a
## landmark wears on the world chart and the player learns one alphabet rather
## than two. The `col` entries are vestigial on a one-ink map and kept only
## because the hover and here states still read them.
const ROLE_MARK := {
	"square":  {"col": "gold",          "shape": "settlement"},
	"inn":     {"col": "gold",          "shape": "tavern"},
	"shop":    {"col": "ember",         "shape": "shop"},
	"hall":    {"col": "ink",           "shape": "landmark"},
	"homes":   {"col": "ink_dim",       "shape": "home"},
	"quay":    {"col": "amethyst",      "shape": "shop"},
	"gate":    {"col": "amethyst_deep", "shape": "landmark"},
	"entry":   {"col": "gold",          "shape": "landmark"},
	"chamber": {"col": "ink_soft",      "shape": "home"},
	"vault":   {"col": "danger",        "shape": "ruin"},
	"side":    {"col": "ink_dim",       "shape": "ruin"},
}


func _ready() -> void:
	Ui.repaint_on_skin(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(680, 430)
	# AT-11 — THE SAME HIDE AS THE ATLAS. Behind this node, exactly as the Atlas
	# does it, so clicking into a town does not look like leaving the book.
	var g := WorldTerrain.for_world(GameState.world_id())
	_paper = ColorRect.new()
	_paper.show_behind_parent = true
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PAPER_SHADER
	mat.set_shader_parameter("c_paper", g.paper_colour())
	mat.set_shader_parameter("c_paper_dark", g.paper_dark_colour())
	_paper.material = mat
	add_child(_paper)
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	if _paper != null:
		_paper.position = _camera.cam
		_paper.size = size
		_paper.scale = Vector2(_camera.zoom, _camera.zoom)
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
	# The Atlas's own face. `Ui.display` is a FontVariation over `Ui.serif` with
	# glyph spacing set — the two tiers must letter identically or the second one
	# reads as a different document.
	var font: Font = Ui.display
	var hi := _here_idx()
	_solve_labels(font, hi)
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
			_draw_mark(p, str(m["shape"]), Color(col, 0.45 if lm.settled else 0.26),
				3.4 if not lm.settled else 4.6)
			if lm.settled:
				_label(font, p, str(n.get("name", "")), 12, 0.85 if i == _hover else 0.6)
			continue
		_draw_mark(p, str(m["shape"]), Color(col, 0.95), 7.0 if i == _hover else 5.0)
		if is_here:
			# YOU ARE HERE, in ink. A gold glow was a UI cue for a dark panel; on
			# paper the mark is a ring drawn round the symbol, which is what a
			# reader circling their own position actually does.
			var breathe := (2.0 * sin(_phase * 1.6)) if not Ui.reduce_motion else 0.0
			draw_arc(p, 15.0 + breathe, 0, TAU, 28, Color(_ink(), 0.85), 2.0, true)
		_label(font, p, str(n.get("name", "")), 13, 1.0 if (i == _hover or is_here) else 0.85)

	# ON THE SHEET, NOT ON THE MAP — outside the camera, exactly as the Atlas
	# does it, so the frame and the title stay put while the plan pans under them.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_cartouche(font)
	# What this place IS, said once — a town has no fog and a barrow does, and
	# the player should not have to infer which from the marks.
	var note := "every street in sight" if lm.settled else "only what you have walked, and what it opens onto"
	draw_string(font, Vector2(26, size.y - 24), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - 52, 12,
		Color(_ink(), 0.62))
	MapInk.draw_border(self, Rect2(Vector2.ZERO, size), _ink(), _paper_tone())


## The plan names itself, in the Atlas's own box. A town map with no title is a
## diagram; the dialog's title bar is chrome and vanishes in a screenshot.
func _draw_cartouche(font: Font) -> void:
	if lm == null or lm.place == "":
		return
	var title := lm.place.to_upper()
	var ink := _ink()
	var paper := _paper_tone()
	var track := 3.6
	var wide := 0.0
	for ch in title:
		wide += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + track
	var pad := 12.0
	var box := Rect2(Vector2(26, 22), Vector2(wide + pad * 2.0, 38))
	draw_rect(box, Color(paper, 0.93))
	draw_rect(box, Color(ink, 0.8), false, 2.0)
	draw_rect(box.grow(-4.0), Color(ink, 0.4), false, 1.0)
	var x := box.position.x + pad
	for ch in title:
		draw_string(font, Vector2(x, box.position.y + 26.0), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(ink, 0.95))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + track


## AT-13, one tier down. A town packs six or seven names into a smaller sheet
## than the Atlas does, so collisions are MORE likely here, not less — the first
## version printed "The Moot Hall" straight through its own symbol.
##
## Same greedy pass, same eight candidates, same reason it is solved once per
## visible set rather than per frame: the outcome depends on placement order, and
## re-solving as the hover moves would make the names twitch.
const LABEL_TRIES: Array[Vector2] = [
	Vector2(0, -1), Vector2(0, 1), Vector2(1, -0.35), Vector2(-1, -0.35),
	Vector2(1, 0.7), Vector2(-1, 0.7), Vector2(1, -1), Vector2(-1, -1)]

var _label_at := {}
var _label_key := ""


func _solve_labels(font: Font, hi: int) -> void:
	var key := "%s|%d|%d|%dx%d" % [lm.place if lm != null else "", hi, walked.size(),
		int(size.x), int(size.y)]
	if _label_key == key:
		return
	_label_key = key
	_label_at.clear()
	if lm == null:
		return
	var taken: Array[Rect2] = []
	for i in lm.nodes.size():
		var st := lm.state_of(i, hi, walked)
		if st == 0 or (st == 1 and not lm.settled):
			continue           # a scouted room in a barrow shows no name to place
		var n: Dictionary = lm.nodes[i]
		var nm := str(n.get("name", ""))
		if nm == "":
			continue
		var p := _pos_of(n)
		var sz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var best := p + Vector2(-sz.x / 2.0, -13.0)
		var placed := false
		for dist in [15.0, 25.0]:
			for dir in LABEL_TRIES:
				var c := p + Vector2(dir.x * (sz.x * 0.5 + 8.0), dir.y * dist)
				var r := Rect2(c - Vector2(sz.x / 2.0, sz.y * 0.8), sz + Vector2(6, 4))
				var clash := false
				for t in taken:
					if r.intersects(t):
						clash = true
						break
				if not clash:
					best = c + Vector2(-sz.x / 2.0, 0)
					taken.append(r)
					placed = true
					break
			if placed:
				break
		if not placed:
			taken.append(Rect2(best - Vector2(0, sz.y * 0.8), sz))
		_label_at[nm] = best


## Lettering set INTO the sheet: a halo in the paper own colour, the way an
## engraver leaves a gap round a word so the hatching does not run through it.
## A black drop shadow reads as a UI label pasted on top of a map.
func _label(font: Font, p: Vector2, nm: String, sz: int, strength: float) -> void:
	if nm == "":
		return
	var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var at: Vector2 = _label_at.get(nm, p + Vector2(-w.x / 2.0, -13.0))
	for o in [Vector2(1.3, 0), Vector2(-1.3, 0), Vector2(0, 1.3), Vector2(0, -1.3)]:
		draw_string(font, at + o, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(_paper_tone(), 0.92))
	draw_string(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(_ink(), strength))


## ── THE GROUND, from the SAME palette as the world chart ─────────────────────
##
## A local map on flat black was a diagram. It takes its earth, its water and its
## stone from `WorldTerrain.PAPER` for this world's family, so a cyber district
## is concrete where a fantasy village is earth — and a town's ground matches the
## country it stands in, which is the whole reason the tiers share a field.
## Ink and paper, asked of the same table the Atlas reads.
func _ink() -> Color:
	return WorldTerrain.for_world(GameState.world_id()).ink_colour()


func _paper_tone() -> Color:
	return WorldTerrain.for_world(GameState.world_id()).paper_colour()





func _draw_ground() -> void:
	# THE PAPER IS `_paper`, the shader behind this node. Nothing to fill here.
	if not lm.settled:
		# A site with no one in it is drawn on the same sheet, but the ground the
		# player has not reached is left BLANK — on a chart the unknown is empty
		# paper, not a dark wash, which is the one place this differs from the
		# Atlas and it differs because a barrow is unlit rather than unmapped.
		return
	if lm.water_dir == Vector2.ZERO:
		return
	# THE SHORE FACES THE SEA. `water_dir` is the direction of the nearest water
	# cell on the WORLD map, so a quay town's harbour is on the side the chart
	# says the water is. (Deleted once by a careless slice, which left Gallows
	# Quay — a QUAY — landlocked with nothing failing. There is a check now.)
	var d := lm.water_dir
	var n := d.orthogonal()
	var c := Vector2(50, 50) + d * lm.water_at
	var ph := float(absi(hash(lm.place)) % 1000) * 0.01
	var pts := PackedVector2Array()
	for k in 24:
		var t := (float(k) / 23.0 - 0.5) * 150.0
		var wob := sin(float(k) * 0.62 + ph) * 5.5 + sin(float(k) * 1.53 + ph * 2.1) * 2.4
		pts.append(_pct(c + n * t + d * wob))
	var coast := PackedVector2Array(pts)
	pts.append(_pct(c + n * 120.0 + d * 400.0))
	pts.append(_pct(c - n * 120.0 + d * 400.0))
	# ENGRAVED, NOT FILLED. The Atlas hatches its sea off the depth; a town has no
	# depth field, so the hatch is drawn as lines PARALLEL TO THE SHORE, which is
	# what the same engraver would do at this scale and reads as the same sea.
	draw_colored_polygon(pts, Color(_paper_tone().darkened(0.06), 1.0))
	for band in 5:
		var off := float(band + 1) * 2.6
		var hl := PackedVector2Array()
		for q in coast:
			hl.append(q + d * off * (size.x / 100.0))
		draw_polyline(hl, Color(_ink(), 0.34 - float(band) * 0.055), 1.1, true)
	draw_polyline(coast, Color(_ink(), 0.95), 2.2, true)


func _pct(p: Vector2) -> Vector2:
	return Vector2(p.x / 100.0 * size.x, p.y / 100.0 * size.y)


## Streets first, then what stands along them — the order they were built in.
func _draw_town(_hi: int) -> void:
	# THE WALL, or the hedge line. A town needs an EDGE: without one the
	# buildings simply stop, and "stops" reads as unfinished where "ends" reads
	# as a boundary. Drawn under the streets so a gate is a road crossing it.
	if lm.bounds.size() > 2:
		var ring := PackedVector2Array()
		for q in lm.bounds:
			ring.append(_pct(q))
		# The built-up ground, a shade off the open sheet — the way a drawn map
		# separates a town footprint from the country round it.
		draw_colored_polygon(ring, Color(_paper_tone().darkened(0.05), 1.0))
		ring.append(ring[0])
		if lm.walled:
			draw_polyline(ring, Color(_ink(), 0.92), 3.4, true)
			# Towers at the turns, which is what makes a ring read as a WALL
			# rather than as a contour line.
			for k in range(0, lm.bounds.size(), 4):
				var tp2 := _pct(lm.bounds[k])
				draw_circle(tp2, 3.4, _paper_tone())
				draw_arc(tp2, 3.4, 0, TAU, 14, Color(_ink(), 0.92), 1.6, true)
		else:
			draw_polyline(ring, Color(_ink(), 0.45), 1.4, true)
	for st in lm.streets:
		var scr := PackedVector2Array()
		for q in st:
			scr.append(_pct(q))
		# Narrower than they were: a 7 px road on a town map is a boulevard, and
		# with lanes added the whole plan was more street than town.
		# A street is the PAPER between the buildings, edged in ink — not a tan
		# ribbon laid over the ground.
		draw_polyline(scr, Color(_ink(), 0.55), 5.0, true)
		draw_polyline(scr, _paper_tone(), 3.2, true)
	for b in lm.buildings:
		# Roofs vary. One flat fill for every building is what made the first
		# version read as cardboard: a real town map has slate beside thatch
		# beside tile, and the variation is most of what says "many hands built
		# this over a long time".
		# INK OUTLINES ON PAPER. A drawn town map does not shade its roofs: the
		# footprint is left blank and the LINE does the work. A handful are
		# filled solid, which is how an engraver marks the buildings that matter
		# without labelling every one of them.
		var seed_h := absi(hash(Vector2i(int(b["at"].x * 7.0), int(b["at"].y * 7.0))))
		var quad := _footprint(b, Vector2.ZERO)
		var closed := quad + PackedVector2Array([quad[0]])
		if bool(b["big"]) or seed_h % 7 == 0:
			draw_colored_polygon(quad, Color(_ink(), 0.72))
		else:
			draw_colored_polygon(quad, _paper_tone())
			draw_polyline(closed, Color(_ink(), 0.85), 1.15, true)


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
		draw_line(pa, pb, Color(_ink(), 0.85), 8.0, true)
		draw_line(pa, pb, _paper_tone(), 5.4, true)
	for i in lm.rooms.size():
		var st := lm.state_of(i, hi, walked)
		if st == 0:
			continue
		var r: Rect2 = lm.rooms[i]
		var scr_r := Rect2(_pct(r.position), _pct(r.position + r.size) - _pct(r.position))
		# A scouted room is an OUTLINE — you have seen the doorway and know there
		# is a space beyond it, not what fills it.
		if st == 1:
			# Scouted: the doorway seen, the room not entered. A dashed wall is
			# how a surveyor draws what was reported rather than measured.
			_dashed_rect(scr_r, Color(_ink(), 0.42))
			continue
		draw_rect(scr_r, _paper_tone())
		draw_rect(scr_r, Color(_ink(), 0.9), false, 2.2)


## A dashed rectangle, for a room reported but not walked.
func _dashed_rect(r: Rect2, col: Color) -> void:
	var corners := [r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var run := a.distance_to(b)
		var dir := (b - a) / maxf(run, 0.001)
		var t := 0.0
		while t < run:
			draw_line(a + dir * t, a + dir * minf(t + 4.0, run), col, 1.4, true)
			t += 7.0


## THE ATLAS OWN SYMBOLS. This file carried a copy of `_draw_mark` — the same
## four shapes, written a second time — which is two answers to "what does a
## ruin look like" and exactly the drift this repo has paid for over and over.
## `MapInk` is the one home.
func _draw_mark(at: Vector2, shape: String, _col: Color, r: float) -> void:
	MapInk.draw_mark(self, at, shape, _ink(), _paper_tone(), r * 1.5)

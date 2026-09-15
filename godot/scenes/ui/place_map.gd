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


## ── THE PLAN IS ITS OWN LAYER, AND THAT IS A PERFORMANCE FIX ─────────────────
##
## Measured before this existed: `_draw()` cost 9.8-10.8 ms and `_draw_town`
## was 9.1-10.0 ms of it — 93 %. The frame budget at 60 fps is 16.6 ms, so a
## STATIC picture was eating 60 % of it, every frame, forever, because
## `_process` called `queue_redraw()` unconditionally for a breathing ring and a
## paper-position sync.
##
## Two things fix it and both need the plan to be a separate CanvasItem:
##
##   · it redraws only when the PLAN changes, not when the ring breathes
##   · the camera becomes this node's TRANSFORM instead of `draw_set_transform`,
##     so panning and zooming cost nothing at all — no redraw, just a matrix
##
## `show_behind_parent` puts it under the marks and lettering, which stay on the
## Control because they answer to hover and must stay cheap to redraw.
class PlanLayer extends Node2D:
	var map: Control = null

	func _draw() -> void:
		if map != null:
			map._draw_plan(self)

var lm: LocalMap = null
var here_room := ""
var walked: Array = []
var _hover := -1
var _camera := MythCamera.new()
var _phase := 0.0
var _paper: ColorRect = null
var _plan: PlanLayer = null
var _plan_key := ""            # what the layer was last drawn for
const PAPER_SHADER := preload("res://ui/local_paper.gdshader")

## Role -> the mark it wears. Colour AND shape, the rule KIND_MARK follows on the
## world map for the same reason: a shape survives being dimmed, printed, or seen
## by someone who will not agree with us about the orange one.
## A room role said in the ATLAS OWN vocabulary: every `shape` here is a kind
## that `MapInk` already draws, so a hall inside a town wears the silhouette a
## landmark wears on the world chart and the player learns one alphabet rather
## than two. The `col` entries are vestigial on a one-ink map and kept only
## because the hover and here states still read them.
## A GM site's kind -> the ROLE_MARK row it borrows. The engine owns this list,
## which is the whole point: `GameState.SITE_KINDS` is a closed enum, so every
## site the GM can invent is one the map already knows how to draw.
const SITE_MARK := {
	"inn": "inn", "tavern": "inn", "store": "shop", "smith": "shop",
	"alchemist": "shop", "temple": "hall", "fence": "shop", "sage": "hall",
	"guild": "hall", "home": "homes", "landmark": "hall",
}

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
	# AFTER the paper and also behind the parent, so the order is
	# paper -> plan -> marks and lettering.
	_plan = PlanLayer.new()
	_plan.map = self
	_plan.show_behind_parent = true
	add_child(_plan)
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	if _paper != null:
		_paper.position = _camera.cam
		_paper.size = size
		_paper.scale = Vector2(_camera.zoom, _camera.zoom)
	if _plan != null:
		# THE CAMERA IS A TRANSFORM, NOT A REDRAW. This is the whole reason the
		# plan is its own node: panning a 585-building town used to re-issue
		# every draw call, and now it moves a matrix.
		_plan.position = _camera.cam
		_plan.scale = Vector2(_camera.zoom, _camera.zoom)
		# WALKED IS IN THE KEY because a ruin's rooms are fogged and the fog
		# lifts as you go — leave it out and a dungeon never reveals anything.
		var key := "%s@%dx%d/%d" % [lm.place if lm != null else "",
			int(size.x), int(size.y), walked.size()]
		if key != _plan_key:
			_plan_key = key
			_plan.queue_redraw()
	# The Control still carries the marks, the lettering and the breathing ring,
	# which measured 0.7 ms together — cheap enough to redraw every frame, and
	# the ring has to.
	queue_redraw()


func _here_idx() -> int:
	return lm.index_of(here_room) if lm != null else -1


func _pos_of(n: Dictionary) -> Vector2:
	return _pct(Vector2(float(n.get("x", 50)), float(n.get("y", 50))))


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


## Everything that only changes when the PLAN changes. Drawn into the layer, in
## the layer's own space — the camera is its transform, so nothing here applies
## one.
func _draw_plan(ci: CanvasItem) -> void:
	if lm == null:
		return
	_draw_ground(ci)
	if lm.settled:
		_draw_outside(ci)
		_draw_town(ci)
	else:
		_draw_rooms(ci, _here_idx())


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
		# A GM-AUTHORED SITE carries its kind in its role ("site:smith"), so the
		# mark it wears is chosen by the SAME table as everything else — the
		# player learns one alphabet, and a place the story invented is drawn in
		# the same ink as a place the generator did.
		var role_s := str(n.get("role", ""))
		if role_s.begins_with("site:"):
			role_s = SITE_MARK.get(role_s.trim_prefix("site:"), "landmark")
		var m = ROLE_MARK.get(role_s, {"col": "ink_soft", "shape": "dot"})
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
				_label(font, p, str(n.get("name", "")), 14, 0.9 if i == _hover else 0.7)
			continue
		_draw_mark(p, str(m["shape"]), Color(col, 0.95), 7.0 if i == _hover else 5.0)
		if is_here:
			# YOU ARE HERE, in ink. A gold glow was a UI cue for a dark panel; on
			# paper the mark is a ring drawn round the symbol, which is what a
			# reader circling their own position actually does.
			var breathe := (2.0 * sin(_phase * 1.6)) if not Ui.reduce_motion else 0.0
			draw_arc(p, 15.0 + breathe, 0, TAU, 28, Color(_ink(), 0.85), 2.0, true)
		# SIXTEEN, NOT THIRTEEN. The lettering measured 6.13:1 against its own halo
		# — it passed contrast and still read as grey mush, because at 13 px this
		# serif draws a one-pixel stem and antialiasing spends most of it. Weight
		# was the defect, not darkness, and the fix for weight is size.
		_label(font, p, str(n.get("name", "")), 16, 1.0 if (i == _hover or is_here) else 0.92)

	# ON THE SHEET, NOT ON THE MAP — outside the camera, exactly as the Atlas
	# does it, so the frame and the title stay put while the plan pans under them.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_cartouche(font)
	# What this place IS, said once — a town has no fog and a barrow does, and
	# the player should not have to infer which from the marks.
	_draw_trouble(font)
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
	# THE MARKS GO DOWN FIRST. A label that dodges other labels but sits on a
	# symbol is still unreadable, and the symbol cannot move.
	var taken: Array[Rect2] = []
	for i in lm.nodes.size():
		if lm.state_of(i, hi, walked) == 0:
			continue
		var mp := _pos_of(lm.nodes[i])
		taken.append(Rect2(mp - Vector2(9, 9), Vector2(18, 18)))
	for i in lm.nodes.size():
		var st := lm.state_of(i, hi, walked)
		if st == 0 or (st == 1 and not lm.settled):
			continue           # a scouted room in a barrow shows no name to place
		var n: Dictionary = lm.nodes[i]
		var nm := str(n.get("name", ""))
		if nm == "":
			continue
		var p := _pos_of(n)
		# MEASURED AT THE SIZE IT IS DRAWN AT. This measured 13 while `_label`
		# drew 16, so every reserved box was a sixth too small and the solver
		# cleared collisions that then happened anyway — which is why Gallows
		# Quay's Rope Walk and Physicker sat on top of each other after the trades
		# took the label count from six to fourteen.
		var sz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		var best := p + Vector2(-sz.x / 2.0, -13.0)
		var best_cost := INF
		# MORE RINGS, AND A LEAST-BAD FALLBACK. With fourteen labels on a plate
		# some of them genuinely cannot be placed clear, and the old solver gave
		# up to its first guess — directly on top of a neighbour. Scoring every
		# candidate by how much it overlaps and keeping the cheapest means a
		# crowded sheet degrades instead of colliding.
		for dist in [15.0, 24.0, 34.0, 46.0]:
			for dir in LABEL_TRIES:
				var c := p + Vector2(dir.x * (sz.x * 0.5 + 8.0), dir.y * dist)
				var r := Rect2(c - Vector2(sz.x / 2.0, sz.y * 0.8), sz + Vector2(6, 4))
				var cost := 0.0
				for t in taken:
					var hit := r.intersection(t)
					cost += hit.size.x * hit.size.y
				# Nearer is better when nothing is in the way, so a clear label
				# does not drift to the far ring for no reason.
				cost += dist * 0.4
				if cost < best_cost:
					best_cost = cost
					best = c + Vector2(-sz.x / 2.0, 0)
			if best_cost <= dist * 0.4 + 0.01:
				break              # found a clear spot on this ring; stop looking
		taken.append(Rect2(best - Vector2(0, sz.y * 0.8), sz + Vector2(6, 4)))
		_label_at[nm] = best


## Lettering set INTO the sheet: a halo in the paper own colour, the way an
## engraver leaves a gap round a word so the hatching does not run through it.
## A black drop shadow reads as a UI label pasted on top of a map.
func _label(font: Font, p: Vector2, nm: String, sz: int, strength: float) -> void:
	if nm == "":
		return
	var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var at: Vector2 = _label_at.get(nm, p + Vector2(-w.x / 2.0, -13.0))
	MapInk.draw_label(self, font, at, nm, sz, _ink(), _paper_tone(), strength)


## ── THE GROUND, from the SAME palette as the world chart ─────────────────────
##
## A local map on flat black was a diagram. It takes its earth, its water and its
## stone from `WorldTerrain.PAPER` for this world's family, so a cyber district
## is concrete where a fantasy village is earth — and a town's ground matches the
## country it stands in, which is the whole reason the tiers share a field.
## Ink and paper, asked of the same table the Atlas reads.
## ── WHAT IS GOING WRONG HERE ─────────────────────────────────────────────────
##
## Drawn on the SHEET, not on the map — it is a note in the margin, the way a
## surveyor writes what a place is dealing with beside the plan rather than on
## it. The clock is segments rather than a number because a fraction reads at a
## glance and "3/6" does not; filled from the top, clockwise, like every other
## clock this idea came from.
func _draw_trouble(font: Font) -> void:
	if lm == null:
		return
	var t := GameState.trouble_at(lm.place)
	if t.is_empty():
		return
	var what := str(t.get("what", ""))
	if what == "":
		return
	var size: int = maxi(int(t.get("size", 6)), 1)
	var filled: int = clampi(int(t.get("filled", 0)), 0, size)
	var ink := _ink()
	var paper := _paper_tone()
	var c := Vector2(size_x_right() - 26.0, 34.0)
	var r := 11.0
	draw_circle(c, r + 1.0, paper)
	for i in size:
		var a0 := -PI * 0.5 + float(i) / float(size) * TAU
		var a1 := -PI * 0.5 + float(i + 1) / float(size) * TAU
		if i < filled:
			var wedge := PackedVector2Array([c])
			for k in 7:
				wedge.append(c + Vector2(cos(lerpf(a0, a1, float(k) / 6.0)),
					sin(lerpf(a0, a1, float(k) / 6.0))) * r)
			draw_colored_polygon(wedge, Color(ink, 0.8))
		draw_line(c, c + Vector2(cos(a0), sin(a0)) * r, Color(ink, 0.55), 1.0, true)
	draw_arc(c, r, 0, TAU, 32, Color(ink, 0.9), 1.6, true)
	# The words to the LEFT of the dial, right-aligned into it.
	var w := font.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	MapInk.draw_label(self, font, Vector2(c.x - r - 10.0 - w, c.y + 5.0), what, 13,
		ink, paper, 0.92)


## The sheet's right edge. A helper because `size.x` is the CONTROL's width and
## the border sits inside it — a note flush to `size.x` would sit on the frame.
func size_x_right() -> float:
	return size.x - 16.0


func _ink() -> Color:
	return WorldTerrain.for_world(GameState.world_id()).ink_colour()


func _paper_tone() -> Color:
	return WorldTerrain.for_world(GameState.world_id()).paper_colour()


## ── THE SEA HAS TO READ AS SEA ON EVERY STOCK ────────────────────────────────
##
## This was `paper.darkened(0.06)` — a fixed six per cent step toward black. On
## parchment that is a faint tonal shift and just about works; on the cyber and
## space stocks the paper is already near-black, so six per cent of it is
## nothing at all and the river vanished. Neonspire's water read as three stray
## hairlines at the sheet edge.
##
## "Darker" is the wrong instruction on a dark ground. What the eye needs is a
## STEP AWAY from the paper, whichever direction has room — so on a light stock
## the water goes down and on a dark one it goes up, and the size of the step is
## the same either way.
func _water_tone() -> Color:
	var paper := _paper_tone()
	var step: float = 0.16
	if paper.get_luminance() < 0.35:
		return Color(paper.lightened(step), 1.0)
	return Color(paper.darkened(step), 1.0)





func _draw_ground(ci: CanvasItem) -> void:
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
		# WIDE ENOUGH TO LEAVE THE SHEET. The plate is square and centred now, so a
		# coast that only spans the plate ends inside the margin and the sea shows
		# a straight vertical seam where the polygon stops.
		var t := (float(k) / 23.0 - 0.5) * 420.0
		var wob := sin(float(k) * 0.62 + ph) * 5.5 + sin(float(k) * 1.53 + ph * 2.1) * 2.4
		pts.append(_pct(c + n * t + d * wob))
	var coast := PackedVector2Array(pts)
	pts.append(_pct(c + n * 120.0 + d * 400.0))
	pts.append(_pct(c - n * 120.0 + d * 400.0))
	# ENGRAVED, NOT FILLED. The Atlas hatches its sea off the depth; a town has no
	# depth field, so the hatch is drawn as lines PARALLEL TO THE SHORE, which is
	# what the same engraver would do at this scale and reads as the same sea.
	ci.draw_colored_polygon(pts, _water_tone())
	for band in 5:
		var off := float(band + 1) * 2.6
		var hl := PackedVector2Array()
		for q in coast:
			hl.append(q + d * off * _plate())
		ci.draw_polyline(hl, Color(_ink(), 0.34 - float(band) * 0.055), 1.1, true)
	ci.draw_polyline(coast, Color(_ink(), 0.95), 2.2, true)


## ── PLATE TO SHEET, AT ONE SCALE ─────────────────────────────────────────────
##
## This used to map x by `size.x` and y by `size.y` independently, which on a
## 1280x800 sheet stretched the plan 1.6x sideways: a square building came out an
## oblong, a round wall came out an oval, and every roof leaned the same wrong
## way. A plan drawn at two scales is not a plan.
##
## One scale, centred. The margin that leaves is the sheet's, and a book map
## wants one — it is where the shore, the hatching and the border live.
func _plate() -> float:
	return minf(size.x, size.y) / 100.0


func _pct(p: Vector2) -> Vector2:
	var s := _plate()
	return (size - Vector2(100, 100) * s) * 0.5 + p * s


## ── THE TOWN, DRAWN ──────────────────────────────────────────────────────────
##
## NOTHING HERE DRAWS A STREET. The wards were inset before they were subdivided,
## so the roads are the gaps that were left — negative space, not marks. That is
## why no building can stand in a road: there is no road to stand in, only
## ground nobody built on. Drawing streets as ribbons over a layout is what the
## first version did, and it is why buildings floated free of them.
## ── THE COUNTRYSIDE, drawn BEFORE the town so the town sits on it ────────────
##
## Every one of these sheets was a town cut out and pasted on blank paper. What
## fills that paper is not decoration: the roads say which way the world is, the
## ribbon outside each gate says the town outgrew its wall, and the ploughland
## says people eat.
func _draw_outside(ci: CanvasItem) -> void:
	var ink := _ink()
	# PLOUGHLAND FIRST, fainter than anything else on the sheet — texture the eye
	# should read as "worked ground" without ever stopping on it.
	for f in lm.furlongs:
		var hull: PackedVector2Array = f["hull"]
		if hull.size() > 2:
			var hs := PackedVector2Array()
			for q in hull:
				hs.append(_pct(q))
			ci.draw_colored_polygon(hs, Color(ink, 0.05))
			hs.append(hs[0])
			ci.draw_polyline(hs, Color(ink, 0.45), 1.2, true)
		for line in f["strips"]:
			var scr := PackedVector2Array()
			for q in line:
				scr.append(_pct(q))
			if scr.size() > 1:
				ci.draw_polyline(scr, Color(ink, 0.22), 0.9, true)
	# The roads out, cased like the world chart's so they read as the same thing
	# one scale down.
	for road in lm.out_roads:
		var scr2 := PackedVector2Array()
		for q in road:
			scr2.append(_pct(q))
		if scr2.size() > 1:
			ci.draw_polyline(scr2, Color(_paper_tone(), 0.9), 5.4, true)
			ci.draw_polyline(scr2, Color(ink, 0.7), 2.0, true)
	# The faubourg: what would not fit, or was not wanted, inside the wall.
	for b in lm.outskirts:
		var poly: PackedVector2Array = b["poly"]
		if poly.size() < 3:
			continue
		var scr3 := PackedVector2Array()
		for q in poly:
			scr3.append(_pct(q))
		ci.draw_colored_polygon(scr3, _paper_tone())
		scr3.append(scr3[0])
		ci.draw_polyline(scr3, Color(ink, 0.6), 1.0, true)


func _draw_town(ci: CanvasItem) -> void:
	var ink := _ink()
	var paper := _paper_tone()
	# The built-up ground first, a shade off the open sheet: this is what makes
	# the gaps between wards READ as streets rather than as holes.
	if lm.bounds.size() > 2:
		var ring := PackedVector2Array()
		for q in lm.bounds:
			ring.append(_pct(q))
		ci.draw_colored_polygon(ring, Color(paper.darkened(0.05), 1.0))

	# Each ward as a faint field, so a quarter reads as a quarter.
	for w in lm.wards:
		if w.size() < 3:
			continue
		var wp := PackedVector2Array()
		for q in w:
			wp.append(_pct(q))
		ci.draw_colored_polygon(wp, Color(paper.darkened(0.10), 0.55))

	# The wall over the ward edges, so the boundary reads as built rather than as
	# the outermost street.
	if lm.bounds.size() > 2:
		var ring2 := PackedVector2Array()
		for q in lm.bounds:
			ring2.append(_pct(q))
		ring2.append(ring2[0])
		if lm.walled:
			ci.draw_polyline(ring2, Color(ink, 0.92), 3.4, true)
			# A GATE IS A GAP WITH TWO TOWERS. Drawn after the wall so it breaks
			# it — and drawn LARGER than a mural tower, which is the one rule
			# about walls safe to make absolute: the gate is always the biggest
			# tower on its circuit, because it is the structural weak point.
			for gt in lm.gates:
				var gp := _pct(gt["at"])
				ci.draw_circle(gp, 7.0, paper)
				ci.draw_arc(gp, 6.4, 0, TAU, 20, Color(ink, 0.95), 2.4, true)
				ci.draw_circle(gp, 2.2, Color(ink, 0.9))
			for k in range(0, lm.bounds.size(), 4):
				var tp2 := _pct(lm.bounds[k])
				ci.draw_circle(tp2, 3.4, paper)
				ci.draw_arc(tp2, 3.4, 0, TAU, 14, Color(ink, 0.92), 1.6, true)
		else:
			ci.draw_polyline(ring2, Color(ink, 0.45), 1.4, true)

	# INK OUTLINES ON PAPER. A drawn town map does not shade its roofs: the
	# footprint is left blank and the LINE does the work, with a handful filled
	# solid the way an engraver marks what matters without labelling it.
	#
	# Every footprint is a sub-polygon of its block, so a wall facing a street is
	# parallel to that street automatically — there is no align-to-road pass,
	# because the geometry cannot come out any other way.
	for b in lm.buildings:
		var poly: PackedVector2Array = b["poly"]
		if poly.size() < 3:
			continue
		var scr := PackedVector2Array()
		for q in poly:
			scr.append(_pct(q))
		# WEIGHT BY DEPTH INTO THE TOWN, not by a coin flip. This filled one
		# building in seven solid on a hash, which I invented — the research found
		# no source for "important buildings are filled" as a historical rule, and
		# declined to treat it as one. What IS cross-source verified, from the OS
		# plans through Braun & Hogenberg to Merian, is ink DENSITY: the core of a
		# town is darker and heavier, the edge lighter and thinner. So the core
		# gets a heavier line and the outskirts a hairline, which says the same
		# thing the random fill was pretending to say and says it truthfully.
		var d := TownPlan.centroid(poly).distance_to(Vector2(50, 50)) / 46.0
		var weight: float = lerpf(1.35, 0.8, clampf(d, 0.0, 1.0))
		if bool(b["big"]):
			ci.draw_colored_polygon(scr, Color(ink, 0.70))
		else:
			ci.draw_colored_polygon(scr, paper)
			var ring3 := scr.duplicate()
			ring3.append(ring3[0])
			ci.draw_polyline(ring3, Color(ink, lerpf(0.9, 0.62, clampf(d, 0.0, 1.0))), weight, true)
			# THE RIDGE. One line down the long axis is what makes a rectangle
			# read as a building rather than a box — the single cheapest mark on
			# this whole sheet, and the device every hand-drawn town map uses.
			var rg := TownPlan.ridge(poly)
			if rg.size() == 2:
				var a := _pct(rg[0])
				var b2 := _pct(rg[1])
				if a.distance_squared_to(b2) > 9.0:
					ci.draw_line(a, b2, Color(ink, 0.5), 0.9, true)



## A ruin is ROOMS WITH WALLS, and the corridor between two of them is a passage
## rather than a line on a floor. Only what the fog allows: an unknown room has
## no rectangle, because it has no shape the player could know.
func _draw_rooms(ci: CanvasItem, hi: int) -> void:
	for e in lm.edges:
		var a := int(e[0])
		var b := int(e[1])
		if lm.state_of(a, hi, walked) == 0 or lm.state_of(b, hi, walked) == 0:
			continue
		var pa := _pct(Vector2(float(lm.nodes[a]["x"]), float(lm.nodes[a]["y"])))
		var pb := _pct(Vector2(float(lm.nodes[b]["x"]), float(lm.nodes[b]["y"])))
		ci.draw_line(pa, pb, Color(_ink(), 0.85), 8.0, true)
		ci.draw_line(pa, pb, _paper_tone(), 5.4, true)
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
			_dashed_rect(ci, scr_r, Color(_ink(), 0.42))
			continue
		ci.draw_rect(scr_r, _paper_tone())
		ci.draw_rect(scr_r, Color(_ink(), 0.9), false, 2.2)


## A dashed rectangle, for a room reported but not walked.
func _dashed_rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var corners := [r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var run := a.distance_to(b)
		var dir := (b - a) / maxf(run, 0.001)
		var t := 0.0
		while t < run:
			ci.draw_line(a + dir * t, a + dir * minf(t + 4.0, run), col, 1.4, true)
			t += 7.0


## THE ATLAS OWN SYMBOLS. This file carried a copy of `_draw_mark` — the same
## four shapes, written a second time — which is two answers to "what does a
## ruin look like" and exactly the drift this repo has paid for over and over.
## `MapInk` is the one home.
func _draw_mark(at: Vector2, shape: String, _col: Color, r: float) -> void:
	MapInk.draw_mark(self, at, shape, _ink(), _paper_tone(), r * 1.5)

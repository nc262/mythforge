extends Control
## 🗺 The living map (docs/rituals/WorldMap.md): the world's chart as living
## paper — wheel-zoom into it, drag to pan, cloud shadows drifting. Visited
## places sit lamp-lit and named; the unknown waits under fog. Quest
## destinations pulse gold; hovering a place draws the road from here.
## Draws entirely from data — no state of its own beyond the camera.
##
## NO SCALE BAR, on purpose. A location's x/y are percentages of the chart, not
## distances — the worlds carry no unit of length at all. A scale would be a
## drawn lie, and a map that lies about distance is worse than one that stays
## quiet about it.

signal travel_requested(place: String)
## AT-5 — clicking the place you are ALREADY STANDING IN did nothing at all, so
## the gesture was free. It is the natural way in: travel there, then step inside.
signal enter_requested(place: String)

var locations: Array = []
var here := ""
var seen: Array = []          # visited place names (world.seen + here)
var fog := true               # table rule: false = the whole chart is known
var quest_text := ""          # active quest prose — matched against names
var _hover := -1
var _camera := MythCamera.new()  # the shared MDL pan/zoom (adopted per Backlog §3)
var _phase := 0.0
var _paper: ColorRect = null
var _paper_world := ""
var _paper_regions := PackedVector2Array()

## AT-3 — TWO TIERS: the realm, and one region within it.
##
## The backlog asked for realm → city → street. Two of those three exist in the
## world model and the third does not: a place is a POINT with a region and a
## kind, and there is no such thing as a street, a city interior, or anything
## inside a place at all. Building a street tier would mean inventing the data
## for it and then painting it, which is a content project, not a map feature.
##
## What was genuinely missing is the tier the data already has. Regions were
## invisible on the chart — the GM can charter one with [[region]] and the
## player would never see it appear. Now they are named on the paper, and
## clicking one frames it and dims everything outside, which is what "zoom to a
## region" actually means when the region is an area of the same chart.
var regions: Array = []
var _focus := ""              # region name, or "" for the whole realm
var _region_hover := -1

## ── ROADS THAT FOLLOW THE LAND ───────────────────────────────────────────────
##
## Roads were straight lines between pins, which is a spider-web rather than a
## road network: no road in any world runs dead straight across a bay and over a
## mountain because those were the two ends. So the road is ROUTED — an A* over a
## cost field, cheap on open ground and dear through water and high country. It
## bends around the bay because the bay costs more, not because a wobble was
## added to make it look bent.
##
## THE FIELD IS `WorldTerrain`, NOT THE PAINTING. This used to sample `chart.png`
## and call blue "water" and dark "steep", which is a colour heuristic over
## generated art — the thing [Terrain.md] deleted for the battle map. The comment
## here argued that two of its three objections did not apply. Measured
## 2026-08-26, they did:
##
##   · Neon Spire: 73.2 % of a flat city classified "expensive" (night shadow
##     read as mountain) and 0.2 % water found, in a world whose chart prompt
##     asks for light-filled canals. Roads detoured up to 1.80x around glow.
##   · Brasshaven: 0.0 % water. Its prompt also asks for canals.
##   · Worse, the plates are not maps at all — they are oblique landscape
##     illustrations WITH A HORIZON, so part of every cost grid was sky.
##
## AT-4 had already forbidden exactly this ("the paper stops claiming positions
## it cannot honour", 8a56197). This function landed two hours later and quietly
## undid it. The ground is data now, generated before anything is drawn, and
## nothing here opens an image.
##
## Built ONCE per (world, size) and every route cached — `_draw` runs every frame
## for the cloud shadows, and re-routing there would be a per-frame A*.
var _land: AStarGrid2D = null
var _land_key := ""
var _routes := {}             # "ax,ay|bx,by" → PackedVector2Array

## SEVEN KINDS, TOLD APART BY COLOUR **AND** SHAPE.
##
## This shipped with `tavern` and `settlement` both gold and `landmark` and
## `ruin` both amethyst — pairs the legend listed twice in one colour, which is
## worse than no legend because it looks like information. The check that let it
## through asserted every kind HAD a colour, not that the colours DIFFERED.
##
## Measuring them then showed the palette simply does not hold seven separable
## hues: gold and ember land 0.165 apart, which is yellow beside orange at 8 px.
## Rather than force seven colours nobody can name, each kind carries a MARK as
## well — and a shape survives being printed, dimmed, or seen by the ~8% of men
## who will not agree with us about the orange one.
const KIND_MARK := {
	"tavern":     {"col": "gold",          "shape": "dot"},      # the hearth
	"shop":       {"col": "ember",         "shape": "ring"},     # trade
	"settlement": {"col": "ink",           "shape": "square"},   # walls and numbers
	"landmark":   {"col": "amethyst",      "shape": "diamond"},  # the notable thing
	"ruin":       {"col": "amethyst_deep", "shape": "diamond"},  # what is left of one
	"wilds":      {"col": "danger",        "shape": "dot"},      # the road with teeth
	"home":       {"col": "ink_dim",       "shape": "square"},   # where you are welcome
}


func kind_color(kind: String) -> String:
	var m = KIND_MARK.get(kind)
	return str(m["col"]) if m is Dictionary else "ink_soft"


func kind_shape(kind: String) -> String:
	var m = KIND_MARK.get(kind)
	return str(m["shape"]) if m is Dictionary else "dot"


## One marker, drawn the same on the chart and in the legend — so the key is
## literally a picture of the thing it explains.
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

## AT-1 — WHAT THE COLOURS MEAN.
##
## The chart has always coloured its pins by kind and never once said so: gold,
## soft gold, amethyst and red, with nothing to read them by. A key is the
## cheapest thing that turns a picture of dots into a map.
##
## Labels live beside the colours rather than in a second table, because two
## tables drift and the drift is invisible — the legend would keep naming a
## colour the pins had stopped using.
const KIND_LABEL := {"tavern": "inn", "shop": "trade", "landmark": "landmark",
	"wilds": "wilds", "home": "home", "settlement": "settlement", "ruin": "ruin"}


func _ready() -> void:
	# PY-14 — self-drawn: a theme change does not repaint us, so ask.
	Ui.repaint_on_skin(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true  # the paper must never flood the neighbours
	custom_minimum_size = Vector2(680, 430)
	_paper = ColorRect.new()
	_paper.show_behind_parent = true
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)
	_sync_paper()
	# ALWAYS PROCESS. `set_process(not Ui.reduce_motion)` was right when _process
	# only drove cloud drift and a pulse; it now also keeps the paper aligned to
	# the camera, and a player with reduce_motion on would have panned the pins
	# away from the ground under them.
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	_sync_paper()
	queue_redraw()


## THE PAPER IS A CHILD, DRAWN BEHIND THIS NODE.
##
## A ShaderMaterial set on this Control would apply to everything it draws — the
## pins, the roads, the names, the legend — so the chart lives on its own
## ColorRect with `show_behind_parent`, which is exactly what that flag is for.
## Godot draws behind-parent children, then the parent, then normal children, so
## the scrim and every pin still land on top.
##
## It carries the camera itself rather than riding `draw_set_transform`, which
## only moves the parent's OWN draws. Keep these two in step: if the paper and
## the pins ever disagree about pan or zoom, the map is lying about position
## again, which is the whole defect this work exists to end.
func _sync_paper() -> void:
	if _paper == null:
		return
	var wid := GameState.world_id()
	if _paper_world != wid:
		_paper_world = wid
		_paper.material = WorldTerrain.for_world(wid).paper_material()
	_paper.position = _camera.cam
	_paper.size = size
	_paper.scale = Vector2(_camera.zoom, _camera.zoom)
	# AT-8 — the regions the player has actually reached, in the shader's own UV
	# space. Rebuilt only when the set changes: this runs every frame.
	var uvs := _region_uvs()
	if uvs != _paper_regions:
		_paper_regions = uvs
		var mat := _paper.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("region_n", uvs.size())
			# The uniform is a fixed-size array; a short one leaves stale hearts
			# behind it, and `region_n` would be the only thing hiding them.
			var padded := PackedVector2Array(uvs)
			while padded.size() < 8:
				padded.append(Vector2.ZERO)
			mat.set_shader_parameter("region_at", padded)


## Region hearts as UV, fog-gated. `_region_anchor` returns INF for a region with
## nothing known inside it, which is exactly the gate the labels already use — so
## the tint appears the moment the name does, and never before it.
##
## The HEART, not the anchor: `_region_anchor` is where the LABEL sits, dropped
## below the cluster so it does not print through a pin. Dividing the land by
## label positions would put every march a little south of where it belongs.
func _region_uvs() -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in regions:
		if not (r is Dictionary):
			continue
		var nm := str(r.get("name", ""))
		if nm == "" or _region_anchor(nm) == Vector2.INF:
			continue
		out.append(Vector2(float(r.get("x", 50)) / 100.0, float(r.get("y", 50)) / 100.0))
		if out.size() >= 8:
			break     # the shader's array is eight; REGION_PLACE_CAP keeps worlds small
	return out


## ── AT-6: THREE STATES, NOT TWO ──────────────────────────────────────────────
##
## `_known` was `not fog or nm == here or seen.has(nm)` — a place was either fully
## known or a question mark under a cloud. That collapses two different kinds of
## knowing: you can know OF the Sunken Fort without having stood in it.
##
## The precedent is exact. Baldur's Gate II updates the world map from dialogue
## alone; Pillars of Eternity greys the icon of a location learned by being told
## about it; Skyrim draws known-unvisited black against visited white. All three
## ship the middle state this file did not have.
##
## HEARD is clickable, following BG2 rather than Pillars: you know the place is
## out there, and setting off for it is the entire point of a chart.
enum { UNKNOWN, HEARD, VISITED }


func _state_of(nm: String) -> int:
	if not fog:
		return VISITED                  # the table turned fog off; all is known
	if nm == here or seen.has(nm) or GameState.visited(nm):
		return VISITED
	return HEARD if GameState.heard_of(nm) else UNKNOWN


## Kept as the "is this drawn at all" test, which is what every caller wanted it
## for. A place merely heard of IS drawn — that is the point — so this is now
## true one state earlier than it used to be.
func _known(nm: String) -> bool:
	return _state_of(nm) != UNKNOWN


func _questward(nm: String) -> bool:
	return nm != "" and quest_text != "" and quest_text.to_lower().contains(nm.to_lower())


func _pos_of(l: Dictionary) -> Vector2:
	return Vector2(float(l.get("x", 50)) / 100.0 * size.x, float(l.get("y", 50)) / 100.0 * size.y)


## Read the chart into a walkable cost grid. Water is dear, dark high ground is
## dear, open country is cheap. Nothing is marked SOLID — a road must always be
## drawable between two places the engine says you can travel between, so the
## worst land is expensive rather than impossible. An unroutable pair would mean
## a pin with no line to it, which reads as a bug.
func _ensure_land() -> void:
	var key := "%s@%dx%d" % [GameState.world_id(), int(size.x), int(size.y)]
	if _land != null and _land_key == key:
		return
	_land_key = key
	_routes.clear()
	var ground := WorldTerrain.for_world(GameState.world_id())
	_land = AStarGrid2D.new()
	_land.region = Rect2i(0, 0, WorldTerrain.W, WorldTerrain.H)
	# The grid is the TERRAIN's resolution, not one of its own. A second grid size
	# meant a resample between the two, and a resample is where a coordinate
	# mismatch hides — which is the bug this whole change exists to end.
	_land.cell_size = Vector2(size.x / float(WorldTerrain.W), size.y / float(WorldTerrain.H))
	_land.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_land.update()
	for y in WorldTerrain.H:
		for x in WorldTerrain.W:
			_land.set_point_weight_scale(Vector2i(x, y), ground.route_cost(Vector2i(x, y)))


## Screen pixels to a terrain cell, THROUGH PERCENT — the coordinate space every
## place already uses. Going straight from pixels to cells would work today and
## break the moment the chart is drawn at anything but the full rect; percent is
## the one space the pins, the terrain and the paper all agree on.
func _cell_of(p: Vector2) -> Vector2i:
	return WorldTerrain.for_world(GameState.world_id()).cell_of(Vector2(
		p.x / maxf(size.x, 1.0) * 100.0, p.y / maxf(size.y, 1.0) * 100.0))


## Chaikin: two passes turn an A* staircase into something drawn by a hand that
## was following a valley. Endpoints are pinned so the road still meets its pins.
func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	for _pass in 2:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array([pts[0]])
		for i in range(pts.size() - 1):
			out.append(pts[i].lerp(pts[i + 1], 0.25))
			out.append(pts[i].lerp(pts[i + 1], 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts


## The line a road actually takes. Cached, because _draw runs every frame.
func _route(a: Vector2, b: Vector2) -> PackedVector2Array:
	_ensure_land()
	var key := "%d,%d|%d,%d" % [int(a.x), int(a.y), int(b.x), int(b.y)]
	if _routes.has(key):
		return _routes[key]
	var line := PackedVector2Array([a, b])
	if _land != null:
		var path := _land.get_point_path(_cell_of(a), _cell_of(b))
		if path.size() >= 2:
			# The grid gives cell centres; the road must meet the pins exactly.
			path[0] = a
			path[path.size() - 1] = b
			line = _smooth(path)
	_routes[key] = line
	return line


## A ROAD IS DRAWN TWICE: a dark casing, then the road on it.
##
## Roads were a single thin line, which was legible over the old flat colour ramp
## and became nearly invisible the moment the chart grew hillshading, contours and
## texture — the terrain detail simply out-shouted them. This is the standard
## cartographic answer and the reason printed maps have used it for a century: a
## casing separates the line from whatever it crosses, so the road stays readable
## over snow, over forest and over open water alike without having to be brighter
## than everything around it.
func _draw_path(pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(0.08, 0.06, 0.05, col.a * 0.85), w + 2.0, true)
	draw_polyline(pts, col, w, true)


## A point a fraction `t` ALONG a road, measured by length rather than by index.
## Indexing would bunch the walking dots wherever Chaikin left dense points —
## which is exactly at the bends, the places the eye is already watching.
func _along(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var want := clampf(t, 0.0, 1.0) * total
	var run := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if run + seg >= want:
			return pts[i].lerp(pts[i + 1], 0.0 if seg <= 0.001 else (want - run) / seg)
		run += seg
	return pts[pts.size() - 1]


## Where a region's name sits: the mean of its KNOWN places, so the label lands
## on the land it describes rather than on a stored coordinate that fog may have
## made meaningless. A region with nothing known yet is not drawn at all.
func _region_anchor(rname: String) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for l in locations:
		if not (l is Dictionary) or str(l.get("region", "")).nocasecmp_to(rname) != 0:
			continue
		if not _known(str(l.get("name", ""))):
			continue
		sum += _pos_of(l)
		n += 1
	if n == 0:
		return Vector2.INF
	# Dropped below the cluster: place names draw ABOVE their pins, and a region
	# with a single known place would otherwise print straight through it. The
	# offset lives here rather than in the drawing so hit-testing and painting
	# cannot drift apart — the click must land where the word is.
	return sum / float(n) + Vector2(0, REGION_DROP)


## Regions worth drawing, with where their name goes. Fog-gated like everything
## else: a region you have not set foot in is not announced.
func _visible_regions() -> Array:
	var out: Array = []
	for r in regions:
		if not (r is Dictionary):
			continue
		var nm := str(r.get("name", ""))
		if nm == "":
			continue
		var at := _region_anchor(nm)
		if at != Vector2.INF:
			out.append({"name": nm, "at": at})
	return out


## Is this place inside the focused region? True for everything when the whole
## realm is in view, so callers need no second branch.
func _in_focus(l: Dictionary) -> bool:
	return _focus == "" or str(l.get("region", "")).nocasecmp_to(_focus) == 0


func _gui_input(event: InputEvent) -> void:
	if _camera.handle(event, self):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _camera.drag_moved:
			return
		# A place wins over a region: the pin is the smaller, more specific
		# target, and travelling is what the player came here to do.
		if _hover >= 0:
			var nm := str(locations[_hover].get("name", ""))
			if nm != here:
				travel_requested.emit(nm)
			else:
				enter_requested.emit(nm)   # AT-5: step inside where you stand
			return
		var vis := _visible_regions()
		if _region_hover >= 0 and _region_hover < vis.size():
			var rn := str(vis[_region_hover]["name"])
			_focus = "" if _focus == rn else rn   # clicking the focused one steps back out
			Sfx.ui("page")
			queue_redraw()
		elif _focus != "":
			_focus = ""                            # empty paper is the way back to the realm
			Sfx.ui("page")
			queue_redraw()
	elif event is InputEventMouseMotion:
		var mp := _camera.to_map(event.position)
		var prev := _hover
		var prev_r := _region_hover
		_hover = -1
		for i in locations.size():
			if _pos_of(locations[i]).distance_to(mp) < 22.0 / _camera.zoom:
				_hover = i
		_region_hover = -1
		if _hover < 0:
			var vis2 := _visible_regions()
			for i in vis2.size():
				if Vector2(vis2[i]["at"]).distance_to(mp) < 46.0 / _camera.zoom:
					_region_hover = i
		if _hover != prev or _region_hover != prev_r:
			queue_redraw()


func _draw() -> void:
	draw_set_transform(_camera.cam, 0.0, Vector2(_camera.zoom, _camera.zoom))
	# The paper: parchment chart preferred, key art as the fallback land.
	# R6 BUG-12 — this asked the art CACHE, which for a shipped world holds the
	# last environment plate painted, so the Atlas drew its location pins over a
	# photograph of a tavern fireplace. The compiler knows where the real
	# overhead plates live.
	# The paper itself is `_paper`, a shader behind this node — see _sync_paper.
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.18))
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
			# The walking dots follow the ROAD now. They used to arc over a
			# straight chord, which drew a route no traveller could take and
			# disagreed with the road already painted underneath them.
			var road := _route(here_p, target)
			var steps := int(target.distance_to(here_p) / 14.0) + 2
			var walk := fmod(_phase * 0.8, 1.0)
			for i in steps:
				var t := (float(i) + walk) / float(steps)
				if t > 1.0:
					continue
				var p := _along(road, t)
				draw_circle(p, 1.8, Color(Ui.c("gold_soft"), 0.75 * (1.0 - t * 0.3)))
	_draw_roads()
	_draw_regions(font)
	for i in locations.size():
		var l: Dictionary = locations[i]
		if not (l is Dictionary):
			continue
		# AT-3 — outside the focused region, a place stays on the paper but
		# steps back. Hiding it would be a different claim ("there is nothing
		# there"); this one is "not what you are looking at".
		if not _in_focus(l):
			var dp := _pos_of(l)
			draw_circle(dp, 2.5, Color(Ui.c("ink_dim"), 0.35))
			continue
		var p := _pos_of(l)
		var nm := str(l.get("name", ""))
		var is_here := nm == here
		var state := _state_of(nm)
		if state == UNKNOWN:
			# NOTHING. This drew a glow and a question mark, and a "?" is a
			# promise — it says "there is a thing here, go and get it", which
			# turns a chart into a checklist.
			#
			# The reason to drop it is stronger than taste. A point-crawl has no
			# surface to sweep: a place either has a pin or it does not, so the
			# reveal-the-whole-map busywork that fog is criticised for CANNOT
			# occur here. Drawing "?" clouds would import a failure mode this
			# design is immune to by construction. An empty edge of paper is a
			# better invitation than a row of question marks — and never add a
			# "map revealed" percentage for the same reason.
			continue
		var kind_s := str(l.get("kind", ""))
		var col: Color = Ui.c(kind_color(kind_s))
		var pulse := (0.5 + 0.5 * sin(_phase * 2.2)) if not Ui.reduce_motion else 0.5
		# Quest pull: the destination beats gold on the paper.
		if _questward(nm) and not is_here:
			draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(30, 30), Vector2(60, 60)), false, Color(Ui.c("gold"), 0.16 + 0.14 * pulse))
			var star := "✦"
			var ss := font.get_string_size(star, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			draw_string(font, p + Vector2(-ss.x / 2.0, -16), star, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(Ui.c("gold"), 0.8 + 0.2 * pulse))
		# HEARD OF: THE SHAPE, NOT THE SUBSTANCE.
		#
		# Hollow, unlit, and no trade badge — you know the place is out there and
		# roughly where, which is what a rumour gives you. Whether anyone keeps a
		# counter is something you learn by arriving.
		#
		# Hollow-vs-filled and NOT a hue difference, deliberately: the state has
		# to survive colour-blindness and a dimmed screen, which is the same rule
		# KIND_MARK already follows for the seven kinds.
		if state == HEARD:
			_draw_mark(p, kind_shape(kind_s), Color(col, 0.30), 4.0 if i == _hover else 3.0)
			draw_arc(p, 8.0, 0, TAU, 24, Color(col, 0.55 if i == _hover else 0.38), 1.2)
			var hsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			var htp := p + Vector2(-hsz.x / 2.0, -13)
			draw_string(font, htp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0, 0, 0, 0.7))
			draw_string(font, htp, nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
				Color(Ui.c("ink_dim"), 0.95 if i == _hover else 0.75))
			continue
		# The lamp of a visited place.
		draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(col, 0.22))
		_draw_mark(p, kind_shape(kind_s), Color(col, 0.95), 7.0 if i == _hover else 5.0)
		# AT-7 — WHO TRADES. A place carries a `shop` string and the Atlas never
		# once read it: "shop" appeared here only as a KIND, so a settlement or a
		# tavern with a keeper behind a counter looked exactly like one without,
		# and the only way to find out was to walk there. `merchant_window` has
		# matched this field against `here` all along; the map simply never asked.
		#
		# A BADGE, not a colour or a shape. Both of those already carry `kind`,
		# and trade is orthogonal to kind — overloading either would have broken
		# the seven-kinds rule that KIND_MARK exists to keep.
		if str(l.get("shop", "")) != "":
			_draw_trade(p)   # visited only — the HEARD branch returned above
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
		# Three states, three answers. A place merely heard of has no lore to
		# tell: the tale named it, and that is all the player has earned.
		var lore := ""
		match _state_of(nm2):
			VISITED:
				lore = str(l2.get("lore", "")).left(80)
			HEARD:
				lore = "you have heard of this place — the road will teach you the rest"
			_:
				lore = ""
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
	_draw_legend(font)


## The coin beside a pin: someone here sells things. Fog-gated with everything
## else by its caller — an undiscovered shop is not advertised.
func _draw_trade(at: Vector2) -> void:
	var c := at + Vector2(8.0, -8.0)
	draw_circle(c, 4.0, Color(Ui.c("night"), 0.92))
	draw_circle(c, 2.8, Ui.c("ember"))
	draw_arc(c, 2.8, 0, TAU, 14, Color(Ui.c("night"), 0.85), 0.9, true)


## AT-1 — THE ROADS A TRAVELLER KNOWS.
##
## A dashed line was drawn only to the place under the cursor, so with the mouse
## anywhere else the chart was pins on paper with nothing joining them. Roads are
## what make a map read as a map.
##
## Drawn as a minimum spanning tree over the places the player has actually SEEN.
## That is the honest network: it invents no topology the world never described,
## it always connects (never a stray island), and it changes as the player learns
## the land. A star from `here` to everywhere would be a lie about how they got
## there; nearest-neighbour alone leaves disconnected pairs.
## AT-2 — NAMED ROADS, over the inferred web.
##
## The spanning tree below stays: it is the honest "these places are near each
## other", and it is all most pairs will ever have. But an inferred edge cannot
## be closed for the winter, and cannot be the reason a journey takes three days
## instead of one. A named road can, so it is drawn heavier and in its own
## state's colour, on top.
##
## Both ends must be KNOWN. A road to a place still under fog would otherwise
## draw a line into blank paper and tell the player something they have not
## earned — the same rule the pins already follow.
func _draw_named_roads() -> void:
	for r in GameState.roads():
		var a := str(r.get("from", ""))
		var b := str(r.get("to", ""))
		if not (_known(a) and _known(b)):
			continue
		var pa := _pos_of_named(a)
		var pb := _pos_of_named(b)
		if pa == Vector2.INF or pb == Vector2.INF:
			continue
		var st := str(r.get("state", Rules.ROAD_DEFAULT))
		var col := Ui.c(str(Rules.road_rule(st)["col"]))
		var line := _route(pa, pb)
		if st == "blocked":
			# A closed road is still a road — draw it, then bar it, so the player
			# can see the way they cannot take. Erasing it would read as "there
			# was never a road here", which is a different fact.
			_draw_dashed_path(line, Color(col, 0.55), 2.2)
			# The bar sits at the road's own midpoint along its length, not at
			# the midpoint of the straight line between the ends — on a road that
			# bends around a bay those are nowhere near each other.
			var m := int(line.size() / 2)
			var mid: Vector2 = line[m]
			var tang: Vector2 = (line[mini(m + 1, line.size() - 1)] - line[maxi(m - 1, 0)])
			var n := (tang.normalized().orthogonal() if tang.length() > 0.01 else Vector2.UP) * 5.0
			draw_line(mid - n, mid + n, Color(col, 0.9), 2.2, true)
		else:
			_draw_path(line, Color(col, 0.75 if st == "dangerous" else 0.5), 2.4)


## Where a place sits, by name — Vector2.INF if the chart does not carry it.
func _pos_of_named(nm: String) -> Vector2:
	for l in locations:
		if l is Dictionary and str(l.get("name", "")).nocasecmp_to(nm) == 0:
			return _pos_of(l)
	return Vector2.INF


## Dashes along a ROUTED road, not a straight one — a closed road bends exactly
## as the open one it replaced did, so the eye reads the same line struck out.
func _draw_dashed_path(pts: PackedVector2Array, col: Color, w: float) -> void:
	var on := true
	var carry := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir := (b - a) / seg
		var t := 0.0
		while t < seg:
			var run: float = minf((4.0 if on else 3.0) - carry, seg - t)
			if on:
				draw_line(a + dir * t, a + dir * (t + run), col, w, true)
			t += run
			carry += run
			if carry >= (4.0 if on else 3.0):
				on = not on
				carry = 0.0


func _draw_roads() -> void:
	var pts: Array[Vector2] = []
	for l in locations:
		if l is Dictionary and _known(str(l.get("name", ""))):
			pts.append(_pos_of(l))
	if pts.size() < 2:
		_draw_named_roads()
		return
	var linked := [0]
	var loose := range(1, pts.size())
	while not loose.is_empty():
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in linked:
			for b in loose:
				var d: float = pts[a].distance_squared_to(pts[b])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		if best_b < 0:
			break
		# Old ink: a road is quieter than the places it joins — and it goes the
		# way the land allows, not the way a ruler would.
		# Brighter than the old 0.28 because the casing now carries the contrast:
		# a cased line reads at a lower alpha than a bare one, and the inferred
		# web should still be quieter than a NAMED road, which is the distinction
		# AT-2 draws.
		_draw_path(_route(pts[best_a], pts[best_b]), Color(Ui.c("ink_soft"), 0.45), 1.7)
		linked.append(best_b)
		loose.erase(best_b)
	# Named roads last, so they sit ON the web rather than under it.
	_draw_named_roads()


## AT-3 — THE REGION NAMES, and the tier they open.
##
## Set wide and small in the cartographic convention for an AREA: a region is
## not a point, so it must not read as one. Drawn UNDER the pins (called before
## them) because it labels the ground they stand on.
##
## Letterspacing is done by hand — Godot's draw_string has no tracking — and it
## is what makes the difference between "a place called The Reach" and "this
## whole stretch of country is The Reach".
## Rendering it found both of this function's bugs. A region anchored on the
## mean of its known places lands ON the pin when it has only one — and the
## worst case is a region and its place sharing a name, so "THE MOURNWOOD" was
## printed straight through "The Mournwood". Place names draw ABOVE their pins,
## so the region name goes below the cluster.
##
## The second was the legend eating the label under it, leaving "…ARCHES" on
## screen looking like a truncation bug. The legend is opaque and fixed, so a
## label whose anchor is inside it is simply not drawn — there is no room for it
## and half a word is worse than none.
const REGION_DROP := 26.0

func _draw_regions(font: Font) -> void:
	var vis := _visible_regions()
	var keep := _legend_rect(font).grow(6.0)
	for i in vis.size():
		var rn := str(vis[i]["name"]).to_upper()
		var at: Vector2 = vis[i]["at"]
		if keep.has_point(at):
			continue
		var focused := _focus != "" and str(vis[i]["name"]).nocasecmp_to(_focus) == 0
		var lit: float = 0.95 if focused else (0.75 if i == _region_hover else 0.42)
		var col := Color(Ui.c("gold_soft") if focused else Ui.c("ink_soft"), lit)
		var track := 3.4
		var wide := 0.0
		for ch in rn:
			wide += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + track
		var x := at.x - wide * 0.5
		for ch in rn:
			draw_string(font, Vector2(x, at.y + 4.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + track
		# A hairline under a focused region, so "which one am I in" survives a
		# glance without reading the word.
		if focused:
			draw_line(Vector2(at.x - wide * 0.5, at.y + 9.0), Vector2(at.x + wide * 0.5, at.y + 9.0),
				Color(Ui.c("gold"), 0.5), 1.0, true)


## What the key will list: only the kinds and road states actually ON this
## chart, because a legend explaining a mark the player has never seen is
## furniture, not information.
##
## Split out from the drawing so the region labels can ask where the legend will
## be BEFORE it is painted. One geometry, two readers — computing the rect twice
## is exactly how a legend and the thing dodging it drift apart.
const LEGEND_PAD := 8.0
const LEGEND_ROW := 14.0
const LEGEND_W := 112.0

func _legend_entries() -> Dictionary:
	var kinds: Array[String] = []
	for l in locations:
		if not (l is Dictionary):
			continue
		if fog and not _known(str(l.get("name", ""))):
			continue
		var k := str(l.get("kind", ""))
		if k != "" and KIND_LABEL.has(k) and not kinds.has(k):
			kinds.append(k)
	var road_states: Array[String] = []
	for r in GameState.roads():
		if not (_known(str(r.get("from", ""))) and _known(str(r.get("to", "")))):
			continue
		var st := str(r.get("state", Rules.ROAD_DEFAULT))
		if st != "open" and not road_states.has(st):
			road_states.append(st)
	# Does anything the player KNOWS about actually trade? The legend lists only
	# marks that are on this chart — a key explaining something never seen is
	# furniture — so the badge earns its row the same way a kind does.
	var trades := false
	for l in locations:
		if not (l is Dictionary):
			continue
		# VISITED, not merely heard of — the badge cannot appear for a rumour, so
		# the legend must not offer to explain one. The pins and the key have to
		# agree about which places show a coin or the key is furniture.
		if fog and _state_of(str(l.get("name", ""))) != VISITED:
			continue
		if str(l.get("shop", "")) != "":
			trades = true
	kinds.sort()
	road_states.sort()
	return {"kinds": kinds, "roads": road_states, "trade": trades}


func _legend_rect(_font: Font) -> Rect2:
	var e := _legend_entries()
	var rows: int = e["kinds"].size() + e["roads"].size() + (1 if e["trade"] else 0)
	if rows == 0:
		return Rect2()
	var h := LEGEND_PAD * 2.0 + LEGEND_ROW * float(rows)
	return Rect2(Vector2(12, size.y - h - 12), Vector2(LEGEND_W, h))


func _draw_legend(font: Font) -> void:
	var e := _legend_entries()
	var kinds: Array = e["kinds"]
	var road_states: Array = e["roads"]
	if kinds.is_empty() and road_states.is_empty() and not e["trade"]:
		return
	var pad := LEGEND_PAD
	var row := LEGEND_ROW
	var w := LEGEND_W
	var rect := _legend_rect(font)
	var h := rect.size.y
	var at := rect.position
	draw_rect(Rect2(at, Vector2(w, h)), Color(Ui.c("night"), 0.62))
	draw_rect(Rect2(at, Vector2(w, h)), Color(Ui.c("gold"), 0.28), false, 1.0)
	for i in kinds.size():
		var k: String = kinds[i]
		var cy := at.y + pad + row * float(i) + row * 0.5
		_draw_mark(Vector2(at.x + pad + 4.0, cy), kind_shape(k), Ui.c(kind_color(k)), 4.0)
		draw_string(font, Vector2(at.x + pad + 14.0, cy + 4.0), str(KIND_LABEL[k]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 11, Ui.c("ink_soft"))
	for j in road_states.size():
		var st2: String = road_states[j]
		var cy2 := at.y + pad + row * float(kinds.size() + j) + row * 0.5
		var col2 := Ui.c(str(Rules.road_rule(st2)["col"]))
		var x0 := at.x + pad
		if st2 == "blocked":
			_draw_dashed_path(PackedVector2Array([Vector2(x0, cy2), Vector2(x0 + 9.0, cy2)]),
				Color(col2, 0.9), 2.0)
		else:
			draw_line(Vector2(x0, cy2), Vector2(x0 + 9.0, cy2), Color(col2, 0.9), 2.2, true)
		draw_string(font, Vector2(at.x + pad + 14.0, cy2 + 4.0), str(Rules.road_rule(st2)["why"]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 11, Ui.c("ink_soft"))
	if e["trade"]:
		# LAST ROW, and drawn with `_draw_trade` — the key is literally a picture
		# of the mark it explains, which is the rule the kind marks already
		# follow. Two drawings of one badge is how a legend starts lying.
		var cyt := at.y + pad + row * float(kinds.size() + road_states.size()) + row * 0.5
		_draw_trade(Vector2(at.x + pad - 4.0, cyt + 8.0))
		draw_string(font, Vector2(at.x + pad + 14.0, cyt + 4.0), "trades here",
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 11, Ui.c("ink_soft"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
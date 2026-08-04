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

var locations: Array = []
var here := ""
var seen: Array = []          # visited place names (world.seen + here)
var fog := true               # table rule: false = the whole chart is known
var quest_text := ""          # active quest prose — matched against names
var _hover := -1
var _camera := MythCamera.new()  # the shared MDL pan/zoom (adopted per Backlog §3)
var _phase := 0.0

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
## mountain because those were the two ends. Baking the chart plate made it
## worse — now there is visible country for a straight line to ignore.
##
## So the road is ROUTED across the paper: an A* over a coarse cost grid sampled
## from the chart, cheap around open ground and expensive through water and dark
## high land. It bends around the bay because the bay costs more, not because a
## wobble was added to make it look bent.
##
## THIS IS A COLOUR HEURISTIC OVER GENERATED ART, which [Terrain.md] deleted for
## the battle map. Two of its three objections do not apply here and the third is
## avoided on purpose:
##
##  · AMBIGUITY was fatal there because the read drove MECHANICS — open snow
##    classified impassable. Here it drives nothing but the shape of a drawn
##    line. Travel cost and peril come from Rules.ROAD and GameState.roads(); a
##    misread bends a road and can never change what a journey costs.
##  · COORDINATE MISMATCH was the real bug: the board drew cover-fit and sampled
##    stretched, so the overlay described part of a painting that was off screen.
##    The chart is drawn `draw_texture_rect(art, Rect2(ZERO, size))` — the whole
##    image stretched — and is sampled the same way, so the grid and the picture
##    cannot disagree. Keep those two together if either ever changes.
##  · WALLS ARE NOT CELLS is a battle-map problem; a chart has no walls.
##
## Sampled ONCE per (world, size) and every route cached — `_draw` runs every
## frame for the cloud shadows, and re-routing there would be a per-frame A*.
const LAND_W := 56
const LAND_H := 36
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
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true  # cover-fit paper must never flood the neighbors
	custom_minimum_size = Vector2(680, 430)
	set_process(not Ui.reduce_motion)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _known(nm: String) -> bool:
	return not fog or nm == here or seen.has(nm)


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
	_land = AStarGrid2D.new()
	_land.region = Rect2i(0, 0, LAND_W, LAND_H)
	_land.cell_size = Vector2(size.x / float(LAND_W), size.y / float(LAND_H))
	_land.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_land.update()
	var art: Texture2D = Compiler.chart_art(GameState.world_id())
	if art == null:
		return                       # no paper to read: routes fall back to straight
	var img := art.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	# Stretched exactly as _draw stretches it — see the note on LAND_W.
	img.resize(LAND_W, LAND_H, Image.INTERPOLATE_LANCZOS)
	for y in LAND_H:
		for x in LAND_W:
			var c := img.get_pixel(x, y)
			# Blue running ahead of both other channels is water on every one of
			# these plates, fantasy or neon. Darkness is ridge and deep forest.
			var wet := clampf((c.b - maxf(c.r, c.g)) * 5.0, 0.0, 1.0)
			var steep := clampf((0.26 - c.get_luminance()) * 4.0, 0.0, 1.0)
			_land.set_point_weight_scale(Vector2i(x, y), 1.0 + wet * 14.0 + steep * 5.0)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(p.x / maxf(size.x, 1.0) * LAND_W), 0, LAND_W - 1),
		clampi(int(p.y / maxf(size.y, 1.0) * LAND_H), 0, LAND_H - 1))


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


func _draw_path(pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() < 2:
		return
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
	var art: Texture2D = Compiler.chart_art(GameState.world_id())
	if art == null:
		art = Art.texture_for("chart-" + GameState.world_id().validate_filename())
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
		var known := _known(nm)
		if not known:
			# Fog: the unknown sleeps under a cloud — a rumor, not a name.
			draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(34, 34), Vector2(68, 68)), false, Color(0.02, 0.02, 0.05, 0.55))
			draw_circle(p, 4.0 if i == _hover else 3.0, Color(Ui.c("ink_dim"), 0.75))
			var q := "?"
			var qs := font.get_string_size(q, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, p + Vector2(-qs.x / 2.0, -10), q, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(Ui.c("ink_dim"), 0.9))
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
		# The lamp of a known place.
		draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(col, 0.22))
		_draw_mark(p, kind_shape(kind_s), Color(col, 0.95), 7.0 if i == _hover else 5.0)
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
	_draw_legend(font)


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
		_draw_path(_route(pts[best_a], pts[best_b]), Color(Ui.c("ink_soft"), 0.28), 1.6)
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
	kinds.sort()
	road_states.sort()
	return {"kinds": kinds, "roads": road_states}


func _legend_rect(_font: Font) -> Rect2:
	var e := _legend_entries()
	var rows: int = e["kinds"].size() + e["roads"].size()
	if rows == 0:
		return Rect2()
	var h := LEGEND_PAD * 2.0 + LEGEND_ROW * float(rows)
	return Rect2(Vector2(12, size.y - h - 12), Vector2(LEGEND_W, h))


func _draw_legend(font: Font) -> void:
	var e := _legend_entries()
	var kinds: Array = e["kinds"]
	var road_states: Array = e["roads"]
	if kinds.is_empty() and road_states.is_empty():
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
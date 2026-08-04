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


func _gui_input(event: InputEvent) -> void:
	if _camera.handle(event, self):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not _camera.drag_moved and _hover >= 0:
			var nm := str(locations[_hover].get("name", ""))
			if nm != here:
				travel_requested.emit(nm)
	elif event is InputEventMouseMotion:
		var mp := _camera.to_map(event.position)
		var prev := _hover
		_hover = -1
		for i in locations.size():
			if _pos_of(locations[i]).distance_to(mp) < 22.0 / _camera.zoom:
				_hover = i
		if _hover != prev:
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
			var steps := int(target.distance_to(here_p) / 14.0) + 2
			var walk := fmod(_phase * 0.8, 1.0)
			for i in steps:
				var t := (float(i) + walk) / float(steps)
				if t > 1.0:
					continue
				var p := here_p.lerp(target, t) + Vector2(0, -sin(t * PI) * 14.0)
				draw_circle(p, 1.8, Color(Ui.c("gold_soft"), 0.75 * (1.0 - t * 0.3)))
	_draw_roads()
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
		if st == "blocked":
			# A closed road is still a road — draw it, then strike it through, so
			# the player can see the way they cannot take. Erasing it would read
			# as "there was never a road here", which is a different fact.
			_draw_dashed(pa, pb, Color(col, 0.55), 2.2)
			var mid := (pa + pb) * 0.5
			var n := (pb - pa).normalized().orthogonal() * 5.0
			draw_line(mid - n, mid + n, Color(col, 0.9), 2.2, true)
		else:
			draw_line(pa, pb, Color(col, 0.75 if st == "dangerous" else 0.5), 2.4, true)


## Where a place sits, by name — Vector2.INF if the chart does not carry it.
func _pos_of_named(nm: String) -> Vector2:
	for l in locations:
		if l is Dictionary and str(l.get("name", "")).nocasecmp_to(nm) == 0:
			return _pos_of(l)
	return Vector2.INF


func _draw_dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var span := a.distance_to(b)
	if span <= 0.0:
		return
	var dir := (b - a) / span
	var step := 7.0
	var t := 0.0
	while t < span:
		var e: float = minf(t + 4.0, span)
		draw_line(a + dir * t, a + dir * e, col, w, true)
		t += step


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
		# Old ink: a road is quieter than the places it joins.
		draw_line(pts[best_a], pts[best_b], Color(Ui.c("ink_soft"), 0.28), 1.6, true)
		linked.append(best_b)
		loose.erase(best_b)
	# Named roads last, so they sit ON the web rather than under it.
	_draw_named_roads()


## The key. Only the kinds THIS world actually uses — a legend listing entries
## the chart never draws is furniture, not information.
func _draw_legend(font: Font) -> void:
	var kinds: Array[String] = []
	for l in locations:
		if not (l is Dictionary):
			continue
		if fog and not _known(str(l.get("name", ""))):
			continue
		var k := str(l.get("kind", ""))
		if k != "" and KIND_LABEL.has(k) and not kinds.has(k):
			kinds.append(k)
	# Only the road states actually ON this chart, for the same reason as kinds:
	# a key explaining a dashed red line the player has never seen teaches them
	# that roads can close, in the most boring way available.
	var road_states: Array[String] = []
	for r in GameState.roads():
		if not (_known(str(r.get("from", ""))) and _known(str(r.get("to", "")))):
			continue
		var st := str(r.get("state", Rules.ROAD_DEFAULT))
		if st != "open" and not road_states.has(st):
			road_states.append(st)
	road_states.sort()
	if kinds.is_empty() and road_states.is_empty():
		return
	kinds.sort()
	var pad := 8.0
	var row := 14.0
	var w := 112.0
	var rows := kinds.size() + road_states.size()
	var h := pad * 2.0 + row * float(rows)
	var at := Vector2(12, size.y - h - 12)
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
			_draw_dashed(Vector2(x0, cy2), Vector2(x0 + 9.0, cy2), Color(col2, 0.9), 2.0)
		else:
			draw_line(Vector2(x0, cy2), Vector2(x0 + 9.0, cy2), Color(col2, 0.9), 2.2, true)
		draw_string(font, Vector2(at.x + pad + 14.0, cy2 + 4.0), str(Rules.road_rule(st2)["why"]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 11, Ui.c("ink_soft"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
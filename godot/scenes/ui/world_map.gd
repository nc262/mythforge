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

const KIND_COLOR := {"tavern": "gold", "shop": "gold_soft", "landmark": "amethyst",
	"wilds": "danger", "home": "ink_soft", "settlement": "gold", "ruin": "amethyst"}

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
func _draw_roads() -> void:
	var pts: Array[Vector2] = []
	for l in locations:
		if l is Dictionary and _known(str(l.get("name", ""))):
			pts.append(_pos_of(l))
	if pts.size() < 2:
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
	if kinds.is_empty():
		return
	kinds.sort()
	var pad := 8.0
	var row := 14.0
	var w := 96.0
	var h := pad * 2.0 + row * kinds.size()
	var at := Vector2(12, size.y - h - 12)
	draw_rect(Rect2(at, Vector2(w, h)), Color(Ui.c("night"), 0.62))
	draw_rect(Rect2(at, Vector2(w, h)), Color(Ui.c("gold"), 0.28), false, 1.0)
	for i in kinds.size():
		var k: String = kinds[i]
		var cy := at.y + pad + row * float(i) + row * 0.5
		draw_circle(Vector2(at.x + pad + 4.0, cy), 4.0, Ui.c(KIND_COLOR.get(k, "ink_soft")))
		draw_string(font, Vector2(at.x + pad + 14.0, cy + 4.0), str(KIND_LABEL[k]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 11, Ui.c("ink_soft"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)
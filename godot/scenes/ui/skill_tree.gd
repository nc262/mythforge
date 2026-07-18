extends Control
## ✨ The Constellation of Destiny (docs/rituals/SkillTree.md): the class's
## whole road, levels 1-20, as a night sky. Earned stars burn gold and
## amethyst joined by glowing thread; the road ahead reads as dim promises.
## Milestones are monuments; the next one breathes — it knows you're coming.
## Progression is still awarded by the level-up ceremony; this is where you
## SEE the road (and where a fresh level flares alight).

const Camera := preload("res://ui/myth_camera.gd")

var pulse_level := -1   # a freshly earned level flares on open
var _cam := Camera.new()
var _nodes: Array = []  # {kind, lv, label, desc, side, rank}
var _hover := -1
var _phase := 0.0
var _level := 1
var _motif := "constellation"   # skin-driven idiom: the road's whole visual language

const ASI_LEVELS := [4, 8, 12, 16, 19]
## family → presentation idiom (Issue 6): progression is identical, only the
## motif changes. Unlisted families read as the constellation night sky.
const MOTIF := {"cyber": "circuit", "steam": "gears", "pirate": "chart"}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(760, 500)
	set_process(not Ui.reduce_motion)
	_build()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


## Read the hero's road out of the sheet + the class tables.
func _build() -> void:
	_nodes.clear()
	var s := GameState.sheet()
	_level = int(s.get("level", 1))
	_motif = MOTIF.get(WorldSkin.family_for_id(GameState.world_id()), "constellation")
	var cls := str(s.get("cls", "Adventurer"))
	for l in range(1, 21):
		_nodes.append({"kind": "level", "lv": l, "label": "Level %d" % l, "desc": "", "side": 0, "rank": 0})
	# Milestones are monuments on the spine itself.
	var subclass := str(s.get("subclass", ""))
	_nodes.append({"kind": "milestone", "lv": 3, "label": subclass if subclass != "" else "Your path awaits",
		"desc": "The level where your %s chooses its tradition." % cls, "side": 0, "rank": 0})
	for al in ASI_LEVELS:
		_nodes.append({"kind": "milestone", "lv": al, "label": "Gift of Growth",
			"desc": "A feat, or +2 to an ability — the ceremony asks when you arrive.", "side": 0, "rank": 0})
	_nodes.append({"kind": "milestone", "lv": 20, "label": "Apotheosis",
		"desc": "The summit of the %s's road." % cls, "side": 0, "rank": 0})
	# Feature stars branch from their level.
	var side := 1
	var feats_map: Dictionary = Rules.tables.get("class_features", {}).get(cls, {})
	var lv_keys := feats_map.keys()
	lv_keys.sort_custom(func(a, b): return int(str(a)) < int(str(b)))
	for lk in lv_keys:
		var rank := 0
		for f in feats_map[lk]:
			var raw := str(f)
			var short := raw.split("(")[0].strip_edges()
			_nodes.append({"kind": "feature", "lv": int(str(lk)), "label": short,
				"desc": raw, "side": side, "rank": rank})
			rank += 1
		side = -side
	# The circles of magic, where each unlocks (casters only).
	if Rules.cast_ability(s) != "":
		var prev_max := {}
		for l in range(1, 21):
			var slots := Rules.full_caster_slots(l)
			for ck in slots:
				var mx := int(slots[ck].get("max", 0))
				if mx > 0 and int(prev_max.get(ck, 0)) == 0:
					_nodes.append({"kind": "circle", "lv": l, "label": "Circle %s Magic" % str(ck),
						"desc": "Spells of the %s circle open to you." % str(ck), "side": -1 if int(str(ck)) % 2 == 0 else 1, "rank": 1})
				prev_max[ck] = mx
	# The next milestone ahead breathes — mark it.
	var next_lv := 999
	for n in _nodes:
		if n["kind"] == "milestone" and int(n["lv"]) > _level and int(n["lv"]) < next_lv:
			next_lv = int(n["lv"])
	for n in _nodes:
		n["next"] = n["kind"] == "milestone" and int(n["lv"]) == next_lv


## The spine: a winding river of stars climbing the dark.
func _spine(lv: int) -> Vector2:
	var t := (lv - 1) / 19.0
	return Vector2(size.x * (0.5 + 0.17 * sin(t * TAU * 1.1)), size.y * (0.92 - 0.84 * t))


func _node_pos(n: Dictionary) -> Vector2:
	var base := _spine(int(n["lv"]))
	if int(n["side"]) == 0:
		return base
	return base + Vector2(int(n["side"]) * (size.x * 0.13 + int(n["rank"]) * size.x * 0.055),
		-size.y * 0.012 - int(n["rank"]) * size.y * 0.012)


func _gui_input(event: InputEvent) -> void:
	if _cam.handle(event, self):
		return
	if event is InputEventMouseMotion:
		var mp := _cam.to_map(event.position)
		var prev := _hover
		_hover = -1
		for i in _nodes.size():
			if _node_pos(_nodes[i]).distance_to(mp) < 18.0 / _cam.zoom:
				_hover = i
		if _hover != prev:
			queue_redraw()


## The screen-space fill behind everything — each motif its own ground.
func _bg_color() -> Color:
	match _motif:
		"circuit":
			return Ui.c("night2").darkened(0.15)
		"gears":
			return Ui.c("night").lerp(Color(0.16, 0.10, 0.05), 0.35)
		"chart":
			return Ui.c("surface").darkened(0.08)
		_:
			return Ui.c("night").darkened(0.3)


## Motif decor drawn in map space (scrolls with the camera): the star field,
## the circuit grid, the gearworks, or the cartographer's rhumb lines.
func _draw_decor() -> void:
	match _motif:
		"circuit":
			var step := 46.0
			var gx := 0.0
			while gx < size.x:
				draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(Ui.c("border"), 0.18), 1.0)
				gx += step
			var gy := 0.0
			while gy < size.y:
				draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(Ui.c("border"), 0.14), 1.0)
				gy += step
			for i in 40:  # solder pads at pseudo-random intersections
				var cx := (0.5 + floor(absf(fmod(sin(i * 91.7) * 4137.1, 1.0)) * size.x / step)) * step
				var cy := (0.5 + floor(absf(fmod(sin(i * 57.3) * 7351.9, 1.0)) * size.y / step)) * step
				draw_circle(Vector2(cx, cy), 1.6, Color(Ui.c("gold"), 0.25))
		"gears":
			for spec in [[0.16, 0.2, 120.0], [0.86, 0.78, 160.0], [0.78, 0.16, 90.0]]:
				var c := Vector2(size.x * float(spec[0]), size.y * float(spec[1]))
				var rad := float(spec[2])
				var spin := _phase * 0.15 if not Ui.reduce_motion else 0.0
				for teeth in [rad, rad * 0.6]:
					draw_arc(c, teeth, 0, TAU, 40, Color(Ui.c("gold"), 0.12), 2.0)
				for k in 12:
					var ang := k * TAU / 12.0 + spin
					draw_line(c + Vector2(cos(ang), sin(ang)) * rad, c + Vector2(cos(ang), sin(ang)) * (rad + 8.0), Color(Ui.c("gold"), 0.12), 2.0)
		"chart":
			var step2 := 60.0
			var gx2 := 0.0
			while gx2 < size.x:
				draw_line(Vector2(gx2, 0), Vector2(gx2, size.y), Color(Ui.c("border"), 0.16), 1.0)
				gx2 += step2
			var gy2 := 0.0
			while gy2 < size.y:
				draw_line(Vector2(0, gy2), Vector2(size.x, gy2), Color(Ui.c("border"), 0.12), 1.0)
				gy2 += step2
			var rose := Vector2(size.x * 0.5, size.y * 0.5)  # a faint compass rose watermark
			for k in 8:
				var ang := k * PI / 4.0
				draw_line(rose, rose + Vector2(sin(ang), -cos(ang)) * (size.y * 0.42 if k % 2 == 0 else size.y * 0.24), Color(Ui.c("gold"), 0.08), 1.0)
		_:  # constellation: deep field, drifting nebulae, fixed stars
			if not Ui.reduce_motion:
				for spec in [[0.25, 0.3, 340.0, "amethyst_deep", 11.0], [0.7, 0.62, 420.0, "gold", -7.0]]:
					var ns := float(spec[2])
					var np := Vector2(size.x * float(spec[0]) + sin(_phase * 0.1) * float(spec[4]),
						size.y * float(spec[1]) + cos(_phase * 0.08) * float(spec[4]))
					draw_texture_rect(Ui.glow_tex(), Rect2(np - Vector2(ns, ns) / 2.0, Vector2(ns, ns)),
						false, Color(Ui.c(str(spec[3])), 0.10))
			for i in 110:
				var h1 := fmod(sin(i * 127.1) * 43758.5453, 1.0)
				var h2 := fmod(sin(i * 311.7) * 12543.8367, 1.0)
				var sp := Vector2(absf(h1) * size.x, absf(h2) * size.y)
				var tw := 0.25 + 0.2 * sin(_phase * 1.4 + i)
				draw_circle(sp, 0.9, Color(Ui.c("ink_soft"), tw))


## One connective link between two road points, styled to the motif.
func _link(pts: PackedVector2Array, earned: bool, role: String) -> void:
	var lit := Color(Ui.c(role), 0.8) if earned else Color(Ui.c("ink_dim"), 0.3)
	match _motif:
		"circuit":  # a trace with a solder node where it lands
			draw_polyline(pts, lit, 1.8 if earned else 1.2, true)
			if earned:
				draw_circle(pts[pts.size() - 1], 2.2, Ui.c(role))
		"gears":  # a solid brass linkage
			draw_polyline(pts, lit, 2.4 if earned else 1.4, true)
		"chart":  # a dashed rhumb line
			var k := 0
			while k < pts.size() - 1:
				draw_line(pts[k], pts[k + 1], lit, 1.5)
				k += 2
		_:  # constellation: a glowing thread
			if earned:
				draw_polyline(pts, Color(Ui.c(role), 0.16), 6.0, true)
			draw_polyline(pts, Color(Ui.c(role), 0.75) if earned else Color(Ui.c("ink_dim"), 0.3), 1.6, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _bg_color())
	draw_set_transform(_cam.cam, 0.0, Vector2(_cam.zoom, _cam.zoom))
	_draw_decor()
	# The threads: earned segments read strong; the road ahead is a dim promise.
	for l in range(1, 20):
		var a := _spine(l)
		var b := _spine(l + 1)
		var mid := (a + b) / 2.0 + (b - a).orthogonal().normalized() * 7.0
		var pts := PackedVector2Array()
		for k in 13:
			var t := k / 12.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		_link(pts, l < _level, "gold")
	for n in _nodes:
		if int(n["side"]) == 0:
			continue
		var a2 := _spine(int(n["lv"]))
		var b2 := _node_pos(n)
		var mid2 := (a2 + b2) / 2.0 + (b2 - a2).orthogonal().normalized() * 9.0
		var pts2 := PackedVector2Array()
		for k in 11:
			var t2 := k / 10.0
			pts2.append(a2.lerp(mid2, t2).lerp(mid2.lerp(b2, t2), t2))
		_link(pts2, int(n["lv"]) <= _level, "amethyst")
	# The stars themselves.
	var font := get_theme_default_font()
	var breathe := (0.5 + 0.5 * sin(_phase * 2.0)) if not Ui.reduce_motion else 0.5
	for i in _nodes.size():
		var n: Dictionary = _nodes[i]
		var p := _node_pos(n)
		var lv := int(n["lv"])
		var earned := lv <= _level
		var flare := 1.0
		if lv == pulse_level and _phase < 2.5 and not Ui.reduce_motion:
			flare = 1.0 + 1.6 * maxf(0.0, sin(_phase * 3.2)) * (1.0 - _phase / 2.5)
		match str(n["kind"]):
			"level":
				if earned:
					draw_circle(p, 4.5 * flare, Ui.c("gold"))
					if lv == _level:
						draw_arc(p, (8.0 + 2.0 * breathe) * flare, 0, TAU, 24, Ui.c("gold_soft"), 1.8, true)
						draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(22, 22), Vector2(44, 44)), false, Color(Ui.c("gold"), 0.3))
				else:
					draw_arc(p, 3.5, 0, TAU, 16, Color(Ui.c("ink_dim"), 0.7), 1.2, true)
			"feature":
				if earned:
					draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(16, 16), Vector2(32, 32)), false, Color(Ui.c("amethyst"), 0.35))
					draw_circle(p, 5.5 * flare, Ui.c("amethyst"))
				else:
					draw_arc(p, 4.5, 0, TAU, 16, Color(Ui.c("ink_dim"), 0.6), 1.2, true)
				var fl := str(n["label"])
				var fs := font.get_string_size(fl, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
				draw_string(font, p + Vector2(-fs.x / 2.0, -11), fl, HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
					Color(Ui.c("ink_soft"), 0.95) if earned else Color(Ui.c("ink_dim"), 0.7))
			"circle":
				var star := PackedVector2Array()
				for k in 8:
					var ang := k * PI / 4.0
					star.append(p + Vector2(sin(ang), -cos(ang)) * (8.0 if k % 2 == 0 else 3.2) * flare)
				if earned:
					draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(18, 18), Vector2(36, 36)), false, Color(Ui.c("amethyst_deep"), 0.4))
					draw_colored_polygon(star, Ui.c("amethyst_deep").lightened(0.2))
				else:
					draw_polyline(star, Color(Ui.c("ink_dim"), 0.6), 1.0, true)
				var cl := str(n["label"])
				var cs := font.get_string_size(cl, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
				draw_string(font, p + Vector2(-cs.x / 2.0, -13), cl, HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
					Color(Ui.c("ink_soft"), 0.9) if earned else Color(Ui.c("ink_dim"), 0.7))
			"milestone":
				var r := 10.0 * flare
				var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
				if earned:
					draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(30, 30), Vector2(60, 60)), false, Color(Ui.c("gold"), 0.4))
					draw_colored_polygon(dia, Ui.c("gold"))
					draw_polyline(dia + PackedVector2Array([dia[0]]), Ui.c("gold_soft"), 1.5, true)
				else:
					if bool(n.get("next", false)):
						draw_texture_rect(Ui.glow_tex(), Rect2(p - Vector2(34, 34), Vector2(68, 68)), false, Color(Ui.c("gold"), 0.12 + 0.14 * breathe))
					draw_polyline(dia + PackedVector2Array([dia[0]]), Color(Ui.c("gold"), 0.55), 1.4, true)
				var ml := str(n["label"])
				var ms := font.get_string_size(ml, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
				draw_string(font, p + Vector2(-ms.x / 2.0, -15), ml, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
					Ui.c("gold_soft") if earned else Color(Ui.c("gold"), 0.7))
	# The ledger: the hovered star tells its story (screen-space).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _hover >= 0:
		var n3: Dictionary = _nodes[_hover]
		var lv3 := int(n3["lv"])
		var story := "%s  —  %s" % [str(n3["label"]),
			("earned at level %d" % lv3) if lv3 <= _level else ("awaits at level %d" % lv3)]
		if str(n3["desc"]) != "":
			story += "   ·   " + str(n3["desc"])
		draw_rect(Rect2(Vector2(0, size.y - 26), Vector2(size.x, 26)), Color(Ui.c("night"), 0.82))
		draw_string(font, Vector2(12, size.y - 8), story.left(140), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, Ui.c("gold_soft"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("border"), 0.9), false, 2.0)

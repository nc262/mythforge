class_name MapInk extends RefCounted
## AT-10 — THE SYMBOLS A CHART IS DRAWN WITH.
##
## The chart became ink on parchment and the PLACE MARKS did not: a purple
## diamond, an orange ring, a cyan dot — shapes and hues picked for a dark UI
## panel, sitting on a book map. On a drawn chart a settlement is a little tower,
## a ruin is a broken arch, an inn is a cup. Same ink as the coastline.
##
## ONE HOME, because the Atlas draws these, the legend draws these, and the local
## maps draw these. Three copies of "what a ruin looks like" is three chances for
## the key to stop describing the map — and `_draw_mark` was already duplicated
## between `world_map` and `place_map` before this existed.
##
## SILHOUETTE FIRST, and this is a rule rather than a preference. `KIND_MARK`
## paired colour with shape because the palette does not hold seven separable
## hues — gold and ember land 0.165 apart, which is yellow beside orange at 8 px.
## In one ink there is no hue left at all, so the shape has to carry the whole
## distinction on its own. Every symbol below is recognisable as a black
## silhouette at 12 px, or it does not belong here.

## Every mark is drawn with the paper showing through it rather than filled
## solid: an engraver leaves the sheet inside a symbol so the hatching behind it
## does not read through, and a solid blob loses its silhouette at small sizes.
static func draw_mark(ci: CanvasItem, at: Vector2, kind: String, ink: Color,
		paper: Color, r: float) -> void:
	match kind:
		"tavern":
			_house(ci, at, ink, paper, r, true)
		"home":
			_house(ci, at, ink, paper, r, false)
		"shop":
			_stall(ci, at, ink, paper, r)
		"settlement":
			_towers(ci, at, ink, paper, r)
		"landmark":
			_pillar(ci, at, ink, paper, r)
		"ruin":
			_broken(ci, at, ink, r)
		"wilds":
			_thicket(ci, at, ink, paper, r)
		_:
			ci.draw_circle(at, r * 0.55, paper)
			ci.draw_arc(at, r * 0.55, 0, TAU, 16, ink, maxf(1.2, r * 0.16), true)


## A house: walls and a pitched roof. With a chimney it is an inn — somewhere
## with a fire lit, which is what a tavern is on a chart.
static func _house(ci: CanvasItem, at: Vector2, ink: Color, paper: Color,
		r: float, hearth: bool) -> void:
	var w := r * 0.86
	var hgt := r * 0.72
	var eaves := at + Vector2(0, hgt * 0.35)
	var body := PackedVector2Array([
		eaves + Vector2(-w, 0), eaves + Vector2(w, 0),
		eaves + Vector2(w, hgt), eaves + Vector2(-w, hgt)])
	ci.draw_colored_polygon(body, paper)
	var roof := PackedVector2Array([
		eaves + Vector2(-w * 1.18, 0), at + Vector2(0, -hgt * 0.95),
		eaves + Vector2(w * 1.18, 0)])
	ci.draw_colored_polygon(roof, paper)
	var lw: float = maxf(1.2, r * 0.15)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, lw, true)
	ci.draw_polyline(roof + PackedVector2Array([roof[0]]), ink, lw, true)
	if hearth:
		var cx := at + Vector2(w * 0.55, -hgt * 0.55)
		ci.draw_line(cx, cx + Vector2(0, -r * 0.5), ink, lw, true)


## A stall: an awning over a counter. Trade, without needing a coin glyph that
## would be a dot at this size.
static func _stall(ci: CanvasItem, at: Vector2, ink: Color, paper: Color, r: float) -> void:
	var w := r * 0.95
	var lw: float = maxf(1.2, r * 0.15)
	var top := at + Vector2(0, -r * 0.55)
	var awning := PackedVector2Array([
		top + Vector2(-w, r * 0.3), top + Vector2(0, -r * 0.25), top + Vector2(w, r * 0.3)])
	ci.draw_colored_polygon(awning, paper)
	ci.draw_polyline(awning, ink, lw, true)
	ci.draw_line(at + Vector2(-w * 0.75, r * 0.05), at + Vector2(-w * 0.75, r * 0.8), ink, lw, true)
	ci.draw_line(at + Vector2(w * 0.75, r * 0.05), at + Vector2(w * 0.75, r * 0.8), ink, lw, true)
	ci.draw_line(at + Vector2(-w, r * 0.8), at + Vector2(w, r * 0.8), ink, lw, true)


## Towers behind a wall — the classic town glyph, and the only symbol here that
## is deliberately WIDE, because a settlement should read as bigger than the
## single buildings around it.
static func _towers(ci: CanvasItem, at: Vector2, ink: Color, paper: Color, r: float) -> void:
	var lw: float = maxf(1.2, r * 0.14)
	var base := at + Vector2(0, r * 0.75)
	for spec in [[-1.0, 0.95], [0.0, 1.35], [1.0, 0.8]]:
		var dx := float(spec[0]) * r * 0.72
		var hgt := float(spec[1]) * r
		var w := r * 0.34
		var t := PackedVector2Array([
			base + Vector2(dx - w, 0), base + Vector2(dx - w, -hgt),
			base + Vector2(dx + w, -hgt), base + Vector2(dx + w, 0)])
		ci.draw_colored_polygon(t, paper)
		ci.draw_polyline(t + PackedVector2Array([t[0]]), ink, lw, true)
	ci.draw_line(base + Vector2(-r * 1.15, 0), base + Vector2(r * 1.15, 0), ink, lw * 1.4, true)


## A standing stone or monument: the notable thing on the skyline.
static func _pillar(ci: CanvasItem, at: Vector2, ink: Color, paper: Color, r: float) -> void:
	var lw: float = maxf(1.2, r * 0.15)
	var body := PackedVector2Array([
		at + Vector2(-r * 0.34, r * 0.8), at + Vector2(-r * 0.22, -r * 0.9),
		at + Vector2(r * 0.22, -r * 0.9), at + Vector2(r * 0.34, r * 0.8)])
	ci.draw_colored_polygon(body, paper)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, lw, true)
	ci.draw_line(at + Vector2(-r * 0.7, r * 0.8), at + Vector2(r * 0.7, r * 0.8), ink, lw, true)


## What is LEFT of a building: two uprights and a broken span. Deliberately not
## filled with paper — a ruin is open to the sky, and the gap is the whole point.
static func _broken(ci: CanvasItem, at: Vector2, ink: Color, r: float) -> void:
	var lw: float = maxf(1.2, r * 0.15)
	var base := at + Vector2(0, r * 0.8)
	ci.draw_line(base + Vector2(-r * 0.7, 0), base + Vector2(-r * 0.62, -r * 1.4), ink, lw, true)
	ci.draw_line(base + Vector2(r * 0.7, 0), base + Vector2(r * 0.58, -r * 0.95), ink, lw, true)
	# The span, snapped: a stub off each upright and nothing between them.
	ci.draw_line(base + Vector2(-r * 0.62, -r * 1.4), base + Vector2(-r * 0.18, -r * 1.2), ink, lw, true)
	ci.draw_line(base + Vector2(r * 0.58, -r * 0.95), base + Vector2(r * 0.3, -r * 1.05), ink, lw, true)
	ci.draw_line(base + Vector2(-r * 0.9, 0), base + Vector2(r * 0.9, 0), ink, lw, true)


## Trees, for country with no one in it.
static func _thicket(ci: CanvasItem, at: Vector2, ink: Color, paper: Color, r: float) -> void:
	var lw: float = maxf(1.1, r * 0.13)
	for spec in [[-0.55, 0.78], [0.5, 1.0]]:
		var c := at + Vector2(float(spec[0]) * r, r * 0.4 - float(spec[1]) * r * 0.75)
		var rad := r * 0.45 * float(spec[1])
		ci.draw_circle(c, rad, paper)
		ci.draw_arc(c, rad, 0, TAU, 14, ink, lw, true)
		ci.draw_line(c + Vector2(0, rad * 0.4), c + Vector2(0, rad * 1.9), ink, lw, true)

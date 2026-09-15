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


## ── ORNAMENT ─────────────────────────────────────────────────────────────────
##
## The reference is a book map, and half of what makes one look like a book map
## is the furniture: a rose, a ship or two in the open water, something with
## teeth in the deep, and a ruled border round the whole sheet. None of it is
## information — which is exactly why it belongs in the empty parts, and why it
## must never sit where a pin or a name goes.


## A sixteen-point rose. Four long points on the cardinals, four short on the
## ordinals, eight shorter still between — the standard construction, and the
## reason it reads as a rose rather than a star is that the alternation is
## regular and the fills alternate light and dark.
static func draw_rose(ci: CanvasItem, at: Vector2, r: float, ink: Color, paper: Color) -> void:
	ci.draw_circle(at, r * 1.06, paper)
	ci.draw_arc(at, r * 1.06, 0, TAU, 40, Color(ink, 0.55), 1.2, true)
	ci.draw_arc(at, r * 0.9, 0, TAU, 36, Color(ink, 0.35), 1.0, true)
	for i in 16:
		var ang := float(i) / 16.0 * TAU - PI * 0.5
		var long: float = r
		if i % 4 != 0:
			long = r * (0.58 if i % 2 == 1 else 0.76)
		var tip := at + Vector2(cos(ang), sin(ang)) * long
		var wide := r * 0.10
		var l := at + Vector2(cos(ang - PI * 0.5), sin(ang - PI * 0.5)) * wide
		var rr := at + Vector2(cos(ang + PI * 0.5), sin(ang + PI * 0.5)) * wide
		# Two halves per point, one inked and one left as paper — the alternation
		# is what gives a rose its cut-gem look at any size.
		ci.draw_colored_polygon(PackedVector2Array([at, l, tip]), Color(ink, 0.85))
		ci.draw_colored_polygon(PackedVector2Array([at, rr, tip]), paper)
		ci.draw_polyline(PackedVector2Array([at, rr, tip, l, at]), Color(ink, 0.8), 1.0, true)


## A ship, side on, three sails. Small enough to be furniture and specific
## enough not to read as a smudge.
static func draw_ship(ci: CanvasItem, at: Vector2, r: float, ink: Color, paper: Color) -> void:
	var lw: float = maxf(1.0, r * 0.09)
	var hull := PackedVector2Array([
		at + Vector2(-r, 0), at + Vector2(r, 0),
		at + Vector2(r * 0.66, r * 0.42), at + Vector2(-r * 0.72, r * 0.42)])
	ci.draw_colored_polygon(hull, paper)
	ci.draw_polyline(hull + PackedVector2Array([hull[0]]), Color(ink, 0.9), lw, true)
	ci.draw_line(at + Vector2(0, 0), at + Vector2(0, -r * 1.5), Color(ink, 0.9), lw, true)
	for spec in [[-0.55, 0.85], [0.5, 1.15]]:
		var sx := float(spec[0]) * r
		var sh := float(spec[1]) * r
		var sail := PackedVector2Array([
			at + Vector2(sx, -sh), at + Vector2(sx + r * 0.5, -sh * 0.45),
			at + Vector2(sx, -sh * 0.1)])
		ci.draw_colored_polygon(sail, paper)
		ci.draw_polyline(sail + PackedVector2Array([sail[0]]), Color(ink, 0.85), lw * 0.9, true)


## Something in the deep: a serpent in three coils. Drawn as arcs rather than a
## silhouette, because at this size a filled beast is a blob and the whole point
## of the thing is that it is recognisable.
static func draw_beast(ci: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var lw: float = maxf(1.1, r * 0.11)
	for i in 3:
		var c := at + Vector2(float(i - 1) * r * 0.82, sin(float(i) * 1.7) * r * 0.18)
		ci.draw_arc(c, r * 0.42, PI, TAU, 14, Color(ink, 0.85), lw, true)
	# The head, at the near end, with an eye and a jaw.
	var head := at + Vector2(-r * 1.5, -r * 0.1)
	ci.draw_arc(head, r * 0.3, -PI * 0.4, PI * 1.1, 14, Color(ink, 0.9), lw, true)
	ci.draw_circle(head + Vector2(-r * 0.06, -r * 0.08), lw * 0.85, Color(ink, 0.95))
	ci.draw_line(head + Vector2(-r * 0.28, r * 0.02), head + Vector2(-r * 0.62, -r * 0.12),
		Color(ink, 0.85), lw, true)


## The sheet's edge: a heavy rule, a hairline inside it, and a corner mark at
## each turn. Drawn OUTSIDE the camera transform so it stays put while the map
## pans under it — a border that scrolls away is a rectangle, not a frame.
static func draw_border(ci: CanvasItem, rect: Rect2, ink: Color, paper: Color) -> void:
	var outer := rect.grow(-6.0)
	var inner := rect.grow(-13.0)
	ci.draw_rect(outer, Color(ink, 0.8), false, 2.6)
	ci.draw_rect(inner, Color(ink, 0.45), false, 1.1)
	for corner in [inner.position, inner.position + Vector2(inner.size.x, 0),
			inner.position + inner.size, inner.position + Vector2(0, inner.size.y)]:
		ci.draw_circle(corner, 4.4, paper)
		ci.draw_arc(corner, 4.4, 0, TAU, 18, Color(ink, 0.75), 1.4, true)
		ci.draw_arc(corner, 2.0, 0, TAU, 12, Color(ink, 0.55), 1.0, true)


## ── LETTERING THAT CAN BE READ OFF A BUSY SHEET ──────────────────────────────
##
## A map label lies over the map, so its background is not the paper — it is
## whatever the map drew there. On Gallows Quay "The Common Room" ran across
## inked rooftops and the glyph cores came out LIGHTER than their own halo:
## measured off the render, the word sat near 1.5:1 against the ground directly
## behind it, against the 4.5:1 the rest of this game is held to.
##
## Two faults, and the halo was both of them. Four offsets at 1.3 px leave the
## diagonals bare, and the paper went down at 0.92 alpha so the ink underneath it
## still showed through and greyed the letter. Eight offsets, an inner ring to
## close the gaps, opaque paper, and ink at full strength.
##
## THIS LIVES HERE BECAUSE IT LIVED IN TWO PLACES. `world_map` and `place_map`
## each carried their own copy of the thin version — the same duplication that
## cost this repo an art key spelled six ways and a fallback hand-written at five
## sites. One drawing, one home, both tiers.
static func draw_label(ci: CanvasItem, font: Font, at: Vector2, text: String,
		size: int, ink: Color, paper: Color, strength := 1.0) -> void:
	if text == "":
		return
	var r := maxf(float(size) * 0.16, 1.8)
	for k in 8:
		var o := Vector2(r, 0).rotated(float(k) / 8.0 * TAU)
		ci.draw_string(font, at + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, paper)
	for k in 4:
		var o2 := Vector2(r * 0.55, 0).rotated(float(k) / 4.0 * TAU + PI * 0.25)
		ci.draw_string(font, at + o2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, paper)
	ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink, strength))

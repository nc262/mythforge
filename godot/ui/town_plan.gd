class_name TownPlan extends RefCounted
## AT-14 — A TOWN PLAN BUILT THE WAY THEY ARE ACTUALLY BUILT.
##
## ── WHY THE OLD ONE LOOKED LIKE A DIAGRAM ────────────────────────────────────
## The first generator subdivided an AXIS-ALIGNED RECTANGLE into lots, then threw
## away every lot that fell on a street, in the water, or outside the wall. Two
## faults, and each is fatal on its own:
##
##   · the thing being split was a rectangle, so every lot was a rectangle, and a
##     town of axis-aligned boxes reads as graph paper however much it is jittered
##   · most candidates were DISCARDED, so the result was sparse — and sparse is
##     what makes a town read as a hamlet scattered in a field
##
## ── WHAT REAL GENERATORS DO ──────────────────────────────────────────────────
## Read out of watabou/TownGeneratorOS (`Ward.hx`, `Cutter.hx`) rather than
## inferred from devlogs. Three things, and the third is the one that changes
## everything:
##
##   1. SPLIT THE POLYGON, NOT A RECTANGLE. Cut along its LONGEST EDGE, at a
##      ratio near the middle, with the cut angle jittered. Children are
##      arbitrary polygons and get cut the same way. Every building is therefore
##      a sub-polygon of its block, which means every wall facing a street is
##      PARALLEL TO THAT STREET by construction — no "rotate the building to face
##      the road" step, because the geometry cannot come out any other way.
##
##   2. NO REJECT STEP. Recurse on both halves unconditionally and keep every
##      leaf. Density is not tuned, it is structural.
##
##   3. THE STREET IS THE GAP. Each cut opens a physical gap of the street's
##      width, and each block is inset before it is subdivided. Streets are never
##      drawn as lines over a layout — they are the negative space left behind,
##      so a building cannot cross a street any more than it can cross the wall.
##
## Widths keep Watabou's ratio (main : regular : alley ~ 2 : 1 : 0.6) rather than
## his units, because his are in the tool's own coordinate space and this plate
## is 100 units across.
##
## Cutting is Sutherland–Hodgman, written here rather than reached for through
## `Geometry2D.clip_polygons`: Clipper quantises to an integer grid and has an
## open bug (godot#91285) where aligned edges — which recursive subdivision
## produces constantly — emit degenerate rings that `triangulate_polygon` then
## silently returns empty for. Half-plane clipping is exact, twenty lines, and
## has no such failure.

const MAIN_STREET := 2.4
const REGULAR_STREET := 1.2
const ALLEY := 0.7


## Clip a polygon to the half-plane on one side of a line. The whole geometric
## foundation of this file, and deliberately the only clipping it does.
static func _half(poly: PackedVector2Array, at: Vector2, nrm: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n < 3:
		return out
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var da := (a - at).dot(nrm)
		var db := (b - at).dot(nrm)
		if da >= 0.0:
			out.append(a)
		# A sign change means the edge crosses the line: emit the crossing point.
		if (da >= 0.0) != (db >= 0.0):
			var t := da / (da - db)
			out.append(a + (b - a) * t)
	return out


static func area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	return absf(_signed_area(poly))


static func centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(poly.size())


## The longest edge, which is where a block wants to be cut: splitting the long
## way makes two blocks of sensible proportion, and splitting the short way makes
## slivers.
static func _longest_edge(poly: PackedVector2Array) -> int:
	var best := 0
	var bl := -1.0
	for i in poly.size():
		var d: float = poly[i].distance_to(poly[(i + 1) % poly.size()])
		if d > bl:
			bl = d
			best = i
	return best


## CUT IN TWO, WITH A GAP. The gap is the street: each half is clipped to its own
## side of a line offset by half the width, so the space between them is empty by
## construction rather than by a later subtraction.
static func cut(poly: PackedVector2Array, gap: float, ratio: float,
		skew: float) -> Array:
	if poly.size() < 3:
		return []
	var i := _longest_edge(poly)
	var a: Vector2 = poly[i]
	var b: Vector2 = poly[(i + 1) % poly.size()]
	var along := (b - a).normalized()
	var at := a + (b - a) * ratio
	# THE HALF-PLANE NORMAL IS PERPENDICULAR TO THE DIVIDING LINE, which is the
	# whole trap here. Using `along.rotated(90 degrees)` as the normal puts the
	# dividing line PARALLEL to the longest edge, so every "split" shaved a thin
	# strip off one side and the town came out as slivers. The normal has to be
	# the edge direction itself for the cut to run ACROSS the block.
	#
	# The skew jitters it off true, because a perfectly square cut every time is
	# what makes a subdivided shape read as a spreadsheet.
	var nrm := along.rotated(skew)
	var left := _half(poly, at + nrm * (gap * 0.5), nrm)
	var right := _half(poly, at - nrm * (gap * 0.5), -nrm)
	var out: Array = []
	if left.size() >= 3 and area(left) > 0.001:
		out.append(left)
	if right.size() >= 3 and area(right) > 0.001:
		out.append(right)
	return out


## ── INSET: MOVE EVERY VERTEX ALONG ITS BISECTOR ──────────────────────────────
##
## THIS WAS HALF-PLANE CLIPPING AND IT WAS DEMOLISHING THE TOWN. Clipping the
## polygon to one side of each edge's line is only an inset when the polygon is
## CONVEX. These are not: a ward inherits its shape from `bounds`, which is a
## lobed ring cut back wherever the sea is, so it carries one to four reflex
## vertices — and at a reflex vertex that infinite line runs straight through the
## body and takes a wedge of it away.
##
## Measured before the fix, at a 0.6-unit inset on a 100-unit plate:
##
##     ward area  550  509  393  277  173
##     "inset"    103  322    0   13  126
##
## A 393-unit quarter reduced to NOTHING, which is why whole districts rendered
## as bare ground — not the recursion cap, which was the first suspect and was
## innocent: the counters read nocut=0 onecut=0 cap=0 across all fourteen towns.
##
## Moving each vertex along the bisector of its two edges is the textbook offset
## and is exact for any simple polygon, reflex vertices included: the distance
## along the bisector is `by / cos(half-turn)`, which is what keeps both new
## edges parallel to their originals at exactly `by`.
static func inset(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return PackedVector2Array()
	# Orientation first, so "inward" is one rule rather than a per-vertex guess.
	var ring := poly
	if _signed_area(ring) < 0.0:
		ring.reverse()
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = ring[(i + n - 1) % n]
		var here: Vector2 = ring[i]
		var next: Vector2 = ring[(i + 1) % n]
		var d0 := (here - prev).normalized()
		var d1 := (next - here).normalized()
		if d0.length_squared() < 0.5 or d1.length_squared() < 0.5:
			continue                          # duplicated vertex; nothing to bisect
		var n0 := d0.rotated(PI * 0.5)        # inward, given the orientation above
		var n1 := d1.rotated(PI * 0.5)
		var bis := (n0 + n1)
		if bis.length_squared() < 0.000001:
			continue                          # a 180-degree spike has no inside
		bis = bis.normalized()
		# CLAMPED. At a near-reversal the exact distance goes to infinity and the
		# vertex shoots across the map; a spike that long is not worth a mitre.
		var denom: float = maxf(bis.dot(n0), 0.25)
		out.append(here + bis * (by / denom))
	# A shape that grew, inverted or vanished was not inset — it self-intersected,
	# which is what an offset does to a piece thinner than twice the distance.
	# Returning nothing is honest; returning a bow-tie is a building shaped like
	# an hourglass.
	if out.size() < 3:
		return PackedVector2Array()
	var a := area(out)
	if a <= 0.001 or a > area(poly):
		return PackedVector2Array()
	return out


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## ── SUBDIVIDE A BLOCK INTO BUILDINGS ─────────────────────────────────────────
##
## Recurse until the piece is under a TARGET AREA that is itself jittered
## log-normally, which is what gives a town some plainly larger buildings among
## mostly middling ones. A single flat threshold gives every building the same
## size, and same-size boxes are the other half of the graph-paper look.
##
## `empty_prob` drops the occasional finished lot, leaving a yard or a garden.
## Watabou's richer wards use a much higher value than his poor ones; that is
## what a courtyard IS, structurally.
static func subdivide(block: PackedVector2Array, min_area: float,
		grid_chaos: float, size_chaos: float, empty_prob: float,
		rng: RandomNumberGenerator, out: Array, depth := 0) -> void:
	if block.size() < 3:
		return
	# AT THE DEPTH CAP, KEEP THE BLOCK — do not drop it. Returning empty here
	# meant any ward that needed more splits than the cap allows lost EVERY
	# building under that branch, silently, and the quarter rendered as open
	# ground. A too-large building is a visible imperfection; a vanished district
	# is a hole nobody can diagnose from the picture.
	if depth > 11:
		out.append(block)
		return
	var target: float = min_area * pow(2.0, 4.0 * size_chaos * (rng.randf() - 0.5))
	if area(block) < target:
		if rng.randf() >= empty_prob:
			out.append(block)
		return
	# THIRTY DEGREES, not sixty. Watabou's figure is +/-30 at full chaos and I
	# doubled it; at 60 the cuts cross each other steeply enough that most leaves
	# come out as WEDGES, and a town of triangles reads as broken glass rather
	# than as buildings. The ratio jitter came down with it for the same reason.
	var halves := cut(block, ALLEY,
		0.5 + (rng.randf() - 0.5) * 0.5 * grid_chaos,
		(rng.randf() - 0.5) * deg_to_rad(30.0) * grid_chaos)
	for h in halves:
		subdivide(h, min_area, grid_chaos, size_chaos, empty_prob, rng, out, depth + 1)


## ── SPLIT A TOWN INTO WARDS ──────────────────────────────────────────────────
##
## The same cut, one scale up and with a wide street for a gap. Watabou grows a
## Voronoi mesh for this; recursive splitting of the boundary reaches the same
## place — irregular polygons that tile the town with streets between them — with
## one primitive instead of two, and `Geometry2D.triangulate_delaunay` returns
## only triangle indices, so a Voronoi would have to be derived by hand anyway.
static func wards(boundary: PackedVector2Array, want: int,
		rng: RandomNumberGenerator) -> Array:
	var open: Array = [boundary]
	while open.size() < want:
		# Always split the biggest remaining ward, or the recursion eats one
		# corner of the town and leaves the rest as a single slab.
		var big := 0
		for i in open.size():
			if area(open[i]) > area(open[big]):
				big = i
		var poly: PackedVector2Array = open[big]
		var halves := cut(poly, MAIN_STREET, 0.5 + (rng.randf() - 0.5) * 0.34,
			(rng.randf() - 0.5) * deg_to_rad(34.0))
		if halves.size() < 2:
			break
		open.remove_at(big)
		for h in halves:
			open.append(h)
	return open

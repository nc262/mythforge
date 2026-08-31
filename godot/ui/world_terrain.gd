class_name WorldTerrain extends RefCounted
## The world's GROUND, as data — generated before anything is drawn, and the one
## source of truth for where land, water and high country are.
##
## ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
## The chart was an SDXL painting, and everything that needed to know about
## terrain read it back out of the PIXELS: `world_map._ensure_land` sampled the
## plate to build a road-cost grid, calling blue "water" and dark "steep".
##
## Measured 2026-08-26, on the six shipped plates:
##
##   world        cells over 1.5x cost   water found   median road detour
##   everyday            27.2 %             23.5 %          1.07x
##   embervale           39.4 %              4.8 %          1.10x
##   neonspire           73.2 %              0.2 %          1.20x  (max 1.80x)
##   brasshaven           7.6 %              0.0 %            --
##
## Neon Spire's prompt asks for "light-filled canals" and the reader found 0.2 %
## water, while classifying 73 % of a flat city as mountain — it was reading
## night-time shadow as relief and neon strips as rivers. Brasshaven asks for
## canals and found none at all. Three of the twenty hand-authored pins sat in
## open water: `Your Apartment` at wet=1.00, `Riverside Park` 0.88, embervale's
## `The Old Chapel` 0.98.
##
## The deeper fault is that the plates are not maps. They are oblique landscape
## illustrations WITH A HORIZON — Corp Plaza at y=19 is pinned above the ground
## plane, among tower tops. A percentage coordinate cannot address a picture with
## a vanishing point.
##
## No shipped map pipeline works in that direction. Azgaar, mapgen2, Martin
## OLeary, Watabou, Unexplored 2, Dwarf Fortress, Caves of Qud and Paradox all
## run field -> elevation -> water -> settlements scored on the field -> routes
## pathed on the field -> RENDER LAST, read-only. Sampling an ARTISTIC raster to
## recover terrain has no precedent at all; the legitimate cases are greyscale
## heightmaps and ID bitmaps, where the raster IS the data.
##
## AT-4 already said this ("the paper stops claiming positions it cannot honour",
## 8a56197, 13:01). The road router started reading the paper two hours later
## (d8a29eb, 15:04) and the doctrine was never revisited. This is the revisit.
##
## ── WHAT IT DOES NOT DO ──────────────────────────────────────────────────────
## No erosion, no rivers, no plate tectonics. An elevation field and a sea level
## yield land, water, shoal, coast and slope, which is everything the pins and
## the roads actually ask for. Rivers are a separate feature, not a prerequisite.

const W := 96
const H := 64          # 3:2, matching the Atlas rect — the square plate was
                       # stretched 1:1 into 1.58:1 and squashed every world 58 %.

## Ground per family: how much of it is water, how much relief it has, and how
## hard the island mask pulls land away from the frame edge.
##
## A CITY IS NOT A RIVER VALLEY — the lesson PY-26 learned for the prompt, owed
## here too. Cyber and steam worlds are nearly dry and nearly flat, so their cost
## field is almost uniform and roads run near-straight, which is correct: a road
## across a city bends for blocks, not for mountains.
## `grain` is the noise frequency: low makes one broad continent, high breaks the
## land into inlets, headlands and islands. `warp` bends the island mask itself.
##
## BOTH EXIST BECAUSE THE FIRST VERSION HAD NEITHER, and every world came out the
## same rounded blob in concentric bands — Saltmarsh, whose whole identity is
## "drowned coastline and shoals, tidal channels, sandbars", rendered as a solid
## continent, and Fimbulreach, "fjords and frozen inlets", as a circle with a
## snowcap. The radial falloff was simply louder than the noise, so the noise
## could not carve anything. A drowned reach needs fine grain and a soft island
## pull; a megacity needs the opposite.
const GROUND := {
	"fantasy":  {"water": 0.24, "relief": 1.00, "island": 0.85, "grain": 0.032, "warp": 0.26},
	"pirate":   {"water": 0.46, "relief": 0.50, "island": 0.70, "grain": 0.060, "warp": 0.42},
	"norse":    {"water": 0.32, "relief": 1.25, "island": 0.80, "grain": 0.052, "warp": 0.40},
	"steam":    {"water": 0.10, "relief": 0.45, "island": 0.40, "grain": 0.030, "warp": 0.22},
	"cyber":    {"water": 0.07, "relief": 0.35, "island": 0.30, "grain": 0.028, "warp": 0.20},
	"everyday": {"water": 0.14, "relief": 0.30, "island": 0.35, "grain": 0.028, "warp": 0.24},
	# SPACE AND HORROR ARE FORGE-ONLY — no shipped world uses either, which is
	# exactly why this table had six entries and `WorldSkin.FAMILIES` has eight.
	# `Art.CHART_GROUND` already carried all eight; the ground table did not, so a
	# forged space or horror world would have silently drawn fantasy country. That
	# is the "matched by NAME, not position" failure this repo keeps paying for,
	# and it was caught by the self_check row below rather than by reading.
	#
	# A station is islands of structure in vacuum, so the void plays the part of
	# water and the grain is fine enough to break the modules apart — read
	# CHART_GROUND["space"], "station rings and habitat modules, docking spars".
	"space":    {"water": 0.22, "relief": 0.35, "island": 0.45, "grain": 0.052, "warp": 0.38},
	"horror":   {"water": 0.20, "relief": 0.65, "island": 0.55, "grain": 0.044, "warp": 0.36},
}

## ── WHAT EACH FAMILY'S GROUND LOOKS LIKE ─────────────────────────────────────
##
## THIS IS NOT ART DIRECTION, IT IS AGREEMENT. One natural-terrain ramp served
## all eight families, so Neon Spire — "dense city blocks and arterial roads,
## elevated rail, rooftops and light-filled canals", in `Art.CHART_GROUND`'s own
## words — rendered as grass and hills. The renderer contradicted the world's
## stated ground, which is exactly PY-26 ("the chart asked EVERY world for open
## country, so a vertical megacity rendered as a neon river valley") moved out of
## the prompt and into the shader. Same bug, new home.
##
## So each row is read off CHART_GROUND rather than invented. `low`/`high` is the
## ordinary ground, `hill` the raised or denser stuff, `peak` its extreme, and
## `strand` the edge where land meets water — SAND in a wilderness, CONCRETE on a
## waterfront, because a megacity has a quay and not a beach.
const PAPER := {
	"fantasy":  {"deep": "0d1f47", "shallow": "4d7f9e", "strand": "d1c294",
		"low": "4d7042", "high": "75874c", "hill": "78704c", "peak": "f5f5f7"},
	"norse":    {"deep": "0a1730", "shallow": "3f6f8c", "strand": "8f9298",
		"low": "3d5c4a", "high": "5e7358", "hill": "6b6b68", "peak": "fbfcfe"},
	"pirate":   {"deep": "0e2b52", "shallow": "5698ad", "strand": "ded0a0",
		"low": "5b7a45", "high": "86955a", "hill": "84775a", "peak": "e8e6dc"},
	# Brick, soot and rail yards. The "peaks" of a steam city are chimney rows and
	# viaducts, which are pale grey smoke rather than snow.
	"steam":    {"deep": "18202b", "shallow": "3f5666", "strand": "8a8378",
		"low": "6a5a4c", "high": "7d6a58", "hill": "8a7360", "peak": "cfc7bd"},
	# Asphalt and concrete, canals that glow rather than reflect sky, and towers
	# for high ground. Nothing here is green: the prompt does not describe a field.
	"cyber":    {"deep": "071726", "shallow": "1d6f86", "strand": "5c6672",
		"low": "3a4049", "high": "4a515c", "hill": "5b6370", "peak": "b9c6d6"},
	"everyday": {"deep": "1c3a5c", "shallow": "5289b0", "strand": "c4bda6",
		"low": "587a4c", "high": "7e9455", "hill": "7b7460", "peak": "d8d5cf"},
	# A station is structure in vacuum: the "sea" is black, and its shallows are
	# the running lights along a hull.
	"space":    {"deep": "05060c", "shallow": "1b3550", "strand": "6b7280",
		"low": "3c4250", "high": "4d5464", "hill": "606878", "peak": "cdd6e4"},
	"horror":   {"deep": "0b1114", "shallow": "2c4340", "strand": "77705f",
		"low": "3f4a35", "high": "555c3f", "hill": "5a5346", "peak": "b3b0a4"},
}


## How much of this world is BUILT rather than grown — see the `urban` uniform in
## chart_paper.gdshader. Read straight off `Art.CHART_GROUND`: cyber and steam
## describe blocks and districts, everyday describes suburbs and town blocks, a
## station is nothing but structure. Fantasy, norse, pirate and horror describe
## country, and get none.
const URBAN := {
	"cyber": 1.0, "space": 0.92, "steam": 0.85, "everyday": 0.55,
	"fantasy": 0.0, "norse": 0.0, "pirate": 0.0, "horror": 0.0,
}


## Terrain classes, coarse on purpose — these are the words the placement scorer
## and the renderer both speak, so adding one means teaching both.
enum { DEEP, SHOAL, COAST, PLAIN, HILL, PEAK }

## Typed, because an untyped array literal makes every `var n := c + d` in a loop
## uninferrable — which is a PARSE error, and a parse error in a class_name file
## is silent at the call site: the first run of this compiled nothing and the
## probe still printed OK for six worlds.
const N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Mean pin score that ends the seed search early. Not 1.0: a perfect score needs
## every kind on its single favourite class at once, which no real coastline
## offers, so demanding it would just burn all 48 candidates every time.
const GOOD_ENOUGH := 0.72

var world_id := ""
var family := "fantasy"
var seed_used := 0
var elev := PackedFloat32Array()   # 0..1, W*H
var sea := 0.5
## The height thresholds `_classify` used, kept so the RENDERER can shade from a
## smoothly-interpolated height instead of stepping cell to cell. Gameplay still
## asks `klass()`, which is exact and cell-resolution; these only smooth a picture.
var hill_at := INF
var peak_at := INF
var land_band := 0.0001
var _class := PackedByteArray()

static var _cache := {}


## The terrain for a world. Cached: the Atlas, the minimap and the compiler must
## all read the SAME ground, and regenerating per caller would be both slow and a
## chance for them to disagree.
static func for_world(wid: String) -> WorldTerrain:
	if _cache.has(wid):
		return _cache[wid]
	var t := WorldTerrain.new()
	t._build(wid)
	_cache[wid] = t
	return t


static func forget(wid := "") -> void:
	if wid == "":
		_cache.clear()
	else:
		_cache.erase(wid)


func _build(wid: String) -> void:
	world_id = wid
	family = WorldSkin.family_for_id(wid)
	# THE SEED SEARCH READS ONLY THE AUTHORED GAZETTEER, never GameState.places().
	# A GM can charter a new place mid-campaign; if those counted, the ground
	# would re-fit itself around them and the coastline would move under a live
	# save. The gazetteer is fixed at ship time, so this is stable forever.
	var pinned := _authored_pins(wid)
	var base := absi(hash(wid))
	var best := -1.0
	var best_seed := base
	for i in 48:
		var s := base + i * 7919
		_generate(s)
		var sc := _fit(pinned)
		if sc > best:
			best = sc
			best_seed = s
		if sc >= GOOD_ENOUGH:
			break
	_generate(best_seed)
	seed_used = best_seed


## The pins a world SHIPPED with. Only those with an explicit x/y constrain the
## ground; a place with no coordinates has nothing to disagree with, and will be
## placed by score later.
func _authored_pins(wid: String) -> Array:
	var out: Array = []
	for l in Rules.world_locations(wid):
		if l is Dictionary and l.has("x") and l.has("y"):
			out.append({"kind": str(l.get("kind", "")),
				"cell": cell_of(Vector2(float(l["x"]), float(l["y"])))})
	return out


## How well this ground suits the pins already driven into it — the MEAN SCORE,
## not the fraction that merely avoid drowning.
##
## This asked `suits` first, and `suits` is a floor ("is it dry land?") that the
## very first candidate seed clears for every pin. So the search terminated on
## seed 0 every time and never actually searched: Hearthwood Market, a shop,
## came out on a glacier — dry, and absurd. Scoring makes the difference between
## "possible" and "right" visible to the search, which is the only place it can
## act on it.
##
## Trivially 1.0 for a world with no authored coordinates, so a forged world
## takes the first seed and the search costs it nothing.
func _fit(pinned: Array) -> float:
	if pinned.is_empty():
		return 1.0
	var sum := 0.0
	for p in pinned:
		sum += score(str(p["kind"]), p["cell"])
	return sum / float(pinned.size())


func _generate(s: int) -> void:
	var g: Dictionary = GROUND.get(family, GROUND["fantasy"])
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = float(g.get("grain", 0.032))
	# The mask's OWN noise, at a much coarser scale — this is what turns a circle
	# into headlands and bays. Its seed is offset so a world never gets the same
	# field for its height and its outline.
	var wn := FastNoiseLite.new()
	wn.seed = s + 104729
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wn.frequency = 0.020
	var warp := float(g.get("warp", 0.26))
	elev = PackedFloat32Array()
	elev.resize(W * H)
	var lo := INF
	var hi := -INF
	var pull := float(g["island"])
	for y in H:
		for x in W:
			# Radial falloff, so the land is a landmass rather than noise running
			# off all four edges — but WARPED, or every world is a disc.
			var dx := (float(x) / float(W - 1) - 0.5) * 2.0
			var dy := (float(y) / float(H - 1) - 0.5) * 2.0
			var d := sqrt(dx * dx + dy * dy) / sqrt(2.0)
			d = clampf(d + wn.get_noise_2d(float(x), float(y)) * warp, 0.0, 1.4)
			var v := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# Exponent 3.0, not 2.2: the pull should bite at the rim and leave the
			# interior to the noise. At 2.2 it dominated everywhere and the result
			# was concentric bands — green ring, brown ring, white middle.
			v -= pull * pow(d, 3.0)
			elev[y * W + x] = v
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var span := maxf(hi - lo, 0.0001)
	for i in elev.size():
		elev[i] = (elev[i] - lo) / span
	# SEA LEVEL BY QUANTILE, not by a magic constant. Asking for "0.46 of this
	# world is water" and taking the 46th percentile guarantees it; picking a
	# fixed height and hoping gives a different coastline for every seed, which
	# is the same drift that made the pixel reader unreliable.
	var sorted := elev.duplicate()
	sorted.sort()
	sea = sorted[clampi(int(float(g["water"]) * float(sorted.size())), 0, sorted.size() - 1)]
	_classify()


## LAND BANDS BY QUANTILE TOO, and driven by `relief`.
##
## This thresholded the NORMALISED height ("up > 0.72 is a peak"), which quietly
## threw the relief parameter away: every world is normalised to 0..1, so every
## world had the same share of peak and hill no matter what family it was. Neon
## Spire — a megacity, relief 0.35 — came out with snowfields and mountain lakes,
## and Brasshaven charged road cost over 50 % of a flat industrial city.
##
## The sea level two functions up already had this right ("by quantile, not by a
## magic constant") and the lesson was not carried one layer down. It is the same
## fix: decide what FRACTION of the land is high country, from the family, then
## take that quantile. A world with no relief now has no peaks at all rather than
## a token few, because `peak_share` goes to zero below 0.45.
func _classify() -> void:
	var g: Dictionary = GROUND.get(family, GROUND["fantasy"])
	var relief := float(g["relief"])
	var land: PackedFloat32Array = PackedFloat32Array()
	for i in elev.size():
		if elev[i] > sea:
			land.append(elev[i])
	land.sort()
	var peak_share := clampf(0.30 * pow(maxf(relief - 0.45, 0.0), 1.4), 0.0, 0.30)
	var hill_share := clampf(0.40 * relief, 0.0, 0.45)
	peak_at = _quantile(land, 1.0 - peak_share) if peak_share > 0.001 else INF
	hill_at = _quantile(land, 1.0 - peak_share - hill_share) if hill_share > 0.001 else INF
	var band := maxf((land[land.size() - 1] if land.size() > 0 else sea) - sea, 0.0001)
	land_band = band
	_class = PackedByteArray()
	_class.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			var e := elev[i]
			if e <= sea:
				# Shoal is the water a ruin can drown in and a quay can stand on:
				# the shallow tenth just below the line.
				_class[i] = SHOAL if e > sea - band * 0.10 else DEEP
				continue
			if _touches_water(x, y):
				_class[i] = COAST
			elif e >= peak_at:
				_class[i] = PEAK
			elif e >= hill_at:
				_class[i] = HILL
			else:
				_class[i] = PLAIN


func _quantile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(q * float(sorted.size())), 0, sorted.size() - 1)]


func _touches_water(x: int, y: int) -> bool:
	for d in N4:
		var nx := x + d.x
		var ny := y + d.y
		if nx < 0 or ny < 0 or nx >= W or ny >= H:
			continue
		if elev[ny * W + nx] <= sea:
			return true
	return false


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


## A percentage position — the coordinate space every place already uses — to a cell.
func cell_of(pct: Vector2) -> Vector2i:
	return Vector2i(clampi(int(pct.x / 100.0 * W), 0, W - 1),
		clampi(int(pct.y / 100.0 * H), 0, H - 1))


## And back: the centre of the cell, in percent.
func pct_of(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) / float(W) * 100.0,
		(float(c.y) + 0.5) / float(H) * 100.0)


func klass(c: Vector2i) -> int:
	return _class[c.y * W + c.x] if in_bounds(c) else DEEP


func height(c: Vector2i) -> float:
	return elev[c.y * W + c.x] if in_bounds(c) else 0.0


func is_water(c: Vector2i) -> bool:
	return klass(c) == DEEP or klass(c) == SHOAL


## Steepness: the sharpest step to a 4-neighbour.
func slope(c: Vector2i) -> float:
	if not in_bounds(c):
		return 0.0
	var e := height(c)
	var m := 0.0
	for d in N4:
		var n := c + d
		if in_bounds(n):
			m = maxf(m, absf(height(n) - e))
	return m


## What a road pays to cross this cell.
##
## NOTHING IS IMPASSABLE, deliberately — the same rule the pixel reader had, and
## it was right: a road must always be drawable between two places the engine
## says you can travel between, or a pin ends up with no line to it and reads as
## a bug. Deep water is dear enough that a route takes any land it can find.
func cost(c: Vector2i) -> float:
	var relief := float(GROUND.get(family, GROUND["fantasy"])["relief"])
	match klass(c):
		DEEP:
			return 15.0
		SHOAL:
			return 6.0
		HILL:
			return 1.0 + 0.55 * relief
		PEAK:
			return 1.0 + 3.0 * relief
		_:
			return 1.0


## What a road pays, with the ground's own unevenness in it.
##
## `cost()` is the honest terrain cost and stays pure — self_check compares it
## across worlds, and a comparison against a jittered number is a comparison
## against noise. This is what PATHFINDING uses.
##
## WHY THE JITTER. On near-uniform ground A* has no reason to bend, so it returns
## the axis-aligned staircase that is genuinely cheapest — and Saltmarsh, a
## drowned reach at relief 0.50 where every land cell costs within 28 % of every
## other, drew a dead-straight ruler line clean across the marsh. It looked like
## an artefact because it WAS one: a road drawn by a cost field with nothing to
## say. Real ground is never uniform, so neither is this; the jitter is hashed
## per cell, so a route is still identical every time it is drawn.
##
## It is deliberately small. At +/-12 % it breaks ties and nothing more — a road
## will still cross a hill rather than detour around a continent, because a hill
## costs far more than 12 % over a plain.
func route_cost(c: Vector2i) -> float:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ absi(hash(world_id))
	return cost(c) * (0.88 + 0.24 * float(absi(h) % 1000) / 1000.0)


## Does this kind of place belong on this cell?
##
## Deliberately permissive — this is the ASSERTION the probe checks and the floor
## a placement search must clear, so it should catch "the inn is in the open sea"
## and stay quiet about matters of taste. A ruin may be sunken and wilds may be
## open water (Fimbulreach's `The White Fjord` is exactly that); an inn does not
## float.
func suits(kind: String, c: Vector2i) -> bool:
	var k := klass(c)
	match kind:
		"wilds":
			return true                          # the sea is wild too
		"ruin":
			return k != DEEP                     # drowned, not abyssal
		_:
			return k != DEEP and k != SHOAL      # people live on land


## How WELL it belongs — the placement search maximises this. `suits` is the
## floor; this is the preference.
func score(kind: String, c: Vector2i) -> float:
	if not suits(kind, c):
		return -1.0
	var k := klass(c)
	var s := 0.0
	match kind:
		"tavern", "shop", "home", "settlement":
			# People settle where the land is kind and a boat or a road can reach.
			s = {COAST: 1.00, PLAIN: 0.85, HILL: 0.45, PEAK: 0.05}.get(k, 0.0)
			s -= slope(c) * 2.0
		"landmark":
			s = {PEAK: 1.00, HILL: 0.85, COAST: 0.60, PLAIN: 0.35}.get(k, 0.0)
		"ruin":
			s = {HILL: 0.90, PEAK: 0.75, SHOAL: 0.70, COAST: 0.55, PLAIN: 0.40}.get(k, 0.0)
		"wilds":
			s = {PEAK: 1.00, HILL: 0.80, DEEP: 0.70, SHOAL: 0.55, PLAIN: 0.30, COAST: 0.25}.get(k, 0.0)
		_:
			s = {PLAIN: 0.80, COAST: 0.80, HILL: 0.55, PEAK: 0.30}.get(k, 0.1)
	return maxf(s, 0.0)


## How much of the world is water — the number the pixel reader was trying to
## guess and got wrong by 20 points on two worlds.
func water_fraction() -> float:
	var n := 0
	for i in _class.size():
		if _class[i] == DEEP or _class[i] == SHOAL:
			n += 1
	return float(n) / float(_class.size())


## ── THE PAPER ────────────────────────────────────────────────────────────────
##
## The chart, rendered FROM the ground rather than painted beside it. This is the
## half that makes the rest honest: the pins, the roads and the picture are three
## views of one field, so the paper cannot disagree with them — which is what
## AT-4 asked for and could not have while the picture was generated separately.
##
## DRAWN BY A SHADER, not baked into an image. The first version interpolated
## this 96x64 grid up to a 384x256 plate and drew it across ~680 px, zoomable to
## 2.6x — roughly 1768 screen pixels from 96 samples of field. Interpolation
## smooths; it cannot invent. The result was guaranteed blurry at any plate size,
## and a bigger bake would have cost seconds of main thread for the same absence
## of detail.
##
## `height_field()` hands the shader the grid as a texture and it stays the one
## source of truth; the shader adds detail octaves that NOTHING gameplay-facing
## reads. Re-deriving the terrain in GLSL would have been two versions of one
## truth, which is the drift this repo has paid for six times over.
const SHADER := preload("res://ui/chart_paper.gdshader")

var _field: ImageTexture = null


## The elevation grid as a single-channel texture. Cached — the Atlas and the
## minimap share one, as they share one terrain.
func height_field() -> ImageTexture:
	if _field != null:
		return _field
	var buf := PackedByteArray()
	buf.resize(W * H * 4)
	var i := 0
	for e in elev:
		# FORMAT_RF wants raw floats; a byte channel would quantise the field to
		# 256 steps, and the contour lines and coastline stroke both read
		# gradients — banding would show as terracing across every slope.
		buf.encode_float(i, e)
		i += 4
	_field = ImageTexture.create_from_image(
		Image.create_from_data(W, H, false, Image.FORMAT_RF, buf))
	return _field


## A material ready to draw the chart with. Built per world; the caller owns it.
func paper_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var g: Dictionary = GROUND.get(family, GROUND["fantasy"])
	m.set_shader_parameter("height_tex", height_field())
	m.set_shader_parameter("sea_level", sea)
	m.set_shader_parameter("land_band", land_band)
	# INF does not survive the trip to a shader uniform. A world with no peaks
	# has `peak_at = INF`, and passing that gives a NaN comparison in GLSL that
	# renders as a black plate — so a world with no high country is told its
	# peaks begin above the highest ground there is.
	m.set_shader_parameter("hill_at", hill_at if hill_at < INF else 2.0)
	m.set_shader_parameter("peak_at", peak_at if peak_at < INF else 2.0)
	m.set_shader_parameter("relief", float(g["relief"]))
	# LESS INVENTED RELIEF WHERE THE GROUND IS BUILT ON. The detail octaves give a
	# wilderness its ridges and crinkled coast; under city blocks they read as a
	# wave texture competing with the streets, and two line systems at similar
	# weight make hatching rather than either one.
	m.set_shader_parameter("detail", 1.0 - 0.65 * float(URBAN.get(family, 0.0)))
	m.set_shader_parameter("urban", float(URBAN.get(family, 0.0)))
	m.set_shader_parameter("accent", Ui.c("amethyst"))
	var pap: Dictionary = PAPER.get(family, PAPER["fantasy"])
	for role in ["deep", "shallow", "strand", "low", "high", "hill", "peak"]:
		m.set_shader_parameter("c_" + role, Color(str(pap[role])))
	return m


## Height at a percentage position, interpolated between cells. `height()` steps
## cell to cell, which is right for gameplay and looks like a staircase.
func height_at_pct(pct: Vector2) -> float:
	var fx := clampf(pct.x / 100.0 * float(W) - 0.5, 0.0, float(W - 1))
	var fy := clampf(pct.y / 100.0 * float(H) - 0.5, 0.0, float(H - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, W - 1)
	var y1 := mini(y0 + 1, H - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top: float = lerpf(elev[y0 * W + x0], elev[y0 * W + x1], tx)
	var bot: float = lerpf(elev[y1 * W + x0], elev[y1 * W + x1], tx)
	return lerpf(top, bot, ty)

class_name LocalMap extends RefCounted
## AT-5 — THE TIER BELOW A PIN: a town's streets, a ruin's rooms.
##
## ── WHY THIS IS POSSIBLE NOW AND WAS NOT BEFORE ──────────────────────────────
## AT-3 cut realm -> city -> street and was RIGHT to: "a place is a POINT with a
## region and a kind, and there is no such thing as a street, a city interior, or
## anything inside a place at all. Building a street tier would mean inventing the
## data for it and then painting it, which is a content project, not a map
## feature."
##
## Both halves of that died with the painted chart. The data is GENERATED, seeded
## from the place, exactly as `WorldTerrain` is; and there is nothing to paint,
## because the chart is rendered. What is left is a generator and a screen.
##
## And it inherits its SITE from the world terrain — `WorldTerrain.klass()` at the
## cell the place stands on. A town on a COAST cell gets a quay; one on a PEAK
## gets a stair and a citadel yard. So the local map cannot contradict the world
## map about what kind of ground the place is built on, which is the dividend of
## having inverted the pipeline and is unavailable to any authored approach.
##
## ── THE LOCAL MAP IS THE WORLD MAP RECURSED ──────────────────────────────────
## Nodes and edges and fog, one scale down. A room is a NODE YOU CLICK, not a
## token you walk: this game travels between discrete points and the GM narrates
## arrival, so continuous movement would mean inventing input, collision and
## encounter triggers, and would contradict every other screen.
##
## ── FOG: IGNORANCE, NOT DISTANCE ─────────────────────────────────────────────
## A SETTLED place is never fogged. People live there, there is signage, and you
## can ask — fogging a friendly town means walking it to reveal streets, which is
## busywork wearing exploration's clothes. Research found no mainstream RPG that
## fogs a settlement interior; the entire fog-of-war literature is about
## wilderness.
##
## An UNSETTLED place is fogged, because nobody is there to tell you. Reveal is
## room-granularity (Darkest Dungeon's model, and more right here than there,
## since there is no partial movement through a room at all) and PERMANENT —
## re-shrouding exists to hide live moving units from an opponent, and there is
## no adversary here and nothing that moves.
##
## Crucially the fog leaves a CHOICE: a room's exits are scouted when you stand
## in it. Reveal only where you are and exploring is a random walk; reveal the
## neighbours and the player picks between visible options under partial
## information, which is what makes it a decision. Darkest Dungeon's scouting is
## the same idea.

## The kinds somebody lives in. Everything else is a site, not a settlement.
const SETTLED_KINDS := ["settlement", "tavern", "shop", "home"]

## Typed, for the same reason `WorldTerrain.N4` is: an untyped array literal in a
## `for` makes every `var x := ...` inside it uninferrable, which is a PARSE
## error — and a parse error in a class_name file is silent at the call site.
## Second time this exact shape has bitten in this work.
const SIDES: Array[float] = [-1.0, 1.0]

var place := ""
var world_id := ""
var kind := ""
var settled := false
var site := WorldTerrain.PLAIN     # the world terrain class under this place
var nodes: Array = []              # {name, role, x, y}  — x/y percent of the plate
var edges: Array = []              # [i, j] into `nodes`

## ── THE GEOMETRY, not just the graph ─────────────────────────────────────────
## Nodes and edges are what the game reasons about; these are what it LOOKS like.
## A town drawn as six dots joined by lines is a diagram of a town. Streets with
## buildings along them, a plaza, a shore where the sea actually is — that is a
## map of one. Same split as the world chart: the field decides, the drawing
## shows, and nothing here is ever read back.
var streets: Array = []            # PackedVector2Array, percent space
var buildings: Array = []          # {"r": Rect2, "big": bool}
var rooms: Array = []              # unsettled: one Rect2 per node, same index
var water_dir := Vector2.ZERO      # toward the sea, or ZERO if landlocked
var water_at := 0.0                # how far across the plate the shore sits
var bounds := PackedVector2Array() # the built-up edge, wall or field boundary
var walled := false                # a settlement has a wall; a hamlet has hedges

static var _cache := {}


static func for_place(wid: String, place_name: String, place_kind: String) -> LocalMap:
	var key := "%s|%s" % [wid, place_name]
	if _cache.has(key):
		return _cache[key]
	var m := LocalMap.new()
	m._build(wid, place_name, place_kind)
	_cache[key] = m
	return m


static func forget(key := "") -> void:
	if key == "":
		_cache.clear()
	else:
		_cache.erase(key)


func _build(wid: String, place_name: String, place_kind: String) -> void:
	world_id = wid
	place = place_name
	kind = place_kind
	settled = SETTLED_KINDS.has(place_kind)
	# THE SITE COMES FROM THE WORLD MAP. Not a re-roll, not a second opinion —
	# the same field the pin was placed on and the roads were routed over.
	var ground := WorldTerrain.for_world(wid)
	for l in GameState.places():
		if l is Dictionary and str(l.get("name", "")) == place_name \
				and l.has("x") and l.has("y"):
			site = ground.klass(ground.cell_of(Vector2(float(l["x"]), float(l["y"]))))
			break
	# WHICH WAY THE SEA IS. Not a coin flip: the nearest water cell on the WORLD
	# map, so a town's shore faces the same direction the chart says the sea lies.
	# Free, because the field is already there, and impossible for any generator
	# that does not share one.
	if ground_is_wet(ground):
		var c := _cell_of_place(ground)
		var best := 1e9
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				var n := c + Vector2i(dx, dy)
				if not ground.in_bounds(n) or not ground.is_water(n):
					continue
				var d := Vector2(dx, dy).length()
				if d < best and d > 0.01:
					best = d
					water_dir = Vector2(dx, dy).normalized()
		if water_dir != Vector2.ZERO:
			# HOW FAR OUT THE SHORE SITS, in percent from the middle of the plate.
			# The first version fed this through `(1 - water_at) * 68`, which put
			# the waterline past the edge of the map for a town standing ON a
			# coast cell — Gallows Quay's harbour was a sliver in the top margin.
			# Distance from centre directly, so a town beside the sea has the sea
			# beside it.
			water_at = clampf(lerpf(19.0, 46.0, float(best) / 11.0), 19.0, 46.0)
	var rng := RandomNumberGenerator.new()
	# Seeded from the world AND the name, so two towns called Millbrook in
	# different worlds are different towns, and the same one is itself forever.
	rng.seed = absi(hash("%s|%s" % [wid, place_name]))
	if settled:
		_build_town(rng)
		_plan_town(rng)
	else:
		_build_site(rng)
		_plan_rooms(rng)


## Is there water anywhere near this place on the world map?
func ground_is_wet(ground: WorldTerrain) -> bool:
	var c := _cell_of_place(ground)
	for dy in range(-11, 12):
		for dx in range(-11, 12):
			var n := c + Vector2i(dx, dy)
			if ground.in_bounds(n) and ground.is_water(n):
				return true
	return false


func _cell_of_place(ground: WorldTerrain) -> Vector2i:
	for l in GameState.places():
		if l is Dictionary and str(l.get("name", "")) == place and l.has("x") and l.has("y"):
			return ground.cell_of(Vector2(float(l["x"]), float(l["y"])))
	return Vector2i(WorldTerrain.W / 2, WorldTerrain.H / 2)


## ── THE TOWN PLAN: BLOCKS AND LOTS, NOT BOXES ON A LINE ──────────────────────
##
## The first version scattered ~35 buildings along street centrelines and it
## looked like a village diagram, because that is what it was. A town map reads
## as a town because the space BETWEEN the streets is full: blocks subdivided
## into lots, and a building on nearly every lot. That is how Watabou's city
## generator and every hand-drawn town map are built, after Parish & Muller —
## streets partition, lots fill, and density is what sells it.
##
## So: recursive rectangle subdivision over the built-up area, in a frame rotated
## per town so the grain is not always north-south, minus anything that falls on
## a street, in the water, or outside the walls.
## Percent of the plate. A house on a town map is SMALL — one to two percent of
## the width. The first version used 3.4 with a depth of 6, and since each pass
## splits only the long axis that is barely three splits per axis: "lots" came
## out 15 units across and the town rendered as a dozen beige slabs. The depth
## has to be about 2*log2(span/LOT_MIN) or the recursion runs out before the
## rectangles are anywhere near house-sized.
const LOT_MIN := 1.7
const LOT_DEPTH := 12


func _plan_town(rng: RandomNumberGenerator) -> void:
	for e in edges:
		var a := Vector2(float(nodes[int(e[0])]["x"]), float(nodes[int(e[0])]["y"]))
		var b := Vector2(float(nodes[int(e[1])]["x"]), float(nodes[int(e[1])]["y"]))
		var mid := a.lerp(b, rng.randf_range(0.4, 0.6)) 			+ (b - a).normalized().orthogonal() * rng.randf_range(-4.0, 4.0)
		streets.append(PackedVector2Array([a, mid, b]))

	# The built-up edge: an irregular ring round the square, cut where the water
	# is. Drawn as the wall for a settlement and as the field boundary otherwise.
	var lobes := rng.randf_range(0.0, TAU)
	for k in 34:
		var ang := float(k) / 34.0 * TAU
		# COMPACT. At 34 the built-up area was two thirds of the plate and the
		# houses inside it read as a scattering in a meadow. A town is DENSE — a
		# small footprint packed full — and density is what makes it a town
		# rather than a hamlet spread thin.
		var r := 25.0 + sin(ang * 3.0 + lobes) * 4.6 + sin(ang * 5.0 + lobes * 2.0) * 2.8 			+ sin(ang * 8.0 + lobes * 0.7) * 1.5
		var at := Vector2(50, 50) + Vector2(cos(ang), sin(ang)) * r
		if _in_water(at):
			at = Vector2(50, 50) + Vector2(cos(ang), sin(ang)) * _shore_reach(ang)
		bounds.append(at)
	walled = kind == "settlement"
	# LANES OFF THE MAIN ROADS. Six streets do not make blocks — they make a star,
	# and a star with houses beside it is a village. The lanes are what turn the
	# space between roads into BLOCKS, which is the unit a town is actually built
	# out of, and they cost one loop.
	var spokes := streets.size()
	for si in spokes:
		var st: PackedVector2Array = streets[si]
		var a0: Vector2 = st[0]
		var b0: Vector2 = st[st.size() - 1]
		var run := a0.distance_to(b0)
		if run < 12.0:
			continue
		var dir := (b0 - a0) / run
		var nrm := dir.orthogonal()
		for _k in rng.randi_range(1, 3):
			var t := rng.randf_range(0.25, 0.8)
			var root := a0 + dir * run * t
			var reach := rng.randf_range(7.0, 15.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			var tip := root + nrm * reach
			# CLIPPED TO THE TOWN. Lanes ran straight out through the wall and
			# off into open country, which reads as a bug rather than a road —
			# a lane is a way between blocks, and outside the built-up edge
			# there are no blocks for it to be between.
			if _in_water(tip) or not _inside_bounds(tip) or not _inside_bounds(root):
				continue
			streets.append(PackedVector2Array([root, root.lerp(tip, 0.55)
				+ dir * rng.randf_range(-2.0, 2.0), tip]))


	# LOTS. Subdivide, then keep what is genuinely buildable.
	var grain := rng.randf_range(0.0, PI)
	var lots: Array = []
	_subdivide(Rect2(Vector2(6, 6), Vector2(88, 88)), LOT_DEPTH, rng, lots)
	for lot in lots:
		var r: Rect2 = lot
		var c := r.position + r.size * 0.5
		var cw := _rot(c, grain)
		if _in_water(cw) or not _inside_bounds(cw):
			continue
		if _near_street(cw, 1.9):
			continue                       # the street itself, and its verges
		# Density falls off from the square: a core of packed frontage, then
		# looser plots toward the edge, which is what a town actually is.
		var away := cw.distance_to(Vector2(50, 50)) / 25.0
		if rng.randf() < away * 0.22:
			continue
		var inset := rng.randf_range(0.35, 0.8)
		var size2 := (r.size - Vector2(inset, inset) * 2.0)
		if size2.x < 1.0 or size2.y < 1.0:
			continue
		buildings.append({"at": cw, "size": size2, "ang": grain,
			"big": r.size.x * r.size.y > 9.0})


## Split a rectangle down the long axis until the pieces are lot-sized. The
## split is off-centre, or every lot on the map is the same size and the result
## is graph paper again — the same fault the city shader had.
func _subdivide(r: Rect2, depth: int, rng: RandomNumberGenerator, out: Array) -> void:
	var long_side: float = maxf(r.size.x, r.size.y)
	if depth <= 0 or long_side < LOT_MIN * 2.0:
		if r.size.x >= LOT_MIN * 0.6 and r.size.y >= LOT_MIN * 0.6:
			out.append(r)
		return
	var t := rng.randf_range(0.36, 0.64)
	if r.size.x >= r.size.y:
		var w := r.size.x * t
		_subdivide(Rect2(r.position, Vector2(w, r.size.y)), depth - 1, rng, out)
		_subdivide(Rect2(r.position + Vector2(w, 0), Vector2(r.size.x - w, r.size.y)), depth - 1, rng, out)
	else:
		var h := r.size.y * t
		_subdivide(Rect2(r.position, Vector2(r.size.x, h)), depth - 1, rng, out)
		_subdivide(Rect2(r.position + Vector2(0, h), Vector2(r.size.x, r.size.y - h)), depth - 1, rng, out)


func _rot(p: Vector2, a: float) -> Vector2:
	var d := p - Vector2(50, 50)
	return Vector2(50, 50) + Vector2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a))


## How far the land reaches on this bearing before the water starts.
func _shore_reach(ang: float) -> float:
	var d := Vector2(cos(ang), sin(ang))
	for step in 34:
		var r := 34.0 - float(step)
		if r < 6.0:
			return 6.0
		if not _in_water(Vector2(50, 50) + d * r):
			return r - 1.2
	return 6.0


func _inside_bounds(p: Vector2) -> bool:
	if bounds.is_empty():
		return true
	var d := (p - Vector2(50, 50))
	var ang := fposmod(d.angle(), TAU)
	var idx := int(ang / TAU * float(bounds.size())) % bounds.size()
	return d.length() <= (bounds[idx] - Vector2(50, 50)).length()


func _near_street(p: Vector2, how_near: float) -> bool:
	for st in streets:
		for i in range(st.size() - 1):
			var a: Vector2 = st[i]
			var b: Vector2 = st[i + 1]
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < how_near:
				return true
	return false


## Is this point out past the shore? The water sits as a half-plane in the
## direction the world map says the sea is, so "seaward of the line" is the whole
## test and it agrees with the chart by construction.
func _in_water(p: Vector2) -> bool:
	if water_dir == Vector2.ZERO:
		return false
	return (p - Vector2(50, 50)).dot(water_dir) > water_at


## ── ROOMS ────────────────────────────────────────────────────────────────────
## A dungeon node becomes a ROOM with walls, sized by what it is: a vault is
## worth more floor than a choked passage. Corridors are the edges, drawn thin.
func _plan_rooms(rng: RandomNumberGenerator) -> void:
	for n in nodes:
		var role := str(n.get("role", ""))
		var w := 9.0
		var h := 7.0
		match role:
			"entry":
				w = 8.0
				h = 6.0
			"vault":
				w = rng.randf_range(15.0, 20.0)
				h = rng.randf_range(11.0, 14.0)
			"side":
				w = rng.randf_range(6.0, 9.0)
				h = rng.randf_range(5.0, 7.0)
			_:
				w = rng.randf_range(10.0, 15.0)
				h = rng.randf_range(8.0, 11.0)
		rooms.append(Rect2(Vector2(float(n["x"]), float(n["y"])) - Vector2(w, h) * 0.5,
			Vector2(w, h)))


## ── A TOWN ───────────────────────────────────────────────────────────────────
## A square in the middle, a ring of buildings round it, and streets joining them
## to the square rather than to each other — which is what a small settlement
## actually is, and it guarantees the graph is connected without a spanning tree.
func _build_town(rng: RandomNumberGenerator) -> void:
	var flavor: Dictionary = WorldSkin.skin_for_id(world_id).get("flavor", {})
	var urban := str(flavor.get("world", "")).contains("cyber") \
		or str(flavor.get("world", "")).contains("steam")
	_add("The %s" % ("Plaza" if urban else "Market Square"), "square", 50.0, 50.0)
	var ring: Array = []
	# The inn is the anchor of a Mythforge settlement — `tavern` is a KIND and
	# every town has somewhere to sit down.
	ring.append(["inn", "The %s" % ("Noodle Bar" if urban else "Common Room")])
	ring.append(["shop", "The %s" % ("Stall Row" if urban else "Trade Row")])
	ring.append(["hall", "The %s" % ("Admin Block" if urban else "Moot Hall")])
	ring.append(["homes", "The %s" % ("Stacks" if urban else "Cottages")])
	# THE SITE DECIDES THE FIFTH. This is the whole point of inheriting from the
	# world terrain: a coastal town has a quay because the CHART says it stands
	# on a coast, and the player can see that it does.
	match site:
		WorldTerrain.COAST:
			ring.append(["quay", "The %s" % ("Docks" if urban else "Quay")])
		WorldTerrain.PEAK, WorldTerrain.HILL:
			ring.append(["gate", "The %s" % ("Upper Terrace" if urban else "High Gate")])
		WorldTerrain.SHOAL:
			ring.append(["quay", "The Stilts"])
		_:
			ring.append(["gate", "The %s" % ("Checkpoint" if urban else "Town Gate")])
	for i in ring.size():
		var ang := (float(i) / float(ring.size())) * TAU + rng.randf_range(-0.22, 0.22)
		var r := rng.randf_range(24.0, 33.0)
		var at := Vector2(50.0, 50.0) + Vector2(cos(ang), sin(ang)) * r
		_add(str(ring[i][1]), str(ring[i][0]), at.x, at.y)
		edges.append([0, nodes.size() - 1])
	# One street round the rim, so the town is a place rather than a star. Real
	# towns have a way from the inn to the quay that does not cross the square.
	#
	# NOT ACROSS THE HARBOUR. The rim joins consecutive ring buildings, and where
	# the ring passes the shore that segment ran over open water — a road drawn
	# across a bay, which is exactly the thing the world map's router was rebuilt
	# to stop doing. The spokes to the square are untouched, so every building
	# stays reachable however many rim links this drops.
	for i in range(1, nodes.size() - 1):
		if rng.randf() >= 0.55:
			continue
		var a := Vector2(float(nodes[i]["x"]), float(nodes[i]["y"]))
		var b := Vector2(float(nodes[i + 1]["x"]), float(nodes[i + 1]["y"]))
		if _in_water(a.lerp(b, 0.5)) or _in_water(a.lerp(b, 0.25)) or _in_water(a.lerp(b, 0.75)):
			continue
		edges.append([i, i + 1])


## ── A SITE NOBODY LIVES IN ───────────────────────────────────────────────────
## A spine inward from the way in, with branches — which is what a barrow, a
## flooded fort or a mine reads as, and it means every room has a route back.
func _build_site(rng: RandomNumberGenerator) -> void:
	var deep := str(kind) == "ruin"
	_add("The Way In", "entry", 50.0, 88.0)
	var n := rng.randi_range(4, 6)
	var y := 88.0
	var spine: Array[int] = [0]
	for i in n:
		y -= rng.randf_range(11.0, 16.0)
		var x := clampf(50.0 + rng.randf_range(-16.0, 16.0), 16.0, 84.0)
		_add(_site_name(i, n, deep, rng), "chamber" if i < n - 1 else "vault", x, y)
		edges.append([spine[spine.size() - 1], nodes.size() - 1])
		spine.append(nodes.size() - 1)
	# Branches: a dead end or two, so a choice at a junction can be wrong. A
	# corridor with no wrong turning is a corridor, not a dungeon.
	for i in range(1, spine.size() - 1):
		if rng.randf() < 0.45:
			var bx := clampf(nodes[spine[i]]["x"] + rng.randf_range(-30.0, 30.0), 12.0, 88.0)
			var by := clampf(nodes[spine[i]]["y"] + rng.randf_range(-8.0, 8.0), 10.0, 90.0)
			_add(_side_name(rng), "side", bx, by)
			edges.append([spine[i], nodes.size() - 1])


func _site_name(i: int, n: int, deep: bool, rng: RandomNumberGenerator) -> String:
	if i == n - 1:
		return "The Deep Vault" if deep else "The Far Chamber"
	var a := ["The Fallen Hall", "The Flooded Stair", "The Ash Gallery", "The Broken Arch",
		"The Silent Rows", "The Weeping Wall", "The Cold Cells"]
	return str(a[rng.randi_range(0, a.size() - 1)])


func _side_name(rng: RandomNumberGenerator) -> String:
	var a := ["A Choked Passage", "A Collapsed Room", "An Old Storeroom", "A Dry Cistern"]
	return str(a[rng.randi_range(0, a.size() - 1)])


func _add(nm: String, role: String, x: float, y: float) -> void:
	# NAMES MUST BE UNIQUE inside one map: the fog lists, like the world's, are
	# lists of NAMES, so two rooms sharing one would reveal together.
	var base := nm
	var n := 2
	while _has_name(nm):
		nm = "%s (%d)" % [base, n]
		n += 1
	nodes.append({"name": nm, "role": role,
		"x": clampf(x, 8.0, 92.0), "y": clampf(y, 8.0, 92.0)})


func _has_name(nm: String) -> bool:
	for e in nodes:
		if e is Dictionary and str(e.get("name", "")) == nm:
			return true
	return false


## The rooms this node opens onto — the scouting rule's raw material.
func exits_of(idx: int) -> Array[int]:
	var out: Array[int] = []
	for e in edges:
		if int(e[0]) == idx and not out.has(int(e[1])):
			out.append(int(e[1]))
		elif int(e[1]) == idx and not out.has(int(e[0])):
			out.append(int(e[0]))
	return out


func index_of(nm: String) -> int:
	for i in nodes.size():
		if str(nodes[i].get("name", "")) == nm:
			return i
	return -1


## UNKNOWN / HEARD / VISITED, the same three the world map uses one scale up.
##
## A settled place has no unknown: everything is at least seen from the street.
## An unsettled one reveals the room you stand in, and SCOUTS the rooms it opens
## onto — which is what keeps a choice in front of the player instead of a
## coin flip.
func state_of(idx: int, here_idx: int, walked: Array) -> int:
	if idx < 0 or idx >= nodes.size():
		return 0
	if not settled:
		if idx == here_idx or walked.has(str(nodes[idx].get("name", ""))):
			return 2
		if here_idx >= 0 and exits_of(here_idx).has(idx):
			return 1
		for w in walked:
			var wi := index_of(str(w))
			if wi >= 0 and exits_of(wi).has(idx):
				return 1
		return 0
	return 2 if (idx == here_idx or walked.has(str(nodes[idx].get("name", "")))) else 1

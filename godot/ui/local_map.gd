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
## ── WARDS ARE ADDRESSABLE, and that is what lets the GM touch a town ─────────
## `wards` is the geometry; `ward_of` is the identity. A ward id is its INDEX,
## and the order is fixed by descending area from a seeded generator, so ward 3
## is the same quarter on every visit and in every save. Without that there is
## nothing for a [[site]] tag to attach to — which is what `site_probe`
## measured: the GM could add a place to the chart and the town never moved.
var wards: Array = []              # PackedVector2Array per quarter, percent space
var ward_role: Array = []          # parallel to `wards`: "square", "quay", ...
var ward_name: Array = []          # parallel: what this world calls it
## ── WHAT A QUARTER IS LIKE, in two axes rather than one ──────────────────────
## Blades in the Dark rates a district on separate Wealth and Security dots, and
## that split is the whole point: a single rich/poor dial is the documented
## cliche, because it makes wealth stand in for danger, for law, and for who will
## talk to you, and loses all three. A quarter here can be poor and orderly, or
## moneyed and unwatched. 0-3 each.
var ward_wealth: PackedInt32Array = PackedInt32Array()
var ward_law: PackedInt32Array = PackedInt32Array()
var buildings: Array = []          # {"poly": PackedVector2Array, "big": bool}
var rooms: Array = []              # unsettled: one Rect2 per node, same index
var water_dir := Vector2.ZERO      # toward the sea, or ZERO if landlocked
var water_at := 0.0                # how far across the plate the shore sits
var bounds := PackedVector2Array() # the built-up edge, wall or field boundary
var walled := false                # a settlement has a wall; a hamlet has hedges
## ── HOW BIG IS THIS PLACE ────────────────────────────────────────────────────
## 0 hamlet, 1 village, 2 town, 3 city. Every published system ties what a
## settlement can OFFER to its size — the 2024 DMG gates the top item value on
## it, Pathfinder gates base value, purchase limit and spell tier. A hamlet and
## a capital came out of this generator with byte-identical rosters of six
## wards, which is the shape of that whole problem.
var size_tier := 1
var sites: Array = []              # GM-authored, per ward — see `GameState.town_sites`

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
		# ORDER MATTERS AND IT DID NOT BEFORE. The wall was generated inside
		# `_plan_town`, AFTER the named places were already sitting on a ring at
		# radius 24-33 — while the wall itself ran 25 +/- 9, so 16 to 34. Places
		# landed OUTSIDE their own wall and the streets from the square crossed
		# it, which is the "roads going outside the city" defect exactly.
		#
		# Two numbers in two functions that had to agree and never did. The fix
		# is not to make them match, because matched numbers drift apart again:
		# it is to DERIVE one from the other so there is only one. The boundary
		# is built first, and everything inside is placed at a fraction of the
		# wall's own reach on its own bearing.
		_size_of(rng)
		_plan_bounds(rng)
		_plan_town(rng)
		_plan_sites()
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


## Is this point out past the shore? The water sits as a half-plane in the
## direction the world map says the sea is, so "seaward of the line" is the whole
## test and it agrees with the chart by construction.
func _in_water(p: Vector2) -> bool:
	if water_dir == Vector2.ZERO:
		return false
	return (p - Vector2(50, 50)).dot(water_dir) > water_at


## How far the land reaches on this bearing before the water starts — used to
## pull the built-up edge in where a town runs up against its own harbour.
func _shore_reach(ang: float) -> float:
	var d := Vector2(cos(ang), sin(ang))
	for step in 34:
		var r := 34.0 - float(step)
		if r < 6.0:
			return 6.0
		if not _in_water(Vector2(50, 50) + d * r):
			return r - 1.2
	return 6.0


## ── HOW BIG IS THIS PLACE ────────────────────────────────────────────────────
##
## Seeded, so it is the same on every visit, and biased by KIND: a place the
## world calls a settlement is the one that can be a city, while a tavern or a
## home is a hamlet with a name on it. Every published system ties what a
## settlement can offer to its size, and a generator that gives a crossroads inn
## the same seven quarters as a capital has thrown that away before it starts.
func _size_of(rng: RandomNumberGenerator) -> void:
	var roll := rng.randf()
	match kind:
		"settlement":
			size_tier = 1 if roll < 0.2 else (2 if roll < 0.7 else 3)
		"shop":
			size_tier = 0 if roll < 0.3 else 1
		_:
			size_tier = 0 if roll < 0.55 else 1
	# The site can argue for one more: a harbour gathers people, a peak does not.
	if site == WorldTerrain.COAST and size_tier < 3 and rng.randf() < 0.4:
		size_tier += 1


## THE BUILT-UP EDGE, built FIRST because everything else is placed relative to
## it. An irregular ring round the square, pulled in wherever the water is.
##
## COMPACT: at radius 34 the built-up area was two thirds of the plate and the
## houses inside it read as a scattering in a meadow. A town is a small footprint
## packed full, and that density is what makes it a town rather than a hamlet
## spread thin.
func _plan_bounds(rng: RandomNumberGenerator) -> void:
	var lobes := rng.randf_range(0.0, TAU)
	for k in 34:
		var ang := float(k) / 34.0 * TAU
		# FORTY, NOT TWENTY-FIVE. At radius 25 the town was a fifth of the plate
		# and read as a hamlet dropped in a meadow; the plate is square and the
		# sheet is 16:10, so the margin it leaves is the sheet's own, not the
		# town's. Building sizes are ABSOLUTE (2-7 square units), so a town this
		# much larger is not a scaled-up town — it is a finer-grained one with
		# more of them, which is what "smaller blocks" asked for.
		# The lobes swing +/-9.6, so the base must stay under 50 - 9.6 - a margin or
		# the town walks off the bottom of the plate, which it did at 40: 52 units
		# from a centre at 50 is 102 on a plate that ends at 100.
		var r := 38.0 + sin(ang * 3.0 + lobes) * 5.0 + sin(ang * 5.0 + lobes * 2.0) * 3.0 			+ sin(ang * 8.0 + lobes * 0.7) * 1.6
		var at := Vector2(50, 50) + Vector2(cos(ang), sin(ang)) * r
		if _in_water(at):
			at = Vector2(50, 50) + Vector2(cos(ang), sin(ang)) * _shore_reach(ang)
		bounds.append(at)
	# A WALL IS A SIZE QUESTION, NOT A KIND QUESTION. This read
	# `kind == "settlement"` and only one shipped world carries a place of that
	# kind — so five of six towns drew a hairline outline instead of a wall, and
	# the gates and towers that hang off a wall had nothing to attach to.
	# Hamlets do not wall themselves; towns and cities do.
	walled = size_tier >= 2


## How far the built-up edge reaches on a bearing — the ONE number every
## placement inside the town derives from, so nothing can sit outside its own
## wall and no second radius exists to drift away from this one.
func _reach(ang: float) -> float:
	if bounds.is_empty():
		return 25.0
	var idx := int(fposmod(ang, TAU) / TAU * float(bounds.size())) % bounds.size()
	return (bounds[idx] - Vector2(50, 50)).length()


## ── THE TOWN PLAN ────────────────────────────────────────────────────────────
##
## Wards cut out of the boundary, each inset to leave its street, each then
## subdivided into buildings. `TownPlan` holds the geometry; this holds the
## decisions about what kind of town it is.
##
## THE NAMED PLACES ARE WARD CENTRES, which is also how the "roads going outside
## the city" defect dies for good. They used to sit on a ring at radius 24-33
## while the wall ran 16-34, so places landed outside their own wall and the
## streets to them crossed it — two numbers in two functions that had to agree
## and never did. A ward is a piece OF the boundary, so its centre cannot be
## outside the boundary. There is no second number left to drift.
func _plan_town(rng: RandomNumberGenerator) -> void:
	if bounds.size() < 3:
		return
	# SIZE DECIDES HOW MANY QUARTERS. A hamlet is not a small city — it is a
	# place with fewer KINDS of ground in it. Four wards to eleven across the
	# tiers, which is also what decides how many named places a town can hold.
	var want: int = [4, 5, 7, 11][size_tier]
	var quarters := TownPlan.wards(bounds, want, rng)
	# Biggest first, so the named places land in the wards that can hold them and
	# the market square is the heart rather than an off-centre scrap.
	quarters.sort_custom(func(a, b): return TownPlan.area(a) > TownPlan.area(b))
	wards = quarters

	# THE WORLD SUPPLIES THE WORDS, the generator supplies the structure. Ask
	# `WorldSkin` for this family's name for each kind of quarter rather than
	# branching on prose — see the RCA on `WorldSkin.WARD_KEYS`, which this used
	# to be a two-way string match against and which put a Noodle Bar in a
	# steampunk town and identical ward names in a fantasy village and a pirate
	# port.
	var fam := WorldSkin.family_for_id(world_id)
	# What each ward IS, richest and busiest first. The order matters: a ward's
	# kind decides how big its buildings are and how chaotic its streets, which
	# is what makes a town read as having quarters rather than one texture.
	var roles: Array = []
	for key in WorldSkin.CORE_WARDS:
		roles.append([key, "The %s" % WorldSkin.ward_name(fam, key)])
	match site:
		WorldTerrain.COAST, WorldTerrain.SHOAL:
			roles.append(["quay", "The %s" % WorldSkin.ward_name(fam, "quay")])
		WorldTerrain.PEAK, WorldTerrain.HILL:
			roles.append(["gate", "The %s" % WorldSkin.ward_name(fam, "heights")])
		_:
			roles.append(["gate", "The %s" % WorldSkin.ward_name(fam, "gate")])

	# THE QUAY GOES WHERE THE WATER IS. Roles were handed out in area order alone,
	# so Gallows Quay put its Quay on the eastern ward while its sea was to the
	# north — a map that contradicts itself about the one fact the whole place is
	# named for. The site already knows which way the water lies; the ward that
	# leans furthest that way takes the role.
	if water_dir != Vector2.ZERO and roles.size() > 1:
		var far := -INF
		var pick := -1
		for i in quarters.size():
			if i >= roles.size():
				break
			var lean := (TownPlan.centroid(quarters[i]) - Vector2(50, 50)).dot(water_dir)
			if lean > far:
				far = lean
				pick = i
		var water_role := roles.size() - 1     # the site-chosen role is appended last
		if pick >= 0 and pick != water_role and str(roles[water_role][0]) == "quay":
			var tmp: Array = roles[pick]
			roles[pick] = roles[water_role]
			roles[water_role] = tmp

	# ── IDENTITY AND CHARACTER, per ward ─────────────────────────────────────
	# Filled before anything is placed, so a ward id means the same thing to the
	# renderer, to the save file and to the GM.
	ward_role.resize(quarters.size())
	ward_name.resize(quarters.size())
	ward_wealth.resize(quarters.size())
	ward_law.resize(quarters.size())
	# NORMALISED AGAINST THE TOWN, not against a single bearing. `_reach(0.0)` is
	# how far the wall runs due east and nothing more, so using it as the scale
	# made every ward "outer" in a town that happens to be wide — wealth never
	# reached 3 and the market square was as poor as the outskirts.
	var far_out := 0.001
	for q in quarters:
		far_out = maxf(far_out, TownPlan.centroid(q).distance_to(Vector2(50, 50)))
	for i in quarters.size():
		var at_i := TownPlan.centroid(quarters[i])
		var role := str(roles[i][0]) if i < roles.size() else "homes"
		ward_role[i] = role
		if i < roles.size():
			ward_name[i] = str(roles[i][1])
		else:
			# BEYOND THE NAMED ROLES, a quarter is still somewhere. Qualified by
			# its bearing so no two share a name — two wards both called "The
			# Netmakers Row" is a town that cannot be given directions in.
			ward_name[i] = "%s %s" % [_quarter_of(at_i), WorldSkin.ward_name(fam, "homes")]
		# WEALTH falls off from the square, because the centre is where the money
		# is in every town plan anyone has ever drawn. LAW is separate and is NOT
		# a copy of it: the hall and the gate are watched, the quay is where the
		# law is thinnest whatever it costs to live there, and the outskirts are
		# nobody's beat. That independence is the whole reason there are two.
		var d := at_i.distance_to(Vector2(50, 50)) / far_out
		var w := int(round(clampf(3.0 - d * 2.6, 0.0, 3.0)))
		var l := int(round(clampf(2.7 - d * 2.0, 0.0, 3.0)))
		match role:
			"hall", "gate":
				l = mini(l + 1, 3)
			"quay":
				l = maxi(l - 2, 0)          # the docks are where the law is thin
				w = maxi(w - 1, 0)
			"square", "shop":
				w = mini(w + 1, 3)
			"homes":
				w = maxi(w - 1, 0)
		ward_wealth[i] = w
		ward_law[i] = l

	for i in quarters.size():
		var poly: PackedVector2Array = quarters[i]
		var at := TownPlan.centroid(poly)
		if i < roles.size():
			_add(str(roles[i][1]), str(roles[i][0]), at.x, at.y)
			if i > 0:
				edges.append([0, i])          # every ward reachable from the square
		# THE STREET IS THE GAP. Each ward is inset before it is subdivided, so
		# the space between wards is the road and no building can stand in it.
		# Nothing here draws a street; the negative space is the street.
		var block := TownPlan.inset(poly, TownPlan.REGULAR_STREET * 0.5)
		if block.size() < 3:
			continue
		# Poorer and older quarters are more chaotic and more tightly packed;
		# richer ones have bigger plots and bigger courtyards. One chaos value
		# for a whole town makes every quarter read the same.
		var rich: float = 1.0 - float(i) / maxf(float(quarters.size() - 1), 1.0)
		var min_area: float = lerpf(2.0, 7.0, rich)
		var chaos: float = lerpf(0.9, 0.5, rich)
		var empty: float = lerpf(0.03, 0.16, rich)
		var lots: Array = []
		TownPlan.subdivide(block, min_area, chaos, 0.7, empty, rng, lots)
		for lot in lots:
			# THINNED AT THE EDGE. A town that stops dead at its boundary reads as
			# a cut-out; real ones fray. Weighted by distance from the middle, so
			# the core stays solid.
			# Thinning starts only at the OUTER FIFTH and never removes more than a
			# fifth of what is there. At (d - 0.55) * 0.9 it was stripping whole
			# wards on the far side of the town, which reads as a district that
			# was never built rather than as an edge that frays.
			var d := TownPlan.centroid(lot).distance_to(Vector2(50, 50)) / maxf(_reach(0.0), 1.0)
			if rng.randf() < clampf((d - 0.80) * 0.9, 0.0, 0.2):
				continue
			buildings.append({"poly": lot, "big": TownPlan.area(lot) > min_area * 2.2})



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


## ── WHAT THE GM PUT HERE ─────────────────────────────────────────────────────
##
## Read LAST, after the generated quarters, so a site always lands inside a ward
## that already exists rather than defining one. The GM named a ward; the lot is
## the engine's choice — a real building lot from the plan, so a site stands ON
## something instead of floating at a centroid.
##
## The lot is picked by a hash of the NAME, not by the rng, because this runs
## after the seeded pass and must give the same answer on every rebuild without
## depending on how many sites came before it.
func _plan_sites() -> void:
	for spec in GameState.town_sites(place):
		if not (spec is Dictionary):
			continue
		var w := int(spec.get("ward", -1))
		if w < 0 or w >= wards.size():
			continue
		var poly: PackedVector2Array = wards[w]
		var at := TownPlan.centroid(poly)
		# Stand it on a real lot inside that ward, if one is there to stand on.
		var h := absi(hash(str(spec.get("name", ""))))
		var lots: Array = []
		for b in buildings:
			var c := TownPlan.centroid(b["poly"])
			if Geometry2D.is_point_in_polygon(c, poly):
				lots.append(c)
		if not lots.is_empty():
			at = lots[h % lots.size()]
		sites.append(spec)
		_add(str(spec.get("name", "")), "site:" + str(spec.get("kind", "landmark")),
			at.x, at.y)
		# Reachable from the square, like every other named place in the town.
		if nodes.size() > 1:
			edges.append([0, nodes.size() - 1])


## Which way out of the middle a point lies — the qualifier an unnamed quarter
## takes, so every ward on a plan has a name you could give directions with.
func _quarter_of(at: Vector2) -> String:
	var d := at - Vector2(50, 50)
	if absf(d.x) > absf(d.y):
		return "East" if d.x > 0.0 else "West"
	return "South" if d.y > 0.0 else "North"


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

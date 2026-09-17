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
var trades: Array = []             # {"kind", "name", "ward"} — what this place sells
var sites: Array = []              # GM-authored, per ward — see `GameState.town_sites`
## ── WHAT IS OUTSIDE THE WALL ─────────────────────────────────────────────────
## A town that stops dead at its boundary reads as a cut-out pasted on blank
## paper, which is what every one of these sheets was. Gates, the roads that
## leave through them, the ribbon of building that follows each road out, and
## the ploughland beyond.
var gates: Array = []              # {"at": Vector2, "to": String}
var out_roads: Array = []          # PackedVector2Array per road, percent space
var arteries: Array = []           # PackedVector2Array: gate -> square, inside the wall
var plaza := PackedVector2Array()  # the open ground of the market square
var gardens: Array = []            # PackedVector2Array: plots left unbuilt
var landmarks: Array = []          # {"kind", "outer": PackedVector2Array, "parts": Array}
var outskirts: Array = []          # {"poly": ...} buildings beyond the wall
var furlongs: Array = []           # {"strips": Array[PackedVector2Array]}

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


## ── THE TOWN, SAID TO THE NARRATOR ───────────────────────────────────────────
## Measured before this existed: no prompt the game sends read `wards`, `trades`,
## `sites` or the trouble clock. The map drew an Inn by the gate and a Fence in the
## lawless quarter, and the GM — never told — invented its own, so the story and
## the map described two different towns. And `[[site ward=N]]` asks for a ward
## NUMBER the model had no way to know. This is that list, numbered.
const _WEALTH := ["poor", "modest", "comfortable", "rich"]
const _LAW := ["lawless", "loosely watched", "watched", "tightly policed"]
const _TIER := ["hamlet", "village", "town", "city"]


func brief(standing_at := "") -> String:
	if not settled or wards.is_empty():
		return ""
	var qs: Array[String] = []
	for i in wards.size():
		# The number rides INSIDE the brackets as `ward=N`. Written "4 The Cottages" the
		# real narrator read it as part of the name and wrote "Cottages 4" in prose.
		qs.append("%s (ward=%d, %s, %s)" % [ward_name[i], i,
			_WEALTH[clampi(ward_wealth[i], 0, 3)], _LAW[clampi(ward_law[i], 0, 3)]])
	var places_in: Array[String] = []
	for t in trades:
		places_in.append("%s in %s" % [t["name"], ward_name[int(t["ward"])]])
	for s in sites:
		var w := int(s.get("ward", 0))
		places_in.append("%s (%s) in %s%s" % [s.get("name", ""), s.get("kind", ""), ward_name[w],
			(" — " + str(s["lore"])) if str(s.get("lore", "")) != "" else ""])
	# WHAT THE TOWN LACKS, said next to the scene. Taught only in the protocol, the
	# real narrator made no [[site]] in six turns — including when asked for a fence
	# in a town that has none.
	var have: Array = trades.map(func(t): return str(t["kind"])) + sites.map(func(x): return str(x.get("kind", "")))
	var lacks: Array[String] = []
	for k in GameState.SITE_KINDS:
		if not have.has(k) and not ["home", "landmark"].has(k):
			lacks.append(str(k))
	var out := "TOWN — %s is a %s. QUARTERS: %s. ALREADY HERE — use these names, do not invent a second of any: %s. NOT HERE YET: %s — when the story needs one, create it with [[site kind=... ward=...]] in the quarter that suits it." % [
		place, _TIER[clampi(size_tier, 0, 3)], "; ".join(qs), "; ".join(places_in), ", ".join(lacks)]
	if standing_at != "" and standing_at != place:
		out += " The party is at %s." % standing_at
	var t := GameState.trouble_at(place)
	if not t.is_empty():
		var fall := str(t.get("fallout", "prices"))
		if GameState.trouble_spent(t):
			out += " TROUBLE HERE CAME TO A HEAD: %s — and now %s; show it." % [t.get("what", ""), GameState.fallout_line(place, fall)]
		else:
			var clues: Array = t.get("clues") if t.get("clues") is Array else []
			out += " TROUBLE HERE (clock %d/%d; if it fills, %s): %s." % [int(t.get("filled", 0)), int(t.get("size", 6)),
				GameState.fallout_line(place, fall), t.get("what", "")]
			if str(t.get("thread", "")) != "":
				out += " It bears on %s." % t["thread"]
			if not clues.is_empty():
				out += " Leads the player has: %s." % "; ".join(clues)
			if GameState.trouble_known(place).is_empty():
				out += " IT IS SECRET — the player does not know. Plant traces they can find (%d of %d clues found so far; tag each with [[clue]]); never state it outright." % [
					clues.size(), GameState.CLUES_TO_UNCOVER]
	var region := GameState.region_of_place(place)
	for rt in GameState.running_troubles():
		if rt["reach"] == "region" and region != "" and str(rt["place"]) != place \
				and GameState.region_of_place(str(rt["place"])) == region:
			out += " ACROSS THE REGION, from %s: %s — folk here feel it too." % [rt["place"], rt["what"]]
	return out


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
		_plan_outside(rng)
		_plan_arteries()
		_plan_trades()
		_plan_landmarks()
		_plan_sites()
		# A TROUBLE THAT CAME TO A HEAD WITH fallout=law takes a step of law off
		# every quarter. AFTER the trades are placed, so the fence does not move
		# house because the watch lost its nerve; the brief and the GM see it.
		if GameState.fallout_at(place) == "law":
			for i in ward_law.size():
				ward_law[i] = maxi(0, ward_law[i] - 1)
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
		var n_w := quarters.size()
		var water_role := roles.size() - 1     # the site-chosen role is appended last
		if str(roles[water_role][0]) == "quay":
			# A QUAY WITH NO WARD TO STAND IN takes the least important slot.
			# Roles run richest first, so the last WARD's role is the filler.
			# Without this the swap below traded the quay into a real ward and
			# pushed that ward's role off the end of the list — which, when the
			# water-facing ward was the square's, deleted the town's market
			# square outright. The Leaning Lantern shipped with no centre, and
			# nothing noticed until its high streets had nowhere to go.
			if water_role >= n_w:
				roles[n_w - 1] = roles[water_role]
				water_role = n_w - 1
			var far := -INF
			var pick := -1
			# Never the square's ward (0): the market may well sit on the
			# waterfront, but evicting it costs the town its centre.
			for i in range(1, n_w):
				var lean := (TownPlan.centroid(quarters[i]) - Vector2(50, 50)).dot(water_dir)
				if lean > far:
					far = lean
					pick = i
			if pick >= 1 and pick != water_role:
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
		# THE WORLD SETS THE GRAIN, the ward varies it. `WorldSkin.grain` carries
		# this family's lot size, street chaos, yard share and how much of a plot
		# is built on — so a cyber district is big regular blocks built lot-line
		# to lot-line and a fishing village is cramped strips with long gardens,
		# from one generator. Before this every world used one set of numbers and
		# every town was the same gravel at map zoom.
		#
		# Wealth then moves it WITHIN the town: a richer quarter has bigger plots,
		# straighter streets and more courtyard. One chaos value for a whole town
		# makes every quarter read the same.
		var g := WorldSkin.grain(fam)
		var rich := float(ward_wealth[i]) / 3.0
		var min_area: float = float(g["lot"]) * lerpf(0.7, 1.9, rich)
		var chaos: float = clampf(float(g["chaos"]) * lerpf(1.15, 0.7, rich), 0.05, 1.0)
		var empty: float = float(g["empty"]) * lerpf(0.6, 1.8, rich)
		# BACKWARDS AT FIRST, and the check caught it. A POOR quarter builds on MORE
		# of its plot, not less: it is packed with infill, outbuildings and
		# subdivided yards, while a wealthy one keeps a courtyard and a garden.
		# Having it the other way round left the poorest wards of the pirate towns
		# under the built-share floor, which is the probe reporting a modelling
		# error rather than a tuning one. Wealth already buys more `empty` on top
		# of this, so the two pull the same way.
		var front: float = clampf(float(g["front"]) * lerpf(1.12, 0.92, rich), 0.25, 1.0)
		# TWO STAGES, and they use OPPOSITE rules on purpose.
		#
		# `subdivide` cuts the longest edge, which drives every piece toward
		# square — right for carving a ward into BLOCKS, and fatally wrong for
		# plots, which have to stay long and narrow. So it stops at block size
		# and `burgage` takes over on one fixed axis per block.
		var block_area := min_area * 14.0
		var plot_w := sqrt(min_area) * 0.6
		# THE SQUARE IS OPEN GROUND. It was a label standing on houses — the
		# square ward was built up like every other, so "The Market Square"
		# named a block of burgage strips. Watabou's market ward has no buildings
		# at all, only the open square and something at its heart; the middle of
		# this ward is kept clear the same way, and the high streets are brought
		# into it below.
		var open := PackedVector2Array()
		if str(ward_role[i]) == "square":
			var bc := TownPlan.centroid(block)
			for v in block:
				open.append(bc + (v - bc) * 0.46)
			plaza = open
		var blocks: Array = []
		TownPlan.subdivide(block, block_area, chaos, 0.5, 0.0, rng, blocks)
		for blk in blocks:
			# THINNED AT THE EDGE. A town that stops dead at its boundary reads as
			# a cut-out; real ones fray. Thinning starts only at the outer fifth
			# and never removes more than a fifth of what is there.
			var d := TownPlan.centroid(blk).distance_to(Vector2(50, 50)) / maxf(_reach(0.0), 1.0)
			if rng.randf() < clampf((d - 0.80) * 0.9, 0.0, 0.2):
				continue
			var plots: Array = []
			TownPlan.burgage(blk, plot_w, front, rng, plots)
			for built in plots:
				# A yard, a garden, a burnt-out plot. Wealthier quarters keep more
				# of them, which is what a courtyard IS, structurally.
				if open.size() > 2 and Geometry2D.is_point_in_polygon(TownPlan.centroid(built), open):
					rng.randf()                # keep the stream identical either way
					continue
				if rng.randf() < empty:
					# NOT DISCARDED — KEPT AS A GARDEN. An unbuilt plot is a yard, a
					# kitchen garden, an orchard; it was thrown away and rendered as
					# bare paper, so a wealthy quarter's courtyards looked like holes.
					gardens.append(built)
					continue
				buildings.append({"poly": built, "big": TownPlan.area(built) > min_area * 2.0})



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


## ── LANDMARKS ARE BUILDINGS, NOT SYMBOLS ─────────────────────────────────────
##
## A hall or a temple was a mark standing on an ordinary burgage strip — a small
## glyph with somebody's house under it. Watabou reserves a whole patch for a
## cathedral and gives it its own cutter (a ring, for the cloister); the cheaper
## version that reads the same at map zoom is to clear the ground round the named
## place and stand a footprint on it whose SHAPE says what it is.
##
##   · a temple is a CROSS PLAN — nave and transept — laid east-west, because
##     churches were oriented with the altar to the east, which is the kind of
##     detail that makes a plan read as surveyed rather than generated
##   · the hall is a COURTYARD RANGE: four wings round an open yard, the shape
##     of a guildhall or a moot hall's precinct
##
## Shape carries the meaning, not fill — the research found no source for "the
## important building is filled solid" as a rule, and this map already dropped
## that for ink density. A silhouette is what an engraver actually changed.
func _plan_landmarks() -> void:
	for n in nodes:
		var role := str(n.get("role", ""))
		var kind := ""
		if role == "hall":
			kind = "hall"
		elif role == "site:temple":
			kind = "temple"
		if kind == "":
			continue
		var at := Vector2(float(n["x"]), float(n["y"]))
		if plaza.size() > 2 and Geometry2D.is_point_in_polygon(at, plaza):
			continue
		var outer := PackedVector2Array()
		var parts: Array = []
		if kind == "temple":
			var nave := _rect_at(at, Vector2(5.2, 1.8), 0.0)
			var transept := _rect_at(at + Vector2(1.1, 0), Vector2(1.5, 3.8), 0.0)
			parts = [nave, transept]
			outer = _rect_at(at + Vector2(0.4, 0), Vector2(5.6, 4.2), 0.0)
		else:
			# Square to the ward's own long axis, so the range sits with its street.
			var w: PackedVector2Array = wards[ward_role.find("hall")] if ward_role.has("hall") else PackedVector2Array()
			var ang := 0.0
			if w.size() > 2:
				var e := TownPlan._longest_edge(w)
				ang = (w[(e + 1) % w.size()] - w[e]).angle()
			outer = _rect_at(at, Vector2(5.0, 3.6), ang)
			parts = [outer, _rect_at(at, Vector2(2.6, 1.4), ang)]   # the yard is parts[1]
		# Clear the ground it stands on.
		var kept: Array = []
		for b in buildings:
			var bc := TownPlan.centroid(b["poly"])
			if not Geometry2D.is_point_in_polygon(bc, outer.duplicate()) 					and bc.distance_to(at) > 2.4:
				kept.append(b)
		buildings = kept
		landmarks.append({"kind": kind, "at": at, "outer": outer, "parts": parts})


func _rect_at(c: Vector2, sz: Vector2, ang: float) -> PackedVector2Array:
	var h := sz * 0.5
	return PackedVector2Array([
		c + Vector2(-h.x, -h.y).rotated(ang), c + Vector2(h.x, -h.y).rotated(ang),
		c + Vector2(h.x, h.y).rotated(ang), c + Vector2(-h.x, h.y).rotated(ang)])


## ── WHAT THE PLACE SELLS, AND WHERE IT STANDS ────────────────────────────────
##
## The `shop` field on a place was a free STRING — the whole economy model, and
## nothing could gate it, price it, draw it or look it up. Trades are a closed
## enum now, gated by size, named by the world, and placed by rules that are
## mostly historical rather than invented:
##
##   · a SMITH is pushed to the edge. Fire risk; real towns zoned forges out, and
##     noxious trades (tanners, knackers) were driven outside the walls by
##     municipal ordinance, not by custom.
##   · a FENCE goes where the law is thinnest, which is what the law axis is for.
##     It is not given a criminal QUARTER — the shipped systems that do this well
##     gate the transaction, not the geography, and their fences live anywhere
##     plausible.
##   · an INN goes to the gate, because that is where travellers arrive and
##     innkeepers were the people who profited from them.
##   · a TEMPLE takes the square, a SAGE and a GUILD take the hall, and trade
##     goods cluster in the trade ward — which is the best-attested pattern of
##     all: guilds were assigned STREETS by the town, which is why English towns
##     still have an Ironmonger Row and a Shambles.
func _plan_trades() -> void:
	if wards.is_empty():
		return
	var fam := WorldSkin.family_for_id(world_id)
	for key in WorldSkin.trades_at(size_tier):
		var best := -1
		var best_score := -INF
		for i in wards.size():
			var role := str(ward_role[i])
			var score := 0.0
			match key:
				"temple":
					score = 3.0 if role == "square" else 0.0
				"sage", "guild":
					score = 3.0 if role == "hall" else 0.0
				"store", "alchemist":
					score = 3.0 if role == "shop" else (1.5 if role == "square" else 0.0)
				"inn":
					score = 3.0 if role in ["gate", "quay"] else (1.5 if role == "square" else 0.0)
				"tavern":
					score = 3.0 if role == "inn" else (1.0 if role == "square" else 0.0)
				"smith":
					# Out to the edge, where the fire cannot take the town with it.
					score = 2.0 - float(ward_wealth[i]) * 0.6
				"fence":
					score = 3.0 - float(ward_law[i]) * 1.4
			# A tie-break that is stable but not always the same ward.
			score += float(absi(hash(key + str(i))) % 100) * 0.004
			if score > best_score:
				best_score = score
				best = i
		if best < 0:
			continue
		var at := TownPlan.centroid(wards[best])
		var lots: Array = []
		for b in buildings:
			var c := TownPlan.centroid(b["poly"])
			if Geometry2D.is_point_in_polygon(c, wards[best]):
				lots.append(c)
		if not lots.is_empty():
			at = lots[absi(hash(key + place)) % lots.size()]
		var nm := "The %s" % WorldSkin.trade_name(fam, key)
		trades.append({"kind": key, "name": nm, "ward": best})
		_add(nm, "site:" + key, at.x, at.y)
		if nodes.size() > 1:
			edges.append([0, nodes.size() - 1])


## ── OUTSIDE THE WALL ─────────────────────────────────────────────────────────
##
## GATES GO WHERE ROADS ARRIVE, which is the historical pattern and not the
## modern-map one: "gates at the four cardinal points" is only true where a Roman
## grid forces it. This map already knows where the roads come from — the other
## places on the world chart — so a gate is put at the point of the wall nearest
## each neighbour's bearing, and the local map agrees with the world map about
## which way the world is. Organic towns run roughly 1.5-3 gates per km of wall;
## two to five here, by size.
func _plan_outside(rng: RandomNumberGenerator) -> void:
	if bounds.size() < 3:
		return
	var me := Vector2(50, 50)
	var mine := Vector2.INF
	var others: Array = []
	for l in GameState.places():
		if not (l is Dictionary) or not (l.has("x") and l.has("y")):
			continue
		if str(l.get("name", "")) == place:
			mine = Vector2(float(l["x"]), float(l["y"]))
		else:
			others.append({"at": Vector2(float(l["x"]), float(l["y"])), "nm": str(l.get("name", ""))})
	var bearings: Array = []
	if mine != Vector2.INF:
		others.sort_custom(func(a, b): return a["at"].distance_to(mine) < b["at"].distance_to(mine))
		for o in others:
			bearings.append([(o["at"] - mine).angle(), str(o["nm"])])
	# A town with no neighbours still has ways out of it.
	while bearings.size() < 2:
		bearings.append([rng.randf() * TAU, ""])
	var want: int = mini(2 + size_tier, bearings.size())

	# A GATE IS WHERE A STREET MEETS THE WALL. Placing gates by bearing alone put
	# them wherever the wall happened to cross that angle, and the wall is mostly
	# the back of somebody's house: measured, 22 of 29 gates across the shipped
	# towns opened straight onto a building. Watabou's rule is the historical one
	# — a gate goes where a street reaches the wall — so the bearing now only
	# CHOOSES among the real street mouths, and a bearing with no mouth near it
	# gets no gate rather than a gate into a kitchen.
	var mouths := _street_mouths()
	var used: Array = []
	var taken_mouth := {}
	for b in bearings:
		if gates.size() >= want:
			break
		var ang: float = float(b[0])
		var pick := -1
		var off := deg_to_rad(40.0)
		for mi in mouths.size():
			if taken_mouth.has(mi):
				continue
			var d := absf(angle_difference(float(mouths[mi]["ang"]), ang))
			if d < off:
				off = d
				pick = mi
		if pick < 0:
			continue
		var mang: float = float(mouths[pick]["ang"])
		# No two gates adjacent — the exclusion rule real generators use, and
		# what stops a town having three doors in one wall.
		var too_close := false
		for u in used:
			if absf(angle_difference(float(u), mang)) < deg_to_rad(50.0):
				too_close = true
				break
		if too_close:
			continue
		# A GATE OPENS ONTO LAND. A neighbour across a bay is a real bearing to a
		# real place, but the road to it does not walk on water — Gallows Quay
		# once put two gates on its seaward wall and drew a suburb into the harbour.
		var at: Vector2 = mouths[pick]["at"]
		ang = mang
		var step0 := Vector2(cos(ang), sin(ang))
		if _in_water(at + step0 * 6.0):
			continue
		taken_mouth[pick] = true
		used.append(ang)
		gates.append({"at": at, "to": str(b[1])})

		# THE ROAD OUT. Straight-ish to the sheet edge, wandering a little, so it
		# reads as drawn rather than ruled — the same distinction the world chart
		# makes between the route and the line.
		var road := PackedVector2Array([at])
		var step := Vector2(cos(ang), sin(ang))
		var wob := rng.randf() * TAU
		for k in range(1, 9):
			var t := float(k) / 8.0
			var far := at + step * (t * 62.0)
			# Enough wander to read as drawn rather than ruled. At 3.2 it was
			# invisible over sixty units.
			far += step.orthogonal() * sin(t * 3.4 + wob) * 7.0 * t
			if _in_water(far):
				break
			road.append(far)
		if road.size() > 1:
			out_roads.append(road)

		# THE FAUBOURG. Building ribbons along the road just outside the gate and
		# thins with distance — the documented shape, and the reason it exists is
		# that it holds what the walls will not: tanneries, forges, inns for
		# travellers who arrived after the gates shut.
		for k in range(1, 7):
			var t2 := float(k) / 6.0
			if rng.randf() > 1.0 - t2 * 0.8:
				continue
			for sgn in SIDES:
				if rng.randf() < 0.35:
					continue
				var c := at + step * (t2 * 17.0) + step.orthogonal() * sgn * rng.randf_range(1.6, 3.4)
				if _in_water(c):
					continue
				var w := rng.randf_range(1.1, 2.0)
				var h := rng.randf_range(0.9, 1.6)
				var quad := PackedVector2Array([
					c + Vector2(-w, -h).rotated(ang), c + Vector2(w, -h).rotated(ang),
					c + Vector2(w, h).rotated(ang), c + Vector2(-w, h).rotated(ang)])
				outskirts.append({"poly": quad})
	_plan_fields(rng)


## ── THE HIGH STREETS: every gate to the square ───────────────────────────────
##
## Watabou computes these once — every gate-to-plaza path — and tiers each street
## by whether it lies on one. NOT by subdivision depth, which was my first
## instinct and is wrong: depth says how small a block is, not whether anyone
## walks past it. The historical version agrees — roads converge on the market
## from the gates — though in an organic town they bend and merge rather than run
## ruler-straight, which a path through the real street network does for free.
##
## Routed on a one-unit grid where the WARDS are solid, so the only way through
## is the gaps between them, which are the streets.
func _plan_arteries() -> void:
	if gates.is_empty() or wards.is_empty():
		return
	var sq := ward_role.find("square")
	if sq < 0:
		return
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, 100, 100)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in 100:
		for x in 100:
			var c := Vector2(float(x) + 0.5, float(y) + 0.5)
			# OUTSIDE THE WALL IS SOLID TOO. Left open, the whole countryside was
			# free space and the cheapest way from a gate to the square was round
			# the OUTSIDE of the town, hugging the wall — both of Gallows Quay's
			# high streets wrapped the perimeter instead of crossing it.
			if not Geometry2D.is_point_in_polygon(c, bounds):
				grid.set_point_solid(Vector2i(x, y), true)
				continue
			for w in wards:
				if Geometry2D.is_point_in_polygon(c, w):
					grid.set_point_solid(Vector2i(x, y), true)
					break
	# The goal is the open street cell nearest the square's middle — the square
	# ward itself is solid, so the road arrives at its edge, which is the square.
	var target := TownPlan.centroid(wards[sq])
	var goal := Vector2i(-1, -1)
	var best := INF
	for y in 100:
		for x in 100:
			if grid.is_point_solid(Vector2i(x, y)):
				continue
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_squared_to(target)
			if d < best:
				best = d
				goal = Vector2i(x, y)
	if goal.x < 0:
		return
	for gt in gates:
		var gp: Vector2 = gt["at"]
		var start := Vector2i(clampi(int(gp.x), 0, 99), clampi(int(gp.y), 0, 99))
		# The gate sits ON the wall; step in until the street is open.
		var inward := (Vector2(50, 50) - gp).normalized()
		var tries := 0
		while grid.is_point_solid(start) and tries < 6:
			gp += inward
			start = Vector2i(clampi(int(gp.x), 0, 99), clampi(int(gp.y), 0, 99))
			tries += 1
		if grid.is_point_solid(start):
			continue
		var path := grid.get_point_path(start, goal)
		if path.size() < 2:
			continue
		var pts := PackedVector2Array([gt["at"]])
		for q in path:
			pts.append(q + Vector2(0.5, 0.5))
		# INTO THE SQUARE, not merely to its edge. The router stops at the last
		# open street cell, which is outside the square's ward; the last leg is
		# cut through to the plaza and anything standing on it is cleared, so the
		# roads visibly converge on the market rather than stopping at a wall of
		# houses.
		if plaza.size() > 2:
			var pc := TownPlan.centroid(plaza)
			var a := pts[pts.size() - 1]
			var kept: Array = []
			for bld in buildings:
				var bcen := TownPlan.centroid(bld["poly"])
				if bcen.distance_to(Geometry2D.get_closest_point_to_segment(bcen, a, pc)) > 1.6:
					kept.append(bld)
			buildings = kept
			pts.append(pc)
		arteries.append(_chaikin(pts))


func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
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


## Every place the town's street network reaches its boundary. Walks the wall,
## steps a little inward at each point, and keeps the runs where that step lands
## in NO ward — which, since wards are cut apart by their streets, is exactly a
## street. Each run collapses to its middle.
func _street_mouths() -> Array:
	var out: Array = []
	var me := Vector2(50, 50)
	var n := bounds.size()
	var run: Array = []
	for i in n + 1:
		var a: Vector2 = bounds[i % n]
		var b: Vector2 = bounds[(i + 1) % n]
		var steps := maxi(int(a.distance_to(b) / 0.6), 1)
		for k in steps:
			var q := a.lerp(b, float(k) / float(steps))
			var probe := q + (me - q).normalized() * 3.0
			var in_ward := false
			for w in wards:
				if Geometry2D.is_point_in_polygon(probe, w):
					in_ward = true
					break
			if not in_ward:
				run.append(q)
			elif not run.is_empty():
				out.append(_mouth_of(run))
				run = []
	if not run.is_empty():
		out.append(_mouth_of(run))
	return out


func _mouth_of(run: Array) -> Dictionary:
	var mid: Vector2 = run[run.size() / 2]
	return {"at": mid, "ang": (mid - Vector2(50, 50)).angle()}


## ── THE PLOUGHLAND ───────────────────────────────────────────────────────────
##
## Open-field strips, not the neat hedged rectangles most people picture — those
## are Enclosure-era, eighteenth century, and putting them round a medieval town
## is a period mismatch. A strip (a selion) is about 200 m long by 5-20 m wide,
## which on this plate is roughly 19 units by 0.5-2; they are bundled into
## FURLONGS, and neighbouring furlongs run at DIFFERENT ANGLES because each
## follows its own slope and drainage. That patchwork of angles is the whole
## visual signature.
func _plan_fields(rng: RandomNumberGenerator) -> void:
	var me := Vector2(50, 50)
	# MANY TRIES, MOST REJECTED. A furlong is refused for water, for the sheet
	# edge and for sitting on a road, so the count here is attempts and not
	# fields. At 14 attempts the ring round the town came out with six scattered
	# blocks and a dead gap between the wall and the first of them.
	for k in 48:
		var ang := rng.randf() * TAU
		# CLEAR OF THE WALL BY THE FIELD'S OWN HALF-DEPTH. Offsetting only the
		# CENTRE put furlongs across the boundary — a ploughed field lying over
		# the town wall, which is the kind of thing a render shows instantly and
		# a number never would.
		var r := _reach(ang) + rng.randf_range(9.0, 26.0)
		var c := me + Vector2(cos(ang), sin(ang)) * r
		if c.x < 2.0 or c.x > 98.0 or c.y < 2.0 or c.y > 98.0:
			continue
		if _in_water(c):
			continue                       # nobody ploughs the harbour
		# Keep off the roads — a field is what the road runs BETWEEN.
		var clash := false
		for road in out_roads:
			for q in road:
				if q.distance_to(c) < 5.5:
					clash = true
					break
			if clash:
				break
		for f2 in furlongs:
			if TownPlan.centroid(f2["hull"]).distance_to(c) < 9.0:
				clash = true
				break
		if clash:
			continue
		var lay := rng.randf() * PI          # this furlong's own ploughing angle
		var long := rng.randf_range(8.0, 14.0)
		var wide := rng.randf_range(5.0, 10.0)
		# THE HEDGE. A furlong needs a BOUNDARY or its strips read as loose
		# hatching — which is exactly what they did: parallel arcs on open paper
		# look like wind lines on a sea chart, not like ploughland. The outline is
		# what says "this is a worked field" before a single strip is seen.
		var hull := PackedVector2Array()
		for corner in [Vector2(-wide, -long), Vector2(wide, -long),
				Vector2(wide, long), Vector2(-wide, long)]:
			hull.append(c + (corner * 0.5).rotated(lay))
		var strips: Array = []
		var n := int(wide / rng.randf_range(1.0, 1.7))
		for i in maxi(n, 2):
			var u := (float(i) / float(maxi(n - 1, 1)) - 0.5) * wide
			var line := PackedVector2Array()
			for j in 5:
				var t3 := float(j) / 4.0
				# THE REVERSED-S IS REAL, not decoration: a plough only turns soil
				# one way, so the team began arcing before the headland to set up
				# the next pass. It still shows in ridge-and-furrow earthworks.
				# Shallow, though — at the amplitude drawn first it bowed the
				# strips into something that read as hatching rather than furrows.
				var bend := sin(t3 * TAU) * 0.35
				line.append(c + Vector2(u + bend, (t3 - 0.5) * long).rotated(lay))
			strips.append(line)
		furlongs.append({"hull": hull, "strips": strips})


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

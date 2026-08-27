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

var place := ""
var world_id := ""
var kind := ""
var settled := false
var site := WorldTerrain.PLAIN     # the world terrain class under this place
var nodes: Array = []              # {name, role, x, y}  — x/y percent of the plate
var edges: Array = []              # [i, j] into `nodes`

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
	var rng := RandomNumberGenerator.new()
	# Seeded from the world AND the name, so two towns called Millbrook in
	# different worlds are different towns, and the same one is itself forever.
	rng.seed = absi(hash("%s|%s" % [wid, place_name]))
	if settled:
		_build_town(rng)
	else:
		_build_site(rng)


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
	for i in range(1, nodes.size() - 1):
		if rng.randf() < 0.55:
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

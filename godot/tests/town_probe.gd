extends Node
## THE INSTRUMENT FOR THE TOWN PLAN — counts what lands in every ward, in every
## settled place, in every world.
##
##   godot --headless --path godot res://tests/town_probe.tscn
##
## ── WHY IT EXISTS ────────────────────────────────────────────────────────────
## `TownPlan.subdivide` used to RETURN EMPTY at its recursion cap. Any ward that
## needed more splits than the cap allows therefore lost every building under
## that branch — silently — and the quarter rendered as bare ground. Nothing
## failed. The only way to see it was to look at the picture and notice a hole,
## which is exactly the class of defect a picture is worst at showing, because a
## map with a park in it looks like a map with a park in it.
##
## So: an empty ward is a FAILURE, and coverage is a printed number rather than
## an adjective. Headless is fine — this reads geometry, it does not draw.

## A ward this small is a scrap left by a cut, not a quarter; it is allowed to
## come out empty. Measured: real quarters in a 100-unit plate run 90-900.
const SCRAP_AREA := 24.0

## Built ground over ward ground.
##
## LOWERED FROM 0.15 WHEN THE GEOMETRY CHANGED, not to make a failure go away.
## 0.15 was calibrated when a building WAS its whole lot; burgage plots build on
## the street end and leave the depth behind as yard, so the same town reads as
## dense at a lower share by design. The number this guards against is a district
## that silently came out empty, and `NOTHING BUILT` above catches that exactly;
## this is the softer floor for "built, but too thin to read as a quarter".
const MIN_FILL := 0.12

var _failed: Array = []
var _towns := 0


func _ready() -> void:
	await get_tree().process_frame
	print("TOWN-PROBE start")
	for w in Rules.builtin_worlds():
		var wid := str(w.get("id", ""))
		if wid == "":
			continue
		# GameState.places(), not Rules.world_locations — same lesson terrain_probe
		# carries: three worlds place ALL their pins by search, so the authored
		# list is not what the map draws, and reading it means never seeing them.
		GameState.character = {"id": "dm-probe", "world_id": wid}
		for p in GameState.places():
			if not p is Dictionary:
				continue
			var knd := str(p.get("kind", ""))
			if not LocalMap.SETTLED_KINDS.has(knd):
				continue
			_probe(wid, str(p.get("name", "")), knd)
	# ── ON THE WORLD CHART, NO PLACE NAME LIES ACROSS A REGION BANNER ────────
	# Region banners were drawn by a pass the label solver never saw, so on
	# Saltmarsh "Gallows Quay" the place sat across "GALLOWS QUAY" the region and
	# read as a typo. Solved headless with every place known, which is the most
	# crowded the chart gets.
	for w2 in Rules.builtin_worlds():
		var wid2 := str(w2.get("id", ""))
		if wid2 == "":
			continue
		GameState.character = {"id": "dm-probe", "world_id": wid2}
		var chart: Control = load("res://scenes/ui/world_map.gd").new()
		chart.size = Vector2(1280, 800)
		chart.locations = GameState.places()
		chart.regions = GameState.regions()
		chart.fog = false
		var font: Font = Ui.display
		chart._solve_labels(font)
		for rg in chart._visible_regions():
			var rr: Rect2 = chart._region_rect(font, str(rg["name"]), rg["at"])
			for nm2 in chart._label_at.keys():
				var at2: Vector2 = chart._label_at[nm2]
				var sz2 := font.get_string_size(str(nm2), HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
				var lr := Rect2(at2 - Vector2(0, sz2.y * 0.8), sz2)
				if lr.intersects(rr):
					_failed.append("%s chart: '%s' is lettered across the region banner '%s'" % [
						wid2, nm2, rg["name"]])
		chart.free()

	# Counting the work, not the ask — same lesson `terrain_probe` carries: a
	# parse error in a class_name file is silent at the call site, so a summary
	# built from the LIST reports a cheerful OK for zero measurements.
	if _towns == 0:
		print("TOWN-PROBE FAILED: measured no towns at all")
		get_tree().quit(1)
		return
	if _failed.is_empty():
		print("TOWN-PROBE OK %d town(s)" % _towns)
		get_tree().quit(0)
		return
	for f in _failed:
		print("  %s" % f)
	print("TOWN-PROBE FAILED: %d problem(s) over %d town(s)" % [_failed.size(), _towns])
	get_tree().quit(1)


var line2 := ""


## Signed cross of consecutive edges; a convex ring never changes sign.
func _reflex(poly: PackedVector2Array) -> int:
	var n := poly.size()
	if n < 3:
		return 0
	var pos := 0
	var neg := 0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var c: Vector2 = poly[(i + 2) % n]
		var cr := (b - a).cross(c - b)
		if cr > 0.0001:
			pos += 1
		elif cr < -0.0001:
			neg += 1
	return mini(pos, neg)


func _convex(poly: PackedVector2Array) -> bool:
	return _reflex(poly) == 0


func _probe(wid: String, nm: String, knd: String) -> void:
	if nm == "":
		return
	LocalMap.forget("%s|%s" % [wid, nm])
	var lm := LocalMap.for_place(wid, nm, knd)
	if lm.wards.is_empty():
		_failed.append("%s/%s: no wards" % [wid, nm])
		return
	_towns += 1
	# Attribute each building to the ward its centroid falls in. Buildings are
	# sub-polygons of an inset ward, so a centroid cannot land in a neighbour.
	var fill := PackedFloat32Array()
	var count := PackedInt32Array()
	fill.resize(lm.wards.size())
	count.resize(lm.wards.size())
	for b in lm.buildings:
		var poly: PackedVector2Array = b["poly"]
		var c := TownPlan.centroid(poly)
		for i in lm.wards.size():
			if Geometry2D.is_point_in_polygon(c, lm.wards[i]):
				fill[i] += TownPlan.area(poly)
				count[i] += 1
				break
	line2 = "   bounds convex=%s reflex=%d |" % [_convex(lm.bounds), _reflex(lm.bounds)]
	for i in lm.wards.size():
		var w: PackedVector2Array = lm.wards[i]
		var ins := TownPlan.inset(w, TownPlan.REGULAR_STREET * 0.5)
		line2 += " [%d cvx=%s rfx=%d a=%.0f ins=%.0f]" % [
			i, _convex(w), _reflex(w), TownPlan.area(w), TownPlan.area(ins)]
	print(line2)
	# ── WARD IDENTITY ────────────────────────────────────────────────────────
	# A ward id is an INDEX, and a [[site]] tag stores one in the save file. So
	# the same town must produce the same wards in the same order every time it
	# is built, or a fence the GM put in ward 3 moves quarters between sessions.
	LocalMap.forget("%s|%s" % [wid, nm])
	var again := LocalMap.for_place(wid, nm, knd)
	if again.ward_name != lm.ward_name or again.ward_role != lm.ward_role:
		_failed.append("%s/%s: ward ids are not stable across rebuilds — a saved site would move" % [wid, nm])
	var seen := {}
	for i in lm.wards.size():
		var wn := str(lm.ward_name[i])
		if wn.strip_edges() == "":
			_failed.append("%s/%s ward %d has no name" % [wid, nm, i])
		elif seen.has(wn):
			_failed.append("%s/%s: wards %d and %d are both called '%s' — a town you cannot give directions in" % [
				wid, nm, int(seen[wn]), i, wn])
		seen[wn] = i
		# Two axes, each 0-3. A single rich/poor dial is the documented cliche;
		# these are only worth having if they can disagree.
		if lm.ward_wealth[i] < 0 or lm.ward_wealth[i] > 3:
			_failed.append("%s/%s ward %d: wealth %d out of 0-3" % [wid, nm, i, lm.ward_wealth[i]])
		if lm.ward_law[i] < 0 or lm.ward_law[i] > 3:
			_failed.append("%s/%s ward %d: law %d out of 0-3" % [wid, nm, i, lm.ward_law[i]])
	# EVERY TOWN HAS EXACTLY ONE SQUARE. The quay swap once traded it off the end
	# of the role list, and The Leaning Lantern shipped with no centre — which only
	# surfaced because its high streets had nothing to route to.
	if lm.ward_role.count("square") != 1:
		_failed.append("%s/%s: %d market squares — a town has exactly one centre (roles %s)" % [
			wid, nm, lm.ward_role.count("square"), lm.ward_role])
	if lm.water_dir != Vector2.ZERO and lm.site in [WorldTerrain.COAST, WorldTerrain.SHOAL] 			and lm.ward_role.count("quay") != 1:
		_failed.append("%s/%s: a coastal town with %d quays" % [wid, nm, lm.ward_role.count("quay")])
	# THE SQUARE IS OPEN. Nothing stands in the plaza, and it is big enough to read.
	if lm.plaza.size() > 2:
		var inside := 0
		for b in lm.buildings:
			if Geometry2D.is_point_in_polygon(TownPlan.centroid(b["poly"]), lm.plaza):
				inside += 1
		if inside > 0:
			_failed.append("%s/%s: %d buildings stand in the market square" % [wid, nm, inside])
	elif lm.ward_role.has("square"):
		_failed.append("%s/%s: the square has no open ground" % [wid, nm])
	if lm.ward_name.size() != lm.wards.size():
		_failed.append("%s/%s: %d wards but %d names" % [wid, nm, lm.wards.size(), lm.ward_name.size()])

	# ── A GATE MUST OPEN ONTO A STREET ───────────────────────────────────────
	# Probe a short way inside each gate. If that point is inside a building, the
	# gate opens into somebody's house.
	var blocked := 0
	for gt in lm.gates:
		var gat: Vector2 = gt["at"]
		var inward := (Vector2(50, 50) - gat).normalized()
		for step in [2.5, 4.0, 5.5]:
			var pt: Vector2 = gat + inward * float(step)
			var hit := false
			for b in lm.buildings:
				if Geometry2D.is_point_in_polygon(pt, b["poly"]):
					hit = true
					break
			if hit:
				blocked += 1
				break
	print("  GATES %s/%s: %d gates, %d open onto a building, %d high streets" % [
		wid, nm, lm.gates.size(), blocked, lm.arteries.size()])
	if blocked > 0:
		_failed.append("%s/%s: %d gate(s) open straight onto a building — a gate belongs where a street meets the wall" % [
			wid, nm, blocked])
	var line := "%s/%s  t%d w%s  wards=%d  buildings=%d
   " % [
		wid, nm, lm.size_tier, "Y" if lm.walled else "n",
		lm.wards.size(), lm.buildings.size()]
	for i in lm.wards.size():
		var a := TownPlan.area(lm.wards[i])
		var f := fill[i] / maxf(a, 0.001)
		line += " [%d: a=%.0f n=%d fill=%.2f]" % [i, a, count[i], f]
		if a < SCRAP_AREA:
			continue
		if count[i] == 0:
			_failed.append("%s/%s ward %d: area %.0f, NOTHING BUILT" % [wid, nm, i, a])
		elif f < MIN_FILL:
			_failed.append("%s/%s ward %d: area %.0f, fill %.2f below %.2f" % [
				wid, nm, i, a, f, MIN_FILL])
	print(line)

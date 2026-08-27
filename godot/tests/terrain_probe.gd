extends Node
## THE INSTRUMENT for the inverted map pipeline — build it before the fix, per
## CLAUDE.md. Generates every world's ground as data, asserts the pins sit on
## something their kind would actually occupy, routes roads over it, and writes a
## PNG per world so the result can be judged by eye rather than by adjective.
##
##   godot --headless --path godot res://tests/terrain_probe.tscn
##
## Headless is fine: this paints into an Image and saves it, so no rasterizer is
## involved — unlike `screen_shots`, which must run windowed and says so.
##
## It FAILS when an authored pin cannot be suited by any candidate seed. That is
## the whole point: the old pipeline could not fail, because nothing ever
## compared a pin against the ground under it, and three pins sat in open water
## for a year.

const OUT := "user://terrain"
const CELL := 10        # px per terrain cell in the written PNG

var _failed: Array = []
var _measured := 0     # worlds that produced a real, non-degenerate terrain


func _ready() -> void:
	await get_tree().process_frame
	print("TERRAIN-PROBE start")
	DirAccess.make_dir_recursive_absolute(OUT)
	var worlds: Array = []
	for w in Rules.builtin_worlds():
		var wid := str(w.get("id", ""))
		if wid != "":
			worlds.append(wid)
	for wid in worlds:
		_probe(wid)
	# REFUSE TO REPORT SUCCESS FOR NOTHING. The first run of this printed
	# "TERRAIN-PROBE OK 6 world(s)" while WorldTerrain failed to compile — a
	# parse error in a class_name file is silent at the call site, every `_probe`
	# aborted on its first line, and the summary read from `worlds.size()`, which
	# counts what was ASKED FOR rather than what was measured. Counting the work
	# is the difference; `screen_shots` learned the same lesson about flat frames.
	if _measured != worlds.size():
		print("TERRAIN-PROBE FAILED: measured %d of %d worlds — the rest never ran" % [
			_measured, worlds.size()])
		get_tree().quit(1)
		return
	if _failed.is_empty():
		print("TERRAIN-PROBE OK %d world(s) -> %s" % [
			_measured, ProjectSettings.globalize_path(OUT)])
		get_tree().quit(0)
		return
	print("TERRAIN-PROBE FAILED: %s" % ", ".join(_failed))
	get_tree().quit(1)


func _probe(wid: String) -> void:
	var t0 := Time.get_ticks_msec()
	WorldTerrain.forget(wid)
	var t := WorldTerrain.for_world(wid)
	# THE REAL PATH. Reading `Rules.world_locations` and skipping anything without
	# x/y meant this probe never saw saltmarsh, fimbulreach or brasshaven place a
	# single pin — and those are the three worlds that place ALL of theirs by
	# search. GameState.places() is what the Atlas actually draws.
	GameState.character = {"id": "dm-probe", "world_id": wid}
	var want: float = float(WorldTerrain.GROUND.get(t.family, WorldTerrain.GROUND["fantasy"])["water"])
	print("\n--- %s (%s)  seed=%d  water asked %.0f%% got %.0f%%  %d ms" % [
		wid, t.family, t.seed_used, want * 100.0, t.water_fraction() * 100.0,
		Time.get_ticks_msec() - t0])

	# Every pin the Atlas would draw, against the ground now under it.
	var places := GameState.places()
	var bad := 0
	var pinned := 0
	var cells := {}
	for l in places:
		if not (l is Dictionary) or not (l.has("x") and l.has("y")):
			continue
		pinned += 1
		var c := t.cell_of(Vector2(float(l["x"]), float(l["y"])))
		var kind := str(l.get("kind", ""))
		var ok := t.suits(kind, c)
		if not ok:
			bad += 1
		# TWO PINS ON ONE CELL is what the hashed tie-break exists to prevent; a
		# spacing pass was the alternative and it would have cost memoisation.
		var ck := "%d,%d" % [c.x, c.y]
		if cells.has(ck):
			_failed.append("%s (%s and %s share cell %s)" % [wid, cells[ck], str(l.get("name", "")), ck])
		cells[ck] = str(l.get("name", ""))
		print("    %s %-26s %-11s %-6s score %.2f  (%d,%d)" % [
			"  " if ok else "!!", str(l.get("name", "")), kind, _kname(t.klass(c)),
			t.score(kind, c), c.x, c.y])
	if bad > 0:
		_failed.append("%s (%d/%d pins on impossible ground)" % [wid, bad, pinned])

	# The cost field the roads will actually path over — the number to hold the
	# old pixel reader against (neonspire was 73.2 % expensive; a flat city
	# should be near zero).
	var heavy := 0
	var total := WorldTerrain.W * WorldTerrain.H
	for y in WorldTerrain.H:
		for x in WorldTerrain.W:
			if t.cost(Vector2i(x, y)) > 1.5:
				heavy += 1
	print("    cost field: %.1f%% of cells over 1.5x" % [100.0 * float(heavy) / float(total)])
	_render(wid, t, places)
	# A DEGENERATE FIELD IS NOT A TERRAIN. All-land or all-water passes every pin
	# check for the wrong reason, and a flat elevation makes every road straight
	# while looking like it routed. Neither may count as a measured world.
	var wf := t.water_fraction()
	if wf <= 0.001 or wf >= 0.999:
		_failed.append("%s (degenerate: %.1f%% water)" % [wid, wf * 100.0])
		return
	if t.elev.size() != WorldTerrain.W * WorldTerrain.H:
		_failed.append("%s (elevation field is %d cells, expected %d)" % [
			wid, t.elev.size(), WorldTerrain.W * WorldTerrain.H])
		return
	_measured += 1


func _kname(k: int) -> String:
	return ["deep", "shoal", "coast", "plain", "hill", "peak"][k]


## Terrain colours — readable, not final art. P4 decides what the Atlas actually
## looks like; this only has to make a wrong coastline obvious at a glance.
func _shade(t: WorldTerrain, c: Vector2i) -> Color:
	var up := clampf((t.height(c) - t.sea) / maxf(1.0 - t.sea, 0.001), 0.0, 1.0)
	match t.klass(c):
		WorldTerrain.DEEP:
			return Color(0.06, 0.13, 0.30)
		WorldTerrain.SHOAL:
			return Color(0.16, 0.34, 0.52)
		WorldTerrain.COAST:
			return Color(0.76, 0.71, 0.52)
		WorldTerrain.PLAIN:
			return Color(0.32, 0.47, 0.26).lerp(Color(0.45, 0.55, 0.29), up)
		WorldTerrain.HILL:
			return Color(0.45, 0.42, 0.26).lerp(Color(0.52, 0.44, 0.32), up)
		_:
			return Color(0.62, 0.60, 0.60).lerp(Color(0.93, 0.93, 0.95), up)


func _render(wid: String, t: WorldTerrain, places: Array) -> void:
	var img := Image.create(WorldTerrain.W * CELL, WorldTerrain.H * CELL, false, Image.FORMAT_RGBA8)
	for y in WorldTerrain.H:
		for x in WorldTerrain.W:
			img.fill_rect(Rect2i(x * CELL, y * CELL, CELL, CELL), _shade(t, Vector2i(x, y)))

	# ROADS over the DATA — the thing P2 will move into world_map. Minimum
	# spanning tree over the places, each edge A*'d across the cost field, which
	# is exactly the network the Atlas already draws.
	var pts: Array[Vector2i] = []
	for l in places:
		if l is Dictionary and l.has("x") and l.has("y"):
			pts.append(t.cell_of(Vector2(float(l["x"]), float(l["y"]))))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, WorldTerrain.W, WorldTerrain.H)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.update()
	for y in WorldTerrain.H:
		for x in WorldTerrain.W:
			grid.set_point_weight_scale(Vector2i(x, y), t.cost(Vector2i(x, y)))
	for e in _mst(pts):
		for p in grid.get_id_path(pts[e.x], pts[e.y]):
			img.fill_rect(Rect2i(p.x * CELL + CELL / 3, p.y * CELL + CELL / 3,
				CELL / 3, CELL / 3), Color(0.12, 0.06, 0.03, 0.95))

	# The pins last, so a road never covers one.
	for l in places:
		if not (l is Dictionary) or not (l.has("x") and l.has("y")):
			continue
		var c := t.cell_of(Vector2(float(l["x"]), float(l["y"])))
		var ok := t.suits(str(l.get("kind", "")), c)
		var col := Color(1, 0.85, 0.25) if ok else Color(1, 0.15, 0.15)
		img.fill_rect(Rect2i(c.x * CELL - CELL, c.y * CELL - CELL, CELL * 3, CELL * 3), Color(0, 0, 0, 0.9))
		img.fill_rect(Rect2i(c.x * CELL - CELL / 2, c.y * CELL - CELL / 2, CELL * 2, CELL * 2), col)

	var p := "%s/%s.png" % [OUT, wid]
	if img.save_png(p) != OK:
		_failed.append("%s (render failed)" % wid)
		return
	print("    -> %s" % ProjectSettings.globalize_path(p))


## Prim's, the same tree world_map draws — kept here so the probe shows the real
## network rather than a prettier one.
func _mst(pts: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if pts.size() < 2:
		return out
	var linked := [0]
	var loose := range(1, pts.size())
	while not loose.is_empty():
		var ba := -1
		var bb := -1
		var bd := INF
		for a in linked:
			for b in loose:
				var d: float = Vector2(pts[a]).distance_squared_to(Vector2(pts[b]))
				if d < bd:
					bd = d
					ba = a
					bb = b
		if bb < 0:
			break
		out.append(Vector2i(ba, bb))
		linked.append(bb)
		loose.erase(bb)
	return out

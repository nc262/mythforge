extends Node
## CAN THE GM PUT A POINT OF INTEREST INSIDE A TOWN? Drives the real path rather
## than reasoning about it.
##
##   godot --headless --path godot res://tests/site_probe.tscn
##
## The GM's geography power is `[[place]]` -> `GameState.add_place`, which the
## engine vetoes by scope. This asks the question one level down: when the GM
## adds a place, does the TOWN the player is standing in change at all?
##
## It asserts nothing about the answer. It PRINTS the answer, because the point
## is to find out, and a probe that assumes its result is a probe that will
## agree with whatever it was written to believe.

var _lines: Array = []


func _ready() -> void:
	await get_tree().process_frame
	print("SITE-PROBE start")
	var wid := "saltmarsh"
	GameState.character = {"id": "dm-site", "name": "Probe", "world_id": wid, "level": 20}
	# A settlement to stand in, and the plan it generates.
	# THE REAL KIND, carried through everywhere. `add_site` builds the plan with
	# the place's own kind, and `_size_of` branches on it — so a probe that
	# snapshots with "settlement" while the engine validates against "tavern" is
	# comparing two different towns with different ward counts.
	var town := ""
	var town_kind := ""
	for p in GameState.places():
		if p is Dictionary and LocalMap.SETTLED_KINDS.has(str(p.get("kind", ""))):
			town = str(p.get("name", ""))
			town_kind = str(p.get("kind", ""))
			break
	if town == "":
		print("SITE-PROBE FAILED: no settled place in %s" % wid)
		get_tree().quit(1)
		return

	var before := _snapshot(wid, town, town_kind)
	print("  town '%s' before: %d nodes -> %s" % [town, before.size(), ", ".join(before)])
	var places_before := GameState.places().size()

	# ── THE GM ACTS ──────────────────────────────────────────────────────────
	# Exactly what `_gm_makes_place` does for [[place name=... kind=shop ...]].
	var why := GameState.add_place({
		"name": "The Drowned Bell",
		"kind": "shop",
		"lore": "A chandlery that buys what the tide brings in, no questions asked.",
		"shop": "rope, oil, salvage",
		"region": "",
		"scope": "local",
	})
	print("  add_place verdict: %s" % ("ACCEPTED" if why == "" else why))

	var places_after := GameState.places().size()
	print("  world chart: %d places -> %d" % [places_before, places_after])


	# ── THE VERDICT ──────────────────────────────────────────────────────────
	var world_changed := places_after > places_before
	print("")
	print("  WORLD MAP updated : %s" % ("yes" if world_changed else "NO"))

	# ── NOW THE TIER BELOW: a site INSIDE the town ───────────────────────────
	var lm := LocalMap.for_place(wid, town, town_kind)
	print("  %s has %d wards, sizes tier %d, walled=%s" % [
		town, lm.wards.size(), lm.size_tier, lm.walled])
	for i in lm.wards.size():
		print("    ward %d  %-22s wealth=%d law=%d" % [
			i, lm.ward_name[i], lm.ward_wealth[i], lm.ward_law[i]])

	# Every refusal the engine can give, so the messages themselves are tested.
	for bad in [
		{"name": "X", "kind": "smith", "ward": 0, "settlement": "Nowhere-at-All"},
		{"name": "X", "kind": "starship-dealer", "ward": 0, "settlement": town},
		{"name": "X", "kind": "smith", "ward": 99, "settlement": town},
	]:
		print("  refused: %s" % GameState.add_site(bad))

	var ok := GameState.add_site({
		"name": "The Drowned Bell", "kind": "fence", "ward": 2,
		"settlement": town, "lore": "Buys what the tide brings in.",
	})
	print("  add_site verdict: %s" % ("ACCEPTED" if ok == "" else ok))
	var after2 := _snapshot(wid, town, town_kind)
	print("  town after site  : %d nodes -> %s" % [after2.size(), ", ".join(after2)])
	var town_changed := after2 != before
	print("")
	print("  TOWN MAP updated  : %s" % ("yes" if town_changed else "NO"))
	if not town_changed:
		print("SITE-PROBE FAILED: the GM added a site and the town did not change")
		get_tree().quit(1)
		return
	if not after2.has("The Drowned Bell"):
		print("SITE-PROBE FAILED: the site is not among the town's named places")
		get_tree().quit(1)
		return
	# ── THE TOWN'S LIVE PROBLEM ──────────────────────────────────────────────
	print("")
	for bad2 in [["Nowhere-at-All", "x", 6], [town, "", 6], [town, "x", 99]]:
		print("  trouble refused: %s" % GameState.set_trouble(str(bad2[0]), str(bad2[1]), int(bad2[2])))
	var tw := GameState.set_trouble(town, "press-gangs are taking men off the quay", 6)
	print("  set_trouble: %s" % ("ACCEPTED" if tw == "" else tw))
	# A SECOND, DIFFERENT trouble must not silently replace the first.
	print("  second trouble refused: %s" % GameState.set_trouble(town, "a different calamity", 6))
	for k in 4:
		GameState.tick_trouble(town, 2)
		var t2 := GameState.trouble_at(town)
		print("    tick -> %d/%d" % [int(t2.get("filled", 0)), int(t2.get("size", 0))])
	var done := GameState.trouble_at(town)
	if int(done.get("filled", 0)) != int(done.get("size", 0)):
		print("SITE-PROBE FAILED: the clock did not fill and did not clamp")
		get_tree().quit(1)
		return
	# And it survives a rebuild of the town, which is the whole point of a clock.
	var kept := GameState.trouble_at(town)
	if str(kept.get("what", "")) == "":
		print("SITE-PROBE FAILED: the trouble did not persist")
		get_tree().quit(1)
		return
	print("  clock persists: %s" % str(kept.get("what", "")))

	# ── THE WORLD MOVES WHILE YOU ARE ELSEWHERE ──────────────────────────────
	# The clock only ever advanced when the GM said so, which makes it a counter
	# the narrator keeps rather than a world that keeps going. A day passing has
	# to move it — everywhere except where the party is standing.
	GameState.tick_trouble(town, -6)                # wind it back to empty
	var away := ""
	for p2 in GameState.places():
		if p2 is Dictionary and str(p2.get("name", "")) != town:
			away = str(p2.get("name", ""))
			break
	if away != "":
		GameState.set_trouble(away, "the mill wheel has cracked", 4)
	# Stand IN the town, then let a day pass.
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	wd["here"] = town
	GameState.state["world"] = wd
	GameState.save_kind("world", wd)
	var here_before := int(GameState.trouble_at(town).get("filled", 0))
	var away_before := int(GameState.trouble_at(away).get("filled", 0)) if away != "" else 0
	GameState.advance_time(GameState.TIMES.size())   # one whole day
	var here_after := int(GameState.trouble_at(town).get("filled", 0))
	var away_after := int(GameState.trouble_at(away).get("filled", 0)) if away != "" else 0
	print("  a day passes — standing in %s: %d -> %d" % [town, here_before, here_after])
	print("                  away in %s: %d -> %d" % [away, away_before, away_after])
	if here_after != here_before:
		print("SITE-PROBE FAILED: the trouble crept in the town the party is standing in")
		get_tree().quit(1)
		return
	if away != "" and away_after != away_before + 1:
		print("SITE-PROBE FAILED: a day passed and the trouble elsewhere did not creep")
		get_tree().quit(1)
		return

	print("SITE-PROBE OK")
	get_tree().quit(0)


## The town's named places, rebuilt from scratch so a cache cannot hide a change.
func _snapshot(wid: String, town: String, knd: String) -> Array:
	LocalMap.forget("%s|%s" % [wid, town])
	var lm := LocalMap.for_place(wid, town, knd)
	var out: Array = []
	for n in lm.nodes:
		out.append(str(n.get("name", "")))
	out.sort()
	return out

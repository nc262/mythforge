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

	if not _trouble_lifecycle(town, town_kind):
		get_tree().quit(1)
		return
	print("SITE-PROBE OK")
	get_tree().quit(0)


func _bad(why: String) -> bool:
	print("SITE-PROBE FAILED: " + why)
	return false


func _stand(place: String) -> void:
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	wd["here"] = place
	GameState.state["world"] = wd


## A TROUBLE ENDS, AND WHO HEARS OF IT DEPENDS ON WHAT KIND IT IS. Two bugs and
## one mechanism, each asserted rather than printed:
##   · a town whose trouble came to a head, or was resolved, could never have
##     another ("already has a trouble running" about a stopped clock);
##   · the map showed every trouble to anyone who had visited, secret or not;
##   · reach=town is heard on arrival, reach=region anywhere in the region,
##     reach=secret only by [[uncover]] or when it comes to a head.
func _trouble_lifecycle(town: String, town_kind: String) -> bool:
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	wd.erase("trouble")
	GameState.state["world"] = wd
	var away := ""
	for p in GameState.places():
		if p is Dictionary and str(p.get("name", "")) != town:
			away = str(p["name"])
			break
	_stand(away)
	# ── BUG 1: a spent trouble blocks nothing ──
	if GameState.set_trouble(town, "a", 4) != "":
		return _bad("a first trouble was refused")
	if GameState.set_trouble(town, "b", 4).find("already has a trouble running") < 0:
		return _bad("a RUNNING trouble let a second, different one replace it")
	GameState.tick_trouble(town, 4)
	var why := GameState.set_trouble(town, "c", 5)
	if why != "":
		return _bad("a trouble that came to a head still blocks the next one: " + why)
	if int(GameState.trouble_at(town).get("filled", -1)) != 0:
		return _bad("the new trouble inherited the old clock's segments")
	GameState.tick_trouble(town, 2)
	GameState.tick_trouble(town, -2)
	if not GameState.trouble_at(town).is_empty():
		return _bad("a trouble pushed back to nothing is still on the record")
	if GameState.set_trouble(town, "d", 4) != "":
		return _bad("a resolved trouble still blocks the next one")
	if GameState.set_trouble(away, "x", 4, "loud").find("reach must be") < 0:
		return _bad("an unknown reach was accepted")
	# ── BUG 2 + reach=town: heard on arrival, not before ──
	if not GameState.trouble_known(town).is_empty():
		return _bad("a town trouble is known to a player who has not been there since it began")
	if not GameState.notice_troubles().is_empty():
		return _bad("a town trouble was announced to a player standing elsewhere")
	_stand(town)
	if GameState.notice_troubles().size() != 1 or GameState.trouble_known(town).is_empty():
		return _bad("arriving in a troubled town did not announce the trouble")
	if not GameState.notice_troubles().is_empty():
		return _bad("a trouble was announced twice")
	# ── reach=secret: never heard, found out by [[uncover]] ──
	GameState.tick_trouble(town, -4)
	if GameState.set_trouble(town, "the reeve is selling children to the fae", 6, "secret") != "":
		return _bad("a secret trouble was refused")
	if not GameState.notice_troubles().is_empty() or not GameState.trouble_known(town).is_empty():
		return _bad("a SECRET trouble was announced to the player standing in the town")
	LocalMap.forget("%s|%s" % [GameState.world_id(), town])
	var brief := LocalMap.for_place(GameState.world_id(), town, town_kind).brief()
	if brief != "" and brief.find("IT IS SECRET") < 0:
		return _bad("the narrator is not told the trouble is secret: " + brief.right(200))
	if GameState.uncover_trouble(town) != "" or GameState.trouble_known(town).is_empty():
		return _bad("[[uncover]] did not make the secret known")
	# A secret that comes to a head is out in the street.
	GameState.tick_trouble(town, -6)
	GameState.set_trouble(town, "a smuggling ring", 4, "secret")
	GameState.tick_trouble(town, 4)
	if GameState.notice_troubles().size() != 1:
		return _bad("a secret that came to a head where the player stands stayed hidden")
	# ── reach=region: heard anywhere in the region ──
	var reg := GameState.region_of_place(town)
	var kin := ""
	for p in GameState.places():
		if p is Dictionary and str(p.get("name", "")) != town and str(p.get("region", "")) == reg and reg != "":
			kin = str(p["name"])
			break
	if kin != "":
		var wd2: Dictionary = GameState.state.get("world")
		wd2.erase("trouble")
		_stand(kin)
		if GameState.set_trouble(town, "the harvest has failed", 6, "region") != "":
			return _bad("a region trouble was refused")
		if GameState.notice_troubles().size() != 1:
			return _bad("a region trouble was not heard in %s, in the same region" % kin)
	# A record written before reach existed was already on the map: still known.
	var wd3: Dictionary = GameState.state.get("world")
	wd3["trouble"] = {town: {"what": "old", "size": 6, "filled": 1}}
	if GameState.trouble_known(town).is_empty():
		return _bad("a trouble from an older save vanished from the player's map")
	wd3.erase("trouble")
	print("  trouble lifecycle: spent and resolved troubles free the town; town/region/secret reach heard correctly%s" % (
		"" if kin != "" else " (no second place in the region — region reach unchecked)"))
	return true


## The town's named places, rebuilt from scratch so a cache cannot hide a change.
func _snapshot(wid: String, town: String, knd: String) -> Array:
	LocalMap.forget("%s|%s" % [wid, town])
	var lm := LocalMap.for_place(wid, town, knd)
	var out: Array = []
	for n in lm.nodes:
		out.append(str(n.get("name", "")))
	out.sort()
	return out

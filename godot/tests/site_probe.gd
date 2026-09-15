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
	var town := ""
	for p in GameState.places():
		if p is Dictionary and LocalMap.SETTLED_KINDS.has(str(p.get("kind", ""))):
			town = str(p.get("name", ""))
			break
	if town == "":
		print("SITE-PROBE FAILED: no settled place in %s" % wid)
		get_tree().quit(1)
		return

	var before := _snapshot(wid, town)
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

	var after := _snapshot(wid, town)
	print("  town '%s' after : %d nodes -> %s" % [town, after.size(), ", ".join(after)])

	# ── THE VERDICT ──────────────────────────────────────────────────────────
	var world_changed := places_after > places_before
	var town_changed := before != after
	print("")
	print("  WORLD MAP updated : %s" % ("yes" if world_changed else "NO"))
	print("  TOWN MAP updated  : %s" % ("yes" if town_changed else "NO"))
	if world_changed and not town_changed:
		print("  => The GM can put a place on the CHART but not inside a TOWN.")
		print("     The town plan is generated from (world, name) alone — it never")
		print("     reads GameState, so nothing the GM invents can appear in it.")
	print("SITE-PROBE OK")
	get_tree().quit(0)


## The town's named places, rebuilt from scratch so a cache cannot hide a change.
func _snapshot(wid: String, town: String) -> Array:
	LocalMap.forget("%s|%s" % [wid, town])
	var lm := LocalMap.for_place(wid, town, "settlement")
	var out: Array = []
	for n in lm.nodes:
		out.append(str(n.get("name", "")))
	out.sort()
	return out

extends Node
## REAL MODEL, AT-19: the player asks a town for something that is not on its map.
## Does the GM decide sensibly, and does the engine keep the answer legal?
## Manual probe (GPU, ~1 min warm): not in the gate.
##
##   godot --headless --path godot res://tests/ask_probe.tscn
const ASKS := [
	"an apothecary",
	"somewhere to sell something I would rather nobody asked about",
	"a stable for my horse",
	"a wizards' college with a library of ten thousand books",
	"a spaceport",
]


func _ready() -> void:
	await get_tree().process_frame
	GameState.character = {"id": "dm-ask-probe", "name": "Probe", "world_id": "embervale"}
	GameState.state = {"world": {}}
	var town := ""
	var kind := ""
	for pl in GameState.places():
		if pl is Dictionary and LocalMap.TOWN_KINDS.has(str(pl.get("kind", ""))):
			town = str(pl["name"])
			kind = str(pl["kind"])
			break
	GameState.state["world"] = {"here": town}
	if not LocalGM.available():
		print("unavailable: ", LocalGM.why_unavailable()); get_tree().quit(); return
	await LocalGM.warm()
	var lm := LocalMap.for_place(GameState.world_id(), town, kind)
	print("ASK-PROBE %s — a %s with %d quarters; already: %s" % [town,
		GameState.SETTLEMENT_SIZES[clampi(lm.size_tier, 0, 3)], lm.wards.size(),
		", ".join(lm.trades.map(func(t): return str(t["name"])))])
	var added := 0
	for q in ASKS:
		var t0 := Time.get_ticks_msec()
		var said: Dictionary = await Chronicle.ask_after(town, kind, q)
		var out: Dictionary = GameState.answer_ask(town, q, said)
		added += 1 if bool(out.get("found", false)) else 0
		print("  \"%s\" %.1fs\n    GM: %s\n    ENGINE: %s -> %s" % [q, (Time.get_ticks_msec() - t0) / 1000.0,
			str(said), "ON THE MAP" if bool(out.get("found", false)) else "no", str(out.get("line", ""))])
	LocalMap.forget("%s|%s" % [GameState.world_id(), town])
	var after := LocalMap.for_place(GameState.world_id(), town, kind)
	var names: Array = []
	for s in after.sites:
		names.append("%s (%s, ward %d)" % [s.get("name", ""), s.get("kind", ""), int(s.get("ward", -1))])
	print("RESULT: %d of %d asks put something on the map: %s" % [added, ASKS.size(), "; ".join(names)])
	get_tree().quit()

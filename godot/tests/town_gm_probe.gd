extends Node
## REAL MODEL: does the narrator use the town its map drew? The offline check in
## `ui_playthrough` proves the town reaches the envelope and the tags reach the
## map; only the model can say whether it then names the map's Inn instead of
## inventing its own, and gives a [[site]] a ward the engine accepts. Same town,
## same lines, A = with the TOWN context, B = with it cut out of the envelope.
## Manual probe (GPU, ~1 min warm): not in the gate.
const LINES := [
	"I look for somewhere in town to sell a ring I would rather nobody asked about.",
	"I find the busiest place to eat and ask what has been going wrong around here lately.",
	"I go looking for a smith to mend my buckler.",
]
var _acc := ""
var _town := ""
var _kind := ""


func _ready() -> void:
	await get_tree().process_frame
	GameState.character = {"id": "dm-town-gm-probe", "name": "Probe", "world_id": "embervale"}
	GameState.state = {"world": {}}
	var best := -1
	for pl in GameState.places():
		if pl is Dictionary and LocalMap.SETTLED_KINDS.has(str(pl.get("kind", ""))):
			var lm := LocalMap.for_place("embervale", str(pl["name"]), str(pl["kind"]))
			if lm.wards.size() > best:
				best = lm.wards.size()
				_town = str(pl["name"])
				_kind = str(pl["kind"])
	GameState.state["world"] = {"here": _town}
	if not LocalGM.available():
		print("unavailable: ", LocalGM.why_unavailable()); get_tree().quit(); return
	Api.sse_delta.connect(func(t): _acc += t)
	await LocalGM.warm()
	var lm := LocalMap.for_place("embervale", _town, _kind)
	var names: Array = lm.trades.map(func(t): return str(t["name"]))
	print("TOWN %s (%s): %d quarters; on the map: %s" % [_town, _kind, lm.wards.size(), ", ".join(names)])
	print("  context: ", Composer.town_context())
	for arm in ["A with town", "B without"]:
		var hits := 0
		var tags := 0
		var accepted := 0
		for line in LINES:
			var env := Composer.envelope(line)
			if arm.begins_with("B"):
				env = env.replace(Composer.town_context(), "")
			_acc = ""
			var t0 := Time.get_ticks_msec()
			LocalGM.stream(env, Composer.system_prompt())
			await Api.sse_done
			var reply := _acc
			var named: Array = names.filter(func(n): return reply.contains(n) or reply.contains(n.trim_prefix("The ")))
			hits += 1 if not named.is_empty() else 0
			var said: Array[String] = []
			for tg in Tags.parse(reply)["tags"]:
				var k := str(tg["name"])
				var a: Dictionary = tg["attrs"]
				if not ["site", "trouble", "clock"].has(k):
					continue
				tags += 1
				var why := ""
				match k:
					"site":
						why = GameState.add_site({"name": str(a.get("name", "")), "kind": str(a.get("kind", "landmark")),
							"ward": int(a.get("ward", -1)), "settlement": _town, "lore": str(a.get("lore", ""))})
					"trouble":
						why = GameState.set_trouble(_town, str(a.get("what", "")), int(a.get("clock", 6)))
					"clock":
						why = GameState.tick_trouble(_town, int(a.get("tick", 1)))
				accepted += 1 if why == "" else 0
				said.append("%s%s" % [k, "" if why == "" else " REFUSED: " + why])
			print("[%s] %.1fs  names-from-map=%s  tags=%s\n    \"%s\"" % [arm, (Time.get_ticks_msec() - t0) / 1000.0,
				named, said, Tags.parse(reply)["clean"].strip_edges().replace("\n", " ").left(260)])
		print("ARM %s: %d/%d replies used a name the map has; %d town tags, %d accepted" % [arm, hits, LINES.size(), tags, accepted])
		GameState.state["world"] = {"here": _town}   # B starts from the same town A did
		LocalMap.forget("embervale|%s" % _town)
	get_tree().quit()

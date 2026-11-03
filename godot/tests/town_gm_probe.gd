extends Node
## REAL MODEL: does the narrator use the town and its trouble the way the engine
## expects? The offline harnesses prove every tag lands; only the model can say
## whether it WRITES them. Manual probe (GPU, ~1 min warm): not in the gate.
##
## Scenario: the richest settled place in Embervale, with a SECRET trouble. The
## player investigates. Measured per turn: does the reply leak the secret, does it
## write [[clue]] (and does the engine accept it), does it mark a roll trouble=1,
## and does it use a name the map has.
const SECRET := "the miller is poisoning the well on the baron's orders"
const LEAK := ["poison", "baron"]
const LINES := [
	"I ask around the market about why so many people have fallen sick.",
	"I go and look closely at the town well.",
	"I watch the mill after dark to see who comes and goes.",
	"I confront the miller and press him hard for the truth.",
]
const TRADE_LINES := [
	"I look for somewhere to get a drink and hear the local gossip.",
	"My sword is notched. Where can I get it mended?",
	"I need a room for the night.",
	"I want to buy rope, lamp oil and travel rations.",
]
## AT-18: things Hearthwood Market does NOT have (no fence, no guild) and one
## that is no trade at all. The narrator should create each with [[site]].
const SITE_LINES := [
	"I look for someone who buys stolen goods, no questions asked.",
	"I want to find whoever runs the merchants' guild here.",
	"Is there a stable where I could buy a horse?",
	"I ask where the town keeps its records and old maps.",
]
const CALM_LINES := [
	"I find a seat in the busiest tavern and listen to what people are worried about.",
	"I ask the market traders what the news is in town.",
	"I ask the temple's priest whether anything troubles the town lately.",
	"I walk the streets after dark and see what's going on.",
]
var _acc := ""


func _ready() -> void:
	await get_tree().process_frame
	GameState.character = {"id": "dm-town-gm-probe", "name": "Probe", "world_id": "embervale"}
	GameState.state = {"world": {}}
	var town := ""
	var kind := ""
	var best := -1
	for pl in GameState.places():
		if pl is Dictionary and LocalMap.TOWN_KINDS.has(str(pl.get("kind", ""))):
			var lm := LocalMap.for_place("embervale", str(pl["name"]), str(pl["kind"]))
			if lm.wards.size() > best:
				best = lm.wards.size()
				town = str(pl["name"])
				kind = str(pl["kind"])
	GameState.state["world"] = {"here": town}
	if not LocalGM.available():
		print("unavailable: ", LocalGM.why_unavailable()); get_tree().quit(); return
	Api.sse_delta.connect(func(t): _acc += t)
	await LocalGM.warm()
	var names: Array = LocalMap.for_place("embervale", town, kind).trades.map(func(t): return str(t["name"]))
	# `-- calm`: a town with NO trouble. Does the narrator start one, in a tag or
	# only in prose? Only the tag reaches the engine.
	if OS.get_cmdline_user_args().has("calm"):
		for line in CALM_LINES:
			_acc = ""
			LocalGM.stream(Composer.envelope(line), Composer.system_prompt())
			await Api.sse_done
			var p: Dictionary = Tags.parse(_acc)
			var said: Array = p["tags"].filter(func(tg): return str(tg["name"]) == "trouble").map(func(tg): return tg["attrs"])
			var t0 := Time.get_ticks_msec()
			var read: Dictionary = await Chronicle.read_new_trouble(line, str(p["clean"]))
			print("[calm: %s] trouble-tags=%s READ %.1fs %s -> on record: %s\n    \"%s\"" % [line.left(30), said,
				(Time.get_ticks_msec() - t0) / 1000.0, read, GameState.trouble_at(town).get("what", "-"),
				str(p["clean"]).strip_edges().replace("\n", " ").left(500)])
			GameState.state = {"world": {"here": town}}   # judge every turn, not just the first
		get_tree().quit()
		return
	print("set_trouble: '%s'" % GameState.set_trouble(town, SECRET, 6, "secret", {"fallout": "law"}))
	print("TOWN %s; context: %s" % [town, Composer.town_context()])
	var leaks := 0
	var clues := 0
	var accepted := 0
	var worked := 0
	for line in LINES:
		_acc = ""
		var t0 := Time.get_ticks_msec()
		LocalGM.stream(Composer.envelope(line), Composer.system_prompt())
		await Api.sse_done
		var reply := _acc
		var clean := str(Tags.parse(reply)["clean"])
		var leaked := LEAK.any(func(w): return clean.to_lower().contains(w)) and GameState.trouble_known(town).is_empty()
		leaks += 1 if leaked else 0
		var said: Array[String] = []
		for tg in Tags.parse(reply)["tags"]:
			var a: Dictionary = tg["attrs"]
			match str(tg["name"]):
				"clue":
					clues += 1
					var why := GameState.add_clue(str(a.get("place", town)) if str(a.get("place", "")) != "" else town, str(a.get("note", "")))
					accepted += 1 if why == "" else 0
					said.append("clue%s" % ("" if why == "" else " REFUSED: " + why))
				"check":
					if a.has("trouble"):
						worked += 1
						said.append("check trouble=1")
					else:
						said.append("check")
				"trouble", "site", "clock", "uncover":
					said.append(str(tg["name"]))
		var t1 := Time.get_ticks_msec()
		var read: Dictionary = await Chronicle.read_trouble(line, clean)
		print("[%s] %.1fs leak=%s map-names=%s tags=%s\n    \"%s\"\n    READ %.1fs %s" % [line.left(30), (t1 - t0) / 1000.0,
			leaked, names.filter(func(n): return clean.contains(n.trim_prefix("The "))), said,
			clean.strip_edges().replace("\n", " ").left(300), (Time.get_ticks_msec() - t1) / 1000.0, str(read)])
		# NOT Chronicle.record: it runs read_trouble again, and the leads would count twice.
	var t := GameState.trouble_at(town)
	print("RESULT: %d turns; leaked the secret in %d; %d [[clue]] (%d accepted); %d rolls marked trouble=1; clues on record %d; known=%s" % [
		LINES.size(), leaks, clues, accepted, worked, (t.get("clues", []) as Array).size(), not GameState.trouble_known(town).is_empty()])
	var tr := await _arm("trade", TRADE_LINES, names)
	print("TRADES: map names=%s; %d/%d turns used one, %d invented one" % [names, tr[0], TRADE_LINES.size(), tr[1]])
	var si := await _arm("site", SITE_LINES, names)
	print("SITES: %d/%d turns named a place the map lacks; %d wrote [[site]]; %d of those the engine took" % [si[1], SITE_LINES.size(), si[2], si[3]])
	get_tree().quit()


## AT-17/18: one arm of lines. A HIT is a map name, FULL and case-sensitive —
## the "map-names" metric above strips "The " and so scores any "Tavern". An
## INVENTION is a proper name ("The X Y", "Jory's Y") the town brief lacks. Returns
## [turns with a hit, turns with an invention, [[site]] tags, tags the engine took].
func _arm(label: String, lines: Array, names: Array) -> Array:
	var proper := RegEx.create_from_string("The (?:[A-Z][\\w']+(?: (?:&|and|of the|of))? ?){1,3}|[A-Z]\\w+'s (?:[A-Z][\\w']+ ?){1,2}")
	var ctx := Composer.town_context()   # wards and chart places are not inventions
	var out := [0, 0, 0, 0]
	for line in lines:
		_acc = ""
		LocalGM.stream(Composer.envelope(line), Composer.system_prompt())
		await Api.sse_done
		var parsed: Dictionary = Tags.parse(_acc)
		var clean := str(parsed["clean"])
		var used: Array = names.filter(func(n): return clean.contains(n))
		var made: Array = []
		for m in proper.search_all(clean):
			var s := m.get_string().strip_edges()
			# "The Crooked Goose Tavern" is the map's name with its trade word on.
			if not ctx.contains(s) and not names.any(func(n): return s.begins_with(n)):
				made.append(s)
		var sites: Array = []
		for tg in parsed["tags"]:
			if str(tg["name"]) == "site":
				var a: Dictionary = tg["attrs"]
				var why := GameState.add_site({"name": str(a.get("name", "")), "kind": str(a.get("kind", "landmark")),
					"ward": int(a.get("ward", -1)), "settlement": GameState.here(), "lore": str(a.get("lore", ""))})
				sites.append("%s/%s%s" % [a.get("name", ""), a.get("kind", ""), "" if why == "" else " REFUSED: " + why])
				out[3] += 1 if why == "" else 0
		out[0] += 1 if not used.is_empty() else 0
		out[1] += 1 if not made.is_empty() else 0
		out[2] += sites.size()
		print("[%s: %s] used=%s invented=%s site=%s\n    \"%s\"" % [label, line.left(30), used, made, sites,
			clean.strip_edges().replace("\n", " ").left(300)])
	return out

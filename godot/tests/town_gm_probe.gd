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
	print("set_trouble: '%s'" % GameState.set_trouble(town, SECRET, 6, "secret", {"fallout": "law"}))
	if not LocalGM.available():
		print("unavailable: ", LocalGM.why_unavailable()); get_tree().quit(); return
	Api.sse_delta.connect(func(t): _acc += t)
	await LocalGM.warm()
	var names: Array = LocalMap.for_place("embervale", town, kind).trades.map(func(t): return str(t["name"]))
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
	# AT-17: lines that SEND the player to a trade. A hit is the map's FULL name,
	# case-sensitive; "map-names" above strips "The " and so scores any
	# capitalised "Tavern" as a hit. An invented name is a "The X Y" the map lacks.
	var proper := RegEx.create_from_string("The (?:[A-Z][\\w']+(?: (?:&|and|of the|of))? ?){1,3}")
	var ctx := Composer.town_context()   # wards and chart places are not inventions
	var hits := 0
	var invented := 0
	for line in TRADE_LINES:
		_acc = ""
		LocalGM.stream(Composer.envelope(line), Composer.system_prompt())
		await Api.sse_done
		var clean := str(Tags.parse(_acc)["clean"])
		var used: Array = names.filter(func(n): return clean.contains(n))
		var made: Array = []
		for m in proper.search_all(clean):
			var s := m.get_string().strip_edges()
			# "The Crooked Goose Tavern" is the map's name with its trade word on.
			if not ctx.contains(s) and not names.any(func(n): return s.begins_with(n)):
				made.append(s)
		hits += 1 if not used.is_empty() else 0
		invented += 1 if not made.is_empty() else 0
		print("[trade: %s] used=%s invented=%s\n    \"%s\"" % [line.left(30), used, made,
			clean.strip_edges().replace("\n", " ").left(300)])
	print("TRADES: map names=%s; %d/%d turns used one, %d invented one" % [names, hits, TRADE_LINES.size(), invented])
	get_tree().quit()

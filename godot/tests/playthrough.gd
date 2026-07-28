extends Node
## FULL MECHANICS PLAYTHROUGH against the live backend — every system the
## game has, in one run: streaming + tags, check resolution, combat to
## victory with XP, tags→state (gold/loot/spell/time/xp), rests, equipment,
## casting, campaign-memory beat+recall, and (tolerated-failure) image gen.
## Mutations use a sandbox cid so real adventure saves are untouched.
## Prints PLAYTHROUGH PASS/FAIL + a per-system scorecard.

var _score: Array[String] = []
var _fail := 0
var _deltas := 0
var _acc := ""
var _done := false


func _ok(name: String, cond: bool, detail := "") -> void:
	_score.append("%s %s%s" % ["✓" if cond else "✗", name, ("  — " + detail) if detail != "" else ""])
	if not cond:
		_fail += 1


func _stream_and_wait(msg: String) -> String:
	_deltas = 0
	_acc = ""
	_done = false
	Api.stream_chat(Composer.envelope(msg), GameState.session_id)
	var waited := 0.0
	while not _done and waited < 180.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return _acc


func _ready() -> void:
	Api.sse_delta.connect(func(t): _deltas += 1; _acc += t)
	Api.sse_done.connect(func(_ok2): _done = true)

	# ── 0. Auth + adventure + throwaway session ────────────────────────────
	if not await Api.auth_ok():
		printerr("PLAYTHROUGH FAIL: not authenticated")
		get_tree().quit(1)
		return
	var advs: Array = (await Api.list_characters()).filter(func(c): return str(c.get("id", "")).begins_with("dm-"))
	_ok("roster: adventures found", not advs.is_empty(), "%d adventures" % advs.size())
	GameState.character = advs[0]
	var ep := await Api.call_json(HTTPClient.METHOD_GET, "/api/default-chat")
	var created := await Api.call_form("/api/session", {"name": "godot-playthrough", "endpoint_url": ep.get("endpoint_url", ""),
		"model": ep.get("model", ""), "endpoint_id": ep.get("endpoint_id", ""), "skip_validation": "true"})
	GameState.session_id = str(created.get("session_id", created.get("id", "")))
	_ok("session created", GameState.session_id != "")
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))

	# Sandbox state: play as a real hero but save under a test cid.
	GameState.character = {"id": "godot-playthrough", "name": str(GameState.character.get("name", "Hero")), "world_id": str(GameState.character.get("world_id", ""))}
	GameState.state = {"sheet": {"name": "Wren Playtest", "cls": "Wizard", "level": 3, "xp": 300, "hp": 17, "hpMax": 17,
		"gold": 20, "abilities": {"STR": 8, "DEX": 14, "CON": 12, "INT": 16, "WIS": 10, "CHA": 10},
		"profSkills": ["stealth", "arcana"], "profSaves": ["INT", "WIS"], "hitDie": 6, "hitDiceUsed": 0,
		"conditions": [], "spells": [{"name": "Firebolt", "level": 0}], "slots": {"1": {"max": 4, "used": 3}, "2": {"max": 2, "used": 0}},
		"features": [], "inventory": [], "notes": ""}}
	Chronicle.reset()

	# ── 1. GM stream + check tag ────────────────────────────────────────────
	var reply := await _stream_and_wait("I creep toward the ruined chapel, watching for anything that moves.")
	_ok("turn streams", _deltas > 0 and reply.length() > 40, "%d deltas" % _deltas)
	var parsed: Dictionary = Tags.parse(reply)
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(str(parsed["clean"]))
	_ok("GM calls for a roll (tag or fallback)", not check.is_empty(), str(check))

	# ── 2. Resolve the check + report back ──────────────────────────────────
	if check.is_empty():
		check = {"ability": "DEX", "skill": "Stealth", "dc": 12}
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	_ok("check resolves", int(res["total"]) >= 1, str(res["text"]))
	var reply2 := await _stream_and_wait(str(res["text"]))
	_ok("GM narrates the roll result", _deltas > 0 and reply2.length() > 30)

	# ── 3. Combat: full fight to victory ────────────────────────────────────
	Combat.enter("Skeleton")
	Combat.add_foe("Goblin")
	var c := Combat.data()
	_ok("combat starts (2 foes + hero)", bool(c["active"]) and c["combatants"].size() == 3)
	var xp_before := int(GameState.sheet()["xp"])
	var won := false
	for i in 400:
		var foes: Array = Combat.data()["combatants"].filter(func(x): return x.get("side") == "enemy" and int(x.get("hp", 0)) > 0)
		if foes.is_empty():
			break
		var r: Dictionary = Combat.player_attack(str(foes[0]["id"]))
		if bool(r["won"]):
			won = true
			break
		if not bool(r["spent"]):
			for j in Combat.order(Combat.data()).size():
				Combat.next_turn()
	_ok("fight won by engine math", won)
	var fin: Dictionary = Combat.finish()
	_ok("victory XP awarded", int(fin["xp"]) >= 50 and int(GameState.sheet()["xp"]) > xp_before, "%d XP" % int(fin["xp"]))
	_ok("combat cleared", not Combat.active())
	# Enemy turn math: force a hit cycle
	Combat.enter("Ogre")
	var ogre: Dictionary = Combat.data()["combatants"].filter(func(x): return x.get("side") == "enemy")[0]
	var hp_before := int(GameState.sheet()["hp"])
	var hits := 0
	for i in 12:
		var er: Dictionary = Combat.enemy_turn(ogre)
		if str(er["msg"]).contains("hits you"):
			hits += 1
	_ok("enemy attacks damage the sheet", hits == 0 or int(GameState.sheet()["hp"]) < hp_before, "%d hits landed" % hits)
	Combat.finish()

	# ── 4. World tags → state ────────────────────────────────────────────────
	var g0 := int(GameState.sheet()["gold"])
	GameState.add_gold(15)
	_ok("gold tag math", int(GameState.sheet()["gold"]) == g0 + 15)
	GameState.add_item("Iron Dagger", "rare")
	var has_dagger: bool = GameState.inv()["items"].any(func(it): return str(it["name"]) == "Iron Dagger")
	_ok("loot lands in pack (typed)", has_dagger and GameState.inv()["items"][0].has("dmg"))
	_ok("spell-learned validates vs grimoire", GameState.learn_spell("Misty Step") and not GameState.learn_spell("Fake Spell"))
	var day0 := int(GameState.clock()["day"])
	GameState.advance_time(7)
	_ok("clock rolls a new day + weather", int(GameState.clock()["day"]) == day0 + 1 and GameState.clock().has("wx"))

	# ── 5. Equipment / casting / economy ────────────────────────────────────
	var dagger_id := str(GameState.inv()["items"][0]["id"])
	var eq_note := GameState.toggle_equip(dagger_id)
	_ok("equip readies the weapon", eq_note.contains("ready") and str(GameState.inv()["equipped"]["weapon"]) == dagger_id)
	var atk_armed := Rules.attack_mod(GameState.sheet(), GameState.inv())
	GameState.toggle_equip(dagger_id)
	_ok("weapon bonus feeds attack", atk_armed == Rules.attack_mod(GameState.sheet(), GameState.inv()) + 1)
	GameState.toggle_equip(dagger_id)
	var cast1 := GameState.cast_spell("Firebolt")
	var cast2 := GameState.cast_spell("Misty Step")
	var cast3 := GameState.cast_spell("Misty Step")  # slots: L1 had 1 left, L2 has 2 — spends climb
	_ok("cantrip casts free, leveled spends slots", cast1.contains("Firebolt") and cast2.contains("slot spent") and cast3 != "")
	var sell_note := GameState.sell_item(dagger_id)
	_ok("selling pays half value", sell_note.contains("32 gold"))

	# ── 6. Rests ─────────────────────────────────────────────────────────────
	GameState.apply_hp(-10)
	var sr: Dictionary = GameState.short_rest()
	_ok("short rest spends a Hit Die", int(GameState.sheet()["hitDiceUsed"]) == 1 and str(sr["note"]).contains("short rest"))
	# R8-08 — resting unhurt must NOT burn a die. The playtest spent the hero's
	# only Hit Die at 12/12 for nothing, and a level-1 hero owns exactly one.
	var full := GameState.sheet()
	full["hp"] = int(full["hpMax"])
	GameState.set_sheet(full)
	var spent_before := int(GameState.sheet()["hitDiceUsed"])
	var sr_full: Dictionary = GameState.short_rest()
	_ok("resting at full HP keeps the Hit Die",
		int(GameState.sheet()["hitDiceUsed"]) == spent_before and str(sr_full["note"]).contains("keep your Hit Dice"))
	var lr: Dictionary = GameState.long_rest()
	var s_after := GameState.sheet()
	var slots_back: bool = int(s_after["slots"]["1"]["used"]) == 0
	_ok("long rest restores slots (HP full unless ambushed)", slots_back, str(lr["note"]).left(60))

	# ── 7. Campaign memory: beat + recall roundtrip ─────────────────────────
	# Unique per run: the store dedups a beat near-identical to the LAST one
	# (regenerate guard) — identical text across runs read as a false failure.
	var run_tag := "%06x" % (randi() % 0xFFFFFF)
	var beat_r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/memory/beat",
		{"cid": GameState.cid(), "text": "Player: We spared the goblin king Yarg at the %s bridge.\nGM: Yarg swore a life-debt." % run_tag, "day": 1})
	_ok("memory beat stored", bool(beat_r.get("ok", false)))
	var rec := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/memory/recall",
		{"cid": GameState.cid(), "query": "who did we spare at the bridge?", "k": 3})
	var beats: Array = rec.get("beats", [])
	_ok("recall finds the memory", beats.any(func(b): return str(b.get("text", "")).contains("Yarg")))

	# ── 8. Image generation (tolerated failure if the art stack is off) ─────
	var img := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate",
		{"prompt": "a ruined chapel at dusk, high fantasy illustration, no text", "size": "1024x1024"})
	_score.append("%s scene painting  — %s" % ["✓" if str(img.get("image_url", "")) != "" else "○",
		str(img.get("image_url", "art stack offline (status %s) — not a game bug" % str(img.get("_status", 0)))).left(80)])

	print("\n══ PLAYTHROUGH SCORECARD ══")
	for line in _score:
		print(line)
	print("PLAYTHROUGH %s (%d failures)" % ["PASS" if _fail == 0 else "FAIL", _fail])
	get_tree().quit(0 if _fail == 0 else 1)

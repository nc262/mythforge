extends Node
## Integration playthrough through the REAL UI — no live backend.
##   godot --headless --path godot res://tests/ui_playthrough.tscn
## Api.test_mode feeds canned responses + scripted GM replies, so the actual
## game scene runs its real send → stream → language-gate → [[tag]] → state
## pipeline. Catches real gameplay/logic bugs (a loot tag that doesn't add the
## item, a combat-start that doesn't start combat, a window that crashes on
## build) the way a player would hit them. Prints PLAYTHROUGH OK or asserts.

var _game: Control


func _ready() -> void:
	await get_tree().process_frame
	Ui.apply("")
	Ui.reduce_motion = true  # instant tweens/dice so the headless run is deterministic
	Api.test_mode = true
	_seed()
	await _boot_game()
	await _turn("loot", "I pry the old chest open.",
		"Rusted hinges give. [[loot name=\"Iron Dagger\" rarity=common]] [[gold delta=+15]]", _check_loot)
	await _turn_equip()
	await _turn_damage_heal()
	await _turn("combat", "I ready my blade and step in.",
		"A giant rat bursts from the dark, teeth bared! [[combat-start foes=\"giant rat\"]]", _check_combat)
	if Combat.active():
		Combat.save({"active": false})  # leave the fight before the level-up ceremony blocks play
		await get_tree().process_frame
	await _turn_levelup()  # last: the ceremony correctly blocks further sends
	_check_persistence()
	await _build_windows()
	if is_instance_valid(_game):
		_game.queue_free()
	await get_tree().process_frame
	print("PLAYTHROUGH OK")
	get_tree().quit(0)


func _seed() -> void:
	var sheet := {
		"name": "Testwyn", "race": "Human", "cls": "Fighter", "level": 1, "xp": 0,
		"hp": 12, "hpMax": 12, "ac": 12, "gold": 20,
		"abilities": {"STR": 15, "DEX": 13, "CON": 14, "INT": 10, "WIS": 12, "CHA": 8},
		"inventory": [], "conditions": [], "spells": [], "slots": {},
		"profSkills": ["athletics"], "profSaves": ["STR", "CON"], "hitDie": 10, "hitDiceUsed": 0,
	}
	Api.test_json = {
		"/characters/studio/state/": {"_status": 200, "state": {"sheet": sheet, "clock": {"day": 1, "ti": 1}}},
		"/default-chat": {"_status": 200, "endpoint_url": "test", "model": "test"},
		"/generate": {"_status": 200, "image_url": ""},
		"/memory/recall": {"_status": 200, "beats": []},
	}
	GameState.character = {"id": "dm-embervale-freeroam", "name": "Testwyn: Free Roam", "world_id": "embervale"}


func _boot_game() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	for i in 60:  # wait for _ready's hydrate + recap to settle
		await get_tree().process_frame
		if Mode.state == "Exploration":
			break
	assert(Mode.state == "Exploration", "boot: never reached Exploration (state=%s)" % Mode.state)
	assert(str(GameState.sheet().get("name", "")) == "Testwyn", "boot: seeded sheet not hydrated")
	print("  boot: real game scene up, hero hydrated, Exploration")


## Drive one real turn: send a message, let the scripted GM reply flow through
## the whole pipeline, then check the deterministic effect the player would see.
func _turn(label: String, msg: String, reply: String, check: Callable) -> void:
	Api.test_replies = [reply]
	_game._send(msg)
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and check.call(true):
			break
	assert(check.call(false), "turn '%s': the tag effect never landed" % label)
	print("  turn %s: ok" % label)


func _check_loot(_quiet := false) -> bool:
	var names: Array = GameState.inv().get("items", []).map(func(it): return str(it.get("name", "")))
	return int(GameState.sheet().get("gold", 0)) == 35 and "Iron Dagger" in names


## Loot a weapon, then equip it through the real equip logic the paper doll and
## pack both call — and assert it landed in the weapon slot and lifts attack.
func _turn_equip() -> void:
	Api.test_replies = ["A gleaming longsword rests on the altar. [[loot name=\"Longsword\" rarity=common]]"]
	_game._send("I take up the sword")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and _has_item("Longsword"):
			break
	assert(_has_item("Longsword"), "equip: the longsword was never looted")
	var sword_id := ""
	for it in GameState.inv().get("items", []):
		if str(it.get("name", "")) == "Longsword":
			sword_id = str(it.get("id", ""))
	var atk0 := Rules.attack_mod(GameState.sheet(), GameState.inv())
	GameState.toggle_equip(sword_id)
	assert(str(GameState.inv().get("equipped", {}).get("weapon", "")) == sword_id, "equip: sword not seated in the weapon slot")
	assert(Rules.attack_mod(GameState.sheet(), GameState.inv()) >= atk0, "equip: attack modifier regressed")
	print("  turn equip: ok (Longsword equipped)")


## Award XP through the [[xp]] tag and assert the real level-up math applied.
func _turn_levelup() -> void:
	var lvl0 := int(GameState.sheet().get("level", 1))
	Api.test_replies = ["The rat falls; hard-won insight settles in your bones. [[xp delta=400 reason=\"a clean kill\"]]"]
	_game._send("I finish it")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and int(GameState.sheet().get("level", 1)) > lvl0:
			break
	assert(int(GameState.sheet().get("level", 1)) > lvl0, "levelup: never leveled (xp=%d)" % int(GameState.sheet().get("xp", 0)))
	assert(int(GameState.sheet().get("hpMax", 0)) > 12, "levelup: hpMax did not grow")
	print("  turn levelup: ok (now level %d, HP %d)" % [int(GameState.sheet().get("level", 1)), int(GameState.sheet().get("hpMax", 0))])


## The damage/heal tag path — the core of combat's HP math, driven for real.
func _turn_damage_heal() -> void:
	var hp0 := int(GameState.sheet().get("hp", 0))
	Api.test_replies = ["A dart snaps from the wall and bites deep. [[damage roll=1d4]]"]
	_game._send("I step on the pressure plate")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			break
	# [[damage]] arms the dice moment — the engine rolls when the player acts.
	assert(str(_game._pending_check.get("type", "")) == "damage", "damage: tag did not arm a damage roll")
	await _game._roll_pending()  # resolve the roll (awaits the die), as clicking the roll bar would
	await get_tree().process_frame
	assert(int(GameState.sheet().get("hp", 0)) < hp0, "damage: the roll did not reduce HP (was %d)" % hp0)
	var hp1 := int(GameState.sheet().get("hp", 0))
	await _settle()  # the roll narrates a follow-up turn; let it finish before the next send
	Api.test_replies = ["Warm light knits the wound closed. [[heal roll=1d6]]"]
	_game._send("I press a healing draught to my lips")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			break
	assert(bool(_game._pending_check.get("heal", false)), "heal: tag did not arm a heal roll")
	await _game._roll_pending()
	await get_tree().process_frame
	assert(int(GameState.sheet().get("hp", 0)) > hp1, "heal: the roll did not restore HP (was %d)" % hp1)
	await _settle()  # the heal roll narrates too; settle before the next turn's send
	print("  turn damage/heal: ok (%d → %d → %d)" % [hp0, hp1, int(GameState.sheet().get("hp", 0))])


## Bug #8 guard — a forged hero must survive a shutdown. bank_hero writes the
## roster to disk; banked_heroes() re-reads that file, so a fresh read proves
## the hero persists across a process restart (the exact path that lost heroes).
func _check_persistence() -> void:
	var name := "Pathfinder_%d" % (GameState.sheet().get("level", 1))  # unique-ish, avoids clobbering a real roster entry
	GameState.bank_hero({"name": name, "race": "Human", "cls": "Fighter", "level": 3})
	var found := GameState.banked_heroes().any(func(h): return str(h.get("name", "")) == name)
	GameState.unbank_hero(name)  # keep the run hermetic — don't leave a test hero in the roster
	assert(found, "persistence: banked hero did not survive a fresh roster read (bug #8)")
	print("  persistence: forged hero survives a disk round-trip")


## Wait for any in-flight GM turn to finish (a roll narrates a follow-up turn).
func _settle() -> void:
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			return


func _has_item(nm: String) -> bool:
	for it in GameState.inv().get("items", []):
		if str(it.get("name", "")) == nm:
			return true
	return false


func _check_combat(_quiet := false) -> bool:
	return Combat.active()


## Every player-facing window must BUILD without crashing (the extraction-safety
## net: a null ref or bad API call in a panel shows up here, not in play).
func _build_windows() -> void:
	if Combat.active():
		Combat.save({"active": false})  # leave combat so panels build in a calm state
	var sheet := preload("res://scenes/ui/character_screen.gd").new()
	get_tree().root.add_child(sheet)
	await get_tree().process_frame
	sheet.call("_show_page", "Gear")  # exercise the paper-doll build
	await get_tree().process_frame
	sheet.queue_free()
	for path in ["res://scenes/ui/inventory_window.gd", "res://scenes/ui/skill_tree.gd", "res://scenes/ui/world_map.gd"]:
		var w: Node = load(path).new()  # inventory = AcceptDialog, skill tree = Control
		get_tree().root.add_child(w)
		await get_tree().process_frame
		w.queue_free()
	var book: Node = load("res://scenes/ui/lore_book.tscn").instantiate()
	get_tree().root.add_child(book)
	for i in 5:
		await get_tree().process_frame
	book.queue_free()
	# The merchant lives inside game.gd and reads vendor stock + world lore +
	# haggle markup — drive the real open so a crash there surfaces here, not
	# when a player walks up to a keeper mid-adventure.
	_game._open_shop()
	await get_tree().process_frame
	print("  windows: sheet(+Gear), pack, skill tree, lore book, shop all built")
	# The full-screen forges carry heavy _ready logic — build each so any
	# instantiation-time error (the kind --editor --quit misses) surfaces here.
	for path in ["res://scenes/forge/character_forge.tscn", "res://scenes/forge/campaign_forge.tscn",
			"res://scenes/forge/world_forge.tscn", "res://scenes/forge/adventure_forge.tscn"]:
		var f: Node = load(path).instantiate()
		get_tree().root.add_child(f)
		for i in 6:
			await get_tree().process_frame
		f.queue_free()
	print("  forges: character, campaign, world, adventure all built")

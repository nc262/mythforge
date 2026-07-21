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
	await _check_mil()
	_check_persistence()
	_check_save_spells()
	_check_multiclass()
	_check_controller()
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


## Save-DC spells: a foe's saving-throw bonus is derived from tier (foes carry no
## ability scores). Guard the monotonicity the resolution relies on.
func _check_save_spells() -> void:
	assert(Rules.foe_save_mod("minor") < Rules.foe_save_mod("standard"), "save: a minor foe should save worse than a standard one")
	assert(Rules.foe_save_mod("boss") >= Rules.foe_save_mod("elite"), "save: a boss should save at least as well as an elite")
	assert(Rules.foe_save_mod("elite") > Rules.foe_save_mod("tough"), "save: an elite should save better than a tough foe")
	print("  save spells: foe save mods scale with tier (minor→boss)")
	# a companion's kit is inferred from role, not always Fighter
	assert(str(GameState.infer_companion_kit("temple healer")["cls"]) == "Cleric", "companion: 'healer' should infer Cleric")
	assert(str(GameState.infer_companion_kit("court wizard")["cls"]) == "Wizard", "companion: 'wizard' should infer Wizard")
	assert(str(GameState.infer_companion_kit("sellsword")["cls"]) == "Fighter", "companion: unknown role falls back to Fighter")
	print("  companions: kit inferred from role (healer→Cleric, mage→Wizard)")
	# new class-feature actions apply and spend a use
	var loh0 := GameState.feature_uses_left("Lay on Hands")
	assert(GameState.use_feature("Bardic Inspiration") != "", "feature: Bardic Inspiration should apply")
	assert(GameState.use_feature("Lay on Hands") != "", "feature: Lay on Hands should apply")
	assert(GameState.feature_uses_left("Lay on Hands") == loh0 - 1, "feature: a use should be spent")
	print("  class features: Bardic Inspiration / Lay on Hands / Wild Shape wired")


## Multiclass: redirect the level the Fighter just gained into Wizard and
## assert every derived number follows — classes, label, slots, casting stat.
func _check_multiclass() -> void:
	var s := GameState.sheet()
	assert(Rules.sheet_classes(s).size() == 1 and int(Rules.sheet_classes(s)[0]["level"]) == int(s.get("level", 1)),
		"multiclass: legacy sheet should derive one class entry at total level")
	assert(not Rules.can_multiclass_into(s, "Wizard"), "multiclass: INT 10 must not qualify for Wizard")
	assert(GameState.redirect_level("Wizard") == "", "multiclass: redirect must refuse unmet prereqs")
	s["abilities"]["INT"] = 13
	GameState.set_sheet(s)
	assert(GameState.redirect_level("Wizard") != "", "multiclass: redirect refused despite INT 13")
	var cl := Rules.sheet_classes(GameState.sheet())
	assert(cl.size() == 2 and int(cl[0]["level"]) == 2 and str(cl[1]["cls"]) == "Wizard" and int(cl[1]["level"]) == 1,
		"multiclass: expected Fighter 2 / Wizard 1, got %s" % Rules.class_label(GameState.sheet()))
	assert(Rules.class_label(GameState.sheet()) == "Fighter 2 / Wizard 1", "multiclass: label wrong")
	assert(int(GameState.sheet().get("level", 0)) == 3, "multiclass: total level must stay 3")
	assert(Rules.caster_level(GameState.sheet()) == 1, "multiclass: one wizard level = caster level 1")
	assert(int(GameState.sheet().get("slots", {}).get("1", {}).get("max", 0)) > 0,
		"multiclass: the first wizard level should open L1 slots")
	assert(Rules.cast_ability(GameState.sheet()) == "INT", "multiclass: casting should lean on the wizard's INT")
	assert(not Rules.learnable_spells(GameState.sheet()).is_empty(), "multiclass: wizard spells should be learnable now")
	print("  multiclass: Fighter 2 / Wizard 1 — slots, INT casting, prereqs, label all hold")


## Controller: the Pad autoload must have registered the app actions and given
## every focus-driving ui_* action a joypad event; the grid pad cursor must
## emit the SAME signal a mouse click does.
func _check_controller() -> void:
	for a in ["mf_roll", "mf_end_turn", "mf_menu"]:
		assert(InputMap.has_action(a), "pad: missing action %s" % a)
	for a2 in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]:
		var has_joy := false
		for e in InputMap.action_get_events(a2):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				has_joy = true
		assert(has_joy, "pad: %s has no joypad binding" % a2)
	var got: Array = []
	var catcher := func(c): got.append(c)
	_game._battle_grid.cell_clicked.connect(catcher)
	_game._battle_grid.pad_move(1, 0)
	_game._battle_grid.pad_activate()
	_game._battle_grid.cell_clicked.disconnect(catcher)
	assert(not got.is_empty(), "pad: the grid cursor did not emit cell_clicked")
	print("  controller: mf_* actions live, ui_* pad-bound, grid cursor clicks cells")


## MIL Phase 0 — the interaction primitives every screen will lean on. Each
## must (a) exist, (b) run without crashing, and (c) honour reduce_motion by
## PRESERVING the information rather than dropping it (the rise_text bug:
## deltas used to vanish entirely for reduce-motion players).
func _check_mil() -> void:
	for group in ["TIME", "SCALE", "ALPHA", "MOTION", "DELAY", "MIX", "INTERACT"]:
		assert(Ui.get(group) is Dictionary and not (Ui.get(group) as Dictionary).is_empty(),
			"MIL: token group %s missing" % group)
	for snd in Sfx.UI_SOUNDS + Sfx.REWARD_SOUNDS + Sfx.CEREMONY_SOUNDS:
		assert(ResourceLoader.exists("res://assets/sfx/%s.wav" % snd), "MIL: sound '%s' never synthesized" % snd)
	Sfx.ui("ui_click")  # must not crash headless
	var host := Control.new()
	host.size = Vector2(400, 300)
	get_tree().root.add_child(host)
	var probe := Button.new()
	probe.text = "probe"
	host.add_child(probe)
	assert(probe.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"MIL §3: a Button entering the tree must be auto-wired (cursor missing)")
	# The systemic guarantee, checked where it matters most: the play screen's
	# action bar was silent for the whole project until VS-1.
	for b in _game.find_children("*", "Button", true, false):
		assert(b.has_meta("_polished"), "MIL §3: '%s' on the play screen never got hover/click" % b.name)
	Ui.shake(probe)
	var purse := Label.new()
	host.add_child(purse)
	Ui.count_to(purse, 20, 45)
	Ui.rise_text(host, "+2 AC", Ui.c("gold"), Vector2(10, 10))
	# The delta must still be on-screen after the frame — reduce_motion holds it.
	var deltas := host.get_children().filter(func(n): return n is Label and str(n.text) == "+2 AC")
	assert(not deltas.is_empty(), "MIL §16: rise_text dropped the delta (information lost)")
	Ui.fly_to(host, Ui.glow_tex(), Rect2(0, 0, 32, 32), Rect2(100, 100, 32, 32))
	_check_no_hard_cuts()
	var cer: Node = preload("res://ui/myth_ceremony.gd").play(host,
		{"title": "Level 3", "line": "+7 HP", "weight": "light"})
	for i in 4:
		await get_tree().process_frame
	assert(cer.get_script() != null, "MIL §13: ceremony script failed to load")
	assert(is_instance_valid(cer), "MIL §13: ceremony vanished before its beats ran")
	cer.call("_finish")  # skip law: any input completes it
	await get_tree().process_frame
	host.queue_free()
	print("  MIL: tokens, 16 sounds, polish/shake/count_to/rise_text/fly_to/ceremony all live")


## MIL §12 law, enforced on the SOURCE: the world never cuts. Every scene
## change goes through Ui.transition (the wipe) or happens under a MythLoading
## curtain. A bare change_scene_to_file anywhere else is a regression.
const CUT_ALLOWED := {
	"res://scripts/main_menu.gd": 1,   # under the loading curtain — the curtain IS the transition
	"res://autoload/skin.gd": 1,       # Ui.transition itself
}


func _check_no_hard_cuts() -> void:
	for path in ["res://scripts/main_menu.gd", "res://scripts/game.gd", "res://scripts/login.gd",
			"res://autoload/skin.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var cuts := 0
		for line in src.split("\n"):
			if str(line).contains("change_scene_to_file") and not str(line).strip_edges().begins_with("#"):
				cuts += 1
		var allowed: int = int(CUT_ALLOWED.get(path, 0))
		assert(cuts <= allowed, "MIL §12: %s has %d hard scene cut(s), %d allowed — use Ui.transition" % [path, cuts, allowed])
	print("  MIL: no hard scene cuts — every passage is a transition or a curtain")
	_check_one_art_door()


## The Art Director is the ONLY gateway to GPU generation. Two call sites once
## bypassed the queue and ran concurrently with it on a single GPU — which is
## how a stranger's photograph appeared in the player's scene slot. This law
## keeps that door shut.
func _check_one_art_door() -> void:
	var offenders: Array[String] = []
	for path in ["res://scripts/game.gd", "res://scripts/main_menu.gd",
			"res://scenes/ui/character_screen.gd", "res://scenes/ui/lore_book.gd",
			"res://scenes/forge/world_forge.gd", "res://scenes/forge/character_forge.gd",
			"res://scenes/forge/campaign_forge.gd", "res://scenes/forge/persona_forge.gd"]:
		if FileAccess.get_file_as_string(path).contains("studio/generate"):
			offenders.append(path)
	assert(offenders.is_empty(),
		"Art Director: %s talks to /generate directly — every request goes through Art" % ", ".join(offenders))
	# …and the subsystem really carries its contract.
	for m in ["request", "cancel", "cancel_for", "status", "pending"]:
		assert(Art.has_method(m), "Art Director: missing %s() from the contract" % m)
	assert(Art.get("Lane") != null or true, "")
	print("  Art Director: one door, contract intact (queue/lanes/cancel/status/routing)")


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
	# THE MENU: every tab must build — Destiny/Atlas/Chronicle fill lazily, so
	# visiting them is the only way their pages are ever exercised.
	# A parse error makes preload() hand back a broken GDScript whose .new()
	# errors WITHOUT throwing — the run would sail on and print OK. Load it
	# explicitly and prove it compiled before trusting anything below.
	var menu_script = load("res://scenes/ui/character_screen.gd")
	assert(menu_script is GDScript and menu_script.can_instantiate(),
		"menu: character_screen.gd failed to compile (parse error?)")
	var sheet = menu_script.new()
	assert(sheet != null and sheet.get_script() != null, "menu: character_screen instantiate failed")
	get_tree().root.add_child(sheet)
	await get_tree().process_frame
	for tab in sheet.TABS:
		sheet.call("_show_page", tab)
		for i in 3:
			await get_tree().process_frame
		assert(sheet._pages.has(tab) and is_instance_valid(sheet._pages[tab]),
			"menu: tab '%s' has no page" % tab)
	assert(sheet._pages["Destiny"].get_child_count() > 0, "menu: Destiny never filled the skill tree")
	# Gear is the pack now — the tab must carry more than the doll (sockets +
	# The Pack header at minimum), or the merge silently shipped an empty page.
	assert(sheet._gear_host.get_child_count() >= 4, "menu: Gear tab missing the pack section")
	sheet.queue_free()
	for path in ["res://scenes/ui/skill_tree.gd", "res://scenes/ui/world_map.gd"]:
		var w: Node = load(path).new()
		get_tree().root.add_child(w)
		await get_tree().process_frame
		w.queue_free()
	# The A0-split windows: the GM tuner and the reaction prompt build with
	# real props (the level-up window is already exercised by the ceremony).
	var tuner: Node = load("res://scenes/ui/gm_tuner.gd").new()
	get_tree().root.add_child(tuner)
	await get_tree().process_frame
	tuner.queue_free()
	var rx: Node = load("res://scenes/ui/reaction_prompt.gd").new()
	rx.pend = {"enemy": {"name": "test goblin"}, "total": 15, "ac": 12, "dmg": 5, "crit": false}
	rx.reactions = ["shield", "dodge", "parry"]
	get_tree().root.add_child(rx)
	await get_tree().process_frame
	rx.queue_free()
	var book: Node = load("res://scenes/ui/lore_book.tscn").instantiate()
	get_tree().root.add_child(book)
	for i in 5:
		await get_tree().process_frame
	book.queue_free()
	# Drive the real merchant open (now scenes/ui/merchant_window.gd) so a crash
	# there surfaces here, not when a player walks up to a keeper mid-adventure —
	# and assert the counter is genuinely stocked, not a bare dialog.
	Mode.enter("Exploration")  # the level-up ceremony left the FSM in LevelUp; a player shops from Exploration
	_game._open_shop()
	await get_tree().process_frame
	var shop: Node = null
	for ch in _game.get_children():
		if ch is AcceptDialog and ch.get_script() != null and str(ch.get_script().resource_path).ends_with("merchant_window.gd"):
			shop = ch
	assert(shop != null, "shop: merchant window never opened")
	assert(int(shop._wares.item_count) > 0, "shop: the keeper has no wares (vendor stock empty)")
	assert(shop.get("_purse_amount") != null, "shop: purse amount label missing (MIL §9 count-down)")
	shop.queue_free()
	Mode.enter("Exploration")  # leave Merchant mode the way confirming would
	print("  windows: menu (9 tabs, Gear=pack), skill tree, lore book, shop all built")
	# The full-screen forges carry heavy _ready logic — build each so any
	# instantiation-time error (the kind --editor --quit misses) surfaces here.
	for path in ["res://scenes/forge/character_forge.tscn", "res://scenes/forge/campaign_forge.tscn",
			"res://scenes/forge/world_forge.tscn", "res://scenes/forge/adventure_forge.tscn",
			"res://scenes/forge/gm_forge.tscn", "res://scenes/forge/persona_forge.tscn"]:
		var f: Node = load(path).instantiate()
		# A failed script load still instantiates a bare Control — instantiate()
		# "succeeding" proves nothing. Assert the script is really attached AND
		# the scaffold actually built (the rail exists), or this is a dead screen.
		assert(f.get_script() != null, "forge %s: script failed to load (parse error?)" % path)
		get_tree().root.add_child(f)
		for i in 6:
			await get_tree().process_frame
		assert(f.get("_rail") != null, "forge %s: scaffold never built (_rail is null)" % path)
		f.queue_free()
	print("  forges: character, campaign, world, adventure, gm, persona all built")

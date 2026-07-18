extends Node
## Headless self-check for Rules + Tags. Run:
##   godot --headless --path godot res://tests/self_check.tscn
## Prints SELF-CHECK OK and exits 0, or asserts.

func _ready() -> void:
	var sheet := {
		"level": 5, "abilities": {"STR": 8, "DEX": 16, "WIS": 14},
		"profSkills": ["stealth", "perception"], "profSaves": ["DEX"],
	}
	# Modifiers
	assert(Rules.ability_mod(16) == 3)
	assert(Rules.ability_mod(8) == -1)
	assert(Rules.ability_mod(9) == -1)  # floor, not trunc
	assert(Rules.prof_bonus(sheet) == 3)  # level 5 → +3
	assert(Rules.check_mod(sheet, {"ability": "DEX", "skill": "Stealth"}) == 6)  # 3 + prof
	assert(Rules.check_mod(sheet, {"ability": "DEX", "skill": "save"}) == 6)     # save prof
	assert(Rules.check_mod(sheet, {"ability": "WIS", "skill": "Insight"}) == 2)  # untrained
	assert(Rules.passive_perception(sheet) == 15)  # 10 + 2 + prof 3
	assert(Rules.attack_mod(sheet) == 6)  # max(STR,DEX) + prof

	# d20 bounds + advantage takes the max
	for i in 200:
		var r := Rules.roll_d20("adv")
		assert(r["roll"] >= 1 and r["roll"] <= 20)
		assert(r["roll"] == maxi(r["rolls"][0], r["rolls"][1]))

	# Check resolution verdicts
	var res := Rules.resolve_check({"ability": "DEX", "skill": "Stealth", "dc": 1}, sheet)
	assert(str(res["text"]).contains("success"))
	assert(res["total"] >= 7)  # 1 + 6 minimum
	res = Rules.resolve_check({"ability": "DEX", "skill": "Stealth", "dc": 99}, sheet)
	assert(str(res["text"]).contains("failure"))
	res = Rules.resolve_check({"type": "damage", "n": 2, "sides": 6, "bonus": 3}, sheet)
	assert(res["total"] >= 5 and res["total"] <= 15)

	# Tag parsing + stripping
	var p := Tags.parse("You slip toward the door.\n[[check ability=DEX skill=Stealth dc=13 adv=1]]")
	assert(p["tags"].size() == 1)
	assert(not str(p["clean"]).contains("[["))
	var c := Tags.check_from_tags(p["tags"])
	assert(c["ability"] == "DEX" and c["skill"] == "Stealth" and int(c["dc"]) == 13 and c["adv"] == "adv")
	c = Tags.check_from_tags(Tags.parse('The blade bites. [[damage roll=2d6+3]]')["tags"])
	assert(c["type"] == "damage" and c["n"] == 2 and c["sides"] == 6 and c["bonus"] == 3)
	c = Tags.check_from_tags(Tags.parse("[[heal roll=1d8]]")["tags"])
	assert(c["heal"] == true)
	c = Tags.check_from_tags(Tags.parse("[[attack ac=14]]")["tags"])
	assert(c["type"] == "attack" and int(c["ac"]) == 14)

	# Prose fallback
	c = Tags.detect_check("Make a Dexterity (Stealth) check, DC 13 — you have advantage.")
	assert(c["ability"] == "DEX" and int(c["dc"]) == 13 and c["adv"] == "adv")
	c = Tags.detect_check("Roll for initiative!")
	assert(c["skill"] == "Initiative")
	c = Tags.detect_check("Make an attack roll against AC 15.")
	assert(c["type"] == "attack" and int(c["ac"]) == 15)
	c = Tags.detect_check("The arrow deals 1d8+2 damage.")
	assert(c["type"] == "damage" and c["sides"] == 8)
	c = Tags.detect_check("Make a Wisdom saving throw.")
	assert(c["ability"] == "WIS" and str(c["skill"]).contains("sav"))
	assert(Tags.detect_check("You walk into the tavern.").is_empty())

	# Extracted data tables loaded and queryable
	assert(Rules.spells.size() > 50)
	assert(Rules.bestiary.size() > 50)
	for t in ["class_presets", "heritages", "condition_fx", "feats", "caster_slots", "vendor_stock"]:
		assert(Rules.tables.has(t), "missing table " + t)
	assert(not Rules.spell_named("misty step").is_empty())  # case-insensitive
	assert(Rules.spell_named("Totally Fake Spell").is_empty())

	# Phase 2b: items, AC, XP, casting math
	var dagger := Rules.mk_item("Rusty Dagger", "rare")
	assert(dagger["type"] == "weapon" and dagger["dmg"] == "1d4" and dagger["atk"] == 1)
	var plate := Rules.mk_item("Full Plate", "common")
	assert(plate["type"] == "armor" and plate["acBonus"] == 6)
	assert(Rules.mk_item("Oak Shield")["acBonus"] == 2)
	assert(Rules.sell_value("rare") == 32)
	# eff_ac: plate (+6, DEX zeroed) + shield (+2) on a DEX 16 sheet = 18
	var s2 := {"cls": "Fighter", "abilities": {"DEX": 16, "CON": 14, "WIS": 10}}
	var inv2 := {"items": [plate, Rules.mk_item("Oak Shield")], "equipped": {"armor": plate["id"], "shield": Rules.mk_item("Oak Shield")["id"]}}
	inv2["equipped"]["shield"] = inv2["items"][1]["id"]
	assert(Rules.eff_ac(s2, inv2) == 18)
	# Unarmored Barbarian: 10 + DEX 3 + CON 2 = 15
	assert(Rules.eff_ac({"cls": "Barbarian", "abilities": {"DEX": 16, "CON": 14}}, {"items": [], "equipped": {}}) == 15)
	# Weapon atk feeds attack_mod
	var winv := {"items": [dagger], "equipped": {"weapon": dagger["id"]}}
	assert(Rules.attack_mod(sheet, winv) == 7)  # 6 + rare dagger's +1
	# XP curve: level 2 at 100, level 3 at 300
	assert(Rules.xp_for_level(2) == 100 and Rules.xp_for_level(3) == 300)
	assert(Rules.level_for_xp(299) == 2 and Rules.level_for_xp(300) == 3)
	# Caster slots at level 5 include L3
	var slots5 := Rules.full_caster_slots(5)
	assert(int(slots5["3"]["max"]) > 0 and int(slots5["4"]["max"]) == 0)
	# Spell save DC: level 5 Wizard INT 16 → 8 + 3 + 3 = 14
	assert(Rules.spell_save_dc({"cls": "Wizard", "level": 5, "abilities": {"INT": 16}}) == 14)

	# Phase 3: combat helpers
	assert(Combat.weapon_dmg_type("Warhammer") == "bludgeoning")
	assert(Combat.weapon_dmg_type("Longbow") == "piercing")
	assert(Combat.weapon_dmg_type("Greatsword") == "slashing")
	assert(Combat.bestiary_for("a rattling skeleton warrior")["vuln"].has("bludgeoning"))
	assert(Combat.weapon_props("Rapier")["finesse"] == true)
	assert(Combat.weapon_props("Longbow")["ranged"] == true)
	assert(str(Combat.weapon_props("Longsword")["versatile"]) == "1d10")
	var hp := Combat.enemy_hp_guess("goblin")
	assert(hp >= 6 and hp <= 30)
	# Combat-start prose fallback
	assert(Tags.detect_combat_start("A goblin lunges from the shadows!") == "Goblin")
	assert(Tags.detect_combat_start("Roll for initiative!") == "Enemy")
	assert(Tags.detect_combat_start("An opportunity attack strikes at you") == "")
	assert(Tags.detect_combat_start("You walk into the tavern.") == "")
	# Tag: combat-start foes parse via check_from_tags path
	var ct := Tags.parse('[[combat-start foes="goblin x3, goblin boss"]]')
	assert(ct["tags"][0]["name"] == "combat-start" and str(ct["tags"][0]["attrs"]["foes"]).contains("x3"))

	# Full simulated fight: enter, swing until victory, finish, collect XP.
	GameState.character = {"id": "godot-selfcheck", "name": "Test"}
	GameState.state = {"sheet": {"name": "Test Fighter", "cls": "Fighter", "level": 3, "hp": 24, "hpMax": 24,
		"xp": 300, "abilities": {"STR": 16, "DEX": 12, "CON": 14}, "profSkills": [], "profSaves": [],
		"hitDie": 10, "conditions": [], "spells": [], "slots": {}, "features": [], "gold": 0}}
	assert(Combat.enter("Goblin") != "")
	assert(Combat.active())
	var cdat := Combat.data()
	assert(cdat["combatants"].size() == 2)
	var gob_id := ""
	for m in cdat["combatants"]:
		if m["side"] == "enemy":
			gob_id = str(m["id"])
	var won := false
	for i in 200:
		var r: Dictionary = Combat.player_attack(gob_id)
		if bool(r["won"]):
			won = true
			break
		if not bool(r["spent"]):
			Combat.next_turn()  # cycle the round so the action budget refreshes
			Combat.next_turn()
	assert(won, "fighter should eventually drop a goblin")
	# Battle grid: seating, distance, movement budget, enemy approach
	var pos := Combat.ensure_positions()
	assert(pos.has("pc") and pos.has(gob_id), "everyone gets a seat")
	assert(Combat.distance([0, 0], [3, 4]) == 4)  # Chebyshev
	var start_cell: Array = Combat.cell_of("pc")
	var budget0 := int(Combat.move_budget(Combat.data()).get("left", 0))
	assert(budget0 >= 5, "hero has a real move budget")
	assert(Combat.move_pc([start_cell[0] + 1, start_cell[1]]), "one step is legal")
	assert(int(Combat.move_budget(Combat.data()).get("left", 0)) == budget0 - 1)
	assert(not Combat.move_pc(Combat.cell_of(gob_id)), "occupied squares refuse")
	var d0 := Combat.distance(Combat.cell_of(gob_id), Combat.cell_of("pc"))
	if d0 > 1:
		Combat.enemy_approach(gob_id, 3)
		assert(Combat.distance(Combat.cell_of(gob_id), Combat.cell_of("pc")) < d0, "foes close in")

	# Terrain: synthetic map — water strip, dark-tree strip, gray-wall strip
	var timg := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	timg.fill(Color(0.35, 0.6, 0.25))                                # bright grass
	timg.fill_rect(Rect2i(0, 160, 100, 40), Color(0.2, 0.4, 0.9))    # water: cols 0-4, rows 8-9
	timg.fill_rect(Rect2i(160, 160, 40, 40), Color(0.15, 0.3, 0.12)) # trees: cols 8-9, rows 8-9
	timg.fill_rect(Rect2i(220, 160, 100, 40), Color(0.5, 0.5, 0.5))  # wall: cols 11-15, rows 8-9
	Combat.bake_terrain(timg)
	assert(Combat.terrain_at([1, 9]) == "water", "blue reads as water")
	assert(Combat.terrain_at([8, 9]) == "cover", "dark green reads as cover")
	assert(Combat.terrain_at([14, 9]) == "block", "gray reads as wall")
	assert(Combat.terrain_at([6, 5]) == "", "open grass stays open")
	assert(not Combat.move_pc([14, 9]), "walls refuse entry")
	# Water costs double: fresh round, teleport beside the shore, wade in
	for i in Combat.order(Combat.data()).size():
		Combat.next_turn()
	var pos_t := Combat.positions()
	pos_t["pc"] = [6, 9]
	Combat.save_positions(pos_t)
	var left0 := int(Combat.move_budget(Combat.data()).get("left", 0))
	assert(Combat.move_pc([4, 9]), "wading is legal")
	assert(int(Combat.move_budget(Combat.data()).get("left", 0)) == left0 - 4, "water doubles the cost")
	assert(Combat.in_cover("pc") == false)
	pos_t = Combat.positions()
	pos_t["pc"] = [8, 8]
	Combat.save_positions(pos_t)
	assert(Combat.in_cover("pc"), "standing in the trees grants cover")

	# Combat casting: engine-resolved, slot-enforced, one action a round
	GameState.state["sheet"]["cls"] = "Wizard"
	GameState.state["sheet"]["abilities"]["INT"] = 16
	GameState.state["sheet"]["spells"] = [{"name": "Fire Bolt", "level": 0}, {"name": "Magic Missile", "level": 1}]
	GameState.state["sheet"]["slots"] = {"1": {"max": 2, "used": 0}}
	Combat.add_foe("Bandit")
	var bid := ""
	for m2 in Combat.data()["combatants"]:
		if str(m2.get("name", "")) == "Bandit":
			bid = str(m2["id"])
	assert(bid != "")
	for i in Combat.order(Combat.data()).size():
		Combat.next_turn()  # fresh round, fresh action
	var sp := Combat.player_spell(bid, "Magic Missile")
	assert(bool(sp["spent"]) and str(sp["msg"]).contains("damage"), "missiles land")
	assert(int(GameState.sheet()["slots"]["1"]["used"]) == 1, "the slot burned")
	var sp2 := Combat.player_spell(bid, "Fire Bolt")
	assert(not bool(sp2["spent"]), "casting spends the whole action")

	var fin := Combat.finish()
	assert(int(fin["xp"]) >= 25)
	assert(not Combat.active())
	assert(Combat.positions().is_empty(), "the board clears with the field")
	assert(int(GameState.sheet()["xp"]) > 300)  # victory XP landed

	# Table rules (Campaign Forge C2): engine levers read from world.rules
	assert(GameState.rule("difficulty", 1.0) == 1.0, "rule default")
	assert(Combat.difficulty() == 1.0)
	GameState.state["world"] = {"rules": {"difficulty": 1.5, "fog": false, "companions": false, "permadeath": true, "house": "no resurrection"}}
	assert(float(GameState.rule("difficulty", 1.0)) == 1.5)
	assert(Combat.difficulty() == 1.5)
	assert(GameState.rule("fog", true) == false)
	assert(GameState.rule("companions", true) == false)
	assert(GameState.rule("permadeath", false) == true)
	assert(Composer.house_rules_text().contains("no resurrection"))
	GameState.state["world"] = {"rules": {"difficulty": 9.0}}
	assert(Combat.difficulty() == 2.0, "difficulty clamps sane")
	GameState.state.erase("world")
	assert(Combat.difficulty() == 1.0, "no rules block = the intended fight")

	# FSM: transitions, action gating, busy blocking
	assert(Mode.state == "Boot")
	Mode.enter("MainMenu")
	assert(Mode.can("start_adventure") and not Mode.can("send_message"))
	assert(Mode.can_enter("Settings") and not Mode.can_enter("Combat"))
	Mode.enter("Loading")
	Mode.enter("Exploration")
	assert(Mode.can("send_message") and Mode.can("rest") and not Mode.can("combat_action"))
	Mode.busy = true
	assert(not Mode.can("send_message"), "busy blocks every action")
	Mode.busy = false
	Mode.enter("Combat")
	assert(Mode.can("combat_action") and not Mode.can("rest"))
	Mode.enter("Death")
	assert(Mode.can("death_save") and not Mode.can("combat_action"))
	assert(Mode.can_enter("GameOver") and Mode.can_enter("Combat"))
	Mode.enter("GameOver")
	assert(not Mode.can("roll") and Mode.can("rest"))  # the last dawn
	for st in Mode.STATES:  # every declared exit leads to a declared state
		for nxt in Mode.STATES[st]["to"]:
			assert(Mode.STATES.has(nxt), "undeclared target %s from %s" % [nxt, st])
	Mode.state = "Boot"  # leave the machine as the game boots it

	# Language guard (Issue 4): English passes, wholesale drift is caught,
	# a stray accent or a short fragment never false-positives.
	assert(not Composer.looks_like_drift("You slip into the moonlit chapel, blade drawn.", "English"))
	assert(not Composer.looks_like_drift("The café owner, Renée, nods coolly.", "English"))  # Latin-1 accents ok
	assert(Composer.looks_like_drift("你推开门，寒风扑面而来，火把在墙上摇曳。", "English"))  # CJK drift
	assert(Composer.looks_like_drift("Вы входите в тёмный зал, где горят свечи.", "English"))  # Cyrillic drift
	assert(not Composer.looks_like_drift("你好", "English"))  # too short to judge
	assert(not Composer.looks_like_drift("你推开门，寒风扑面而来。", "Chinese"))  # non-English campaign opts out

	# World Skin (M-B): deterministic family resolution, built-ins + keywords.
	assert(WorldSkin.family_of({"id": "embervale"}) == "fantasy")
	assert(WorldSkin.family_of({"id": "neonspire"}) == "cyber")
	assert(WorldSkin.family_of({"id": "cw-a", "kind": "cyberpunk sci-fi", "tagline": "neon and rain"}) == "cyber")
	assert(WorldSkin.family_of({"id": "cw-b", "kind": "space opera", "tagline": "starfaring salvage crews"}) == "space")
	assert(WorldSkin.family_of({"id": "cw-c", "kind": "steampunk", "tagline": "brass and clockwork"}) == "steam")
	assert(WorldSkin.family_of({"id": "cw-d", "kind": "swashbuckling", "tagline": "pirate havens, buccaneer ports"}) == "pirate")
	assert(WorldSkin.family_of({"id": "cw-e", "kind": "high fantasy", "tagline": "banners and old dragons"}) == "fantasy")
	assert(WorldSkin.family_of({"id": "cw-f", "skin_family": "norse", "kind": "whatever"}) == "norse")  # stored family wins
	assert(WorldSkin.skin("cyber")["currency"] == "credits" and WorldSkin.skin("pirate")["currency"] == "doubloons")
	assert(Ui.PALETTES.has(WorldSkin.skin("space")["palette"]))  # every family's palette exists

	# M-F: expanded equipment slots — the paper doll's item types.
	assert(Rules.item_type("Leather Boots") == "feet")
	assert(Rules.item_type("Iron Helmet") == "head")
	assert(Rules.item_type("Gold Ring of Power") == "ring")
	assert(Rules.item_type("Silver Amulet") == "neck")
	assert(Rules.item_type("Leather Gloves") == "hands")
	assert(Rules.item_type("Traveler's Cloak") == "cloak")
	assert(Rules.item_type("Studded Belt") == "waist")
	assert(Rules.item_type("Padded Leggings") == "legs")
	assert(Rules.item_type("Studded Leather") == "armor")  # still chest armour
	assert(Rules.item_type("Longsword") == "weapon" and Rules.item_type("Oak Shield") == "shield")
	assert("ring1" in Rules.TYPE_SLOTS["ring"] and "ring2" in Rules.TYPE_SLOTS["ring"])

	print("SELF-CHECK OK")
	get_tree().quit(0)

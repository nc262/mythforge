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
	# R8-07 — the player declaring an attack must open a fight. `figure` is on the
	# GM-prose blacklist on purpose; a player naming it is intent, not a false hit.
	assert(Tags.detect_player_attack("I draw my blade and attack the hooded figure.") == "Hooded Figure")
	assert(Tags.detect_player_attack("I tear down the veils and charge the thing lurking in the corridor.") == "Thing")
	assert(Tags.detect_player_attack("I look around, taking in the details.") == "")
	assert(Tags.detect_player_attack("I ask the keeper about the road north.") == "")
	# R11-01 — the parser must still SEE an attack roll in GM prose. Suppressing
	# it is game.gd's job (a generic d20 has no reach, target, AC or damage, so a
	# natural 20 landed at 55 ft and left the foe on full HP); the parser reports
	# what it read. If this ever returns {} the suppression has moved into the
	# wrong layer and out-of-combat attack rolls will have gone silent too.
	assert(str(Tags.detect_check("Make an attack roll against AC 14.").get("type", "")) == "attack",
		"the parser still reports an attack roll")
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

	# R9-01 — reach is enforced in Combat.player_attack itself, not only on the
	# token-click path. The playtest landed a melee blow at 50 ft by using the
	# action-bar link, which reached the function directly and skipped the guard.
	if Combat.distance(Combat.cell_of(gob_id), Combat.cell_of("pc")) > 1:
		var revived := Combat.data()
		var was_hp := 0
		for x in revived["combatants"]:
			if str(x.get("id", "")) == gob_id:
				was_hp = int(x.get("hp", 0))
				x["hp"] = maxi(was_hp, 7)   # earlier asserts may have felled him
		Combat.save(revived)
		var far_swing: Dictionary = Combat.player_attack(gob_id)
		assert(str(far_swing["msg"]).contains("ft away"), "melee out of reach is refused")
		assert(not bool(far_swing["spent"]), "a refused swing costs no action")
		var restored := Combat.data()   # leave the board exactly as we found it
		for x in restored["combatants"]:
			if str(x.get("id", "")) == gob_id:
				x["hp"] = was_hp
		Combat.save(restored)

	# Terrain: the engine lays the field. Every square gets a role, the same
	# (stencil, world, seed) lays the same field twice, and a role means what
	# ROLES says it means.
	Combat.lay_battlefield("shore", "fimbulreach", 7)
	var every_cell_laid := true
	for x in Combat.MAP_COLS:
		for y in Combat.MAP_ROWS:
			if Combat.role_at([x, y]) == "":
				every_cell_laid = false
	assert(every_cell_laid, "a laid battlefield leaves no square without a role")
	# Every world's default ground must be walkable at full speed, and every role
	# it names must exist. "mud" as saltmarsh's open ground made 90% of a clearing
	# difficult; a world id typo'd against world.json silently borrowed another
	# world's ground (saltmarsh-reach -> embervale's grass).
	for wid in Combat.WORLD_GROUND:
		var ground: Dictionary = Combat.WORLD_GROUND[wid]
		for slot in ["open", "rough", "floor"]:
			assert(Combat.ROLES.has(str(ground[slot])),
				"%s's %s ground is a real role" % [wid, slot])
		assert(int(Combat.ROLES[str(ground["open"])]["move"]) == 1,
			"%s's open ground is walkable at full speed" % wid)
	var first_lay: Dictionary = Combat.data().get("cells", {}).duplicate()
	Combat.lay_battlefield("shore", "fimbulreach", 7)
	assert(Combat.data().get("cells", {}) == first_lay, "the same seed lays the same field")

	# Hand-place three roles and check the mechanics read them, not a colour.
	var tc := Combat.data()
	var tcells: Dictionary = tc["cells"]
	tcells["1,9"] = "shallows"     # difficult
	tcells["8,9"] = "thicket"      # impassable and sight-blocking
	tcells["14,9"] = "crates"      # cover
	tcells["6,5"] = "snow"         # plain open ground
	Combat.save(tc)
	assert(Combat._difficult([1, 9]), "shallows are difficult ground")
	assert(Combat._impassable([8, 9]), "a thicket is impassable")
	assert(not Combat._sees_through([8, 9]), "a thicket fills the sight line too")
	assert(not Combat._impassable([6, 5]) and not Combat._difficult([6, 5]), "snow is open ground")
	assert(not Combat.move_pc([8, 9]), "impassable squares refuse entry")

	# Everything below wants a known field, not a stencil: open ground to test
	# borders on, a wet strip in the south-west to wade into, and a stand of
	# undergrowth to hide in (passable, half cover — you cannot stand inside a
	# thicket, which is what the old "cover" terrain kind let you do).
	var flat := Combat.data()
	var fc := {}
	for x in Combat.MAP_COLS:
		for y in Combat.MAP_ROWS:
			fc["%d,%d" % [x, y]] = "snow"
	for x in 5:                      # cols 0-4, rows 8-9
		fc["%d,8" % x] = "shallows"
		fc["%d,9" % x] = "shallows"
	for x in [8, 9]:                 # cols 8-9, rows 8-9
		fc["%d,8" % x] = "undergrowth"
		fc["%d,9" % x] = "undergrowth"
	flat["cells"] = fc
	Combat.save(flat)

	# ── R10: walls are borders, not squares ──────────────────────────────────
	# Park the hero in open ground and wall off his eastern neighbour.
	var epos := Combat.positions()
	epos["pc"] = [3, 3]
	Combat.save_positions(epos)
	assert(Combat.can_step([3, 3], [4, 3]), "open border is passable")
	assert(Combat.has_los([3, 3], [6, 3]), "open ground sees across")
	Combat.set_edge([3, 3], [4, 3], "wall")
	assert(not Combat.can_step([3, 3], [4, 3]), "a wall on the border stops the step")
	assert(not Combat.has_los([3, 3], [6, 3]), "a wall on the border stops the eye")
	assert(not Combat._impassable([4, 3]), "the square beyond a wall is still open ground")
	# Corner-cutting: one wall leaves a diagonal open, two pinch it shut.
	assert(Combat.can_step([3, 3], [4, 2]), "one wall still leaves a way round the corner")
	Combat.set_edge([3, 3], [3, 2], "wall")
	assert(not Combat.can_step([3, 3], [4, 2]), "two walls pinch the corner shut")
	# A window stops the body but not the eye; a curtain does the reverse.
	Combat.set_edge([3, 3], [4, 3], "window")
	assert(not Combat.can_step([3, 3], [4, 3]), "you cannot walk through a window")
	assert(Combat.has_los([3, 3], [6, 3]), "you can see through a window")
	Combat.set_edge([3, 3], [4, 3], "curtain")
	assert(Combat.can_step([3, 3], [4, 3]), "you can push through a curtain")
	assert(not Combat.has_los([3, 3], [6, 3]), "you cannot see through a curtain")
	# A door is stateful.
	Combat.set_edge([3, 3], [4, 3], "door_shut")
	assert(not Combat.can_step([3, 3], [4, 3]), "a shut door is a wall")
	Combat.set_edge([3, 3], [4, 3], "door_open")
	assert(Combat.can_step([3, 3], [4, 3]), "an open door is a doorway")
	# Vaulting a rail costs extra; open ground does not.
	Combat.set_edge([3, 3], [4, 3], "railing")
	assert(Combat.step_cost([3, 3], [4, 3]) == Combat.step_cost([3, 3], [3, 4]) + 1, "vaulting costs")
	# Reachability is a PATH question — a walled cell is unreachable however near.
	Combat.set_edge([3, 3], [4, 3], "")
	Combat.set_edge([3, 3], [3, 2], "")
	for wy in Combat.MAP_ROWS:      # a full north-south wall down column 4/5
		Combat.set_edge([4, wy], [5, wy], "wall")
	var routes := Combat.reachable([3, 3], 6)
	assert(routes.has("4,3"), "near side of the wall is reachable")
	assert(not routes.has("5,3"), "far side of the wall is not, though it is 2 cells away")
	assert(Combat.distance([3, 3], [5, 3]) == 2, "...and Chebyshev distance still says 2, which is the bug")
	# Adjacency must mean REACHABLE: no stabbing through a wall.
	var apos := Combat.positions()
	apos["pc"] = [4, 3]
	apos[gob_id] = [5, 3]
	Combat.save_positions(apos)
	assert(Combat.distance([4, 3], [5, 3]) == 1, "the two stand a square apart")
	assert(not Combat.adjacent("pc", gob_id), "a wall between them is not adjacency")
	assert(Combat.cover_between([4, 3], [7, 3]) == "blocked", "a wall is total cover")
	# R9-02 — and the ATTACK must actually ask. cover_between was correct and
	# asserted here for a whole round while player_attack never called it, so an
	# arrow crossed a wall as happily as open air. Assert the caller, not just
	# the rule.
	# The goblin died in the fight above, and a dead target short-circuits
	# player_attack before any guard runs — so stand him up for the test, then
	# put him back exactly as he was.
	var wall_dat := Combat.data()
	var gob_hp := 0
	for x in wall_dat["combatants"]:
		if str(x.get("id", "")) == gob_id:
			gob_hp = int(x.get("hp", 0))
			x["hp"] = 7
	Combat.save(wall_dat)
	var blind := Combat.player_attack(gob_id)
	assert(not bool(blind["spent"]), "an attack through a wall costs no action")
	assert(str(blind["msg"]) != "", "...and says why rather than failing silently")
	var wall_back := Combat.data()
	for x in wall_back["combatants"]:
		if str(x.get("id", "")) == gob_id:
			x["hp"] = gob_hp
	Combat.save(wall_back)
	# With a melee weapon the REACH guard answers first, and its message is the
	# better one ("move in"). The sight gate is what catches the ranged case, so
	# prove that separately, straight against the rule the attack now consults.
	assert(Combat.cover_between(Combat.cell_of("pc"), Combat.cell_of(gob_id)) == "blocked",
		"the attack's own sight test sees the wall between them")
	for wy in Combat.MAP_ROWS:
		Combat.set_edge([4, wy], [5, wy], "")
	assert(Combat.adjacent("pc", gob_id), "with the wall gone they are adjacent again")
	# Water costs double: fresh round, teleport beside the shore, wade in
	for i in Combat.order(Combat.data()).size():
		Combat.next_turn()
	var pos_t := Combat.positions()
	pos_t["pc"] = [6, 9]
	Combat.save_positions(pos_t)
	var left0 := int(Combat.move_budget(Combat.data()).get("left", 0))
	assert(Combat.move_pc([4, 9]), "wading is legal")
	# R10 — cost is now per STEP, not per destination. [6,9]→[5,9] is dry ground
	# (1) and [5,9]→[4,9] enters the shallows (2), so wading two squares to the
	# water's edge costs 3, not 4. The old model doubled the WHOLE distance
	# whenever the destination happened to be wet, which charged you double for
	# crossing dry land. (The previous code said as much: "destination-based
	# difficult terrain; per-step path costs later".)
	assert(int(Combat.move_budget(Combat.data()).get("left", 0)) == left0 - 3, "only the wet steps cost double")
	assert(Combat.in_cover("pc") == false)
	pos_t = Combat.positions()
	pos_t["pc"] = [8, 8]
	Combat.save_positions(pos_t)
	assert(Combat.in_cover("pc"), "standing in the undergrowth grants cover")

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

	# R8-28 — no XP was ever awarded in play. Never a bug in award_xp: `finish()`
	# pays for the slain and always has, but it only runs when a fight ENDS. Until
	# R8-07 the player could not start one; then until R11-01 the GM's dice path
	# resolved attacks without ever applying damage, so nothing died and there was
	# nothing to pay for. Both fixed — so assert the whole chain reaches the sheet,
	# because "it should work now" is not evidence.
	var xp_before := int(GameState.sheet().get("xp", 0))
	var fin := Combat.finish()
	assert(int(fin["xp"]) >= 25)
	assert(not Combat.active())
	assert(Combat.positions().is_empty(), "the board clears with the field")
	assert(int(GameState.sheet()["xp"]) == xp_before + int(fin["xp"]),
		"the XP a won fight pays actually lands on the sheet")
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

	# World Skin legibility guard: ink and accent must read on every palette's
	# surface (the contrast floor that a future LLM-refined palette gets clamped
	# to; the eight authored palettes must already clear it).
	var lum := func(col: Color) -> float: return 0.299 * col.r + 0.587 * col.g + 0.114 * col.b
	for fam in WorldSkin.FAMILIES:
		var pal: Dictionary = Ui.PALETTES[WorldSkin.FAMILIES[fam]["palette"]]
		var surf: float = lum.call(pal["surface"])
		assert(absf(lum.call(pal["ink"]) - surf) > 0.35, "low ink contrast: " + str(fam))
		assert(absf(lum.call(pal["gold"]) - surf) > 0.12, "low accent contrast: " + str(fam))

	# A1 World Style Guide: every family carries generative + voice descriptors.
	assert(WorldSkin.STYLE.size() == WorldSkin.FAMILIES.size())
	for fam in WorldSkin.FAMILIES:
		for k in ["char", "beast", "item", "dialogue", "lore_tone"]:
			assert(WorldSkin.STYLE[fam].has(k), "style missing %s in %s" % [k, fam])
	assert(WorldSkin.style_for_id("neonspire")["dialogue"] != WorldSkin.style_for_id("embervale")["dialogue"])
	assert(WorldSkin.style_of({"id": "cw-x", "kind": "steampunk", "tagline": "brass towers"})["beast"] == WorldSkin.STYLE["steam"]["beast"])

	# A2 art manifest: an asset can be noted and evicted (LRU bookkeeping).
	Art._manifest_loaded = true  # skip the disk scan in this unit check
	Art._manifest = {"unit-old": {"size": 100, "used": 1.0}, "unit-new": {"size": 100, "used": 9.0}}
	Art._evict("unit-old")
	assert(not Art._manifest.has("unit-old") and Art._manifest.has("unit-new"))
	Art._manifest = {}

	# A4 Character Resources: structured NPCs + a clamped relationship bond.
	GameState.state = {}
	GameState.record_npc({"name": "Aldric", "role": "knight", "goal": "reclaim his keep", "feeling": "wary"})
	GameState.relate("Aldric", 2, "the player spared him")
	var cst := GameState.cast()
	assert(cst.has("Aldric") and str(cst["Aldric"]["role"]) == "knight" and int(cst["Aldric"]["bond"]) == 2)
	GameState.relate("Aldric", 10, "")  # bond clamps at +5
	assert(int(GameState.cast()["Aldric"]["bond"]) == 5)
	assert(GameState.cast_summary().contains("Aldric"))
	GameState.state = {}

	# A6 Director scene context: reflects the location and the known cast.
	GameState.state = {"world": {"here": "the drowned chapel"}, "cast": {"Mara": {"role": "priestess"}}}
	var sctx := Composer.scene_context()
	assert(sctx.contains("drowned chapel") and sctx.contains("Mara"))
	GameState.state = {}
	assert(Composer.scene_context().contains("not yet established"))

	# Persistence: save_kind updates local state AND lands on disk, immediately.
	# This used to assert that the write was QUEUED for a PUT — the save being on
	# a server is what let three features silently never persist and what filed
	# every save under "null" once auth was disabled. It is a file now, so the
	# check is the one that actually matters: read it back.
	var keep_char := GameState.character
	GameState.character = {"id": "dm-selfcheck-persist"}
	GameState.state = {}
	GameState.save_kind("unit_kind", {"v": 7})
	assert(GameState.state.get("unit_kind") == {"v": 7}, "local state updates instantly")
	assert(GameState.state_for("dm-selfcheck-persist").get("unit_kind") == {"v": 7},
		"...and it is on disk before the next line runs")
	GameState.wipe_adventure("dm-selfcheck-persist")
	assert(GameState.state_for("dm-selfcheck-persist").is_empty(), "wiping a tale removes its save")
	GameState.character = keep_char
	GameState.state = {}

	# Stage 2 — the in-process narrator must be INERT until it is genuinely
	# usable. Both halves are required: the GDExtension (so the class exists at
	# all) and a GGUF on disk. If `available()` ever returns true with one of
	# them missing, every GM turn silently stops reaching a narrator.
	assert(LocalGM.available() == (ClassDB.class_exists("NobodyWhoChat")
		and ClassDB.class_exists("NobodyWhoModel") and LocalGM.model_file() != ""),
		"LocalGM is available exactly when the extension AND a model are present")
	if not LocalGM.available():
		assert(LocalGM.why_unavailable() != "", "an unusable narrator says why")
		assert(not LocalGM.stream("hello", ""), "an unusable narrator refuses rather than hanging the turn")
	# A local turn has no session, so the world framing must travel with it. If
	# this comes back empty the GM keeps the tag protocol and the live sheet but
	# loses the world, its cast and its voice — which is most of what makes it
	# this game's narrator rather than a generic assistant.
	var keep_world = GameState.character.get("world_id", "")
	GameState.character["world_id"] = "fimbulreach"
	var sysp := Composer.system_prompt()
	assert(sysp.contains("Fimbulreach"), "the local narrator is told which world it runs")
	assert(sysp.contains("CRAFT:") and sysp.contains("VOICE:"), "...and how to narrate it")
	GameState.character["world_id"] = keep_world

	print("SELF-CHECK OK")
	get_tree().quit(0)

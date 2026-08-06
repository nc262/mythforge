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
	assert(Rules.attack_mod(sheet, {}) == 6)  # max(STR,DEX) + prof; {} = no gear, said out loud

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

	# PS-1 — A LEVEL-1 HERO HAS THEIR CLASS FEATURE.
	#
	# The forge wrote HERITAGE traits into sheet.features, which the sheet renders
	# under "Class Features" and which feature_action_key() matches to put a
	# usable action on the HUD. So a level-1 Fighter had no Second Wind, a
	# Barbarian no Rage, and the "Class Features" list was their heritage —
	# repeated again on the Story page. Level-up only grants the level just
	# reached, so level 1's features were lost the moment the hero was forged.
	assert(Rules.class_features_upto("Fighter", 1).any(func(f): return str(f).begins_with("Second Wind")))
	assert(Rules.class_features_upto("Barbarian", 1).any(func(f): return str(f).begins_with("Rage")))
	assert(Rules.class_features_upto("Paladin", 1).any(func(f): return str(f).begins_with("Lay on Hands")))
	# It must ACCUMULATE, not report only the newest level.
	var f5 := Rules.class_features_upto("Fighter", 5)
	assert(f5.any(func(f): return str(f).begins_with("Second Wind")))     # still there at 5
	assert(f5.any(func(f): return str(f).begins_with("Action Surge")))    # level 2
	assert(f5.size() > Rules.class_features_upto("Fighter", 1).size())
	# No heritage trait may masquerade as a class feature.
	for race in ["Human", "Half-Orc", "Elf"]:
		for t in Rules.tables.get("heritages", {}).get(race, {}).get("traits", []):
			assert(not Rules.class_features_upto("Fighter", 5).has(str(t)))
	# And the feature must actually REACH the HUD, or it is a line of text.
	assert(GameState.feature_action_key(str(Rules.class_features_upto("Fighter", 1)[0])) == "Second Wind")

	# PS-2 — NO HERO LEAVES THE FORGE WITH A SWORD AND NOTHING ELSE.
	#
	# Both kit paths can hand back exactly one weapon (a compiled world whose
	# asset language invented no armour forms does), and neither ever granted
	# sundries. The floor fills only what is MISSING.
	var lone_sword := [{"name": "Longsword", "type": "weapon"}]
	var gaps := Rules.kit_gaps(lone_sword, "fantasy")
	assert(not gaps.has("Club"))                            # already armed
	assert(gaps.has("Traveler's Leathers"))                 # but unarmoured
	assert(gaps.any(func(g): return str(g).begins_with("Rations")))
	# A generous kit is left alone apart from sundries.
	var full := [{"name": "Longsword", "type": "weapon"}, {"name": "Chain Shirt", "type": "armor"}]
	var gaps2 := Rules.kit_gaps(full, "fantasy")
	assert(not gaps2.has("Club") and not gaps2.has("Traveler's Leathers"))
	# Nothing is added twice.
	var already := [{"name": "Torch", "type": "misc"}]
	assert(not Rules.kit_gaps(already, "fantasy").has("Torch"))
	# An empty-handed hero gets armed.
	assert(Rules.kit_gaps([], "fantasy").has("Club"))
	# Family-flavoured: a runner carries no tinderbox.
	var cyber := Rules.kit_gaps([], "cyber")
	assert(not cyber.has("Tinderbox"))
	assert(cyber.any(func(g): return str(g).begins_with("Ration Bars")))
	assert(Rules.starting_sundries("nonesuch") == Rules.starting_sundries("_"))

	# UI-1 — TAG DEBRIS NEVER REACHES THE BUBBLE.
	#
	# `_tag_re` needs a closing "]]", so an unclosed "[[Perception" and a
	# single-bracket "[Active Perception]" were invisible to the parser: it could
	# neither act on them nor strip them, and they rendered verbatim.
	var d1 := Tags.parse("You edge along the ledge.
[[Perception")
	assert(not d1["clean"].contains("[["))
	assert(d1["clean"].contains("You edge along the ledge."))
	var d2 := Tags.parse("The lock clicks. [Active Perception] The hall is quiet.")
	assert(not d2["clean"].contains("["))
	assert(d2["clean"].contains("The lock clicks.") and d2["clean"].contains("The hall is quiet."))
	# A real tag still parses AND still leaves clean prose behind it.
	var d3 := Tags.parse("You slip past. [[check ability=DEX skill=Stealth dc=13]]")
	assert(d3["tags"].size() == 1 and str(d3["tags"][0]["name"]) == "check")
	assert(d3["clean"] == "You slip past.")
	# PROSE MUST SURVIVE. A bracket is legal English, and eating the player's
	# aside would be a worse bug than the one being fixed.
	var d4 := Tags.parse("She hands you the ledger [it is warm] and says nothing.")
	assert(d4["clean"].contains("[it is warm]"))
	var d5 := Tags.parse("The sign reads [CLOSED].")
	assert(d5["clean"].contains("[CLOSED]"))
	# And the cut must not leave a scar.
	assert(not Tags.parse("A step. [[loot name=\"Rope\"]] Another.")["clean"].contains("  "))

	# UI-2 — no two Destiny monuments may share a name. Five nodes all reading
	# "Gift of Growth" is five nodes the player cannot tell apart. Asked of the
	# REAL node list — a check that builds its own list proves nothing about the
	# screen it is named for.
	var keep_st := GameState.state
	GameState.state = {"sheet": {"cls": "Fighter", "level": 20, "race": "Human",
		"abilities": {"STR": 14, "DEX": 12, "CON": 13, "INT": 10, "WIS": 10, "CHA": 10}}}
	var tree = load("res://scenes/ui/skill_tree.gd").new()
	tree._build()
	var labels := {}
	var dupes: Array[String] = []
	for n in tree._nodes:
		if str(n.get("kind", "")) != "milestone":
			continue
		var lbl := str(n.get("label", ""))
		if labels.has(lbl):
			dupes.append(lbl)
		labels[lbl] = true
	tree.free()
	GameState.state = keep_st
	assert(dupes.is_empty())          # every monument is nameable
	assert(labels.size() >= 6)        # 5 ASI + subclass + apotheosis, all distinct

	# ── THE WORLD GROWS: places, regions, scope ─────────────────────────────
	#
	# The map was three disagreeing answers to "what places exist", and for a
	# FORGED world every pin defaulted to (50,50) and stacked on the chart's
	# centre — the Worldsmith is never asked for x/y and nothing added them.
	var keep_c := GameState.character
	var keep_s := GameState.state
	GameState.character = {"id": "dm-geo-probe", "world_id": "cw-geo-probe"}
	GameState.state = {"sheet": {"name": "Probe", "level": 1,
		"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}},
		"world": {"here": "", "regions": [{"name": "The Reach"}, {"name": "The Deeps"}],
			"places": [{"name": "Hollowmere", "kind": "settlement", "region": "The Reach"},
				{"name": "Gull's Rest", "kind": "tavern", "region": "The Reach"},
				{"name": "The Drowned Stair", "kind": "ruin", "region": "The Deeps"}]}}
	# NO TWO PLACES MAY SHARE A PIXEL. This is the bug that made a forged world's
	# Atlas one dot: assert the failure, not that coordinates merely exist.
	var pts := {}
	for pl in GameState.places():
		var k := "%d,%d" % [int(pl["x"]), int(pl["y"])]
		assert(not pts.has(k))          # stacked pins = the chart is a lie
		pts[k] = true
	assert(pts.size() == 3)
	# Places of different regions must not land on top of each other either.
	var reach := GameState.region_at("The Reach")
	var deeps := GameState.region_at("The Deeps")
	assert(reach.distance_to(deeps) > 5.0)
	# Deterministic: the same world laid out twice is the same map.
	var first := GameState.places()
	var again := GameState.places()
	for i in first.size():
		assert(first[i]["x"] == again[i]["x"] and first[i]["y"] == again[i]["y"])

	# SCOPE IS EARNED. A level-1 party may charter next door, not a continent.
	assert(Rules.scope_allowed("local", 1))
	assert(not Rules.scope_allowed("regional", 1))
	assert(not Rules.scope_allowed("far", 1))
	assert(Rules.scope_allowed("far", 7))
	assert(Rules.scope_for_level(1) == "local")
	assert(Rules.scope_for_level(20) == "far")
	# The GM's power, and the engine's veto.
	assert(GameState.add_place({"name": "Saltwick", "kind": "settlement",
		"scope": "local", "region": "The Reach"}) == "")
	assert(GameState.places().size() == 4)
	assert(GameState.add_place({"name": "Saltwick"}) != "")        # no duplicates
	assert(GameState.add_place({"name": ""}) != "")                # no nameless places
	assert(GameState.add_place({"name": "The Far Waste", "scope": "far"}) != "")  # unearned
	assert(GameState.add_region({"name": "Beyond"}) != "")         # regions are far-gated
	# ...and a level-7 party opens the frontier.
	GameState.state["sheet"]["level"] = 7
	assert(GameState.add_place({"name": "The Far Waste", "scope": "far"}) == "")
	assert(GameState.add_region({"name": "Beyond"}) == "")
	assert(GameState.regions().size() == 3)
	# DENSITY: a region fills up, or twenty sessions of GM whim become noise.
	GameState.state["sheet"]["level"] = 20
	var refused := ""
	for i in 20:
		var why := GameState.add_place({"name": "Filler %d" % i, "region": "The Reach"})
		if why != "":
			refused = why
			break
	assert(refused != "")
	assert(GameState.region_place_count("The Reach") <= Rules.REGION_PLACE_CAP)
	# DISTANCE COSTS TIME. It used to be one tick to anywhere.
	GameState.state["world"]["here"] = "Hollowmere"
	assert(GameState.travel_cost("Gull's Rest") >= 1)
	# The GM is TOLD its reach, or it invents a continent and gets refused.
	var geo := Composer.geography_context()
	assert(geo.contains("The Reach") and geo.contains("REGIONS"))
	assert(geo.contains("YOUR REACH"))
	GameState.character = keep_c
	GameState.state = keep_s

	# EVERY SHIPPED WORLD HAS REGIONS, AND EVERY SHIPPED PLACE STANDS IN ONE.
	#
	# Place-creation attaches a new place to a region. Without regions in the six
	# worlds people actually play, the whole mechanic is dead in exactly the
	# content that ships — new places would hang off nothing and pile onto the
	# chart's centre ring.
	#
	# Three of the six also had NO x/y at all (saltmarsh, fimbulreach,
	# brasshaven), so they stacked before any of this was built.
	var keep_c2 := GameState.character
	var keep_s2 := GameState.state
	for wid in ["embervale", "neonspire", "everyday", "saltmarsh", "fimbulreach", "brasshaven"]:
		var regs: Array = Rules.world_regions(wid)
		assert(regs.size() >= 2)                     # a world with one region has no shape
		var rnames := {}
		for r in regs:
			assert(str(r.get("name", "")) != "" and str(r.get("lore", "")) != "")
			rnames[str(r["name"])] = true
		assert(rnames.size() == regs.size())          # no two regions share a name
		# Every shipped place names a region that exists.
		for l in Rules.world_locations(wid):
			var rg := str(l.get("region", ""))
			assert(rg != "")
			assert(rnames.has(rg))
		# ...and laid out through GameState, no two places share a pixel.
		GameState.character = {"id": "dm-layout-%s" % wid, "world_id": wid}
		GameState.state = {"sheet": {"level": 1}, "world": {}}
		var pts2 := {}
		for pl in GameState.places():
			var k2 := "%d,%d" % [int(pl["x"]), int(pl["y"])]
			assert(not pts2.has(k2))                  # stacked pins = the chart is a lie
			pts2[k2] = true
		assert(pts2.size() == Rules.world_locations(wid).size())
	GameState.character = keep_c2
	GameState.state = keep_s2

	# THE SHIPPED WORLDS MUST BE FINDABLE BESIDE THE EXE, not only inside it.
	# The zips are no longer bundled (a 3.02 GB single file cannot be published),
	# so `res://baked` does not exist in an export and the game would ship with
	# NO WORLDS if this search were pck-only. No other harness covers this: they
	# all run from source, where res://baked is right there.
	var dirs: Array[String] = Compiler.baked_dirs()
	assert(dirs.has("res://baked"))                   # editor and harnesses
	assert(dirs.size() >= 2)                          # and somewhere beside the exe
	var beside := false
	for dd in dirs:
		if not dd.begins_with("res://") and dd.ends_with("baked"):
			beside = true
	assert(beside)

	# UI-7 — THE ITEM PROMPT MUST NAME THE THING, NOT THE WEATHER.
	#
	# Measured against the real image engine, one item, three prompts:
	#   "…, high fantasy oil painting, candlelit"  → a lit CANDLE on a hilt
	#   the same with "candlelit" removed          → a blade, wrong silhouette
	#   plus a shape clause                        → a blade
	#
	# The atmosphere clause becomes the SUBJECT on a 512 px icon; the compiler
	# learned that the hard way ("…lantern light" turned a sword into a lantern)
	# and the legacy per-name path had to learn it too.
	#
	# The third line originally read "a correct short blade". It was not. Rendered
	# again on 2026-08-04 it is a full-length cruciform sword, and so are a
	# gladius clause and a wakizashi clause — see KI-5 below. The clause helps
	# when it names a CATEGORY and cannot help when it names a size.
	assert(Rules.shape_clause("Iron Dagger").contains("dagger"))
	assert(Rules.shape_clause("Greataxe").contains("axe"))
	assert(Rules.shape_clause("Healing Potion").contains("bottle"))
	# Every clause must be derived from a word IN the name — a shape the item
	# does not claim would be worse than no shape at all.
	for pair in Rules.SHAPE_WORDS:
		assert(str(pair[1]) != "")
	assert(Rules.shape_clause("Widget of Nonsense") == "")   # unknown → say nothing
	# And the item flavour must drop the atmosphere while keeping the medium.
	var keep_w := GameState.character
	GameState.character = {"id": "dm-flavor-probe", "world_id": "embervale"}
	var flav_full := Art.world_flavor()
	var item_f := Art.item_flavor()
	assert(item_f != "")
	assert(not item_f.contains(","))          # medium only, no trailing weather
	assert(flav_full.begins_with(item_f))     # and it is genuinely the head of it
	GameState.character = keep_w

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

	# CN-2 — the envelope must forbid INVENTING A CAUSE for a number.
	#
	# The GM narrated "the vitality you lost in battle" with no battle fought. It
	# could see HP below max and supplied a reason, which is what storytellers do
	# with unexplained numbers. The sheet states what is true and never why, so
	# the envelope has to say out loud that the why is not the model's to invent.
	GameState.state = {"sheet": {"name": "Drao", "level": 3, "hp": 7, "hpMax": 22,
		"abilities": {"STR": 12, "DEX": 12, "CON": 12, "INT": 10, "WIS": 10, "CHA": 10}}}
	var env := Composer.envelope("I look around.")
	assert(env.contains("7/22"))                       # the fact is stated
	assert(env.contains("CAUSES are not yours to invent"))
	assert(env.contains("Never explain a number by inventing an event"))
	GameState.state = {}

	# CN-4 — the backdrop key must carry the MOOD, or one painting serves a place
	# forever: the reported symptom was a single plate across four days and three
	# weather states. Buckets are coarse on purpose (3 light x 3 sky = 9 max per
	# place, not 7 x 6 = 42), so this asserts they SEPARATE, not that they enumerate.
	GameState.state = {"clock": {"day": 1, "ti": 1, "wx": {"ico": "*", "name": "clear skies"}}}
	var noon := GameState.scene_mood()
	GameState.state = {"clock": {"day": 1, "ti": 6, "wx": {"ico": "*", "name": "a brewing storm"}}}
	var night := GameState.scene_mood()
	assert(noon != night)                     # the same place must not key the same
	assert(noon == "day-clear")
	assert(night == "night-wet")
	GameState.state = {"clock": {"day": 1, "ti": 5, "wx": {"ico": "*", "name": "low mist"}}}
	assert(GameState.scene_mood() == "dusk-misty")
	# An hour inside one afternoon is NOT a repaint; dusk falling is.
	GameState.state = {"clock": {"day": 1, "ti": 1, "wx": {"ico": "*", "name": "clear skies"}}}
	var m0 := GameState.scene_mood()
	GameState.state["clock"]["ti"] = 2
	assert(GameState.scene_mood() == m0)
	# And the words a painter gets must differ with it.
	assert(GameState.scene_mood_words() != "")
	GameState.state = {"clock": {"day": 1, "ti": 6, "wx": {"ico": "*", "name": "a brewing storm"}}}
	assert(GameState.scene_mood_words().contains("night"))
	GameState.state = {}

	# Persistence: save_kind updates local state AND lands on disk, immediately.
	# The check that matters is the one that reads it back — asserting a write was
	# merely QUEUED is how three features silently never persisted.
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
	# This one line is what stopped the GM opening every reply on the weather —
	# measured 3/3 atmosphere openings before it, 0/3 after (bench_gm). It reads
	# like ordinary prose in a long directive and is exactly the kind of thing a
	# later tidy-up deletes as redundant, so it is pinned.
	assert(sysp.contains("OPEN ON WHAT CHANGED"),
		"the GM is told to open on what changed, not on the weather")
	GameState.character["world_id"] = keep_world

	# The Worldsmith's class reskins are PARSED out of prose rather than extracted
	# by a schema — a nested twelve-key object burned the whole 180 s deadline
	# every run. That makes the parser load-bearing, and it is the kind of regex
	# that quietly stops matching when a model changes its bullet style, so it is
	# checked here against the shapes actually observed rather than only against
	# whatever the model happens to emit on the day.
	var sample := """**PART 1**
In Aquari's Repose, power seeps from ancient stones as an energy called "Echovox".

**PART 2**
The term for spell slots is "Echoes."

**PART 3**
- Fighter: Kraelion
1. Barbarian — Vorgathor
**Rogue**: Shadewalker
- Ranger: Tidesinger
- Monk: Kyrium
- Paladin: Solaire
- Wizard: Aetherbinder
- Sorcerer: Dreamweaver
- Cleric: Elyrian
- Druid: Terrakai
- Bard: Melodist
- Warlock: Umbrawyn"""
	var rs := Worldsmith.parse_reskins(sample)
	assert(rs.get("names", {}).size() == 12, "all twelve class titles parse out of prose")
	assert(str(rs["names"]["Fighter"]) == "Kraelion", "a plain bullet parses")
	assert(str(rs["names"]["Barbarian"]) == "Vorgathor", "a numbered line with an em dash parses")
	assert(str(rs["names"]["Rogue"]) == "Shadewalker", "a bolded class name parses")
	assert(str(rs["slots"]) == "Echoes", "the spell-slot term is unwrapped from its sentence")
	assert(str(rs["flavor"]).contains("Echovox"), "the flavor line survives")
	# A class named inside PART 1's prose must NOT be mistaken for an entry.
	var decoy := "**PART 3**\n- Fighter: Kraelion"
	assert(Worldsmith.parse_reskins(decoy).get("names", {}).size() == 1,
		"a partial answer yields only what it actually said")

	# The World Compiler's stages think in prose and are shaped afterwards, so
	# the coercion is load-bearing: measured, the style stage returned eleven
	# good materials inside ONE string where an array was wanted.
	var arr_schema := '{"type":"object","required":["materials","visual_language"],' \
		+ '"properties":{"materials":{"type":"array","minItems":10,"items":{"type":"string"}},' \
		+ '"visual_language":{"type":"string"},' \
		+ '"colors":{"type":"array","minItems":2,"items":{"type":"object"}}}}'
	var coerced := Compiler._coerce({
		"materials": "Weathered wood, rusting iron, bleached bone, tarred rope",
		"visual_language": ["salt-bleached", "low sun"],
		"colors": "not, recoverable",
	}, arr_schema)
	assert(coerced["materials"] is Array and (coerced["materials"] as Array).size() == 4,
		"a comma-joined list becomes the array the stage asked for")
	# The shape actually observed: valid JSON, whole list inside ONE element.
	# It parses, it IS an array, and it is still wrong.
	var one_elem := Compiler._coerce({"materials":
		["Weathered wood, rusting iron, bleached bone, tarred rope"],
		"visual_language": "salt and rust"}, arr_schema)
	assert((one_elem["materials"] as Array).size() == 4,
		"a list smuggled inside a single array element is unpacked")
	assert(str((coerced["materials"] as Array)[1]) == "rusting iron", "…trimmed")
	assert(coerced["visual_language"] is String, "a list where prose was wanted is joined")
	assert(coerced["colors"] is String,
		"an array of OBJECTS is left alone — it is not hiding in a sentence")
	# The gate that decides whether a second call is worth paying for.
	assert(not Compiler._satisfies({"materials": ["one"]}, arr_schema),
		"a stage missing a required key is not accepted")
	assert(Compiler._satisfies({"materials": ["a", "b", "c", "d", "e"],
		"visual_language": "salt and rust"}, arr_schema),
		"…but an under-filled list still beats falling back to generic content")

	# The smith's ask-back copies prose lines faithfully, label and all, so the
	# label is stripped on this side. Pinned here because the pattern holds
	# literal dash characters — PCRE2 has no \u escape, and getting that wrong
	# once already shipped a parser that silently matched nothing.
	assert(Worldsmith._strip_label("A: A sea goddess's silent compact.", "A")
		== "A sea goddess's silent compact.", "a colon label comes off")
	assert(Worldsmith._strip_label("**B** — Her own potential", "B")
		== "Her own potential", "a bolded em-dash label comes off")
	assert(Worldsmith._strip_label("Ashen tide", "A") == "Ashen tide",
		"an answer that merely starts with the letter is left alone")

	# The World Forge's question pool. The whole point is that two different
	# worlds get asked different things, so that is what gets asserted — a pool
	# that quietly returns the same five every time would look fine in a
	# screenshot and be exactly the bug it replaced.
	const WQ := preload("res://scenes/forge/world_questions.gd")
	var sea := WQ.pick("a drowned city where the tide keeps the dead polite", {})
	var stars := WQ.pick("a starfaring frontier of salvage crews and cold void",
		{"title": "Sci-Fi"})
	var sea_ids := sea.map(func(q): return str(q["id"]))
	var star_ids := stars.map(func(q): return str(q["id"]))
	assert(sea_ids != star_ids, "two different worlds are asked different questions")
	assert(sea_ids.has("the_water"), "a drowned world is asked what the water takes")
	assert(not star_ids.has("the_water"), "...and a starfaring one is not")
	assert(star_ids.has("machine_cost"), "a machine world is asked what the machines run on")
	# The conflict pair leads every world — they are what make it playable rather
	# than merely described.
	for ids in [sea_ids, star_ids]:
		assert(ids.has("scarcity") and ids.has("authority"),
			"every world is asked what is scarce and who decides")
	assert(sea.size() <= WQ.ASK, "never more questions than the interaction budget")
	# "Different six" must actually be different, or the button is a lie.
	var p0 := WQ.premises(0)
	var p1 := WQ.premises(1)
	assert(p0.size() == 6 and p1.size() == 6, "the Spark offers six premises")
	for prem in p0:
		assert(not p1.has(prem), "a second page repeats nothing from the first")
		assert(str(prem).length() > 40, "a premise is specific enough to be worth picking")
	# Never ask what the player already told you.
	var mundane := WQ.pick("a world with no magic at all, just mud and politics", {})
	assert(not mundane.map(func(q): return str(q["id"])).has("magic_cost"),
		"a premise that rules out magic is not asked what magic costs")
	# Options carry consequences, not categories — the option text becomes prompt
	# text, so an empty rule would hand the model an adjective and nothing else.
	for q in sea:
		for o in q["options"]:
			assert(str(o.get("rule", "")).strip_edges() != "",
				"every option states the rule it puts into the world")

	# ── STAGE C: the modular doll ────────────────────────────────────────────
	# Driven against the REAL CC0 body in the repo, not a stub — the whole point
	# is that the slot wiring and the body-zone occlusion agree with geometry
	# that actually exists.
	if ResourceLoader.exists("res://spike3d/models/Knight.glb"):
		var doll := ModularDoll.new()
		doll.rig = "kaykit"   # the legacy fixture, kept because it proves the
		add_child(doll)       # in-scene "unhide a part" path the new rig does not use
		doll.build(load(doll.body_path()))
		assert(doll.skeleton != null, "doll: the body must bring a skeleton")
		# A doll starts BARE, whatever the source scene shipped wearing.
		assert(doll.hidden_zones().is_empty(), "doll: nothing is covered before anything is worn")
		assert(doll.worn("head") == "", "doll: the head slot starts empty")

		# A helm covers the head; the head mesh goes away so it cannot poke out.
		assert(doll.equip("head", "knight_helm"), "doll: the helm should go on")
		assert(doll.hidden_zones() == ["head"], "doll: a helm hides the head zone")
		# Two pieces, two zones — and taking one off must not un-hide the other.
		assert(doll.equip("cloak", "knight_cape"), "doll: the cape should go on")
		assert(doll.equip("head", ""), "doll: the helm should come off")
		assert(doll.hidden_zones().is_empty(), "doll: bare head shows again once the helm is off")

		# The order-of-undressing bug the refresh exists to prevent: recomputing
		# from the whole loadout, never toggling per change.
		doll.equip("head", "knight_helm")
		doll.equip("cloak", "")
		assert(doll.hidden_zones() == ["head"], "doll: removing the cape must not reveal a helmeted head")

		# One slot holds ONE thing: a second weapon replaces the first.
		assert(doll.equip("weapon", "sword_1h"), "doll: a sword should draw")
		assert(doll.equip("weapon", "sword_2h"), "doll: a greatsword should replace it")
		assert(doll.worn("weapon") == "sword_2h", "doll: the slot holds the newer weapon")
		assert(not doll.equip("weapon", "not_a_thing"), "doll: an unknown part is refused, not drawn")
		assert(doll.worn("weapon") == "sword_2h", "doll: ...and a refusal leaves the slot alone")

		# Every rendered slot the game can fill must be a slot this rig answers
		# for, or a player equips something and nothing happens on the doll.
		var prof: Dictionary = doll.profile()
		for slot in ["head", "cloak", "weapon", "offhand", "shield"]:
			assert(prof["parts"].has(slot) or prof["sockets"].has(slot),
				"doll: rig '%s' has no answer for the '%s' slot" % [doll.rig, slot])
		# Sockets must name bones the skeleton actually has — a typo here fails
		# silently, hanging the sword on nothing.
		for slot2 in prof.get("sockets", {}):
			var bone := str(prof["sockets"][slot2])
			assert(doll.skeleton.find_bone(bone) >= 0,
				"doll: socket bone '%s' for '%s' is not on this skeleton" % [bone, slot2])
		# An ITEM NAME must reach the right mesh. Specific before generic — the
		# same ordering trap SHAPE_WORDS fell into, where a prefix shadowed the
		# category noun and a shortbow was described as a blade.
		assert(doll.part_for("weapon", "Greatsword") == "sword_2h", "doll: a greatsword is two-handed")
		assert(doll.part_for("weapon", "Iron Sword") == "sword_1h", "doll: a plain sword is one-handed")
		assert(doll.part_for("weapon", "Oak Staff") == "staff", "doll: a staff is a staff")
		assert(doll.part_for("weapon", "Wand of Sparks") == "wand", "doll: a wand is a wand")
		assert(doll.part_for("weapon", "Nonsense Thing") == "sword_1h",
			"doll: an unknown weapon still arms the hand rather than emptying it")
		assert(doll.part_for("shield", "Round Shield") == "round", "doll: a round shield is round")
		assert(doll.part_for("shield", "Tower Shield") == "rect", "doll: a tower shield is the big one")
		assert(doll.part_for("head", "Leather Hood") == "mage_hat", "doll: a hood is soft headgear")
		assert(doll.part_for("head", "Iron Helm") == "knight_helm", "doll: a helm is hard headgear")
		assert(doll.part_for("armor", "Chain Shirt") == "",
			"doll: a slot this rig has no geometry for resolves to nothing, not to a guess")

		# Dressed from the REAL inventory shape the game keeps, not a bespoke one.
		doll.build(load("res://spike3d/models/Knight.glb"))
		doll.wear_inventory({
			"items": [{"id": "w1", "name": "Greatsword"}, {"id": "h1", "name": "Iron Helm"}],
			"equipped": {"weapon": "w1", "head": "h1"}})
		assert(doll.worn("weapon") == "sword_2h", "doll: the equipped greatsword reaches the figurine")
		assert(doll.worn("head") == "knight_helm", "doll: the equipped helm reaches the figurine")
		assert(doll.hidden_zones() == ["head"], "doll: ...and wearing it still hides the head")
		# Unequipping in the game must bare the figurine.
		doll.wear_inventory({"items": [{"id": "w1", "name": "Greatsword"}], "equipped": {}})
		assert(doll.worn("weapon") == "" and doll.worn("head") == "",
			"doll: an empty loadout strips the figurine")
		assert(doll.hidden_zones().is_empty(), "doll: ...and gives the head back")
		doll.queue_free()
		print("  doll: helm/cape/weapon slots wired, body zones hide, sockets resolve, items map")

	# ── The SHIPPING rig: separate garment files, skinned onto one skeleton ───
	if ResourceLoader.exists("res://assets3d/bodies/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"):
		var qd := ModularDoll.new()
		qd.rig = "quaternius"
		add_child(qd)
		qd.build(load(qd.body_path()))
		assert(qd.skeleton != null and qd.skeleton.get_bone_count() == 65,
			"q-doll: the shipping body is the 65-bone rig")
		# THE SLOTS THAT WERE MISSING. These are the whole reason for the pack —
		# on the old fixture every one of them resolved to nothing.
		for slot in ["armor", "hands", "legs", "feet"]:
			assert(qd.equip(slot, "ranger"), "q-doll: '%s' must have geometry now" % slot)
			assert(qd.worn(slot) == "ranger", "q-doll: '%s' stays worn" % slot)
		assert(qd.equip("head", "hood"), "q-doll: a hood goes on")
		# A garment is its own FILE here, so wearing it must actually add meshes
		# to the doll — and taking it off must remove them, or the figurine keeps
		# every shirt it ever wore, invisibly stacked.
		var meshes_on := qd._all_meshes(qd).size()
		assert(meshes_on > 3, "q-doll: garments add real geometry, got %d meshes" % meshes_on)
		qd.equip("armor", "")
		assert(qd._all_meshes(qd).size() < meshes_on, "q-doll: undressing REMOVES the garment")
		assert(qd.worn("armor") == "", "q-doll: ...and the slot reads bare")
		# Swapping within a slot must not stack either.
		qd.equip("armor", "ranger")
		var one := qd._all_meshes(qd).size()
		qd.equip("armor", "peasant")
		assert(qd._all_meshes(qd).size() <= one,
			"q-doll: swapping a garment replaces it rather than layering it")
		# Item names must reach the right archetype.
		assert(qd.part_for("armor", "Studded Leather") == "ranger", "q-doll: leather reads as the ranger")
		assert(qd.part_for("armor", "Homespun Tunic") == "peasant", "q-doll: cloth reads as the peasant")
		assert(qd.part_for("feet", "Riding Boots") == "ranger", "q-doll: boots are boots")
		# Sockets must name real bones on THIS skeleton, or a sword hangs on air.
		for qslot in qd.profile().get("sockets", {}):
			var bn := str(qd.profile()["sockets"][qslot])
			assert(qd.skeleton.find_bone(bn) >= 0,
				"q-doll: socket '%s' -> bone '%s' is not on this rig" % [qslot, bn])
		# And it must STAND — the clips live in a separate file on this rig, so a
		# broken attach shows up as a T-posed mannequin and nothing else.
		var posed2 := 0
		for bi2 in qd.skeleton.get_bone_count():
			if not qd.skeleton.get_bone_pose_rotation(bi2).is_equal_approx(
					qd.skeleton.get_bone_rest(bi2).basis.get_rotation_quaternion()):
				posed2 += 1
		assert(posed2 > 0, "q-doll: the borrowed animation library never reached the skeleton")
		# NOBODY STANDS IN THEIR UNDERWEAR. An empty slot falls back to the rig's
		# underclothes, because a hero who has not found trousers yet is dressed
		# poorly, not undressed — and that is most of act one.
		qd.wear_inventory({"items": [], "equipped": {}})
		for bare_slot in ["armor", "legs", "feet", "hands"]:
			assert(qd.worn(bare_slot) != "",
				"q-doll: '%s' must fall back to underclothes, not skin" % bare_slot)
		assert(qd.worn("head") == "", "q-doll: bare-headed is fine and stays bare")

		# ── Rigid props: weapons and shields ─────────────────────────────────
		# A different attach path from garments — one bone, no skin weights —
		# which is why a weapon pack built for no particular rig works at all.
		assert(qd.equip("weapon", "sword"), "q-doll: a sword goes in the hand")
		assert(qd.equip("shield", "heater"), "q-doll: a shield goes on the arm")
		assert(qd.worn("weapon") == "sword" and qd.worn("shield") == "heater",
			"q-doll: both hands hold what they were given")
		assert(qd.part_for("weapon", "Greataxe") == "axe_big", "q-doll: a greataxe is the big axe")
		assert(qd.part_for("weapon", "Hand Axe") == "axe", "q-doll: ...and a hand axe is not")
		assert(qd.part_for("weapon", "Oak Longbow") == "bow", "q-doll: a longbow is a bow, not a sword")
		assert(qd.part_for("weapon", "Rusty Thing") == "sword", "q-doll: an unknown weapon still arms the hand")
		assert(qd.part_for("shield", "Tower Shield") == "heater", "q-doll: a tower shield is the big one")
		# A prop is SCALED FROM ITS OWN MESH to a target length. The first version
		# used a fixed factor and produced a sword taller than the man; a pack's
		# authored units are not something you can reason about from here.
		var fitw: Dictionary = qd.profile().get("prop_fit", {}).get("weapon", {})
		assert(fitw.has("len") and not fitw.has("scale"),
			"q-doll: props are fitted by target LENGTH, never by a guessed scale factor")
		# SIZE WITHIN A CATEGORY, which the icon pipeline provably cannot draw
		# (KnownIssues #5) and geometry gets for nothing. A dagger that is as long
		# as a sword is the same failure, just in 3D.
		var plen: Dictionary = qd.profile().get("prop_len", {})
		assert(float(plen.get("dagger", 9.0)) < float(plen.get("sword", 0.0)),
			"q-doll: a dagger must be shorter than a sword")
		assert(float(plen.get("claymore", 0.0)) > float(plen.get("sword", 9.0)),
			"q-doll: a claymore must be longer than a sword")
		assert(float(plen.get("spear", 0.0)) > float(plen.get("claymore", 9.0)),
			"q-doll: a spear outreaches every blade")
		# And the stance must not hide them. Folded arms tucks both hands into the
		# chest, which makes a figurine that shows your gear show nothing.
		var stance: Array = qd.profile().get("stand", [])
		assert(stance.size() > 0 and str(stance[0]).to_lower() != "idle_foldarms",
			"q-doll: the default stance must leave the hands visible")
		qd.queue_free()
		print("  q-doll: chest/hands/legs/feet wear real garments, swap cleanly, and stand")

		# ── Both sexes, both wardrobes ───────────────────────────────────────
		# The pack ships a full garment set per body and the female cut is not
		# the male one scaled, so every path carries a {S} token. A template that
		# silently resolves to a file that does not exist leaves a slot empty and
		# says nothing, so every one is checked for real.
		var qf := ModularDoll.new()
		qf.rig = "quaternius"
		qf.sex = "female"
		add_child(qf)
		assert(ResourceLoader.exists(qf.body_path()), "q-doll: the female body resolves")
		assert(qf.body_path() != qd.body_path(), "q-doll: the sexes are different bodies")
		qf.build(load(qf.body_path()))
		for fslot in ["armor", "hands", "legs", "feet"]:
			assert(qf.equip(fslot, "ranger"), "q-doll(f): '%s' must resolve for the female cut" % fslot)
		assert(qf.equip("head", "hood"), "q-doll(f): the hood resolves")
		# The pack's own naming diverges on exactly one file (Feet_Boots vs
		# Feet), which a pure template cannot cover — this is the assertion that
		# caught it.
		assert(qf.worn("feet") == "ranger", "q-doll(f): boots stay on despite the odd filename")
		# The body the player shaped must actually MOVE bones. A build that does
		# nothing is a slider that lies.
		var before_pose := qf.skeleton.get_bone_pose(qf.skeleton.find_bone("spine_03"))
		qf.apply_build(Rules.hero_body({"race": "Human", "sex": "female",
			"build": {"chest": 100, "frame": 100, "weight": 100, "height": 100, "build": 100}}))
		assert(qf.skeleton.get_bone_pose(qf.skeleton.find_bone("spine_03")) != before_pose,
			"q-doll: the build knobs must reach the skeleton")
		# ...and dragging twice must not double it. apply_build restores the bind
		# pose first, because bone scale compounds.
		var once := qf.skeleton.get_bone_pose(qf.skeleton.find_bone("spine_03"))
		qf.apply_build(Rules.hero_body({"race": "Human", "sex": "female",
			"build": {"chest": 100, "frame": 100, "weight": 100, "height": 100, "build": 100}}))
		assert(qf.skeleton.get_bone_pose(qf.skeleton.find_bone("spine_03")).is_equal_approx(once),
			"q-doll: applying the same build twice must not compound it")
		qf.queue_free()

		# ── The world's cloth ────────────────────────────────────────────────
		# Four families have no wardrobe of their own and wear the fantasy cut
		# in the world's substance instead. Whether that looks GOOD is a picture
		# (tests/doll_shot.gd renders the sheet); whether it is plugged in at all
		# is this, and the two are not the same question — the first version of
		# this feature rendered five identical rangers and nothing said so.
		var qc := ModularDoll.new()
		qc.rig = "quaternius"
		add_child(qc)
		qc.build(load(qc.body_path()))
		for fam in ModularDoll.CLOTH:
			assert(ResourceLoader.exists(str(ModularDoll.CLOTH[fam])),
				"cloth: the %s cloth must actually be in the export" % fam)
		assert(ResourceLoader.exists(ModularDoll.CLOTH_SHADER), "cloth: the shader ships too")
		# A dyed family overrides the garment's material; an undyed one must NOT,
		# because the pack's own leather is already right for it and pouring over
		# a good texture only costs the detail painted into it.
		qc.family = "cyber"
		assert(qc.cloth_tex() != null, "cloth: a dyed family resolves a texture")
		assert(qc.equip("armor", "ranger"), "cloth: the garment still wears")
		var dyed_mat := _first_override(qc)
		assert(dyed_mat is ShaderMaterial, "cloth: a dyed family must reach the garment's material")
		# ...and the poured texture must be the one that family named, not simply
		# SOME shader — a single hardcoded cloth would pass a weaker assertion
		# while every world wore the same jumpsuit.
		assert((dyed_mat as ShaderMaterial).get_shader_parameter("cloth") != null,
			"cloth: the poured texture must reach the shader")
		qc.family = "fantasy"
		assert(qc.cloth_tex() == null, "cloth: fantasy keeps the pack's own leather")
		assert(qc.equip("armor", "ranger"), "cloth: the garment still wears undyed")
		assert(not (_first_override(qc) is ShaderMaterial),
			"cloth: an undyed family must leave the garment's own material alone")
		qc.queue_free()
		print("  cloth: four families dye the garment, the other four are left alone")

	# ── The knobs themselves ─────────────────────────────────────────────────
	# 50 means "whatever heritage and sex say", so an untouched hero is exactly
	# what the rules already describe — the sliders modify, never replace.
	assert(is_equal_approx(Rules.build_factor("height", Rules.BUILD_NEUTRAL), 1.0),
		"build: the neutral notch changes nothing")
	assert(Rules.build_factor("height", 100) > 1.0 and Rules.build_factor("height", 0) < 1.0,
		"build: the knob runs both ways")
	assert(Rules.build_factor("height", 999) == Rules.build_factor("height", 100),
		"build: a knob past its end is clamped, not extrapolated")
	# A Dwarf who drags Height to the top is a TALL DWARF, not an Elf — the knob
	# multiplies the heritage profile rather than overwriting it.
	var dwarf_tall := Rules.hero_body({"race": "Dwarf", "sex": "male", "build": {"height": 100}})
	var human_mid := Rules.hero_body({"race": "Human", "sex": "male", "build": {}})
	assert(float(dwarf_tall["height"]) < float(human_mid["height"]),
		"build: a maxed-out Dwarf is still shorter than an average Human")
	assert(Rules.default_build().size() == Rules.BUILD_KNOBS.size(),
		"build: a fresh hero gets every knob, all neutral")
	for k in Rules.default_build().values():
		assert(int(k) == Rules.BUILD_NEUTRAL, "build: a fresh hero starts neutral everywhere")
	# The forge must ASK, and the answer must reach the sheet.
	var fsrc := FileAccess.get_file_as_string("res://scenes/forge/character_forge.gd")
	assert(fsrc.contains("draft[\"sex\"] = opt"), "forge: the anvil asks for a hero's sex")
	assert(fsrc.contains("Rules.BUILD_KNOBS"), "forge: ...and offers every build knob")
	var gsrc5 := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(gsrc5.contains("s[\"sex\"]") and gsrc5.contains("s[\"build\"]"),
		"forge: a forged hero carries its body onto the sheet")
	print("  build: sex + 5 knobs, neutral means heritage, and a tall Dwarf is still a Dwarf")

	# The Gear page shows the FIGURINE, not a commissioned painting — the whole
	# point is that equipping answers now instead of queueing a GPU job.
	var cs_src := FileAccess.get_file_as_string("res://scenes/ui/character_screen.gd")
	assert(cs_src.contains("DollView.new("), "gear: the Gear page builds the live figurine")
	assert(cs_src.contains("figurine.wear(inv)"), "gear: ...and dresses it from the real inventory")

	# DRESSING BEFORE THE VIEW IS IN THE TREE. The Gear page calls wear() the
	# statement after new(), which is before _ready — so the doll does not exist
	# and the loadout used to vanish in silence. The hero held a dagger and the
	# figurine stood empty-handed, and the source-string assertion above passed
	# happily through it. Drive the real order.
	if ResourceLoader.exists("res://spike3d/models/Knight.glb"):
		var dv := DollView.new()
		# Chest and boots, because those are slots the SHIPPING rig has geometry
		# for. Weapons are not among them — see the note in ModularDoll — so
		# asserting on a sword here would only test the fixture.
		dv.wear({"items": [{"id": "a1", "name": "Studded Leather"}, {"id": "b1", "name": "Riding Boots"}],
			"equipped": {"armor": "a1", "feet": "b1"}})   # BEFORE add_child, as the page does
		add_child(dv)
		assert(dv.doll != null, "gear: the view must own a doll once it enters the tree")
		assert(dv.doll.worn("armor") == "ranger",
			"gear: a loadout set before _ready must still reach the figurine")
		assert(dv.doll.worn("feet") == "ranger", "gear: ...for every slot, not just one")
		# And it must STAND, not hang in the bind pose like a mannequin on a rack.
		# Asserted on the skeleton rather than on AnimationPlayer bookkeeping:
		# "some bone is off its rest transform" is the actual property, and it
		# cannot be satisfied by a player that reports a clip it never applied.
		var sk: Skeleton3D = dv.doll.skeleton
		var posed := 0
		for bi in sk.get_bone_count():
			if not sk.get_bone_pose_rotation(bi).is_equal_approx(sk.get_bone_rest(bi).basis.get_rotation_quaternion()):
				posed += 1
		assert(posed > 0, "gear: the figurine is still in its rest pose — no stance was applied")
		dv.queue_free()
		print("  gear: figurine dressed from a pre-tree loadout, standing, framed")

	# ── The board token ──────────────────────────────────────────────────────
	# The mini is re-rendered per LOADOUT, so the key has to move when the gear
	# does. A key that ignores a slot means you swap your shield and the figurine
	# on the table keeps the old one — and nothing anywhere would report it.
	var kit_a := {"items": [{"id": "w1", "name": "Iron Sword"}, {"id": "s1", "name": "Round Shield"}],
		"equipped": {"weapon": "w1"}}
	var kit_b := {"items": [{"id": "w1", "name": "Iron Sword"}, {"id": "s1", "name": "Round Shield"}],
		"equipped": {"weapon": "w1", "shield": "s1"}}
	assert(Art._loadout_key(kit_a) != Art._loadout_key(kit_b),
		"figurine: taking up a shield must produce a different token")
	assert(Art._loadout_key(kit_a) == Art._loadout_key(kit_a.duplicate(true)),
		"figurine: the same kit must reuse its token rather than re-render forever")
	# The helm has to be IN the pack. Equipping an id the pack does not hold is
	# not a loadout, it is a corrupt save — and the key rightly ignores it, which
	# is what the first version of this assertion mistook for a bug.
	var kit_c := {"items": kit_a["items"] + [{"id": "h1", "name": "Iron Helm"}],
		"equipped": {"weapon": "w1", "head": "h1"}}
	assert(Art._loadout_key(kit_a) != Art._loadout_key(kit_c), "figurine: a helm changes the token")
	var kit_ghost := kit_a.duplicate(true)
	kit_ghost["equipped"] = {"weapon": "w1", "head": "nonesuch"}
	assert(Art._loadout_key(kit_a) == Art._loadout_key(kit_ghost),
		"figurine: wearing an item the pack does not hold changes nothing")
	# Headless cannot render, so it must decline rather than cache a blank square
	# and call it a token — the harnesses would then "pass" on an empty mini.
	assert(Art.figurine_tex(kit_a) == null, "figurine: headless declines instead of caching a blank")
	var asrc := FileAccess.get_file_as_string("res://autoload/art_cache.gd")
	assert(asrc.contains("figurine_tex(GameState.inv())"),
		"figurine: the board's PC token actually asks for the figurine")
	assert(asrc.contains("UPDATE_DISABLED"),
		"figurine: the offscreen viewport is not left rendering forever")
	# A face that lands LATE must reach the initiative rail too. The board
	# repaints every frame and picks it up alone; the rail is built once per
	# roster change, so without this the same combatant wore a figurine on the
	# board and a letter on the rail, on the same screen.
	var gsrc4 := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(gsrc4.contains("Art.art_ready.connect(func(_k):"),
		"figurine: late art must refresh the initiative rail, not just the board")
	print("  figurine: loadout key tracks gear, headless declines, board and rail agree")

	# ── THE CONTRAST GATE ────────────────────────────────────────────────────
	# InteractionLanguage.md has always required body text at >= 4.5:1 "measured
	# per palette". Nothing measured it, and `horror` shipped `danger` at 3.74:1
	# on surface2 — the colour of an error message, at the moment it matters.
	#
	# EVERY palette, not the six the shipped worlds happen to use. The first draft
	# of this gate walked world ids and so never touched `horror` — the only one
	# that was broken. A gate that misses the failing case is decoration.
	var pal_checked := 0
	for pkey in Ui.PALETTES:
		var clamped: Dictionary = Ui.clamp_palette(Ui.PALETTES[pkey])
		var lightest: Color = clamped[Ui.SURFACE_ROLES[0]]
		for s in Ui.SURFACE_ROLES:
			if Ui.relative_luminance(clamped[s]) > Ui.relative_luminance(lightest):
				lightest = clamped[s]
		for t in Ui.TEXT_ROLES:
			if not clamped.has(t):
				continue
			var want: float = Ui.LARGE_MIN if t == "amethyst_deep" else Ui.TEXT_MIN
			var got := Ui.contrast_ratio(clamped[t], lightest)
			assert(got >= want - 0.01,
				"contrast: '%s' on the lightest surface of '%s' is %.2f:1, under %.1f" % [t, pkey, got, want])
		pal_checked += 1
	assert(pal_checked >= 8, "contrast: every palette must be gated, checked %d" % pal_checked)
	print("  contrast: %d palettes clamped and measured against 4.5:1 body / 3.0:1 large" % pal_checked)

	# The clamp must be a no-op on a colour that already passes — a gate that
	# repaints everything is a restyle wearing a gate's clothes.
	var fine := Color("efeafb")
	var dark := Color("0c0a1c")
	assert(Ui.readable_on(fine, dark) == fine, "contrast: a passing colour is left alone")
	# ...and must actually move one that does not.
	var faint := Color("1a1636")
	assert(Ui.contrast_ratio(faint, dark) < Ui.TEXT_MIN, "contrast: the probe colour should start too faint")
	assert(Ui.contrast_ratio(Ui.readable_on(faint, dark), dark) >= Ui.TEXT_MIN,
		"contrast: a failing colour is walked until it reads")

	# A world may choose the HUE and never the darkness — otherwise a model that
	# names a bright dominant washes the whole app pale.
	var deep := Color.from_hsv(0.7, 0.4, 0.12)
	var glare := Color.from_hsv(0.1, 1.0, 1.0)
	var mixed := Ui._hued(deep, glare)
	assert(is_equal_approx(mixed.v, deep.v), "skin: a world's colour must not change a surface's darkness")
	assert(is_equal_approx(mixed.h, glare.h), "skin: ...but it does set the hue")
	assert(mixed.s <= Ui.WORLD_SAT_CAP + 0.001, "skin: saturation is capped so surfaces stay surfaces")

	# ── AT-3: the region tier is drawn AND wired ─────────────────────────────
	var wm := FileAccess.get_file_as_string("res://scenes/ui/world_map.gd")
	var drew_regions := false
	for raw3 in wm.split("\n"):
		if raw3.strip_edges() == "_draw_regions(font)":
			drew_regions = true
	assert(drew_regions, "the chart actually draws its region names")
	assert(wm.contains("_in_focus("), "focusing a region actually changes what is drawn")
	# Roads must be ROUTED across the land, not ruled between the pins. Every
	# road-drawing site goes through _route(); a bare draw_line between two place
	# positions is the straight-line spider-web this replaced.
	assert(wm.contains("_route(pts[best_a], pts[best_b])"), "the inferred web follows the land")
	assert(wm.contains("_route(pa, pb)"), "a named road follows the land")
	assert(wm.contains("_route(here_p, target)"), "the hovered road follows the land")
	assert(wm.contains("AStarGrid2D"), "routing uses the engine's own grid solver")
	# The read is COSMETIC. If a pixel ever decides a journey's cost or peril,
	# the Terrain.md heuristic is back and it is back in the place that matters.
	var gs_src := FileAccess.get_file_as_string("res://autoload/game_state.gd")
	for fn in ["func travel_cost", "func travel_peril", "func travel_blocked"]:
		var seg := gs_src.substr(gs_src.find(fn), 900)
		assert(not seg.contains("get_pixel") and not seg.contains("chart_art"),
			"%s decides from rules, never from the painting" % fn)
	# The tier is worthless if nobody hands it the regions — the exact way the
	# GM-model picker stayed broken for weeks, writing to a key nothing read.
	var gsrc3 := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(gsrc3.contains("map.regions = GameState.regions()"),
		"the Atlas is given the world's regions, not just its places")

	# ── KI-5: a size word must never shadow the category noun ────────────────
	# `Shortbow` used to resolve to "a SHORT blade" and `Great Axe` to "an
	# oversized two-handed weapon", because the size prefix matched first. The
	# clause meant to fix wrong silhouettes was causing them.
	for pair in Rules.SHAPE_WORDS:
		assert(not str(pair[0]) in ["short", "long", "great", "greater", "lesser", "small", "large"],
			"'%s' is a size, not a shape — it shadows the category noun" % str(pair[0]))
	assert(Rules.shape_clause("Shortbow").contains("bow"), "a shortbow is a BOW")
	assert(Rules.shape_clause("Longbow").contains("bow"), "a longbow is a BOW")
	assert(Rules.shape_clause("Great Axe").contains("axe"), "a great axe is an AXE")
	assert(Rules.shape_clause("Long Spear").contains("spear"), "a long spear is a SPEAR")
	# No clause at all beats a wrong one: nothing in the picture gives scale.
	assert(Rules.shape_clause("Shortblade") == "", "a size-only name earns no clause")

	# ── AT-4: every shipped package carries its own chart plate ──────────────
	# Without art/chart.png the Atlas falls through to the biome-0 TACTICAL map,
	# which is painted with buildings because a battlefield wants them — and then
	# the pins disagree with the paper. Skipped on a fresh clone, which has no
	# baked/ at all (it is generated output, and gitignored).
	var bdir := DirAccess.open("res://baked")
	if bdir != null:
		var checked_pkgs := 0
		for zf in bdir.get_files():
			if not zf.ends_with(".zip"):
				continue
			var zrr := ZIPReader.new()
			if zrr.open("res://baked/" + zf) != OK:
				continue
			assert(zrr.file_exists("art/chart.png"),
				"%s ships an Atlas plate of its own (else the chart is a battle map)" % zf)
			zrr.close()
			checked_pkgs += 1
		if checked_pkgs > 0:
			print("  chart plates verified in %d package(s)" % checked_pkgs)

	# ── AT-2: named roads ────────────────────────────────────────────────────
	# A road is only worth naming if it CHANGES something, so every assertion
	# here is about travel, not about storage.
	GameState.state["world"] = {"here": "Alpha", "seen": ["Alpha", "Beta"], "roads": [],
		"places": [{"name": "Alpha", "kind": "tavern", "x": 20, "y": 20},
			{"name": "Beta", "kind": "ruin", "x": 60, "y": 60}]}
	var open_cost := GameState.travel_cost("Beta")
	assert(open_cost >= 1, "a journey is never free")
	assert(is_equal_approx(GameState.travel_peril("Beta"), 0.20), "an unnamed way carries the old 1-in-5")
	assert(GameState.travel_blocked("Beta") == "", "no road means no obstacle — roads modify travel, never gate it")

	# Both ends must already exist, or [[road]] becomes a second way to create a
	# place that skips add_place's veto.
	assert(GameState.set_road({"from": "Alpha", "to": "Atlantis"}) != "", "a road to nowhere is refused")
	assert(GameState.set_road({"from": "Alpha", "to": "Alpha"}) != "", "a road must join two different places")
	assert(GameState.set_road({"from": "Alpha", "to": "Beta", "state": "nonsense"}) != "", "an unknown state is refused")

	assert(GameState.set_road({"from": "Alpha", "to": "Beta", "state": "hard", "name": "the Weir Road"}) == "",
		"the GM may name a road between two known places")
	assert(GameState.travel_cost("Beta") > open_cost, "a hard road costs more hours than an open one")
	assert(GameState.road_between("Beta", "Alpha").get("state") == "hard",
		"a road is the same road from either end")

	assert(GameState.set_road({"from": "Beta", "to": "Alpha", "state": "dangerous"}) == "",
		"the story may spoil a road, naming its ends in either order")
	assert(GameState.roads().size() == 1, "...and that updates the road rather than adding a second")
	assert(GameState.travel_peril("Beta") > 0.5, "a dangerous road is far likelier to meet you")
	assert(GameState.travel_blocked("Beta") == "", "dangerous is not impassable")

	assert(GameState.set_road({"from": "Alpha", "to": "Beta", "state": "blocked"}) == "", "a road can close")
	var shut_why := GameState.travel_blocked("Beta")
	assert(shut_why != "" and shut_why.contains("Beta"), "a closed road turns you back, and says where to")
	assert(GameState.set_road({"from": "Alpha", "to": "Beta", "state": "blocked"}) == "already",
		"closing a closed road is not an event")
	assert(GameState.set_road({"from": "Alpha", "to": "Beta", "state": "open"}) == "", "and a road can reopen")
	assert(GameState.travel_blocked("Beta") == "", "...which lets the player through again")

	# Wired, not merely defined — the same trap as the Atlas roads check.
	var rsrc := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(rsrc.contains("GameState.travel_blocked("), "travel actually consults the road")
	assert(rsrc.contains("GameState.travel_peril("), "the encounter roll actually consults the road")
	assert(not rsrc.contains("randf() < 0.2"), "the hard-coded 1-in-5 is gone, not shadowed")
	assert(rsrc.contains("_gm_makes_road("), "the [[road]] tag is handled")
	var msrc2 := FileAccess.get_file_as_string("res://scenes/ui/world_map.gd")
	var drew := false
	for raw2 in msrc2.split("\n"):
		if raw2.strip_edges() == "_draw_named_roads()":
			drew = true
	assert(drew, "the chart actually draws named roads")
	assert(Composer.PROTOCOL.contains("[[road"), "the GM is told the road tag exists")
	GameState.state.erase("world")

	# ── The first-run tutorial ───────────────────────────────────────────────
	# Fires once per player, survives a reset, and is actually WIRED.
	GameState.coach_reset()
	assert(GameState.coach_once("probe"), "a first-time hint fires the first time")
	assert(not GameState.coach_once("probe"), "...and never again")
	assert(GameState.coach_once("probe2"), "each beat is taught on its own")
	GameState.coach_reset()
	assert(GameState.coach_once("probe"), "Settings can bring the hints back")
	GameState.coach_reset()

	# The lesson from the Atlas roads check: `src.find("_coach(")` matches the
	# FUNCTION DEFINITION too, so deleting every call site still passes. Count
	# lines whose stripped form STARTS a call, and require the four beats by key.
	var gsrc := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(gsrc != "", "game.gd is readable")
	var calls := 0
	for raw in gsrc.split("\n"):
		if raw.strip_edges().begins_with("_coach("):
			calls += 1
	assert(calls >= 4, "every teaching beat is wired, not merely defined (found %d)" % calls)
	# `_coach("<key>"` cannot match `func _coach(key: String`, so this is exact.
	for beat in ["check", "combat", "travel", "contract"]:
		assert(gsrc.contains("_coach(\"%s\"" % beat), "the '%s' beat is taught" % beat)
	# A hint nobody can replay is a bug for the second player on one machine.
	var msrc := FileAccess.get_file_as_string("res://scripts/main_menu.gd")
	assert(msrc.contains("coach_reset()"), "Settings can replay the hints")

	print("SELF-CHECK OK")
	get_tree().quit(0)


## The first surface-override material on any mesh the doll is currently
## wearing. Walked rather than looked up by path, because the holder's shape is
## ModularDoll's business and a test that hardcodes it breaks on every rig swap
## while proving nothing about the dye.
func _first_override(doll: ModularDoll) -> Material:
	for n in _meshes_under(doll):
		if n.mesh == null:
			continue
		for i in n.mesh.get_surface_count():
			var m := n.get_surface_override_material(i)
			if m != null:
				return m
	return null


func _meshes_under(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes_under(c))
	return out

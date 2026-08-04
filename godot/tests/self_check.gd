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

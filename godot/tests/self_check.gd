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
	# PY-3 - THE SHEET OWNS WHICH ABILITY A SKILL USES, not the narrator. Seen in
	# play: the GM wrote Insight against INT, the bar read d20 +1 and resolved
	# 16 +1 = 17, while the player's own Skills tab said "Insight (WIS) +0" three
	# clicks away. SKILL2AB had known the right answer since it was written and
	# only is_proficient ever asked it.
	#
	# The wrong ability is passed DELIBERATELY here, because that is what the
	# defect looked like - a check that only ever passed the right one would go
	# green with the bug still in.
	assert(Rules.check_ability({"ability": "INT", "skill": "Insight"}) == "WIS",
		"check ability: a named skill overrules the ability the narrator asked for")
	assert(Rules.check_mod(sheet, {"ability": "INT", "skill": "Insight"})
		== Rules.check_mod(sheet, {"ability": "WIS", "skill": "Insight"}),
		"check ability: ...and the modifier is the same either way")
	assert(Rules.check_label({"ability": "INT", "skill": "Insight"}).begins_with("Wisdom"),
		"check ability: ...and the label does not still say Intelligence")
	# A bare ability check and a saving throw have no skill to appeal to, so the
	# tag stays the only source and must be honoured.
	assert(Rules.check_ability({"ability": "STR"}) == "STR",
		"check ability: a bare ability check keeps the ability it was given")
	assert(Rules.check_ability({"ability": "CHA", "skill": "save"}) == "CHA",
		"check ability: a saving throw keeps its ability")
	assert(Rules.check_ability({"ability": "INT", "skill": "Hotwiring"}) == "INT",
		"check ability: a skill the engine does not know keeps the narrator's ability")
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

	# PY-2 - TAG DEBRIS THE PLAYER ACTUALLY SAW. A played session put raw markup
	# in the chat twice: `dc=15]` alone on a line, then all of
	# `[check ability=WIS insight dc=15]`. The model had used SINGLE brackets, so
	# the parser correctly declined to act on it and then showed it verbatim - the
	# player reads markup AND loses the roll. Three shapes escaped the old
	# scrubber; these are the exact strings, not paraphrases of them.
	for debris in [
			"The console hums.
[check ability=WIS insight
dc=15]",
			"Vex leans in with interest.

dc=15]",
			"Echo looks up. [check ability=WIS insight dc=15]",
			"You steady your hand. [check ability=WIS skill=Insight adv=1 reason=\"reading the ledger\" dc=15]",
			"[Active Perception]"]:
		var scrubbed := str(Tags.parse(str(debris))["clean"])
		assert(not scrubbed.contains("dc=15]") and not scrubbed.contains("[check")
			and not scrubbed.contains("[Active"),
			"tag debris: %s survived into the bubble" % scrubbed)
	# ...and PROSE MUST SURVIVE. A scrubber that eats a bracketed aside is a worse
	# bug than the one it fixes, and the blank-line guard is what protects it.
	assert(Tags.parse("He paused [he always did] and looked up.")["clean"].contains("[he always did]"),
		"tag debris: a bracketed aside in prose was eaten")
	assert(Tags.parse("She left.

[I never saw her again.]

The rain kept on.")["clean"].contains("[I never saw her again.]"),
		"tag debris: an aside across paragraphs was eaten")
	assert(Tags.parse("the sign read [VEX'S] in faded letters")["clean"].contains("[VEX'S]"),
		"tag debris: a bracketed sign in prose was eaten")
	# The real protocol still parses, including across a newline.
	assert(Tags.parse("[[check ability=DEX skill=Stealth dc=13]]")["tags"].size() == 1,
		"tag debris: the widened scrubber must not stop a real tag parsing")

	# PY-1 - THE NARRATOR IS NOT TOLD THE NUMBER. Seen in play: the engine handed
	# the GM "bought a Shock Blade (25 credits)" and asked it to colour the
	# exchange, and it wrote "your purse is 30 credits lighter" - a figure nothing
	# in the engine ever produced, in a game whose contract is that the table owns
	# every number. The player keeps the exact amount; only the model's copy loses
	# it, and only parentheticals carrying a digit.
	assert(Composer.without_amounts("bought a Shock Blade (25 credits)") == "bought a Shock Blade",
		"amounts: the price still reaches the narrator")
	assert(Composer.without_amounts("sold a Mono-Knife (3 credits); haggled (won a fifth off)")
		== "sold a Mono-Knife; haggled (won a fifth off)",
		"amounts: a parenthetical WITHOUT a number is flavour and must survive")
	assert(not Composer.without_amounts("At the trader: bought a Shock Blade (25 credits).").contains("25"),
		"amounts: a digit survived into the narrator's copy")
	# The play screen must actually USE it - the helper existing proves nothing.
	var shop_src := FileAccess.get_file_as_string("res://scripts/game.gd")
	var told_at := shop_src.find("Briefly color the exchange")
	assert(told_at >= 0, "amounts: the counter-left prompt is gone")
	assert(shop_src.substr(maxi(0, told_at - 400), 800).contains("without_amounts"),
		"amounts: the counter-left prompt hands the narrator the raw summary again")

	# PY-4 - THE ENGINE MUST NOT TELL THE NARRATOR THE WRONG WORD. The sheet
	# summary hardcoded "Purse: %d gold" for every world, so Neon Spire handed the
	# GM "Purse: 95 gold" and it duly charged the player "50 gold pieces" in a city
	# whose HUD, merchant and starting kit all say credits. The model was
	# repeating us, not inventing. Asserted per world, because a summary that said
	# "credits" everywhere would be the same bug pointing the other way.
	var world_was = GameState.character.get("world_id", "")
	for pair in [["embervale", "gold"], ["neonspire", "credits"]]:
		GameState.character["world_id"] = str(pair[0])
		assert(GameState.currency() == str(pair[1]),
			"currency: %s should trade in %s" % [pair[0], pair[1]])
		var told := Composer.sheet_summary(GameState.sheet())
		assert(told.contains("Purse: %d %s" % [int(GameState.sheet().get("gold", 0)), str(pair[1])]),
			"currency: the narrator is not told %s calls its money %s" % [pair[0], pair[1]])
	GameState.character["world_id"] = "neonspire"
	assert(not Composer.sheet_summary(GameState.sheet()).contains(" gold."),
		"currency: the sheet still says gold in a credits world")

	# PY-6 - THE BANNER FOLLOWS THE PURSE. Buying a 25-credit blade left the
	# merchant reading "Your purse: 4 credits" while the chip row above it still
	# said 29 - two truths on one screen for as long as the player kept shopping.
	# Announced from add_gold, which every delta goes through, so a [[gold]] tag
	# and a sale are covered too and not just the case that was noticed.
	var purse_fired := [0, -1]
	GameState.purse_changed.connect(func(t): purse_fired[0] += 1; purse_fired[1] = t)
	# A known purse first: add_gold clamps at zero, so a delta bigger than the
	# balance would make the arithmetic here wrong rather than the code.
	var s_purse := GameState.sheet()
	s_purse["gold"] = 40
	GameState.set_sheet(s_purse)
	GameState.add_gold(-25)
	assert(purse_fired[0] == 1, "purse: add_gold did not announce the change")
	assert(purse_fired[1] == 15, "purse: announced %d, the sheet says 15" % purse_fired[1])
	assert(int(GameState.sheet().get("gold", 0)) == 15, "purse: the sheet itself did not move")
	GameState.add_gold(5)
	assert(purse_fired[0] == 2 and purse_fired[1] == 20, "purse: a credit does not announce")
	# ...and the play screen must actually listen, or the signal is decoration.
	var chips_src := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(chips_src.contains("GameState.purse_changed.connect("),
		"purse: the play screen does not listen for a purse change")
	# PY-9 - THE NATURE PAGE MUST SHOW THE ORDER THE SHEET WILL USE. It displayed
	# the sorted roll against the canonical STR..CHA order while new_hero_sheet
	# assigned by class priority, so a Warlock read "15 STR / 9 CHA" on the one
	# page whose promise is "the best land where your class wants them" - and a
	# player rerolls off that screen. The numbers committed were always right; the
	# screen was the lie, which is why this asserts the two AGREE rather than
	# asserting either alone.
	for cls_ab in [["Warlock", "CHA"], ["Wizard", "INT"], ["Cleric", "WIS"], ["Fighter", "STR"], ["Rogue", "DEX"]]:
		var prio_now := Rules.ability_priority(str(cls_ab[0]))
		assert(str(prio_now[0]) == str(cls_ab[1]),
			"nature: a %s wants its best score in %s, not %s" % [cls_ab[0], cls_ab[1], prio_now[0]])
		var built := GameState.new_hero_sheet("Probe", "Human", str(cls_ab[0]), [15, 14, 13, 12, 10, 8] as Array[int])
		var abil: Dictionary = built.get("abilities", {})
		var best := ""
		for ab_k in abil:
			if best == "" or int(abil[ab_k]) > int(abil[best]):
				best = str(ab_k)
		assert(best == str(cls_ab[1]),
			"nature: a %s committed its best score to %s, but the page shows %s" % [cls_ab[0], best, cls_ab[1]])
	# The forge must READ that same order rather than keeping its own copy.
	var forge_src := FileAccess.get_file_as_string("res://scenes/forge/character_forge.gd")
	assert(forge_src.contains("Rules.ability_priority(str(draft[\"cls\"]))"),
		"nature: the forge displays the roll against its own order again")
	# PY-10 - the standard array can no longer be built into an illegal state. The
	# refusal on Strike is real and stays; the pickers swap so it is unreachable.
	assert(forge_src.contains("SWAP, do not duplicate"),
		"nature: the standard-array pickers no longer swap")
	assert(forge_src.contains("must be used exactly once"),
		"nature: the array refusal was removed — the swap is a convenience, not the guard")
	GameState.character["world_id"] = world_was
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
	# …and every key whose PROMPT carries that flavour must carry the world in
	# the KEY too, or one world is served another's paintings. `race-tiefling.png`
	# sat in the cache with no family on it while `_race_prompt` fed it
	# `world_flavor()` — so a Tiefling painted in Embervale was handed straight
	# back in Neonspire. Fantasy stays unsuffixed on purpose; every other family
	# must differ from it AND from each other.
	var fam_keys := {}
	for probe in [["embervale", "fantasy"], ["neonspire", "cyber"], ["brasshaven", "steam"]]:
		GameState.character = {"id": "dm-key-probe", "world_id": str(probe[0])}
		for k in [Art.race_key("Tiefling"), Art.item_key("Healing Potion"),
				Art.beast_key("ogre"), Art.map_key("The Ember & Oak"),
				Art.npc_key("Cael Mercer"), Art.foe_key("Samuel Jenkins"),
				Art.class_key("Wizard"), Art.bg_key("Acolyte")]:
			assert(not fam_keys.has(k),
				"art key '%s' is reused across worlds — its prompt is world-flavored, so the first world to paint it wins" % k)
			fam_keys[k] = true
	GameState.character = {"id": "dm-key-probe", "world_id": "embervale"}
	assert(Art.race_key("Tiefling") == "race-tiefling")        # fantasy: unsuffixed, as shipped
	assert(Art.fam_base(Art.beast_key("ogre")) == "beast-ogre")
	GameState.character = {"id": "dm-key-probe", "world_id": "neonspire"}
	assert(Art.fam_base(Art.beast_key("ogre")) == "beast-ogre")  # the slug survives the round trip
	GameState.character = keep_w
	# …and every SHIPPED world must resolve to its own family without anyone
	# having entered it first. A world absent from BUILTIN falls through to the
	# "fantasy" default, and because art keys are family-scoped it then eats
	# Embervale's paintings whole. saltmarsh shipped that way and it took a
	# real warm run to notice: 0 pictures painted, 0.0 minutes, everything it
	# asked for already on disk.
	var shipped: Array = Rules.worlds_json.get("worlds", [])
	for w in shipped:
		var wid := str(w.get("id", ""))
		if wid == "":
			continue
		assert(WorldSkin.BUILTIN.has(wid),
			"shipped world '%s' is not in WorldSkin.BUILTIN — it resolves to the fantasy default and will be served Embervale's art" % wid)

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
	# An object tile is prompted onto "a plain flat dark grey background", so a
	# boulder arrives as a grey SQUARE. `board_paint._key_background` lifts that
	# field out at composite time. Nothing proved it — TechnicalDebt still carried
	# the row as open, which is how a paid debt starts looking like an open one.
	#
	# ASSERT BOTH DIRECTIONS. "an object tile has transparency" alone passes for a
	# keyer that has gone mad and erased the boulder too, so the ground roles are
	# checked to be FULLY opaque in the same breath. Measured on fimbulreach:
	# boulder 68.5 %, crates 78.3 %, grass and dirt 0.0 %.
	var bp := load("res://scenes/combat/board_paint.gd")
	for probe in [["boulder", true], ["crates", true], ["grass", false], ["dirt", false]]:
		var pi: Image = bp._tile("fimbulreach", str(probe[0]), 1)
		assert(pi != null, "board paint: no '%s' tile for fimbulreach — is the world package unpacked?" % probe[0])
		var clear := 0
		for py in pi.get_height():
			for px in pi.get_width():
				if pi.get_pixelv(Vector2i(px, py)).a < 0.02:
					clear += 1
		var pct := 100.0 * float(clear) / float(pi.get_width() * pi.get_height())
		if bool(probe[1]):
			assert(pct > 25.0, "board paint: '%s' keeps its studio background (%.1f%% clear) — it will draw as a grey square" % [probe[0], pct])
			assert(pct < 95.0, "board paint: '%s' was keyed away almost entirely (%.1f%% clear) — the object is gone, not its background" % [probe[0], pct])
		else:
			assert(pct < 2.0, "board paint: ground role '%s' is %.1f%% transparent — the keyer is eating material tiles" % [probe[0], pct])
	print("  board paint: object tiles keyed off their studio field, ground tiles left opaque")
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

	# ── IF YOU CAN STILL TALK, A FIGHT CAN STILL START ───────────────────────
	# The GM answers any message, and one of the answers is an ambush. So every
	# state that allows send_message has to declare Combat as a legal exit, or
	# the fight that follows is an undeclared transition the renderer forces
	# while Mode.enter logs a warning — which is exactly how Dialogue, Merchant,
	# Victory and Camp sat broken.
	#
	# DERIVED, NOT LISTED. A hardcoded list of four states would pass forever
	# while a fifth state added next year quietly repeats the bug. This reads the
	# machine and re-derives the rule, so the new state fails the day it lands.
	for st in Mode.STATES:
		var acts: Array = Mode.STATES[st]["allowed"]
		if not acts.has("send_message") or st == "GameOver":
			continue   # the run is over — see state_manager
		if st != "Combat":
			assert(Mode.STATES[st]["to"].has("Combat"),
				"%s lets the player speak but cannot enter Combat — a fight declared there is an undeclared transition" % st)
		# ...and the same reply can award XP. Combat → LevelUp is the one that
		# fired in practice: killing the last enemy levels you mid-fight, and the
		# ceremony forced an undeclared transition every time.
		if st != "LevelUp":
			assert(Mode.STATES[st]["to"].has("LevelUp"),
				"%s lets the player speak but cannot enter LevelUp — XP awarded there is an undeclared transition" % st)
	# And the converse, so "just add Combat everywhere" is not the fix: a state
	# where nothing can be said must not reach Combat either.
	assert(not Mode.STATES["MainMenu"]["to"].has("Combat"), "the menu is not a place a fight can start")
	assert(not Mode.STATES["GameOver"]["to"].has("Combat"), "the dead do not get ambushed")
	assert(not Mode.STATES["GameOver"]["to"].has("LevelUp"), "no level-up ceremony over an epitaph")
	# ...and the screen must agree with the map, or the transition is merely
	# forced with a warning instead of declared — which is how it was.
	var gsrc_lvl := FileAccess.get_file_as_string("res://scripts/game.gd")
	var cer := str(gsrc_lvl.split("func _level_up_ceremony")[1]).substr(0, 500)
	assert(cer.find("GameOver") >= 0 and cer.find("GameOver") < cer.find('Mode.enter("LevelUp")'),
		"the level-up ceremony opens over a finished run — it must refuse before changing mode")

	# ── ONE FLAG FOR "A REPLY IS IN FLIGHT" ──────────────────────────────────
	# `Mode.busy` is an autoload and survives a scene change, so a path that
	# stops a stream without clearing it strands the game: `Mode.can()`
	# short-circuits on busy, so the NEXT adventure refuses every message the
	# player types until the app restarts. That is exactly what happened while a
	# private `_streaming` mirrored it — `_leave_to_hall` cleared the copy and
	# forgot the original.
	#
	# A SOURCE CHECK, deliberately, and the repo distrusts those for good reason.
	# It is right here only because the defect IS a fact about the source: the
	# existence of a second flag. Nothing about behaviour is being inferred from
	# a string — the behaviour is asserted above, at "busy blocks every action".
	var gsrc_busy := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(not gsrc_busy.contains("var _streaming"),
		"a second streaming flag is back; Mode.busy is the one source and a copy will drift from it")
	# Whatever cancels a stream must say the game is no longer waiting on one.
	var parts := gsrc_busy.split("Api.cancel_stream()")
	for i in range(1, parts.size()):
		assert(str(parts[i]).substr(0, 220).contains("Mode.busy = false"),
			"a stream is cancelled without clearing Mode.busy — the next adventure will refuse every message")

	# ── RESUMING A SAVED FIGHT MUST NOT LAND IN EXPLORATION ──────────────────
	# `_boot` renders a persisted fight — which enters Combat — and then used to
	# call `Mode.enter("Exploration")` unconditionally ten lines later, throwing
	# that away. The player resumed a saved battle into a mode where
	# `can("combat_action")` is false and every attack refused until a click
	# healed it. Nothing warned, because Combat → Exploration is legal.
	for st in Mode.FIGHT_OWNED:
		Mode.state = st
		assert(Mode.fight_owned(), "%s owns the fight and must not be overridden" % st)
	for st in ["Exploration", "Dialogue", "Merchant", "Camp", "Victory"]:
		Mode.state = st
		assert(not Mode.fight_owned(), "%s does not own a fight and may be entered normally" % st)
	# ── THE DICE MENU'S ID BLOCKS MUST NOT COLLIDE ───────────────────────────
	# A renumbering here does not crash: a colliding item falls through to the
	# ability-check path and rolls a d20 at the player instead of doing what the
	# menu said. Silent wrong behaviour, which is the kind this repo asserts.
	var Play := preload("res://scripts/game.gd")
	# The expression item sits one below the tray, and the tray is tested FIRST
	# with `>=`. Move it above and "Roll an expression…" silently becomes a die.
	assert(Play.DICE_EXPRESSION < Play.DICE_TRAY_BASE,
		"the raw-dice tray starts at or below the expression item and would swallow it")
	# Recipes carry an index, so the block has to end before the ask-the-GM ids.
	assert(Play.DICE_RECIPE_END <= Play.DICE_LEARN_SPELL,
		"the recipe block runs into the ask-the-GM ids")
	for a in [Play.DICE_LEARN_SPELL, Play.DICE_RECRUIT, Play.DICE_CRAFT, Play.DICE_INSPIRATION]:
		assert(a < Play.DICE_EXPRESSION, "an ask-the-GM id collides with the dice items")
		assert(a >= Play.DICE_RECIPE_END, "an ask-the-GM id falls inside the recipe block")
	# Skills and raw abilities take small sequential ids; the gap to the special
	# blocks is what keeps a long skill list from reaching them.
	assert(Play.DICE_RECIPE_BASE > 200,
		"the special id blocks are too close to the sequential skill/ability ids")

	# ── THE BOOT STAYS A LIST OF PHASES ──────────────────────────────────────
	# `_ready` was 215 lines, and that is not a style complaint: PL-4 lived in it.
	# `_render_combat()` entered Combat and a `Mode.enter("Exploration")` ten
	# lines later threw it away — invisible in a wall of code, obvious in a list
	# of five named calls. The ceiling is what protects that, so it is asserted:
	# the day someone inlines a sixth thing back into the boot, this fails.
	var gsrc_ready := FileAccess.get_file_as_string("res://scripts/game.gd")
	var ready_body := str(gsrc_ready.split("func _ready() -> void:")[1]).split("\nfunc ")[0]
	assert(ready_body.split("\n").size() < 30,
		"_ready is growing back into a wall (%d lines) — the boot is a list of phases, put the work in one" % ready_body.split("\n").size())
	var phase_order := ["_wire_signals()", "_build_chrome()", "_open_the_room()", "_open_the_adventure()"]
	var at := -1
	for ph in phase_order:
		var here := ready_body.find(ph)
		assert(here > at, "the boot phases are out of order at %s — chrome builds what the room paints into" % ph)
		at = here

	# The boot path itself: the resume must ASK before forcing Exploration. This
	# is structural — the bug was a correct decision overwritten a few lines
	# later, which no value check can see, only the order of the two statements.
	var gsrc_boot := FileAccess.get_file_as_string("res://scripts/game.gd")
	var after_forge := str(gsrc_boot.split("_open_character_forge()")[1]).substr(0, 900)
	var guard_at := after_forge.find("Mode.fight_owned()")
	var force_at := after_forge.find('Mode.enter("Exploration")')
	assert(guard_at >= 0 and force_at >= 0 and guard_at < force_at,
		"the resume forces Exploration without asking whether a saved fight is still on")
	# PY-22 — EVERY SHIPPED WORLD'S KIT MUST RESOLVE. A kit id that misses is not
	# a cosmetic miss: `kit_for` returns an empty array, `character_forge` falls
	# back to its hardcoded FANTASY kit, and a Warlock in a neon city is handed a
	# Quarterstaff, Traveler's Leathers and a Healing Potion. Found by playing the
	# game, not by any harness. Measured at the time: 66 ids across five worlds did
	# not resolve — neonspire, everyday and fimbulreach 16 of 20 each — and the
	# fallback was SILENT, which is why it survived to a played session.
	#
	# A world shipping no kits.json is skipped; a world that has one must resolve
	# every id in it.
	for wid in ["embervale", "neonspire", "brasshaven", "everyday", "fimbulreach"]:
		var kp := "%s/data/kits.json" % Compiler.world_dir(wid)
		if not FileAccess.file_exists(kp):
			continue
		var kdata = JSON.parse_string(FileAccess.get_file_as_string(kp))
		if not (kdata is Dictionary):
			continue
		for arch in kdata:
			var want_n := int((kdata[arch].get("items", []) as Array).size())
			var got_n := int(Compiler.kit_for(wid, str(arch)).size())
			assert(got_n == want_n,
				"world kit: %s/%s resolved %d of %d items — the forge falls back to the generic FANTASY kit" % [wid, arch, got_n, want_n])
	print("  world kits: every archetype in every shipped world resolves to real catalogue items")

	# PL-9, and structural for the same reason: the narrator must be woken BEHIND
	# the curtain. Its nodes are built lazily by the first `stream()`, so the
	# ~4.6 GB load used to land on the player's first sentence — `bench_gm`
	# measured turn 1 at 9.0 s against 2-4 s after. Warming under `MythLoading`
	# put 4.5 s of labelled progress on the loading screen and brought turn 1 to
	# 3.6 s. The seconds did not vanish; they became visible. Nothing offline can
	# measure that (no model under `Api.test_mode`), but the wiring is exactly
	# what would rot: reorder these two and the load walks back into turn 1 with
	# every harness still green.
	var warm_at := gsrc_boot.find("await LocalGM.warm()")
	var lift_at := gsrc_boot.find("MythLoading.lift()")
	assert(warm_at >= 0, "boot: the narrator is never warmed — turn 1 pays the model load again (PL-9)")
	assert(lift_at >= 0, "boot: the loading curtain is never lifted")
	assert(warm_at < lift_at,
		"boot: the curtain lifts BEFORE the narrator is warm — the load moves back into the player's first sentence")
	# THE IMAGE ENGINE MUST NOT TAKE THE CARD FIRST. sd-server loads its whole
	# checkpoint into VRAM at startup, before it listens - its own log says
	# "total params memory size = 6624.11MB (VRAM 6624.11MB, RAM 0.00MB)" - and its
	# small working set is system RAM, which is what made "it loads per request"
	# look true for so long. llama.cpp fixes its GPU/CPU split once, at load, and
	# the engine's first image takes 6.6 GB it never gives back - 19.3 s per turn
	# against 3.7 s for the whole session. Warming first is what keeps the engine
	# from ever generating before the narrator has its split. Structural, like the
	# curtain above: the order is the fix, and the order is what rots.
	var eng_at := gsrc_boot.find("Services.ensure_engine()")
	assert(eng_at >= 0, "boot: nothing starts the image engine — art will never appear")
	assert(warm_at < eng_at,
		"boot: the image engine is started BEFORE the narrator warms — its first image takes 6.6 GB it never returns, and the narrator would keep the worse split all session")
	var svc_src := FileAccess.get_file_as_string("res://autoload/services.gd")
	assert(not svc_src.contains("call_deferred(\"ensure_engine\")"),
		"boot: Services starts the engine at boot again — that is before the narrator loads")

	# PY-15. EVERY shipped world must be able to produce an establishing prompt,
	# and it must fit inside SDXL's first 77-token chunk — past that, text still
	# reaches cross-attention but never touches the POOLED embedding that carries
	# global style, so a long prompt gives each world a different amount of
	# style-bearing text. Three of six worlds had no prompt at all and `request()`
	# returned silently for them. ~1.3 CLIP tokens per English word.
	for w in Rules.builtin_worlds():
		var pw := Art.world_prompt(str(w.get("id", "")))
		assert(pw != "",
			"world '%s' can produce no establishing prompt — its card will be a bare glyph for ever" % str(w.get("id", "")))
		var approx := int(float(pw.split(" ").size()) * 1.3) + pw.count(",")
		assert(approx <= 75,
			"world '%s' prompt is ~%d tokens — past chunk 0, where SDXL's style vector stops looking" % [str(w.get("id", "")), approx])

	# INVARIANTS.MD IS CHECKED AGAINST REALITY. Three of its rows went stale within
	# an hour of it being written - listed as gaps while their checks were being
	# committed in the same session. A tracker that drifts is worse than none,
	# because it reads as information; that is why this repo deleted a 107-row
	# feature matrix. So every check NAME quoted in the Enforced table must exist
	# in this file or in verify.ps1. Claiming a check you did not write is red.
	#
	# The separators are BUILT from char(), not escaped. Writing them as escapes
	# is how the first version of this block shipped a string literal containing a
	# real newline and parsed zero rows while reporting success.
	var NEWLINE := char(10)
	var OPENQ := "*" + char(34)
	var CLOSEQ := char(34) + "*"
	var inv := FileAccess.get_file_as_string("res://docs/Invariants.md")
	assert(inv != "", "Invariants.md is missing - CLAUDE.md points every change at it")
	var vps := FileAccess.get_file_as_string("res://../scripts/verify.ps1")
	# EVERY HARNESS, not just this one. The parser read self_check.gd and the gate
	# script alone, so an invariant enforced anywhere else could not be declared —
	# which quietly pushed new checks INTO this file to satisfy the parser rather
	# than into the harness they belong to. `town_probe` was the first row that hit
	# it, and the row is not wrong; the reader was too narrow.
	var me := ""
	for f in DirAccess.get_files_at("res://tests"):
		if str(f).ends_with(".gd"):
			me += FileAccess.get_file_as_string("res://tests/" + str(f))
	var in_enforced := false
	var claims := 0
	for line in inv.split(NEWLINE):
		if line.begins_with("## "):
			in_enforced = line.begins_with("## Enforced")
			continue
		if not in_enforced or not line.begins_with("| "):
			continue
		var q := line.split(OPENQ)
		if q.size() < 2:
			continue
		var needle := str(q[1]).split(CLOSEQ)[0]
		if needle.strip_edges() == "":
			continue
		claims += 1
		assert(me.contains(needle) or vps.contains(needle),
			"Invariants.md claims a check that does not exist: '%s' - write the check, or move the row to Not yet enforced" % needle)
	assert(claims >= 8, "Invariants.md: only %d enforced rows parsed - the table shape changed and this check went blind" % claims)
	print("  invariants: %d enforced rows, every claimed check found" % claims)

	# A SHIPPED WORLD KEEPS ITS AUTHORED ACCENT. Every builtin is compiled, and
	# the pack accent was replacing all four hand-tuned palettes. Two came out
	# visibly wrong: brasshaven — "brass, soot and secrets" — rendered PALE BLUE
	# (#c9d3f5 over an authored #d69a52), and Neon Spire rendered ORANGE (#ff8400
	# over an authored #2de2e6 cyan). A forged world has no authored palette and
	# still needs its pack's accent, so the split is exactly BUILTIN.
	var pal_keep2 := Ui.pal.duplicate(true)
	var wid_keep2 := Ui.world_id
	for probe2 in ["neonspire", "brasshaven", "embervale"]:
		Ui.apply(probe2)
		var authored: Dictionary = Ui.PALETTES.get(str(WorldSkin.skin_for_id(probe2).get("palette", "arcane")), {})
		if authored.has("gold"):
			assert(Ui.c("gold").is_equal_approx(authored["gold"]),
				"a shipped world's authored accent was overruled by its generated pack — %s wanted %s, got %s (Invariants.md)" % [
					probe2, Color(authored["gold"]).to_html(false), Ui.c("gold").to_html(false)])
	Ui.apply(str(wid_keep2))
	Ui.pal = pal_keep2

	# PY-14, THE REAL ONE. Measured from a windowed screenshot, not from source:
	# `Ui.c("gold")` came back #ff8706 on Neon Spire while its palette says
	# #2de2e6. The world is COMPILED, so `_overlay_world_palette` replaces the
	# primary accent with the pack's (#ff8400) — and left the SECONDARY at the
	# palette's magenta. Orange beside magenta, neither of them the authored cyan:
	# "two accents on one screen". The earlier repaint_on_skin fix was for a real
	# but different bug and never touched this.
	var pal_keep := Ui.pal.duplicate(true)
	var wid_keep := Ui.world_id
	if Compiler.is_compiled("neonspire"):
		Ui.apply("neonspire")
		# TEST THE DERIVATION, not a distance. The first version of this asserted
		# the two hues sat 0.18-0.5 apart on the wheel — and orange-to-magenta,
		# which IS the bug, measures 0.196. It passed the mutation. A band that
		# admits the failure it was written for is not a check.
		var acc_h := Ui.c("gold").h
		var want_h := fposmod(acc_h + 0.38, 1.0)
		var got_h := Ui.c("amethyst").h
		var off := absf(want_h - got_h)
		off = minf(off, 1.0 - off)   # around the wheel, not across it
		assert(off < 0.04,
			"PY-14: the secondary accent is not derived from the world's own — expected hue %.3f, got %.3f. A compiled world that overlays only its primary leaves two unrelated accents on one screen (Invariants.md)" % [want_h, got_h])
	Ui.apply(str(wid_keep))
	Ui.pal = pal_keep

	# PY-26. A CITY IS NOT A RIVER VALLEY. The chart asked every world for "open
	# country — terrain, water, forest, hills and coast", so Neon Spire's minimap
	# during a scene in The Undercity was a neon-tinted wilderness. The Atlas rule
	# it cites ("nothing that claims a position") is about POSITION, not biome.
	var keep26 := GameState.character
	GameState.character = {"id": "dm-chart-probe", "world_id": "neonspire"}
	var cyber_ground := Art.chart_ground("neonspire")
	GameState.character = {"id": "dm-chart-probe", "world_id": "embervale"}
	var fant_ground := Art.chart_ground("embervale")
	GameState.character = keep26
	assert(cyber_ground != fant_ground, "PY-26: a megacity and a green valley get the same chart ground")
	assert(cyber_ground.contains("blocks") or cyber_ground.contains("districts"),
		"PY-26: the cyber chart does not describe a city")
	assert(fant_ground.contains("forest") or fant_ground.contains("hills"),
		"PY-26: the fantasy chart lost its open country")
	assert(Art.chart_ground("no-such-world") == fant_ground,
		"PY-26: an unknown world must fall back to open country, not to nothing")
	# …and the prompt must DESCRIBE, not forbid. This exact prompt is the one
	# `ensure_item_icon`'s RCA is about: it forbade buildings and text and the
	# bake produced "a painted city and two misspelled cartouches".
	var chart_src := FileAccess.get_file_as_string("res://autoload/art_cache.gd")
	var chart_at := chart_src.find("illustrated %s of the lands around")
	assert(chart_at >= 0, "PY-26: the chart prompt is gone — this check has gone blind")
	var chart_txt := chart_src.substr(chart_at, 320)
	# AND THE BAKE MUST NOT KEEP ITS OWN COPY. world_compiler carried a hand-copy
	# labelled "the runtime twin of this prompt", so PY-26 fixed the twin and the
	# bake — which is what a COMPILED world actually draws — kept painting
	# wilderness. Re-baking would have reproduced the bug faithfully.
	var wc_src := FileAccess.get_file_as_string("res://autoload/world_compiler.gd")
	assert(wc_src.contains("Art.chart_prompt("),
		"PY-26: the bake does not use Art.chart_prompt — a second copy of that prompt is how the runtime fix missed every compiled world (Invariants.md)")
	assert(not wc_src.contains("overhead view of open country"),
		"PY-26: world_compiler still spells the chart prompt by hand")
	for forbid in ["no buildings", "no settlements", "no text labels", "no border"]:
		assert(not chart_txt.contains(forbid),
			"PY-26: the chart prompt still says \"%s\" — a negative inside a positive prompt does not work, and this prompt is the RCA (Invariants.md)" % forbid)

	# PY-23. A world may be plain; it may not be MEDIEVAL by accident. Forms carry
	# "a shape prompt only" on the theory that the world's anchor makes them
	# world-true — which holds for a circlet and fails for a halberd. Neon Spire
	# shipped halberds, mail coifs and kite shields and offered no pistol at all.
	var fantasy_forms: Array = Compiler._forms({})
	var cyber_forms: Array = Compiler._forms({"family": "cyber"})
	assert(fantasy_forms.size() > 40, "PY-23: the base form spine collapsed")
	var fids := {}
	for f in fantasy_forms:
		fids[str(f.get("id", ""))] = true
	var cids := {}
	for f in cyber_forms:
		cids[str(f.get("id", ""))] = true
	# The era-locked shapes must be GONE from a cyber world…
	for banned in ["halberd", "glaive", "pike", "coif", "mail_chausses", "greaves",
			"kite_shield", "targe", "mail_gloves", "gauntlets", "sandals", "parry_dagger"]:
		if fids.has(banned):
			assert(not cids.has(banned),
				"PY-23: a cyber world is still offered '%s' — no prompt anchor makes that cyberpunk (Invariants.md)" % banned)
	# …and it must actually have something of its own to swing and shoot.
	for want in ["monoblade", "service_pistol", "deck"]:
		assert(cids.has(want), "PY-23: a cyber world has no '%s' — the override table is not reaching _forms()" % want)
	# A family with no overrides keeps the universal spine, unchanged.
	var norse_forms: Array = Compiler._forms({"family": "norse"})
	assert(norse_forms.size() == fantasy_forms.size(),
		"PY-23: a family with no overrides must keep the universal shapes, not lose them")

	# PY-7. AN INSTRUCTION THAT DOES NOT MOVE THE PLAYER MUST SAY SO. The location
	# is already in the envelope, near the top — and a trailing "briefly color the
	# exchange" or "narrate the outcome" is an open invitation to invent a scene.
	# Recency wins in a long context. `GameState.here_pin()` was written for CN-1
	# (camped at a barrow-mound, woke in a mead-hall) and applied ONLY to the rest
	# paths, so the merchant counter and the roll result — PY-7's two symptoms —
	# never carried it. Travel and resume must NOT be pinned: they move on purpose.
	var g7 := FileAccess.get_file_as_string("res://scripts/game.gd")
	# WINDOWED, not line-by-line. The counter-left statement wraps, so `here_pin()`
	# sits on the continuation line — the first version of this check demanded it
	# on the SAME line and failed against correct code.
	var stay := ["Briefly color the exchange", "Narrate the outcome — set a DC",
		"Narrate the making briefly", "Narrate the aftermath of the battle"]
	var moves := ["I travel to %s — but something finds me", "We resume from this saved chapter"]
	for s in stay:
		var pin_at := g7.find(s)
		assert(pin_at >= 0, "PY-7: the stay-put instruction \"%s\" is gone — this check has gone blind" % s)
		assert(g7.substr(pin_at, 340).contains("here_pin()"),
			"PY-7: \"%s\" is a stay-put instruction with no location pin — the GM will invent a place (Invariants.md)" % s)
	for m in moves:
		var move_at := g7.find(m)
		if move_at < 0:
			continue
		assert(not g7.substr(move_at, 340).contains("here_pin()"),
			"PY-7: a TRAVEL instruction must not be pinned in place — the player is moving on purpose")
	# …and the pin has to actually name somewhere.
	var keep7 := GameState.state
	GameState.state = {"world": {"here": "Mercer's clinic"}}
	assert(GameState.here_pin().contains("Mercer's clinic"), "PY-7: the pin does not name where the player is")
	assert(GameState.here_pin().contains("not travelled"), "PY-7: the pin does not forbid moving them")
	GameState.state = {}
	assert(GameState.here_pin().contains("do not relocate"), "PY-7: with no location the pin must still forbid a move")
	GameState.state = keep7

	# PY-14. A CONTROL THAT PAINTS ITSELF MUST ASK TO BE REPAINTED. Godot re-runs
	# `_draw()` only on `queue_redraw()`, so a widget reading `Ui.c()` inside
	# `_draw()` keeps whatever palette was live when it last painted. 13 of 14
	# self-drawn controls never asked: the title, input border and buttons are
	# THEMED and went magenta in Neon Spire while the toolbar, the Session Zero
	# sliders and the HP bar are SELF-DRAWN and stayed gold. Two accents, one
	# screen. `backdrop.gd` is the one that always did it right.
	var NL14 := char(10)
	for df in ["res://scenes/combat/battle_grid.gd", "res://scenes/ui/mini_map.gd",
			"res://scenes/ui/skill_tree.gd", "res://scenes/ui/world_map.gd",
			"res://scenes/ui/cinematic.gd", "res://ui/myth_environment.gd",
			"res://ui/myth_gauge.gd", "res://ui/myth_icon.gd",
			"res://ui/myth_portrait.gd", "res://ui/myth_stage_rail.gd",
			"res://ui/forge_flow.gd"]:
		var dsrc2 := FileAccess.get_file_as_string(df)
		assert(dsrc2 != "", "self_check: %s could not be read" % df)
		var self_drawn := false
		for dl in dsrc2.split(NL14):
			if dl.begins_with("func _draw("):
				self_drawn = true
				break
		if not self_drawn:
			continue
		assert(dsrc2.contains("Ui.repaint_on_skin(self)") or dsrc2.contains("Ui.changed.connect"),
			"%s paints itself but never repaints on a skin change — it will hold the old world's accent (Invariants.md)" % df)

	# PY-12. EVERY dialog is dressed, and a dressed dialog carries the THEME. In
	# Godot 4 a Window starts a new theme context, so a PanelContainer inside an
	# undressed dialog renders in the engine default — hard-edged, borderless,
	# unrounded, "a grey debug-looking box over a fully skinned neon screen".
	# Three of five dialogs never called dress_dialog at all, and dress_dialog
	# itself never set `theme`, which is why even the dressed ones had unstyled
	# innards.
	var skn := FileAccess.get_file_as_string("res://autoload/skin.gd")
	assert(skn.contains("dlg.theme = theme"),
		"PY-12: dress_dialog does not give the dialog the theme — every panel inside it falls back to engine grey (Invariants.md)")
	for dlgf in ["res://scenes/ui/gm_tuner.gd", "res://scenes/ui/levelup_window.gd",
			"res://scenes/ui/reaction_prompt.gd", "res://scenes/ui/character_screen.gd",
			"res://scenes/ui/merchant_window.gd"]:
		var dsrc := FileAccess.get_file_as_string(dlgf)
		assert(dsrc != "", "self_check: %s could not be read" % dlgf)
		assert(dsrc.contains("Ui.dress_dialog("),
			"%s is a dialog that never gets dressed — it renders in the engine default theme (Invariants.md)" % dlgf)

	# PY-11. Card prose was cut with `.left(N)`, which severs mid-word and gives no
	# sign it happened: "quiet adventu", "stolen blueprt", "answer them i", on four
	# separate screens. Ui.trim cuts at a word and says so.
	assert(Ui.trim("a short one", 60) == "a short one", "trim: text that fits is untouched")
	var t11 := Ui.trim("A snug realm of hearth-fires, hedge-magic, and quiet adventure.", 60)
	assert(t11.ends_with("…"), "PY-11: a trimmed line must SAY it was trimmed")
	assert(not t11.contains("adventu…"), "PY-11: trimmed mid-word — the whole point is to cut at a space")
	assert(t11.length() <= 61, "PY-11: trim overshot its budget")
	# One very long word still has to be cut, or the line collapses to nothing.
	assert(Ui.trim("Supercalifragilisticexpialidocious", 10).ends_with("…"))
	assert(Ui.trim("Supercalifragilisticexpialidocious", 10).length() > 3, "PY-11: an early space must not eat the line")
	# …and no card payload may go back to raw truncation. LINE-AWARE: `.left(1)`
	# for a name's initial is fine and common, so the file-wide test this started
	# as fired on innocent code. Only a line that builds a card FIELD counts.
	var NEWLINE2 := char(10)
	for cf in ["res://scenes/forge/adventure_forge.gd", "res://scenes/forge/character_forge.gd"]:
		var csrc := FileAccess.get_file_as_string(cf)
		assert(csrc != "", "self_check: %s could not be read" % cf)
		for cline in csrc.split(NEWLINE2):
			var is_payload := cline.contains("\"body\":") or cline.contains("\"title\":") or cline.contains("\"foot\":")
			assert(not (is_payload and cline.contains(".left(")),
				"%s truncates card prose with .left() — use Ui.trim(), which cuts at a word (Invariants.md)" % cf)

	# PY-27. THE WORLD IS CHOSEN BEFORE THE HERO. Everything the character forge
	# commits — kit, body, portrait, heritage art — is world-flavored, so a hero
	# forged before the world is known is dressed for the wrong one. That is the
	# upstream half of PY-21, PY-22 and PY-23. The menu already announced
	# "world > campaign > hero"; only this rail disagreed.
	var afsrc := FileAccess.get_file_as_string("res://scenes/forge/adventure_forge.gd")
	assert(afsrc != "", "self_check: adventure_forge.gd could not be read")
	var af_stages := afsrc.split("const STAGES := [")
	assert(af_stages.size() > 1, "PY-27: adventure_forge has no STAGES to check")
	var af_first := str(af_stages[1]).split("]")[0]
	assert(af_first.find("The Campaign") < af_first.find("The Hero"),
		"PY-27: the Adventure Forge asks for the hero before the world — the kit is then committed for a world nobody has chosen (Invariants.md)")
	# …and the child forge must be TOLD which world, not left to read a stale one.
	assert(afsrc.contains("GameState.character = {\"id\": \"forge-draft\", \"world_id\""),
		"PY-27: the hero forge is spawned without publishing the chosen world, so world_flavor() reads whatever was last played")

	# PY-28, structural. The npc-/foe- prefixes were spelled by hand at FOURTEEN
	# sites, which is how they stayed unscoped while race-/item-/beast-/map- were
	# fixed. A cast portrait's prompt is world-flavored (lore_book appends
	# world_flavor(); a foe's carries subject_style("char")), so the first world
	# to paint a name owned that face everywhere. Art.npc_key/foe_key are the
	# only spellings now — a prefix TEST (begins_with) is still fine.
	for kf in ["res://scripts/game.gd", "res://scenes/ui/lore_book.gd",
			"res://scenes/forge/campaign_forge.gd", "res://scenes/forge/persona_forge.gd"]:
		var ksrc := FileAccess.get_file_as_string(kf)
		assert(ksrc != "", "self_check: %s could not be read" % kf)
		for pre in ["\"npc-\" +", "\"foe-\" +"]:
			assert(not ksrc.contains(pre),
				"%s builds a cast art key by hand — use Art.npc_key()/foe_key(), which carry the world (Invariants.md)" % kf)

	# PY-15, structural. A world's key art lives in TWO places — the compiled
	# package (`art/key.png`) and the art cache — and the fallback between them
	# was spelled out by hand at five call sites in three different spellings.
	# Two were wrong, in opposite directions: world_forge asked the cache only
	# (so a compiled world's baked art never showed) and adventure_forge asked
	# the package only (so an uncompiled world's painted art never showed). That
	# is the fifth appearance of the RCA art_cache.gd already carries for
	# `roster_art`. `Art.world_tex` is the one spelling now.
	for f in ["res://scripts/main_menu.gd", "res://scripts/game.gd",
			"res://scenes/forge/world_forge.gd", "res://scenes/forge/adventure_forge.gd"]:
		var wsrc := FileAccess.get_file_as_string(f)
		assert(wsrc != "", "self_check: %s could not be read" % f)
		assert(not wsrc.contains("Compiler.key_art("),
			"%s spells the key-art fallback by hand — use Art.world_tex(), which asks the package before the cache" % f)

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

	# ── EVERY FAMILY FILLS EVERY SOCKET, AND NO TWO FILL THEM THE SAME ───────
	#
	# The town generator asks `WorldSkin.ward_name(family, key)` for what this
	# world calls its square, its inn, its docks. That is only plug-and-play if
	# every family answers every key — and only worth having if the answers
	# DIFFER.
	#
	# This check exists because the vocabulary used to live in `local_map` as a
	# string match against the family's prose `world` line ("contains cyber or
	# steam"). Eight families produced two vocabularies: a steampunk foundry
	# town was given a Noodle Bar, and a fantasy village and a pirate port came
	# out with byte-identical ward names on the same sheet. Nothing failed —
	# it took looking at two renders side by side to see it.
	var seen_wards := {}
	for fam in WorldSkin.FAMILIES:
		var words: Dictionary = WorldSkin.FAMILIES[fam].get("wards", {})
		for k in WorldSkin.WARD_KEYS:
			assert(words.has(k) and str(words[k]).strip_edges() != "",
				"world family '%s' has no word for the '%s' ward - the town generator asks every family for every key" % [fam, k])
			assert(WorldSkin.ward_name(fam, k) == str(words[k]),
				"ward_name('%s', '%s') does not return the family's own word" % [fam, k])
			# NO ARTICLE IN THE WORD. `local_map` writes "The %s", so a word that
			# carries its own "The" renders as "The The Plaza" — which is exactly
			# what the cyber and everyday sheets said.
			assert(not str(words[k]).to_lower().begins_with("the "),
				"world family '%s' spells the '%s' ward as '%s' - the generator adds \"The\", so this renders as \"The %s\"" % [
					fam, k, str(words[k]), str(words[k])])
		var fingerprint := ""
		for k2 in WorldSkin.WARD_KEYS:
			fingerprint += str(words[k2]) + "|"
		assert(not seen_wards.has(fingerprint),
			"world families '%s' and '%s' name their wards IDENTICALLY - two worlds would draw the same town under different skies" % [
				fam, str(seen_wards.get(fingerprint, ""))])
		seen_wards[fingerprint] = fam
	# EVERY KIND THE GM MAY INVENT IS ONE THE MAP CAN DRAW. `SITE_KINDS` is a
	# closed enum precisely so this can be true — the model never names a kind,
	# it picks one, and the engine guarantees a mark for each. Leave a kind out
	# of `SITE_MARK` and that site renders as a bare dot with no silhouette.
	var pm: GDScript = load("res://scenes/ui/place_map.gd")
	var site_mark: Dictionary = pm.get("SITE_MARK")
	for k in GameState.SITE_KINDS:
		assert(site_mark.has(k),
			"GameState.SITE_KINDS carries '%s' and place_map.SITE_MARK has no mark for it - the GM could create a site the map cannot draw" % k)
	print("  sites: %d kinds, every one has a mark" % GameState.SITE_KINDS.size())
	# ── A QUARTER AND A BUSINESS MAY NOT SHARE A NAME ────────────────────────
	# The town draws both: "The Chandlery" the ward and "The Chandlery" the shop
	# stood on the same sheet, and only `_add`'s de-duplicator kept them apart —
	# as "The Chandlery (2)". Four families collided (space on Galley, steam on
	# Guildhall, pirate on Chandlery AND Tavern, norse on Mead-Hall), and nothing
	# failed; it took reading a probe's node list to see it.
	for fam2 in WorldSkin.FAMILIES:
		var wrd: Dictionary = WorldSkin.FAMILIES[fam2].get("wards", {})
		var trd: Dictionary = WorldSkin.FAMILIES[fam2].get("trades", {})
		for tk in WorldSkin.TRADE_KEYS:
			assert(trd.has(tk) and str(trd[tk]).strip_edges() != "",
				"world family '%s' has no name for the '%s' trade" % [fam2, tk])
			assert(not str(trd[tk]).to_lower().begins_with("the "),
				"world family '%s' spells the '%s' trade as '%s' - the generator adds \"The\"" % [fam2, tk, str(trd[tk])])
			for wk in WorldSkin.WARD_KEYS:
				assert(str(wrd[wk]) != str(trd[tk]),
					"world family '%s' calls both a WARD and a TRADE '%s' - the map would draw two places with one name" % [
						fam2, str(trd[tk])])
	# Size gates what a place can offer, and a bigger place never offers less.
	var prev := 0
	for tier in 4:
		var got: Array = WorldSkin.trades_at(tier)
		assert(got.size() > prev, "settlement tier %d offers no more trades than tier %d - the size gate does nothing" % [tier, tier - 1])
		prev = got.size()
	assert(WorldSkin.trades_at(0).size() < WorldSkin.trades_at(3).size(),
		"a hamlet offers as much as a city")
	print("  trades: %d kinds, %d..%d by size, none shares a ward's name" % [
		WorldSkin.TRADE_KEYS.size(), WorldSkin.trades_at(0).size(), WorldSkin.trades_at(3).size()])
	# THE CHART IS INK ON PAPER — NO DARK-PANEL UI COLOURS ON IT. The hover lore,
	# the you-are-here ring and the travel dots were still drawn in `gold_soft`
	# after the chart became parchment, and measured 1.05-1.23:1 against the paper
	# on five of six worlds: the player's own position was the least visible mark
	# on the sheet. Ink is asserted at 4.5:1 per family already; this keeps the
	# chart from quietly reaching back for a UI colour.
	var parchment_src := FileAccess.get_file_as_string("res://scenes/ui/world_map.gd")
	for banned in ['Ui.c("gold_soft")']:
		assert(not parchment_src.contains(banned),
			"world_map draws %s on the parchment chart - a dark-panel colour that measured ~1.1:1 against the paper; use _ink()" % banned)
	# WHAT THE PLAYER SEES OF A TROUBLE IS WHAT THEY KNOW. Both maps read
	# `trouble_at`, which returns secrets too, so a conspiracy was printed on the
	# Atlas card before a single clue. A screen goes through `trouble_known`.
	for trouble_screen in ["res://scenes/ui/world_map.gd", "res://scenes/ui/place_map.gd"]:
		assert(not FileAccess.get_file_as_string(trouble_screen).contains("GameState.trouble_at("),
			"%s shows GameState.trouble_at - that includes SECRET troubles; use trouble_known" % trouble_screen)
	# ── ONE ROOF HAS ROOMS, and every world names them ───────────────────────
	# The scale a place is drawn at comes from its kind, and the room words come
	# from the family. A family missing a kind would silently fall back to
	# fantasy's cottage, which is how a Noodle Bar got a Scullery.
	assert(LocalMap.BUILDING_KINDS == WorldSkin.ROOM_KINDS,
		"LocalMap.BUILDING_KINDS and WorldSkin.ROOM_KINDS disagree about what is one building")
	for fam_id in WorldSkin.FAMILIES:
		for bk in WorldSkin.ROOM_KINDS:
			var rws: Array = WorldSkin.FAMILIES[fam_id].get("rooms", {}).get(bk, [])
			assert(rws.size() >= WorldSkin.ROOM_KEYS.size(),
				"%s has %d room words for a %s, and a building can have %d rooms" % [
					fam_id, rws.size(), bk, WorldSkin.ROOM_KEYS.size()])
			for rw in rws:
				assert(str(rw).strip_edges() != "" and not str(rw).begins_with("The "),
					"%s/%s room '%s' is empty or carries an article" % [fam_id, bk, rw])
	# THE CONSTANT, NOT AN INSTANCE. `new()` on a Control here leaked a CanvasItem
	# RID on every run — a warning in a passing gate is still a warning.
	var marks: Dictionary = (load("res://scenes/ui/place_map.gd") as GDScript).get_script_constant_map()["ROLE_MARK"]
	for rk in WorldSkin.ROOM_KEYS:
		assert(marks.has(rk), "a room role '%s' has no mark on the plan — it would draw as a dot" % rk)
	for fam_id2 in WorldSkin.FAMILIES:
		assert(WorldSkin.ROOFS.has(str(WorldSkin.FAMILIES[fam_id2].get("roof", ""))),
			"%s has no roof style, so its town draws fantasy's pitched ridge" % fam_id2)
	print("  rooms: %d families x %d building kinds, every room socket named and marked" % [
		WorldSkin.FAMILIES.size(), WorldSkin.ROOM_KINDS.size()])
	print("  wards: %d families, %d sockets each, all distinct" % [
		WorldSkin.FAMILIES.size(), WorldSkin.WARD_KEYS.size()])

	# INVARIANT: never paint while the narrator talks. Measured three ways - a
	# resident engine at narrator load costs NOTHING (3.3/3.6/3.5 s against
	# 3.0/3.5/3.5), but generating 1024x1024 DURING the turns takes them to 6.1 s
	# by the sixth. Peak VRAM there was 15310 MB of 16384, so nothing was evicted:
	# the two processes contend for shaders, not memory. `Art.hold` around the
	# stream is the whole fix, and until now nothing asserted it existed.
	# LINE-AWARE, because `contains` matched the guard COMMENTED OUT. Mutation-
	# testing this check is what found that: the first version passed against
	# "# Art.hold = true MUTATION", which is exactly the change it must catch.
	var hsrc := FileAccess.get_file_as_string("res://scripts/game.gd")
	var hold_on := 0
	var hold_off := 0
	for line in hsrc.split("
"):
		var t := line.strip_edges()
		if t.begins_with("Art.hold = true"):
			hold_on += 1
		elif t.begins_with("Art.hold = false"):
			hold_off += 1
	assert(hold_on >= 1,
		"invariant: nothing holds the art queue while the narrator streams - turns go 3.5 s to 6.1 s (Invariants.md)")
	assert(hold_off >= 3,
		"invariant: every exit from a stream must release Art.hold - done, cancel and leaving the table are three paths")

	# INVARIANT: Godot's RegEx is PCRE2, where a \u escape does NOT exist. A
	# pattern using one compiles clean and then silently matches nothing, which is
	# the worst failure shape available: no error, no match, no clue.
	# The needle is BUILT, not escaped: char(92) is a backslash, so this line
	# cannot itself trip the very parse error it is looking for. It did, once.
	var u_esc := char(92) + "u"
	for rf in ["res://autoload/tag_parser.gd", "res://autoload/prompt_composer.gd",
			"res://autoload/rules_engine.gd", "res://autoload/world_skin.gd"]:
		var rsrc2 := FileAccess.get_file_as_string(rf)
		for line in rsrc2.split("\n"):
			assert(not (line.contains(".compile(") and line.contains(u_esc)),
				"invariant: %s uses a backslash-u escape in a RegEx - PCRE2 does not know it, so the pattern matches nothing (Invariants.md)" % rf)

	# PY-16 / PY-17 both turn on ONE primitive: the difference between "not
	# painted" and "being painted". `Art.status` is the only thing that knows it.
	Art._generating["unit-inflight"] = true
	assert(Art.status("unit-inflight") == "queued",
		"art: a commission in flight must not look the same as one never asked for")
	assert(Art.status("unit-never") == "", "art: an unasked key is empty, not queued")
	Art._generating.erase("unit-inflight")

	# PY-16: the codex sweep narrated "Painting X…" once per UPDATE rather than
	# once per commission, because it asked `has_art` — true only when the paint
	# FINISHES, ~20 s later. The work was never duplicated; the line was.
	var gsrc5 := FileAccess.get_file_as_string("res://scripts/game.gd")
	assert(gsrc5.contains("if Art.status(key) == \"\":"),
		"PY-16: _auto_portrait must skip a portrait already in flight, or it narrates the same one twice")

	# PY-17: the forge's re-strike went silent for the ~25 s it paints, and left
	# itself pressable. It must say so AND come back — including when the paint
	# fails, which never emits art_ready at all.
	var cfsrc := FileAccess.get_file_as_string("res://scenes/forge/character_forge.gd")
	assert(cfsrc.contains("restrike.text = \"The forge paints…\""),
		"PY-17: the re-strike must say it is working — 25 s of silence reads as failure")
	assert(cfsrc.contains("func _on_quench_progress"),
		"PY-17: a failed paint emits no art_ready, so the button would stay dead for ever without a progress handler")

	# PY-13. Banking a hero must PIN THEIR FACE, and the hero the forge just
	# painted is exactly the one it failed for. `hero_portrait_key` refuses the
	# shared "heroprev" scratch key by design, and `bank_hero` asked IT for the
	# copy source — so a menu-forged hero (portrait_key == "heroprev") yielded
	# "", the copy never ran, and the roster card asked the same refusing
	# function and got "" for ever. Real save: 2 of 4 heroes stranded that way.
	var pin_keep := Art._manifest.duplicate(true)
	Art._manifest_loaded = true
	var pin_img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pin_img.fill(Color.RED)
	pin_img.save_png(Art.path_for("heroprev"))
	var pin_hero := {"name": "Unit Pin", "id": null, "portrait_key": "heroprev"}
	GameState.bank_hero(pin_hero)
	var pinned: Array = GameState.banked_heroes().filter(func(h): return str(h.get("name", "")) == "Unit Pin")
	assert(pinned.size() == 1, "PY-13: the banked hero was not written")
	var pk := str(pinned[0].get("portrait_key", ""))
	assert(pk != "heroprev",
		"PY-13: a banked hero is still pinned to the shared scratch key — the next forging overwrites their face")
	assert(Art.has_art(pk), "PY-13: the banked hero's portrait key names no file")
	assert(GameState.hero_portrait_key(pinned[0]) != "",
		"PY-13: the roster card will show a glyph for a hero who has a portrait")
	GameState.unbank_hero("Unit Pin")
	Art.forget(pk)
	Art.forget("heroprev")
	Art._manifest = pin_keep
	print("  PY-13: banking pins the forge's scratch portrait to the hero's own key")

	# A2 art manifest: an asset is noted, and NOTHING removes it behind the
	# player's back. `_evict` used to live here.
	Art._manifest_loaded = true  # skip the disk scan in this unit check
	Art._manifest = {"unit-old": {"size": 100, "used": 1.0}, "unit-new": {"size": 100, "used": 9.0}}
	assert(not Art.has_method("_evict"),
		"art: _evict is back — paintings must never be deleted to make room, there is no path that regenerates one")
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
		# 65 shipped, plus the five soft-tissue bones scripts/add_jiggle_bones.py
		# adds. Named individually as well as counted, because a count alone
		# passes if the exporter renames one — and a renamed jiggle bone does not
		# error, it silently stops being simulated.
		assert(qd.skeleton != null and qd.skeleton.get_bone_count() == 75,
			"q-doll: 65 shipped, five for soft tissue, five for the tail")
		for jb in ModularDoll.JIGGLE:
			assert(qd.skeleton.find_bone(str(jb)) >= 0,
				"q-doll: the body carries the '%s' bone" % jb)
		var sim := qd.skeleton.get_node_or_null("Jiggle")
		assert(sim != null, "q-doll: a spring simulator is hung off the skeleton")
		assert(not sim.active, "q-doll: ...and it is OFF until something asks to be alive")
		assert(sim.get_setting_count() == ModularDoll.JIGGLE.size() + ModularDoll.JIGGLE_CHAINS.size(),
			"q-doll: every soft-tissue bone and every chain gets a spring")
		# EVERY GESTURE CLIP MUST EXIST AND MUST END. A name that is not in the
		# library is a gesture that never plays; a name that LOOPS is worse, because
		# `animation_finished` never fires for it and the director stops dead —
		# the figure freezes on the last thing it did and idles no more. Neither
		# is visible from the table, since Godot's glTF importer decides loop mode
		# from a `_Loop` suffix that it then strips off the name.
		var qap: AnimationPlayer = qd._find_anim(qd._body)
		assert(qap != null, "q-doll: the shipping rig has an AnimationPlayer")
		var pools: Dictionary = qd.profile().get("gestures", {})
		assert(not pools.is_empty(), "q-doll: the figure has gestures to play")
		for pool in pools:
			assert(not pools[pool].is_empty(), "q-doll: the '%s' pool is not empty" % pool)
			for seq in pools[pool]:
				for nm in seq:
					var clip := qap.get_animation(str(nm))
					assert(clip != null, "q-doll: gesture clip '%s' is in the library" % nm)
					assert(clip.loop_mode == Animation.LOOP_NONE,
						"q-doll: gesture clip '%s' ends — a looping one stops the director dead" % nm)
		# And the idle must be the opposite: a loop, or the figure plays it once
		# and stands frozen until the next gesture.
		var idles := 0
		for w in qd.profile().get("live", []):
			var idle := qap.get_animation(str(w))
			assert(idle != null, "q-doll: idle clip '%s' is in the library" % w)
			assert(idle.loop_mode != Animation.LOOP_NONE,
				"q-doll: live idle '%s' loops" % w)
			idles += 1
		assert(idles >= 3, "q-doll: several idles to choose between, got %d" % idles)
		# BOTH libraries attached, not just the first. They arrive under
		# different names and a clip from the second resolving to nothing is
		# silent — Godot matches tracks by name and a track that hits nothing is
		# not an error, so the figure would just never leave its idle.
		assert(qap.get_animation_library_list().size() >= 2,
			"q-doll: both animation libraries are attached")
		assert(qap.get_animation("ual1/Idle") != null,
			"q-doll: the retargeted library is reachable")
		# The spell set is for casters ONLY, so it must not be in either of the
		# pools that every hero draws from.
		# ── HAIR ─────────────────────────────────────────────────────────────
		# Five styles and a beard sat in this repo, rigged and imported, wired to
		# NOTHING — every figurine ever rendered here was bald and nobody noticed,
		# because bald is a perfectly plausible thing for a character to be.
		var hair: Dictionary = qd.profile().get("hair", {})
		assert(hair.size() >= 3, "q-doll: several hairstyles, got %d" % hair.size())
		for style in hair:
			var entry = hair[style]
			var paths: Array = []
			if entry is Dictionary:
				for k in entry:
					paths.append(entry[k])
			else:
				paths.append(entry)
			for path in paths:
				assert(ResourceLoader.exists(str(path)),
					"q-doll: hairstyle '%s' resolves to a real file" % style)
		var bald := qd._all_meshes(qd).size()
		qd.apply_look({"hair": "long", "beard": ""})
		assert(qd._all_meshes(qd).size() > bald, "q-doll: hair adds geometry")
		assert(qd.worn("hair") == "long", "q-doll: ...and the doll knows it wears it")
		# A HOOD EATS THE HAIR, and this is a boolean rather than a mask, so it is
		# the cheapest thing in the world to break silently.
		qd.equip("head", "hood")
		assert(not qd._extern["hair"].visible, "q-doll: a hood hides the hair under it")
		qd.equip("head", "")
		assert(qd._extern["hair"].visible, "q-doll: ...and taking it off gives it back")
		qd.apply_look({"hair": "", "beard": ""})
		assert(qd.worn("hair") == "", "q-doll: an empty style is honoured, not defaulted")
		assert(qd._all_meshes(qd).size() == bald, "q-doll: ...and the geometry goes")
		assert(ModularDoll.HAIR_COLORS.has(ModularDoll.DEFAULT_HAIR),
			"q-doll: the default hair colour is one of the palette")
		# ── HORNS ────────────────────────────────────────────────────────────
		# Grown by scripts/author_horns.py and skinned entirely to the Head bone,
		# so they are a garment as far as the doll is concerned. Paired by sex,
		# because the two skulls sit 43 mm apart and a horn seeded off one floats
		# above the other.
		var horns: Dictionary = qd.profile().get("horns", {})
		assert(horns.size() >= 3, "q-doll: several horn styles, got %d" % horns.size())
		for style in horns:
			var pair = horns[style]
			assert(pair is Dictionary and pair.has("male") and pair.has("female"),
				"q-doll: horn '%s' is cut for both skulls" % style)
			for k in pair:
				assert(ResourceLoader.exists(str(pair[k])),
					"q-doll: horn '%s' (%s) resolves to a real file" % [style, k])
		# Hair pinned OFF at both ends of the comparison. `apply_look` falls back
		# to the sex default for anything the dictionary does not mention, so a
		# baseline taken without saying `hair: ""` silently includes a wig and
		# the counts never match.
		qd.apply_look({"hair": "", "beard": "", "horns": ""})
		var plain := qd._all_meshes(qd).size()
		qd.apply_look({"hair": "", "beard": "", "horns": "ram"})
		assert(qd._all_meshes(qd).size() > plain, "q-doll: horns add geometry")
		assert(qd.worn("horns") == "ram", "q-doll: ...and the doll knows it wears them")
		# A HOOD DOES NOT REMOVE THEM. Hair is hidden under a hood; horns are part
		# of the head, and a tiefling who loses their horns to a hat is not a
		# tiefling. This is the assertion that stops someone "fixing" that.
		qd.equip("head", "hood")
		assert(qd._extern["horns"].visible, "q-doll: a hood does not take the horns off")
		qd.equip("head", "")
		qd.apply_look({"hair": "", "beard": "", "horns": ""})
		assert(qd._all_meshes(qd).size() == plain, "q-doll: and they come off again")
		# PY-21 — THE HERITAGE MUST REACH THE RIG, not just the proportions. The
		# table has declared `features: ["horns", "tail"]` for a Tiefling since it
		# was written, `Rules.heritage_features()` was built to read it, and it had
		# ZERO callers — so a Tiefling previewed as a plain human while the 2D
		# portrait, which does read the heritage, came back with horns. Found by
		# playing the game and looking at the two pictures side by side.
		#
		# Asserted through the DOLL, not just the table, or this passes while the
		# wire is cut again: a lookup returning the right dictionary proves nothing
		# if nobody applies it.
		assert(Rules.heritage_look("Human")["horns"] == "", "heritage look: a Human grows no horns")
		assert(Rules.heritage_look("Human")["tail"] == "", "heritage look: a Human grows no tail")
		assert(str(Rules.heritage_look("Tiefling")["horns"]) != "", "heritage look: a Tiefling has horns")
		assert(str(Rules.heritage_look("Tiefling")["tail"]) != "", "heritage look: a Tiefling has a tail")
		assert(str(Rules.heritage_look("Dragonborn")["tail"]) != "", "heritage look: a Dragonborn has a tail")
		qd.apply_look(Rules.heritage_look("Human"))
		var human_meshes := qd._all_meshes(qd).size()
		assert(qd.worn("horns") == "", "heritage look: a Human doll wears no horns")
		qd.apply_look(Rules.heritage_look("Tiefling"))
		assert(qd.worn("horns") != "", "heritage look: a Tiefling doll actually WEARS its horns")
		assert(qd.worn("tail") != "", "heritage look: ...and its tail")
		assert(qd._all_meshes(qd).size() > human_meshes,
			"heritage look: a Tiefling carries more geometry than a Human — the features are really on the rig")
		qd.apply_look({"hair": "", "beard": "", "horns": ""})
		print("  heritage look: horns and tail reach the rig from the heritage table")
		# PY-25 - the counter's nouns follow the world, as its currency already did.
		# A Neon Spire fixer sold Mono-Knives for credits from behind "The trading
		# post", and the Record said those credits were "in the purse". Found by
		# playing it. Asserted as a DIFFERENCE, not a spelling: a lexicon that
		# returns the fantasy word for every family would pass a spelling check.
		assert(WorldSkin.shop_word("embervale", "post") == "The trading post",
			"shop words: a fantasy world keeps the fantasy default")
		for fam_world in ["neonspire", "everyday"]:
			for key in ["post", "keeper", "wares", "purse"]:
				assert(WorldSkin.shop_word(str(fam_world), key) != WorldSkin.shop_word("embervale", key),
					"shop words: %s still says the fantasy '%s'" % [fam_world, key])
		assert(WorldSkin.shop_word("embervale", "nonsense") == "nonsense",
			"shop words: an unknown key returns itself rather than an empty label")
		print("  shop words: the counter speaks each world's own vocabulary")
		# PY-24 - a skinned room prompt must not name medieval furniture. These read
		# "a %s merchant's STALL interior ... on WORN SHELVES, warm LAMPLIGHT", so
		# Neon Spire painted a wooden market and stood it behind a counter selling
		# Pulse Rifles. Asserted as a WORD BAN rather than by rendering, because
		# rendering costs a GPU minute per room and the defect is in the text.
		var period_nouns := ["stall", "lamplight", "curio", "torch", "parchment",
			"tavern", "hearth", "candle", "scroll", "pouch"]
		for role_key in Art.ENV_ROLE:
			var tmpl := str(Art.ENV_ROLE[role_key]).to_lower()
			for noun in period_nouns:
				assert(not tmpl.contains(noun),
					"env prompt: the skinned '%s' names '%s' - every world gets that furniture" % [role_key, noun])
		# ...and the skinned key must move when the words do, or a player who has
		# already painted the room keeps it for ever.
		assert(Art.ENV_SKIN_REV >= 2, "env prompt: the skinned cache key was not revved after a prompt change")
		print("  env prompts: no skinned room names period furniture")
		assert(ModularDoll.HORN_COLORS.has(ModularDoll.DEFAULT_HORN),
			"q-doll: the default horn colour is one of the palette")
		assert(ModularDoll.SKIN_TONES.has(ModularDoll.DEFAULT_SKIN),
			"q-doll: the default skin tone is one of the palette")

		var spell_pool: Array = pools.get("caster", [])
		assert(not spell_pool.is_empty(), "q-doll: a caster has something to cast")
		for seq in spell_pool:
			for nm in seq:
				var clip := qap.get_animation(str(nm))
				assert(clip != null and clip.loop_mode == Animation.LOOP_NONE,
					"q-doll: caster clip '%s' exists and ends" % nm)
			assert(not pools["armed"].has(seq) and not pools["bare"].has(seq),
				"q-doll: a non-caster is never handed a spell")
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
		# SOFT TISSUE IS A MORPH, NOT A BONE, and the entire point of it is that
		# the CLOTH moves with the skin. So the assertion is not "the body has a
		# chest" — it is that the body and the garment over it carry the same key
		# at the same value. The failure this catches is a body-only morph: a full
		# chest inside a flat tunic, which is worse than having neither.
		var chest_keys := 0
		for mi in qf._all_meshes(qf):
			var bi: int = mi.find_blend_shape_by_name("Chest")
			if bi < 0:
				continue
			chest_keys += 1
			assert(is_equal_approx(mi.get_blend_shape_value(bi), 1.0),
				"q-doll: %s carries Chest but was not driven to it" % mi.name)
		assert(chest_keys >= 2,
			"q-doll: the Chest morph must reach the body AND what it wears, got %d" % chest_keys)
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
			"cloth: an undyed family keeps the pack's own material, not a shader")
		qc.queue_free()
		print("  cloth: four families dye the garment, the other four are left alone")

		# ── Hidden surface removal ───────────────────────────────────────────
		# EVERY garment needs its mask, because a garment without one hides no
		# skin and the skin then tears through it — which is a picture, not an
		# error, so nothing would report it. The forged trousers were doing
		# exactly that while the pack's own were clean, because equip_scene did
		# not record the file its mask is named after.
		var qm := ModularDoll.new()
		qm.rig = "quaternius"
		add_child(qm)
		var scenes: Dictionary = qm.profile().get("scenes", {})
		var checked := 0
		for msex in ["male", "female"]:
			qm.sex = msex
			for mslot in scenes:
				for pid in scenes[mslot]:
					var entry = scenes[mslot][pid]
					var gp := qm._sexed(str(entry.get(msex, entry.get("male", "")))
						if entry is Dictionary else str(entry))
					if not ResourceLoader.exists(gp):
						continue
					checked += 1
					assert(qm._mask_for(gp) != null,
						"mask: %s has no baked hidden-surface mask" % gp)
		assert(checked >= 16, "mask: expected the whole wardrobe, only saw %d" % checked)
		# Dressed, the skin is masked; bare, it is untouched. The undress half is
		# the one that rots — a mask left on after a garment comes off is a hero
		# with a hole in them.
		qm.sex = "male"
		qm.build(load(qm.body_path()))
		# WHAT THE MASK CONTAINS, not whether one is present. The skin now always
		# wears its own shader — bare included, because that is where the skin
		# tone and the PBR maps live — so "is there an override" stopped meaning
		# anything. How much of the body it hides still does.
		var bare_sm := _skin_override(qm)
		assert(bare_sm is ShaderMaterial, "mask: the skin always wears its own shader")
		assert(_mask_white(bare_sm) <= 0.001, "mask: a bare body is covered nowhere")
		# THE PBR MAPS SURVIVE IT. This shader replaced a StandardMaterial that
		# carries a normal map and a roughness map, and for months sampled albedo
		# alone — so putting on a shirt turned a hero's skin to plastic, on every
		# surface in the game, and nothing failed.
		assert(bool(bare_sm.get_shader_parameter("has_normal")),
			"mask: the skin keeps its normal map")
		assert(bool(bare_sm.get_shader_parameter("has_rough")),
			"mask: the skin keeps its roughness map")
		assert(qm.equip("armor", "ranger"), "mask: the garment wears")
		assert(_mask_white(_skin_override(qm)) > 0.02, "mask: dressing must hide skin")
		assert(qm.equip("armor", ""), "mask: the garment comes off")
		assert(_mask_white(_skin_override(qm)) <= 0.001,
			"mask: undressing must give the skin back")
		qm.queue_free()
		print("  mask: %d garments carry a hidden-surface mask; dressing hides skin, undressing returns it" % checked)

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
	# ...AND IT IS ASSERTED BY BUILDING ONE. This used to grep game.gd for
	# `s["sex"]`, which broke the day the construction moved to GameState with no
	# behaviour changed — the tell that it was testing where the code lived. A
	# grep also passes when the value is assigned and then thrown away.
	var rolls: Array[int] = [15, 14, 13, 12, 10, 8]
	var forged := GameState.new_hero_sheet("Test", "Dwarf", "Fighter", rolls, "",
		{"sex": "female", "appearance": "a scarred jaw"})
	assert(str(forged.get("sex", "")) == "female", "forge: the hero's sex reaches the sheet")
	assert(forged.get("build") is Dictionary
		and (forged["build"] as Dictionary).size() == Rules.BUILD_KNOBS.size(),
		"forge: every build knob reaches the sheet")
	assert(str(forged.get("look", "")) == "a scarred jaw",
		"forge: the look is persisted, not handed to one portrait and dropped")
	# PS-1 — the table had Second Wind at level 1 the whole time and nothing asked.
	assert(not (forged.get("features", []) as Array).is_empty(),
		"forge: a level-1 hero leaves with no class features (PS-1)")
	# Preset + heritage + background can grant the same skill, and the sheet then
	# reads "athletics, perception, athletics, perception".
	#
	# THE COMBINATION IS CHOSEN, NOT CONVENIENT. The Dwarf Fighter above shares no
	# skill with anything, so deleting the dedup left it green — measured, not
	# assumed. Fighter+Elf collides on perception through heritage and Fighter+
	# Soldier collides on athletics through background, so this one exercises both
	# sources. 238 of the table's combinations overlap; this check would be
	# decoration if it used one of the few that do not.
	var dupe := GameState.new_hero_sheet("Test3", "Elf", "Fighter", rolls, "Soldier")
	var seen_sk := {}
	for sk in dupe.get("profSkills", []):
		assert(not seen_sk.has(sk), "forge: %s is listed twice — the skill dedup is gone" % sk)
		seen_sk[sk] = true
	assert(seen_sk.has("perception") and seen_sk.has("athletics"),
		"forge: this case no longer collides — pick another, or the dedup check proves nothing")
	# The best roll goes where the class wants it: a Fighter is STR-first, and a
	# caster leads with its casting ability instead.
	var abil: Dictionary = forged.get("abilities", {})
	assert(int(abil.get("STR", 0)) >= int(abil.get("CHA", 0)),
		"forge: a Fighter's best scores are not going to STR")
	var wiz := GameState.new_hero_sheet("Test2", "Human", "Wizard", rolls)
	assert(wiz.get("slots") != null, "forge: a caster leaves the anvil with no spell slots")
	assert(int((wiz["abilities"] as Dictionary).get("INT", 0)) >= int(abil.get("STR", 0)) - 2,
		"forge: a Wizard's best score is not going to its casting ability")
	assert(int(forged.get("hp", 0)) == int(forged.get("hpMax", 0)) and int(forged.get("hp", 0)) > 0,
		"forge: a new hero does not start at full health")
	print("  build: sex + %d knobs, neutral means heritage, and a tall Dwarf is still a Dwarf"
		% Rules.BUILD_KNOBS.size())

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

	# ── THE PAINTINGS ARE PERMANENT ──────────────────────────────────────────
	# There was a 700 MB LRU here that deleted the least-recently-used art to
	# stay under budget, defended by "evicted art self-heals: the next
	# ensure(key, prompt) simply repaints it". Nothing in this repo regenerates
	# from a sidecar — every `_meta_path` reference writes one or deletes one —
	# and a hero's face cannot be repainted at all, because its source is the
	# shared `heroprev` scratch key the next forging overwrites. So these assert
	# that a total far past the ceiling costs NOTHING, and that the size is still
	# named out loud, because a runaway generator is real (R10 queued ~1.3 GB).
	var art_keep: Dictionary = Art._manifest.duplicate(true)
	var art_loaded: bool = Art._manifest_loaded
	var art_warned: bool = Art.size_warned
	Art._manifest_loaded = true
	Art.size_warned = false
	var GB := 1024 * 1024 * 1024

	# Twelve GB against a 10 GB warning mark: it complains, and it keeps both.
	Art._manifest = {"stale": {"size": 6 * GB, "used": 100.0},
		"fresh": {"size": 6 * GB, "used": 900.0}}
	Art._enforce_budget()
	assert(Art._manifest.has("stale"), "art: the oldest painting must SURVIVE — nothing regenerates it")
	assert(Art._manifest.has("fresh"), "art: the painting in use survives")
	assert(Art._manifest.size() == 2, "art: going over the mark must delete nothing at all")
	assert(Art.size_warned, "art: passing the mark is said out loud, once")

	# A shipped terrain tile is a library asset and is not even counted.
	Art._manifest = {}
	Art._note_asset("tile-grass-01")
	assert(Art._manifest.is_empty(), "art: a shipped terrain tile is never counted")

	Art._manifest = art_keep
	Art._manifest_loaded = art_loaded
	Art.size_warned = art_warned
	Art._save_manifest()
	print("  art: paintings are permanent, size named once past the mark, tiles exempt")

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
	# The kinds a [[site]] may take are spelled out in the prompt by hand; the engine refuses any other.
	assert(Composer.PROTOCOL.contains("kind: " + "/".join(GameState.SITE_KINDS)), "the [[site]] kinds the GM is taught are not GameState.SITE_KINDS")
	for trouble_reach in GameState.TROUBLE_REACH:
		assert(Composer.PROTOCOL.contains("%s (" % trouble_reach), "the GM is never taught trouble reach=%s" % trouble_reach)
	assert(Composer.PROTOCOL.contains("[[uncover]]"), "the GM is never taught [[uncover]] - a secret trouble could never be found out")
	# THE TURN-READ IS WHAT FEEDS A TROUBLE IN REAL PLAY: the narrator wrote 0 [[clue]] in
	# four investigating turns (town_gm_probe). Nothing offline can run it - the model is
	# not there - so this pins the one line that calls it after every recorded turn.
	var chron_src := FileAccess.get_file_as_string("res://autoload/chronicle.gd")
	var rec_body := chron_src.substr(chron_src.find("func record("), 900)
	assert(rec_body.contains("_after_turn(") and chron_src.contains("await read_trouble(player_msg, gm_reply)"),
		"Chronicle.record no longer reads the turn for the trouble - leads and effort would only ever come from tags the real narrator does not write")
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

	# ── THE GROUND IS DATA, AND THE PINS STAND ON IT ─────────────────────────
	#
	# The chart used to be an SDXL painting and the road router read terrain back
	# out of its PIXELS. Measured 2026-08-26: that gave Neon Spire a cost field
	# 73.2 % "expensive" (night shadow read as mountain) while finding 0.2 % water
	# in a world whose prompt asks for canals, and three of the twenty authored
	# pins stood in open water — `Your Apartment` at wet=1.00.
	#
	# Nothing ever compared a pin against the ground beneath it, so nothing could
	# fail. These are the comparisons.
	for fam in WorldSkin.FAMILIES.keys():
		# THE RENDERER MUST NOT CONTRADICT THE WORLD'S STATED GROUND. One natural
		# ramp for all eight families drew Neon Spire — "dense city blocks and
		# arterial roads" in CHART_GROUND's own words — as grass and hills, which
		# is PY-26 relocated from the prompt into the shader.
		assert(WorldTerrain.PAPER.has(fam),
			"WorldTerrain.PAPER has no colours for the '%s' family - its chart would render in fantasy green whatever Art.CHART_GROUND says it is" % fam)
		for role in ["paper", "dark", "ink", "land"]:
			assert(WorldTerrain.PAPER[fam].has(role),
				"WorldTerrain.PAPER['%s'] is missing '%s' - the shader would take the previous world's colour for it" % [fam, role])
		assert(WorldTerrain.GROUND.has(fam),
			"WorldTerrain.GROUND has no ground for the '%s' family - it would silently fall back to fantasy, which is how a megacity got a river valley (PY-26)" % fam)
	var _seen_terrain := 0
	for w in Rules.builtin_worlds():
		var twid := str(w.get("id", ""))
		if twid == "":
			continue
		WorldTerrain.forget(twid)
		var ter := WorldTerrain.for_world(twid)
		_seen_terrain += 1
		var wf := ter.water_fraction()
		assert(wf > 0.001 and wf < 0.999,
			"%s terrain is degenerate (%.1f%% water) - all-land or all-sea passes every other check for the wrong reason" % [twid, wf * 100.0])
		# THE BUG ITSELF: a place standing somewhere its kind cannot stand.
		for l in Rules.world_locations(twid):
			if not (l is Dictionary) or not (l.has("x") and l.has("y")):
				continue
			var lc := ter.cell_of(Vector2(float(l["x"]), float(l["y"])))
			var lk := str(l.get("kind", ""))
			var lclass: String = ["deep", "shoal", "coast", "plain", "hill", "peak"][ter.klass(lc)]
			assert(ter.suits(lk, lc),
				"%s: '%s' (%s) stands on %s - the seed search failed to find ground that suits the authored pins" % [
					twid, str(l.get("name", "")), lk, lclass])
			# SCORE, NOT JUST `suits`. Asserting only `suits` is asserting "not
			# drowned", which the very first candidate seed satisfies for every
			# pin - so the check passed while Hearthwood Market, a shop, sat on a
			# glacier at score 0.00. The bug was never that pins were underwater;
			# it was that nothing compared a pin to the ground at all.
			assert(ter.score(lk, lc) > 0.15,
				"%s: '%s' (%s) scores %.2f on %s - possible ground, but not ground of its kind; the seed search is not searching" % [
					twid, str(l.get("name", "")), lk, ter.score(lk, lc), lclass])
		# DETERMINISM. The Atlas, the minimap and the compiler each ask for this
		# world's ground separately; if two calls disagree, the pins and the paper
		# disagree, which is the whole defect being fixed here.
		WorldTerrain.forget(twid)
		var ter_again := WorldTerrain.for_world(twid)
		assert(ter_again.seed_used == ter.seed_used and is_equal_approx(ter_again.sea, ter.sea),
			"%s terrain is not deterministic - two calls gave seeds %d and %d" % [twid, ter.seed_used, ter_again.seed_used])
	assert(_seen_terrain >= 6, "only %d worlds had terrain built - the loop went blind" % _seen_terrain)
	# A PLACE WITH NO AUTHORED COORDINATES IS PLACED BY THE GROUND, NOT BY A HASH.
	#
	# `Rules.place_position` was `hash(name)` on a ring: deterministic, which was
	# the point, and blind to the world. Saltmarsh is 46 % sea and positioned all
	# three of its places that way, so each had roughly a 2-in-5 chance of
	# standing in open water - the same way every playthrough, since the hash
	# never changes.
	var _char_was = GameState.character
	for w2 in Rules.builtin_worlds():
		var ter_wid := str(w2.get("id", ""))
		if ter_wid == "":
			continue
		GameState.character = {"id": "dm-selfcheck", "world_id": ter_wid}
		var ter_g := WorldTerrain.for_world(ter_wid)
		var occupied := {}
		var searched := 0
		for l in GameState.places():
			if not (l is Dictionary) or not (l.has("x") and l.has("y")):
				continue
			var ter_cell := ter_g.cell_of(Vector2(float(l["x"]), float(l["y"])))
			var ter_kind := str(l.get("kind", ""))
			var ter_name := str(l.get("name", ""))
			# TWO PINS ON ONE CELL. The tie-break is hashed per (name, cell)
			# instead of a spacing pass over already-placed pins, because a
			# spacing term makes the answer depend on what else has been placed
			# and that is what stops it being memoisable - and it must be
			# memoisable, since mini_map._draw calls places() every frame. This
			# assertion is the property that spacing pass would have bought.
			var ter_ck := "%d,%d" % [ter_cell.x, ter_cell.y]
			assert(not occupied.has(ter_ck),
				"%s: '%s' and '%s' stand on the same cell %s - the placement tie-break has stopped spreading them" % [
					ter_wid, str(occupied.get(ter_ck, "")), ter_name, ter_ck])
			occupied[ter_ck] = ter_name
			assert(ter_g.suits(ter_kind, ter_cell),
				"%s: '%s' (%s) was placed on %s" % [ter_wid, ter_name, ter_kind,
					["deep", "shoal", "coast", "plain", "hill", "peak"][ter_g.klass(ter_cell)]])
			# A SEARCHED place must land WELL, not merely legally. An authored pin
			# is what it is and the terrain fits around it; a place the engine
			# positions itself has no excuse for poor ground.
			var authored := false
			for al in Rules.world_locations(ter_wid):
				if al is Dictionary and al.has("x") and str(al.get("name", "")) == ter_name:
					authored = true
			if not authored:
				searched += 1
				assert(ter_g.score(ter_kind, ter_cell) > 0.5,
					"%s: '%s' (%s) was SEARCHED for and still only scores %.2f on %s - the search is not reading the ground" % [
						ter_wid, ter_name, ter_kind, ter_g.score(ter_kind, ter_cell), ["deep", "shoal", "coast", "plain", "hill", "peak"][ter_g.klass(ter_cell)]])
		assert(occupied.size() > 0, "%s placed no pins at all - places() went blind" % ter_wid)
	GameState.character = _char_was

	# ── AT-6: KNOWING OF A PLACE IS NOT HAVING BEEN THERE ────────────────────
	#
	# Fog was two-state and the table rule said so: "the map hides what you
	# haven't walked". In a game narrated by an LLM that produces one specific,
	# severe failure — the GM says "word reaches you of the Sunken Fort", the
	# player opens the Atlas, and there is no such place. The map calls the
	# narrator a liar.
	#
	# Unlike the two rows below this, these are BEHAVIOURAL: hear_of/heard_of/
	# visited are pure data, so the states can be driven and read directly.
	var _fog_char = GameState.character
	var _fog_state = GameState.state
	GameState.character = {"id": "dm-fog", "world_id": "embervale"}
	GameState.state = {"world": {"here": "", "seen": [], "heard": []}}
	assert(not GameState.heard_of("Nowhere At All"), "an unmentioned place is not heard of")
	assert(not GameState.visited("Nowhere At All"), "an unmentioned place is not visited")
	GameState.hear_of("The Sunken Fort")
	assert(GameState.heard_of("The Sunken Fort"),
		"a place the tale NAMED is not on the chart - this is the exact contradiction AT-6 exists to end")
	assert(not GameState.visited("The Sunken Fort"),
		"hearing of a place must not count as having stood in it, or there are two states again")
	# VISITING IMPLIES HEARING OF, and this is the row that matters most.
	# Every save written before `heard` existed carries a `seen` list and no
	# `heard` at all. A place the player has STOOD IN must never come back as a
	# rumour because the format changed underneath them.
	GameState.state = {"world": {"here": "", "seen": ["Gallows Quay"]}}
	assert(GameState.visited("Gallows Quay"), "a seen place is visited")
	assert(GameState.heard_of("Gallows Quay"),
		"an OLD SAVE with `seen` and no `heard` demoted a visited place back to a rumour")
	# `here` counts on its own: a tale can open somewhere before anything is
	# written to either list.
	GameState.state = {"world": {"here": "The Ember & Oak", "seen": []}}
	assert(GameState.visited("The Ember & Oak") and GameState.heard_of("The Ember & Oak"),
		"where the player is STANDING must be the most known place on the chart")
	GameState.character = _fog_char
	GameState.state = _fog_state

	# ── AT-5 / AT-6: THE LOCAL TIER, AND FOG THAT LEAVES A CHOICE ────────────
	#
	# AT-3 cut this and was right to at the time: "a street tier would mean
	# inventing the data and then painting it". Both halves died with the painted
	# chart — the data is generated and there is nothing to paint.
	var _loc_char = GameState.character
	var _loc_state = GameState.state
	GameState.character = {"id": "dm-local", "world_id": "saltmarsh"}
	GameState.state = {"world": {"here": "", "seen": [], "heard": []}}
	LocalMap.forget()
	var town := LocalMap.for_place("saltmarsh", "Gallows Quay", "settlement")
	var barrow := LocalMap.for_place("fimbulreach", "The Barrow-Field", "ruin")
	assert(town.settled and not barrow.settled,
		"a settlement is settled and a ruin is not - the whole fog rule hangs off this")
	for lm in [town, barrow]:
		assert(lm.nodes.size() >= 4, "%s generated only %d rooms" % [lm.place, lm.nodes.size()])
		assert(not lm.edges.is_empty(), "%s generated no ways between its rooms" % lm.place)
		# EVERY ROOM REACHABLE FROM THE WAY IN. A node with no edge is a room the
		# player can see and never enter, which reads as a broken map.
		var seen_idx := {0: true}
		var queue := [0]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			for nb in lm.exits_of(cur):
				if not seen_idx.has(nb):
					seen_idx[nb] = true
					queue.append(nb)
		assert(seen_idx.size() == lm.nodes.size(),
			"%s: %d of %d rooms are cut off from the entrance" % [
				lm.place, lm.nodes.size() - seen_idx.size(), lm.nodes.size()])
		# Unique names: the fog lists are lists of NAMES, so a duplicate would
		# reveal two rooms at once.
		var names := {}
		for nd in lm.nodes:
			var nn := str(nd.get("name", ""))
			assert(not names.has(nn), "%s has two rooms called '%s'" % [lm.place, nn])
			names[nn] = true
	# A FRIENDLY TOWN IS NEVER FOGGED. People live there, there is signage, and
	# you can ask; fogging one means walking it to reveal streets, which is
	# busywork wearing exploration's clothes.
	for i in town.nodes.size():
		assert(town.state_of(i, 0, []) > 0,
			"'%s' in a SETTLED place is hidden - a town you have just walked into is not a dungeon" % str(town.nodes[i]["name"]))
	# ...and the DRAWING has to honour that. The screen treats state 1 as "a
	# doorway, not a room" — right for a barrow, wrong for a town, where the
	# footer promises "every street in sight". The first version drew five
	# unnamed rings under that promise.
	var pm_src := FileAccess.get_file_as_string("res://scenes/ui/place_map.gd")
	# A COASTAL TOWN MUST DRAW ITS WATER. The shore block was deleted by a
	# careless slice while removing something next to it, and Gallows Quay — a
	# QUAY — rendered landlocked. Nothing failed; the shot simply had no sea in
	# it, and only looking caught it.
	assert(pm_src.contains("lm.water_dir") and pm_src.contains("draw_colored_polygon(pts"),
		"place_map no longer draws the shore - a coastal town renders landlocked and nothing else notices")
	assert(pm_src.contains("if lm.settled:"),
		"place_map draws every un-walked room the same way - a settled place must still show its names, or the map contradicts its own footer")
	# A BARROW IS. And the fog must leave a CHOICE: standing in a room scouts the
	# rooms it opens onto. Reveal only where you are and exploring is a random
	# walk; reveal the neighbours and the player picks between visible options.
	var hidden := 0
	for i in barrow.nodes.size():
		if barrow.state_of(i, 0, []) == 0:
			hidden += 1
	assert(hidden > 0, "an UNSETTLED site hides nothing - fog is not applying where it should")
	for nb in barrow.exits_of(0):
		assert(barrow.state_of(nb, 0, []) == 1,
			"standing at the way in does not scout what it opens onto - exploring is a coin flip")
	assert(barrow.state_of(0, 0, []) == 2, "the room the player is standing in is not known")
	# PERMANENCE: a room walked stays known after moving on.
	var far := barrow.nodes.size() - 1
	assert(barrow.state_of(far, 0, [str(barrow.nodes[far]["name"])]) == 2,
		"a room already walked came back as unknown - fog is re-shrouding, which is an RTS convention")
	# DETERMINISM, the same rule the terrain follows: the Atlas, the screen and
	# any bake must each get the same town.
	LocalMap.forget()
	var town2 := LocalMap.for_place("saltmarsh", "Gallows Quay", "settlement")
	assert(town2.nodes.size() == town.nodes.size()
		and str(town2.nodes[0]["name"]) == str(town.nodes[0]["name"]),
		"the same place generated two different towns")
	GameState.character = _loc_char
	GameState.state = _loc_state

	var wm_src := FileAccess.get_file_as_string("res://scenes/ui/world_map.gd")

	# AT-7 / AT-8 — THE ATLAS READS WHAT THE PLACES ACTUALLY CARRY.
	#
	# `shop` sat on every place for the life of the project and `world_map.gd`
	# never once read it: "shop" appeared there only as a KIND, so a settlement
	# with a keeper behind a counter drew the same mark as one without. Regions
	# had the same shape of bug — real in the data, drawn as floating text.
	#
	# THESE ARE MECHANISM CHECKS AND THAT IS WORTH SAYING. They prove the Atlas
	# still ASKS for the field, not that what it draws is right; judging a badge
	# or a border is `screen_shots` work. They would not have caught the original
	# defect either, because the original defect was that nobody looked. What they
	# do catch is the field being quietly dropped again in a refactor.
	assert(wm_src.contains("l.get(\"shop\"") or wm_src.contains("get(\"shop\", \"\")"),
		"world_map.gd no longer reads a place's `shop` field - trade is invisible on the chart again (AT-7)")
	assert(wm_src.contains("region_at") and wm_src.contains("region_n"),
		"world_map.gd stopped handing region hearts to the chart shader - regions are back to floating text (AT-8)")
	var shader_src := FileAccess.get_file_as_string("res://ui/chart_paper.gdshader")
	assert(shader_src != "", "chart_paper.gdshader is missing - the Atlas has no paper")
	assert(shader_src.contains("uniform vec2 region_at"),
		"the chart shader no longer takes region hearts (AT-8)")
	# ONE FACE AND ONE SYMBOL SET ACROSS BOTH TIERS. `place_map` carried its own
	# `_draw_mark` with four shapes of its own before `MapInk` existed, and the
	# Atlas lettered in the theme default while the reference is a book map. Two
	# tiers of one atlas that letter differently read as two documents.
	var pm2_src := FileAccess.get_file_as_string("res://scenes/ui/place_map.gd")
	for pair in [[wm_src, "world_map"], [pm2_src, "place_map"]]:
		var src2: String = pair[0]
		assert(src2.contains("Ui.display"),
			"%s letters in its own font instead of Ui.display - the two map tiers must read as one document" % str(pair[1]))
		assert(src2.contains("MapInk."),
			"%s draws its own marks instead of MapInk - two answers to what a ruin looks like is how a legend stops describing the map" % str(pair[1]))
		assert(not src2.contains("get_theme_default_font()"),
			"%s fell back to the theme default font" % str(pair[1]))

	# AT-6, the drawing half: no question-mark cloud. A "?" is a promise, and a
	# point-crawl has no surface to sweep — a place either has a pin or it does
	# not — so clouds would import a busywork failure this design cannot produce.
	assert(not wm_src.contains("var q := \"?\""),
		"the Atlas is drawing question marks for unknown places again (AT-6)")
	assert(wm_src.contains("_state_of") and wm_src.contains("HEARD"),
		"world_map.gd has lost the heard-of state - fog is back to two states")
	# ...and the feature must have something to show, or it is dead code that
	# passes every grep. At least one shipped world has to carry a trader.
	var traders := 0
	for tw in Rules.builtin_worlds():
		for tl in Rules.world_locations(str(tw.get("id", ""))):
			if tl is Dictionary and str(tl.get("shop", "")) != "":
				traders += 1
	assert(traders > 0,
		"no shipped world has a place with a `shop` - the trade badge can never appear, so nothing would notice it breaking")

	# NOTHING READS TERRAIN OUT OF A PAINTING.
	#
	# `world_map._ensure_land` used to open chart.png and call blue "water" and
	# dark "steep". That is a colour heuristic over generated art, and it was
	# wrong in the way generated art is always wrong to read: Neon Spire's neon
	# strips became rivers, its night became mountains, and the top of every plate
	# was sky, because the plates are oblique illustrations with a horizon rather
	# than maps.
	#
	# This is a grep, and a grep is the honest shape here — the invariant is
	# literally a statement about what this file may touch, not a proxy for one.
	assert(wm_src != "", "world_map.gd is missing")
	for forbidden in ["get_pixel(", "get_image("]:
		assert(not wm_src.contains(forbidden),
			"world_map.gd calls %s - the road router is reading terrain out of the painting again (AT-4, and Invariants.md)" % forbidden)
	# ...and it must still be routing over SOMETHING, or the grep above passes on
	# a file that simply draws straight lines.
	assert(wm_src.contains("WorldTerrain.for_world"),
		"world_map.gd no longer asks WorldTerrain for its ground - roads have quietly gone back to straight lines")

	# ROUGH GROUND COSTS WHAT ITS WORLD'S RELIEF SAYS IT COSTS.
	#
	# This first compared MEAN cost across two whole worlds - and that check was
	# worthless, proven by mutation: hardcoding the HILL and PEAK constants so
	# `relief` no longer entered `cost()` at all left SELF-CHECK OK. The mean is
	# dominated by how much water and high country each world has, which
	# `_classify` decides, so the assertion was re-testing `_classify` (already
	# covered above) and saying nothing about `cost`.
	#
	# The claim `cost()` actually makes is per-class: the SAME kind of ground is
	# dearer in a world with more relief. So compare like with like.
	var _class_cost := func(wid2: String, want: int) -> float:
		var t2 := WorldTerrain.for_world(wid2)
		for yy in WorldTerrain.H:
			for xx in WorldTerrain.W:
				if t2.klass(Vector2i(xx, yy)) == want:
					return t2.cost(Vector2i(xx, yy))
		return -1.0
	# INK MUST READ ON ITS PAPER. The stock is per family and hand-picked, so the
	# one thing that can silently go wrong is a pairing nobody can read — pale ink
	# on pale vellum, or dark ink on a dark blueprint. Contrast is checkable where
	# taste is not, and below it the map is unusable.
	#
	# THROUGH `Ui.contrast_ratio`, not a hand-rolled one. The first version of
	# this computed luminance from `Color.get_luminance()`, which works on
	# GAMMA-ENCODED channels and is not the WCAG formula — it failed the fantasy
	# stock at "3.9:1" when the real ratio is 9.0:1. The repo already had the
	# right function, used by the palette checks a few hundred lines up, and
	# reaching past it to write a second one is how two answers to one question
	# get into a codebase.
	for fam2 in WorldTerrain.PAPER.keys():
		var ink_paper := Color(str(WorldTerrain.PAPER[fam2]["paper"]))
		var ink_ink := Color(str(WorldTerrain.PAPER[fam2]["ink"]))
		var got_ratio := Ui.contrast_ratio(ink_ink, ink_paper)
		assert(got_ratio >= Ui.TEXT_MIN,
			"'%s' draws %s ink on %s paper - %.1f:1, under the %.1f:1 the rest of this game is held to" % [
				fam2, ink_ink.to_html(false), ink_paper.to_html(false), got_ratio, Ui.TEXT_MIN])

	var city_hill: float = _class_cost.call("neonspire", WorldTerrain.HILL)
	var fjord_hill: float = _class_cost.call("fimbulreach", WorldTerrain.HILL)
	assert(city_hill > 0.0 and fjord_hill > 0.0,
		"no hill found in neonspire (%.2f) or fimbulreach (%.2f) - the class search went blind" % [city_hill, fjord_hill])
	assert(city_hill < fjord_hill * 0.8,
		"a rise in a megacity costs %.2f and one in a fjord world %.2f - relief has stopped driving cost()" % [city_hill, fjord_hill])

	print("SELF-CHECK OK")
	get_tree().quit(0)


## The first surface-override material on any mesh the doll is currently
## WEARING. Walked rather than looked up by path, because the holder's shape is
## ModularDoll's business and a test that hardcodes it breaks on every rig swap
## while proving nothing about the dye.
##
## Scoped to the worn pieces, not the whole doll: once hidden-surface removal
## landed, the BODY carries an override too, and walking everything found the
## skin's mask material first and asserted the dye against it.
func _first_override(doll: ModularDoll) -> Material:
	var worn: Array[MeshInstance3D] = []
	for slot in doll._extern:
		if is_instance_valid(doll._extern[slot]):
			worn.append_array(_meshes_under(doll._extern[slot]))
	for n in worn:
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


## The override on the BODY's skin surface, or null. Separate from
## _first_override, which walks what the doll is wearing — this walks what it is.
## What fraction of the coverage mask is white — how much of the skin it hides.
## Sampled every 8th texel; the answer is a proportion and does not need all
## 262,144 of them.
func _mask_white(m: Material) -> float:
	if not (m is ShaderMaterial):
		return -1.0
	var tex = m.get_shader_parameter("cover_mask")
	if not (tex is Texture2D):
		return -1.0
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return -1.0
	var hit := 0
	var seen := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			seen += 1
			if img.get_pixel(x, y).r > 0.5:
				hit += 1
	return float(hit) / float(maxi(seen, 1))


func _skin_override(doll: ModularDoll) -> Material:
	var want := str(doll.profile().get("skin_mat", ""))
	for n in _meshes_under(doll._body):
		if n.mesh == null:
			continue
		for i in n.mesh.get_surface_count():
			var src = n.mesh.surface_get_material(i)
			if src is StandardMaterial3D and src.resource_name.contains(want):
				return n.get_surface_override_material(i)
	return null

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

	print("SELF-CHECK OK")
	get_tree().quit(0)

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

	print("SELF-CHECK OK")
	get_tree().quit(0)

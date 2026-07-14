extends Node
## Rules — deterministic dice + check resolution, ported from characterStudio.js.
## The LLM never rolls; it asks (via tags), we resolve, it narrates.

const ABILITIES := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const AB_NAME := {
	"STR": "Strength", "DEX": "Dexterity", "CON": "Constitution",
	"INT": "Intelligence", "WIS": "Wisdom", "CHA": "Charisma",
}
const SKILL2AB := {
	"athletics": "STR", "acrobatics": "DEX", "sleight of hand": "DEX", "stealth": "DEX",
	"arcana": "INT", "history": "INT", "investigation": "INT", "nature": "INT", "religion": "INT",
	"animal handling": "WIS", "insight": "WIS", "medicine": "WIS", "perception": "WIS", "survival": "WIS",
	"deception": "CHA", "intimidation": "CHA", "performance": "CHA", "persuasion": "CHA",
}


func ability_mod(score: int) -> int:
	return floori((score - 10) / 2.0)


func prof_bonus(sheet: Dictionary) -> int:
	return 2 + floori((int(sheet.get("level", 1)) - 1) / 4.0)


func is_proficient(sheet: Dictionary, check: Dictionary) -> bool:
	var skill := str(check.get("skill", "")).to_lower()
	if skill.contains("sav"):
		return str(check.get("ability", "")) in sheet.get("profSaves", [])
	if skill != "" and SKILL2AB.has(skill):
		return skill in sheet.get("profSkills", [])
	return false


func check_mod(sheet: Dictionary, check: Dictionary) -> int:
	var ab := str(check.get("ability", ""))
	var abilities: Dictionary = sheet.get("abilities", {})
	var mod := ability_mod(int(abilities.get(ab, 10))) if ab != "" else 0
	if is_proficient(sheet, check):
		mod += prof_bonus(sheet)
	return mod


# ponytail: no equipped-weapon atk bonus yet — inventory lands in Phase 2.
func attack_mod(sheet: Dictionary) -> int:
	var abilities: Dictionary = sheet.get("abilities", {})
	var s := ability_mod(int(abilities.get("STR", 10)))
	var d := ability_mod(int(abilities.get("DEX", 10)))
	return maxi(s, d) + prof_bonus(sheet)


func passive_perception(sheet: Dictionary) -> int:
	var wis := ability_mod(int(sheet.get("abilities", {}).get("WIS", 10)))
	var prof := prof_bonus(sheet) if "perception" in sheet.get("profSkills", []) else 0
	return 10 + wis + prof


## mode: "" | "adv" | "dis" → {roll, rolls, mode}
func roll_d20(mode: String) -> Dictionary:
	var a := randi_range(1, 20)
	if mode == "adv" or mode == "dis":
		var b := randi_range(1, 20)
		return {"roll": maxi(a, b) if mode == "adv" else mini(a, b), "rolls": [a, b], "mode": mode}
	return {"roll": a, "rolls": [a], "mode": ""}


func d20_text(r: Dictionary) -> String:
	if str(r["mode"]) != "":
		var pair: Array = r["rolls"]
		return "d20 %s (%s/%s→%s)" % ["adv" if r["mode"] == "adv" else "dis", pair[0], pair[1], r["roll"]]
	return "d20 %s" % r["roll"]


func check_label(c: Dictionary) -> String:
	var ab: String = AB_NAME.get(str(c.get("ability", "")), str(c.get("ability", "")))
	var skill := str(c.get("skill", ""))
	if skill == "":
		return "%s check" % ab
	if skill.to_lower().contains("sav"):
		return "%s saving throw" % ab
	if skill == "Initiative":
		return "Initiative (Dexterity)"
	return "%s (%s)" % [ab, skill]


## Resolve any check dict (from a [[tag]] or the prose fallback) against the
## sheet. Returns {"text": markdown line for the GM, "total": int}. Message
## formats mirror the web client so the GM reads them identically.
func resolve_check(check: Dictionary, sheet: Dictionary) -> Dictionary:
	var mode := str(check.get("adv", ""))
	if check.get("type", "") == "attack":
		var am := attack_mod(sheet)
		var r := roll_d20(mode)
		var total: int = r["roll"] + am
		var verdict := ""
		if r["roll"] == 20:
			verdict = " — **critical hit!** 🎯"
		elif r["roll"] == 1:
			verdict = " — **critical miss!**"
		elif check.get("ac") != null:
			var ac := int(check["ac"])
			verdict = (" — **hit!** (AC %d)" if total >= ac else " — **miss** (AC %d)") % ac
		return {"text": "⚔ *attack roll* → %s %+d = **%d**%s" % [d20_text(r), am, total, verdict], "total": total}
	if check.get("type", "") == "damage":
		var n := int(check.get("n", 1))
		var sides := int(check.get("sides", 6))
		var bonus := int(check.get("bonus", 0))
		var rolls: Array[int] = []
		for i in n:
			rolls.append(randi_range(1, sides))
		var sum := bonus
		for v in rolls:
			sum += v
		var total := maxi(0, sum)
		var expr := "%dd%d (%s)%s" % [n, sides, ", ".join(rolls.map(func(x): return str(x))),
			(" + %d" % bonus) if bonus > 0 else ((" − %d" % absi(bonus)) if bonus < 0 else "")]
		var kind := "healing" if check.get("heal", false) else "damage"
		return {"text": "🎲 *%s* → %s = **%d** %s" % [kind, expr, total, "healed" if check.get("heal", false) else "damage"], "total": total}
	# Plain ability/skill check or save.
	var mod := check_mod(sheet, check)
	var prof := is_proficient(sheet, check)
	var r2 := roll_d20(mode)
	var total2: int = r2["roll"] + mod
	var verdict2 := ""
	if check.get("dc") != null:
		var dc := int(check["dc"])
		verdict2 = (" — **success!** (DC %d)" if total2 >= dc else " — **failure** (DC %d)") % dc
	return {"text": "🎲 *%s%s* → %s %+d = **%d**%s" % [check_label(check),
		" (proficient)" if prof else "", d20_text(r2), mod, total2, verdict2], "total": total2}

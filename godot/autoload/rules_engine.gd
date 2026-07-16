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

# Extracted game data (scripts/extract_studio_data.mjs → res://data/*.json):
# tables = classes/heritages/conditions/feats/…, spells + bestiary separate.
var tables: Dictionary = {}
var spells: Array = []
var bestiary: Array = []


var worlds_json: Dictionary = {}


func _ready() -> void:
	tables = _load_json("res://data/tables.json")
	spells = _load_json("res://data/spells.json").get("spells", [])
	bestiary = _load_json("res://data/bestiary.json").get("entries", [])
	worlds_json = _load_json("res://data/worlds.json")


func builtin_worlds() -> Array:
	return worlds_json.get("worlds", [])


func world_stories(wid: String) -> Array:
	return worlds_json.get("stories", {}).get(wid, [])


func world_locations(wid: String) -> Array:
	return worlds_json.get("locations", {}).get(wid, [])


func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func spell_named(nm: String) -> Dictionary:
	var want := nm.strip_edges()
	for sp in spells:
		if str(sp.get("name", "")).nocasecmp_to(want) == 0:
			return sp
	# "Firebolt" and "fire-bolt" are still Fire Bolt — match with spacing stripped.
	var squeezed := want.to_lower().replace(" ", "").replace("-", "")
	for sp in spells:
		if str(sp.get("name", "")).to_lower().replace(" ", "").replace("-", "") == squeezed:
			return sp
	return {}


# ── Items (ports of _weaponDie / _armorAcBonus / _mkItem / _itemValue) ──────
var _weapon_re := RegEx.create_from_string("(?i)dagger|knife|sickle|dart|greatsword|greataxe|maul|halberd|glaive|pike|claymore|longsword|battleaxe|warhammer|morningstar|flail|longbow|trident|crossbow|broadsword|shortsword|scimitar|rapier|shortbow|handaxe|mace|spear|whip|club|staff|quarterstaff|sword|axe|bow|blade|pistol|rifle|blaster")
var _shield_re := RegEx.create_from_string("(?i)shield|buckler")
var _armor_re := RegEx.create_from_string("(?i)plate|chain ?mail|chain shirt|splint|banded|scale|brigandine|ring mail|hide armor|leather|padded|studded|breastplate|armor|cuirass")


func weapon_die(nm: String) -> String:
	var n := nm.to_lower()
	for pat in [["dagger|knife|sickle|dart", "1d4"], ["greatsword|greataxe|maul|halberd|glaive|pike|claymore", "1d12"],
			["longsword|battleaxe|warhammer|morningstar|flail|longbow|trident|crossbow|broadsword", "1d8"]]:
		if RegEx.create_from_string("(?i)" + pat[0]).search(n):
			return pat[1]
	return "1d6"


func armor_ac_bonus(nm: String) -> int:
	var n := nm.to_lower()
	for pat in [["full plate|^plate|plate armor", 6], ["half.?plate|breastplate|chain ?mail|splint|banded", 4],
			["scale|chain shirt|brigandine|ring mail|hide", 3], ["leather|padded|studded", 2],
			["shield|buckler", 2], ["cloak|robe|cloth", 1]]:
		if RegEx.create_from_string("(?i)" + str(pat[0])).search(n):
			return pat[1]
	return 2


func item_type(nm: String) -> String:
	if _shield_re.search(nm):
		return "shield"
	if _weapon_re.search(nm):
		return "weapon"
	if _armor_re.search(nm):
		return "armor"
	return "gear"


func item_value(rarity: String) -> int:
	return {"common": 6, "uncommon": 20, "rare": 65, "epic": 175, "legendary": 500}.get(rarity, 6)


func sell_value(rarity: String) -> int:
	return maxi(1, item_value(rarity) / 2)


## Full item from a bare name — weapon dice, magic atk bonus, armor AC.
func mk_item(nm: String, rarity := "common", qty := 1) -> Dictionary:
	var it := {"id": "it-%d" % (randi() % 1000000), "name": nm.strip_edges(), "qty": qty,
		"type": item_type(nm), "rarity": rarity}
	if it["type"] == "weapon":
		it["dmg"] = weapon_die(nm)
		it["atk"] = {"rare": 1, "epic": 1, "legendary": 2}.get(rarity, 0)
	elif it["type"] in ["armor", "shield"]:
		var ac := 2 if it["type"] == "shield" else armor_ac_bonus(nm)
		ac += {"epic": 1, "legendary": 2}.get(rarity, 0)
		it["acBonus"] = ac
	return it


# ── AC (port of _baseAC/_effAC: DEX caps by armor weight, unarmored defense) ─
func eff_ac(s: Dictionary, inv: Dictionary) -> int:
	var equipped: Dictionary = inv.get("equipped", {})
	var items: Array = inv.get("items", [])
	var find := func(id):
		for it in items:
			if str(it.get("id", "")) == str(id):
				return it
		return null
	var body = find.call(equipped.get("armor"))
	var dex := ability_mod(int(s["abilities"].get("DEX", 10)))
	if body != null:
		var b := int(body.get("acBonus", 0))
		if b >= 6:
			dex = 0
		elif b >= 3:
			dex = mini(dex, 2)
	var ac := 10 + dex
	if body == null:
		var cls := str(s.get("cls", ""))
		if cls == "Barbarian":
			ac += maxi(0, ability_mod(int(s["abilities"].get("CON", 10))))
		elif cls == "Monk":
			ac += maxi(0, ability_mod(int(s["abilities"].get("WIS", 10))))
	for key in equipped:
		var it = find.call(equipped[key])
		if it != null:
			ac += int(it.get("acBonus", 0))
	return ac


# ── Casting / XP ─────────────────────────────────────────────────────────────
const CAST_ABIL := {"Wizard": "INT", "Cleric": "WIS", "Druid": "WIS", "Bard": "CHA",
	"Sorcerer": "CHA", "Warlock": "CHA", "Paladin": "CHA", "Ranger": "WIS", "Artificer": "INT"}


func cast_ability(s: Dictionary) -> String:
	return CAST_ABIL.get(str(s.get("cls", "")), "")


func spell_save_dc(s: Dictionary) -> int:
	var ab := cast_ability(s)
	if ab == "":
		return -1
	return 8 + prof_bonus(s) + ability_mod(int(s["abilities"].get(ab, 10)))


func spell_attack(s: Dictionary) -> int:
	var ab := cast_ability(s)
	if ab == "":
		return -1
	return prof_bonus(s) + ability_mod(int(s["abilities"].get(ab, 10)))


func xp_for_level(lvl: int) -> int:
	var t := 0
	for i in range(1, lvl):
		t += i * 100
	return t


func level_for_xp(xp: int) -> int:
	var lvl := 1
	while xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl


## Highest spell circle a class reaches at a level (port of _maxCircle).
func max_circle(cls: String, level: int) -> int:
	var preset: Dictionary = tables.get("class_presets", {}).get(cls, {})
	if bool(preset.get("caster", false)):
		return mini(5, ceili(clampi(level, 1, 9) / 2.0))
	if cls in ["Ranger", "Paladin"]:
		return 3 if level >= 9 else (2 if level >= 5 else (1 if level >= 2 else 0))
	return 0


## Spells this hero could learn right now (class list, reachable circle, unknown).
func learnable_spells(s: Dictionary) -> Array:
	var cls := str(s.get("cls", ""))
	var circle := max_circle(cls, int(s.get("level", 1)))
	if circle == 0:
		return []
	var known := {}
	for sp in s.get("spells", []):
		known[str(sp.get("name", "")).to_lower()] = true
	var out: Array = []
	for sp in spells:
		if sp.get("classes", []).has(cls) and int(sp.get("level", 9)) <= circle \
				and not known.has(str(sp.get("name", "")).to_lower()):
			out.append(sp)
	return out


func full_caster_slots(level: int) -> Dictionary:
	var m: Dictionary = tables.get("caster_slots", {}).get(str(clampi(level, 1, 9)), {})
	var out := {}
	for l in [1, 2, 3, 4, 5]:
		out[str(l)] = {"max": int(m.get(str(l), 0)), "used": 0}
	return out


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


func attack_mod(sheet: Dictionary, inv: Dictionary = {}) -> int:
	var abilities: Dictionary = sheet.get("abilities", {})
	var s := ability_mod(int(abilities.get("STR", 10)))
	var d := ability_mod(int(abilities.get("DEX", 10)))
	var m := maxi(s, d) + prof_bonus(sheet)
	var wid = inv.get("equipped", {}).get("weapon")
	if wid != null:
		for it in inv.get("items", []):
			if str(it.get("id", "")) == str(wid):
				m += int(it.get("atk", 0))
				break
	return m


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
func resolve_check(check: Dictionary, sheet: Dictionary, inv: Dictionary = {}) -> Dictionary:
	var mode := str(check.get("adv", ""))
	if check.get("type", "") == "attack":
		var am := attack_mod(sheet, inv)
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
		return {"text": "⚔ *attack roll* → %s %+d = **%d**%s" % [d20_text(r), am, total, verdict], "total": total, "roll": r["roll"], "sides": 20}
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
		return {"text": "🎲 *%s* → %s = **%d** %s" % [kind, expr, total, "healed" if check.get("heal", false) else "damage"], "total": total, "roll": total, "sides": sides}
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
		" (proficient)" if prof else "", d20_text(r2), mod, total2, verdict2], "total": total2, "roll": r2["roll"], "sides": 20}

extends Node
## Tags — the structured GM protocol. The model ends replies with lines like
## [[check ability=DEX skill=Stealth dc=13]]; we parse them here and strip
## them from the displayed narration. detect_check() is the prose fallback
## (a straight port of the web client's _detectCheck) for non-compliant turns.

var _tag_re := RegEx.create_from_string("\\[\\[(\\w[\\w-]*)([^\\]]*)\\]\\]")
var _attr_re := RegEx.create_from_string("(\\w[\\w-]*)\\s*=\\s*(?:\"([^\"]*)\"|(\\S+))")
var _dice_re := RegEx.create_from_string("(?i)\\b(\\d{1,2})d(\\d{1,3})\\b\\s*([+-]\\s*\\d+)?")


## → {"clean": narration without tags, "tags": [{name, attrs:{k:v}}]}
func parse(text: String) -> Dictionary:
	var tags: Array = []
	for m in _tag_re.search_all(text):
		var attrs := {}
		for a in _attr_re.search_all(m.get_string(2)):
			attrs[a.get_string(1)] = a.get_string(2) if a.get_string(2) != "" else a.get_string(3)
		tags.append({"name": m.get_string(1), "attrs": attrs})
	var clean := _tag_re.sub(text, "", true).strip_edges()
	return {"clean": clean, "tags": tags}


## First roll-requiring tag → a check dict Rules.resolve_check understands, or {}.
func check_from_tags(tags: Array) -> Dictionary:
	for t in tags:
		var a: Dictionary = t["attrs"]
		match str(t["name"]):
			"check":
				var c := {"ability": str(a.get("ability", "")).to_upper(), "skill": str(a.get("skill", ""))}
				if a.has("dc"):
					c["dc"] = int(a["dc"])
				c["adv"] = "adv" if a.has("adv") else ("dis" if a.has("dis") else "")
				if c["ability"] == "" and Rules.SKILL2AB.has(c["skill"].to_lower()):
					c["ability"] = Rules.SKILL2AB[c["skill"].to_lower()]
				return c
			"attack":
				var c2 := {"type": "attack", "adv": "adv" if a.has("adv") else ("dis" if a.has("dis") else "")}
				if a.has("ac"):
					c2["ac"] = int(a["ac"])
				return c2
			"damage", "heal":
				var d := _dice(str(a.get("roll", "")))
				if not d.is_empty():
					d["heal"] = t["name"] == "heal"
					return d
	return {}


func _dice(expr: String) -> Dictionary:
	var m := _dice_re.search(expr)
	if m == null:
		return {}
	var bonus := 0
	if m.get_string(3) != "":
		bonus = int(m.get_string(3).replace(" ", ""))
	return {"type": "damage", "n": int(m.get_string(1)), "sides": int(m.get_string(2)), "bonus": bonus}


# ── Prose fallback (port of _detectCheck) ───────────────────────────────────
const _AB_FULL := {
	"strength": "STR", "dexterity": "DEX", "constitution": "CON",
	"intelligence": "INT", "wisdom": "WIS", "charisma": "CHA",
	"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA",
}

var _init_re := RegEx.create_from_string("(?i)\\broll(?:ing)?\\s+(?:for\\s+)?initiative\\b")
var _atk_re := RegEx.create_from_string("(?i)\\b(attack roll|roll to hit|make an attack|roll an attack)\\b")
var _dmg_word_re := RegEx.create_from_string("(?i)\\b(damage|dmg|healing|heal|hit points|hp)\\b")
var _heal_word_re := RegEx.create_from_string("(?i)\\b(healing|heal)\\b")
var _ab_check_re := RegEx.create_from_string("(?i)\\b(strength|dexterity|constitution|intelligence|wisdom|charisma|str|dex|con|int|wis|cha)\\b\\s*(?:\\(([^)]{2,40})\\))?\\s*(check|saving throw|save)\\b")
var _skill_re := RegEx.create_from_string("(?i)\\b(athletics|acrobatics|sleight of hand|stealth|arcana|history|investigation|nature|religion|animal handling|insight|medicine|perception|survival|deception|intimidation|performance|persuasion)\\b\\s*(?:check)?")
var _checkroll_re := RegEx.create_from_string("(?i)check|roll")
var _dc_re := RegEx.create_from_string("(?i)\\bDC\\s*(\\d+)")
var _ac_re := RegEx.create_from_string("(?i)\\bAC\\s*(\\d+)")


func _find(re: RegEx, text: String) -> Variant:
	var m := re.search(text)
	return int(m.get_string(1)) if m else null


func _adv_mode(text: String) -> String:
	if text.matchn("*disadvantage*"):
		return "dis"
	if text.matchn("*advantage*"):
		return "adv"
	return ""


# ── Combat-start prose fallback (port of _detectCombatStart) ────────────────
const _COMBAT_VERBS := "attacks?|lunges?|charges?|strikes? at you|swings? at you|springs?|pounces?|snarls?|growls?|roars?|blocks? your|bars? your|emerges?|draws? (?:a |its |his |her )?(?:weapon|blade|sword)|rushes? (?:at |toward )you|ambush(?:es)?|attacks!"
var _init_call_re := RegEx.create_from_string("(?i)\\broll(?:ing)?\\s+(?:for\\s+)?initiative\\b|combat begins|the fight is on|battle is joined")
var _foe_re := RegEx.create_from_string("(?i)\\b(?:a|an|the)\\s+([a-z][a-z' -]{2,32}?)\\s+(?:%s)" % _COMBAT_VERBS)
var _foe_adj_re := RegEx.create_from_string("(?i)^(?:sudden|nearby|massive|huge|towering|hulking|snarling|angry|hostile|great|dark|shadowy|looming|fierce|wild)\\s+")
var _foe_bad_re := RegEx.create_from_string("(?i)\\b(?:spell|strain|attack|attempt|effort|roll|save|check|throw|note|failure|failed|aid|magic|blow|strike|swing|turn|round|damage|scene|story|moment|option|chance|way|plan|idea|question|opportunity|reaction|advantage|disadvantage|initiative|inspiration|perception|surprise|condition|action|bonus|movement|challenge|threat|danger|risk|memory|thought|feeling|instinct|your|my|this|that|these|those|to|will|would|could|can|you|i|we|as|and|but|with|into|from|near|upon|while|when|where|here|there|is|are|was|were|has|have|had|air|wind|door|gate|voice|silence|tension|figure|shape|sound|noise|smell|shiver|chill|storm|world|ground|floor|shaft|entrance|wall|ceiling|corridor|chamber|doorway|realization)\\b")


func detect_combat_start(text: String) -> String:
	if text == "":
		return ""
	var initiative := _init_call_re.search(text) != null
	var m := _foe_re.search(text)
	var enemy := m.get_string(1).strip_edges() if m else ""
	enemy = _foe_adj_re.sub(enemy, "").strip_edges()
	if enemy != "" and (enemy.split(" ").size() > 3 or _foe_bad_re.search(enemy)):
		enemy = ""
	if enemy == "":
		return "Enemy" if initiative else ""
	return enemy.capitalize()


func detect_check(text: String) -> Dictionary:
	if text == "":
		return {}
	var adv := _adv_mode(text)
	if _init_re.search(text):
		return {"ability": "DEX", "skill": "Initiative", "adv": adv}
	if _atk_re.search(text):
		var c := {"type": "attack", "adv": adv}
		var ac = _find(_ac_re, text)
		if ac != null:
			c["ac"] = ac
		return c
	var dm := _dice_re.search(text)
	if dm and _dmg_word_re.search(text):
		var d := _dice(dm.get_string(0))
		d["heal"] = _heal_word_re.search(text) != null
		return d
	var m := _ab_check_re.search(text)
	if m:
		var skill := m.get_string(2).strip_edges()
		if skill == "" and m.get_string(3).to_lower().contains("sav"):
			skill = "saving throw"
		var c2 := {"ability": _AB_FULL[m.get_string(1).to_lower()], "skill": skill, "adv": adv}
		var dc = _find(_dc_re, text)
		if dc != null:
			c2["dc"] = dc
		return c2
	m = _skill_re.search(text)
	if m and _checkroll_re.search(text):
		var skill2 := m.get_string(1).to_lower()
		var c3 := {"ability": Rules.SKILL2AB.get(skill2, ""), "skill": m.get_string(1), "adv": adv}
		var dc2 = _find(_dc_re, text)
		if dc2 != null:
			c3["dc"] = dc2
		return c3
	return {}

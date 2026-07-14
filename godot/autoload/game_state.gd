extends Node
## GameState — the selected adventure, its session, and the server-mirrored
## world state (kinds: sheet, inv, clock, combat, …). Server is the source of
## truth; every mutation saves back via PUT state/{cid}/{kind}. Formulas live
## in Rules; this file owns state + the ported game procedures (rests, time).

const DEFAULT_SHEET := {
	"name": "", "cls": "Adventurer", "level": 1, "xp": 0, "hp": 10, "hpMax": 10,
	"ac": 10, "gold": 0,
	"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
	"inventory": [], "conditions": [], "notes": "", "spells": [], "slots": {},
	"profSkills": [], "profSaves": [], "hitDie": 8, "hitDiceUsed": 0, "exhaustion": 0,
}
const TIMES := ["Dawn", "Morning", "Midday", "Afternoon", "Dusk", "Nightfall", "Deep Night"]
const WEATHERS := {
	"embervale": [["☀️", "clear skies"], ["🌤", "drifting clouds"], ["🌧", "soft valley rain"], ["🌫", "low mist"], ["💨", "cold wind off the hills"], ["⛈", "a brewing storm"]],
	"neonspire": [["🌧", "steady rain"], ["🌧", "acid drizzle"], ["🌫", "smog haze"], ["⛈", "an electric storm"], ["🌤", "a rare dry spell"]],
	"everyday": [["☀️", "sunshine"], ["🌤", "partly cloudy"], ["🌧", "light rain"], ["💨", "a breezy day"], ["❄️", "a cold snap"]],
	"_": [["☀️", "clear weather"], ["🌤", "scattered clouds"], ["🌧", "rain"], ["🌫", "fog"], ["💨", "strong wind"], ["⛈", "a storm"]],
}

var character: Dictionary = {}
var session_id := ""
var state: Dictionary = {}


func cid() -> String:
	return str(character.get("id", ""))


func world_id() -> String:
	return str(character.get("world_id", ""))


func hydrate() -> void:
	state = {}
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/" + cid().uri_encode())
	if r.get("_status", 0) == 200 and r.get("state") is Dictionary:
		state = r["state"]


func save_kind(kind: String, value) -> void:
	state[kind] = value
	await Api.call_json(HTTPClient.METHOD_PUT,
		"/api/characters/studio/state/%s/%s" % [cid().uri_encode(), kind], {"value": value})


func _merged(kind: String, defaults: Dictionary) -> Dictionary:
	var d := defaults.duplicate(true)
	var stored = state.get(kind)
	if stored is Dictionary:
		d.merge(stored, true)
	return d


# ── Sheet ───────────────────────────────────────────────────────────────────
func sheet() -> Dictionary:
	var s := _merged("sheet", DEFAULT_SHEET)
	for k in DEFAULT_SHEET["abilities"]:
		if not s["abilities"].has(k):
			s["abilities"][k] = 10
	return s


func set_sheet(s: Dictionary) -> void:
	save_kind("sheet", s)


## delta < 0 = damage, > 0 = healing. Returns the saved sheet.
func apply_hp(delta: int) -> Dictionary:
	var s := sheet()
	s["hp"] = clampi(int(s["hp"]) + delta, 0, int(s["hpMax"]))
	set_sheet(s)
	return s


func add_gold(delta: int) -> int:
	var s := sheet()
	s["gold"] = maxi(0, roundi(int(s.get("gold", 0)) + delta))
	set_sheet(s)
	return s["gold"]


func learn_spell(nm: String) -> bool:
	var known := Rules.spell_named(nm)
	if known.is_empty():
		return false
	var s := sheet()
	for sp in s.get("spells", []):
		if str(sp.get("name", "")).nocasecmp_to(nm) == 0:
			return false
	s["spells"].append({"name": str(known.get("name", nm)), "level": int(known.get("level", 1))})
	set_sheet(s)
	return true


# ── Inventory ───────────────────────────────────────────────────────────────
func inv() -> Dictionary:
	return _merged("inv", {"slots": 24, "items": [], "equipped": {}})


func add_item(nm: String, rarity := "common", qty := 1) -> void:
	var v := inv()
	for it in v["items"]:
		if str(it.get("name", "")).nocasecmp_to(nm) == 0:
			it["qty"] = int(it.get("qty", 1)) + qty
			save_kind("inv", v)
			return
	v["items"].append({"id": "%s-%d" % [nm.to_lower().replace(" ", "-"), randi() % 10000],
		"name": nm, "qty": qty, "rarity": rarity})
	save_kind("inv", v)


func inv_text() -> String:
	var v := inv()
	var items: Array = v.get("items", [])
	if items.is_empty():
		return ""
	var names: Array[String] = []
	for it in items:
		var q := int(it.get("qty", 1))
		names.append(str(it.get("name", "")) + (" ×%d" % q if q > 1 else ""))
	return "The player's pack holds: %s." % ", ".join(names)


func spell_text() -> String:
	var s := sheet()
	var spells: Array = s.get("spells", [])
	if spells.is_empty():
		return ""
	var known: Array[String] = []
	for sp in spells:
		known.append(str(sp.get("name", "")) + ((" (lvl %d)" % int(sp["level"])) if int(sp.get("level", 0)) > 0 else " (cantrip)"))
	var t := "The player knows these spells: %s." % ", ".join(known)
	var slots: Dictionary = s.get("slots", {})
	var parts: Array[String] = []
	for l in slots:
		if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
			parts.append("L%s %d/%d" % [l, maxi(0, int(slots[l]["max"]) - int(slots[l].get("used", 0))), int(slots[l]["max"])])
	if not parts.is_empty():
		t += " Spell slots remaining: %s. Don't let them cast a leveled spell with no slot left." % ", ".join(parts)
	return t


# ── Clock / weather (port of _advanceTime) ──────────────────────────────────
func clock() -> Dictionary:
	return _merged("clock", {"day": 1, "ti": 1, "at": 0})


func advance_time(steps := 1) -> Dictionary:
	var c := clock()
	var prev_day := int(c.get("day", 1))
	c["ti"] = int(c.get("ti", 0)) + steps
	while int(c["ti"]) >= TIMES.size():
		c["ti"] = int(c["ti"]) - TIMES.size()
		c["day"] = int(c.get("day", 1)) + 1
	if not (c.get("wx") is Dictionary) or int(c["day"]) != prev_day:
		var list: Array = WEATHERS.get(world_id(), WEATHERS["_"])
		var w: Array = list[randi() % list.size()]
		c["wx"] = {"ico": w[0], "name": w[1]}
	save_kind("clock", c)
	# Timed sheet conditions wane as in-world time passes.
	var s := sheet()
	var conds: Array = s.get("conditions", [])
	if conds.any(func(x): return x is Dictionary and x.get("rounds") != null):
		var kept: Array = []
		for x in conds:
			if x is Dictionary and x.get("rounds") != null:
				x["rounds"] = int(x["rounds"]) - 1
				if int(x["rounds"]) > 0:
					kept.append(x)
			else:
				kept.append(x)
		s["conditions"] = kept
		set_sheet(s)
	return c


func clock_text() -> String:
	var c := clock()
	var wx := (", under " + str(c["wx"]["name"])) if c.get("wx") is Dictionary else ""
	return "In-world time: %s, day %d of the adventure%s. Keep time's passage and weather consistent and let them color the scene (light, who's about, what's open)." % [
		TIMES[clampi(int(c.get("ti", 0)), 0, TIMES.size() - 1)], int(c.get("day", 1)), wx]


# ── Rests (ports of _shortRest / _longRest) ─────────────────────────────────
## → {note: player-visible line, gm: bracketed instruction for the GM}
func short_rest() -> Dictionary:
	var s := sheet()
	var pool := int(s.get("level", 1))
	var used := int(s.get("hitDiceUsed", 0))
	var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
	var heal := 0
	var note: String
	if used < pool:
		var die := int(s.get("hitDie", 8))
		heal = maxi(1, randi_range(1, die) + con)
		s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + heal)
		s["hitDiceUsed"] = used + 1
		note = "🌙 *You take a short rest — spend a Hit Die (d%d%+d CON) and recover **%d HP**, now %d/%d. Hit Dice left: %d/%d.*" % [
			die, con, heal, int(s["hp"]), int(s["hpMax"]), pool - int(s["hitDiceUsed"]), pool]
	else:
		note = "🌙 *You rest an hour, but you're out of Hit Dice (%d/%d spent) — a long rest is what you need to heal.*" % [pool, pool]
	set_sheet(s)
	advance_time(1)
	var gm := "[I take a short rest%s. Briefly narrate the pause, then continue.]" % [
		(", recovering %d HP" % heal) if heal > 0 else " but I am out of Hit Dice"]
	return {"note": note, "gm": gm}


func long_rest() -> Dictionary:
	var s := sheet()
	# The night is not guaranteed: 1-in-4 rests are interrupted.
	var interrupted := randf() < 0.25
	if interrupted:
		s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + maxi(1, ceili((int(s["hpMax"]) - int(s.get("hp", 0))) / 2.0)))
		s["hitDiceUsed"] = maxi(0, int(s.get("hitDiceUsed", 0)) - ceili(int(s.get("level", 1)) / 2.0))
	else:
		s["hp"] = int(s["hpMax"])
		s["conditions"] = []
		s["concentration"] = null
		s["hitDiceUsed"] = 0
	var slots: Dictionary = s.get("slots", {})
	for l in slots:
		if slots[l] is Dictionary:
			slots[l]["used"] = 0
	if int(s.get("exhaustion", 0)) > 0:
		s["exhaustion"] = int(s["exhaustion"]) - 1
	set_sheet(s)
	var c := clock()
	var steps := TIMES.size() if int(c.get("ti", 0)) == 0 else TIMES.size() - int(c.get("ti", 0))
	advance_time(steps)
	var note := ("⛺ *You make camp — but something finds you in the night. You wake half-rested at %d/%d HP.*" % [int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else ("⛺ *You make camp and sleep. You wake at dawn, fully restored — %d/%d HP.*" % [int(s["hpMax"]), int(s["hpMax"])])
	var gm := ("[My rest is interrupted in the night — run a short encounter fitting where I'm camped. I woke at %d/%d HP, only half-rested. Open on the moment I startle awake.]" % [int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else "[I take a long rest through the night and wake at dawn, fully healed. Narrate the new morning and what's changed, then continue.]"
	return {"note": note, "gm": gm}

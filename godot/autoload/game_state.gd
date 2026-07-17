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

signal leveled_up(from_level: int, to_level: int)

var character: Dictionary = {}
var session_id := ""
var state: Dictionary = {}
var pending_hero: Dictionary = {}   # a banked hero chosen to fill the next adventure's Quenching


# ── Banked heroes: a persistent roster forged at the anvil ───────────────────
## Heroes survive shutdown and being played — a forged legend is a reusable
## template you can begin many adventures with (fixes the "my hero vanished"
## data loss: the old single-file draft was deleted the moment it was used).
const HERO_ROSTER := "user://heroes.json"


func banked_heroes() -> Array:
	var arr: Array = []
	if FileAccess.file_exists(HERO_ROSTER):
		var p = JSON.parse_string(FileAccess.get_file_as_string(HERO_ROSTER))
		if p is Array:
			arr = p
	# Migrate (once) the legacy single-file banked hero into the roster.
	if FileAccess.file_exists("user://forged_hero.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://forged_hero.json"))
		if d is Dictionary and str(d.get("name", "")) != "":
			arr = _roster_upsert(arr, d)
			_write_roster(arr)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://forged_hero.json"))
	return arr


func bank_hero(d: Dictionary) -> void:
	if d.is_empty() or str(d.get("name", "")) == "":
		return
	_write_roster(_roster_upsert(banked_heroes(), d))


func unbank_hero(hero_name: String) -> void:
	_write_roster(banked_heroes().filter(func(h): return str(h.get("name", "")).nocasecmp_to(hero_name) != 0))


func _roster_upsert(arr: Array, d: Dictionary) -> Array:
	var out: Array = arr.filter(func(h): return str(h.get("name", "")).nocasecmp_to(str(d.get("name", ""))) != 0)
	out.append(d)
	return out


func _write_roster(arr: Array) -> void:
	var f := FileAccess.open(HERO_ROSTER, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arr))
		f.close()


func cid() -> String:
	return str(character.get("id", ""))


func world_id() -> String:
	return str(character.get("world_id", ""))


## One number, three names: gold in the vale, credits in the spire, cash at home.
func currency() -> String:
	return {"embervale": "gold", "neonspire": "credits", "everyday": "cash"}.get(world_id(), "gold")


## DM adventures carry the game systems; everything else is pure conversation.
func is_dm() -> bool:
	return cid().begins_with("dm-")


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


func grant_inspiration() -> bool:
	var s := sheet()
	if bool(s.get("inspiration", false)):
		return false
	s["inspiration"] = true
	set_sheet(s)
	return true


func spend_inspiration() -> bool:
	var s := sheet()
	if not bool(s.get("inspiration", false)):
		return false
	s["inspiration"] = false
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
	v["items"].append(Rules.mk_item(nm, rarity, qty))
	save_kind("inv", v)


func item_by_id(id: String) -> Dictionary:
	for it in inv().get("items", []):
		if str(it.get("id", "")) == id:
			return it
	return {}


## Equip into its type slot (weapon/armor/shield); same id again unequips.
## → note text, or "" if the item can't be worn.
func toggle_equip(id: String) -> String:
	var v := inv()
	var it := {}
	for x in v["items"]:
		if str(x.get("id", "")) == id:
			it = x
			break
	if it.is_empty():
		return ""
	var slot := str(it.get("type", "gear"))
	if not slot in ["weapon", "armor", "shield"]:
		return ""
	var eq: Dictionary = v.get("equipped", {})
	# A second light weapon slips into the off-hand (two-weapon fighting).
	if slot == "weapon" and str(eq.get("weapon", "")) != "" and str(eq.get("weapon", "")) != id:
		var light_re := RegEx.create_from_string("(?i)dagger|shortsword|handaxe|hatchet|scimitar|club|sickle|knife")
		if light_re.search(str(it.get("name", ""))) != null:
			slot = "offhand"
	if str(eq.get(slot, "")) == id:
		eq.erase(slot)
		save_kind("inv", v)
		return "You put away the %s." % it["name"]
	eq[slot] = id
	v["equipped"] = eq
	save_kind("inv", v)
	return "You ready the %s%s." % [it["name"],
		(" (%s, %+d to hit)" % [it.get("dmg", ""), int(it.get("atk", 0))]) if slot == "weapon" and int(it.get("atk", 0)) > 0
		else (" (+%d AC)" % int(it.get("acBonus", 0))) if it.get("acBonus") != null else ""]


## Sell one of the item at half value. → note text.
func sell_item(id: String) -> String:
	var v := inv()
	for i in v["items"].size():
		var it: Dictionary = v["items"][i]
		if str(it.get("id", "")) == id:
			var price := Rules.sell_value(str(it.get("rarity", "common")))
			if int(it.get("qty", 1)) > 1:
				it["qty"] = int(it["qty"]) - 1
			else:
				var eq: Dictionary = v.get("equipped", {})
				for k in eq.keys():
					if str(eq[k]) == id:
						eq.erase(k)
				v["items"].remove_at(i)
			save_kind("inv", v)
			var total := add_gold(price)
			return "You sell the %s for %d gold — purse now %d." % [it["name"], price, total]
	return ""


## A table rule set at the Campaign Forge (world.rules) — engine-enforced:
## difficulty scales foes, permadeath archives the save, fog hides the map,
## companions gates recruiting, house feeds the envelope.
func rule(key: String, dflt = null):
	var w = state.get("world")
	if w is Dictionary and w.get("rules") is Dictionary:
		return w["rules"].get(key, dflt)
	return dflt


## Cast a known spell, spending the lowest fitting slot. → note, or "" on fail.
func cast_spell(nm: String) -> String:
	var s := sheet()
	var known := {}
	for sp in s.get("spells", []):
		if str(sp.get("name", "")).nocasecmp_to(nm) == 0:
			known = sp
			break
	if known.is_empty():
		return ""
	var lv := int(known.get("level", 0))
	var cast_note := ""
	if lv > 0:
		var slots: Dictionary = s.get("slots", {})
		var found := ""
		var keys := slots.keys()
		keys.sort()
		for l in keys:
			if int(str(l)) >= lv and slots[l] is Dictionary \
					and int(slots[l].get("used", 0)) < int(slots[l].get("max", 0)):
				found = str(l)
				break
		if found == "":
			return "✋ *No spell slot left for %s — a long rest restores your magic.*" % nm
		slots[found]["used"] = int(slots[found]["used"]) + 1
		set_sheet(s)
		cast_note = " (L%s slot spent, %d/%d left)" % [found,
			int(slots[found]["max"]) - int(slots[found]["used"]), int(slots[found]["max"])]
	var dc := Rules.spell_save_dc(s)
	var stat := (" Spell save DC %d, spell attack %+d." % [dc, Rules.spell_attack(s)]) if dc > 0 else ""
	return "✨ *You cast **%s**%s.%s*" % [known.get("name", nm), cast_note, stat]


## Port of _awardXp: average hit-die HP per level, full heal, auto-features.
## → {note, leveled: bool}
func award_xp(amount: int, reason := "") -> Dictionary:
	if amount <= 0:
		return {"note": "", "leveled": false}
	var s := sheet()
	var before := int(s.get("level", 1))
	s["xp"] = int(s.get("xp", 0)) + amount
	var after := Rules.level_for_xp(int(s["xp"]))
	var note := "✨ *Gained %d XP%s.*" % [amount, (" — " + reason) if reason != "" else ""]
	if after > before:
		var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
		var die_avg := int(s.get("hitDie", 8)) / 2 + 1
		for l in range(before, after):
			s["hpMax"] = int(s["hpMax"]) + maxi(1, die_avg + con)
		s["level"] = after
		s["hp"] = s["hpMax"]
		# Auto-grant class features for the new levels (choice UI comes later).
		var gained: Array[String] = []
		var feats_map: Dictionary = Rules.tables.get("class_features", {}).get(str(s.get("cls", "")), {})
		for l in range(before + 1, after + 1):
			for f in feats_map.get(str(l), []):
				gained.append(str(f))
		if not gained.is_empty():
			var have: Array = s.get("features", [])
			have.append_array(gained)
			s["features"] = have
		# Casters climb the slot table with their level.
		var preset: Dictionary = Rules.tables.get("class_presets", {}).get(str(s.get("cls", "")), {})
		if preset.get("caster", false):
			s["slots"] = Rules.full_caster_slots(after)
		note += "\n🎉 *LEVEL UP — you are now level %d! HP restored to %d.%s*" % [after, int(s["hpMax"]),
			(" New: " + ", ".join(gained)) if not gained.is_empty() else ""]
	set_sheet(s)
	if after > before:
		leveled_up.emit(before, after)
	return {"note": note, "leveled": after > before, "from": before, "to": after}


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


## An NPC joins the party (port of _toggleCompanion's recruit half).
func add_companion(nm: String, role := "") -> String:
	var s := sheet()
	var comps: Array = s.get("companions", [])
	for c in comps:
		if str(c.get("name", "")).nocasecmp_to(nm) == 0:
			return ""
	var level := int(s.get("level", 1))
	var hp_max := 10 + 2 * level
	comps.append({"name": nm, "role": role, "cls": "Fighter", "level": level,
		"ac": 13, "hpMax": hp_max, "hp": hp_max})
	s["companions"] = comps
	set_sheet(s)
	return "⚔ *%s joins your party — a level %d companion!*" % [nm, level]


# ── Class feature actions (port of FEATURE_ACTIONS) ─────────────────────────
## Feature name (matched by prefix against sheet.features) → per-rest uses.
const FEATURE_ACTIONS := {
	"Second Wind": {"rest": "short", "uses": 1},
	"Rage": {"rest": "long", "uses": 2},
	"Action Surge": {"rest": "short", "uses": 1},
	"Combat Maneuver": {"rest": "short", "uses": 4},
	"Arcane Ward": {"rest": "long", "uses": 1},
	"Cutting Words": {"rest": "long", "uses": 3},
}


## The action a sheet feature string maps to ("Rage (bonus damage…)") → "Rage".
func feature_action_key(feature: String) -> String:
	for k in FEATURE_ACTIONS:
		if feature.begins_with(k):
			return k
	return ""


func feature_uses_left(key: String) -> int:
	var meta: Dictionary = FEATURE_ACTIONS.get(key, {})
	if meta.is_empty():
		return 0
	return int(meta["uses"]) - int(sheet().get("featUses", {}).get(key, 0))


## Spend one use and apply the effect. → in-fiction note for the GM, "" if dry.
func use_feature(key: String) -> String:
	if feature_uses_left(key) <= 0:
		return ""
	var s := sheet()
	var used: Dictionary = s.get("featUses", {})
	used[key] = int(used.get(key, 0)) + 1
	s["featUses"] = used
	var note := ""
	match key:
		"Second Wind":
			var heal := randi_range(1, 10) + int(s.get("level", 1))
			s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + heal)
			note = "💨 *Second Wind — you steady yourself and recover **%d HP** (now %d/%d).*" % [heal, int(s["hp"]), int(s["hpMax"])]
		"Rage":
			s["conditions"] = s.get("conditions", []) + [{"name": "raging (+2 melee damage, resist physical)", "rounds": 10}]
			note = "😤 *You RAGE — advantage on Strength, resistance to physical damage, +2 melee damage while it lasts.*"
		"Action Surge":
			var c: Dictionary = Combat.data()
			if bool(c.get("active", false)) and c.get("_pcb") is Dictionary:
				c["_pcb"]["attacksLeft"] = int(c["_pcb"].get("attacksLeft", 0)) + int(c["_pcb"].get("attacksMax", 1))
				Combat.save(c)
			note = "⚡ *Action Surge — you push past your limits and act again this turn.*"
		"Combat Maneuver":
			note = "🎖 *Superiority die spent — trip, disarm, riposte, or feint for **+%d** to the effect. Tell the GM which maneuver.*" % randi_range(1, 8)
		"Arcane Ward":
			var ward := 2 * int(s.get("level", 1)) + maxi(0, Rules.ability_mod(int(s["abilities"].get("INT", 10))))
			s["conditions"] = s.get("conditions", []) + [{"name": "arcane ward (absorbs %d damage)" % ward, "rounds": 99}]
			note = "🛡 *A woven ward of abjuration surrounds you — it absorbs the next **%d** damage before your HP does.*" % ward
		"Cutting Words":
			note = "🎻 *Cutting Words — your mockery lands where armor doesn't: **−%d** from an enemy's attack, check, or damage roll.*" % randi_range(1, 8)
	set_sheet(s)
	return note


func _recharge_features(rest_kind: String) -> void:
	var s := sheet()
	var used: Dictionary = s.get("featUses", {})
	for k in FEATURE_ACTIONS:
		if rest_kind == "long" or str(FEATURE_ACTIONS[k]["rest"]) == "short":
			used.erase(k)
	s["featUses"] = used
	set_sheet(s)


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
	_recharge_features("short")
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
	_recharge_features("long")
	var c := clock()
	var steps := TIMES.size() if int(c.get("ti", 0)) == 0 else TIMES.size() - int(c.get("ti", 0))
	advance_time(steps)
	var note := ("⛺ *You make camp — but something finds you in the night. You wake half-rested at %d/%d HP.*" % [int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else ("⛺ *You make camp and sleep. You wake at dawn, fully restored — %d/%d HP.*" % [int(s["hpMax"]), int(s["hpMax"])])
	var gm := ("[My rest is interrupted in the night — run a short encounter fitting where I'm camped. I woke at %d/%d HP, only half-rested. Open on the moment I startle awake.]" % [int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else "[I take a long rest through the night and wake at dawn, fully healed. Narrate the new morning and what's changed, then continue.]"
	return {"note": note, "gm": gm}

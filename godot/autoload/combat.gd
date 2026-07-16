extends Node
## Combat — the deterministic fight engine, ported from characterStudio.js
## (_enterCombat/_playerAttack/_enemyTurn/_companionTurn/_finishCombat).
## Combatants live in the `combat` world-state kind:
##   {active, round, turn, combatants: [{id, name, hp, hpMax, ac, init, side, conditions}]}
## Every function returns player-visible/GM lines; the game screen streams them.

signal changed  # combat state mutated — panels re-render

var _incap_re := RegEx.create_from_string("(?i)stunned|paralyz|unconscious|incapacitat|frozen|petrif")


func data() -> Dictionary:
	return GameState._merged("combat", {"active": false, "round": 1, "turn": 0, "combatants": []})


func save(c: Dictionary) -> void:
	GameState.save_kind("combat", c)
	changed.emit()


func active() -> bool:
	return bool(data().get("active", false))


func order(c: Dictionary) -> Array:
	var arr: Array = c.get("combatants", []).duplicate()
	arr.sort_custom(func(a, b): return int(a.get("init", 0)) > int(b.get("init", 0)))
	return arr


func current(c: Dictionary) -> Dictionary:
	var ord := order(c)
	return ord[int(c.get("turn", 0)) % ord.size()] if not ord.is_empty() else {}


func enemy_hp_guess(nm: String) -> int:
	var n := nm.to_lower()
	var hp: int
	if RegEx.create_from_string("(?i)dragon|giant|troll|ogre|golem|demon|wyvern|hydra|behemoth|titan|bear|owlbear|minotaur|elemental").search(n):
		hp = 30 + randi() % 20
	elif RegEx.create_from_string("(?i)knight|warrior|guard|bandit|mercenary|cultist|orc|gnoll|hobgoblin|zombie|ghoul|wolf|boar|construct|enforcer|brute|soldier").search(n):
		hp = 14 + randi() % 12
	elif RegEx.create_from_string("(?i)goblin|kobold|rat|bat|spider|imp|sprite|thug|snake|slime|skeleton|servitor|drone|scavenger").search(n):
		hp = 6 + randi() % 7
	else:
		hp = 12 + randi() % 8
	# Foes keep pace with the hero: +20% per level past 1st.
	return roundi(hp * (1.0 + 0.2 * (int(GameState.sheet().get("level", 1)) - 1)))


func bestiary_for(nm: String) -> Dictionary:
	var n := nm.to_lower()
	for e in Rules.bestiary:
		if n.contains(str(e.get("slug", "")).replace("-", " ")) or n.contains(str(e.get("name", "")).to_lower()):
			return e
	return {}


func weapon_dmg_type(nm: String) -> String:
	var n := nm.to_lower()
	if RegEx.create_from_string("(?i)mace|club|hammer|maul|staff|quarterstaff|flail|fist|bare|cudgel|baton|wrench|pipe").search(n):
		return "bludgeoning"
	if RegEx.create_from_string("(?i)dagger|spear|pike|arrow|bow|crossbow|rapier|dart|lance|pick|needle|stiletto|bolt|bullet|gun|pistol|rifle").search(n):
		return "piercing"
	if RegEx.create_from_string("(?i)torch|flame|fire|brand").search(n):
		return "fire"
	return "slashing"


func weapon_props(nm: String) -> Dictionary:
	var n := nm.to_lower()
	var versatile := ""
	for pair in [["longsword", "1d10"], ["battleaxe", "1d10"], ["warhammer", "1d10"], ["quarterstaff", "1d8"], ["trident", "1d8"], ["spear", "1d8"], ["staff", "1d8"]]:
		if n.contains(pair[0]):
			versatile = pair[1]
			break
	return {
		"die": Rules.weapon_die(nm), "versatile": versatile,
		"ranged": RegEx.create_from_string("(?i)bow|crossbow|sling|dart|gun|pistol|rifle|blaster|thrown").search(n) != null,
		"finesse": RegEx.create_from_string("(?i)dagger|rapier|shortsword|whip|scimitar|blade|estoc").search(n) != null,
		"heavy": RegEx.create_from_string("(?i)greatsword|greataxe|maul|halberd|glaive|pike|claymore|heavy crossbow").search(n) != null,
	}


func _dice_expr(expr: String) -> Dictionary:
	var m := RegEx.create_from_string("(\\d+)d(\\d+)([+-]\\d+)?").search(expr)
	if m == null:
		return {"n": 1, "sides": 4, "mod": 0}
	return {"n": int(m.get_string(1)), "sides": int(m.get_string(2)),
		"mod": int(m.get_string(3)) if m.get_string(3) != "" else 0}


## Start a fight (or reinforce a running one). → player-visible line.
func enter(enemy: String) -> String:
	var c := data()
	if bool(c.get("active", false)):
		add_foe(enemy)
		return ""
	var s := GameState.sheet()
	var inv := GameState.inv()
	var pc := {"id": "pc", "name": str(s.get("name", "You")), "hp": int(s.get("hp", 10)),
		"hpMax": int(s.get("hpMax", 10)), "ac": Rules.eff_ac(s, inv),
		"init": randi_range(1, 20) + Rules.ability_mod(int(s["abilities"].get("DEX", 10))),
		"side": "ally", "conditions": []}
	var combatants: Array = [pc]
	var i := 0
	for cmp in s.get("companions", []):
		var chp := int(cmp.get("hp", cmp.get("hpMax", 1)))
		combatants.append({"id": "cmp%d" % i, "name": str(cmp.get("name", "Ally")), "hp": maxi(0, chp),
			"hpMax": int(cmp.get("hpMax", maxi(chp, 1))), "ac": int(cmp.get("ac", 12)),
			"init": randi_range(1, 20), "side": "ally", "conditions": []})
		i += 1
	var hp0 := enemy_hp_guess(enemy)
	combatants.append({"id": "e1_" + enemy.replace(" ", ""), "name": enemy, "hp": hp0, "hpMax": hp0,
		"ac": null, "init": randi_range(1, 20), "side": "enemy", "conditions": []})
	save({"active": true, "round": 1, "turn": 0, "combatants": combatants})
	return "⚔️ *Combat — %s!*" % enemy


func add_foe(enemy: String) -> void:
	var c := data()
	if enemy == "" or enemy == "Enemy":
		return
	for x in c["combatants"]:
		if x.get("side") == "enemy" and str(x.get("name", "")).nocasecmp_to(enemy) == 0:
			return
	var hp := enemy_hp_guess(enemy)
	c["combatants"].append({"id": "e%d_%s" % [c["combatants"].size(), enemy.replace(" ", "")],
		"name": enemy, "hp": hp, "hpMax": hp, "ac": null, "init": randi_range(1, 20),
		"side": "enemy", "conditions": []})
	save(c)


func _budget(c: Dictionary) -> Dictionary:
	var s := GameState.sheet()
	var attacks := 2 if s.get("features", []).any(func(f): return str(f).matchn("*extra attack*")) else 1
	if not (c.get("_pcb") is Dictionary) or int(c["_pcb"].get("round", -1)) != int(c["round"]):
		c["_pcb"] = {"round": int(c["round"]), "attacksLeft": attacks, "attacksMax": attacks}
	return c["_pcb"]


## The full ported attack: finesse/ranged ability pick, prof + weapon bonus,
## crits double dice, rage bonus, bestiary resist/vuln, victory detection.
## → {msg, fell, won, spent} — spent=false means the action budget was empty.
func player_attack(target_id: String) -> Dictionary:
	var c := data()
	var foe := {}
	for x in c["combatants"]:
		if str(x.get("id", "")) == target_id:
			foe = x
			break
	if foe.is_empty() or int(foe.get("hp", 0)) <= 0:
		return {"msg": "", "fell": false, "won": false, "spent": true}
	var b := _budget(c)
	if int(b.get("attacksLeft", 0)) <= 0:
		return {"msg": "⚔ *Your action is spent — end your turn.*", "fell": false, "won": false, "spent": false}
	b["attacksLeft"] = int(b["attacksLeft"]) - 1
	var s := GameState.sheet()
	var inv := GameState.inv()
	var wpn := GameState.item_by_id(str(inv.get("equipped", {}).get("weapon", "")))
	var wname := str(wpn.get("name", "bare fists")) if not wpn.is_empty() else "bare fists"
	var props := weapon_props(wname)
	var dex := Rules.ability_mod(int(s["abilities"].get("DEX", 10)))
	var strn := Rules.ability_mod(int(s["abilities"].get("STR", 10)))
	var abil_mod := dex if (props["ranged"] or (props["finesse"] and dex > strn)) else strn
	var mod: int = abil_mod + Rules.prof_bonus(s) + int(wpn.get("atk", 0))
	# Heavy weapons are unwieldy for Small heroes — swing at disadvantage.
	var small: bool = RegEx.create_from_string("(?i)halfling|gnome|goblin|kobold|imp|sprite|fairy|pixie").search(str(s.get("race", ""))) != null
	var roll := randi_range(1, 20)
	var dv_tag := ""
	if bool(props["heavy"]) and small:
		roll = mini(roll, randi_range(1, 20))
		dv_tag = " *(disadvantage — heavy weapon in small hands)*"
	var champion: bool = str(s.get("subclass", "")) == "Champion"
	var total := roll + mod
	var crit: bool = roll == 20 or (roll == 19 and champion)
	var fumble := roll == 1
	var target_ac := int(foe["ac"]) if foe.get("ac") != null else 12
	var vs_ac := (" vs AC %d" % int(foe["ac"])) if foe.get("ac") != null else ""
	if props["ranged"] and in_cover(target_id):
		target_ac += 2
		vs_ac += " (+2 cover)"
	if not crit and (fumble or total < target_ac):
		save(c)
		var miss := {"msg": "⚔ *You attack the %s with your %s — d20 %d %+d = **%d**%s%s%s → a miss.*" % [
			foe["name"], wname, roll, mod, total, vs_ac, dv_tag, " — a FUMBLE" if fumble else ""],
			"fell": false, "won": false, "spent": true}
		var off_miss := offhand_followup(target_id, b)
		if str(off_miss.get("msg", "")) != "":
			miss["msg"] = str(miss["msg"]) + "\n" + str(off_miss["msg"])
			miss["fell"] = off_miss["fell"]
			miss["won"] = off_miss["won"]
		return miss
	var de := _dice_expr(props["versatile"] if str(props["versatile"]) != "" else str(wpn.get("dmg", props["die"])))
	var dmg: int = int(de["mod"]) + maxi(0, abil_mod)
	for i in int(de["n"]) * (2 if crit else 1):
		dmg += randi_range(1, int(de["sides"]))
	if not props["ranged"] and s.get("conditions", []).any(func(cd): return str(cd.get("name", cd) if cd is Dictionary else cd).matchn("*raging*")):
		dmg += 2
	dmg = maxi(1, dmg)
	# Typed defenses are math, not lore.
	var entry := bestiary_for(str(foe["name"]))
	var dtype := weapon_dmg_type(wname)
	var res_tag := ""
	if entry.get("vuln", []).has(dtype):
		dmg *= 2
		res_tag = " — **vulnerable to %s!**" % dtype
	elif entry.get("resist", []).has(dtype):
		dmg = maxi(1, ceili(dmg / 2.0))
		res_tag = " *(resists %s)*" % dtype
	foe["hp"] = maxi(0, int(foe["hp"]) - dmg)
	var fell := int(foe["hp"]) <= 0
	var enemies: Array = c["combatants"].filter(func(x): return x.get("side") == "enemy")
	var won: bool = fell and not enemies.is_empty() and enemies.all(func(e): return int(e.get("hp", 0)) <= 0)
	save(c)
	var msg := "⚔ *You attack the %s with your %s — d20 %d %+d = **%d**%s%s%s → **%d damage**%s%s.*" % [
		foe["name"], wname, roll, mod, total, vs_ac, dv_tag,
		" — **CRITICAL HIT%s!**" % (" (Champion)" if roll == 19 else "") if crit else "",
		dmg, res_tag,
		(" — the %s falls!" % foe["name"]) if fell else " (%d/%d left)" % [int(foe["hp"]), int(foe["hpMax"])]]
	var result := {"msg": msg, "fell": fell, "won": won, "spent": true}
	if not fell:
		var off := offhand_followup(target_id, b)
		if str(off.get("msg", "")) != "":
			result["msg"] = str(result["msg"]) + "\n" + str(off["msg"])
			result["fell"] = off["fell"]
			result["won"] = off["won"]
	return result


## Two-weapon fighting: a light off-hand weapon grants a bonus strike — no
## positive ability mod to its damage (that's the trade). Once per round.
func offhand_followup(target_id: String, budget: Dictionary) -> Dictionary:
	var out := {"msg": "", "fell": false, "won": false}
	if bool(budget.get("bonusUsed", false)):
		return out
	var s := GameState.sheet()
	var inv := GameState.inv()
	var main := GameState.item_by_id(str(inv.get("equipped", {}).get("weapon", "")))
	var off := GameState.item_by_id(str(inv.get("equipped", {}).get("offhand", "")))
	if off.is_empty() or main.is_empty():
		return out
	var main_props := weapon_props(str(main.get("name", "")))
	var off_props := weapon_props(str(off.get("name", "")))
	var light_re := RegEx.create_from_string("(?i)dagger|shortsword|handaxe|hatchet|scimitar|club|sickle|knife")
	if light_re.search(str(main.get("name", ""))) == null or light_re.search(str(off.get("name", ""))) == null:
		return out
	budget["bonusUsed"] = true
	var c := data()
	save(c)
	var foe := {}
	for x in c["combatants"]:
		if str(x.get("id", "")) == target_id:
			foe = x
	if foe.is_empty() or int(foe.get("hp", 0)) <= 0:
		return out
	var dex := Rules.ability_mod(int(s["abilities"].get("DEX", 10)))
	var strn := Rules.ability_mod(int(s["abilities"].get("STR", 10)))
	var abil_mod: int = dex if (off_props["finesse"] and dex > strn) else strn
	var mod: int = abil_mod + Rules.prof_bonus(s)
	var roll := randi_range(1, 20)
	var total := roll + mod
	var target_ac := int(foe["ac"]) if foe.get("ac") != null else 12
	var crit := roll == 20
	if not crit and (roll == 1 or total < target_ac):
		out["msg"] = "🗡 *Off-hand %s — d20 %d %+d = %d → misses.*" % [str(off.get("name", "")), roll, mod, total]
		return out
	var de := _dice_expr(str(off.get("dmg", off_props["die"])))
	var dmg: int = int(de["mod"]) + mini(0, abil_mod)
	for i in int(de["n"]) * (2 if crit else 1):
		dmg += randi_range(1, int(de["sides"]))
	dmg = maxi(1, dmg)
	foe["hp"] = maxi(0, int(foe["hp"]) - dmg)
	var fell := int(foe["hp"]) <= 0
	var enemies: Array = c["combatants"].filter(func(x): return x.get("side") == "enemy")
	var won: bool = fell and enemies.all(func(e): return int(e.get("hp", 0)) <= 0)
	save(c)
	out["msg"] = "🗡 *Off-hand %s%s → **%d damage**%s.*" % [str(off.get("name", "")),
		" — **CRIT!**" if crit else "", dmg,
		(" — the %s falls!" % foe["name"]) if fell else " (%d/%d left)" % [int(foe["hp"]), int(foe["hpMax"])]]
	out["fell"] = fell
	out["won"] = won
	return out


## Reactions the hero can take against an incoming hit (port of
## _availableReactions): Shield needs the spell + a slot + the hit inside
## +5; Uncanny Dodge is a feature; Parry rides Combat Maneuver uses.
## Nudge a spawn seat off walls and occupied squares (reinforcements land
## after terrain bakes; original seating happens before it and stays put).
func _free_seat(cell: Array, pos: Dictionary) -> Array:
	for dy in MAP_ROWS:
		var cand := [int(cell[0]), (int(cell[1]) + dy) % MAP_ROWS]
		if terrain_at(cand) == "block":
			continue
		var taken := false
		for id in pos:
			if pos[id] is Array and int(pos[id][0]) == cand[0] and int(pos[id][1]) == cand[1]:
				taken = true
		if not taken:
			return cand
	return cell


## ✦ Cast a damaging spell at a foe: spell attack vs AC (Magic Missile darts
## strike unerringly), dice pulled from the spell's own description, typed
## defenses applied. Spends the whole action and the slot.
func player_spell(target_id: String, nm: String) -> Dictionary:
	var c := data()
	var foe := {}
	for x in c["combatants"]:
		if str(x.get("id", "")) == target_id:
			foe = x
			break
	if foe.is_empty() or int(foe.get("hp", 0)) <= 0:
		return {"msg": "", "fell": false, "won": false, "spent": true}
	var b := _budget(c)
	if int(b.get("attacksLeft", 0)) <= 0:
		return {"msg": "✦ *Your action is spent — end your turn.*", "fell": false, "won": false, "spent": false}
	var s := GameState.sheet()
	var desc := str(Rules.spell_named(nm).get("desc", ""))
	var cast := GameState.cast_spell(nm)
	if cast == "" or cast.begins_with("✋"):
		return {"msg": cast, "fell": false, "won": false, "spent": false}
	b["attacksLeft"] = 0  # casting is your whole action
	var atk := Rules.spell_attack(s)
	var target_ac := int(foe["ac"]) if foe.get("ac") != null else 12
	var cover_tag := ""
	if in_cover(target_id):
		target_ac += 2
		cover_tag = " (+2 cover)"
	var auto_hit := nm.nocasecmp_to("Magic Missile") == 0
	var roll := randi_range(1, 20)
	var total := roll + atk
	var crit := roll == 20
	if not auto_hit and (roll == 1 or (not crit and total < target_ac)):
		save(c)
		return {"msg": "✦ *You cast **%s** at the %s — d20 %d %+d = **%d** vs AC %d%s → the spell goes wide.*" % [
			nm, foe["name"], roll, atk, total, target_ac, cover_tag], "fell": false, "won": false, "spent": true}
	var de := _dice_expr(desc)
	var darts := 3 if auto_hit else 1
	var dmg := int(de["mod"]) * darts
	for i in int(de["n"]) * darts * (2 if crit and not auto_hit else 1):
		dmg += randi_range(1, int(de["sides"]))
	dmg = maxi(1, dmg)
	var dt := RegEx.create_from_string("(?i)fire|cold|lightning|thunder|acid|poison|necrotic|radiant|force|psychic").search(desc)
	var dtype := dt.get_string(0).to_lower() if dt else "force"
	var entry := bestiary_for(str(foe["name"]))
	var res_tag := ""
	if entry.get("vuln", []).has(dtype):
		dmg *= 2
		res_tag = " — **vulnerable to %s!**" % dtype
	elif entry.get("resist", []).has(dtype):
		dmg = maxi(1, ceili(dmg / 2.0))
		res_tag = " *(resists %s)*" % dtype
	foe["hp"] = maxi(0, int(foe["hp"]) - dmg)
	var fell := int(foe["hp"]) <= 0
	var enemies: Array = c["combatants"].filter(func(x): return x.get("side") == "enemy")
	var won: bool = fell and enemies.all(func(e): return int(e.get("hp", 0)) <= 0)
	save(c)
	return {"msg": "✦ *You cast **%s** at the %s — %s**%d %s damage**%s%s.*" % [
		nm, foe["name"],
		"the darts strike unerringly — " if auto_hit else ("d20 %d %+d = **%d** vs AC %d%s → " % [roll, atk, total, target_ac, cover_tag]),
		dmg, dtype, res_tag,
		(" — the %s falls!" % foe["name"]) if fell else " (%d/%d left)" % [int(foe["hp"]), int(foe["hpMax"])]],
		"fell": fell, "won": won, "spent": true}


func available_reactions(total: int, ac: int) -> Array:
	var s := GameState.sheet()
	var out: Array = []
	var knows_shield: bool = s.get("spells", []).any(func(sp): return str(sp.get("name", "")).nocasecmp_to("Shield") == 0)
	var has_slot := false
	for l in s.get("slots", {}).values():
		if l is Dictionary and int(l.get("used", 0)) < int(l.get("max", 0)):
			has_slot = true
	if knows_shield and has_slot and total < ac + 5:
		out.append("shield")
	if s.get("features", []).any(func(f): return str(f).matchn("*uncanny dodge*")):
		out.append("dodge")
	var has_maneuver: bool = s.get("features", []).any(func(f): return str(f).begins_with("Combat Maneuver"))
	if has_maneuver and GameState.feature_uses_left("Combat Maneuver") > 0:
		out.append("parry")
	return out


## One enemy acts against the hero. On a hit with reactions available the
## blow PENDS: → {pending: {enemy,dmg,crit,total,ac}, reactions:[…]} and
## nothing is applied until resolve_enemy_hit. Otherwise → {msg, gm, down}.
func enemy_turn(enemy: Dictionary) -> Dictionary:
	if enemy.get("conditions", []).any(func(cd): return _incap_re.search(str(cd.get("name", cd) if cd is Dictionary else cd)) != null):
		return {"msg": "😵 *The %s can't act.*" % enemy["name"], "gm": "", "down": false}
	var s := GameState.sheet()
	var ac := Rules.eff_ac(s, GameState.inv())
	var atk_bonus := mini(9, 3 + int(enemy.get("hpMax", 10)) / 15)
	var roll := randi_range(1, 20)
	var total := roll + atk_bonus
	var crit := roll == 20
	if not crit and (roll == 1 or total < ac):
		return {"msg": "🗡 *The %s strikes at you — d20 %d +%d = %d vs AC %d → misses.*" % [enemy["name"], roll, atk_bonus, total, ac],
			"gm": "[The %s attacked me and missed (%d vs my AC %d). Narrate the near-miss briefly.]" % [enemy["name"], total, ac], "down": false}
	var dmg := int(enemy.get("hpMax", 10)) / 18
	for i in (2 if crit else 1):
		dmg += randi_range(1, 6)
	dmg = maxi(1, dmg)
	var reactions := available_reactions(total, ac)
	if not reactions.is_empty():
		return {"pending": {"enemy": enemy, "dmg": dmg, "crit": crit, "total": total, "ac": ac},
			"reactions": reactions, "msg": "", "gm": "", "down": false}
	return resolve_enemy_hit(enemy, dmg, crit, "")


## Apply a landed enemy hit (possibly softened by a reaction). → {msg, gm, down}
func resolve_enemy_hit(enemy: Dictionary, dmg: int, crit: bool, note: String) -> Dictionary:
	dmg = maxi(0, dmg)
	if dmg <= 0:
		return {"msg": "🛡 *%s — no damage gets through.*" % (note if note != "" else "You turn the blow aside"),
			"gm": "[The %s's blow was turned aside — no damage. Narrate it briefly.]" % enemy["name"], "down": false}
	var after := GameState.apply_hp(-dmg)
	var down := int(after["hp"]) <= 0
	var c := data()
	for x in c["combatants"]:
		if str(x.get("id", "")) == "pc":
			x["hp"] = int(after["hp"])
	save(c)
	return {"msg": "🗡 *The %s hits you%s%s for **%d damage** (%d/%d left).%s*" % [enemy["name"],
			" — **CRIT!**" if crit else "", (" — " + note) if note != "" else "", dmg,
			int(after["hp"]), int(after["hpMax"]),
			" — **you go down!**" if down else ""],
		"gm": "[The %s hit me for %d (%d/%d HP).%s Narrate the blow briefly.]" % [enemy["name"], dmg,
			int(after["hp"]), int(after["hpMax"]), " I am down and must roll death saves." if down else ""],
		"down": down}


## A companion strikes a random living foe. → {msg}
func companion_turn(ally: Dictionary) -> Dictionary:
	var c := data()
	var foes: Array = c["combatants"].filter(func(x): return x.get("side") == "enemy" and int(x.get("hp", 0)) > 0)
	if foes.is_empty() or int(ally.get("hp", 0)) <= 0:
		return {"msg": ""}
	var foe: Dictionary = foes[randi() % foes.size()]
	var atk := 2 + int(ally.get("hpMax", 10)) / 12
	var roll := randi_range(1, 20)
	var total := roll + atk
	var target_ac := int(foe["ac"]) if foe.get("ac") != null else 12
	if roll != 20 and (roll == 1 or total < target_ac):
		return {"msg": "🛡 *%s strikes at the %s — %d → a miss.*" % [ally["name"], foe["name"], total]}
	var dmg := maxi(1, randi_range(1, 6) + int(ally.get("hpMax", 10)) / 15)
	foe["hp"] = maxi(0, int(foe["hp"]) - dmg)
	save(c)
	return {"msg": "🛡 *%s hits the %s for **%d** (%d/%d left)%s.*" % [ally["name"], foe["name"], dmg,
		int(foe["hp"]), int(foe["hpMax"]), " — it falls!" if int(foe["hp"]) <= 0 else ""]}


## Death saves at 0 HP (port of _rollDeathSave): 10+ succeeds, nat 20 revives
## at 1 HP, nat 1 counts double; 3 successes stabilize, 3 failures kill.
## → {msg, dead, stable, revived} or {} when no save is due.
func death_save() -> Dictionary:
	var c := data()
	var pc := {}
	for x in c["combatants"]:
		if str(x.get("id", "")) == "pc":
			pc = x
			break
	if pc.is_empty():
		return {}
	if not (pc.get("ds") is Dictionary):
		pc["ds"] = {"s": 0, "f": 0}
	var ds: Dictionary = pc["ds"]
	if bool(ds.get("stable", false)) or bool(ds.get("dead", false)):
		return {}
	var roll := randi_range(1, 20)
	var msg: String
	if roll == 20:
		pc["hp"] = 1
		pc["ds"] = {"s": 0, "f": 0}
		GameState.apply_hp(1)
		msg = "🎲 *death save → natural 20! You gasp back to life at 1 HP.*"
	elif roll == 1:
		ds["f"] = int(ds["f"]) + 2
		msg = "🎲 *death save → natural 1 — two failures (%d/3).*" % mini(3, int(ds["f"]))
	elif roll >= 10:
		ds["s"] = int(ds["s"]) + 1
		msg = "🎲 *death save → %d, a success (%d/3).*" % [roll, mini(3, int(ds["s"]))]
	else:
		ds["f"] = int(ds["f"]) + 1
		msg = "🎲 *death save → %d, a failure (%d/3).*" % [roll, mini(3, int(ds["f"]))]
	if int(ds.get("s", 0)) >= 3:
		ds["stable"] = true
		msg += " **You stabilize**, clinging to life."
	if int(ds.get("f", 0)) >= 3:
		ds["dead"] = true
		msg += " **You have fallen.**"
	save(c)
	return {"msg": msg, "dead": bool(ds.get("dead", false)),
		"stable": bool(ds.get("stable", false)), "revived": roll == 20}


## The hero needs a death save this beat?
func pc_down() -> Dictionary:
	var c := data()
	if not bool(c.get("active", false)):
		return {}
	for x in c["combatants"]:
		if str(x.get("id", "")) == "pc" and int(x.get("hp", 1)) <= 0:
			var ds: Dictionary = x.get("ds", {})
			if not bool(ds.get("stable", false)) and not bool(ds.get("dead", false)):
				return x
	return {}


# ── The battle grid (bmap kind): positions matter — 5 ft per cell ───────────
const MAP_COLS := 16
const MAP_ROWS := 10
const FEET_PER_CELL := 5


# ── Terrain: the battle map's paint made mechanical ─────────────────────────
## Cell kinds sampled from the generated map painting: "block" (buildings and
## walls — impassable), "water" (difficult — double move cost), "cover"
## (trees/foliage — +2 AC against ranged attacks and spells).
## ponytail: color-heuristic sampling with a flood guard; upgrade path is an
## LLM-authored terrain layout commissioned alongside the map.

func terrain() -> Dictionary:
	return data().get("terrain", {})


func terrain_at(cell: Array) -> String:
	return str(terrain().get("%d,%d" % [int(cell[0]), int(cell[1])], ""))


## Sample the battle-map painting into the terrain grid. Bakes once per fight;
## cells someone already stands on stay passable.
func bake_terrain(img: Image) -> void:
	var c := data()
	if not bool(c.get("active", false)) or c.has("terrain") or img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / float(MAP_COLS)
	var ch := img.get_height() / float(MAP_ROWS)
	var t := {}
	var counts := {"block": 0, "water": 0, "cover": 0}
	for x in MAP_COLS:
		for y in MAP_ROWS:
			var avg := Color(0, 0, 0)
			for i in 9:  # 3×3 sample points per cell
				avg += img.get_pixelv(Vector2i(
					mini(img.get_width() - 1, int((x + 0.25 + 0.25 * (i % 3)) * cw)),
					mini(img.get_height() - 1, int((y + 0.25 + 0.25 * int(i / 3.0)) * ch))))
			avg /= 9.0
			var luma := avg.get_luminance()
			var kind := ""
			if avg.b > avg.r * 1.12 and avg.b > avg.g * 1.04 and avg.s > 0.1:
				kind = "water"
			elif avg.g > avg.r * 1.06 and avg.g > avg.b * 1.15 and luma < 0.42:
				kind = "cover"
			elif avg.s < 0.14 and luma > 0.2 and luma < 0.78:
				kind = "block"
			if kind != "":
				t["%d,%d" % [x, y]] = kind
				counts[kind] += 1
	# Flood guard: a kind claiming near half the board is the sampler lying.
	for kind in counts:
		if counts[kind] > int(MAP_COLS * MAP_ROWS * 0.45):
			for k in t.keys():
				if t[k] == kind:
					t.erase(k)
	# Occupied squares stay passable — nobody spawns inside a wall.
	for p in positions().values():
		t.erase("%d,%d" % [int(p[0]), int(p[1])])
	c["terrain"] = t
	save(c)


## True when the combatant stands in or beside foliage — ranged shots suffer.
func in_cover(id: String) -> bool:
	var cl := cell_of(id)
	for d in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]:
		if terrain_at([int(cl[0]) + d[0], int(cl[1]) + d[1]]) == "cover":
			return true
	return false


func positions() -> Dictionary:
	return GameState._merged("bmap", {"pos": {}}).get("pos", {})


func save_positions(pos: Dictionary) -> void:
	GameState.save_kind("bmap", {"pos": pos})
	changed.emit()


## Seat everyone who lacks a square: allies file in on the left, foes right.
## Saves ONLY when seating changed — save emits `changed`, and an
## unconditional save here recursed through every render. (RCA'd live.)
func ensure_positions() -> Dictionary:
	var pos := positions()
	var c := data()
	var dirty := false
	var ally_row := 0
	var foe_row := 0
	for m in order(c):
		var id := str(m.get("id", ""))
		if pos.has(id):
			continue
		if m.get("side") == "ally":
			pos[id] = _free_seat([2, 2 + (ally_row * 2) % (MAP_ROWS - 3)], pos)
			ally_row += 1
		else:
			pos[id] = _free_seat([MAP_COLS - 3, 2 + (foe_row * 2) % (MAP_ROWS - 3)], pos)
			foe_row += 1
		dirty = true
	# Sweep the seats of the fallen-and-removed.
	for id in pos.keys():
		if not c["combatants"].any(func(x): return str(x.get("id", "")) == str(id)):
			pos.erase(id)
			dirty = true
	if dirty:
		save_positions(pos)
	return pos


func cell_of(id: String) -> Array:
	return positions().get(id, [0, 0])


## Chebyshev distance in cells (diagonals count 1, like the original board).
func distance(a: Array, b: Array) -> int:
	return maxi(absi(int(a[0]) - int(b[0])), absi(int(a[1]) - int(b[1])))


func adjacent(id_a: String, id_b: String) -> bool:
	return distance(cell_of(id_a), cell_of(id_b)) <= 1


## Hero speed in cells per round (heritage speed, 30 ft default).
func pc_move_cells() -> int:
	var race := str(GameState.sheet().get("race", ""))
	var speed := int(Rules.tables.get("heritages", {}).get(race, {}).get("speed", 30))
	return maxi(1, speed / FEET_PER_CELL)


func move_budget(c: Dictionary) -> Dictionary:
	if not (c.get("_move") is Dictionary) or int(c["_move"].get("round", -1)) != int(c["round"]):
		c["_move"] = {"round": int(c["round"]), "left": pc_move_cells()}
	return c["_move"]


## Move the hero if the cell is free and within budget. → true on success.
func move_pc(to: Array) -> bool:
	var c := data()
	var pos := positions()
	if int(to[0]) < 0 or int(to[0]) >= MAP_COLS or int(to[1]) < 0 or int(to[1]) >= MAP_ROWS:
		return false
	for id in pos:
		if int(pos[id][0]) == int(to[0]) and int(pos[id][1]) == int(to[1]):
			return false
	if terrain_at(to) == "block":
		return false
	var budget := move_budget(c)
	var cost := distance(cell_of("pc"), to)
	if terrain_at(to) == "water":
		cost *= 2  # ponytail: destination-based difficult terrain; per-step path costs later
	if cost > int(budget["left"]):
		return false
	budget["left"] = int(budget["left"]) - cost
	save(c)
	pos["pc"] = [int(to[0]), int(to[1])]
	save_positions(pos)
	return true


## An enemy closes toward the hero (up to its move). → cells actually moved.
func enemy_approach(enemy_id: String, cells := 6) -> int:
	var pos := positions()
	if not pos.has(enemy_id) or not pos.has("pc"):
		return 0
	var e: Array = pos[enemy_id]
	var p: Array = pos["pc"]
	var moved := 0
	while moved < cells and distance(e, p) > 1:
		var dx := signi(int(p[0]) - int(e[0]))
		var dy := signi(int(p[1]) - int(e[1]))
		var stepped := false
		# Prefer the diagonal; sidestep along one axis around walls and bodies.
		for step in [[int(e[0]) + dx, int(e[1]) + dy], [int(e[0]) + dx, int(e[1])], [int(e[0]), int(e[1]) + dy]]:
			if (step[0] == int(e[0]) and step[1] == int(e[1])) or terrain_at(step) == "block":
				continue
			var taken := false
			for id in pos:
				if str(id) != enemy_id and int(pos[id][0]) == step[0] and int(pos[id][1]) == step[1]:
					taken = true
			if taken:
				continue
			e = step
			moved += 1
			stepped = true
			break
		if not stepped:
			break
	pos[enemy_id] = e
	save_positions(pos)
	return moved


func next_turn() -> void:
	var c := data()
	var n := order(c).size()
	if n == 0:
		return
	c["turn"] = (int(c.get("turn", 0)) + 1) % n
	if int(c["turn"]) == 0:
		c["round"] = int(c.get("round", 1)) + 1
	save(c)


## End the fight: XP for the slain, companion wounds persist. → {note, xp}
func finish() -> Dictionary:
	var c := data()
	var slain: Array = c.get("combatants", []).filter(func(m): return m.get("side") == "enemy" and int(m.get("hp", 1)) <= 0)
	var xp := 0
	for m in slain:
		xp += maxi(25, int(m.get("hpMax", 10)) * 2)
	# Companion wounds carry between fights (synced back to the sheet).
	var s := GameState.sheet()
	var comps: Array = s.get("companions", [])
	for m in c.get("combatants", []):
		if str(m.get("id", "")).begins_with("cmp"):
			for cmp in comps:
				if str(cmp.get("name", "")) == str(m.get("name", "")):
					cmp["hp"] = int(m.get("hp", 0))
	if not comps.is_empty():
		s["companions"] = comps
		GameState.set_sheet(s)
	save({"active": false, "round": 1, "turn": 0, "combatants": []})
	save_positions({})  # the board clears with the field
	var note := ""
	if xp > 0:
		note = str(GameState.award_xp(xp, "%d foe%s defeated" % [slain.size(), "" if slain.size() == 1 else "s"])["note"])
	return {"note": note, "xp": xp}

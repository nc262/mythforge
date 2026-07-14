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
	var roll := randi_range(1, 20)
	var champion: bool = str(s.get("subclass", "")) == "Champion"
	var total := roll + mod
	var crit: bool = roll == 20 or (roll == 19 and champion)
	var fumble := roll == 1
	var target_ac := int(foe["ac"]) if foe.get("ac") != null else 12
	var vs_ac := (" vs AC %d" % int(foe["ac"])) if foe.get("ac") != null else ""
	if not crit and (fumble or total < target_ac):
		save(c)
		return {"msg": "⚔ *You attack the %s with your %s — d20 %d %+d = **%d**%s%s → a miss.*" % [
			foe["name"], wname, roll, mod, total, vs_ac, " — a FUMBLE" if fumble else ""],
			"fell": false, "won": false, "spent": true}
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
	var msg := "⚔ *You attack the %s with your %s — d20 %d %+d = **%d**%s%s → **%d damage**%s%s.*" % [
		foe["name"], wname, roll, mod, total, vs_ac,
		" — **CRITICAL HIT%s!**" % (" (Champion)" if roll == 19 else "") if crit else "",
		dmg, res_tag,
		(" — the %s falls!" % foe["name"]) if fell else " (%d/%d left)" % [int(foe["hp"]), int(foe["hpMax"])]]
	return {"msg": msg, "fell": fell, "won": won, "spent": true}


## One enemy acts against the hero. → {msg, gm, down}
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
	var after := GameState.apply_hp(-dmg)
	var down := int(after["hp"]) <= 0
	var c := data()
	for x in c["combatants"]:
		if str(x.get("id", "")) == "pc":
			x["hp"] = int(after["hp"])
	save(c)
	return {"msg": "🗡 *The %s hits you%s for **%d damage** (%d/%d left).%s*" % [enemy["name"],
			" — **CRIT!**" if crit else "", dmg, int(after["hp"]), int(after["hpMax"]),
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
	var note := ""
	if xp > 0:
		note = str(GameState.award_xp(xp, "%d foe%s defeated" % [slain.size(), "" if slain.size() == 1 else "s"])["note"])
	return {"note": note, "xp": xp}

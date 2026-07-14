extends Node
## Composer — the per-turn context envelope prepended to every player message.
## The persona's stored system prompt (composed by the web studio) still
## carries the world + GM voice; this adds live state + the tag protocol.

const PROTOCOL := """[MECHANICS PROTOCOL — the game engine, not you, resolves all mechanics.
When the player attempts something with an uncertain outcome, call for a roll by ending your reply with one tag on its own final line:
[[check ability=DEX skill=Stealth dc=13]]  (ability: STR/DEX/CON/INT/WIS/CHA; skill optional, or skill=save for saving throws; add adv=1 or dis=1 when circumstances grant it)
[[attack ac=14]] when the player swings at a foe.
[[damage roll=2d6+3]] when the player takes damage. [[heal roll=1d8+2]] when they receive healing.
[[gold delta=+15]] or [[gold delta=-10]] when the player gains or spends money.
[[loot name="Iron Dagger" rarity=common]] when the player picks up or is given an item (rarity: common/uncommon/rare/epic/legendary).
[[spell-learned name="Misty Step"]] when the player learns a spell. [[time advance=1]] when notable in-world time passes.
Never write dice results, totals, remaining HP, or the success/failure of a player's roll in prose — the game rolls and reports the result in the player's next message. Use one tag per mechanical effect, each on its own line.]"""


func envelope(player_msg: String) -> String:
	var parts: Array[String] = []
	var summary := sheet_summary(GameState.sheet())
	if summary != "":
		parts.append("[THE PLAYER'S SHEET (live, engine-owned): %s]" % summary)
	parts.append("[%s]" % GameState.clock_text())
	for extra in [GameState.inv_text(), GameState.spell_text()]:
		if str(extra) != "":
			parts.append("[%s]" % extra)
	parts.append(PROTOCOL)
	parts.append(player_msg)
	return "\n".join(parts)


func sheet_summary(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var abilities: Dictionary = s.get("abilities", {})
	var ab_parts: Array[String] = []
	for k in Rules.ABILITIES:
		var v := int(abilities.get(k, 10))
		ab_parts.append("%s %d (%+d)" % [k, v, Rules.ability_mod(v)])
	var conds: Array = s.get("conditions", [])
	var cond_names: Array[String] = []
	for c in conds:
		cond_names.append(str(c.get("name", c)) if c is Dictionary else str(c))
	return ("%s, level %d %s. HP %d/%d, AC %d, passive Perception %d. Purse: %d gold. Abilities: %s. Conditions: %s." % [
		str(s.get("name", "the hero")), int(s.get("level", 1)), str(s.get("cls", "Adventurer")),
		int(s.get("hp", 10)), int(s.get("hpMax", 10)), int(s.get("ac", 10)),
		Rules.passive_perception(s), int(s.get("gold", 0)),
		", ".join(ab_parts),
		", ".join(cond_names) if not cond_names.is_empty() else "none",
	])

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
[[xp delta=50 reason="outwitted the toll-keeper"]] when the player earns experience (25-75 for a scene; combat XP is automatic — never tag xp for kills).
[[combat-start foes="goblin x3, goblin boss"]] the moment a fight breaks out — name every foe. [[combat-end]] only when foes flee or surrender (victory ends it automatically).
During combat the game resolves ALL attacks, damage, and HP — narrate around the numbers the player reports, never invent your own.
Never write dice results, totals, remaining HP, or the success/failure of a player's roll in prose — the game rolls and reports the result in the player's next message. Use one tag per mechanical effect, each on its own line.]"""


func envelope(player_msg: String, beats: Array = []) -> String:
	var parts: Array[String] = []
	var summary := sheet_summary(GameState.sheet())
	if summary != "":
		parts.append("[THE PLAYER'S SHEET (live, engine-owned): %s]" % summary)
	parts.append("[%s]" % GameState.clock_text())
	for extra in [GameState.inv_text(), GameState.spell_text(),
			Chronicle.recall_text(beats), Chronicle.codex_text(), Chronicle.quests_text()]:
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
	var dc := Rules.spell_save_dc(s)
	return ("%s, level %d %s. HP %d/%d, AC %d, passive Perception %d. Purse: %d gold. Abilities: %s. Conditions: %s.%s" % [
		str(s.get("name", "the hero")), int(s.get("level", 1)), str(s.get("cls", "Adventurer")),
		int(s.get("hp", 10)), int(s.get("hpMax", 10)), Rules.eff_ac(s, GameState.inv()),
		Rules.passive_perception(s), int(s.get("gold", 0)),
		", ".join(ab_parts),
		", ".join(cond_names) if not cond_names.is_empty() else "none",
		(" Spell save DC %d, spell attack +%d (enemies roll saves against this; use these numbers)." % [dc, Rules.spell_attack(s)]) if dc > 0 else "",
	])

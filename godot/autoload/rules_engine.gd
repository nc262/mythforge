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
var class_lore: Dictionary = {}


func _ready() -> void:
	tables = _load_json("res://data/tables.json")
	spells = _load_json("res://data/spells.json").get("spells", [])
	bestiary = _load_json("res://data/bestiary.json").get("entries", [])
	worlds_json = _load_json("res://data/worlds.json")
	class_lore = _load_json("res://data/class_lore.json")


func builtin_worlds() -> Array:
	return worlds_json.get("worlds", [])


func world_stories(wid: String) -> Array:
	return worlds_json.get("stories", {}).get(wid, [])


func world_locations(wid: String) -> Array:
	return worlds_json.get("locations", {}).get(wid, [])


## The save-slot id for one tale in one world. Every caller used to read
## `story.slug` with "freeroam" as the fallback — but the built-in stories in
## worlds.json carry a title and NO slug, so every tale in a world collapsed
## onto "dm-<world>-freeroam": one save, one GM session and one chronicle
## shared by all of them, and picking a different tale changed nothing. Fall
## back to the title before surrendering to "freeroam" (which now means only
## Free Roam itself).
func adventure_id(world_id: String, story: Dictionary) -> String:
	var slug := str(story.get("slug", "")).strip_edges()
	if slug == "":
		slug = str(story.get("title", "")).to_lower().replace(" ", "-").validate_filename()
	if slug == "":
		slug = "freeroam"
	return "dm-%s-%s" % [world_id.validate_filename(), slug]


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


## ── Heritage size and body ────────────────────────────────────────────────
##
## SIZE is a rules category; BODY is a render profile. Keeping them apart is the
## point, and the Dwarf is why: mechanically **Medium** in 5e, but visibly short
## and broad. Conflate them and you get either a Dwarf that plays as Small
## (wrong rules) or one drawn at Human height (wrong look).

## Fallback for anything with no heritage entry — monsters, homebrew, reskins.
## This pattern used to be the ONLY test, inline in combat.gd, which meant a
## world that renamed Halfling silently made them Medium and lost the
## heavy-weapon rule. Data wins now; this only catches what the table has never
## heard of.
## HOW SAFE IS IT TO SLEEP HERE?
##
## CN-3 — two long rests inside an opened barrow, a hostile figure watching, and
## nothing happened either night: the interrupt was a flat 1-in-4 wherever you
## lay down, so a tavern bed and a monster's tomb carried identical risk. Where
## you sleep is the single most obvious thing a rest should care about.
##
## Keyed on the location `kind` the worlds already carry. Unknown or unnamed is
## treated as the wilds, because "I don't know where I am" is not a safe bed.
const REST_RISK := {
	"tavern": 0.05, "home": 0.05, "settlement": 0.08, "shop": 0.10,
	"landmark": 0.25, "ruin": 0.45, "wilds": 0.40,
}
const REST_RISK_UNKNOWN := 0.35


## The chance a long rest is interrupted in this place, and the reason, so the GM
## can run an encounter that fits the ground rather than a generic ambush.
func rest_risk(world_id_: String, here: String) -> Dictionary:
	if here == "":
		return {"risk": REST_RISK_UNKNOWN, "kind": "", "shelter": "in the open, with no roof you trust"}
	for l in world_locations(world_id_):
		if l is Dictionary and str(l.get("name", "")) == here:
			var k := str(l.get("kind", ""))
			if REST_RISK.has(k):
				return {"risk": float(REST_RISK[k]), "kind": k, "shelter": _shelter_word(k)}
			break
	return {"risk": REST_RISK_UNKNOWN, "kind": "", "shelter": "somewhere you do not know well"}


func _shelter_word(kind: String) -> String:
	match kind:
		"tavern": return "under a roof, among people"
		"home": return "somewhere you are welcome"
		"settlement": return "inside a settlement's walls"
		"shop": return "on someone else's floor"
		"landmark": return "at a place others also know how to find"
		"ruin": return "inside a ruin that something else may still consider home"
		"wilds": return "in the open wilds"
	return "somewhere you do not know well"


const SMALL_NAME_HINT := "(?i)halfling|gnome|goblin|kobold|imp|sprite|fairy|pixie|homunculus"

const DEFAULT_BODY := {"height": 1.0, "girth": 1.0, "head": 1.0, "leg": 1.0, "arm": 1.0}


func heritage(race: String) -> Dictionary:
	var h = tables.get("heritages", {}).get(race, {})
	return h if h is Dictionary else {}


## "small" | "medium". Anything larger belongs to the bestiary, not a heritage.
func heritage_size(race: String) -> String:
	var sz := str(heritage(race).get("size", ""))
	if sz != "":
		return sz
	return "small" if RegEx.create_from_string(SMALL_NAME_HINT).search(race) != null else "medium"


func is_small(race: String) -> bool:
	return heritage_size(race) == "small"


## Bone-scale multipliers for the ONE shared skeleton. Race and sex are data
## here, never separate geometry — equipment is skinned to the same bones, so it
## follows the scaling for free. That is why nine heritages times two sexes does
## not mean eighteen armour sets.
func body_profile(race: String, sex := "") -> Dictionary:
	var out := DEFAULT_BODY.duplicate()
	var b = heritage(race).get("body", {})
	if b is Dictionary:
		for k in out:
			out[k] = float(b.get(k, out[k]))
	var sx = tables.get("body_sexes", {}).get(sex, {})
	if sx is Dictionary and not sx.is_empty():
		# Sex modifies the heritage profile rather than replacing it — a female
		# dwarf is still short and broad.
		out["height"] *= float(sx.get("height", 1.0))
		out["girth"] *= float(sx.get("girth", 1.0))
		out["shoulder"] = float(sx.get("shoulder", 1.0))
		out["hip"] = float(sx.get("hip", 1.0))
	return out


## Which authored body an armour piece is fitted against. Equipment multiplies by
## TIER, not by race — see godot/docs/CharacterRender.md.
func body_tier(race: String) -> String:
	return str(heritage(race).get("tier", "regular"))


## Extra meshes parented to a bone (ears, horns, tail, snout). These do not
## affect armour fitting — the one real exception is helm versus horns.
func heritage_features(race: String) -> Array:
	var f = heritage(race).get("features", [])
	return f if f is Array else []


## Every worn slot the paper doll knows (key, label). Rings are two slots.
const EQUIP_SLOTS := [
	["head", "Head"], ["neck", "Neck"], ["cloak", "Cloak"], ["armor", "Chest"],
	["hands", "Hands"], ["waist", "Waist"], ["legs", "Legs"], ["feet", "Feet"],
	["ring1", "Ring"], ["ring2", "Ring"], ["weapon", "Main Hand"],
	["offhand", "Off Hand"], ["shield", "Shield"],
]
## Item type → the slot key(s) it can occupy.
const TYPE_SLOTS := {
	"weapon": ["weapon", "offhand"], "offhand": ["offhand"], "shield": ["shield"],
	"armor": ["armor"], "head": ["head"], "neck": ["neck"], "cloak": ["cloak"],
	"hands": ["hands"], "waist": ["waist"], "legs": ["legs"], "feet": ["feet"],
	"ring": ["ring1", "ring2"],
}
const WEARABLE := ["weapon", "armor", "shield", "head", "neck", "cloak", "hands", "waist", "legs", "feet", "ring"]


func item_type(nm: String) -> String:
	if _shield_re.search(nm):
		return "shield"
	if _weapon_re.search(nm):
		return "weapon"
	var n := nm.to_lower()
	# Worn gear beyond armour — checked before the generic armour test so
	# "leather boots" is feet, not chest (the paper doll's many slots, Issue 5).
	for pat in [["head", "helmet|helm\\b|\\bcap\\b|\\bhat\\b|hood|crown|circlet|coif|\\bmask\\b|visor"],
			["neck", "amulet|necklace|pendant|torc|medallion|locket|\\bcollar"],
			["ring", "\\bring\\b|signet"],
			["hands", "glove|gauntlet|bracer|vambrace|\\bmitt"],
			["waist", "\\bbelt\\b|\\bsash\\b|girdle"],
			["feet", "boot|sabaton|\\bshoe|sandal|\\bgreave"],
			["legs", "pants|trouser|legging|breeches|\\bkilt\\b|chausses|\\bskirt"],
			["cloak", "cloak|cape|mantle|\\brobe\\b|shawl"]]:
		if RegEx.create_from_string("(?i)" + str(pat[1])).search(n):
			return str(pat[0])
	if _armor_re.search(nm):
		return "armor"
	return "gear"


## The keeper's stock for the ACTIVE world's family — a cyber corner sells
## stim-patches, not daggers. Families without their own table (steam, pirate,
## norse, horror) fit the fantasy base well enough and fall back to it.
func vendor_stock() -> Dictionary:
	return vendor_stock_for(WorldSkin.family_for_id(GameState.world_id()))


## Same table by family, for the compiler — it bakes the shelves before there is
## an active world to ask about (Performance §7 A1).
func vendor_stock_for(fam: String) -> Dictionary:
	return tables.get("vendor_stock_" + fam, tables.get("vendor_stock", {}))


## Every ware name a keeper of this family can stock, flattened. Constant per
## family, so it is build-time work, never play-time work.
func vendor_stock_names(fam: String) -> Array:
	var out: Array = []
	for cat in vendor_stock_for(fam).values():
		if cat is Array:
			for gd in cat:
				if gd is Array and gd.size() >= 1 and not out.has(str(gd[0])):
					out.append(str(gd[0]))
	return out


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
	elif it["type"] in ["head", "neck", "cloak", "hands", "waist", "legs", "feet", "ring"]:
		# Worn accessories are cosmetic until they're magical — keeps AC sane.
		it["acBonus"] = {"epic": 1, "legendary": 2}.get(rarity, 0)
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
		# Unarmored defense follows ANY class on the sheet (multiclass-aware).
		var names: Array = sheet_classes(s).map(func(c): return str(c.get("cls", "")))
		if "Barbarian" in names:
			ac += maxi(0, ability_mod(int(s["abilities"].get("CON", 10))))
		elif "Monk" in names:
			ac += maxi(0, ability_mod(int(s["abilities"].get("WIS", 10))))
	for key in equipped:
		var it = find.call(equipped[key])
		if it != null:
			ac += int(it.get("acBonus", 0))
	return ac


# ── Casting / XP ─────────────────────────────────────────────────────────────
const CAST_ABIL := {"Wizard": "INT", "Cleric": "WIS", "Druid": "WIS", "Bard": "CHA",
	"Sorcerer": "CHA", "Warlock": "CHA", "Paladin": "CHA", "Ranger": "WIS", "Artificer": "INT"}


# ── Multiclass ───────────────────────────────────────────────────────────────
## A sheet's classes as [{cls, level, subclass}]. Legacy single-class sheets
## derive one entry from cls/level/subclass — no migration pass ever needed.
## classes[0] is the PRIMARY (drives portraits, prose, the hit-die pool).
func sheet_classes(s: Dictionary) -> Array:
	var cl = s.get("classes")
	if cl is Array and not cl.is_empty():
		return cl
	return [{"cls": str(s.get("cls", "Adventurer")), "level": int(s.get("level", 1)),
		"subclass": str(s.get("subclass", ""))}]


## "Fighter 3" or "Fighter 2 / Wizard 1" — the sheet line and the GM envelope.
func class_label(s: Dictionary) -> String:
	var bits: Array[String] = []
	for c in sheet_classes(s):
		bits.append("%s %d" % [str(c.get("cls", "?")), int(c.get("level", 1))])
	return " / ".join(bits)


func class_hit_die(cls: String) -> int:
	return int(tables.get("class_presets", {}).get(cls, {}).get("hitDie", 8))


## Combined caster level across classes: full casters count whole,
## the half-casters (Ranger/Paladin) count half, floored.
func caster_level(s: Dictionary) -> int:
	var full := 0
	var half := 0
	for c in sheet_classes(s):
		var cls := str(c.get("cls", ""))
		var lv := int(c.get("level", 0))
		if bool(tables.get("class_presets", {}).get(cls, {}).get("caster", false)):
			full += lv
		elif cls in ["Ranger", "Paladin"]:
			half += lv
	@warning_ignore("integer_division")
	return full + half / 2


## The ability a class leans on — the multiclass prerequisite (13+ to cross).
func class_prime(cls: String) -> String:
	if CAST_ABIL.has(cls):
		return str(CAST_ABIL[cls])
	return str({"Barbarian": "STR", "Fighter": "STR", "Monk": "DEX", "Rogue": "DEX"}.get(cls, "STR"))


func can_multiclass_into(s: Dictionary, cls: String) -> bool:
	return int(s.get("abilities", {}).get(class_prime(cls), 10)) >= 13


## The best casting class on the sheet decides the casting ability.
func cast_ability(s: Dictionary) -> String:
	var best := ""
	var best_lv := -1
	for c in sheet_classes(s):
		var cls := str(c.get("cls", ""))
		if CAST_ABIL.has(cls) and int(c.get("level", 0)) > best_lv:
			best = str(CAST_ABIL[cls])
			best_lv = int(c.get("level", 0))
	return best


func spell_save_dc(s: Dictionary) -> int:
	var ab := cast_ability(s)
	if ab == "":
		return -1
	return 8 + prof_bonus(s) + ability_mod(int(s["abilities"].get(ab, 10)))


## Foes carry no ability scores — their saving-throw bonus is derived from tier,
## the same way AC/HP are. Used when a spell forces a save (Fireball, Hold, …).
func foe_save_mod(tier: String) -> int:
	match tier.to_lower():
		"minor": return 1
		"tough": return 4
		"elite": return 5
		"boss", "legendary": return 7
	return 2  # standard/unknown


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


## Spells this hero could learn right now — every casting class on the sheet
## contributes, each at its OWN class level's reachable circle.
func learnable_spells(s: Dictionary) -> Array:
	var known := {}
	for sp in s.get("spells", []):
		known[str(sp.get("name", "")).to_lower()] = true
	var out: Array = []
	var seen := {}
	for c in sheet_classes(s):
		var cls := str(c.get("cls", ""))
		var circle := max_circle(cls, int(c.get("level", 1)))
		if circle == 0:
			continue
		for sp in spells:
			var nm := str(sp.get("name", "")).to_lower()
			if sp.get("classes", []).has(cls) and int(sp.get("level", 9)) <= circle \
					and not known.has(nm) and not seen.has(nm):
				seen[nm] = true
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
			verdict = " — **critical hit!**"
		elif r["roll"] == 1:
			verdict = " — **critical miss!**"
		elif check.get("ac") != null:
			var ac := int(check["ac"])
			verdict = (" — **hit!** (AC %d)" if total >= ac else " — **miss** (AC %d)") % ac
		return {"text": "*attack roll* → %s %+d = **%d**%s" % [d20_text(r), am, total, verdict], "total": total, "roll": r["roll"], "sides": 20}
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
		return {"text": "*%s* → %s = **%d** %s" % [kind, expr, total, "healed" if check.get("heal", false) else "damage"], "total": total, "roll": total, "sides": sides}
	# Plain ability/skill check or save.
	var mod := check_mod(sheet, check)
	var prof := is_proficient(sheet, check)
	var r2 := roll_d20(mode)
	var total2: int = r2["roll"] + mod
	var verdict2 := ""
	if check.get("dc") != null:
		var dc := int(check["dc"])
		verdict2 = (" — **success!** (DC %d)" if total2 >= dc else " — **failure** (DC %d)") % dc
	return {"text": "*%s%s* → %s %+d = **%d**%s" % [check_label(check),
		" (proficient)" if prof else "", d20_text(r2), mod, total2, verdict2], "total": total2, "roll": r2["roll"], "sides": 20}

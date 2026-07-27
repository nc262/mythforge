extends Node
## Skin — the World Skin system (docs/WorldSkin.md, Sprint M-B). A per-campaign
## visual language, resolved DETERMINISTICALLY from the world: built-in ids map
## directly; a forged world's kind/tagline/lore keywords choose a family; a
## stored `skin_family` always wins. Each family carries a palette key (into
## Ui.PALETTES), a currency, a generated-art style, a material vocabulary, and
## flavor nouns. Nothing downstream is hardcoded to fantasy — every surface
## resolves through here. LLM-refined palettes are a later slice; the
## deterministic default is always valid.

## family → { palette (Ui.PALETTES key), currency, art, materials{role→plate}, flavor }
const FAMILIES := {
	"fantasy": {"palette": "arcane", "currency": "gold", "art": "high fantasy oil painting, candlelit",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "stone", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "pack", "book": "tome", "world": "high fantasy"}},
	"cyber": {"palette": "neonspire", "currency": "credits", "art": "cyberpunk neon concept render, volumetric haze",
		"materials": {"steel": "glass", "leather": "carbon", "brass": "neon", "oak": "carbon", "panel": "glass", "page": "glass"},
		"flavor": {"map": "holo-map", "pack": "grid", "book": "datapad", "world": "cyberpunk sci-fi"}},
	"everyday": {"palette": "everyday", "currency": "cash", "art": "warm contemporary slice-of-life illustration",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "leather", "page": "parchment"},
		"flavor": {"map": "map", "pack": "bag", "book": "notebook", "world": "warm contemporary slice-of-life"}},
	"space": {"palette": "space", "currency": "credits", "art": "sci-fi space-opera concept art, cold starlight, sleek hull panels",
		"materials": {"steel": "glass", "leather": "carbon", "brass": "steel", "oak": "steel", "panel": "carbon", "page": "glass"},
		"flavor": {"map": "starmap", "pack": "locker", "book": "log", "world": "sci-fi space opera"}},
	"steam": {"palette": "steam", "currency": "cogs", "art": "steampunk illustration, brass and soot, warm gaslight",
		"materials": {"steel": "copper", "leather": "leather", "brass": "copper", "oak": "oak", "panel": "copper", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "case", "book": "ledger", "world": "steampunk"}},
	"pirate": {"palette": "pirate", "currency": "doubloons", "art": "age-of-sail painting, salt haze and lantern light",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "oak", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "sea chest", "book": "logbook", "world": "age-of-sail adventure"}},
	"horror": {"palette": "horror", "currency": "coin", "art": "gothic horror illustration, candlelit dread, desaturated",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "stone", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "satchel", "book": "grimoire", "world": "gothic horror"}},
	"norse": {"palette": "norse", "currency": "silver", "art": "norse saga illustration, cold fjord light, rune-carved wood",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "stone", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "pack", "book": "saga", "world": "norse saga fantasy"}},
}

const BUILTIN := {"embervale": "fantasy", "neonspire": "cyber", "everyday": "everyday",
	"fimbulreach": "norse", "brasshaven": "steam"}

## The World Style Guide's generative + voice descriptors, per family (A1 —
## ArchitectureEvolution §6). Referenced by the Art prompt builders (character
## fashion, creature kind, item materials) AND the GM persona (dialogue diction,
## lore tone), so everything a world generates — pictures and prose — matches it.
const STYLE := {
	"fantasy": {"char": "in medieval fantasy attire of leather, cloth, and plate", "beast": "a fantasy creature",
		"item": "forged metal, leather, and wood", "dialogue": "evocative, slightly archaic high-fantasy diction", "lore_tone": "mythic and grand"},
	"cyber": {"char": "in cyberpunk streetwear with chrome augments and neon trim", "beast": "a bio-engineered or cybernetic creature",
		"item": "sleek tech, glass, and carbon", "dialogue": "clipped, slang-laced neon-noir cyberpunk voice", "lore_tone": "gritty and corporate-dystopian"},
	"everyday": {"char": "in ordinary modern clothing", "beast": "an ordinary or slightly uncanny animal",
		"item": "everyday modern objects", "dialogue": "warm, natural, contemporary speech", "lore_tone": "grounded and personal"},
	"space": {"char": "in a sleek spacesuit or starfarer's uniform", "beast": "an alien lifeform",
		"item": "advanced alloys and energy tech", "dialogue": "cool, precise, spacefaring cadence", "lore_tone": "vast and coldly wondrous"},
	"steam": {"char": "in Victorian steampunk dress with brass fittings and goggles", "beast": "a clockwork or steam-driven creature",
		"item": "brass, copper, and clockwork", "dialogue": "ornate, mannered, Victorian phrasing", "lore_tone": "inventive and smoke-stained"},
	"pirate": {"char": "in weathered age-of-sail garb of coat, sash, and tricorn", "beast": "a sea beast or drowned thing",
		"item": "salt-worn wood, rope, and iron", "dialogue": "salty, rakish, seafaring speech", "lore_tone": "briny and roguish"},
	"horror": {"char": "in drab period dress, pale and wary", "beast": "an eldritch horror",
		"item": "tarnished, worn, faintly wrong objects", "dialogue": "hushed, dread-laced, foreboding prose", "lore_tone": "creeping and doom-laden"},
	"norse": {"char": "in furs, wool, and iron with rune-carved trim", "beast": "a saga beast of frost and legend",
		"item": "cold iron, bone, and carved wood", "dialogue": "stark, oath-bound, saga-like speech", "lore_tone": "cold, fated, and heroic"},
}

## family → an existing ambient track (Sfx has embervale/neonspire/everyday/arcane).
const MUSIC := {"fantasy": "embervale", "cyber": "neonspire", "everyday": "everyday",
	"space": "neonspire", "steam": "embervale", "pirate": "embervale", "horror": "arcane", "norse": "embervale"}

## First keyword hit wins — order from most-specific to least.
const KEYWORDS := [
	["cyber", ["cyber", "neon", "chrome", "hacker", "augment", "corpo", "megacity", "synth", "cyberpunk"]],
	["space", ["space", "starfaring", "interstellar", "orbital", "galax", "nebula", "cosmic", "starship", "void", "alien"]],
	["steam", ["steam", "clockwork", "cog", "victorian", "airship", "gaslight", "brass tower"]],
	["pirate", ["pirate", "buccaneer", "corsair", "privateer", "age of sail", "high seas", "doubloon"]],
	["horror", ["horror", "eldritch", "gothic", "nightmare", "haunted", "cursed", "dread"]],
	["norse", ["norse", "viking", "fjord", "valhalla", "rune", "jotun", "saga"]],
]

var _by_id := {}   # world_id → resolved family (cache; keeps play cheap)


## Resolve a full world descriptor to a family (deterministic).
func family_of(world: Dictionary) -> String:
	var id := str(world.get("id", ""))
	if BUILTIN.has(id):
		return BUILTIN[id]
	if world.get("skin_family") is String and FAMILIES.has(world["skin_family"]):
		return world["skin_family"]
	var hay := (str(world.get("kind", "")) + " " + str(world.get("tagline", "")) + " " + str(world.get("lore", ""))).to_lower()
	for pair in KEYWORDS:
		for kw in pair[1]:
			if hay.contains(kw):
				return pair[0]
	return "fantasy"


## Cache a world's family so later id-only lookups (in play) resolve correctly.
func remember(world: Dictionary) -> void:
	var id := str(world.get("id", ""))
	if id != "":
		_by_id[id] = family_of(world)
	remember_world(world)   # …and its real name, for anything that displays it


## The world's DISPLAYABLE name. Playtest #1: the hero panel rendered
## `world_id.capitalize()`, so the custom id `cw-elyrien-or-6v` reached the
## player as "Cw Elyrien Or 6v" — an engineering string in the UI (MIL §6).
## `remember_world` caches the real name as each world is seen.
var _names := {}


func remember_world(world: Dictionary) -> void:
	var id := str(world.get("id", ""))
	if id != "" and str(world.get("name", "")) != "":
		_names[id] = str(world["name"])


func world_name(world_id: String) -> String:
	if _names.has(world_id):
		return str(_names[world_id])
	for w in Rules.builtin_worlds():
		if w is Dictionary and str(w.get("id", "")) == world_id:
			_names[world_id] = str(w.get("name", ""))
			return str(_names[world_id])
	# A forged id looks like "cw-<slug>-<hex>" — recover the slug, never show
	# the prefix or the disambiguating hex.
	var parts := world_id.split("-", false)
	if parts.size() >= 2 and str(parts[0]) == "cw":
		parts.remove_at(0)
		if parts.size() > 1 and str(parts[-1]).length() <= 4:
			parts.remove_at(parts.size() - 1)
		return " ".join(parts).capitalize()
	return world_id.capitalize()


func family_for_id(world_id: String) -> String:
	if BUILTIN.has(world_id):
		return BUILTIN[world_id]
	return _by_id.get(world_id, "fantasy")


func skin(family: String) -> Dictionary:
	return FAMILIES.get(family, FAMILIES["fantasy"])


func skin_for_id(world_id: String) -> Dictionary:
	return skin(family_for_id(world_id))


func music_for_id(world_id: String) -> String:
	return MUSIC.get(family_for_id(world_id), "arcane")


## The style guide for the active adventure's world (by id, uses the cache).
func style_for_id(world_id: String) -> Dictionary:
	return STYLE.get(family_for_id(world_id), STYLE["fantasy"])


## The style guide for a full world descriptor (by keywords — used at forge time
## before the world is cached, e.g. when composing the GM persona).
func style_of(world: Dictionary) -> Dictionary:
	return STYLE.get(family_of(world), STYLE["fantasy"])


## Place-kind display: raw authored kinds ("tavern", "wilds") → a skinned
## label + drawn-icon name, so the Lore Book never leaks engine taxonomy and
## an Everyday world says "Café" where Embervale says "Tavern".
const PLACE_ICON := {"tavern": "mug", "home": "house", "landmark": "pillar", "wilds": "tree",
	"shop": "coins", "temple": "pillar", "dungeon": "skull", "port": "ship", "market": "coins"}
const PLACE_LABEL := {
	"everyday": {"tavern": "Café", "wilds": "Park", "dungeon": "Basement", "temple": "Chapel"},
	"cyber": {"tavern": "Bar", "wilds": "Undercity", "temple": "Shrine", "dungeon": "Sublevel"},
	"space": {"tavern": "Cantina", "wilds": "The Void", "dungeon": "Derelict", "home": "Quarters"},
	"pirate": {"wilds": "Open Water", "dungeon": "Sea Cave", "home": "Berth"},
	"steam": {"tavern": "Gin Palace", "wilds": "The Moors"},
}


func place_kind(world_id: String, kind: String) -> Dictionary:
	var k := kind.strip_edges().to_lower()
	if k == "":
		return {}
	var fam := family_for_id(world_id)
	return {"label": str(PLACE_LABEL.get(fam, {}).get(k, k.capitalize())),
		"icon": str(PLACE_ICON.get(k, "pin"))}


## The name of a hero's progression road, per family (Issue 6 flavor).
const TREE := {"cyber": "Augment Web", "steam": "Clockwork", "pirate": "Navigator's Chart"}


func tree_title(world_id: String) -> String:
	return TREE.get(family_for_id(world_id), "Constellation")

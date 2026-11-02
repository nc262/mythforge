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
		"flavor": {"map": "chart", "pack": "pack", "book": "tome", "world": "high fantasy"},
		"wards": {"square": "Market Square", "inn": "Common Room", "shop": "Trade Row", "hall": "Moot Hall", "homes": "Cottages", "quay": "Quay", "heights": "High Gate", "gate": "Town Gate"},
		"roof": "pitch",
		"grain": {"lot": 3.0, "chaos": 0.80, "empty": 0.10, "front": 0.74},
		"rooms": {"tavern": ["Common Room", "Kitchen", "Cellar", "Guest Rooms", "Stable Yard"], "shop": ["Shop Floor", "Work Bench", "Store Room", "Keeper's Room", "Back Yard"], "home": ["Hearth Room", "Scullery", "Larder", "Bed Chamber", "Garden"]},
		"trades": {"inn": "Inn", "tavern": "Tavern", "store": "General Store", "smith": "Smithy", "alchemist": "Apothecary", "temple": "Temple", "fence": "Crooked Door", "sage": "Sage's Study", "guild": "Guildhall"}},
	"cyber": {"palette": "neonspire", "currency": "credits", "art": "cyberpunk neon concept render, volumetric haze",
		"materials": {"steel": "glass", "leather": "carbon", "brass": "neon", "oak": "carbon", "panel": "glass", "page": "glass"},
		"flavor": {"map": "holo-map", "pack": "grid", "book": "datapad", "world": "cyberpunk sci-fi"},
		"wards": {"square": "Plaza", "inn": "Noodle Bar", "shop": "Stall Row", "hall": "Admin Block", "homes": "Stacks", "quay": "Docks", "heights": "Upper Terrace", "gate": "Checkpoint"},
		"roof": "flat",
		"grain": {"lot": 9.0, "chaos": 0.30, "empty": 0.05, "front": 0.95},
		"rooms": {"tavern": ["Counter", "Galley", "Cold Store", "Back Booths", "Alley Door"], "shop": ["Storefront", "Bench", "Stock Cage", "Owner's Nook", "Loading Bay"], "home": ["Main Room", "Kitchenette", "Closet", "Sleep Pod", "Balcony"]},
		"trades": {"inn": "Capsule Hotel", "tavern": "Noodle Stand", "store": "Bodega", "smith": "Fabricator", "alchemist": "Ripperdoc", "temple": "Shrine", "fence": "Chop Shop", "sage": "Datahaus", "guild": "Syndicate Office"}},
	"everyday": {"palette": "everyday", "currency": "cash", "art": "warm contemporary slice-of-life illustration",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "leather", "page": "parchment"},
		"flavor": {"map": "map", "pack": "bag", "book": "notebook", "world": "warm contemporary slice-of-life"},
		"wards": {"square": "Town Square", "inn": "Corner Cafe", "shop": "Shopping Row", "hall": "City Hall", "homes": "Suburbs", "quay": "Waterfront", "heights": "Hill Road", "gate": "Old Town"},
		"roof": "flat",
		"grain": {"lot": 5.5, "chaos": 0.40, "empty": 0.14, "front": 0.78},
		"rooms": {"tavern": ["Dining Room", "Kitchen", "Walk-In", "Back Booth", "Patio"], "shop": ["Sales Floor", "Counter", "Stock Room", "Office", "Loading Dock"], "home": ["Living Room", "Kitchen", "Pantry", "Bedroom", "Back Yard"]},
		"trades": {"inn": "Motel", "tavern": "Bar", "store": "Corner Store", "smith": "Garage", "alchemist": "Pharmacy", "temple": "Chapel", "fence": "Pawn Shop", "sage": "Library", "guild": "Union Hall"}},
	"space": {"palette": "space", "currency": "credits", "art": "sci-fi space-opera concept art, cold starlight, sleek hull panels",
		"materials": {"steel": "glass", "leather": "carbon", "brass": "steel", "oak": "steel", "panel": "carbon", "page": "glass"},
		"flavor": {"map": "starmap", "pack": "locker", "book": "log", "world": "sci-fi space opera"},
		"wards": {"square": "Concourse", "inn": "Mess Deck", "shop": "Exchange", "hall": "Command Deck", "homes": "Hab Block", "quay": "Docking Ring", "heights": "Upper Deck", "gate": "Airlock"},
		"roof": "flat",
		"grain": {"lot": 8.0, "chaos": 0.18, "empty": 0.04, "front": 0.97},
		"rooms": {"tavern": ["Mess", "Galley", "Cold Locker", "Quiet Booth", "Airlock"], "shop": ["Trade Floor", "Bench", "Cargo Bay", "Purser's Office", "Dock Arm"], "home": ["Berth", "Galley Nook", "Locker", "Bunk", "Viewport"]},
		"trades": {"inn": "Berths", "tavern": "Galley", "store": "Commissary", "smith": "Machine Shop", "alchemist": "Medbay", "temple": "Quiet Room", "fence": "Grey Market", "sage": "Archive", "guild": "Union Office"}},
	"steam": {"palette": "steam", "currency": "cogs", "art": "steampunk illustration, brass and soot, warm gaslight",
		"materials": {"steel": "copper", "leather": "leather", "brass": "copper", "oak": "oak", "panel": "copper", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "case", "book": "ledger", "world": "steampunk"},
		"wards": {"square": "Clockwork Square", "inn": "Public House", "shop": "Merchant Arcade", "hall": "Board of Works", "homes": "Tenements", "quay": "Wharf", "heights": "Upper Works", "gate": "Toll Gate"},
		"roof": "pitch",
		"grain": {"lot": 3.4, "chaos": 0.62, "empty": 0.08, "front": 0.72},
		"rooms": {"tavern": ["Public Bar", "Kitchen", "Beer Cellar", "Upstairs Rooms", "Coach Yard"], "shop": ["Shop Front", "Work Bench", "Store Room", "Counting Room", "Back Court"], "home": ["Parlour", "Scullery", "Coal Store", "Bed Room", "Back Court"]},
		"trades": {"inn": "Lodging House", "tavern": "Public Bar", "store": "Emporium", "smith": "Foundry", "alchemist": "Dispensary", "temple": "Chapel", "fence": "Pawnbroker", "sage": "Athenaeum", "guild": "Guildhall"}},
	"pirate": {"palette": "pirate", "currency": "doubloons", "art": "age-of-sail painting, salt haze and lantern light",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "oak", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "sea chest", "book": "logbook", "world": "age-of-sail adventure"},
		"wards": {"square": "Harbour Market", "inn": "Grog Alley", "shop": "Rope Walk", "hall": "Harbourmaster", "homes": "Netmakers Row", "quay": "Quay", "heights": "Cliff Stair", "gate": "Landward Gate"},
		"roof": "pitch",
		"grain": {"lot": 2.6, "chaos": 0.92, "empty": 0.09, "front": 0.75},
		"rooms": {"tavern": ["Tap Room", "Galley", "Cellar", "Upstairs Bunks", "Back Alley"], "shop": ["Chandlery Floor", "Work Bench", "Store Room", "Keeper's Room", "Quay Door"], "home": ["Front Room", "Galley", "Net Store", "Bunk Room", "Fish Yard"]},
		"trades": {"inn": "Boarding House", "tavern": "Tavern", "store": "Chandlery", "smith": "Forge", "alchemist": "Physicker", "temple": "Chapel", "fence": "Receiver", "sage": "Navigator's Loft", "guild": "Brotherhood Hall"}},
	"horror": {"palette": "horror", "currency": "coin", "art": "gothic horror illustration, candlelit dread, desaturated",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "stone", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "satchel", "book": "grimoire", "world": "gothic horror"},
		"wards": {"square": "Old Square", "inn": "Lodging House", "shop": "Shuttered Row", "hall": "Parish Hall", "homes": "Almshouses", "quay": "Black Wharf", "heights": "Chapel Rise", "gate": "Iron Gate"},
		"roof": "pitch",
		"grain": {"lot": 2.8, "chaos": 0.88, "empty": 0.16, "front": 0.70},
		"rooms": {"tavern": ["Tap Room", "Kitchen", "Cold Cellar", "Lodging Rooms", "Back Court"], "shop": ["Shop Floor", "Work Bench", "Store Room", "Keeper's Room", "Yard"], "home": ["Parlour", "Scullery", "Cellar", "Bed Chamber", "Overgrown Garden"]},
		"trades": {"inn": "Boarding House", "tavern": "Public House", "store": "Dry Goods", "smith": "Blacksmith", "alchemist": "Apothecary", "temple": "Chapel", "fence": "Pawnbroker", "sage": "Antiquarian", "guild": "Lodge"}},
	"norse": {"palette": "norse", "currency": "silver", "art": "norse saga illustration, cold fjord light, rune-carved wood",
		"materials": {"steel": "steel", "leather": "leather", "brass": "brass", "oak": "oak", "panel": "stone", "page": "parchment"},
		"flavor": {"map": "chart", "pack": "pack", "book": "saga", "world": "norse saga fantasy"},
		"wards": {"square": "Thing-Stead", "inn": "Ale-Row", "shop": "Traders Row", "hall": "Jarls Hall", "homes": "Longhouses", "quay": "Boat Strand", "heights": "Beacon Rise", "gate": "Stockade Gate"},
		"roof": "pitch",
		"grain": {"lot": 5.0, "chaos": 0.70, "empty": 0.12, "front": 0.84},
		"rooms": {"tavern": ["Long Room", "Hearth Kitchen", "Ale Store", "Sleeping Benches", "Byre"], "shop": ["Trade Booth", "Work Bench", "Goods Store", "Keeper's Nook", "Boat Yard"], "home": ["Hall", "Hearth", "Food Store", "Sleeping Bench", "Home Field"]},
		"trades": {"inn": "Guest-Hall", "tavern": "Mead-Hall", "store": "Trade-Booth", "smith": "Forge", "alchemist": "Healer's Croft", "temple": "Hof", "fence": "Silver-Buyer", "sage": "Skald's Seat", "guild": "Thing-Booth"}},
}

## ── WHAT A PLACE SELLS, AND WHEN IT IS BIG ENOUGH TO SELL IT ─────────────────
##
## The same socket idea as the wards: nine trades the engine can price and draw,
## each named by the world. A fantasy `alchemist` is an Apothecary, a cyber one
## is a Ripperdoc, a norse one is a Healer's Croft — one mechanic, one mark, nine
## signs.
##
## TIERED, because every published system ties what a settlement can offer to
## its size and none of them leave it to taste: the 2024 DMG gates the top item
## value on it, Pathfinder gates base value, purchase limit and spell tier. A
## hamlet has a tavern and somewhere to buy rope; a city has everything and a
## guild. The list is cumulative — a tier gets its own row plus every row below.
const TRADE_KEYS: Array[String] = ["inn", "tavern", "store", "smith",
	"alchemist", "temple", "fence", "sage", "guild"]

## tier -> the trades that ARRIVE at that size. 0 hamlet, 1 village, 2 town, 3 city.
const TRADE_TIERS: Array = [
	["tavern", "store"],
	["inn", "smith"],
	["temple", "alchemist", "sage"],
	["guild", "fence"],
]


func trade_name(family: String, key: String) -> String:
	var fam: Dictionary = FAMILIES.get(family, FAMILIES["fantasy"])
	var words: Dictionary = fam.get("trades", {})
	if words.has(key):
		return str(words[key])
	return str(FAMILIES["fantasy"]["trades"].get(key, key))


## AT-17: A TRADE NEEDS A PROPER NAME. "The Tavern" is a role word, and a generic
## noun loses to any proper one — the real narrator sent the player to a chart
## tavern instead of the market's own. So each trade gets a name the way real
## towns name them: a SIGN for a house you drink or deal in, an OWNER for a
## workshop, the TOWN for its temple and guild. Seeded by town + trade, so the
## map, the brief and every visit agree; the words are the family's flavour.
## ponytail: six of each per family; widen when two towns in one world collide.
const SIGNS := {
	"fantasy": {"adj": ["Leaning", "Gilded", "Drowsy", "Crooked", "Silver", "Merry"], "noun": ["Lantern", "Stag", "Kettle", "Goose", "Anvil", "Thistle"], "folk": ["Harrow", "Thorne", "Mabry", "Pell", "Ashdown", "Crane"]},
	"cyber": {"adj": ["Neon", "Static", "Chrome", "Broken", "Midnight", "Ghost"], "noun": ["Circuit", "Koi", "Signal", "Lotus", "Socket", "Relay"], "folk": ["Okafor", "Vance", "Tanaka", "Rourke", "Mbeki", "Sato"]},
	"everyday": {"adj": ["Lucky", "Blue", "Corner", "Sunny", "Red", "Old"], "noun": ["Penny", "Door", "Spoon", "Lamp", "Fox", "Bench"], "folk": ["Miller", "Garcia", "Patel", "Brooks", "Nguyen", "Walsh"]},
	"space": {"adj": ["Drifting", "Cold", "Last", "Silent", "Bright", "Red"], "noun": ["Comet", "Airlock", "Orbit", "Beacon", "Dock", "Star"], "folk": ["Okonkwo", "Reyes", "Ivanova", "Chen", "Halloran", "Adeyemi"]},
	"steam": {"adj": ["Brass", "Copper", "Smoking", "Rusted", "Iron", "Whistling"], "noun": ["Gear", "Piston", "Gauge", "Boiler", "Kettle", "Cog"], "folk": ["Ashworth", "Fennimore", "Blackwood", "Crowley", "Pendleton", "Hargreave"]},
	"pirate": {"adj": ["Salty", "Drunken", "Black", "Rusty", "Jolly", "Sunken"], "noun": ["Anchor", "Parrot", "Gull", "Barrel", "Kraken", "Compass"], "folk": ["Morgan", "Teague", "Flint", "Bonney", "Rackham", "Doyle"]},
	"horror": {"adj": ["Hanged", "Weeping", "Hollow", "Silent", "Last", "Black"], "noun": ["Crow", "Bell", "Candle", "Lamb", "Gate", "Lantern"], "folk": ["Marsh", "Gaunt", "Whateley", "Corwin", "Pike", "Hale"]},
	"norse": {"adj": ["Red", "Grey", "Howling", "Iron", "Frost", "One-Eyed"], "noun": ["Wolf", "Raven", "Boar", "Horn", "Elk", "Hammer"], "folk": ["Ragnarsson", "Eiriksdottir", "Bjornsson", "Haldorsdottir", "Ulfsson", "Sigrunsdottir"]},
}
const _SIGN_TRADES := ["inn", "tavern", "fence"]
const _CIVIC_TRADES := ["temple", "guild"]
const _OWNER_TRADES := ["store", "smith", "alchemist", "sage"]


## `salt` re-rolls a name that is already taken in the same town.
func trade_title(family: String, key: String, town: String, salt := 0) -> String:
	var s: Dictionary = SIGNS.get(family, SIGNS["fantasy"])
	var word := trade_name(family, key)
	# TOWN hash + the trade's slot WITHIN ITS STYLE, not a hash per trade: per-trade
	# hashes gave one town Crane's Smithy AND Crane's General Store. Slots are
	# 0..n-1 and n is below the pool size, so no two trades share a word.
	var h := absi(hash("%s|%d" % [town, salt]))
	if _SIGN_TRADES.has(key):
		var k := _SIGN_TRADES.find(key)
		return "The %s %s" % [s["adj"][(h + k) % s["adj"].size()], s["noun"][(h / 7 + k) % s["noun"].size()]]
	if _CIVIC_TRADES.has(key):
		return "%s %s" % [town.trim_prefix("The ").get_slice(" ", 0), word]
	# "Sage's Study" under an owner is "Harrow's Study", not "Harrow's Sage's Study".
	if word.contains("'s "):
		word = word.get_slice("'s ", 1)
	return "%s's %s" % [s["folk"][(h + _OWNER_TRADES.find(key)) % s["folk"].size()], word]


## Everything a settlement of this size offers — its own row and all below it.
func trades_at(tier: int) -> Array:
	var out: Array = []
	for t in mini(tier, TRADE_TIERS.size() - 1) + 1:
		for k in TRADE_TIERS[t]:
			out.append(k)
	return out


## ── THE GRAIN OF A WORLD'S BUILDING ──────────────────────────────────────────
##
## The ward NAMES differed per family and the FABRIC did not — every town was
## built with one lot size and one street chaos, so at map zoom a cyberpunk
## district and a fishing village were the same gravel texture under different
## words. These are the four numbers that make them read differently before a
## single label is drawn.
##
##   lot    base building area, in square plate units (the plate is 100 across,
##          so one unit is about ten metres)
##   chaos  how far a street may wander off square; 0 is a grid, 1 is organic
##   empty  share of finished plots left unbuilt — yards, courts, gardens
##   front  how much of a plot is BUILT ON, the rest left as yard behind it.
##          Low is a medieval burgage strip (narrow frontage, long garden),
##          high is a modern block built lot-line to lot-line.
##
## THESE ARE NOT THE HISTORICAL RATIOS and deliberately so. A real burgage plot
## builds on maybe a fifth of its depth; at that value the measured built share
## of a ward fell to 0.08-0.14 and the town read as a scattering in a field
## rather than as a town. The clip also takes more than its depth fraction,
## because cutting a tapering polygon at 45 % of its extent removes more than
## 45 % of its area. What is kept is the SHAPE of the pattern — narrow fronts on
## the street, open ground behind — at a density a map can be read at.
const GRAIN_KEYS: Array[String] = ["lot", "chaos", "empty", "front"]


## ── THE ROOMS OF ONE BUILDING ────────────────────────────────────────────────
##
## MEASURED 2026-09-17: of the 29 places the six shipped worlds carry, exactly
## ONE is a `settlement`. The rest of what the map treated as settled are single
## BUILDINGS — a tavern, a shop, a cottage — and each was drawn as a village with
## quarters, an inn, a smithy and a general store inside it. The Ember & Oak, a
## tavern, came out with four wards and its own Tavern in one of them.
##
## So a building has ROOMS, not quarters: the same socket idea one scale down.
## Five keys, in order — the public room, the working room, the store, the
## private room, and the way out the back — and every family names them its own
## way. A hamlet-sized cottage uses the first few; a coaching inn uses all five.
const ROOM_KEYS: Array[String] = ["main", "work", "store", "private", "outside"]
## The building kinds a world puts people in. `settlement` is a town; these are
## one roof. Matches LocalMap.BUILDING_KINDS, asserted in self_check.
const ROOM_KINDS: Array[String] = ["tavern", "shop", "home"]


## The rooms of a building of this kind in this world, in ROOM_KEYS order.
func rooms_of(family: String, place_kind: String) -> Array:
	var fam: Dictionary = FAMILIES.get(family, FAMILIES["fantasy"])
	var table: Dictionary = fam.get("rooms", FAMILIES["fantasy"]["rooms"])
	var got = table.get(place_kind, table.get("home", []))
	return got if got is Array and not got.is_empty() else FAMILIES["fantasy"]["rooms"]["home"]


## ── HOW A ROOF READS FROM ABOVE ──────────────────────────────────────────────
## Every world drew the same house: a footprint with one ridge line down its long
## axis, which is the hand-drawn-map convention for a PITCHED roof. On a cyber
## street or a station deck that is simply wrong — those roofs are flat, and what
## a plan shows is the parapet, not a ridge. One key, two values, and the town
## sheet stops being the same town in eight palettes.
const ROOFS: Array[String] = ["pitch", "flat"]


func roof(family: String) -> String:
	var fam: Dictionary = FAMILIES.get(family, FAMILIES["fantasy"])
	var r := str(fam.get("roof", "pitch"))
	return r if ROOFS.has(r) else "pitch"


func grain(family: String) -> Dictionary:
	var fam: Dictionary = FAMILIES.get(family, FAMILIES["fantasy"])
	return fam.get("grain", FAMILIES["fantasy"]["grain"])


## ── THE WARD VOCABULARY ──────────────────────────────────────────────────────
##
## The SOCKETS are fixed and the WORDS are the world's. Every family answers the
## same eight keys, so the town generator asks for `square` and gets whatever
## that world calls its square — a Thing-Stead in a saga, a Concourse on a
## station, Clockwork Square under the soot.
##
## THIS USED TO BE A STRING MATCH IN THE GENERATOR, and it is the reason a
## steampunk foundry town had a Noodle Bar in it. `local_map` asked whether the
## family's prose `world` line contained "cyber" or "steam", and branched two
## ways — so eight families produced two vocabularies, cyberpunk words leaked
## into steampunk, and a fantasy village and a pirate port came out with
## identical ward names on the same sheet. Flavour belongs in the flavour table,
## keyed, never inferred from prose.
## TYPED, for the reason `WorldTerrain.N4` and `LocalMap.SIDES` are: an untyped
## array literal iterated in a `for` makes every `var x := ...` inside that loop
## uninferrable, which is a PARSE error — and a parse error in a class_name file
## is silent at the call site. Third time this shape has come up in this work.
const WARD_KEYS: Array[String] = ["square", "inn", "shop", "hall", "homes",
	"quay", "heights", "gate"]

## BARE NOUNS, NO ARTICLE. The generator writes "The %s", so a word carrying its
## own "The" renders as "The The Plaza" — which it did, on the cyber and everyday
## sheets, until the check below was written.
##
## The five every town has, in the order they are handed out — richest first.
## `quay`, `heights` and `gate` are chosen by the SITE instead.
const CORE_WARDS: Array[String] = ["square", "inn", "shop", "hall", "homes"]


## What this world calls the given kind of quarter. Falls back to fantasy, which
## is complete by the check in `self_check` — so this cannot return "".
func ward_name(family: String, key: String) -> String:
	var fam: Dictionary = FAMILIES.get(family, FAMILIES["fantasy"])
	var words: Dictionary = fam.get("wards", {})
	if words.has(key):
		return str(words[key])
	return str(FAMILIES["fantasy"]["wards"].get(key, key))


## EVERY shipped world must be here. `_by_id` is only filled by `remember()`,
## which runs when a world is entered — so a world missing from this map
## resolves to the "fantasy" default on any cold lookup, and since art keys
## are family-scoped it then SHARES EMBERVALE'S PAINTINGS. saltmarsh did
## exactly that: a warm run over all six worlds painted 42 pictures each for
## five of them and 0 for saltmarsh, in 0.0 minutes, because every key it
## asked for was already on disk under fantasy. self_check now counts this.
const BUILTIN := {"embervale": "fantasy", "neonspire": "cyber", "everyday": "everyday",
	"saltmarsh": "pirate", "fimbulreach": "norse", "brasshaven": "steam"}

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


## The counter's own vocabulary, per family. "The trading post", "the keeper's
## wares" and "your purse" are fantasy nouns, and they were sitting beside a
## currency the game had already correctly renamed: a Neon Spire fixer sells you
## a Mono-Knife for credits from behind "The trading post", and the Record says
## the credits are "in the purse" (PY-25, found by playing it).
##
## Same shape as PLACE_LABEL above — a family overrides the words it cares about
## and anything it does not name keeps the fantasy default, so a new family is a
## few entries rather than a rewrite.
const SHOP_WORDS := {
	"cyber": {"post": "The exchange", "keeper": "dealer", "wares": "The dealer's stock", "purse": "account"},
	"everyday": {"post": "The shop", "keeper": "shopkeeper", "wares": "On the shelves", "purse": "wallet"},
	"space": {"post": "The commissary", "keeper": "quartermaster", "wares": "The commissary's stock", "purse": "account"},
	"steam": {"post": "The emporium", "keeper": "proprietor", "wares": "The proprietor's wares", "purse": "billfold"},
	"pirate": {"post": "The chandlery", "keeper": "quartermaster", "wares": "The quartermaster's stock", "purse": "coffer"},
}
const SHOP_DEFAULT := {"post": "The trading post", "keeper": "keeper",
	"wares": "The keeper's wares", "purse": "purse"}


func shop_word(world_id: String, key: String) -> String:
	var fam := family_for_id(world_id)
	return str(SHOP_WORDS.get(fam, {}).get(key, SHOP_DEFAULT.get(key, key)))


## The name of a hero's progression road, per family (Issue 6 flavor).
const TREE := {"cyber": "Augment Web", "steam": "Clockwork", "pirate": "Navigator's Chart"}


func tree_title(world_id: String) -> String:
	return TREE.get(family_for_id(world_id), "Constellation")

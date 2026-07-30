extends RefCounted
## The World Forge's question pool — see docs/WorldForge-UX.md.
##
## This replaces five fixed axes (Magic system, Technology, Era, Beast variants,
## Tone) that were asked of every world forever. Five frozen questions are a
## TAXONOMY: 3,000 combinations, most producing near-identical prompts, and the
## same options regardless of theme — which is how a cyberpunk world came to be
## offered "Dragons & their kin".
##
## Two rules make this different:
##
## 1. **A question must earn its place.** Each declares `when`, and is only asked
##    of a world it actually fits.
## 2. **A question must not be asked twice.** `answered_by` lists the words that
##    mean the player's own premise already settled it. Asking someone who wrote
##    "a drowned city" whether their world has water is how a form feels like a
##    form.
##
## Options carry a CONSEQUENCE, not a label. "Forbidden & feared" is a category;
## "casting in public gets you reported" is a rule the player can picture and the
## GM can enforce — and since the option text becomes the prompt text, the model
## is handed rules instead of adjectives.

## How many to ask. Same interaction budget as the five it replaces: the gain is
## in which ones get asked, not in asking more. Ask too many and people leave.
const ASK := 5

## Always in the pool, whatever the world. These two generate CONFLICT rather
## than colour, which is what a playable world actually needs — "Technology:
## Medieval" has never once started an argument at the table.
const ALWAYS := ["scarcity", "authority"]

const POOL := [
	{
		"id": "scarcity", "label": "What is scarce here?",
		"answered_by": [],
		"when": {},
		"options": [
			{"pick": "Clean water", "rule": "every settlement is built around a well somebody owns"},
			{"pick": "Iron", "rule": "a steel blade is inherited, never bought"},
			{"pick": "Daylight", "rule": "work and travel are rationed to the hours of light"},
			{"pick": "Truth", "rule": "no two accounts of the same event agree, and everyone knows it"},
			{"pick": "Names", "rule": "a true name is property, and can be taken"},
			{"pick": "Medicine", "rule": "an infected wound is a death sentence with a schedule"},
		],
	},
	{
		"id": "authority", "label": "Who decides — and who resents it?",
		"answered_by": [],
		"when": {},
		"options": [
			{"pick": "An old order, quietly hated", "rule": "the law is obeyed in public and ignored in private"},
			{"pick": "Whoever holds the supply", "rule": "power changes hands with the harvest, not the crown"},
			{"pick": "A council that cannot agree", "rule": "nothing is decided quickly, and every faction has a veto"},
			{"pick": "No one, and it shows", "rule": "every road is a negotiation and every town sets its own rules"},
			{"pick": "Something not human", "rule": "the rulings are absolute, and nobody can explain the reasoning"},
		],
	},
	{
		"id": "magic_cost", "label": "What does power cost the one who uses it?",
		"answered_by": ["no magic", "mundane", "magicless"],
		"when": {"not_theme": ["Sci-Fi"]},
		"options": [
			{"pick": "Years off a life", "rule": "casters are young and look old; nobody old still casts"},
			{"pick": "Memory", "rule": "every working takes something the caster will not notice is gone"},
			{"pick": "A debt to something", "rule": "power is borrowed, the lender keeps count, and it collects"},
			{"pick": "Nothing — and that's the problem", "rule": "power is free, so it is everywhere, and nobody trusts anything they see"},
			{"pick": "Standing", "rule": "casting in public gets you reported"},
		],
	},
	{
		"id": "the_water", "label": "What does the water take?",
		"answered_by": [],
		"when": {"theme": ["Pirates"], "premise": ["sea", "tide", "drowned", "sunken", "salt", "harbour", "harbor", "ocean", "canal", "flood"]},
		"options": [
			{"pick": "Ships, on a schedule", "rule": "every crossing is a wager and the odds are known"},
			{"pick": "The drowned, who come back", "rule": "the dead return with the tide and are not always hostile"},
			{"pick": "Memory of the coast", "rule": "the maps are wrong because the shore keeps moving"},
			{"pick": "Nothing — it gives", "rule": "the sea feeds everyone here, which is why nobody will leave when they should"},
		],
	},
	{
		"id": "machine_cost", "label": "What do the machines run on?",
		"answered_by": [],
		"when": {"theme": ["Steampunk", "Sci-Fi"], "premise": ["steam", "clockwork", "brass", "engine", "machine", "neon", "cyber", "starfar", "salvage", "reactor"]},
		"options": [
			{"pick": "Something that used to be alive", "rule": "fuel is harvested, and polite society does not ask from where"},
			{"pick": "Labour, endlessly", "rule": "someone is always shovelling, and they are not paid well"},
			{"pick": "Salvage nobody can make any more", "rule": "every machine is a countdown to its last spare part"},
			{"pick": "A principle nobody understands", "rule": "it works, no one can say why, and it is beginning to stop"},
		],
	},
	{
		"id": "the_dead", "label": "What do the dead do here?",
		"answered_by": [],
		"when": {"theme": ["Horror", "Norse"], "premise": ["dead", "ghost", "haunt", "spirit", "grave", "tomb", "corpse", "wake", "restless"]},
		"options": [
			{"pick": "Stay, and keep opinions", "rule": "the dead are consulted, and they lie as often as the living did"},
			{"pick": "Come back wrong", "rule": "a burial is a security measure, not a ceremony"},
			{"pick": "Nothing — and that is new", "rule": "the dead have recently stopped answering, and no one knows why"},
			{"pick": "Get paid to leave", "rule": "a funeral is a transaction and a poor family's dead do not rest"},
		],
	},
	{
		"id": "watched", "label": "Who is listening?",
		"answered_by": [],
		"when": {"theme": ["Intrigue", "Horror", "Sci-Fi"], "premise": ["court", "spy", "conspirac", "secret", "cult", "guild", "watch", "informant"]},
		"options": [
			{"pick": "Everyone, for money", "rule": "any conversation in a public room is for sale by nightfall"},
			{"pick": "One office, thoroughly", "rule": "there are records of you, and they are more complete than your memory"},
			{"pick": "Something in the walls", "rule": "buildings remember what was said in them, and can be asked"},
			{"pick": "No one — nobody cares", "rule": "you can say anything anywhere, which is why nothing said matters"},
		],
	},
	{
		"id": "the_road", "label": "What makes travel dangerous?",
		"answered_by": [],
		"when": {},
		"options": [
			{"pick": "What lives between towns", "rule": "the roads are safe by day and belong to something else after dark"},
			{"pick": "Other travellers", "rule": "the monsters are people, and they are organised"},
			{"pick": "The distance itself", "rule": "there is nothing out there, and that is enough to kill you"},
			{"pick": "The tolls", "rule": "every border is a fee, and the fees are how the map is really drawn"},
			{"pick": "The weather", "rule": "a season can close a route for months and strand you where you stand"},
		],
	},
	{
		"id": "the_cold", "label": "What does winter take?",
		"answered_by": [],
		"when": {"theme": ["Norse"], "premise": ["winter", "ice", "frost", "snow", "cold", "fjord", "glacier"]},
		"options": [
			{"pick": "The old and the unlucky", "rule": "every settlement counts survivors in spring and expects to lose some"},
			{"pick": "The roads", "rule": "for half the year each place is alone with whatever it has"},
			{"pick": "The light", "rule": "there are weeks of dark, and things travel in it"},
			{"pick": "Nothing yet — it is coming", "rule": "everyone is preparing for a winter that has not arrived, and preparing badly"},
		],
	},
	{
		"id": "the_wrong", "label": "What went wrong here, and how long ago?",
		"answered_by": [],
		"when": {"theme": ["Dark Fantasy", "Horror", "Steampunk"], "premise": ["ruin", "cataclysm", "fell", "collapse", "after", "war", "plague", "empire"]},
		"options": [
			{"pick": "Within living memory", "rule": "there are people who remember it working, and they are angry"},
			{"pick": "Long enough to be a story", "rule": "everyone knows the tale and no two versions agree"},
			{"pick": "It is still happening", "rule": "the decline is measurable year on year and nobody will say so out loud"},
			{"pick": "Nothing did — that is the lie", "rule": "the golden age is propaganda and the evidence is buried"},
		],
	},
	# ── Rulings ─────────────────────────────────────────────────────────────
	# Two options, both attractive, neither a category. The player is not
	# classifying their world here, they are MAKING A RULING ABOUT IT — and a
	# ruling is a fact the GM can hold them to later, which "Tone: Grim & gritty"
	# never was. These sit low in the pool on purpose: they land best once a
	# premise and a theme have given them something to be a ruling about.
	{
		"id": "ruling_blame", "label": "Which is worse — the thing in the dark, or the people who feed it?",
		"answered_by": [],
		"when": {"theme": ["Horror", "Dark Fantasy"], "premise": ["dread", "dark", "cult", "sacrifice", "hunger", "monster"]},
		"options": [
			{"pick": "The thing", "rule": "the horror is genuinely inhuman and the people are its victims"},
			{"pick": "The people", "rule": "the horror is fed on purpose by people with reasons, and the reasons are good ones"},
		],
	},
	{
		"id": "ruling_order", "label": "Which would this world rather lose — its order, or its freedom?",
		"answered_by": [],
		"when": {},
		"options": [
			{"pick": "Order", "rule": "people here will accept chaos before they accept being told what to do"},
			{"pick": "Freedom", "rule": "people here will trade almost anything for safety, and have"},
		],
	},
	{
		"id": "ruling_past", "label": "Is the past something to recover, or something to survive?",
		"answered_by": [],
		"when": {"theme": ["Dark Fantasy", "High Fantasy", "Steampunk", "Sci-Fi"], "premise": ["ruin", "ancient", "forgotten", "empire", "relic", "old"]},
		"options": [
			{"pick": "Recover", "rule": "the old world was better and everyone is digging for what it left"},
			{"pick": "Survive", "rule": "the old world is what went wrong and its leavings are still dangerous"},
		],
	},
	{
		"id": "beasts", "label": "What kind of thing hunts people?",
		"answered_by": [],
		"when": {},
		"options": [
			{"pick": "Animals, but wrong", "rule": "the wildlife is familiar in shape and not in behaviour"},
			{"pick": "Things that were made", "rule": "the dangerous things were built on purpose and outlived their purpose"},
			{"pick": "The unquiet", "rule": "what hunts is not alive and cannot be reasoned with or killed twice"},
			{"pick": "Something enormous, rarely", "rule": "there are few threats and each one is a regional event"},
			{"pick": "Nothing — people are enough", "rule": "there are no monsters, which makes every threat somebody's decision"},
		],
	},
]


## Concrete premises for the Spark, so nobody is handed a blank box.
##
## "Describe your world" in an empty text area is the blank-page problem in its
## purest form, and what it mostly produces is a genre label — "dark fantasy with
## dragons" — which carries less information than the theme card the player is
## about to click anyway.
##
## These are the length and specificity a good answer has. Picking one is a real
## choice; rejecting all of them is also a signal; and the player who wanted the
## blank box still has it, now primed by six examples of what "specific" means.
##
## Written rather than generated, deliberately: generating six costs a model call
## at the exact moment the forge opens, and the blank page is a latency problem as
## much as a creative one. The upgrade path is to generate a seventh row in the
## background — it does not change the interaction.
const PREMISES := [
	"A drowned Venice of sky-whales and salvage guilds, melancholy but hopeful",
	"A city that rebuilt itself around the corpse of the god that fell on it",
	"Border country where two empires pretend not to be at war, and everyone lives on the pretence",
	"A generation ship whose passengers have forgotten it is moving",
	"A desert where the wells are owned by families that have not spoken in nine hundred years",
	"The last winter of a kingdom that has already lost and has not been told",
	"A mining town under a mountain that has begun, very slowly, to close",
	"An archipelago where every island keeps a different century",
	"A forest that regrows overnight, and the road crews who fight it for a living",
	"A plague city under quarantine, governed by the doctors who cannot leave either",
	"A frontier where the maps are sold by people who have never been there",
	"A cathedral-state built on a lie that three people still remember",
	"Salt flats where the tide comes in once a year and takes what it likes",
	"A trade port whose bank owns the army, the harbour and most of the population",
	"A valley where the dead are useful, and therefore never buried",
	"Sky-islands drifting apart, one bridge at a time",
	"A monastery brewing the only medicine, in a country that has started to want it",
	"A clockwork city where the machines were built by someone who is no longer answering",
]

## Six premises, plus the offer to write your own. `page` rotates through the pool
## so "show me different ones" is a real button rather than a reshuffle that can
## repeat what was just rejected.
static func premises(page: int) -> Array:
	var out: Array = []
	for i in 6:
		out.append(PREMISES[(page * 6 + i) % PREMISES.size()])
	return out


## The questions worth asking THIS world. Deterministic given the same inputs —
## no shuffling, because a player who backs up a stage should find the page they
## left, not a new one.
static func pick(idea: String, theme: Dictionary) -> Array:
	var lower := idea.to_lower()
	var title := str(theme.get("title", ""))
	var out: Array = []
	var relevant: Array = []
	for q in POOL:
		if _already_answered(q, lower):
			continue
		if q["id"] in ALWAYS:
			out.append(q)
		elif _applies(q, lower, title):
			relevant.append(q)
	# The always-on pair leads, then whatever this world actually earned, in pool
	# order. Pool order is authored: the sharper questions sit higher.
	out.append_array(relevant)
	return out.slice(0, ASK)


## True when the player's own premise already said it. A question the premise has
## answered is the single clearest signal that nobody read what you typed.
static func _already_answered(q: Dictionary, lower: String) -> bool:
	for w in q.get("answered_by", []):
		if lower.find(str(w)) >= 0:
			return true
	return false


static func _applies(q: Dictionary, lower: String, title: String) -> bool:
	var when: Dictionary = q.get("when", {})
	# No conditions means it fits any world — the generic-but-useful questions
	# (the road, the beasts) live here.
	if when.is_empty():
		return true
	if title != "" and title in when.get("not_theme", []):
		return false
	if title != "" and title in when.get("theme", []):
		return true
	for w in when.get("premise", []):
		if lower.find(str(w)) >= 0:
			return true
	return false

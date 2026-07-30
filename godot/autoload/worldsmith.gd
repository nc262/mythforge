extends Node
## The Worldsmith, in-process — the last creative helper off the backend.
##
## Expands a one-line idea into a playable world (name, lore, locations, cast,
## campaigns, bestiary, class reskins), or crafts a single campaign for a world
## that already exists. Four call sites, all through `Api.worldsmith()`, which
## now delegates here.
##
## WHAT THE SCHEMA DELETED. The server version was ~320 lines, and most of that
## was defending against a model that drops sections:
##
##   - `_ask()` retried every call once with "your previous answer omitted
##     required sections", doubling the wall clock on a bad box.
##   - Two RESCUE CALLS existed solely to re-ask for `locations` and `stories`
##     when the big call came back without them.
##   - `_clean()` unwrapped fields the model returned as a repr'd dict —
##     `"{'prompt': '…'}"` where a string was wanted.
##   - `_reskins()` returned null unless at least 8 of the 12 classes came back,
##     because they often did not.
##
## A grammar cannot omit a required key, cannot emit an object where a string
## belongs, and cannot stop an array below `minItems`. Every one of those guards
## was defending against a failure the constraint makes UNREACHABLE, so all four
## are gone rather than ported. What remains is clamping lengths, which is a
## taste decision the grammar has no opinion about.

## Length caps, carried over from the server so a chatty model cannot push a
## 4000-character "tagline" into a UI built for one line.
const CAP := {
	"name": 60, "kind": 40, "tagline": 160, "lore": 1200, "backdrop": 400,
	"title": 80, "premise": 500, "hook": 300, "role": 80, "appearance": 300,
	"persona": 600, "loc_lore": 200, "shop": 120, "desc": 300, "weakness": 200,
	"tactics": 200, "art": 300, "flavor": 400, "slots": 40, "class_name": 40,
}

const CLASSES := ["Fighter", "Barbarian", "Rogue", "Ranger", "Monk", "Paladin",
	"Wizard", "Sorcerer", "Cleric", "Druid", "Bard", "Warlock"]

const LOC_KINDS := ["tavern", "shop", "landmark", "wilds", "home"]
const TIERS := ["minor", "standard", "dire"]


## A plain string. NO `maxLength` — it is worse than useless in a grammar.
##
## JSON-Schema `maxLength: N` compiles to `char{0,N}` in GBNF, and llama.cpp's own
## grammar guide warns that large repetition counts cause "extremely slow
## sampling"; past ~2000 it emits GBNF that llama.cpp's own parser then rejects.
## `lore` was declared 1200, which bought a 1200-repetition rule and no bound the
## code was not already applying with `.left()` afterwards.
##
## The `cap_key` still selects which cap the ANSWER is clamped to — see `_cap`.
func _s(_cap_key: String) -> String:
	return '{"type":"string"}'


## Exactly-n arrays: minItems AND maxItems, because "exactly 3" in a prompt is a
## request and in a grammar is a fact.
func _arr(items: String, lo: int, hi: int) -> String:
	return '{"type":"array","minItems":%d,"maxItems":%d,"items":%s}' % [lo, hi, items]


func _obj(props: Dictionary) -> String:
	var keys: Array = props.keys()
	var parts: Array[String] = []
	for k in keys:
		parts.append('"%s":%s' % [k, props[k]])
	return '{"type":"object","required":["%s"],"properties":{%s}}' % [
		"\",\"".join(keys), ",".join(parts)]


func _enum(vals: Array) -> String:
	return '{"enum":["%s"]}' % "\",\"".join(vals)


func _loc_schema() -> String:
	# `shop` is required here on purpose. The server made it optional and then
	# backfilled "odds & ends" / "food & drink" when a shop or tavern arrived
	# without one; asking the model for it costs nothing and is better writing.
	return _obj({"name": _s("name"), "kind": _enum(LOC_KINDS),
		"lore": _s("loc_lore"), "shop": _s("shop")})


func _creature_schema() -> String:
	return _obj({"name": _s("name"), "tier": _enum(TIERS), "desc": _s("desc"),
		"weakness": _s("weakness"), "tactics": _s("tactics"), "art": _s("art")})


func _story_schema() -> String:
	return _obj({"title": _s("title"), "premise": _s("premise"), "hook": _s("hook")})


## The world-core ask, exposed so a probe can drive the REAL shape and prompt
## rather than a copy of them that might have drifted.
const CORE_TASK := "You design original worlds for a tabletop-style roleplay adventure " \
	+ "game. Write: `name`, a short world name; `kind`, a 2-4 word genre label; " \
	+ "`tagline`, one enticing sentence; `lore`, 3-4 sentences establishing the " \
	+ "world, its feel and what adventurers do there; `backdrop`, an image-" \
	+ "generation prompt for an empty atmospheric establishing scene with no " \
	+ "people; and `locations`, 5 to 7 places, each with a one-sentence `lore` and " \
	+ "a `shop` naming what it trades (for a landmark, wilds or home, say what can " \
	+ "be found or bartered there). Be specific and flavorful, never generic.\n\n"


func core_schema() -> String:
	return _obj({
		"name": _s("name"), "kind": _s("kind"), "tagline": _s("tagline"),
		"lore": _s("lore"), "backdrop": _s("backdrop"),
		"locations": _arr(_loc_schema(), 5, 7),
	})


func core_prompt_for(idea: String, pillar_line := "") -> String:
	return CORE_TASK + "The player wants a world like this: %s%s" % [
		idea.left(1000), pillar_line]


func _cap(v, key: String) -> String:
	return str(v).strip_edges().left(CAP[key])


func _pillars(fields: Dictionary) -> String:
	var parts: Array[String] = []
	for k in fields:
		var v := str(fields[k]).strip_edges()
		if v != "":
			parts.append("%s: %s" % [k, v.left(120)])
	if parts.is_empty():
		return ""
	return "\nWorld pillars the player chose — honor ALL of them: %s" % "; ".join(parts).left(600)


## THINK, THEN SERIALISE. Two calls, and the split is the whole point.
##
## Asking one grammar-constrained call to invent a world and shape it at the same
## time produced grammar-valid word salad, because the schema preset replaces the
## sampler with raw distribution sampling (docs/LocalLLM-Tuning.md). So:
##
##   1. `prose()` writes it, with top-k/top-p/temperature/penalties.
##   2. `complete_json()` copies that prose into the schema — a low-entropy job,
##      which is the regime where the constrained sampler is reliable, and
##      exactly what codex/quests/world-tick already do all day.
##
## Two calls at ~2 s beat one at 98 s that fails. Returns {} when unusable, which
## the caller turns into a status the forge already knows how to show. No retry:
## the server's retry existed to re-ask for dropped keys, and a required key
## cannot be dropped.
func _ask(prompt: String, schema: String) -> Dictionary:
	var thought := await LocalGM.prose(prompt)
	if thought.strip_edges() == "":
		return {}
	var raw := await LocalGM.complete_json(
		"Copy the following into the required fields. Use ONLY what it says — do "
		+ "not invent, summarise or improve anything.\n\n" + thought, schema)
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


# ── The two modes ───────────────────────────────────────────────────────────
func forge(payload: Dictionary) -> Dictionary:
	if not LocalGM.available():
		return {"_status": 0}
	var idea := str(payload.get("idea", "")).strip_edges()
	if idea == "":
		return {"_status": 400}
	if str(payload.get("mode", "world")) == "story":
		return await _story(idea, payload.get("world", {}))
	return await _world(idea, payload)


func _story(idea: String, w) -> Dictionary:
	var world: Dictionary = w if w is Dictionary else {}
	var r := await _ask(
		"You craft campaign premises for a tabletop-style roleplay adventure. Given "
		+ "the world and the player's idea, write: `title`, a short evocative campaign "
		+ "name; `premise`, 2-3 sentences giving the situation, the stakes and the "
		+ "hook, written to entice; and `hook`, one vivid present-tense sentence "
		+ "describing the exact opening scene the GM sets. Fit the world's tone.\n\n"
		+ "World: %s — %s. %s\n\nThe player wants a campaign about: %s" % [
			str(world.get("name", "an original world")), str(world.get("kind", "")),
			str(world.get("lore", "")).left(600), idea.left(800)],
		_story_schema())
	if _cap(r.get("title", ""), "title") == "":
		return {"_status": 502}
	return {
		"title": _cap(r["title"], "title"),
		"premise": _cap(r.get("premise", ""), "premise"),
		"hook": _cap(r.get("hook", ""), "hook"),
		"_status": 200,
	}


func _world(idea: String, payload: Dictionary) -> Dictionary:
	var prior: Dictionary = payload.get("prior", {}) if payload.get("prior") is Dictionary else {}
	var refining := str(prior.get("name", "")) != ""
	var fields: Dictionary = payload.get("fields", {}) if payload.get("fields") is Dictionary else {}
	var pillar_line := _pillars(fields)

	# ── The world's core ────────────────────────────────────────────────────
	var schema := core_schema()
	var core: Dictionary
	if refining:
		var core_slice := {}
		for k in ["name", "kind", "tagline", "lore", "backdrop", "locations"]:
			core_slice[k] = prior.get(k)
		core = await _ask(CORE_TASK + "Current world core:\n%s\n\nRevise it per these "
			% JSON.stringify(core_slice).left(2000)
			+ "instructions, keeping everything not mentioned: %s" % idea.left(800),
			schema)
	else:
		core = await _ask(core_prompt_for(idea, pillar_line), schema)
	if _cap(core.get("name", ""), "name") == "":
		return {"_status": 502}

	var core_name := _cap(core["name"], "name")
	var core_lore := str(core.get("lore", "")).left(600)
	var world_line := "The world: %s — %s. %s%s" % [
		core_name, str(core.get("kind", "")), core_lore, pillar_line]

	# ── Its people and its campaigns ────────────────────────────────────────
	# On a REFINE this call also revises the bestiary, because the player's
	# instruction may be about the creatures. On a fresh forge the bestiary gets
	# its own call below, so this one stays small.
	var life_props := {
		"cast": _arr(_obj({"name": _s("name"), "role": _s("role"),
			"appearance": _s("appearance"), "persona": _s("persona")}), 3, 3),
		"stories": _arr(_story_schema(), 2, 2),
	}
	if refining:
		life_props["creatures"] = _arr(_creature_schema(), 3, 3)
	var life_task := "You populate a tabletop roleplay world with people and campaigns. " \
		+ "Write `cast`, 3 characters, each with a `role`, an `appearance` written as " \
		+ "an image-generation portrait prompt, and a `persona` of 2-3 sentences in " \
		+ "second person ('You are …') giving their voice, personality and how they " \
		+ "speak; and `stories`, 2 campaigns, each with a `premise` of 2-3 sentences " \
		+ "and a `hook` that is one vivid opening-scene sentence" \
		+ (", and `creatures`, 3 setting-specific threats" if refining else "") \
		+ ". Be specific and flavorful, never generic.\n\n"
	var life: Dictionary
	if refining:
		var life_slice := {}
		for k in ["cast", "stories", "creatures"]:
			life_slice[k] = prior.get(k)
		life = await _ask(life_task + "%s\nCurrent people & threats:\n%s\n\nRevise them "
			% [world_line, JSON.stringify(life_slice).left(2200)]
			+ "per these instructions, keeping everything not mentioned: %s" % idea.left(800),
			_obj(life_props))
	else:
		life = await _ask(life_task + "%s\nThe player's original idea: %s\n\nInvent its "
			% [world_line, idea.left(600)] + "cast and campaigns.", _obj(life_props))

	var out := {
		"name": core_name,
		"kind": _cap(core.get("kind", ""), "kind") if str(core.get("kind", "")).strip_edges() != "" else "Adventure",
		"tagline": _cap(core.get("tagline", ""), "tagline"),
		"lore": _cap(core.get("lore", ""), "lore"),
		"backdrop": _cap(core.get("backdrop", ""), "backdrop"),
		"cast": _clean_cast(life.get("cast", [])),
		"stories": _clean_stories(life.get("stories", [])),
		"locations": _clean_locs(core.get("locations", [])),
		"creatures": _clean_creatures(life.get("creatures", [])),
		"reskins": null,
		"_status": 200,
	}

	if refining:
		# The class reskins are not part of what a refine asks about, so they
		# carry through untouched rather than being regenerated into new names
		# the player never asked to change.
		if prior.get("reskins") is Dictionary:
			out["reskins"] = prior["reskins"]
		return out

	# ── A fresh world gets its own bestiary and its own words for the classes ─
	var beasts := await _ask(
		"You invent monsters for a tabletop roleplay world. Write `creatures`, 6 "
		+ "distinct threats, each with a `desc` of 1-2 sentences, a `weakness` saying "
		+ "in one sentence how a clever hero beats it, `tactics` saying in one sentence "
		+ "how it fights, and `art` written as an image-generation prompt. Vary the "
		+ "tiers. Every creature must belong to THIS world specifically, never generic "
		+ "fantasy filler.\n\n%s\nInvent its bestiary." % world_line,
		_obj({"creatures": _arr(_creature_schema(), 6, 6)}))
	out["creatures"] = _clean_creatures(beasts.get("creatures", []))

	# NO SCHEMA HERE — this one is parsed, not extracted.
	#
	# The prose half is flawless and takes ~2 s: twelve lines of "- Fighter:
	# Kraelion". The extraction half was a schema with a nested twelve-key object,
	# which is the same large-schema failure as the world core, and it burned the
	# full 180 s deadline every run (a world went 66 s -> 236 s).
	#
	# The keys are a CONSTANT. When the shape is a list whose labels you already
	# know, parsing it is deterministic, instant, and cannot derail — asking a
	# model to serialise it is work being paid for twice.
	#
	# The prompt still spells the shape out, because the schema is not there to
	# imply it: asked for "`flavor`, `slots` and `names`" the model produced a
	# flavor and a slots term PER CLASS, which is a fair reading of a prompt
	# written for a shape the model cannot see.
	var rsk := await LocalGM.prose(
		"You translate the standard adventurer classes into a specific world's own "
		+ "language. Answer in exactly three parts.\n"
		+ "PART 1 — one or two sentences on how supernatural power manifests in this "
		+ "world. The GM will describe ALL casting this way.\n"
		+ "PART 2 — a single 1-3 word term this world uses for spell slots.\n"
		+ "PART 3 — all twelve classes, one per line as `Class: Title`, each title "
		+ "1-3 words in this world's language, in this order and no other:\n%s\n\n%s"
		% ["\n".join(CLASSES), world_line])
	var rs := parse_reskins(rsk)
	# All twelve or none. A partial map means the classes the parse missed keep
	# their classic names while their neighbours get world ones, which reads like
	# a bug rather than a world.
	if (rs.get("names", {}) as Dictionary).size() == CLASSES.size():
		out["reskins"] = rs
	return out


## The smith's one question back — see docs/WorldForge-UX.md, change 5.
##
## After a world is struck, ask about the thing the world left OPEN. The forge
## stops being a form the player filled in and becomes something they are in
## conversation with, for one round and one click.
##
## THINK-THEN-SERIALISE, like everything else. I first wrote this as one flat
## three-key schema, reasoning that the cliff was nesting and that three short
## strings sat safely below it. Measured: **95827 ms**, and the "answers" came
## back as paragraphs about a specific NPC rather than answers to a question.
##
## The cliff is not only nesting, it is TOTAL GENERATED LENGTH — under grammar
## plus `Dist` there is no penalty pulling generation to a close, so a field the
## code will clamp to 160 characters is under no obligation to stop there, and
## every extra token is one more chance to wander. Nothing gets to invent under a
## grammar, however small the schema looks.
##
## Returns {} rather than a placeholder when it has nothing to ask — a forge that
## always has a question will eventually ask a stupid one, and the stage simply
## does not show the row.
func ask_back(world: Dictionary) -> Dictionary:
	if not LocalGM.available() or str(world.get("name", "")) == "":
		return {}
	var cast_names: Array[String] = []
	for c in world.get("cast", []):
		if c is Dictionary:
			cast_names.append(str(c.get("name", "")))
	var parsed := await _ask(
		"You are the smith who just forged this world. Ask the player ONE closed "
		+ "question about something the world leaves genuinely open — a power you "
		+ "gave someone without saying whether it is deserved, a bargain without "
		+ "saying who got the better of it. Name the specific thing you are asking "
		+ "about.\n\nAnswer in exactly three lines and nothing else:\n"
		+ "QUESTION: one sentence, at most 20 words, ending in a question mark.\n"
		+ "A: one possible answer, AT MOST SIX WORDS.\n"
		+ "B: the opposing answer, AT MOST SIX WORDS.\n\n"
		+ "A and B are answers to the question, not descriptions — if the question "
		+ "is whether the wardens are trusted, A is \"Trusted\" and B is \"Merely "
		+ "obeyed\". Never ask an open question and never ask the player to describe "
		+ "anything.\n\nThe world: %s — %s. %s\nIts people: %s\n"
		% [str(world.get("name", "")), str(world.get("kind", "")),
			str(world.get("lore", "")).left(600), ", ".join(cast_names)],
		_obj({"question": _s("premise"), "a": _s("kind"), "b": _s("kind")}))
	if parsed.is_empty():
		return {}
	var q := _strip_label(_cap(parsed.get("question", ""), "premise"), "QUESTION")
	var a := _strip_label(_cap(parsed.get("a", ""), "kind"), "A")
	var b := _strip_label(_cap(parsed.get("b", ""), "kind"), "B")
	# Two identical options is not a choice, and a button the width of the screen
	# is not an option — an answer that arrives as a paragraph means the model
	# described the world instead of answering, so drop the whole row.
	if q == "" or a == "" or b == "" or a.to_lower() == b.to_lower():
		return {}
	if a.length() > 48 or b.length() > 48:
		return {}
	return {"question": q, "a": a, "b": b}


## Drop the prose format's own label off an extracted field.
##
## The prose prompt asks for "A: one possible answer", and the extraction copies
## the line faithfully — label included — so the button read "A: A sea goddess's
## silent compact." Faithful copying is exactly what was asked for; the label has
## to come off on this side.
func _strip_label(s: String, label: String) -> String:
	# LITERAL dash characters — RegEx is PCRE2, where `—` is not an escape.
	# This is the second time that has bitten in this file; see parse_reskins.
	var re := RegEx.create_from_string("(?i)^\\**%s\\**[ \\t]*[-:.—–][ \\t]*" % label)
	return re.sub(s.strip_edges(), "").strip_edges()


## Pull `{flavor, slots, names}` out of the reskins prose. Public because it is
## the load-bearing half of that call and self_check exercises it directly — a
## regex over model output is exactly the thing that quietly stops matching.
func parse_reskins(text: String) -> Dictionary:
	var names := {}
	for c in CLASSES:
		# Anchored to the start of a line so a class merely NAMED in the prose
		# cannot match, and tolerant of whichever bullet and separator the model
		# picks on the day: "- Fighter: Kraelion", "1. Barbarian — Vorgathor",
		# "**Rogue**: Shadewalker".
		# The punctuation classes hold LITERAL characters, not \uXXXX escapes.
		# RegEx is PCRE2, where `\u` is not an escape at all — it silently matched
		# nothing, and every one of these lines came back unparsed.
		var re := RegEx.create_from_string(
			"(?im)^[ \\t]*(?:[-*•][ \\t]*)?(?:\\d+[.)][ \\t]*)?\\**%s\\**[ \\t]*[-:—–][ \\t]*(.+)$" % c)
		var m := re.search(text)
		if m == null:
			continue
		var nm := m.get_string(1).strip_edges().lstrip("\"*_ ").rstrip("\"*_ .")
		if nm != "":
			names[c] = nm.left(CAP["class_name"])
	return {
		"flavor": _cap(_part(text, 1), "flavor"),
		"slots": _cap(_part(text, 2), "slots"),
		"names": names,
	}


## One numbered PART of a prose answer, without its heading.
func _part(text: String, n: int) -> String:
	var re := RegEx.create_from_string(
		"(?is)PART[ \\t]*%d\\**[ \\t]*[-—:]?[ \\t]*(.*?)(?=\\**PART[ \\t]*%d|$)" % [n, n + 1])
	var m := re.search(text)
	if m == null:
		return ""
	var body := m.get_string(1).strip_edges().lstrip("*_ \n").rstrip("*_ \n")
	# PART 2 is a single term and the model likes to wrap it in a sentence
	# ("The term for spell slots is \"Echoes.\""). Prefer the quoted word.
	if n == 2:
		var q := RegEx.create_from_string("[\"“]([^\"”]{1,40})[\"”]").search(body)
		if q != null:
			return q.get_string(1).strip_edges().rstrip(".")
	return body


# ── Shaping (length caps only — the grammar owns types and presence) ────────
func _clean_cast(items) -> Array:
	var out: Array = []
	for c in (items if items is Array else []):
		if c is Dictionary and str(c.get("name", "")).strip_edges() != "":
			out.append({
				"name": _cap(c["name"], "name"),
				"role": _cap(c.get("role", ""), "role"),
				"appearance": _cap(c.get("appearance", ""), "appearance"),
				"persona": _cap(c.get("persona", ""), "persona"),
			})
	return out


func _clean_stories(items) -> Array:
	var out: Array = []
	for s in (items if items is Array else []):
		if s is Dictionary and str(s.get("title", "")).strip_edges() != "":
			out.append({
				"title": _cap(s["title"], "title"),
				"premise": _cap(s.get("premise", ""), "premise"),
				"hook": _cap(s.get("hook", ""), "hook"),
			})
	return out


func _clean_locs(items) -> Array:
	var out: Array = []
	for p in (items if items is Array else []):
		if p is Dictionary and str(p.get("name", "")).strip_edges() != "":
			out.append({
				"name": _cap(p["name"], "name"),
				"kind": str(p.get("kind", "landmark")),
				"lore": _cap(p.get("lore", ""), "loc_lore"),
				"shop": _cap(p.get("shop", ""), "shop"),
			})
	return out


func _clean_creatures(items) -> Array:
	var out: Array = []
	for c in (items if items is Array else []):
		if c is Dictionary and str(c.get("name", "")).strip_edges() != "":
			out.append({
				"name": _cap(c["name"], "name"),
				"tier": str(c.get("tier", "standard")),
				"desc": _cap(c.get("desc", ""), "desc"),
				"weakness": _cap(c.get("weakness", ""), "weakness"),
				"tactics": _cap(c.get("tactics", ""), "tactics"),
				"art": _cap(c.get("art", ""), "art"),
			})
	return out

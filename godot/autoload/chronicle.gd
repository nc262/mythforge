extends Node
## Chronicle — the anti-amnesia layer: pinpoint campaign memory (embedded
## beats + recall), the cast codex, and the quest log. Results persist in
## world-state kinds and fold back into the GM's context each turn.
##
## All three run in this process, on the narrator's own model. There is
## deliberately no second path: the narrator already fails loudly without a local
## model (api_client.narrator_missing), so a quieter degradation here would only
## hide the same fault twice.

const CODEX_EVERY := 6  # player turns between codex/quest extractions

## Grammar-constrained, so the model cannot emit a preamble or a ```json fence
## and there is nothing to extract. `enum` also makes an invalid disposition or
## status UNGENERATABLE rather than something to normalise afterwards — measured
## 6.7x faster than asking politely for JSON (LocalGM.complete_json).
##
## Every string carries `maxLength` — declared, not relied on; see the note on
## Worldsmith._s() for what this build actually does with it. The numbers match
## the caps the answer is clamped to anyway.
const CODEX_SCHEMA := '{"type":"object","required":["npcs"],"properties":{"npcs":' \
	+ '{"type":"array","maxItems":12,"items":{"type":"object",' \
	+ '"required":["name","role","disposition","note","goal","appearance"],"properties":{' \
	+ '"name":{"type":"string","maxLength":60},"role":{"type":"string","maxLength":60},' \
	+ '"disposition":{"enum":["ally","friendly","neutral","wary","hostile"]},' \
	+ '"note":{"type":"string","maxLength":240},"goal":{"type":"string","maxLength":160},' \
	+ '"appearance":{"type":"string","maxLength":240}}}}}}'

const QUESTS_SCHEMA := '{"type":"object","required":["quests"],"properties":{"quests":' \
	+ '{"type":"array","maxItems":10,"items":{"type":"object",' \
	+ '"required":["title","desc","status"],"properties":{' \
	+ '"title":{"type":"string","maxLength":80},"desc":{"type":"string","maxLength":240},' \
	+ '"status":{"enum":["active","done"]}}}}}}'

## `newQuest` is deliberately NOT required — most days do not produce one, and a
## required object would make the model invent one every long rest.
const TICK_SCHEMA := '{"type":"object","required":["events"],"properties":{' \
	+ '"events":{"type":"array","maxItems":3,"items":{"type":"string","maxLength":240}},' \
	+ '"newQuest":{"type":"object","required":["title","desc"],"properties":{' \
	+ '"title":{"type":"string","maxLength":80},"desc":{"type":"string","maxLength":240}}}}}'

var transcript: Array = []  # [{role, content}] — this adventure, this session
var _player_turns := 0

signal chronicle_updated  # codex/quests refreshed — panels may re-render


func reset() -> void:
	transcript = []
	_player_turns = 0


## Called after every completed exchange: store a beat, batch the extractors.
func record(player_msg: String, gm_reply: String) -> void:
	if player_msg.strip_edges() == "" or gm_reply.strip_edges() == "":
		return
	transcript.append({"role": "user", "content": player_msg})
	transcript.append({"role": "assistant", "content": gm_reply})
	if transcript.size() > 60:
		transcript = transcript.slice(-60)
	_player_turns += 1
	var beat := "Player: %s\nGM: %s" % [player_msg.left(300), gm_reply.left(500)]
	# The embedding runs on the same Vulkan device as the narrator; the beat never
	# leaves the machine or the process.
	LocalMemory.add_beat(GameState.cid(), beat, int(GameState.clock().get("day", 1)))
	_after_turn(player_msg, gm_reply, _player_turns % CODEX_EVERY == 0)


## The trouble read, then (on its cadence) the codex and quests — in that order,
## on the one JSON node, so the three never contend.
func _after_turn(player_msg: String, gm_reply: String, chronicle_due: bool) -> void:
	await read_trouble(player_msg, gm_reply)
	if chronicle_due:
		await _update_chronicle()


## ── THE PLAYER ASKS A TOWN FOR SOMETHING NOT ON ITS MAP ──────────────────────
## The GM decides whether this town has one; `GameState.answer_ask` decides
## whether the answer is legal. Schema-constrained, because the caller needs a
## decision, not prose — and the prose it does write is one in-world sentence.
## KIND IS REQUIRED. Measured with the real narrator: five asks, five yeses, and
## `kind` left out of every one, so every answer landed as a generic landmark and
## the size gate had nothing to bite on.
const ASK_SCHEMA := '{"type":"object","required":["here","kind","name","ward","answer"],"properties":{' 	+ '"here":{"type":"boolean"},"kind":{"enum":["inn","tavern","store","smith","alchemist",' 	+ '"temple","fence","sage","guild","home","landmark"]},' 	+ '"name":{"type":"string","maxLength":60},"ward":{"type":"integer"},' 	+ '"lore":{"type":"string","maxLength":160},"answer":{"type":"string","maxLength":240}}}'


func ask_after(town: String, town_kind: String, query: String) -> Dictionary:
	if not LocalGM.available() or query.strip_edges() == "":
		return {}
	var brief := LocalMap.for_place(GameState.world_id(), town, town_kind).brief()
	# THE WORLD ITSELF, because the narrator said yes to a SPACEPORT in a fantasy
	# village: with only the town in front of it, nothing in the prompt said what kind
	# of world this is, and a model with no grounds to refuse will not refuse.
	var world := {}
	for w in Rules.builtin_worlds() + GameState.global_get("cworlds", []):
		if w is Dictionary and str(w.get("id", "")) == GameState.world_id():
			world = w
			break
	var raw := await LocalGM.complete_json(
		"You are the Game Master of %s, %s. %s" % [str(world.get("name", "this world")),
			str(world.get("kind", "")), str(world.get("lore", "")).left(320)]
		+ "%s

" % brief
		+ "The player is in %s, asking after: %s

" % [town, query.strip_edges().left(120)]
		+ "Decide whether this place HAS such a thing. `here` is true only if it fits a "
		+ "place of this size and character, serves the story, and is not one of the places "
		+ "already listed above. If true: `name` it in this world's voice, choose the closest "
		+ "`kind`, and give the `ward` number of the quarter it stands in, from the list above. "
		+ "Two examples, in a high-fantasy village: \"a blacksmith\" -> here true, kind smith. "
		+ "\"a spaceport\" -> here FALSE, because nothing in this world flies; answer: "
		+ "\"Folk here would stare at you — there is no such thing in this valley.\" "
		+ "SAY NO WHEN IT DOES NOT BELONG. `here` is false for anything out of this world's "
		+ "genre, anything grander than a place this size would hold, and anything this tale "
		+ "has no room for — a no is a good answer and the commonest one. "
		+ "`answer` is ONE short sentence said to the player in the world's own voice — where "
		+ "to find it and what it is like, or why there is no such thing here. Never mention "
		+ "rules, numbers or tags.",
		ASK_SCHEMA, 25.0)   # somebody is standing at the box waiting for this
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


## ── DID THAT TURN TOUCH THE TROUBLE? ─────────────────────────────────────────
## MEASURED 2026-09-17 (tests/town_gm_probe, real narrator, a secret trouble,
## four turns of the player investigating it): the narrator kept the secret and
## planted traces in prose — worried faces at the well, a bitter tang at the mill
## — and wrote ZERO [[clue]] tags and marked ZERO rolls trouble=1. The engine
## side was correct and never fed. LocalLLM-Tuning.md already says why: one call
## should not both invent and serialise. So the narrator writes the scene, and
## this reads it afterwards: one small schema call, only on turns where the town
## the party stands in has a trouble running.
const TROUBLE_READ_SCHEMA := '{"type":"object","required":["lead","working_it"],"properties":{' 	+ '"lead":{"type":"string","maxLength":160},"working_it":{"type":"boolean"}}}'


func read_trouble(player_msg: String, gm_reply: String) -> Dictionary:
	var here := GameState.here()
	var t := GameState.trouble_at(here)
	if not LocalGM.available():
		return {}
	if t.is_empty() or GameState.trouble_spent(t):
		return await read_new_trouble(player_msg, gm_reply)
	var clues: Array = t.get("clues") if t.get("clues") is Array else []
	var raw := await LocalGM.complete_json(
		"A trouble is running in %s: %s.
Leads the player already has: %s

" % [here, t.get("what", ""),
			"; ".join(clues) if not clues.is_empty() else "(none)"]
		+ "Read ONLY this exchange.
Player: %s
Narrator: %s

" % [player_msg.left(400), gm_reply.left(1200)]
		+ "`lead`: if the player saw, heard or learned something concrete in this exchange that points "
		+ "toward the trouble and is not already a lead, one sentence describing what they found — "
		+ "only what the exchange shows, never the hidden truth itself. Otherwise an empty string. "
		+ "`working_it`: true only if the player was deliberately acting on or investigating this trouble.",
		TROUBLE_READ_SCHEMA)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	GameState.apply_trouble_read(here, parsed)
	return parsed


## ── DID THAT TURN START ONE? ─────────────────────────────────────────────────
## MEASURED 2026-11-02 (town_gm_probe `-- calm`, a town with no trouble, 8
## turns): ZERO [[trouble]] tags, while the prose set one up in 3 — press-gangs
## on the quay, told by a trader and a priestess. Nothing else ever starts a
## trouble, so the clocks, the leads and `read_trouble` above all starved. Same
## cure: the narrator tells it, this reads it. Only in a settled place with no
## trouble running, so a town that has one costs no extra call.
const NEW_TROUBLE_SCHEMA := '{"type":"object","required":["started","what","fallout"],"properties":{' 	+ '"started":{"type":"boolean"},"what":{"type":"string","maxLength":200},' 	+ '"fallout":{"enum":["road","trade","prices","law"]},"title":{"type":"string","maxLength":50}}}'


func read_new_trouble(player_msg: String, gm_reply: String) -> Dictionary:
	var here := GameState.here()
	var settled := false
	for p in GameState.places():
		if p is Dictionary and str(p.get("name", "")) == here:
			settled = LocalMap.SETTLED_KINDS.has(str(p.get("kind", "")))
			break
	if not settled:
		return {}
	var raw := await LocalGM.complete_json(
		"The party is in %s.\nRead ONLY this exchange.\nPlayer: %s\nNarrator: %s\n\n" % [
			here, player_msg.left(400), gm_reply.left(1200)]
		+ "`started`: true only if the NARRATOR'S words establish an ongoing problem IN %s itself " % here
		+ "that will get worse unless someone acts — a threat, a crime, a scarcity, a feud people here are "
		+ "suffering now. False for ordinary hardship, a mood, a rumour about somewhere else, or anything the "
		+ "exchange does not actually say. If true: `what`, ONE short clause (under 15 words) saying what is going wrong, in the "
		+ "narrator's terms; `fallout`, what it costs the town if nobody stops it (road: the roads out turn "
		+ "dangerous / trade: the shops shut / prices: prices climb / law: the streets go lawless); `title`, a "
		+ "short name for it.",
		NEW_TROUBLE_SCHEMA)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or not bool(parsed.get("started", false)):
		return {}
	return apply_new_trouble(here, parsed)


## The engine's half of the read, apart so `self_check` can run it with no model.
func apply_new_trouble(here: String, parsed: Dictionary) -> Dictionary:
	# Measured: a constrained call returned what="trouble" once, and once a line
	# of narration ("You overhear mentions of…"). Neither is a trouble to record.
	# The cap is a backstop: at 120 it cut two of four mid-word, one into a stray glyph.
	var what := str(parsed.get("what", "")).strip_edges().rstrip(",;: ")
	if what.split(" ", false).size() < 4 or what.to_lower().begins_with("you "):
		parsed["why"] = "not a trouble: '%s'" % what
		return parsed
	# reach=town: the player has just HEARD it, so it is known, not a secret.
	var why := GameState.set_trouble(here, what, 6, "town",
		{"fallout": str(parsed.get("fallout", "")), "title": str(parsed.get("title", ""))})
	parsed["why"] = why
	if why == "":
		GameState.notice_troubles()
	return parsed


## The beats most relevant to this moment. Empty when the encoder is missing —
## the game plays on without pinpoint recall, which is the honest degradation.
func recall(query: String) -> Array:
	return await LocalMemory.recall(GameState.cid(), query, 4)


func recall_text(beats: Array) -> String:
	if beats.is_empty():
		return ""
	var lines: Array[String] = []
	for b in beats:
		lines.append("• " + str(b.get("text", b)).replace("\n", " ").left(240))
	return "Relevant past events (canon — honor them): %s" % " ".join(lines)


## The last 44 messages as plain dialogue, which is what both extractors read.
## Strips the leading [tag] the GM's pipeline adds, so the model chronicles the
## story rather than the markup.
func _convo() -> String:
	var cname := str(GameState.character.get("name", "the story"))
	var lines: Array[String] = []
	for m in transcript.slice(-44):
		var content := str(m.get("content", "")).strip_edges()
		if content == "":
			continue
		content = RegEx.create_from_string("^\\[[^\\]]*\\]\\s*").sub(content, "")
		lines.append("%s: %s" % [cname if m.get("role") == "assistant" else "Player", content])
	return "\n".join(lines).left(7000)


## Codex then quests, SEQUENTIALLY. They share LocalGM's one JSON chat node, and
## firing both off the same turn used to be two HTTP requests that could overlap
## freely — in-process they cannot.
func _update_chronicle() -> void:
	# Checked once here rather than tolerated twice below: without it the harnesses
	# build both prompts and then parse "" as JSON, which logs a real-looking
	# `Parse JSON failed` error on every sixth turn of a passing run.
	if not LocalGM.available():
		return
	await _update_codex()
	await _update_quests()


func _update_codex() -> void:
	var current = GameState.state.get("codex", [])
	var existing := "(none yet)"
	if current is Array and not current.is_empty():
		var parts: Array[String] = []
		for n in current:
			if n is Dictionary and str(n.get("name", "")) != "":
				parts.append("%s (%s, %s): %s [wants: %s]" % [n["name"], str(n.get("role", "")),
					str(n.get("disposition", "neutral")), str(n.get("note", "")), str(n.get("goal", ""))])
		if not parts.is_empty():
			existing = "; ".join(parts)
	var raw := await LocalGM.complete_json(
		"You maintain a cast codex of non-player characters the player has MET in an "
		+ "ongoing roleplay. Merge the EXISTING codex with the LATEST events: update "
		+ "dispositions, notes and goals as things shift. `disposition` is toward the "
		+ "player; `goal` is that character's own agenda; `appearance` is a short "
		+ "comma-separated visual anchor for a portrait. Include ONLY named characters "
		+ "the player has actually encountered, and never invent one the story does not "
		+ "contain.\n\nExisting codex:\n%s\n\nLatest events:\n%s" % [existing, _convo()],
		CODEX_SCHEMA)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or not (parsed.get("npcs") is Array):
		return
	var out: Array = []
	for n in parsed["npcs"]:
		if not (n is Dictionary) or str(n.get("name", "")).strip_edges() == "":
			continue
		out.append({
			"name": str(n.get("name", "")).strip_edges().left(60),
			"role": str(n.get("role", "")).strip_edges().left(60),
			"disposition": str(n.get("disposition", "neutral")),
			"note": str(n.get("note", "")).strip_edges().left(240),
			"goal": str(n.get("goal", "")).strip_edges().left(160),
			"appearance": str(n.get("appearance", "")).strip_edges().left(240),
		})
	GameState.save_kind("codex", out)
	chronicle_updated.emit()


func _update_quests() -> void:
	var current = GameState.state.get("quests", [])
	var existing := "(none yet)"
	if current is Array and not current.is_empty():
		var parts: Array[String] = []
		for q in current:
			if q is Dictionary and str(q.get("title", "")) != "":
				parts.append("%s [%s]: %s" % [q["title"], str(q.get("status", "active")),
					str(q.get("desc", ""))])
		if not parts.is_empty():
			existing = "; ".join(parts)
	var raw := await LocalGM.complete_json(
		"You maintain a quest log for an ongoing roleplay adventure. Track the goals, "
		+ "missions and promises the player has taken on. Merge the EXISTING quests "
		+ "with the LATEST events, mark a quest done when it is clearly resolved, and "
		+ "never invent a quest the story does not imply. `desc` is one sentence on the "
		+ "objective and its current state.\n\nExisting quests:\n%s\n\nLatest events:\n%s"
		% [existing, _convo()],
		QUESTS_SCHEMA)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or not (parsed.get("quests") is Array):
		return
	GameState.save_kind("quests", merge_quests(current if current is Array else [], parsed["quests"]))
	chronicle_updated.emit()


## The model's rewrite of the log, merged over what the log already holds.
func merge_quests(current: Array, from_model: Array) -> Array:
	var out: Array = []
	# THE ENGINE'S QUESTS ARE NOT THE MODEL'S TO REWRITE. A trouble's quest is
	# opened, updated and closed by `GameState` from the clock itself; this pass
	# replaces the whole log, so without this it would drop them, or mark "done" a
	# trouble whose clock is still running. Kept as they are, and any model entry
	# carrying the same title is the model restating one.
	var engine_titles: Array = []
	for q in current:
		if q is Dictionary and q.has("trouble"):
			out.append(q)
			engine_titles.append(str(q.get("title", "")).to_lower())
	for q in from_model:
		if not (q is Dictionary) or str(q.get("title", "")).strip_edges() == "":
			continue
		if engine_titles.has(str(q.get("title", "")).strip_edges().to_lower()):
			continue
		out.append({
			"title": str(q.get("title", "")).strip_edges().left(80),
			"desc": str(q.get("desc", "")).strip_edges().left(240),
			"status": str(q.get("status", "active")),
		})
	return out


## A day passes off-screen. Returns {"events": [String], "newQuest": Dictionary}
## — small developments driven by what the NPCs want and what threads are open.
##
## A new quest, if one appears, is FILED HERE rather than handed back for the
## caller to remember to save. The old server route returned one and game.gd
## dropped it on the floor for the same reason it dropped the events: it read
## keys ("tick"/"aside"/"text") the route never sent, so this feature has been
## returning an empty string since it was written.
func world_tick() -> Dictionary:
	var empty := {"events": [], "newQuest": {}}
	if transcript.is_empty() or not LocalGM.available():
		return empty
	var quests = GameState.state.get("quests", [])
	var codex = GameState.state.get("codex", [])
	var active: Array[String] = []
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("status", "active")) == "active" and str(q.get("title", "")) != "":
				active.append(str(q["title"]))
	var goals: Array[String] = []
	if codex is Array:
		for n in codex:
			if n is Dictionary and str(n.get("goal", "")) != "" and str(n.get("name", "")) != "":
				goals.append("%s wants %s" % [n["name"], n["goal"]])
	# THE TOWNS' OWN TROUBLES COUNT AS THINGS IN MOTION, and they are the best
	# material this call has: a clock says what is going wrong, WHERE, and how far
	# along it is — which is exactly the "small and reactive" development this
	# prompt asks for, and something it could previously only get from an NPC's
	# stated goal.
	var troubles: Array[String] = []
	for t in GameState.running_troubles():
		if str(t["what"]) == "":
			continue
		troubles.append("%s: %s (%d of %d%s)" % [t["place"], t["what"],
			int(t["filled"]), int(t["size"]),
			", SECRET — only traces may surface" if GameState.trouble_known(str(t["place"])).is_empty() else ""])
	# Nothing in motion yet — a tick here would be the model inventing a world
	# rather than advancing one.
	if active.is_empty() and goals.is_empty() and troubles.is_empty():
		return empty
	var raw := await LocalGM.complete_json(
		"You simulate a living world between scenes in an ongoing roleplay. A day has "
		+ "passed off-screen. Give 1 to 3 short, concrete developments that plausibly "
		+ "happened while the player was elsewhere — each driven by an NPC pursuing "
		+ "their goal or by an open thread progressing. Small and reactive: a rumour, "
		+ "a rival's move, a quiet change in town. NOT major plot twists, and NEVER act "
		+ "for the player. One sentence each. Add `newQuest` ONLY if these developments "
		+ "naturally create a fresh opportunity or threat the player could choose to "
		+ "pursue.\n\nStory so far:\n%s\n\nOpen quests: %s\n\nNPC agendas: %s\n\n"
		% [_convo() if not transcript.is_empty() else "(just beginning)",
			"; ".join(active) if not active.is_empty() else "(none)",
			"; ".join(goals) if not goals.is_empty() else "(no known agendas)"]
		+ ("Trouble brewing (the count is how far gone it is; PREFER THESE for your "
			+ "developments, and say what WORSENED rather than restating the problem): "
			+ "%s

" % "; ".join(troubles) if not troubles.is_empty() else "")
		+ "Day %d has dawned. What happened off-screen?" % int(GameState.clock().get("day", 1)),
		TICK_SCHEMA)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return empty
	var events: Array[String] = []
	if parsed.get("events") is Array:
		for ev in parsed["events"]:
			var s := str(ev).strip_edges()
			if s != "":
				events.append(s.left(240))
	var nq: Dictionary = {}
	var raw_nq = parsed.get("newQuest")
	if raw_nq is Dictionary and str(raw_nq.get("title", "")).strip_edges() != "":
		nq = {
			"title": str(raw_nq.get("title", "")).strip_edges().left(80),
			"desc": str(raw_nq.get("desc", "")).strip_edges().left(240),
			"status": "active",
		}
		var log: Array = (quests if quests is Array else []).duplicate()
		var known := false
		for q in log:
			if q is Dictionary and str(q.get("title", "")).to_lower() == str(nq["title"]).to_lower():
				known = true
		if not known:
			log.append(nq)
			GameState.save_kind("quests", log)
			chronicle_updated.emit()
	return {"events": events, "newQuest": nq}


# ── Chapters (save-points) ──────────────────────────────────────────────────
## A titled recap of the tale so far, written when the player marks a chapter.
##
## This was the LAST LLM call still leaving the process, and I had already
## claimed none did — `studio_snapshot` summarised the session server-side while
## codex, quests and the world tick had all moved. It is the same shape as those:
## prose from the local narrator, then a small schema to give it fields.
const SNAP_SCHEMA := '{"type":"object","required":["title","story_so_far","world_changes"],' \
	+ '"properties":{"title":{"type":"string"},"story_so_far":{"type":"string"},' \
	+ '"world_changes":{"type":"string"}}}'

const SNAP_DIR := "user://chapters"


func _snap_path(key: String) -> String:
	return "%s/%s.json" % [SNAP_DIR, key.validate_filename()]


## Every chapter of this adventure, oldest first.
func chapters(key := "") -> Array:
	var p := _snap_path(key if key != "" else GameState.cid())
	if not FileAccess.file_exists(p):
		return []
	var arr = JSON.parse_string(FileAccess.get_file_as_string(p))
	return arr if arr is Array else []


## Mark a chapter. Returns {} when there is nothing to set down or no narrator.
func save_chapter() -> Dictionary:
	if transcript.is_empty() or not LocalGM.available():
		return {}
	var raw := await LocalGM.prose(
		"You turn an in-progress roleplay session into a save-point. Answer in "
		+ "exactly three parts.\nPART 1 — an evocative chapter title, at most six "
		+ "words.\nPART 2 — a recap of what has happened, 2 to 4 sentences.\n"
		+ "PART 3 — a short list of how the world, the relationships or the "
		+ "situation have CHANGED, one per line, plus any threads left open.\n\n"
		+ "The session:\n%s" % _convo())
	if raw.strip_edges() == "":
		return {}
	var parsed = JSON.parse_string(await LocalGM.complete_json(
		"Copy the following into the required fields. Use ONLY what it says — do "
		+ "not invent, summarise or improve anything.\n\n" + raw, SNAP_SCHEMA))
	if not (parsed is Dictionary):
		return {}
	var name := str(GameState.character.get("name", "the character"))
	var snap := {
		"id": "%d-%04d" % [Time.get_unix_time_from_system(), randi() % 10000],
		"character_id": GameState.cid(), "character_name": name,
		"world_id": GameState.world_id(),
		"title": _first_line(str(parsed.get("title", ""))).left(80),
		"story_so_far": str(parsed.get("story_so_far", "")).strip_edges().left(900),
		"world_changes": str(parsed.get("world_changes", "")).strip_edges().left(900),
		"message_count": transcript.size(),
		"created_at": Time.get_datetime_string_from_system(),
	}
	if str(snap["title"]) == "":
		snap["title"] = "%s — save point" % name
	var all := chapters()
	all.append(snap)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAP_DIR))
	var p := _snap_path(GameState.cid())
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return {}
	f.store_string(JSON.stringify(all))
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".tmp"),
		ProjectSettings.globalize_path(p))
	return snap


## A title is one line. The prose half is asked for six words and sometimes
## explains itself first.
func _first_line(s: String) -> String:
	var t := s.strip_edges()
	var nl := t.find("\n")
	return (t.left(nl) if nl > 0 else t).strip_edges().lstrip("*_\" ").rstrip("*_\" .")


func codex_text() -> String:
	var codex = GameState.state.get("codex", [])
	if not (codex is Array) or codex.is_empty():
		return ""
	var parts: Array[String] = []
	for n in codex.slice(0, 12):
		if n is Dictionary and str(n.get("name", "")) != "":
			parts.append("%s (%s%s)" % [n["name"], str(n.get("role", "")),
				(", " + str(n.get("note", ""))) if str(n.get("note", "")) != "" else ""])
	if parts.is_empty():
		return ""
	return "The named cast so far — keep them consistent: %s." % "; ".join(parts)


## The mark a quest carries in every list: done, failed (a trouble that came to a
## head) or still open. One place, so the log and the book cannot disagree.
func quest_mark(q: Dictionary) -> String:
	return {"done": "✓", "failed": "✕"}.get(str(q.get("status", "active")), "◈")


func quests_text() -> String:
	var quests = GameState.state.get("quests", [])
	var active: Array[String] = []
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("status", "active")) == "active" and str(q.get("title", "")) != "":
				active.append("%s%s" % [q["title"], (" — " + str(q.get("desc", ""))) if str(q.get("desc", "")) != "" else ""])
	# A trouble quest that failed stays in the tale: its fallout is still standing.
	for q in (quests if quests is Array else []):
		if q is Dictionary and str(q.get("status", "")) == "failed":
			active.append("FAILED, fallout still standing — %s: %s" % [q.get("title", ""), q.get("desc", "")])
	if active.is_empty():
		return ""
	return "Active quests: %s. Keep the story moving toward these." % "; ".join(active)

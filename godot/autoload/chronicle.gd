extends Node
## Chronicle — the anti-amnesia layer: pinpoint campaign memory (embedded
## beats + recall), the cast codex, and the quest log. Results persist in
## world-state kinds and fold back into the GM's context each turn.
##
## ALL THREE RUN IN THIS PROCESS. They used to be three POSTs to the backend's
## LLM extractor endpoints, which meant a session's whole cast list depended on
## a FastAPI server and an Ollama daemon being up — for work the narrator's own
## model can do. There is no HTTP path left here and deliberately no fallback to
## one: the narrator already hard-fails without a local model (see
## api_client.narrator_missing), so a second, quieter degradation path would only
## hide the same fault.

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
	if _player_turns % CODEX_EVERY == 0:
		_update_chronicle()


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
	var out: Array = []
	for q in parsed["quests"]:
		if not (q is Dictionary) or str(q.get("title", "")).strip_edges() == "":
			continue
		out.append({
			"title": str(q.get("title", "")).strip_edges().left(80),
			"desc": str(q.get("desc", "")).strip_edges().left(240),
			"status": str(q.get("status", "active")),
		})
	GameState.save_kind("quests", out)
	chronicle_updated.emit()


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
			if q is Dictionary and str(q.get("status", "active")) != "done" and str(q.get("title", "")) != "":
				active.append(str(q["title"]))
	var goals: Array[String] = []
	if codex is Array:
		for n in codex:
			if n is Dictionary and str(n.get("goal", "")) != "" and str(n.get("name", "")) != "":
				goals.append("%s wants %s" % [n["name"], n["goal"]])
	# Nothing in motion yet — a tick here would be the model inventing a world
	# rather than advancing one.
	if active.is_empty() and goals.is_empty():
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


func quests_text() -> String:
	var quests = GameState.state.get("quests", [])
	var active: Array[String] = []
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("status", "active")) != "done" and str(q.get("title", "")) != "":
				active.append("%s%s" % [q["title"], (" — " + str(q.get("desc", ""))) if str(q.get("desc", "")) != "" else ""])
	if active.is_empty():
		return ""
	return "Active quests: %s. Keep the story moving toward these." % "; ".join(active)

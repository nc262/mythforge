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
const CODEX_SCHEMA := '{"type":"object","required":["npcs"],"properties":{"npcs":' \
	+ '{"type":"array","maxItems":12,"items":{"type":"object",' \
	+ '"required":["name","role","disposition","note","goal","appearance"],"properties":{' \
	+ '"name":{"type":"string"},"role":{"type":"string"},' \
	+ '"disposition":{"enum":["ally","friendly","neutral","wary","hostile"]},' \
	+ '"note":{"type":"string"},"goal":{"type":"string"},' \
	+ '"appearance":{"type":"string"}}}}}}'

const QUESTS_SCHEMA := '{"type":"object","required":["quests"],"properties":{"quests":' \
	+ '{"type":"array","maxItems":10,"items":{"type":"object",' \
	+ '"required":["title","desc","status"],"properties":{' \
	+ '"title":{"type":"string"},"desc":{"type":"string"},' \
	+ '"status":{"enum":["active","done"]}}}}}}'

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

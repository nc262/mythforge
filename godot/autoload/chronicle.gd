extends Node
## Chronicle — the anti-amnesia layer: pinpoint campaign memory (embedded
## beats + recall), the cast codex, and the quest log. All three ride the
## backend's LLM extractor endpoints; results persist in world-state kinds
## and fold back into the GM's context each turn.

const CODEX_EVERY := 6  # player turns between codex/quest extractions

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
	var day := int(GameState.clock().get("day", 1))
	# Stage 3 — campaign memory in-process. The embedding runs on the same Vulkan
	# device as the narrator; the beat never leaves the machine or the process.
	# Falls through to the server only while no embedding model is installed.
	if LocalMemory.available():
		LocalMemory.add_beat(GameState.cid(), beat, day)
	else:
		Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/memory/beat",
			{"cid": GameState.cid(), "text": beat, "day": day})
	if _player_turns % CODEX_EVERY == 0:
		_update_codex()
		_update_quests()


## The beats most relevant to this moment. Score floor and k are the same either
## way — LocalMemory is a port of src/campaign_memory.py, not a reimagining.
func recall(query: String) -> Array:
	if LocalMemory.available():
		return await LocalMemory.recall(GameState.cid(), query, 4)
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/memory/recall",
		{"cid": GameState.cid(), "query": query, "k": 4})
	return r.get("beats", []) if r.get("_status", 0) == 200 else []


func recall_text(beats: Array) -> String:
	if beats.is_empty():
		return ""
	var lines: Array[String] = []
	for b in beats:
		lines.append("• " + str(b.get("text", b)).replace("\n", " ").left(240))
	return "Relevant past events (canon — honor them): %s" % " ".join(lines)


func _update_codex() -> void:
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/codex", {
		"character_name": str(GameState.character.get("name", "the story")),
		"transcript": transcript, "codex": GameState.state.get("codex", []),
	})
	if r.get("_status", 0) == 200 and r.get("codex") is Array:
		GameState.save_kind("codex", r["codex"])
		chronicle_updated.emit()


func _update_quests() -> void:
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/quests", {
		"character_name": str(GameState.character.get("name", "the story")),
		"transcript": transcript, "quests": GameState.state.get("quests", []),
	})
	if r.get("_status", 0) == 200 and r.get("quests") is Array:
		GameState.save_kind("quests", r["quests"])
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

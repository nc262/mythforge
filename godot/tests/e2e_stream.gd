extends Node
## End-to-end against the LIVE backend: two consecutive GM turns — player
## action, then a roll result — the exact flow from playtesting. Uses a
## throwaway session so real adventure saves stay untouched.
## PASSES if both turns stream deltas and finish. Prints the GM text + tags.

var _deltas := 0
var _turns := 0
var _acc := ""


func _ready() -> void:
	Api.sse_delta.connect(func(t): _deltas += 1; _acc += t)
	Api.sse_done.connect(_done)
	if not await Api.auth_ok():
		printerr("E2E FAIL: not authenticated (run the app once to log in)")
		get_tree().quit(1)
		return
	var advs: Array = (await Api.list_characters()).filter(
		func(c): return str(c.get("id", "")).begins_with("dm-"))
	if advs.is_empty():
		printerr("E2E FAIL: no dm-* adventures on this backend")
		get_tree().quit(1)
		return
	GameState.character = advs[0]
	print("E2E adventure: ", GameState.character.get("name"))
	# Throwaway session (NOT ensure_session — that would remap the user's save).
	var ep := await Api.call_json(HTTPClient.METHOD_GET, "/api/default-chat")
	var fields := {"name": "godot-e2e-throwaway"}
	if str(ep.get("endpoint_url", "")) != "":
		fields["endpoint_url"] = ep["endpoint_url"]
		fields["model"] = ep.get("model", "")
		fields["endpoint_id"] = ep.get("endpoint_id", "")
		fields["skip_validation"] = "true"
	var created := await Api.call_form("/api/session", fields)
	GameState.session_id = str(created.get("session_id", created.get("id", "")))
	if GameState.session_id == "":
		printerr("E2E FAIL: session create -> ", created)
		get_tree().quit(1)
		return
	await GameState.hydrate()
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	print("TURN 1: sneaking past the guard…")
	Api.stream_chat(Composer.envelope("I try to sneak past the guard."), GameState.session_id)


func _done(ok: bool) -> void:
	_turns += 1
	var parsed: Dictionary = Tags.parse(_acc)
	print("--- turn %d done ok=%s deltas=%d chars=%d tags=%s" % [_turns, ok, _deltas, _acc.length(), str(parsed["tags"])])
	print("GM: ", str(parsed["clean"]).substr(0, 300).replace("\n", " "))
	if not ok or _deltas == 0:
		printerr("E2E FAIL: turn %d streamed nothing" % _turns)
		get_tree().quit(1)
		return
	if _turns == 1:
		_deltas = 0
		_acc = ""
		print("TURN 2: reporting the roll result…")
		await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
		Api.stream_chat(Composer.envelope(
			"🎲 *Dexterity (Stealth) check* → d20 11 +0 = **11** — **failure** (DC 13)"),
			GameState.session_id)
	else:
		print("E2E PASS")
		get_tree().quit(0)

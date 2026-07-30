extends Node
## Api — the only door to the Mythforge backend (FastAPI on :7000).
## Cookie auth, JSON/form calls, and SSE streaming for /api/chat_stream.

const BASE := "http://127.0.0.1:7000"
const HOST := "127.0.0.1"
const PORT := 7000
## Local settings (chosen GM model, UI prefs). Same PATH as the old cookie jar
## so nothing a player already set is lost — it just stopped holding a cookie.
const SETTINGS_FILE := "user://session.cfg"

signal sse_delta(text: String)
signal sse_event(data: Dictionary)
signal sse_done(ok: bool)
## The narrator could not speak because the local model is missing. There is no
## server to fall back to by design, so this must surface to the player instead
## of failing quietly — carries the reason from LocalGM.why_unavailable().
signal narrator_missing(reason: String)


## Integration-test hooks (tests/ui_playthrough): when test_mode is on, no real
## network happens — call_json/call_form return canned responses matched by a
## path substring, stream_chat replays scripted GM turns through the REAL tag
## pipeline, and images resolve to nothing. Drives the actual game scene headless.
var test_mode := false
var test_json := {}       # path-substring → response Dictionary
var test_replies: Array = []  # queue of GM reply strings for stream_chat


func _test_response(path: String) -> Dictionary:
	for k in test_json:
		if path.find(str(k)) != -1:
			var v = test_json[k]
			return v.duplicate(true) if v is Dictionary else {"_status": 200}
	return {"_status": 200}


func _ready() -> void:
	pass


func _headers(extra: Array = []) -> PackedStringArray:
	var h := PackedStringArray()
	for e in extra:
		h.append(e)
	return h


# ── One-shot requests ───────────────────────────────────────────────────────
## Returns the parsed JSON body. Arrays come back as {"data": [...]}. Every
## result carries "_status" (0 = transport failure).
func call_json(method: int, path: String, body = null) -> Dictionary:
	if test_mode:
		return _test_response(path)
	var payload := "" if body == null else JSON.stringify(body)
	var extra := [] if body == null else ["Content-Type: application/json"]
	return await _request(method, path, _headers(extra), payload)


## The worldsmith. It used to POST to an endpoint that answered an ENVELOPE —
## `{"ok":true,"world":{…}}` — which every caller read straight through, so a
## perfectly good world was thrown away as "The forge sputtered (200)" every
## single time, after ~2.5 min and six LLM calls (UIPolish R5 B3).
##
## It runs IN THIS PROCESS now (autoload/worldsmith.gd) and there is no envelope
## left to unwrap: Worldsmith returns the flat body every caller was already
## reading. Kept here as the entry point so all four call sites stay untouched.
func worldsmith(payload: Dictionary) -> Dictionary:
	if test_mode:
		return _test_response("/api/characters/studio/worldsmith")
	return await Worldsmith.forge(payload)


## POST application/x-www-form-urlencoded (the backend's Form(...) endpoints).
func call_form(path: String, fields: Dictionary, method := HTTPClient.METHOD_POST) -> Dictionary:
	if test_mode:
		return _test_response(path)
	return await _request(method, path,
		_headers(["Content-Type: application/x-www-form-urlencoded"]), _urlencode(fields))


func _request(method: int, path: String, headers: PackedStringArray, payload: String) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(BASE + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"_status": 0}
	var res: Array = await req.request_completed  # [result, code, headers, body]
	req.queue_free()
	var out = JSON.parse_string(res[3].get_string_from_utf8())
	var d: Dictionary = out if out is Dictionary else {"data": out}
	d["_status"] = res[1]
	return d


func _urlencode(fields: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in fields:
		parts.append(str(k).uri_encode() + "=" + str(fields[k]).uri_encode())
	return "&".join(parts)


## Multipart file upload (STT audio). → parsed JSON with "_status".
func post_file(path: String, field: String, bytes: PackedByteArray, filename := "audio.wav", mime := "audio/wav") -> Dictionary:
	if test_mode:
		return _test_response(path)
	var boundary := "----mythforge%08x" % (randi() & 0x7FFFFFFF)
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [
		boundary, field, filename, mime]).to_utf8_buffer())
	body.append_array(bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request_raw(BASE + path,
		_headers(["Content-Type: multipart/form-data; boundary=%s" % boundary]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {"_status": 0}
	var res: Array = await req.request_completed
	req.queue_free()
	var out = JSON.parse_string(res[3].get_string_from_utf8())
	var d: Dictionary = out if out is Dictionary else {"data": out}
	d["_status"] = res[1]
	return d


## Raw bytes (images). Empty array on any failure.
func fetch_bytes(path: String) -> PackedByteArray:
	if test_mode:
		return PackedByteArray()
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(BASE + path, _headers()) != OK:
		req.queue_free()
		return PackedByteArray()
	var res: Array = await req.request_completed
	req.queue_free()
	return res[3] if res[1] == 200 else PackedByteArray()


# ── Auth ────────────────────────────────────────────────────────────────────
# THERE ISN'T ANY. This is a single-player desktop game; there was nothing on
# the other side of the door. The exe booted into a login form backed by a
# backend that had no accounts configured at all, so the only way in was the
# `auth_enabled: false` escape hatch — a password prompt that could not be
# satisfied by any password, guarding a save file already sitting in user://.
#
# `login()`, `auth_ok()` and the cookie went with it. The backend still resolves
# an identity for its own bookkeeping (app.py, _identify_without_gating) and
# refuses nothing.


# ── Studio ──────────────────────────────────────────────────────────────────
# `list_characters()` asked /api/presets/templates for the backend's
# user_templates and ALWAYS got an empty list — the key does not exist in
# presets.json, here or on the running server. Companions come from the worlds'
# own cast now (main_menu._companions_from_worlds), which is where they were all
# along.
#
# The four `studio/save` calls went with it. They POSTed a system prompt composed
# by Composer.compose_world_gm for the backend to store on a persona — and
# nothing ever read it back: Composer.system_prompt() rebuilds it from the local
# world every turn, on purpose, "so the two paths cannot drift". They were writes
# into a void.


# `model_size_b` and `auto_gm_model` lived here: they ranked the BACKEND's chat
# models so "Auto" could pick the largest one under 9B. The narrator is a local
# .gguf now and Settings picks it by filename (LocalGM.chat_models), so both were
# ranking candidates that could never be chosen. auto_gm_model had no callers at
# all — its last one went with the session code.


# ── Sessions ────────────────────────────────────────────────────────────────
# ALSO GONE. A session was a SERVER concept: an id the backend hung a model and
# a system prompt on, mirrored from the old web client's _ensureSession. The
# narrator runs in this process now and has neither, so opening a save used to
# mean asking a server for permission to start before reaching the code that no
# longer needed the server.


# ── SSE chat stream ─────────────────────────────────────────────────────────
## Streams one GM turn. Emits sse_delta per token batch, sse_event for
## message_saved / tool_output / error, then sse_done exactly once.

## Drop the GM turn in flight. The player leaving the table must not have to
## wait out a ~45s reply they've already walked away from; the tale is saved
## continuously, so an abandoned turn costs nothing.
## Stop the narrator mid-sentence. Used to set a flag that the SSE read loop
## checked; with the turn running in-process there is no loop to poll, so ask the
## worker directly — NobodyWhoChat exposes `stop_generation`.
func cancel_stream() -> void:
	LocalGM.stop()


func stream_chat(message: String) -> void:
	if test_mode:
		var reply := str(test_replies.pop_front()) if not test_replies.is_empty() else "The quiet holds a moment longer."
		await get_tree().process_frame
		await get_tree().process_frame
		sse_delta.emit(reply)  # one batch — the game's language gate + tag pipeline run for real
		await get_tree().process_frame
		sse_done.emit(true)
		return
	# THE NARRATOR IS LOCAL. There is no server path any more.
	#
	# This used to fall back to POST /api/chat_stream when NobodyWho or the model
	# was missing, and that fallback was not a safety net — it was the REAL path
	# for every install, because nothing ever put a .gguf on disk (the installer
	# pulled Ollama models instead). So the game silently depended on a FastAPI
	# process and an Ollama service, and the in-process narrator was dev-only.
	#
	# Games do not ship an infrastructure fallback. They ship their assets and
	# require them. The installer now downloads the GGUF, LocalGM is the only
	# narrator, and a missing model is a plain, honest failure rather than a
	# silent degradation into 21k lines of agent/tool machinery on a web server.
	#
	# `message` is the full per-turn envelope; `system_prompt()` is the framing a
	# turn used to get from its SESSION. Both are built by the same
	# `compose_world_gm` the forges call, so they cannot drift apart.
	if LocalGM.stream(message, Composer.system_prompt()):
		return
	# Only reachable if the model is absent or a turn is already in flight.
	var why := LocalGM.why_unavailable()
	if why != "":
		push_error("Narrator unavailable: %s" % why)
		narrator_missing.emit(why)
	sse_done.emit(false)


## Consume complete "data: {...}" lines from buf; return the unfinished tail.
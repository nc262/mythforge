extends Node
## Api — the only door to the Mythforge backend (FastAPI on :7000).
## Cookie auth, JSON/form calls, and SSE streaming for /api/chat_stream.

const BASE := "http://127.0.0.1:7000"
const HOST := "127.0.0.1"
const PORT := 7000
const COOKIE_FILE := "user://session.cfg"

signal sse_delta(text: String)
signal sse_event(data: Dictionary)
signal sse_done(ok: bool)
## The narrator could not speak because the local model is missing. There is no
## server to fall back to by design, so this must surface to the player instead
## of failing quietly — carries the reason from LocalGM.why_unavailable().
signal narrator_missing(reason: String)

var cookie := ""

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
	_load_cookie()


# ── Cookie persistence ──────────────────────────────────────────────────────
func _save_cookie() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "cookie", cookie)
	cfg.save(COOKIE_FILE)


func _load_cookie() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(COOKIE_FILE) == OK:
		cookie = cfg.get_value("auth", "cookie", "")


func _headers(extra: Array = []) -> PackedStringArray:
	var h := PackedStringArray()
	for e in extra:
		h.append(e)
	if cookie != "":
		h.append("Cookie: " + cookie)
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


## The worldsmith, unwrapped. The endpoint answers an ENVELOPE —
## `{"ok":true,"world":{…}}` for mode=world, `{"ok":true,"story":{…}}` for
## mode=story — but all four callers read `name`/`title` straight off the
## envelope, where they never are. So a perfectly good world was thrown away as
## "The forge sputtered (200)" every single time, after ~2.5 min and six LLM
## calls (UIPolish R5 B3); the campaign forge failed the same way, quieter.
## Unwrap in one place and every caller's existing check starts working.
func worldsmith(payload: Dictionary) -> Dictionary:
	var r := await call_json(HTTPClient.METHOD_POST, "/api/characters/studio/worldsmith", payload)
	var key := "story" if str(payload.get("mode", "world")) == "story" else "world"
	var body: Dictionary = r[key] if r.get(key) is Dictionary else {}
	body["_status"] = r.get("_status", 0)
	return body


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
	_capture_cookie(res[2])
	var out = JSON.parse_string(res[3].get_string_from_utf8())
	var d: Dictionary = out if out is Dictionary else {"data": out}
	d["_status"] = res[1]
	return d


func _capture_cookie(headers: PackedStringArray) -> void:
	for h in headers:
		if h.to_lower().begins_with("set-cookie:"):
			cookie = h.substr(11).strip_edges().split(";")[0]
			_save_cookie()


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
func login(username: String, password: String) -> Dictionary:
	return await call_json(HTTPClient.METHOD_POST, "/api/auth/login",
		{"username": username, "password": password, "remember": true})


func auth_ok() -> bool:
	var r := await call_json(HTTPClient.METHOD_GET, "/api/auth/status")
	if r.get("_status", 0) != 200:
		return false
	# Backend has auth turned off (single-player desktop): there's no door to
	# open — go straight in.
	if not bool(r.get("auth_enabled", true)):
		return true
	return bool(r.get("authenticated", r.get("ok", false)))


# ── Studio ──────────────────────────────────────────────────────────────────
func list_characters() -> Array:
	var r := await call_json(HTTPClient.METHOD_GET, "/api/presets/templates")
	return r.get("data", []) if r.get("_status", 0) == 200 else []


func activate(char_id: String, char_name: String) -> void:
	await call_json(HTTPClient.METHOD_POST, "/api/characters/studio/activate",
		{"id": char_id, "name": char_name})


## Param count (billions) read off a model id — "llama3.1:8b" → 8.0. Unknown
## ids score huge so a size-blind name never wins the "fastest" race. Mirrors
## the server's own `_model_size` in character_studio_routes.py.
func model_size_b(mid: String) -> float:
	var m := RegEx.new()
	m.compile("(\\d+(?:\\.\\d+)?)\\s*[bB]\\b")
	var hit := m.search(mid)
	return float(hit.get_string(1)) if hit != null else 999.0


## What "Auto" means for the narrator. The account default is whatever model is
## biggest, which on a one-GPU box is whatever model is slowest — a 14B took
## 53s for one turn and the player waited two minutes. So Auto takes the LARGEST
## model that still fits the fast window (≤9B): good prose, a fraction of the
## wait. Returns {} when nothing qualifies, and the caller falls back to the
## account default as before. Settings still overrides this outright.
const GM_FAST_CEILING := 9.0

func auto_gm_model() -> Dictionary:
	var mods := await call_json(HTTPClient.METHOD_GET, "/api/models")
	var best := {}
	var best_sz := 0.0
	for host in mods.get("items", []):
		for mn in host.get("models", []):
			var sz := model_size_b(str(mn))
			if sz <= GM_FAST_CEILING and sz > best_sz:
				best_sz = sz
				best = {"url": str(host.get("url", "")), "model": str(mn)}
	return best


## A remembered session keeps whatever model it was BORN with, forever.
##
## `auto_gm_model()` runs only when a session is created, so a session made
## while the account default was a 14B stayed pinned to it for the life of the
## save — and Auto's whole job is to keep the narrator under 9B. Observed live:
## qwen2.5:14b resident with 4.2 GB in VRAM (half of it spilled to CPU) and a
## turn still composing at 143 s. The fast-ceiling logic was correct and simply
## never got a second chance to apply.
##
## So the model is re-asserted every time a session is reopened. Cheap — one
## PATCH per adventure load — against minutes a turn.
func _reassert_gm_model(sid: String) -> void:
	if test_mode:
		return
	var cfg := ConfigFile.new()
	cfg.load(COOKIE_FILE)
	var pick = JSON.parse_string(str(cfg.get_value("settings", "gm_model", "")))
	if not (pick is Dictionary and str(pick.get("url", "")) != ""):
		pick = await auto_gm_model()
	if not (pick is Dictionary and str(pick.get("url", "")) != ""):
		return
	await call_form("/api/session/" + sid, {
		"model": str(pick.get("model", "")),
		"endpoint_url": str(pick.get("url", "")),
	}, HTTPClient.METHOD_PATCH)


## Session per character, mirrored from the web client's _ensureSession:
## reuse a remembered session if /api/history/{sid} still 200s, else create one
## seeded with the caller's default chat endpoint (/api/default-chat).
func ensure_session(char_id: String, char_name: String) -> String:
	if test_mode:
		return "test-session"
	var cfg := ConfigFile.new()
	cfg.load(COOKIE_FILE)
	var sid: String = cfg.get_value("sessions", char_id, "")
	if sid != "":
		var r := await call_json(HTTPClient.METHOD_GET, "/api/history/" + sid)
		if r.get("_status", 0) == 200:
			await _reassert_gm_model(sid)
			return sid
	# The chosen GM model (Settings) beats the account default.
	var cfg2 := ConfigFile.new()
	cfg2.load(COOKIE_FILE)
	var pick = JSON.parse_string(str(cfg2.get_value("settings", "gm_model", "")))
	if not (pick is Dictionary and str(pick.get("url", "")) != ""):
		pick = await auto_gm_model()   # "Auto" means fast, not biggest
	var ep := await call_json(HTTPClient.METHOD_GET, "/api/default-chat")
	var fields := {"name": char_name}
	if pick is Dictionary and str(pick.get("url", "")) != "":
		fields["endpoint_url"] = pick["url"]
		fields["model"] = pick.get("model", "")
		fields["skip_validation"] = "true"
	elif str(ep.get("endpoint_url", "")) != "":
		fields["endpoint_url"] = ep["endpoint_url"]
		fields["model"] = ep.get("model", "")
		fields["endpoint_id"] = ep.get("endpoint_id", "")
		fields["skip_validation"] = "true"
	var created := await call_form("/api/session", fields)
	sid = str(created.get("session_id", created.get("id", "")))
	if sid != "":
		cfg.set_value("sessions", char_id, sid)
		cfg.save(COOKIE_FILE)
	return sid


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


func stream_chat(message: String, session_id: String) -> void:
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
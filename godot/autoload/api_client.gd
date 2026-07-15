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

var cookie := ""


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
	var payload := "" if body == null else JSON.stringify(body)
	var extra := [] if body == null else ["Content-Type: application/json"]
	return await _request(method, path, _headers(extra), payload)


## POST application/x-www-form-urlencoded (the backend's Form(...) endpoints).
func call_form(path: String, fields: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path,
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


## Raw bytes (images). Empty array on any failure.
func fetch_bytes(path: String) -> PackedByteArray:
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
	return r.get("_status", 0) == 200 and bool(r.get("authenticated", r.get("ok", false)))


# ── Studio ──────────────────────────────────────────────────────────────────
func list_characters() -> Array:
	var r := await call_json(HTTPClient.METHOD_GET, "/api/presets/templates")
	return r.get("data", []) if r.get("_status", 0) == 200 else []


func activate(char_id: String, char_name: String) -> void:
	await call_json(HTTPClient.METHOD_POST, "/api/characters/studio/activate",
		{"id": char_id, "name": char_name})


## Session per character, mirrored from the web client's _ensureSession:
## reuse a remembered session if /api/history/{sid} still 200s, else create one
## seeded with the caller's default chat endpoint (/api/default-chat).
func ensure_session(char_id: String, char_name: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load(COOKIE_FILE)
	var sid: String = cfg.get_value("sessions", char_id, "")
	if sid != "":
		var r := await call_json(HTTPClient.METHOD_GET, "/api/history/" + sid)
		if r.get("_status", 0) == 200:
			return sid
	# The chosen GM model (Settings) beats the account default.
	var cfg2 := ConfigFile.new()
	cfg2.load(COOKIE_FILE)
	var pick = JSON.parse_string(str(cfg2.get_value("settings", "gm_model", "")))
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
func stream_chat(message: String, session_id: String) -> void:
	var client := HTTPClient.new()
	if client.connect_to_host(HOST, PORT) != OK:
		sse_done.emit(false)
		return
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		await get_tree().process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		sse_done.emit(false)
		return
	var body := _urlencode({
		"message": message, "session": session_id, "mode": "chat", "preset_id": "custom",
	})
	var headers := _headers([
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: text/event-stream",
	])
	if client.request(HTTPClient.METHOD_POST, "/api/chat_stream", headers, body) != OK:
		sse_done.emit(false)
		return
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		await get_tree().process_frame
	# Byte buffer, not String: a UTF-8 char can straddle two chunks.
	var buf := PackedByteArray()
	# Idle watchdog (mirrors the web client): abort only after a long gap with
	# no tokens — first token on a slow local model can take ~50s.
	var last_data := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() > 0:
			buf.append_array(chunk)
			buf = _drain_lines(buf)
			last_data = Time.get_ticks_msec()
		else:
			if Time.get_ticks_msec() - last_data > 75_000:
				push_warning("SSE stalled for 75s — aborting stream")
				client.close()
				sse_done.emit(false)
				return
			await get_tree().process_frame
	_drain_lines(buf)
	sse_done.emit(true)


## Consume complete "data: {...}" lines from buf; return the unfinished tail.
func _drain_lines(buf: PackedByteArray) -> PackedByteArray:
	while true:
		var nl := buf.find(10)  # \n
		if nl == -1:
			break
		var line := buf.slice(0, nl).get_string_from_utf8().strip_edges()
		buf = buf.slice(nl + 1)
		if not line.begins_with("data: "):
			continue
		var payload := line.substr(6)
		if payload == "[DONE]":
			continue
		var j = JSON.parse_string(payload)
		if j is Dictionary:
			if j.has("delta"):
				sse_delta.emit(str(j["delta"]))
			else:
				sse_event.emit(j)
	return buf

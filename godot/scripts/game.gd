extends MarginContainer
## Phase 0: raw message in, streamed GM tokens out. Mechanics arrive in Phase 1.

var _streaming := false


func _ready() -> void:
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	$Box/Input/Send.pressed.connect(_send)
	$Box/Input/Msg.text_submitted.connect(func(_t): _send())
	$Box/Log.append_text("[i]The tale of %s begins…[/i]\n" % _bb(str(GameState.character.get("name", "?"))))


func _send() -> void:
	if _streaming:
		return
	var msg: String = $Box/Input/Msg.text.strip_edges()
	if msg == "":
		return
	$Box/Input/Msg.text = ""
	_streaming = true
	$Box/Input/Send.disabled = true
	$Box/Log.append_text("\n[b]You:[/b] %s\n\n[b]GM:[/b] " % _bb(msg))
	await Api.activate(str(GameState.character.get("id", "")), str(GameState.character.get("name", "")))
	Api.stream_chat(msg, GameState.session_id)


func _on_delta(t: String) -> void:
	$Box/Log.append_text(_bb(t))


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		$Box/Log.append_text("[color=red]%s[/color]" % _bb(str(d.get("error", "stream error"))))


func _on_done(_ok: bool) -> void:
	_streaming = false
	$Box/Input/Send.disabled = false
	$Box/Log.append_text("\n")


## Escape user/model text so it can't inject BBCode into the log.
func _bb(s: String) -> String:
	return s.replace("[", "[lb]")

extends MarginContainer
## The adventure screen. Phase 1: streamed narration, structured [[tag]]
## checks resolved by the Rules engine, read-only sheet panel.

var _streaming := false
var _acc := ""          # full raw GM reply
var _shown := 0         # chars of _acc already printed (tags are held back)
var _pending_check := {}


func _ready() -> void:
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	$Split/ChatBox/Input/Send.pressed.connect(func(): _send($Split/ChatBox/Input/Msg.text))
	$Split/ChatBox/Input/Msg.text_submitted.connect(func(_t): _send($Split/ChatBox/Input/Msg.text))
	$Split/ChatBox/Input/SheetBtn.toggled.connect(func(on): $Split/Sheet.visible = on)
	$Split/ChatBox/RollBar.pressed.connect(_roll_pending)
	await GameState.hydrate()
	_render_sheet()
	_log("[i]The tale of %s begins…[/i]\n" % _bb(str(GameState.character.get("name", "?"))))


func _send(raw: String) -> void:
	if _streaming:
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	$Split/ChatBox/Input/Msg.text = ""
	_set_check({})
	_log("\n[b]You:[/b] %s\n\n[b]GM:[/b] " % _bb(msg))
	_stream(Composer.envelope(msg))


## Roll results go to the GM with the envelope too, so state stays fresh.
func _stream(framed: String) -> void:
	_streaming = true
	_acc = ""
	_shown = 0
	$Split/ChatBox/Input/Send.disabled = true
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	Api.stream_chat(framed, GameState.session_id)


func _on_delta(t: String) -> void:
	_acc += t
	# Print only up to the first "[[" — tags are parsed on done, never shown.
	var safe := _acc.substr(_shown)
	var cut := safe.find("[[")
	if cut >= 0:
		_log(_bb(safe.substr(0, cut)))
		_shown += cut
		return
	var hold := 1 if safe.ends_with("[") else 0
	_log(_bb(safe.substr(0, safe.length() - hold)))
	_shown += safe.length() - hold


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		_log("[color=red]%s[/color]" % _bb(str(d.get("error", "stream error"))))


func _on_done(_ok: bool) -> void:
	_streaming = false
	$Split/ChatBox/Input/Send.disabled = false
	# Flush the held-back tail with tags stripped, then act on the tags.
	var parsed: Dictionary = Tags.parse(_acc.substr(_shown))
	if str(parsed["clean"]) != "":
		_log(_bb(parsed["clean"]))
	_log("\n")
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(Tags.parse(_acc)["clean"])  # prose fallback
	_set_check(check)


func _set_check(check: Dictionary) -> void:
	_pending_check = check
	var bar: Button = $Split/ChatBox/RollBar
	bar.visible = not check.is_empty()
	if check.is_empty():
		return
	var sheet := GameState.sheet()
	if check.get("type", "") == "attack":
		bar.text = "⚔ Roll to hit  d20 %+d%s" % [Rules.attack_mod(sheet),
			("  vs AC %d" % int(check["ac"])) if check.get("ac") != null else ""]
	elif check.get("type", "") == "damage":
		bar.text = "🎲 Roll %s  %dd%d%s" % ["healing" if check.get("heal", false) else "damage",
			int(check["n"]), int(check["sides"]),
			(" %+d" % int(check["bonus"])) if int(check.get("bonus", 0)) != 0 else ""]
	else:
		bar.text = "🎲 Roll %s  d20 %+d%s" % [Rules.check_label(check),
			Rules.check_mod(sheet, check),
			("  vs DC %d" % int(check["dc"])) if check.get("dc") != null else ""]


func _roll_pending() -> void:
	if _pending_check.is_empty() or _streaming:
		return
	var check := _pending_check
	_set_check({})
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet())
	_log("\n[b]You:[/b] %s\n\n[b]GM:[/b] " % _md(str(res["text"])))
	_stream(Composer.envelope(str(res["text"])))


func _render_sheet() -> void:
	var s := GameState.sheet()
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _bb(str(s.get("name", "?"))))
	lines.append("%s %s, level %d" % [_bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))), int(s.get("level", 1))])
	lines.append("")
	lines.append("HP [b]%d / %d[/b]    AC [b]%d[/b]" % [int(s.get("hp", 10)), int(s.get("hpMax", 10)), int(s.get("ac", 10))])
	lines.append("Gold [b]%d[/b]    Passive Perception [b]%d[/b]" % [int(s.get("gold", 0)), Rules.passive_perception(s)])
	lines.append("")
	for k in Rules.ABILITIES:
		var v := int(s.get("abilities", {}).get(k, 10))
		lines.append("%s  [b]%d[/b]  (%+d)" % [k, v, Rules.ability_mod(v)])
	var prof: Array = s.get("profSkills", [])
	if not prof.is_empty():
		lines.append("")
		lines.append("[b]Proficient:[/b] %s" % _bb(", ".join(prof.map(func(x): return str(x)))))
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("")
		lines.append("[b]Conditions:[/b] %s" % _bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c)))))
	$Split/Sheet.text = "\n".join(lines)


func _log(bbcode: String) -> void:
	$Split/ChatBox/Log.append_text(bbcode)


## Escape model/user text so it can't inject BBCode.
func _bb(s: String) -> String:
	return s.replace("[", "[lb]")


## Roll-result lines use markdown ** ** — show them bold in our log.
func _md(s: String) -> String:
	var out := _bb(s)
	var parts := out.split("**")
	if parts.size() % 2 == 1:
		out = ""
		for i in parts.size():
			out += ("[b]%s[/b]" % parts[i]) if i % 2 == 1 else parts[i]
	return out

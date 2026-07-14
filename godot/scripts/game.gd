extends Control
## The adventure screen. Streamed narration, structured [[tag]] checks
## resolved by the Rules engine, read-only sheet panel — in the world's skin.

var _streaming := false
var _acc := ""          # full raw GM reply
var _shown := 0         # chars of _acc already printed (tags are held back)
var _pending_check := {}

@onready var _log: RichTextLabel = $Margin/Split/ChatBox/Log
@onready var _roll_bar: Button = $Margin/Split/ChatBox/RollBar
@onready var _msg: LineEdit = $Margin/Split/ChatBox/Input/Msg
@onready var _send_btn: Button = $Margin/Split/ChatBox/Input/Send
@onready var _sheet_panel: RichTextLabel = $Margin/Split/Sheet


func _ready() -> void:
	theme = Ui.theme
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	_send_btn.pressed.connect(func(): _send(_msg.text))
	_msg.text_submitted.connect(func(_t): _send(_msg.text))
	$Margin/Split/ChatBox/Input/SheetBtn.toggled.connect(func(on): _sheet_panel.visible = on)
	_roll_bar.pressed.connect(_roll_pending)
	var world := str(GameState.character.get("world_id", ""))
	$Margin/Split/ChatBox/Header.text = "✦ %s%s" % [str(GameState.character.get("name", "?")),
		("  ·  " + world) if world != "" else ""]
	await GameState.hydrate()
	_render_sheet()
	_log_text("[i]The tale of %s begins…[/i]\n" % _bb(str(GameState.character.get("name", "?"))))


func _you() -> String:
	return "[color=%s][b]You[/b][/color]" % Ui.c("gold").to_html(false)


func _gm() -> String:
	return "[color=%s][b]GM[/b][/color]" % Ui.c("amethyst").to_html(false)


func _send(raw: String) -> void:
	if _streaming:
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	_msg.text = ""
	_set_check({})
	_log_text("\n%s  %s\n\n%s  " % [_you(), _bb(msg), _gm()])
	_stream(Composer.envelope(msg))


## Roll results go to the GM with the envelope too, so state stays fresh.
func _stream(framed: String) -> void:
	_streaming = true
	_acc = ""
	_shown = 0
	_send_btn.disabled = true
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	Api.stream_chat(framed, GameState.session_id)


func _on_delta(t: String) -> void:
	_acc += t
	_flush_stream()


## Print new narration, skipping over [[tags]] as they complete so a mid-reply
## tag never freezes the display. Incomplete tags at the tail are held back.
func _flush_stream() -> void:
	while true:
		var safe := _acc.substr(_shown)
		var i := safe.find("[[")
		if i == -1:
			var hold := 1 if safe.ends_with("[") else 0
			_log_text(_bb(safe.substr(0, safe.length() - hold)))
			_shown += safe.length() - hold
			return
		_log_text(_bb(safe.substr(0, i)))
		_shown += i
		var j := safe.find("]]", i)
		if j == -1:
			return  # tag still streaming in — hold
		_shown += (j + 2) - i  # skip the completed tag; done() re-parses _acc


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		_log_text("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false), _bb(str(d.get("error", "stream error")))])


func _on_done(_ok: bool) -> void:
	_streaming = false
	_send_btn.disabled = false
	# Flush the held-back tail with tags stripped, then act on the tags.
	var parsed: Dictionary = Tags.parse(_acc.substr(_shown))
	if str(parsed["clean"]) != "":
		_log_text(_bb(parsed["clean"]))
	_log_text("\n")
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(Tags.parse(_acc)["clean"])  # prose fallback
	_set_check(check)


func _set_check(check: Dictionary) -> void:
	_pending_check = check
	_roll_bar.visible = not check.is_empty()
	if check.is_empty():
		return
	var sheet := GameState.sheet()
	if check.get("type", "") == "attack":
		_roll_bar.text = "⚔ Roll to hit  d20 %+d%s" % [Rules.attack_mod(sheet),
			("  vs AC %d" % int(check["ac"])) if check.get("ac") != null else ""]
	elif check.get("type", "") == "damage":
		_roll_bar.text = "🎲 Roll %s  %dd%d%s" % ["healing" if check.get("heal", false) else "damage",
			int(check["n"]), int(check["sides"]),
			(" %+d" % int(check["bonus"])) if int(check.get("bonus", 0)) != 0 else ""]
	else:
		_roll_bar.text = "🎲 Roll %s  d20 %+d%s" % [Rules.check_label(check),
			Rules.check_mod(sheet, check),
			("  vs DC %d" % int(check["dc"])) if check.get("dc") != null else ""]


func _roll_pending() -> void:
	if _pending_check.is_empty() or _streaming:
		return
	var check := _pending_check
	_set_check({})
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet())
	_log_text("\n%s  %s\n\n%s  " % [_you(), _md(str(res["text"])), _gm()])
	_stream(Composer.envelope(str(res["text"])))


func _render_sheet() -> void:
	var s := GameState.sheet()
	var gold := Ui.c("gold_soft").to_html(false)
	var lines: Array[String] = []
	lines.append("[color=%s][b]%s[/b][/color]" % [gold, _bb(str(s.get("name", "?")))])
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
		lines.append("[color=%s][b]Proficient[/b][/color]  %s" % [gold, _bb(", ".join(prof.map(func(x): return str(x))))])
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Conditions[/b][/color]  %s" % [gold, _bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c))))])
	_sheet_panel.text = "\n".join(lines)


func _log_text(bbcode: String) -> void:
	_log.append_text(bbcode)


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

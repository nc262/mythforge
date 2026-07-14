extends Control
## The adventure screen: bubbled narration, streamed tokens, structured
## [[tag]] mechanics, the dice moment, and generated art as a living backdrop.

var _streaming := false
var _acc := ""          # full raw GM reply
var _shown := 0         # chars of _acc already printed (tags are held back)
var _pending_check := {}
var _last_player_msg := ""  # the visible player line, paired into memory beats
var _conjuring := false
var _gm_rt: RichTextLabel = null  # the bubble currently receiving tokens

@onready var _thread: VBoxContainer = $Margin/Split/ChatBox/Scroll/Thread
@onready var _scroll: ScrollContainer = $Margin/Split/ChatBox/Scroll
@onready var _combat_panel: RichTextLabel = $Margin/Split/ChatBox/CombatPanel
@onready var _roll_bar: Button = $Margin/Split/ChatBox/RollBar
@onready var _msg: LineEdit = $Margin/Split/ChatBox/Input/Msg
@onready var _send_btn: Button = $Margin/Split/ChatBox/Input/Send
@onready var _sheet_panel: RichTextLabel = $Margin/Split/Sheet
@onready var _scene_art: TextureRect = $SceneArt
@onready var _battle_tint: ColorRect = $BattleTint
@onready var _die_layer: CenterContainer = $DieLayer


func _ready() -> void:
	theme = Ui.theme
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	_send_btn.pressed.connect(func(): _send(_msg.text))
	_msg.text_submitted.connect(func(_t): _send(_msg.text))
	$Margin/Split/ChatBox/Input/SheetBtn.toggled.connect(func(on): _sheet_panel.visible = on)
	$Margin/Split/ChatBox/Input/ShortRest.pressed.connect(func(): _rest("short"))
	$Margin/Split/ChatBox/Input/LongRest.pressed.connect(func(): _rest("long"))
	$Margin/Split/ChatBox/Input/Scene.pressed.connect(_conjure_scene)
	_roll_bar.pressed.connect(_roll_pending)
	_sheet_panel.meta_clicked.connect(_on_sheet_action)
	_combat_panel.meta_clicked.connect(_on_combat_action)
	Combat.changed.connect(_render_combat)
	Chronicle.reset()
	var world := str(GameState.character.get("world_id", ""))
	$Margin/Split/ChatBox/Header.text = "✦ %s%s" % [str(GameState.character.get("name", "?")),
		("  ·  " + world) if world != "" else ""]
	await GameState.hydrate()
	_build_dice_menu()
	_render_sheet()
	_render_combat()  # a fight persisted mid-round resumes where it stood
	_say_system("The tale of %s begins…" % str(GameState.character.get("name", "?")))


# ── Bubbles ──────────────────────────────────────────────────────────────────
## kind: "me" (gold, right) | "gm" (parchment, left). Returns the text node.
func _bubble(kind: String) -> RichTextLabel:
	var row := HBoxContainer.new()
	var panel := PanelContainer.new()
	panel.theme_type_variation = "BubbleMe" if kind == "me" else "BubbleGm"
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.selection_enabled = true
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())  # the bubble panel is the only frame
	panel.add_child(rt)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == "me":
		spacer.size_flags_stretch_ratio = 1.0
		panel.size_flags_stretch_ratio = 2.6
		row.add_child(spacer)
		row.add_child(panel)
	else:
		panel.size_flags_stretch_ratio = 8.0
		spacer.size_flags_stretch_ratio = 1.0
		row.add_child(panel)
		row.add_child(spacer)
	_thread.add_child(row)
	_scroll_bottom()
	return rt


func _say_me(bb: String) -> void:
	_bubble("me").append_text(bb)


func _say_system(text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "HintLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_thread.add_child(l)
	_scroll_bottom()


func _scroll_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# ── Sending / streaming ──────────────────────────────────────────────────────
func _send(raw: String) -> void:
	if _streaming:
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	_msg.text = ""
	_set_check({})
	_say_me(_bb(msg))
	_last_player_msg = msg
	var beats: Array = await Chronicle.recall(msg)
	_stream(Composer.envelope(msg, beats))


func _stream(framed: String) -> void:
	_streaming = true
	_acc = ""
	_shown = 0
	_send_btn.disabled = true
	_gm_rt = _bubble("gm")
	_gm_rt.append_text("[color=%s]✦ ✦ ✦[/color]" % Ui.c("ink_dim").to_html(false))
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	Api.stream_chat(framed, GameState.session_id)


func _on_delta(t: String) -> void:
	if _acc == "" and _gm_rt != null:
		_gm_rt.clear()  # first token replaces the typing glyphs
	_acc += t
	_flush_stream()


## Print new narration, skipping over [[tags]] as they complete so a mid-reply
## tag never freezes the display. Incomplete tags at the tail are held back.
func _flush_stream() -> void:
	if _gm_rt == null:
		return
	while true:
		var safe := _acc.substr(_shown)
		var i := safe.find("[[")
		if i == -1:
			var hold := 1 if safe.ends_with("[") else 0
			_gm_rt.append_text(_bb(safe.substr(0, safe.length() - hold)))
			_shown += safe.length() - hold
			_scroll_bottom()
			return
		_gm_rt.append_text(_bb(safe.substr(0, i)))
		_shown += i
		var j := safe.find("]]", i)
		if j == -1:
			return  # tag still streaming in — hold
		_shown += (j + 2) - i  # skip the completed tag; done() re-parses _acc


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		if _gm_rt != null:
			_gm_rt.append_text("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false), _bb(str(d.get("error", "stream error")))])
	elif d.get("type", "") == "tool_output" and str(d.get("image_url", "")) != "":
		_show_image(str(d["image_url"]))


func _on_done(_ok: bool) -> void:
	_streaming = false
	_send_btn.disabled = false
	var tail: Dictionary = Tags.parse(_acc.substr(_shown))
	if _gm_rt != null:
		if str(tail["clean"]) != "":
			_gm_rt.append_text(_bb(tail["clean"]))
		if _acc.strip_edges() == "":
			_gm_rt.clear()
			_gm_rt.append_text("[color=%s][i]The GM falls silent — try again or rephrase.[/i][/color]" % Ui.c("ink_dim").to_html(false))
	var parsed: Dictionary = Tags.parse(_acc)
	_apply_world_tags(parsed["tags"])
	Chronicle.record(_last_player_msg, str(parsed["clean"]))
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(str(parsed["clean"]))
	_set_check(check)
	_scroll_bottom()


# ── World tags → state ───────────────────────────────────────────────────────
func _apply_world_tags(tags: Array) -> void:
	for t in tags:
		var a: Dictionary = t["attrs"]
		match str(t["name"]):
			"gold":
				var delta := int(str(a.get("delta", "0")).replace("+", ""))
				if delta != 0:
					var total := GameState.add_gold(delta)
					_say_system("%s gold %+d — purse now %d" % ["💰" if delta > 0 else "🪙", delta, total])
			"loot":
				var nm := str(a.get("name", "")).strip_edges()
				if nm != "":
					GameState.add_item(nm, str(a.get("rarity", "common")), maxi(1, int(a.get("qty", 1))))
					_say_system("🎒 %s added to your pack" % nm)
			"spell-learned":
				var sp := str(a.get("name", "")).strip_edges()
				if sp != "" and GameState.learn_spell(sp):
					_say_system("📖 You learn %s" % sp)
			"time":
				GameState.advance_time(maxi(1, int(a.get("advance", 1))))
				var c: Dictionary = GameState.clock()
				_say_system("🕰 %s, day %d" % [GameState.TIMES[int(c["ti"])], int(c["day"])])
			"xp":
				var r: Dictionary = GameState.award_xp(int(str(a.get("delta", a.get("amount", "0"))).replace("+", "")), str(a.get("reason", "")))
				if str(r["note"]) != "":
					_say_system(str(r["note"]).replace("*", ""))
			"combat-start":
				_start_combat(str(a.get("foes", a.get("foe", "Enemy"))))
			"combat-end":
				_end_combat()
	if not Combat.active():
		var foe := Tags.detect_combat_start(Tags.parse(_acc)["clean"])
		if foe != "":
			_start_combat(foe)
	_render_sheet()


func _start_combat(foes: String) -> void:
	var first := true
	for part in foes.split(","):
		var nm := part.strip_edges()
		var count := 1
		var xm := RegEx.create_from_string("(?i)^(.*?)\\s*[x×]\\s*(\\d+)$").search(nm)
		if xm:
			nm = xm.get_string(1).strip_edges()
			count = clampi(int(xm.get_string(2)), 1, 6)
		if nm == "":
			continue
		for i in count:
			var label := nm.capitalize() if count == 1 else "%s %d" % [nm.capitalize(), i + 1]
			if first:
				var line := Combat.enter(label)
				if line != "":
					_say_system(line.replace("*", ""))
				first = false
			else:
				Combat.add_foe(label)
	_render_combat()


func _end_combat() -> void:
	var r: Dictionary = Combat.finish()
	if str(r["note"]) != "":
		_say_system(str(r["note"]).replace("*", ""))
	_render_combat()
	_render_sheet()


# ── The dice moment ──────────────────────────────────────────────────────────
func _animate_die(sides: int, final_roll: int, caption: String) -> void:
	var num: Label = $DieLayer/DiePanel/Box/Num
	var cap: Label = $DieLayer/DiePanel/Box/Caption
	cap.text = caption
	_die_layer.visible = true
	for i in 11:
		num.text = str(randi_range(1, sides))
		await get_tree().create_timer(0.05 + i * 0.012).timeout
	num.text = str(final_roll)
	await get_tree().create_timer(0.75).timeout
	_die_layer.visible = false


# ── Rolls ────────────────────────────────────────────────────────────────────
func _set_check(check: Dictionary) -> void:
	_pending_check = check
	_roll_bar.visible = not check.is_empty()
	if check.is_empty():
		return
	var sheet := GameState.sheet()
	if check.get("type", "") == "attack":
		_roll_bar.text = "⚔ Roll to hit  d20 %+d%s" % [Rules.attack_mod(sheet, GameState.inv()),
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
	if check.get("type", "") == "death":
		var dr: Dictionary = Combat.death_save()
		if dr.is_empty():
			return
		await _animate_die(20, 20 if bool(dr["revived"]) else randi_range(1, 20), "death save")
		_render_sheet()
		_say_me(_md(str(dr["msg"])))
		_last_player_msg = str(dr["msg"])
		if bool(dr["dead"]):
			_say_system("☠ THE TALE ENDS HERE — three failures. A long rest starts a new dawn… if the GM allows it.")
			_stream(Composer.envelope("[Three death saves failed — I am dying, my tale at its end. Narrate my final moment with the weight it deserves.]"))
		else:
			_stream(Composer.envelope(str(dr["msg"])))
		return
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	var caption := "d%d" % int(res.get("sides", 20))
	if check.get("type", "") == "damage":
		caption = "%dd%d" % [int(check["n"]), int(check["sides"])]
	await _animate_die(int(res.get("sides", 20)), int(res.get("roll", res["total"])), caption)
	if check.get("type", "") == "damage":
		GameState.apply_hp(int(res["total"]) if check.get("heal", false) else -int(res["total"]))
		_render_sheet()
	_say_me(_md(str(res["text"])))
	_last_player_msg = str(res["text"])
	_stream(Composer.envelope(str(res["text"])))


## 🎲 Roll-anything menu: every skill (with your real modifier) + raw abilities.
func _build_dice_menu() -> void:
	var pop: PopupMenu = $Margin/Split/ChatBox/Input/Dice.get_popup()
	pop.clear()
	var s := GameState.sheet()
	var skills := Rules.SKILL2AB.keys()
	skills.sort()
	var idx := 0
	for k in skills:
		var prof: bool = k in s.get("profSkills", [])
		var mod := Rules.ability_mod(int(s["abilities"].get(Rules.SKILL2AB[k], 10))) + (Rules.prof_bonus(s) if prof else 0)
		pop.add_item("%s  %+d%s" % [str(k).capitalize(), mod, "  ●" if prof else ""], idx)
		pop.set_item_metadata(idx, {"skill": k})
		idx += 1
	pop.add_separator("Raw ability")
	idx += 1
	for a in Rules.ABILITIES:
		pop.add_item("%s  %+d" % [a, Rules.ability_mod(int(s["abilities"].get(a, 10)))], idx)
		pop.set_item_metadata(idx, {"abil": a})
		idx += 1
	if not pop.id_pressed.is_connected(_free_check):
		pop.id_pressed.connect(_free_check)


func _free_check(id: int) -> void:
	if _streaming:
		return
	var pop: PopupMenu = $Margin/Split/ChatBox/Input/Dice.get_popup()
	var meta = pop.get_item_metadata(pop.get_item_index(id))
	if meta == null:
		return
	var check := {}
	var label := ""
	if meta.has("skill"):
		check = {"ability": Rules.SKILL2AB[meta["skill"]], "skill": str(meta["skill"]).capitalize()}
		label = "%s check" % str(meta["skill"]).capitalize()
	else:
		check = {"ability": meta["abil"], "skill": ""}
		label = "%s check" % meta["abil"]
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	await _animate_die(20, int(res.get("roll", res["total"])), label)
	_say_me(_md(str(res["text"])))
	_last_player_msg = str(res["text"])
	_stream(Composer.envelope("[I make a %s: I rolled %d. Narrate the outcome — set a DC if there was uncertainty.]" % [label, int(res["total"])]))


# ── Sheet actions ────────────────────────────────────────────────────────────
func _on_sheet_action(meta) -> void:
	var parts := str(meta).split(":", true, 1)
	if parts.size() != 2 or _streaming:
		return
	var note := ""
	var tell_gm := false
	match parts[0]:
		"cast":
			note = GameState.cast_spell(parts[1].uri_decode())
			tell_gm = not note.begins_with("✋")
		"equip":
			note = GameState.toggle_equip(parts[1])
		"sell":
			note = GameState.sell_item(parts[1])
			tell_gm = true
	if note == "":
		return
	_render_sheet()
	if tell_gm:
		_say_me(_md(note))
		_last_player_msg = note
		_stream(Composer.envelope(note))
	else:
		_say_system(note.replace("*", ""))


# ── Combat actions ───────────────────────────────────────────────────────────
func _on_combat_action(meta) -> void:
	if _streaming:
		return
	var m := str(meta)
	if m == "cend":
		_end_combat()
		_last_player_msg = "The fight ends."
		_stream(Composer.envelope("[I end the fight here. Narrate the aftermath of the battle briefly.]"))
		return
	if m == "cnext":
		Combat.next_turn()
		var c: Dictionary = Combat.data()
		var cur: Dictionary = Combat.current(c)
		if cur.get("side") == "enemy" and int(cur.get("hp", 0)) > 0:
			var r: Dictionary = Combat.enemy_turn(cur)
			_say_me(_md(str(r["msg"])))
			_render_sheet()
			_render_combat()
			if str(r["gm"]) != "":
				_last_player_msg = str(r["msg"])
				_stream(Composer.envelope(str(r["gm"])))
		elif str(cur.get("id", "")).begins_with("cmp"):
			var cr: Dictionary = Combat.companion_turn(cur)
			if str(cr["msg"]) != "":
				_say_me(_md(str(cr["msg"])))
		elif str(cur.get("id", "")) == "pc":
			_say_system("Round %d — your turn." % int(c.get("round", 1)))
		return
	if m.begins_with("atk:"):
		var r2: Dictionary = Combat.player_attack(m.substr(4))
		if not bool(r2["spent"]):
			_say_system(str(r2["msg"]).replace("*", ""))
			return
		if str(r2["msg"]) == "":
			return
		_say_me(_md(str(r2["msg"])))
		if bool(r2["won"]):
			_end_combat()
			_last_player_msg = str(r2["msg"])
			_stream(Composer.envelope("%s\n[Victory — the last foe falls! Narrate the killing blow in full cinema, then the aftermath.]" % str(r2["msg"])))
		elif bool(r2["fell"]):
			_last_player_msg = str(r2["msg"])
			_stream(Composer.envelope("%s\n[The foe falls — narrate the finish with cinema.]" % str(r2["msg"])))
		else:
			_last_player_msg = str(r2["msg"])
			_stream(Composer.envelope(str(r2["msg"])))


func _render_combat() -> void:
	var c: Dictionary = Combat.data()
	var fighting := bool(c.get("active", false))
	_combat_panel.visible = fighting
	# The room darkens toward ember-red while steel is out.
	var tween := create_tween()
	tween.tween_property(_battle_tint, "color:a", 0.05 if fighting else 0.0, 0.8)
	if not fighting:
		return
	if not Combat.pc_down().is_empty():
		_pending_check = {"type": "death"}
		_roll_bar.text = "☠ Roll a death save"
		_roll_bar.visible = true
	var gold := Ui.c("gold_soft").to_html(false)
	var danger := Ui.c("danger").to_html(false)
	var cur: Dictionary = Combat.current(c)
	var lines: Array[String] = []
	lines.append("[color=%s][b]⚔ COMBAT — Round %d[/b][/color]    [url=cnext]Next ›[/url]    [url=cend]End combat[/url]" % [gold, int(c.get("round", 1))])
	for m in Combat.order(c):
		var here := "▶ " if str(m.get("id")) == str(cur.get("id")) else "   "
		var hp := int(m.get("hp", 0))
		var hp_max := maxi(1, int(m.get("hpMax", 1)))
		var bar_n := clampi(roundi(10.0 * hp / hp_max), 0, 10)
		var color := gold if m.get("side") == "ally" else danger
		var row := "%s[color=%s]%s[/color]  [color=%s]%s[/color][color=%s]%s[/color] %d/%d" % [here, color, _bb(str(m.get("name", "?"))),
			color, "▰".repeat(bar_n), Ui.c("ink_dim").to_html(false), "▱".repeat(10 - bar_n), hp, hp_max]
		if m.get("side") == "enemy" and hp > 0:
			row += "   [url=atk:%s]⚔ attack[/url]" % str(m.get("id"))
		elif hp <= 0:
			row += "   ✝"
		lines.append(row)
	_combat_panel.text = "\n".join(lines)


# ── Rests ────────────────────────────────────────────────────────────────────
func _rest(kind: String) -> void:
	if _streaming:
		return
	var r: Dictionary = GameState.short_rest() if kind == "short" else GameState.long_rest()
	_render_sheet()
	_say_me(_md(str(r["note"])))
	_last_player_msg = str(r["note"])
	_stream(Composer.envelope(str(r["gm"])))


# ── Images ───────────────────────────────────────────────────────────────────
## Paint a generated image into the tale AND behind it (the living backdrop).
func _show_image(url: String) -> void:
	var path := url.trim_prefix(Api.BASE)
	var bytes := await Api.fetch_bytes(path)
	if bytes.is_empty():
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		return
	# Backdrop first: the full image, faded in low behind the parchment.
	_scene_art.texture = ImageTexture.create_from_image(img)
	var tw := create_tween()
	tw.tween_property(_scene_art, "modulate:a", 0.45, 1.4)
	# Then inline, sized to the thread.
	var inline := img.duplicate()
	var w := 520
	if inline.get_width() > w:
		inline.resize(w, inline.get_height() * w / inline.get_width(), Image.INTERPOLATE_LANCZOS)
	var rt := _bubble("gm")
	rt.add_image(ImageTexture.create_from_image(inline))
	_scroll_bottom()


func _conjure_scene() -> void:
	if _conjuring:
		return
	var last_gm := str(Tags.parse(_acc)["clean"]).strip_edges()
	if last_gm == "":
		var t: Array = Chronicle.transcript.filter(func(m): return m.get("role") == "assistant")
		if not t.is_empty():
			last_gm = str(t[-1].get("content", ""))
	if last_gm == "":
		_say_system("Nothing to paint yet — play a scene first.")
		return
	_conjuring = true
	_say_system("🖼 The scene paints itself…")
	var prompt := "The current scene: %s. Cinematic %s illustration, dramatic lighting, no text." % [
		last_gm.left(400), {"neonspire": "cyberpunk sci-fi", "everyday": "warm slice-of-life"}.get(GameState.world_id(), "high fantasy")]
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate", {"prompt": prompt})
	_conjuring = false
	if r.get("_status", 0) == 200 and str(r.get("image_url", "")) != "":
		await _show_image(str(r["image_url"]))
	else:
		_say_system("The art forge sputters — no image this time.")


# ── Sheet panel ──────────────────────────────────────────────────────────────
func _render_sheet() -> void:
	var s := GameState.sheet()
	var gold := Ui.c("gold_soft").to_html(false)
	var lines: Array[String] = []
	lines.append("[color=%s][b]%s[/b][/color]" % [gold, _bb(str(s.get("name", "?")))])
	lines.append("%s %s, level %d" % [_bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))), int(s.get("level", 1))])
	lines.append("")
	var hp := int(s.get("hp", 10))
	var hp_max := maxi(1, int(s.get("hpMax", 10)))
	var hb := clampi(roundi(12.0 * hp / hp_max), 0, 12)
	var hp_col := gold if hp * 2 >= hp_max else Ui.c("danger").to_html(false)
	lines.append("HP [b]%d / %d[/b]  [color=%s]%s[/color][color=%s]%s[/color]" % [hp, hp_max, hp_col, "▰".repeat(hb), Ui.c("ink_dim").to_html(false), "▱".repeat(12 - hb)])
	lines.append("AC [b]%d[/b]    Gold [b]%d[/b]    Perception [b]%d[/b]" % [Rules.eff_ac(s, GameState.inv()), int(s.get("gold", 0)), Rules.passive_perception(s)])
	lines.append("")
	for k in Rules.ABILITIES:
		var v := int(s.get("abilities", {}).get(k, 10))
		lines.append("%s  [b]%d[/b]  (%+d)" % [k, v, Rules.ability_mod(v)])
	var pool := int(s.get("level", 1))
	lines.append("Hit Dice [b]%d / %d[/b] (d%d)" % [pool - int(s.get("hitDiceUsed", 0)), pool, int(s.get("hitDie", 8))])
	if int(s.get("exhaustion", 0)) > 0:
		lines.append("[color=%s]Exhaustion level %d[/color]" % [Ui.c("danger").to_html(false), int(s["exhaustion"])])
	var prof: Array = s.get("profSkills", [])
	if not prof.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Proficient[/b][/color]  %s" % [gold, _bb(", ".join(prof.map(func(x): return str(x))))])
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Conditions[/b][/color]  %s" % [gold, _bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c))))])
	var spells: Array = s.get("spells", [])
	if not spells.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Spells[/b][/color]" % gold)
		for sp in spells:
			var lv := int(sp.get("level", 0))
			lines.append("  %s %s  [url=cast:%s]✦ cast[/url]" % [_bb(str(sp.get("name", ""))),
				("(lvl %d)" % lv) if lv > 0 else "(cantrip)", str(sp.get("name", "")).uri_encode()])
		var slots: Dictionary = s.get("slots", {})
		var slot_parts: Array[String] = []
		var slot_keys := slots.keys()
		slot_keys.sort()
		for l in slot_keys:
			if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
				slot_parts.append("L%s %d/%d" % [l, maxi(0, int(slots[l]["max"]) - int(slots[l].get("used", 0))), int(slots[l]["max"])])
		if not slot_parts.is_empty():
			lines.append("  Slots: %s" % "  ".join(slot_parts))
	var inv: Dictionary = GameState.inv()
	var items: Array = inv.get("items", [])
	if not items.is_empty():
		var worn: Array = inv.get("equipped", {}).values()
		lines.append("")
		lines.append("[color=%s][b]Pack[/b][/color]  (%d/%d slots)" % [gold, items.size(), int(inv.get("slots", 24))])
		for it in items:
			var q := int(it.get("qty", 1))
			var iid := str(it.get("id", ""))
			var row := "  %s%s%s" % [_bb(str(it.get("name", ""))), (" ×%d" % q) if q > 1 else "",
				"  [color=%s]● worn[/color]" % gold if iid in worn else ""]
			if str(it.get("type", "")) in ["weapon", "armor", "shield"]:
				row += "  [url=equip:%s]%s[/url]" % [iid, "unequip" if iid in worn else "equip"]
			row += "  [url=sell:%s]sell %d[/url]" % [iid, Rules.sell_value(str(it.get("rarity", "common")))]
			lines.append(row)
	var feats: Array = s.get("feats", [])
	if not feats.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Feats[/b][/color]  %s" % [gold, _bb(", ".join(feats.map(func(x): return str(x))))])
	var features: Array = s.get("features", [])
	if not features.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Class features[/b][/color]" % gold)
		for f in features:
			lines.append("  %s" % _bb(str(f)))
	_sheet_panel.text = "\n".join(lines)


# ── Text helpers ─────────────────────────────────────────────────────────────
## Escape model/user text so it can't inject BBCode.
func _bb(s: String) -> String:
	return s.replace("[", "[lb]")


## Roll-result lines use markdown ** ** — show them bold in our bubbles.
func _md(s: String) -> String:
	var out := _bb(s)
	var parts := out.split("**")
	if parts.size() % 2 == 1:
		out = ""
		for i in parts.size():
			out += ("[b]%s[/b]" % parts[i]) if i % 2 == 1 else parts[i]
	return out

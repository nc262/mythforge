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
var _panel_mode := "sheet"  # what the right panel shows: sheet | codex
var _shop_markup := 1.0  # haggling moves the keeper's prices

@onready var _thread: VBoxContainer = $Margin/Split/ChatBox/Scroll/Thread
@onready var _scroll: ScrollContainer = $Margin/Split/ChatBox/Scroll
@onready var _combat_panel: RichTextLabel = $Margin/Split/ChatBox/CombatPanel
@onready var _battle_grid: Control = $Margin/Split/ChatBox/BattleGrid
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
	$Margin/Split/ChatBox/Input/SheetBtn.toggled.connect(func(on):
		_panel_mode = "sheet"
		$Margin/Split/ChatBox/Input/CodexBtn.set_pressed_no_signal(false)
		_sheet_panel.visible = on
		if on:
			_render_sheet())
	$Margin/Split/ChatBox/Input/CodexBtn.toggled.connect(func(on):
		_panel_mode = "codex" if on else "sheet"
		$Margin/Split/ChatBox/Input/SheetBtn.set_pressed_no_signal(false)
		_sheet_panel.visible = on
		if on:
			_render_codex())
	Chronicle.chronicle_updated.connect(func():
		if _panel_mode == "codex" and _sheet_panel.visible:
			_render_codex())
	$Margin/Split/ChatBox/Input/ShortRest.pressed.connect(func(): _rest("short"))
	$Margin/Split/ChatBox/Input/LongRest.pressed.connect(func(): _rest("long"))
	$Margin/Split/ChatBox/Input/Scene.pressed.connect(_conjure_scene)
	$Margin/Split/ChatBox/Input/Shop.pressed.connect(_open_shop)
	$Margin/Split/ChatBox/Input/Retell.pressed.connect(_regen)
	_roll_bar.pressed.connect(_roll_pending)
	_sheet_panel.meta_clicked.connect(_on_sheet_action)
	_combat_panel.meta_clicked.connect(_on_combat_action)
	_battle_grid.cell_clicked.connect(_on_grid_move)
	_battle_grid.token_clicked.connect(_on_grid_token)
	Combat.changed.connect(_render_combat)
	Chronicle.reset()
	var world := str(GameState.character.get("world_id", ""))
	$Margin/Split/ChatBox/Header.text = "✦ %s%s" % [str(GameState.character.get("name", "?")),
		("  ·  " + world) if world != "" else ""]
	# The world's key art is the room you sit in from the first breath.
	var world_tex := Art.texture_for(world)
	if world_tex != null:
		_scene_art.texture = world_tex
		_scene_art.modulate.a = 0.35
	# Companion chat (non-DM persona): a quiet table for two — no dice, no HUD.
	if not GameState.is_dm():
		Mode.enter("Dialogue")
		for btn in ["SheetBtn", "CodexBtn", "Dice", "Shop", "ShortRest", "LongRest", "Scene"]:
			$Margin/Split/ChatBox/Input.get_node(btn).visible = false
		_say_system("You sit down with %s." % str(GameState.character.get("name", "?")))
		return
	await GameState.hydrate()
	_build_dice_menu()
	_render_sheet()
	_render_combat()  # a fight persisted mid-round resumes where it stood
	if str(GameState.sheet().get("name", "")) == "":
		Mode.enter("CharacterCreation")
		_hero_forge()  # a fresh adventure begins with a hero, not a nobody
	else:
		Mode.enter("Exploration")
		_say_system("The tale of %s continues…" % str(GameState.character.get("name", "?")))
		_recap()


## "Previously, in <adventure>…" — the campaign memory recalls the thread.
func _recap() -> void:
	var beats: Array = await Chronicle.recall("the most important recent events of our story")
	if beats.is_empty():
		return
	var lines: Array[String] = []
	for b in beats.slice(0, 3):
		var t := str(b.get("text", "")).replace("\n", " · ").left(160)
		if t != "":
			lines.append("• " + t)
	if not lines.is_empty():
		var rt := _bubble("gm")
		rt.append_text("[color=%s][b]Previously…[/b][/color]\n%s" % [Ui.c("gold_soft").to_html(false), _bb("\n".join(lines))])


# ── Hero forge: character creation is the door into a new adventure ─────────
func _hero_forge() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "⚒ Forge your hero"
	dlg.ok_button_text = "Begin the tale"
	dlg.get_cancel_button().visible = false
	dlg.min_size = Vector2i(480, 320)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Your hero's name"
	# One-click legends (the original's prebuilts) — or start fresh below.
	const PREBUILT := [
		["Brakka Ironhide", "Half-Orc", "Fighter", "Soldier"],
		["Elara Venn", "Elf", "Wizard", "Sage"],
		["Finch", "Halfling", "Rogue", "Criminal"],
		["Sister Maren", "Human", "Cleric", "Acolyte"],
	]
	var pre_row := HFlowContainer.new()
	var race_in := OptionButton.new()
	var races: Array = Rules.tables.get("heritages", {}).keys()
	races.sort()
	for r in races:
		race_in.add_item(str(r))
	var cls_in := OptionButton.new()
	var classes: Array = Rules.tables.get("class_presets", {}).keys()
	classes.sort()
	for c in classes:
		cls_in.add_item(str(c))
	var bg_in := OptionButton.new()
	var bgs: Array = Rules.tables.get("backgrounds", {}).keys()
	bgs.sort()
	for bgn in bgs:
		bg_in.add_item(str(bgn))
	var bg_hint := Label.new()
	bg_hint.theme_type_variation = "HintLabel"
	bg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg_hint.custom_minimum_size = Vector2(420, 0)
	var refresh_bg := func():
		var bgd: Dictionary = Rules.tables.get("backgrounds", {}).get(bg_in.get_item_text(bg_in.selected), {})
		bg_hint.text = "%s — trained in %s" % [str(bgd.get("line", "")), ", ".join(bgd.get("skills", []))]
	bg_in.item_selected.connect(func(_i): refresh_bg.call())
	refresh_bg.call()
	var pick := func(idx: int):
		name_in.text = str(PREBUILT[idx][0])
		for i in race_in.item_count:
			if race_in.get_item_text(i) == str(PREBUILT[idx][1]):
				race_in.selected = i
		for i in cls_in.item_count:
			if cls_in.get_item_text(i) == str(PREBUILT[idx][2]):
				cls_in.selected = i
		for i in bg_in.item_count:
			if bg_in.get_item_text(i) == str(PREBUILT[idx][3]):
				bg_in.selected = i
		refresh_bg.call()
	for pi in PREBUILT.size():
		var pb := Button.new()
		pb.text = "%s — %s %s" % [PREBUILT[pi][0], PREBUILT[pi][1], PREBUILT[pi][2]]
		pb.add_theme_font_size_override("font_size", 12)
		pb.pressed.connect(pick.bind(pi))
		pre_row.add_child(pb)
	var stats_l := Label.new()
	stats_l.theme_type_variation = "HintLabel"
	var rolled: Array[int] = []
	var reroll := func():
		rolled.clear()
		for i in 6:
			var d := [randi_range(1, 6), randi_range(1, 6), randi_range(1, 6), randi_range(1, 6)]
			d.sort()
			rolled.append(d[1] + d[2] + d[3])
		rolled.sort()
		rolled.reverse()
		stats_l.text = "Destiny rolled (4d6, best assigned to your class): %s" % ", ".join(rolled.map(func(x): return str(x)))
	reroll.call()
	var roll_btn := Button.new()
	roll_btn.text = "🎲 Reroll destiny"
	roll_btn.pressed.connect(reroll)
	for n in [pre_row, name_in, race_in, cls_in, bg_in, bg_hint, roll_btn, stats_l]:
		box.add_child(n)
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	name_in.grab_focus()
	dlg.confirmed.connect(func():
		var nm := name_in.text.strip_edges()
		_create_hero(nm if nm != "" else "The Nameless",
			race_in.get_item_text(race_in.selected), cls_in.get_item_text(cls_in.selected), rolled,
			bg_in.get_item_text(bg_in.selected))
		dlg.queue_free())


func _create_hero(nm: String, race: String, cls: String, rolled: Array[int], background := "") -> void:
	var preset: Dictionary = Rules.tables.get("class_presets", {}).get(cls, {"hitDie": 8})
	var heritage: Dictionary = Rules.tables.get("heritages", {}).get(race, {})
	# Best scores where the class wants them: cast ability or STR/DEX first, CON second.
	var prio: Array[String] = []
	var cast_ab: String = Rules.CAST_ABIL.get(cls, "")
	if cast_ab != "":
		prio.append(cast_ab)
	for a in (["DEX", "STR"] if cls in ["Rogue", "Ranger", "Monk"] else ["STR", "DEX"]):
		if not a in prio:
			prio.append(a)
	if not "CON" in prio:
		prio.insert(1, "CON")
	for a in Rules.ABILITIES:
		if not a in prio:
			prio.append(a)
	var abilities := {}
	for i in 6:
		abilities[prio[i]] = rolled[i] if i < rolled.size() else 10
	for a in heritage.get("abil", {}):
		abilities[a] = int(abilities.get(a, 10)) + int(heritage["abil"][a])
	var s: Dictionary = GameState.DEFAULT_SHEET.duplicate(true)
	s["name"] = nm
	s["race"] = race
	s["cls"] = cls
	s["abilities"] = abilities
	s["hitDie"] = int(preset.get("hitDie", 8))
	s["hpMax"] = int(preset.get("hitDie", 8)) + Rules.ability_mod(int(abilities.get("CON", 10)))
	s["hp"] = s["hpMax"]
	s["gold"] = 10 + randi_range(1, 20)
	s["profSaves"] = preset.get("saves", [])
	var bgd: Dictionary = Rules.tables.get("backgrounds", {}).get(background, {})
	s["background"] = background
	s["profSkills"] = preset.get("skills", []) + heritage.get("skills", []) + bgd.get("skills", [])
	var traits: Array = heritage.get("traits", [])
	s["features"] = traits.duplicate()
	if bool(preset.get("caster", false)):
		s["slots"] = Rules.full_caster_slots(1)
		var seed: Array = Rules.tables.get("class_spells", {}).get(cls, [])
		s["spells"] = []
		for sp in seed:
			if sp is Array and sp.size() >= 2 and int(sp[1]) <= 1:
				s["spells"].append({"name": str(sp[0]), "level": int(sp[1])})
	GameState.set_sheet(s)
	_build_dice_menu()
	_render_sheet()
	_say_system("⚒ %s the %s %s steps into the tale — HP %d, %d gold." % [nm, race, cls, int(s["hpMax"]), int(s["gold"])])
	_session_zero(nm, race, cls, background)


## Session Zero — Step 3 of 3: set the table's tone before the first scene.
const GM_KNOBS := [
	["humor", "Humor", "Serious", "Comedic", 40],
	["spice", "Romance & spice", "None", "Bold", 0],
	["grit", "Grit & danger", "Gentle", "Brutal", 50],
	["pace", "Pace", "Slow", "Fast", 55],
	["rules", "Rules", "Loose", "Strict 5e", 50],
]


func _session_zero(nm: String, race: String, cls: String, background := "") -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Session Zero — set the tone"
	dlg.ok_button_text = "Begin the adventure ›"
	dlg.get_cancel_button().visible = false
	dlg.min_size = Vector2i(460, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var sliders := {}
	for k in GM_KNOBS:
		var row := Label.new()
		row.theme_type_variation = "HintLabel"
		row.text = "%s   %s ↔ %s" % [k[1], k[2], k[3]]
		box.add_child(row)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = k[4]
		sl.custom_minimum_size = Vector2(400, 0)
		box.add_child(sl)
		sliders[k[0]] = sl
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		var knobs := {}
		for key in sliders:
			knobs[key] = int(sliders[key].value)
		GameState.save_kind("gm", knobs)
		dlg.queue_free()
		Mode.enter("Exploration")
		_last_player_msg = "I arrive."
		_stream(Composer.envelope("[Session zero: I am %s, a level 1 %s %s%s. Open the adventure — set the very first scene, introduce where I am and why today is different, and end on a choice.]" % [nm, race, cls, (", " + str(Rules.tables.get("backgrounds", {}).get(background, {}).get("line", ""))) if background != "" else ""])))


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
	row.modulate.a = 0.0
	_thread.add_child(row)
	create_tween().tween_property(row, "modulate:a", 1.0, 0.35)
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
	if not Mode.can("send_message"):
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	_msg.text = ""
	_set_check({})
	_say_me(_bb(msg))
	_last_player_msg = msg
	if not GameState.is_dm():
		_stream(msg)  # companions get your words, not a rules envelope
		return
	var beats: Array = await Chronicle.recall(msg)
	_stream(Composer.envelope(msg, beats))


var _last_framed := ""


func _stream(framed: String) -> void:
	_last_framed = framed
	_streaming = true
	Mode.busy = true
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


## ↻ Retell: drop the last GM reply and stream the same framed message again.
func _regen() -> void:
	if not Mode.can("retell") or _last_framed == "" or _gm_rt == null:
		return
	var row := _gm_rt.get_parent().get_parent()  # rt -> panel -> row
	if row != null and row.get_parent() == _thread:
		row.queue_free()
	_gm_rt = null
	_stream(_last_framed)


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		if _gm_rt != null:
			_gm_rt.append_text("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false), _bb(str(d.get("error", "stream error")))])
	elif d.get("type", "") == "tool_output" and str(d.get("image_url", "")) != "":
		_show_image(str(d["image_url"]))


func _on_done(_ok: bool) -> void:
	_streaming = false
	Mode.busy = false
	_send_btn.disabled = false
	var tail: Dictionary = Tags.parse(_acc.substr(_shown))
	if _gm_rt != null:
		if str(tail["clean"]) != "":
			_gm_rt.append_text(_bb(tail["clean"]))
		if _acc.strip_edges() == "":
			_gm_rt.clear()
			_gm_rt.append_text("[color=%s][i]The GM falls silent — try again or rephrase.[/i][/color]" % Ui.c("ink_dim").to_html(false))
	if not GameState.is_dm():
		_scroll_bottom()  # pure conversation: no tags, no rolls, no chronicling
		return
	var parsed: Dictionary = Tags.parse(_acc)
	_apply_world_tags(parsed["tags"])
	Chronicle.record(_last_player_msg, str(parsed["clean"]))
	if RegEx.create_from_string("\bTHE END\b").search(str(parsed["clean"])):
		Sfx.play("chime")
		Sfx.play("sting")
		var fin_rt := _bubble("gm")
		fin_rt.append_text("[color=%s][b]🏁 THE TALE IS COMPLETE[/b][/color]
[i]This campaign has reached its end — the world remembers. Free roam continues if you keep talking, or return to the menu for a new tale.[/i]" % Ui.c("gold_soft").to_html(false))
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
					Sfx.play("chime")
					_say_system("%s gold %+d — purse now %d" % ["💰" if delta > 0 else "🪙", delta, total])
			"loot":
				var nm := str(a.get("name", "")).strip_edges()
				if nm != "":
					GameState.add_item(nm, str(a.get("rarity", "common")), maxi(1, int(a.get("qty", 1))))
					Sfx.play("chime")
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
			"scene":
				var place := str(a.get("place", "")).strip_edges()
				if place != "" and not _conjuring:
					_repaint_scene(place)
			"companion":
				var cn := str(a.get("name", "")).strip_edges()
				if cn != "":
					var note := GameState.add_companion(cn, str(a.get("role", "")))
					if note != "":
						Sfx.play("chime")
						_say_system(note.replace("*", ""))
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
				Sfx.play("sting")
				var line := Combat.enter(label)
				if line != "":
					_say_system(line.replace("*", ""))
				first = false
			else:
				Combat.add_foe(label)
	_render_combat()


func _end_combat() -> void:
	Mode.enter("Exploration")
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
	Sfx.play("dice")
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
	if _pending_check.is_empty() or not (Mode.can("roll") or Mode.can("death_save")):
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
		if bool(dr["revived"]) or bool(dr["stable"]):
			Mode.enter("Combat")  # the fight goes on around you
		if bool(dr["dead"]):
			Mode.enter("GameOver")
			# The epitaph: what this run amounted to.
			var s := GameState.sheet()
			var c: Dictionary = GameState.clock()
			var rt := _bubble("gm")
			rt.append_text("[color=%s][b]☠ HERE ENDS THE TALE OF %s[/b][/color]\nLevel %d %s %s · survived to day %d · %d XP · %d gold in the purse\n[i]The dice remember what the living forget.[/i]" % [
				Ui.c("danger").to_html(false), _bb(str(s.get("name", "?")).to_upper()),
				int(s.get("level", 1)), _bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))),
				int(c.get("day", 1)), int(s.get("xp", 0)), int(s.get("gold", 0))])
			_say_system("A long rest starts a new dawn… if the GM allows it.")
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
	pop.add_separator("Ask the GM")
	idx += 1
	pop.add_item("📖 Learn a spell…", 900)
	pop.add_item("🤝 Recruit an ally…", 901)
	if not pop.id_pressed.is_connected(_free_check):
		pop.id_pressed.connect(_free_check)


func _free_check(id: int) -> void:
	if not (Mode.can("roll") or Mode.can("ask_gm")):
		return
	if id == 900:
		_ask_gm("Learn a spell", "Which spell do you seek?",
			func(x): return "[I want to learn the spell %s. As GM, decide honestly if I could access it here and what it costs — gold, a favor, training time. If you grant it, say clearly that I learn it and tag [[spell-learned name=\"%s\"]].]" % [x, x])
		return
	if id == 901:
		_ask_gm("Recruit an ally", "Who do you ask to join you?",
			func(x): return "[I ask %s to join my party as a companion. Decide honestly from our history whether they agree — if they do, tag [[companion name=\"%s\"]].]" % [x, x])
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


## A one-line ask that the GM adjudicates (learn a spell, recruit an ally).
func _ask_gm(title: String, placeholder: String, frame: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.ok_button_text = "Ask"
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.custom_minimum_size = Vector2(360, 0)
	dlg.add_child(input)
	add_child(dlg)
	dlg.popup_centered()
	input.grab_focus()
	dlg.confirmed.connect(func():
		var x := input.text.strip_edges()
		dlg.queue_free()
		if x == "" or _streaming:
			return
		_say_me(_bb("I ask about: %s" % x))
		_last_player_msg = "I ask about " + x
		_stream(Composer.envelope(str(frame.call(x)))))


# ── Sheet actions ────────────────────────────────────────────────────────────
func _on_sheet_action(meta) -> void:
	var parts := str(meta).split(":", true, 1)
	if not Mode.can("panels"):
		return
	if parts.size() == 1:
		parts = [parts[0], ""]
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
		"feat":
			note = GameState.use_feature(parts[1].uri_decode())
			tell_gm = note != ""
		"portrait":
			_conjure_portrait(parts[1].uri_decode())
			return
		"haggle":
			var hres: Dictionary = Rules.resolve_check({"ability": "CHA", "skill": "Persuasion", "dc": 12}, GameState.sheet(), GameState.inv())
			await _animate_die(20, int(hres.get("roll", 10)), "Persuasion")
			_shop_markup = 0.8 if int(hres["total"]) >= 12 else 1.1
			_say_me(_md(str(hres["text"])))
			_say_system("The keeper %s." % ("softens — a fifth off everything" if _shop_markup < 1.0 else "bristles — prices nudge up"))
			_open_shop()
			return
		"buy":
			var bits := parts[1].split("|")
			var price := int(bits[1]) if bits.size() > 1 else 0
			if int(GameState.sheet().get("gold", 0)) < price:
				_say_system("Not enough gold for the %s (%d needed)." % [bits[0].uri_decode(), price])
				return
			GameState.add_gold(-price)
			GameState.add_item(bits[0].uri_decode())
			note = "🛒 *You buy the %s for %d gold.*" % [bits[0].uri_decode(), price]
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
	if not Mode.can("combat_action"):
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
			var eid := str(cur.get("id", ""))
			if not Combat.adjacent(eid, "pc"):
				var moved := Combat.enemy_approach(eid)
				if not Combat.adjacent(eid, "pc"):
					_say_system("The %s closes in — %d ft nearer." % [str(cur.get("name", "?")), moved * Combat.FEET_PER_CELL])
					return
			var r: Dictionary = Combat.enemy_turn(cur)
			if r.has("pending"):
				_reaction_overlay(r["pending"], r["reactions"])
				return
			_deliver_enemy_result(r)
		elif str(cur.get("id", "")).begins_with("cmp"):
			var cr: Dictionary = Combat.companion_turn(cur)
			if str(cr["msg"]) != "":
				_say_me(_md(str(cr["msg"])))
		elif str(cur.get("id", "")) == "pc":
			_say_system("Round %d — your turn." % int(c.get("round", 1)))
		return
	if m.begins_with("atk:"):
		var r2: Dictionary = Combat.player_attack(m.substr(4))
		if str(r2.get("msg", "")).contains("damage"):
			Sfx.play("hit")
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


## ⚡ Reaction! The blow pends while you choose: Shield / Uncanny Dodge /
## Parry / take the hit. Closing the dialog takes the hit — never voids it.
func _reaction_overlay(pend: Dictionary, reactions: Array) -> void:
	var enemy: Dictionary = pend["enemy"]
	var dlg := AcceptDialog.new()
	dlg.title = "⚡ Reaction!"
	dlg.ok_button_text = "Take the hit"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(380, 0)
	lbl.text = "The %s's blow is coming in — %d vs your AC %d, %d damage%s." % [
		str(enemy.get("name", "?")), int(pend["total"]), int(pend["ac"]), int(pend["dmg"]),
		" (CRIT)" if bool(pend["crit"]) else ""]
	box.add_child(lbl)
	var resolve := func(dmg: int, note: String):
		dlg.queue_free()
		var r: Dictionary = Combat.resolve_enemy_hit(enemy, dmg, bool(pend["crit"]), note)
		_deliver_enemy_result(r)
	if reactions.has("shield"):
		var b1 := Button.new()
		b1.text = "🛡 Shield — +5 AC, spends a slot"
		b1.pressed.connect(func():
			GameState.cast_spell("Shield")
			if int(pend["total"]) < int(pend["ac"]) + 5:
				resolve.call(0, "your Shield flares — the blow glances off")
			else:
				resolve.call(int(pend["dmg"]), "even the ward can't stop this one"))
		box.add_child(b1)
	if reactions.has("dodge"):
		var b2 := Button.new()
		b2.text = "🌀 Uncanny Dodge — halve the damage"
		b2.pressed.connect(func(): resolve.call(ceili(int(pend["dmg"]) / 2.0), "you twist away at the last instant"))
		box.add_child(b2)
	if reactions.has("parry"):
		var b3 := Button.new()
		b3.text = "🎖 Parry — superiority die + mod off the damage"
		b3.pressed.connect(func():
			GameState.use_feature("Combat Maneuver")
			var s := GameState.sheet()
			var red := randi_range(1, 8) + maxi(Rules.ability_mod(int(s["abilities"].get("STR", 10))), Rules.ability_mod(int(s["abilities"].get("DEX", 10))))
			resolve.call(maxi(0, int(pend["dmg"]) - red), "your parry turns %d of it aside" % red))
		box.add_child(b3)
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func(): dlg.queue_free(); resolve.call(int(pend["dmg"]), ""))


func _deliver_enemy_result(r: Dictionary) -> void:
	if str(r.get("msg", "")).contains("hits you"):
		Sfx.play("hit")
	if str(r.get("msg", "")) != "":
		_say_me(_md(str(r["msg"])))
	_render_sheet()
	_render_combat()
	if str(r.get("gm", "")) != "":
		_last_player_msg = str(r["msg"])
		_stream(Composer.envelope(str(r["gm"])))


## Click an open square on your turn: move there (spends the round's budget).
func _on_grid_move(cell: Array) -> void:
	if not Mode.can("combat_action"):
		return
	var c: Dictionary = Combat.data()
	if str(Combat.current(c).get("id", "")) != "pc":
		_say_system("Not your turn — press Next › to advance.")
		return
	if Combat.move_pc(cell):
		var left := int(Combat.move_budget(Combat.data()).get("left", 0))
		_say_system("You move — %d ft of movement left." % (left * Combat.FEET_PER_CELL))
	else:
		_say_system("Too far, or the square is taken.")


## Click a foe's token: attack if you can reach it (melee adjacency or ranged).
func _on_grid_token(id: String) -> void:
	if not Mode.can("combat_action"):
		return
	var c: Dictionary = Combat.data()
	var m := {}
	for x in c.get("combatants", []):
		if str(x.get("id", "")) == id:
			m = x
	if m.is_empty() or m.get("side") != "enemy" or int(m.get("hp", 0)) <= 0:
		return
	var wpn := GameState.item_by_id(str(GameState.inv().get("equipped", {}).get("weapon", "")))
	var ranged: bool = Combat.weapon_props(str(wpn.get("name", "fists")))["ranged"]
	if not ranged and not Combat.adjacent("pc", id):
		_say_system("The %s is %d ft away — move in, or ready a ranged weapon." % [str(m.get("name", "?")),
			Combat.distance(Combat.cell_of("pc"), Combat.cell_of(id)) * Combat.FEET_PER_CELL])
		return
	_on_combat_action("atk:" + id)


func _render_combat() -> void:
	var c: Dictionary = Combat.data()
	var fighting := bool(c.get("active", false))
	_combat_panel.visible = fighting
	_battle_grid.visible = fighting
	if fighting:
		Combat.ensure_positions()
	# The room darkens toward ember-red while steel is out.
	var tween := create_tween()
	tween.tween_property(_battle_tint, "color:a", 0.05 if fighting else 0.0, 0.8)
	if not fighting:
		return
	if Mode.state in ["Exploration", "Victory", "Loading"]:
		Mode.enter("Combat")
	if not Combat.pc_down().is_empty():
		if Mode.state == "Combat":
			Mode.enter("Death")  # the only roll that matters now is the save
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
	if not Mode.can("rest"):
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


## The GM moved us somewhere new — quietly repaint the backdrop (no inline).
func _repaint_scene(place: String) -> void:
	_conjuring = true
	var prompt := "%s, in the world of %s. Atmospheric %s establishing scene, cinematic lighting, no people, no text." % [
		place, str(GameState.character.get("name", "")).split(":")[0],
		{"neonspire": "cyberpunk sci-fi", "everyday": "slice-of-life"}.get(GameState.world_id(), "high fantasy")]
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate", {"prompt": prompt})
	_conjuring = false
	if r.get("_status", 0) != 200 or str(r.get("image_url", "")) == "":
		return
	var bytes := await Api.fetch_bytes(str(r["image_url"]).trim_prefix(Api.BASE))
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
		return
	_scene_art.texture = ImageTexture.create_from_image(img)
	var tw := create_tween()
	_scene_art.modulate.a = 0.0
	tw.tween_property(_scene_art, "modulate:a", 0.45, 1.8)


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
	if _panel_mode == "codex" and _sheet_panel.visible:
		_render_codex()
		return
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
			var row := "  %s" % _bb(str(f))
			var key := GameState.feature_action_key(str(f))
			if key != "":
				var left := GameState.feature_uses_left(key)
				row += "  [url=feat:%s]◆ use (%d/%d)[/url]" % [key.uri_encode(), left, int(GameState.FEATURE_ACTIONS[key]["uses"])] if left > 0 \
					else "  [color=%s]◇ spent[/color]" % Ui.c("ink_dim").to_html(false)
			lines.append(row)
	_sheet_panel.text = "\n".join(lines)


## 🛒 The trade screen: world-appropriate stock at honest prices. Buying is a
## sheet action (buy:<name>|<price>) so the GM narrates the purchase.
func _open_shop() -> void:
	var stock: Dictionary = Rules.tables.get("vendor_stock", {})
	var gold := Ui.c("gold_soft").to_html(false)
	var lines: Array[String] = ["[color=%s][b]🛒 The trader's wares[/b][/color]  (your purse: %d)" % [gold, int(GameState.sheet().get("gold", 0))]]
	for cat in ["weapon", "armor", "potion", "general", "food"]:
		var goods: Array = stock.get(cat, [])
		if goods.is_empty():
			continue
		lines.append("")
		lines.append("[color=%s][b]%s[/b][/color]" % [gold, cat.capitalize()])
		for g in goods:
			if g is Array and g.size() >= 2:
				var price := maxi(1, roundi(int(g[1]) * _shop_markup))
				lines.append("  %s — %d gold  [url=buy:%s|%d]buy[/url]" % [_bb(str(g[0])), price, str(g[0]).uri_encode(), price])
	if _shop_markup == 1.0:
		lines.append("
[url=haggle]💬 Haggle with the keeper[/url]")
	elif _shop_markup < 1.0:
		lines.append("
[i]The keeper likes you — prices are down a fifth.[/i]")
	else:
		lines.append("
[i]The keeper is annoyed — prices are up.[/i]")
	var rt := _bubble("gm")
	rt.append_text("\n".join(lines))
	rt.meta_clicked.connect(_on_sheet_action)


# ── The codex panel: the cast you've met and the threads you're pulling ─────
func _render_codex() -> void:
	var gold := Ui.c("gold_soft").to_html(false)
	_sheet_panel.clear()
	_sheet_panel.append_text("[color=%s][b]📜 The Cast[/b][/color]\n" % gold)
	var codex = GameState.state.get("codex", [])
	var any := false
	if codex is Array:
		for n in codex:
			if not (n is Dictionary) or str(n.get("name", "")) == "":
				continue
			any = true
			var tex := Art.texture_for("npc-" + str(n["name"]).to_lower().replace(" ", "-"))
			if tex != null:
				var img: Image = tex.get_image()
				img.resize(48, 48 * img.get_height() / maxi(1, img.get_width()))
				_sheet_panel.add_image(ImageTexture.create_from_image(img))
				_sheet_panel.append_text("  ")
			_sheet_panel.append_text("[b]%s[/b] — %s" % [_bb(str(n["name"])), _bb(str(n.get("role", "")))])
			var disp := str(n.get("disposition", ""))
			if disp != "":
				var dcol := gold if disp in ["ally", "friendly", "warm"] else (Ui.c("danger").to_html(false) if disp in ["hostile", "enemy"] else Ui.c("ink_dim").to_html(false))
				_sheet_panel.append_text("  [color=%s]● %s[/color]" % [dcol, disp])
			if tex == null:
				_sheet_panel.append_text("  [url=portrait:%s]🖼[/url]" % str(n["name"]).uri_encode())
			var note := str(n.get("note", ""))
			if note != "":
				_sheet_panel.append_text("\n[color=%s]%s[/color]" % [Ui.c("ink_dim").to_html(false), _bb(note)])
			_sheet_panel.append_text("\n\n")
	if not any:
		_sheet_panel.append_text("[color=%s]No one of note yet — the codex writes itself as you meet people.[/color]\n\n" % Ui.c("ink_dim").to_html(false))
	_sheet_panel.append_text("[color=%s][b]Quests[/b][/color]\n" % gold)
	var quests = GameState.state.get("quests", [])
	var anyq := false
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("title", "")) != "":
				anyq = true
				var done: bool = str(q.get("status", "active")) == "done"
				_sheet_panel.append_text("%s %s%s\n" % ["✓" if done else "◈", _bb(str(q["title"])),
					(" — " + _bb(str(q.get("desc", "")))) if str(q.get("desc", "")) != "" else ""])
	if not anyq:
		_sheet_panel.append_text("[color=%s]No threads yet — make a promise, take a job, swear revenge.[/color]\n" % Ui.c("ink_dim").to_html(false))


## Give a codex NPC a face: generate from their appearance anchor, cache, redraw.
func _conjure_portrait(nm: String) -> void:
	var entry := {}
	for n in GameState.state.get("codex", []):
		if n is Dictionary and str(n.get("name", "")).nocasecmp_to(nm) == 0:
			entry = n
			break
	var look := str(entry.get("appearance", entry.get("note", "")))
	_say_system("🖼 Painting %s…" % nm)
	await Art.ensure("npc-" + nm.to_lower().replace(" ", "-"),
		"portrait of %s, %s. %s character portrait, painterly, head and shoulders" % [nm, look,
		{"neonspire": "cyberpunk", "everyday": "contemporary"}.get(GameState.world_id(), "fantasy")])
	if _panel_mode == "codex":
		_render_codex()


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

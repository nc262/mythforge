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
var _insp_armed := false  # spend Inspiration on the next roll
var _turns_since_tick := 0  # the clock walks every 3 player turns

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
			_render_codex()
		_auto_portrait())
	$Margin/Split/ChatBox/Input/ShortRest.pressed.connect(func(): _rest("short"))
	$Margin/Split/ChatBox/Input/LongRest.pressed.connect(func(): _rest("long"))
	$Margin/Split/ChatBox/Input/Scene.pressed.connect(_conjure_scene)
	$Margin/Split/ChatBox/Input/Shop.pressed.connect(_open_shop)
	$Margin/Split/ChatBox/Input/Bag.pressed.connect(_open_inventory)
	$Margin/Split/ChatBox/Input/Retell.pressed.connect(_regen)
	_roll_bar.pressed.connect(_roll_pending)
	_sheet_panel.meta_clicked.connect(_on_sheet_action)
	_combat_panel.meta_clicked.connect(_on_combat_action)
	_battle_grid.cell_clicked.connect(_on_grid_move)
	_battle_grid.token_clicked.connect(_on_grid_token)
	Combat.changed.connect(_render_combat)
	Art.art_ready.connect(func(k):
		if Combat.active() and str(k) == str(_battle_grid.map_key):
			Combat.bake_terrain(Image.load_from_file(Art.path_for(str(k)))))
	GameState.leveled_up.connect(_level_up_ceremony)
	_init_rail = HBoxContainer.new()
	_init_rail.name = "InitRail"
	_init_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_init_rail.add_theme_constant_override("separation", Ui.SPACE["s"])
	_init_rail.visible = false
	var chatbox: VBoxContainer = $Margin/Split/ChatBox
	chatbox.add_child(_init_rail)
	chatbox.move_child(_init_rail, _battle_grid.get_index())
	Chronicle.reset()
	var world := str(GameState.character.get("world_id", ""))
	$Margin/Split/ChatBox/Header.text = "✦ %s%s" % [str(GameState.character.get("name", "?")),
		("  ·  " + world) if world != "" else ""]
	Sfx.music(GameState.world_id() if GameState.world_id() in ["embervale", "neonspire", "everyday"] else "arcane")
	# The world's key art is the room you sit in from the first breath.
	var world_tex := Art.texture_for(world)
	if world_tex != null:
		_scene_art.texture = world_tex
		_scene_art.modulate.a = 0.35
		_ken_burns()
	# Companion chat (non-DM persona): a quiet table for two — no dice, no HUD.
	if not GameState.is_dm():
		Mode.enter("Dialogue")
		for btn in ["SheetBtn", "CodexBtn", "Dice", "Shop", "Bag", "ShortRest", "LongRest", "Scene"]:
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
	_msg.grab_focus()


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
	Art.ensure_hero_portrait(GameState.cid(), s)
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
	_turns_since_tick += 1
	if _turns_since_tick >= 3 and not Combat.active():
		_turns_since_tick = 0
		GameState.advance_time(1)
		_render_chips()
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
					_say_system("%s %s %+d — purse now %d" % ["💰" if delta > 0 else "🪙", GameState.currency(), delta, total])
			"loot":
				var nm := str(a.get("name", "")).strip_edges()
				if nm != "":
					GameState.add_item(nm, str(a.get("rarity", "common")), maxi(1, int(a.get("qty", 1))))
					Art.ensure_item_icon(nm)
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


# ── The level-up ceremony (M2): choices, not just numbers ───────────────────
func _level_up_ceremony(from_level: int, to_level: int) -> void:
	var prev_mode: StringName = Mode.state
	Mode.enter("LevelUp")
	Sfx.play("chime")
	var s := GameState.sheet()
	var cls := str(s.get("cls", ""))
	var dlg := ConfirmationDialog.new()
	dlg.title = "🎉 Level %d — %s grows" % [to_level, str(s.get("name", "the hero"))]
	dlg.ok_button_text = "Embrace it ›"
	dlg.get_cancel_button().visible = false
	dlg.min_size = Vector2i(480, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	# HP: the average is already applied — offer the gamble.
	var die := int(s.get("hitDie", 8))
	var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
	var levels := to_level - from_level
	var hp_l := Label.new()
	hp_l.theme_type_variation = "HintLabel"
	hp_l.text = "HP: took the average (+%d per level). Feeling lucky?" % maxi(1, die / 2 + 1 + con)
	var hp_btn := Button.new()
	hp_btn.text = "🎲 Roll the hit die instead (d%d%+d, per level)" % [die, con]
	var rolled_hp := false
	hp_btn.pressed.connect(func():
		if rolled_hp:
			return
		rolled_hp = true
		var sh := GameState.sheet()
		var delta := 0
		for i in levels:
			delta += maxi(1, randi_range(1, die) + con) - maxi(1, die / 2 + 1 + con)
		sh["hpMax"] = maxi(1, int(sh["hpMax"]) + delta)
		sh["hp"] = sh["hpMax"]
		GameState.set_sheet(sh)
		hp_btn.text = "🎲 Rolled — %s%d HP vs the average" % ["+" if delta >= 0 else "", delta]
		hp_btn.disabled = true
		_render_sheet())
	box.add_child(hp_l)
	box.add_child(hp_btn)
	# Subclass at 3.
	var sub_in: OptionButton = null
	var subs: Array = Rules.tables.get("subclasses", {}).get(cls, [])
	if to_level >= 3 and str(s.get("subclass", "")) == "" and not subs.is_empty():
		var sub_l := Label.new()
		sub_l.theme_type_variation = "HintLabel"
		sub_l.text = "Choose your path:"
		sub_in = OptionButton.new()
		for sc in subs:
			sub_in.add_item("%s — %s" % [str(sc.get("name", "?")), str(sc.get("line", "")).left(60)])
		box.add_child(sub_l)
		box.add_child(sub_in)
	# Feat or ASI at the milestone levels the run crossed.
	var feat_in: OptionButton = null
	var crossed_asi := false
	for l in range(from_level + 1, to_level + 1):
		if l in [4, 8]:
			crossed_asi = true
	if crossed_asi:
		var feat_l := Label.new()
		feat_l.theme_type_variation = "HintLabel"
		feat_l.text = "A milestone — take a feat, or raise an ability:"
		feat_in = OptionButton.new()
		for ab in Rules.ABILITIES:
			feat_in.add_item("+2 %s (ASI)" % ab)
		var feats: Array = Rules.tables.get("feats", {}).keys()
		feats.sort()
		for f in feats:
			feat_in.add_item("Feat: %s — %s" % [str(f), str(Rules.tables["feats"][f].get("desc", "")).left(50)])
		box.add_child(feat_l)
		box.add_child(feat_in)
	# New spells for casters.
	var spell_in: OptionButton = null
	var learnable := Rules.learnable_spells(s)
	if not learnable.is_empty():
		var sp_l := Label.new()
		sp_l.theme_type_variation = "HintLabel"
		sp_l.text = "A new spell reveals itself:"
		spell_in = OptionButton.new()
		for sp in learnable:
			spell_in.add_item("%s (%s) — %s" % [str(sp.get("name", "?")),
				("lvl %d" % int(sp["level"])) if int(sp.get("level", 0)) > 0 else "cantrip",
				str(sp.get("desc", "")).left(46)])
		box.add_child(sp_l)
		box.add_child(spell_in)
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		var sh := GameState.sheet()
		var gains: Array[String] = []
		if sub_in != null:
			var chosen: Dictionary = subs[sub_in.selected]
			sh["subclass"] = str(chosen.get("name", ""))
			var grants: Array = Rules.tables.get("subclass_grants", {}).get(sh["subclass"], [])
			sh["features"] = sh.get("features", []) + grants
			gains.append("the path of the %s" % sh["subclass"])
		if feat_in != null:
			var idx := feat_in.selected
			if idx < Rules.ABILITIES.size():
				var ab: String = Rules.ABILITIES[idx]
				sh["abilities"][ab] = int(sh["abilities"].get(ab, 10)) + 2
				gains.append("+2 %s" % ab)
			else:
				var fname: String = feat_in.get_item_text(idx).trim_prefix("Feat: ").split(" — ")[0]
				sh["feats"] = sh.get("feats", []) + [fname]
				gains.append("the %s feat" % fname)
		if spell_in != null:
			var sp: Dictionary = learnable[spell_in.selected]
			sh["spells"] = sh.get("spells", []) + [{"name": sp.get("name", ""), "level": int(sp.get("level", 0))}]
			gains.append("the spell %s" % str(sp.get("name", "")))
		GameState.set_sheet(sh)
		dlg.queue_free()
		Mode.enter(prev_mode)
		_build_dice_menu()
		_render_sheet()
		if not gains.is_empty():
			_say_system("🎉 Level %d: you gain %s." % [to_level, ", ".join(gains)]))


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
	if _insp_armed and str(check.get("adv", "")) == "" and check.get("type", "") != "damage":
		check["adv"] = "adv"
		_insp_armed = false
		GameState.spend_inspiration()
		_say_system("✨ Inspiration spent — advantage.")
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	if int(res.get("roll", 0)) == 20 and GameState.grant_inspiration():
		Sfx.play("chime")
		_say_system("✨ A natural 20 — you gain Inspiration.")
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
	pop.add_item("🔨 Craft something…", 902)
	if bool(GameState.sheet().get("inspiration", false)):
		pop.add_item("✨ Spend Inspiration — advantage on your next roll", 903)
	if not pop.id_pressed.is_connected(_free_check):
		pop.id_pressed.connect(_free_check)


func _free_check(id: int) -> void:
	if not (Mode.can("roll") or Mode.can("ask_gm")):
		return
	if id == 900:
		_ask_gm("Learn a spell", "Which spell do you seek?",
			func(x): return "[I want to learn the spell %s. As GM, decide honestly if I could access it here and what it costs — gold, a favor, training time. If you grant it, say clearly that I learn it and tag [[spell-learned name=\"%s\"]].]" % [x, x])
		return
	if id == 903:
		_insp_armed = true
		_say_system("✨ Inspiration armed — your next roll has advantage.")
		return
	if id == 902:
		_ask_gm("Craft something", "What do you try to make (and from what)?",
			func(x): return "[I try to craft: %s. Check my pack in the context — decide honestly if my materials and skills allow it, what it costs (time, gold, a roll), and if I succeed, grant it with [[loot name=\"...\"]] and take costs with [[gold delta=-N]].]" % x)
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
	if _insp_armed:
		check["adv"] = "adv"
		_insp_armed = false
		GameState.spend_inspiration()
		_say_system("✨ Inspiration spent — advantage.")
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	if int(res.get("roll", 0)) == 20 and GameState.grant_inspiration():
		Sfx.play("chime")
		_say_system("✨ A natural 20 — you gain Inspiration.")
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


## 🎒 The paper-doll inventory window.
func _open_inventory() -> void:
	if not Mode.can("panels"):
		return
	var win := preload("res://scenes/ui/inventory_window.gd").new()
	win.inventory_changed.connect(func(): _render_sheet())
	add_child(win)
	win.popup_centered()
	Ui.ritual_open(win)


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
		"tune":
			_session_zero_retune()
			return
		"snap":
			_save_snapshot()
			return
		"chron":
			_open_chronicle()
			return
		"atlas":
			_open_atlas()
			return
		"map":
			_open_world_map()
			return
		"travel":
			_travel_to(parts[1].uri_decode())
			return
		"snaprecall":
			_recall_snapshot(parts[1].uri_decode())
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
var _init_rail: HBoxContainer       # the initiative rail: faces in turn order
var _rail_turn_id := ""             # whose chip pulsed last
var _armed_spell := ""              # a combat spell waiting for its target click
var _auto_round := false            # End Turn's auto-sweep paused on a reaction
var _round_gm: Array[String] = []   # enemy-turn GM notes, streamed once per sweep


## The one gate for every combat click — self-heals Mode drift (a fight is on
## but the FSM sat in Dialogue/whatever: enter Combat) and never fails silent.
func _can_fight() -> bool:
	if Combat.active() and not Mode.busy and Mode.state not in ["Combat", "Death", "GameOver"]:
		Mode.enter("Combat")
	if Mode.can("combat_action"):
		return true
	if Mode.busy:
		_say_system("⏳ The GM is mid-tale — wait for the words to settle.")
	elif Mode.state == "Death":
		_say_system("☠ You are down — roll your death save.")
	return false


func _on_combat_action(meta) -> void:
	if not _can_fight():
		return
	var m := str(meta)
	if m == "cend":
		_end_combat()
		_last_player_msg = "The fight ends."
		_stream(Composer.envelope("[I end the fight here. Narrate the aftermath of the battle briefly.]"))
		return
	if m == "cnext":
		_run_round()
		return
	if m.begins_with("spl:"):
		_cast_in_combat(m.substr(4).uri_decode())
		return
	if m.begins_with("atk:"):
		_deliver_player_hit(Combat.player_attack(m.substr(4)))


## End Turn: everyone else acts on their own — enemies close and strike
## (reactions still pend for your choice), companions swing — then play
## returns to you. The GM hears one combined note per sweep, not one per foe.
func _run_round() -> void:
	var guard := 0
	while guard < 32:
		guard += 1
		Combat.next_turn()
		var c: Dictionary = Combat.data()
		if not bool(c.get("active", false)):
			return
		var cur: Dictionary = Combat.current(c)
		var cid := str(cur.get("id", ""))
		if cid == "pc":
			_render_combat()
			if Combat.pc_down().is_empty():
				_say_system("Round %d — your turn: move on the board, ⚔ attack, or ✦ cast." % int(c.get("round", 1)))
			_flush_round_gm()
			return
		if cur.get("side") == "enemy" and int(cur.get("hp", 0)) > 0:
			if not Combat.adjacent(cid, "pc"):
				var moved := Combat.enemy_approach(cid)
				if not Combat.adjacent(cid, "pc"):
					if moved > 0:
						_say_system("The %s closes in — %d ft nearer." % [str(cur.get("name", "?")), moved * Combat.FEET_PER_CELL])
					continue
			var r: Dictionary = Combat.enemy_turn(cur)
			if r.has("pending"):
				_auto_round = true
				_reaction_overlay(r["pending"], r["reactions"])
				return
			if str(r.get("msg", "")) != "":
				if str(r["msg"]).contains("hits you"):
					Sfx.play("hit")
				_say_me(_md(str(r["msg"])))
			if str(r.get("gm", "")) != "":
				_round_gm.append(str(r["gm"]))
			_render_sheet()
			if bool(r.get("down", false)):
				_render_combat()
				_flush_round_gm()
				return
		elif cid.begins_with("cmp"):
			var cr: Dictionary = Combat.companion_turn(cur)
			if str(cr["msg"]) != "":
				_say_me(_md(str(cr["msg"])))


func _flush_round_gm() -> void:
	if _round_gm.is_empty():
		return
	var notes := "\n".join(_round_gm)
	_round_gm = []
	_last_player_msg = notes
	_stream(Composer.envelope(notes))


## Deliver a player attack/cast result: sound, message, victory, GM note.
func _deliver_player_hit(r2: Dictionary) -> void:
	if str(r2.get("msg", "")).contains("damage"):
		Sfx.play("hit")
	if not bool(r2["spent"]):
		if str(r2["msg"]) != "":
			_say_system(str(r2["msg"]).replace("*", ""))
		return
	if str(r2["msg"]) == "":
		return
	_say_me(_md(str(r2["msg"])))
	_render_sheet()
	_render_combat()
	if bool(r2["won"]) or bool(r2["fell"]):
		_how_do_you_want_to_do_this(str(r2["msg"]), bool(r2["won"]))
	else:
		_last_player_msg = str(r2["msg"])
		_stream(Composer.envelope(str(r2["msg"])))


## ✦ A combat cast: one living foe → cast now; several → arm it and click one.
func _cast_in_combat(nm: String) -> void:
	var foes: Array = Combat.data().get("combatants", []).filter(func(x): return x.get("side") == "enemy" and int(x.get("hp", 0)) > 0)
	if foes.is_empty():
		return
	if foes.size() == 1:
		_deliver_player_hit(Combat.player_spell(str(foes[0]["id"]), nm))
		return
	_armed_spell = nm
	_say_system("✦ %s armed — click your target on the board." % nm)


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
	if _auto_round:
		_auto_round = false
		if str(r.get("gm", "")) != "":
			_round_gm.append(str(r["gm"]))
		if bool(r.get("down", false)):
			_flush_round_gm()
		else:
			_run_round()  # the sweep picks up where the reaction paused it
		return
	if str(r.get("gm", "")) != "":
		_last_player_msg = str(r["msg"])
		_stream(Composer.envelope(str(r["gm"])))


## Click an open square on your turn: move there (spends the round's budget).
func _on_grid_move(cell: Array) -> void:
	if not _can_fight():
		return
	var c: Dictionary = Combat.data()
	if str(Combat.current(c).get("id", "")) != "pc":
		_say_system("Not your turn — press Next › to advance.")
		return
	if Combat.move_pc(cell):
		var left := int(Combat.move_budget(Combat.data()).get("left", 0))
		_say_system("You move — %d ft of movement left." % (left * Combat.FEET_PER_CELL))
	elif Combat.terrain_at(cell) == "block":
		_say_system("Something solid stands there — no way through.")
	else:
		_say_system("Too far, or the square is taken.")


## Click a foe's token: attack if you can reach it (melee adjacency or ranged).
func _on_grid_token(id: String) -> void:
	if not _can_fight():
		return
	var c: Dictionary = Combat.data()
	var m := {}
	for x in c.get("combatants", []):
		if str(x.get("id", "")) == id:
			m = x
	if m.is_empty() or m.get("side") != "enemy" or int(m.get("hp", 0)) <= 0:
		return
	if _armed_spell != "":
		var spell_nm := _armed_spell
		_armed_spell = ""
		_deliver_player_hit(Combat.player_spell(id, spell_nm))
		return
	var wpn := GameState.item_by_id(str(GameState.inv().get("equipped", {}).get("weapon", "")))
	var ranged: bool = Combat.weapon_props(str(wpn.get("name", "fists")))["ranged"]
	if not ranged and not Combat.adjacent("pc", id):
		_say_system("The %s is %d ft away — move in, or ready a ranged weapon." % [str(m.get("name", "?")),
			Combat.distance(Combat.cell_of("pc"), Combat.cell_of(id)) * Combat.FEET_PER_CELL])
		return
	_on_combat_action("atk:" + id)


## The table's favorite question: the killing blow belongs to the player.
func _how_do_you_want_to_do_this(mech_msg: String, won: bool) -> void:
	if won:
		Sfx.play("chime")
		var flash := create_tween()
		flash.tween_property(_battle_tint, "color", Color(Ui.c("gold"), 0.12), 0.3)
		flash.tween_property(_battle_tint, "color", Color(Ui.c("danger"), 0.0), 1.2)
	var dlg := ConfirmationDialog.new()
	dlg.title = "The foe is finished."
	dlg.ok_button_text = "Strike ›"
	dlg.get_cancel_button().text = "Let the GM paint it"
	var input := LineEdit.new()
	input.placeholder_text = "How do you want to do this?"
	input.custom_minimum_size = Vector2(420, 0)
	dlg.add_child(input)
	add_child(dlg)
	dlg.popup_centered()
	input.grab_focus()
	var go := func(flourish: String):
		dlg.queue_free()
		if won:
			_end_combat()
		if flourish != "":
			_say_me(_bb("⚔ " + flourish))
		_last_player_msg = mech_msg
		var frame := "%s\n[%s%s]" % [mech_msg,
			("My finishing flourish: " + flourish + ". ") if flourish != "" else "",
			"Victory — the last foe falls! Narrate the killing blow in full cinema, then the aftermath." if won else "The foe falls — narrate the finish with cinema."]
		_stream(Composer.envelope(frame))
	dlg.confirmed.connect(func(): go.call(input.text.strip_edges()))
	dlg.canceled.connect(func(): go.call(""))
	input.text_submitted.connect(func(t): dlg.hide(); go.call(t.strip_edges()))


func _render_combat() -> void:
	var c: Dictionary = Combat.data()
	var fighting := bool(c.get("active", false))
	_combat_panel.visible = fighting
	_battle_grid.visible = fighting
	if _init_rail != null and not fighting:
		_init_rail.visible = false
	if fighting:
		Combat.ensure_positions()
		var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
		_battle_grid.map_key = Art.ensure_battle_map(here if here != "" else "a %s battlefield" % Art.world_flavor())
		if Art.has_art(_battle_grid.map_key):
			Combat.bake_terrain(Image.load_from_file(Art.path_for(_battle_grid.map_key)))
	# The room darkens toward ember-red while steel is out.
	var tween := create_tween()
	tween.tween_property(_battle_tint, "color:a", 0.05 if fighting else 0.0, 0.8)
	if fighting:
		Sfx.music("combat")
	else:
		Sfx.music(GameState.world_id() if GameState.world_id() in ["embervale", "neonspire", "everyday"] else "arcane")
	if not fighting:
		return
	if Mode.state not in ["Combat", "Death", "GameOver", "LevelUp"]:
		Mode.enter("Combat")  # steel is out — whatever mode we drifted to yields
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
	lines.append("[color=%s][b]⚔ COMBAT — Round %d[/b][/color]    [url=cnext]End turn ›[/url]    [url=cend]End combat[/url]" % [gold, int(c.get("round", 1))])
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
	var srow := _combat_spell_row(c)
	if srow != "":
		lines.append(srow)
	_combat_panel.text = "\n".join(lines)
	_render_init_rail(c, cur)


## The initiative rail: everyone in the fight as a face, in turn order —
## ally gold, enemy danger, the current actor swollen with a halo and pulsed.
func _render_init_rail(c: Dictionary, cur: Dictionary) -> void:
	_init_rail.visible = true
	for ch in _init_rail.get_children():
		ch.queue_free()
	var cur_id := str(cur.get("id", ""))
	for m in Combat.order(c):
		var id := str(m.get("id", ""))
		var is_turn := id == cur_id
		var chip := MythPortrait.new(52 if is_turn else 40,
			"gold" if m.get("side") == "ally" else "danger", is_turn)
		chip.set_portrait(Art.combatant_tex(m), str(m.get("name", "?")).left(1).to_upper())
		chip.set_vitals(clampf(float(m.get("hp", 0)) / maxf(1.0, float(m.get("hpMax", 1))), 0.0, 1.0), is_turn)
		if int(m.get("hp", 0)) <= 0:
			chip.modulate = Color(1, 1, 1, 0.32)
		chip.tooltip_text = "%s — %d/%d" % [str(m.get("name", "?")), int(m.get("hp", 0)), int(m.get("hpMax", 1))]
		_init_rail.add_child(chip)
		if is_turn and cur_id != _rail_turn_id:
			Ui.pulse(chip)
	_rail_turn_id = cur_id


## Damaging spells you can cast right now + slots + feet left, one tracker row.
func _combat_spell_row(c: Dictionary) -> String:
	var s := GameState.sheet()
	var parts: Array[String] = []
	var offensive := RegEx.create_from_string("\\d+d\\d+")
	var soothing := RegEx.create_from_string("(?i)heal|restore|regain|cure|mend")
	for sp in s.get("spells", []):
		var nm := str(sp.get("name", ""))
		var desc := str(Rules.spell_named(nm).get("desc", ""))
		if offensive.search(desc) == null or soothing.search(desc) != null:
			continue
		if int(sp.get("level", 0)) > 0:
			var has_slot := false
			for l in s.get("slots", {}).values():
				if l is Dictionary and int(l.get("used", 0)) < int(l.get("max", 0)):
					has_slot = true
			if not has_slot:
				continue
		parts.append("[url=spl:%s]✦ %s[/url]" % [nm.uri_encode(), _bb(nm)])
	var dim := Ui.c("ink_dim").to_html(false)
	var bits: Array[String] = []
	if not parts.is_empty():
		bits.append("   ".join(parts))
	var slots: Dictionary = s.get("slots", {})
	var slot_parts: Array[String] = []
	var sk := slots.keys()
	sk.sort()
	for l in sk:
		if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
			slot_parts.append("L%s %d/%d" % [l, maxi(0, int(slots[l]["max"]) - int(slots[l].get("used", 0))), int(slots[l]["max"])])
	if not slot_parts.is_empty():
		bits.append("[color=%s]Slots %s[/color]" % [dim, " ".join(slot_parts)])
	if str(Combat.current(c).get("id", "")) == "pc":
		bits.append("[color=%s]🥾 %d ft left[/color]" % [dim, int(Combat.move_budget(c).get("left", 0)) * Combat.FEET_PER_CELL])
	return "    ".join(bits)


## A BG3-style gilded section header for the sheet panel.
func _hdr(t: String) -> String:
	return "[center][color=%s]────  ✦  [b]%s[/b]  ✦  ────[/color][/center]" % [Ui.c("gold").to_html(false), t]


# ── Rests ────────────────────────────────────────────────────────────────────
func _rest(kind: String) -> void:
	if not Mode.can("rest"):
		return
	var r: Dictionary = GameState.short_rest() if kind == "short" else GameState.long_rest()
	_render_sheet()
	_say_me(_md(str(r["note"])))
	_last_player_msg = str(r["note"])
	_stream(Composer.envelope(str(r["gm"])))
	if kind == "long":
		_worldtick()


## The living world breathes between days: off-screen events surface as an
## aside and fold into memory (backend /worldtick extractor).
func _worldtick() -> void:
	if Chronicle.transcript.is_empty():
		return
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/worldtick", {
		"character_name": str(GameState.character.get("name", "")),
		"transcript": Chronicle.transcript,
		"codex": GameState.state.get("codex", []),
		"quests": GameState.state.get("quests", [])})
	var tick := str(r.get("tick", r.get("aside", r.get("text", ""))))
	if r.get("_status", 0) == 200 and tick != "":
		var rt := _bubble("gm")
		rt.append_text("[color=%s][i]Meanwhile… %s[/i][/color]" % [Ui.c("ink_dim").to_html(false), _bb(tick.left(400))])
		Chronicle.record("(a day passes)", "Meanwhile: " + tick.left(300))


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
	_ken_burns()
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


## The slow breath of the backdrop — Ken Burns, reduced-motion aware.
func _ken_burns() -> void:
	if Ui.reduce_motion:
		_scene_art.scale = Vector2.ONE
		return
	_scene_art.pivot_offset = _scene_art.size / 2.0
	_scene_art.scale = Vector2(1.03, 1.03)
	var tw := create_tween().set_loops()
	tw.tween_property(_scene_art, "scale", Vector2(1.09, 1.09), 24.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_scene_art, "scale", Vector2(1.03, 1.03), 24.0).set_trans(Tween.TRANS_SINE)


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
	_render_chips()
	if _panel_mode == "codex" and _sheet_panel.visible:
		_render_codex()
		return
	var s := GameState.sheet()
	# The hero's painted face crowns the sheet (commissioned lazily).
	if str(s.get("name", "")) != "" and not Art.has_art("hero-" + GameState.cid().validate_filename()):
		Art.ensure_hero_portrait(GameState.cid(), s)
	var gold := Ui.c("gold_soft").to_html(false)
	var lines: Array[String] = []
	lines.append("[url=tune]🎛 tune the GM[/url]  [url=snap]💾 save chapter[/url]  [url=chron]📜 chronicle[/url]  [url=atlas]🧭 atlas[/url]")
	lines.append("")
	var dim := Ui.c("ink_dim").to_html(false)
	lines.append("[center][font_size=22][color=%s][b]%s[/b][/color][/font_size]" % [gold, _bb(str(s.get("name", "?")))])
	lines.append("[color=%s]%s %s  ·  Level %d[/color][/center]" % [dim, _bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))), int(s.get("level", 1))])
	lines.append("")
	var hp := int(s.get("hp", 10))
	var hp_max := maxi(1, int(s.get("hpMax", 10)))
	var hb := clampi(roundi(12.0 * hp / hp_max), 0, 12)
	var hp_col := gold if hp * 2 >= hp_max else Ui.c("danger").to_html(false)
	lines.append("HP [b]%d / %d[/b]  [color=%s]%s[/color][color=%s]%s[/color]" % [hp, hp_max, hp_col, "▰".repeat(hb), Ui.c("ink_dim").to_html(false), "▱".repeat(12 - hb)])
	lines.append("AC [b]%d[/b]    Gold [b]%d[/b]    Perception [b]%d[/b]" % [Rules.eff_ac(s, GameState.inv()), int(s.get("gold", 0)), Rules.passive_perception(s)])
	lines.append("")
	var bcol := Ui.c("gold").darkened(0.25).to_html(false)
	var cbg := Ui.c("night").lightened(0.04).to_html(false)
	var plaques := "[table=3]"
	for k in Rules.ABILITIES:
		var v := int(s.get("abilities", {}).get(k, 10))
		plaques += "[cell border=#%s bg=#%s padding=10,7,10,7][center][color=%s]%s[/color]  [font_size=19][b]%d[/b][/font_size]  [color=%s]%+d[/color][/center][/cell]" % [
			bcol, cbg, gold, k, v, dim, Rules.ability_mod(v)]
	plaques += "[/table]"
	lines.append(plaques)
	var pool := int(s.get("level", 1))
	lines.append("Hit Dice [b]%d / %d[/b] (d%d)" % [pool - int(s.get("hitDiceUsed", 0)), pool, int(s.get("hitDie", 8))])
	if int(s.get("exhaustion", 0)) > 0:
		lines.append("[color=%s]Exhaustion level %d[/color]" % [Ui.c("danger").to_html(false), int(s["exhaustion"])])
	var prof: Array = s.get("profSkills", [])
	if not prof.is_empty():
		lines.append("")
		lines.append(_hdr("PROFICIENCIES"))
		lines.append("[center]%s[/center]" % _bb(", ".join(prof.map(func(x): return str(x)))))
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("")
		lines.append(_hdr("CONDITIONS"))
		lines.append("[center]%s[/center]" % _bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c)))))
	var spells: Array = s.get("spells", [])
	if not spells.is_empty():
		lines.append("")
		lines.append(_hdr("SPELLS"))
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
		lines.append(_hdr("PACK") + "  [color=%s](%d/%d)[/color]" % [Ui.c("ink_dim").to_html(false), items.size(), int(inv.get("slots", 24))])
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
		lines.append(_hdr("FEATS"))
		lines.append("[center]%s[/center]" % _bb(", ".join(feats.map(func(x): return str(x)))))
	var features: Array = s.get("features", [])
	if not features.is_empty():
		lines.append("")
		lines.append(_hdr("CLASS FEATURES"))
		for f in features:
			var row := "  %s" % _bb(str(f))
			var key := GameState.feature_action_key(str(f))
			if key != "":
				var left := GameState.feature_uses_left(key)
				row += "  [url=feat:%s]◆ use (%d/%d)[/url]" % [key.uri_encode(), left, int(GameState.FEATURE_ACTIONS[key]["uses"])] if left > 0 \
					else "  [color=%s]◇ spent[/color]" % Ui.c("ink_dim").to_html(false)
			lines.append(row)
	_sheet_panel.clear()
	var face := Art.round_tex("hero-" + GameState.cid().validate_filename(), 148)
	if face != null:
		_sheet_panel.append_text("[center]")
		_sheet_panel.add_image(face)
		_sheet_panel.append_text("[/center]\n")
	_sheet_panel.append_text("\n".join(lines))


## 🛒 The trading post: wares on the left, your pack on the right, the
## purse between. Haggling moves every price; the GM hears the visit once.
func _open_shop() -> void:
	if not Mode.can("shop"):
		return
	Mode.enter("Merchant")
	var deals: Array[String] = []
	var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	var here_shop := ""
	for l in Rules.world_locations(GameState.world_id()):
		if l is Dictionary and str(l.get("name", "")) == here and str(l.get("shop", "")) != "":
			here_shop = str(l.get("shop", ""))
	var dlg := AcceptDialog.new()
	dlg.title = "🛒 %s" % (here if here_shop != "" else "The trading post")
	dlg.ok_button_text = "Leave the counter"
	dlg.min_size = Vector2i(720, 480)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var purse := Label.new()
	purse.theme_type_variation = "HintLabel"
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	var wares := ItemList.new()
	wares.custom_minimum_size = Vector2(330, 320)
	var pack := ItemList.new()
	pack.custom_minimum_size = Vector2(330, 320)
	var wares_meta: Array = []
	var pack_meta: Array = []
	var refresh := func():
		purse.text = "Your purse: %d %s%s" % [int(GameState.sheet().get("gold", 0)), GameState.currency(),
			"   ·   the keeper likes you (−20%)" if _shop_markup < 1.0 else ("   ·   the keeper is annoyed (+10%)" if _shop_markup > 1.0 else "")]
		wares.clear()
		wares_meta.clear()
		var stock: Dictionary = Rules.tables.get("vendor_stock", {})
		for cat in ["weapon", "armor", "potion", "general", "food"]:
			var goods: Array = stock.get(cat, [])
			if goods.is_empty():
				continue
			wares.add_item("— %s —" % cat.to_upper(), null, false)
			wares_meta.append(null)
			for gd in goods:
				if gd is Array and gd.size() >= 2:
					var price := maxi(1, roundi(int(gd[1]) * _shop_markup))
					wares.add_item("%s   ·   %d gold" % [str(gd[0]), price])
					wares_meta.append({"name": str(gd[0]), "price": price})
		pack.clear()
		pack_meta.clear()
		for it in GameState.inv().get("items", []):
			var q := int(it.get("qty", 1))
			pack.add_item("%s%s   ·   sells %d" % [str(it.get("name", "")),
				(" ×%d" % q) if q > 1 else "", Rules.sell_value(str(it.get("rarity", "common")))])
			pack_meta.append(str(it.get("id", "")))
	var left := VBoxContainer.new()
	var lt := Label.new()
	lt.text = "The keeper's wares"
	var buy := Button.new()
	buy.text = "Buy ›"
	buy.pressed.connect(func():
		var sel := wares.get_selected_items()
		if sel.is_empty() or wares_meta[sel[0]] == null:
			return
		var w: Dictionary = wares_meta[sel[0]]
		if int(GameState.sheet().get("gold", 0)) < int(w["price"]):
			purse.text = "Not enough gold for the %s." % w["name"]
			return
		GameState.add_gold(-int(w["price"]))
		GameState.add_item(str(w["name"]))
		Sfx.play("chime")
		deals.append("bought a %s (%d gold)" % [w["name"], int(w["price"])])
		refresh.call())
	left.add_child(lt)
	left.add_child(wares)
	left.add_child(buy)
	var right := VBoxContainer.new()
	var rt2 := Label.new()
	rt2.text = "Your pack"
	var sell := Button.new()
	sell.text = "‹ Sell"
	sell.pressed.connect(func():
		var sel := pack.get_selected_items()
		if sel.is_empty():
			return
		var note := GameState.sell_item(str(pack_meta[sel[0]]))
		if note != "":
			Sfx.play("chime")
			deals.append(note.trim_prefix("You "))
		refresh.call())
	right.add_child(rt2)
	right.add_child(pack)
	right.add_child(sell)
	cols.add_child(left)
	cols.add_child(right)
	var haggle := Button.new()
	haggle.text = "💬 Haggle with the keeper (Persuasion, DC 12)"
	haggle.pressed.connect(func():
		if _shop_markup != 1.0:
			return
		var hres: Dictionary = Rules.resolve_check({"ability": "CHA", "skill": "Persuasion", "dc": 12}, GameState.sheet(), GameState.inv())
		_shop_markup = 0.8 if int(hres["total"]) >= 12 else 1.1
		deals.append("haggled (%s)" % ("won a fifth off" if _shop_markup < 1.0 else "annoyed the keeper"))
		haggle.disabled = true
		refresh.call())
	if here_shop != "":
		var trades := Label.new()
		trades.theme_type_variation = "HintLabel"
		trades.text = "This counter trades in: %s" % here_shop
		root.add_child(trades)
	root.add_child(purse)
	root.add_child(cols)
	root.add_child(haggle)
	dlg.add_child(root)
	add_child(dlg)
	refresh.call()
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		dlg.queue_free()
		Mode.enter("Exploration")
		_render_sheet()
		if not deals.is_empty():
			var summary := "🛒 *At the trader: %s.*" % "; ".join(deals)
			_say_me(_md(summary))
			_last_player_msg = summary
			_stream(Composer.envelope("[%s Briefly color the exchange — the keeper's manner, a passing detail.]" % summary.replace("*", ""))))


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


## Quietly give the newest face-less codex NPC a portrait (one per update).
func _auto_portrait() -> void:
	var codex = GameState.state.get("codex", [])
	if not (codex is Array):
		return
	for n in codex:
		if n is Dictionary and str(n.get("name", "")) != "":
			var key := "npc-" + str(n["name"]).to_lower().replace(" ", "-")
			if not Art.has_art(key):
				_conjure_portrait(str(n["name"]))
				return


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


# ── M2: tune / snapshots / atlas ─────────────────────────────────────────────
## Re-open the Session Zero knobs mid-campaign; saved live to the gm kind.
func _session_zero_retune() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "🎛 Tune the GM"
	dlg.ok_button_text = "So be it"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var knobs: Dictionary = GameState.state.get("gm", {}) if GameState.state.get("gm") is Dictionary else {}
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
		sl.value = int(knobs.get(k[0], k[4]))
		sl.custom_minimum_size = Vector2(400, 0)
		box.add_child(sl)
		sliders[k[0]] = sl
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		var out := {}
		for key in sliders:
			out[key] = int(sliders[key].value)
		GameState.save_kind("gm", out)
		dlg.queue_free()
		_say_system("🎛 The table's tone shifts."))


## 💾 A chapter marker: the backend distills the recent tale into a snapshot.
func _save_snapshot() -> void:
	if Chronicle.transcript.is_empty():
		_say_system("Nothing to chronicle yet — play a little first.")
		return
	_say_system("💾 The chronicler sets down this chapter…")
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/snapshot", {
		"character_id": GameState.cid(), "character_name": str(GameState.character.get("name", "")),
		"world_id": GameState.world_id(), "transcript": Chronicle.transcript})
	if r.get("_status", 0) == 200:
		var snap: Dictionary = r.get("snapshot", r)
		_say_system("💾 Chapter saved: %s" % str(snap.get("title", "untitled")))
	else:
		_say_system("The chronicler's ink ran dry (%s)." % str(r.get("_status", 0)))


## 📜 Chronicle: every saved chapter of this adventure.
func _open_chronicle() -> void:
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/snapshots?character_id=" + GameState.cid().uri_encode())
	var snaps: Array = r.get("snapshots", r.get("data", [])) if r.get("_status", 0) == 200 else []
	var rt := _bubble("gm")
	if snaps.is_empty():
		rt.append_text("[i]The chronicle is blank — 💾 save a chapter when a moment deserves remembering.[/i]")
		return
	var gold := Ui.c("gold_soft").to_html(false)
	rt.append_text("[color=%s][b]📜 The Chronicle[/b][/color]\n" % gold)
	for sn in snaps:
		if not (sn is Dictionary):
			continue
		rt.append_text("\n[b]%s[/b]\n%s\n" % [_bb(str(sn.get("title", "untitled"))), _bb(str(sn.get("story_so_far", "")))])
		var wc := str(sn.get("world_changes", ""))
		if wc != "":
			rt.append_text("[color=%s]%s[/color]\n" % [Ui.c("ink_dim").to_html(false), _bb(wc.left(220))])
		rt.append_text("[url=snaprecall:%s]▶ resume from this chapter[/url]\n" % str(sn.get("id", "")).uri_encode())
	rt.meta_clicked.connect(_on_sheet_action)


## Resume from a chapter: its summary re-anchors the GM's context.
func _recall_snapshot(id: String) -> void:
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/snapshots?character_id=" + GameState.cid().uri_encode())
	for sn in r.get("snapshots", r.get("data", [])):
		if sn is Dictionary and str(sn.get("id", "")) == id:
			_say_me(_bb("We pick the tale back up at: %s" % str(sn.get("title", ""))))
			_last_player_msg = "We resume from a saved chapter."
			_stream(Composer.envelope("[We resume from this saved chapter — treat it as where the story stands: %s. Re-set the scene and continue.]" % str(sn.get("story_so_far", ""))))
			return


const KIND_ICO := {"tavern": "🍺", "shop": "🛒", "landmark": "🏛", "wilds": "🌲", "home": "🏠"}


## 🧭 The atlas: the world's places; travel repaints the world (and risks it).
func _open_atlas() -> void:
	var locs: Array = Rules.world_locations(GameState.world_id())
	if locs.is_empty():
		var g2 := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
		for w in g2.get("state", {}).get("cworlds", []):
			if w is Dictionary and str(w.get("id", "")) == GameState.world_id():
				locs = w.get("locations") if w.get("locations") is Array else []
	var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	var rt := _bubble("gm")
	var gold := Ui.c("gold_soft").to_html(false)
	rt.append_text("[color=%s][b]🧭 The Atlas[/b][/color]   [url=map]🗺 open the map[/url]\n" % gold)
	if locs.is_empty():
		rt.append_text("[i]No charted places — the GM's narration is your map for now.[/i]")
		return
	for l in locs:
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", ""))
		rt.append_text("\n%s [b]%s[/b]%s — %s\n" % [KIND_ICO.get(str(l.get("kind", "")), "📍"), _bb(nm),
			"  [color=%s]● you are here[/color]" % gold if nm == here else "", _bb(str(l.get("lore", "")).left(90))])
		if nm != here:
			rt.append_text("[url=travel:%s]set off →[/url]\n" % nm.uri_encode())
	rt.meta_clicked.connect(_on_sheet_action)


## 🗺 The painted map: the world's key art with its places marked.
func _open_world_map() -> void:
	var locs: Array = Rules.world_locations(GameState.world_id())
	if locs.is_empty():
		var g2 := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
		for w in g2.get("state", {}).get("cworlds", []):
			if w is Dictionary and str(w.get("id", "")) == GameState.world_id():
				locs = w.get("locations") if w.get("locations") is Array else []
	if locs.is_empty():
		_say_system("No charted places to map yet.")
		return
	var dlg := AcceptDialog.new()
	dlg.title = "🗺 %s" % str(GameState.character.get("name", "the world")).split(":")[0]
	dlg.ok_button_text = "Close the map"
	Art.ensure_world_chart(GameState.world_id(), str(GameState.character.get("name", "")).split(":")[0])
	var map := preload("res://scenes/ui/world_map.gd").new()
	map.locations = locs
	map.here = str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	map.travel_requested.connect(func(place):
		dlg.queue_free()
		_travel_to(place))
	dlg.add_child(map)
	add_child(dlg)
	dlg.popup_centered()


func _travel_to(place: String) -> void:
	if not Mode.can("send_message"):
		return
	var world = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	world["here"] = place
	GameState.save_kind("world", world)
	GameState.advance_time(1)
	_say_system("🧭 You set off for %s." % place)
	_repaint_scene(place)
	_last_player_msg = "I travel to %s." % place
	# The road is never guaranteed: 1-in-5 journeys meet something.
	if randf() < 0.2:
		_stream(Composer.envelope("[I travel to %s — but something finds me on the road. Run a brief encounter (a threat, a stranger, or a wonder), then let me arrive.]" % place))
	else:
		_stream(Composer.envelope("[I travel to %s. Describe the journey briefly and my arrival — who is about, what I notice first.]" % place))


## Dusk cools the scene; deep night darkens it (time-of-day tint).
const _TIME_TINT := [Color(1.0, 0.92, 0.85), Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.97, 0.9), Color(0.95, 0.85, 0.85), Color(0.8, 0.78, 0.9), Color(0.62, 0.62, 0.78)]


func _apply_time_tint() -> void:
	var ti := clampi(int(GameState.clock().get("ti", 1)), 0, _TIME_TINT.size() - 1)
	var target: Color = _TIME_TINT[ti]
	target.a = _scene_art.modulate.a
	create_tween().tween_property(_scene_art, "modulate", target, 1.2)


## The banner chips: time · weather · place · quest · party wounds.
func _render_chips() -> void:
	_apply_time_tint()
	var c: Dictionary = GameState.clock()
	var bits: Array[String] = []
	var wx := str(c.get("wx", {}).get("ico", "")) if c.get("wx") is Dictionary else ""
	bits.append("🕰 %s · Day %d %s" % [GameState.TIMES[clampi(int(c.get("ti", 0)), 0, GameState.TIMES.size() - 1)], int(c.get("day", 1)), wx])
	var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	if here != "":
		bits.append("🧭 " + here)
	var quests = GameState.state.get("quests", [])
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("status", "active")) != "done" and str(q.get("title", "")) != "":
				bits.append("◈ " + str(q["title"]).left(36))
				break
	if bool(GameState.sheet().get("inspiration", false)):
		bits.append("✨ Inspiration")
	for cmp in GameState.sheet().get("companions", []):
		if cmp is Dictionary:
			var chp := int(cmp.get("hp", 0))
			var cmax := maxi(1, int(cmp.get("hpMax", 1)))
			bits.append("%s⚔ %s %d/%d" % ["🩸 " if chp * 3 < cmax else "", str(cmp.get("name", "")), chp, cmax])
	$Margin/Split/ChatBox/Chips.text = "    ".join(bits)


## Keyboard: Ctrl+S sheet · Ctrl+L codex · Ctrl+R retell · Space next turn
## (combat, when not typing) · Esc back to the message box.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		var btn: Button = $Margin/Split/ChatBox/Input/SheetBtn
		btn.button_pressed = not btn.button_pressed
	elif event.ctrl_pressed and event.keycode == KEY_L:
		var btn2: Button = $Margin/Split/ChatBox/Input/CodexBtn
		btn2.button_pressed = not btn2.button_pressed
	elif event.ctrl_pressed and event.keycode == KEY_R:
		_regen()
	elif event.keycode == KEY_SPACE and Mode.is_state("Combat") and not _msg.has_focus():
		_on_combat_action("cnext")
	elif event.ctrl_pressed and event.keycode == KEY_M:
		_open_world_map()
	elif event.ctrl_pressed and event.keycode == KEY_J:
		_open_journal()
	elif event.ctrl_pressed and event.keycode == KEY_I:
		_open_inventory()
	elif event.keycode == KEY_ESCAPE:
		_msg.grab_focus()


## 📖 The journal: everything the campaign remembers, searchable.
func _open_journal() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "📖 The Journal"
	dlg.ok_button_text = "Close"
	dlg.min_size = Vector2i(640, 520)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var search := LineEdit.new()
	search.placeholder_text = "Search quests, people, chapters…"
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.selection_enabled = true
	body.custom_minimum_size = Vector2(600, 430)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var render := func(q: String):
		q = q.to_lower()
		body.clear()
		var gold := Ui.c("gold_soft").to_html(false)
		var hits := 0
		body.append_text("[color=%s][b]Quests[/b][/color]\n" % gold)
		for qq in (GameState.state.get("quests", []) if GameState.state.get("quests") is Array else []):
			if qq is Dictionary:
				var line := "%s — %s" % [str(qq.get("title", "")), str(qq.get("desc", ""))]
				if q == "" or line.to_lower().contains(q):
					body.append_text("%s %s\n" % ["✓" if str(qq.get("status", "")) == "done" else "◈", _bb(line)])
					hits += 1
		body.append_text("\n[color=%s][b]People[/b][/color]\n" % gold)
		for n in (GameState.state.get("codex", []) if GameState.state.get("codex") is Array else []):
			if n is Dictionary:
				var line2 := "%s (%s) — %s" % [str(n.get("name", "")), str(n.get("role", "")), str(n.get("note", ""))]
				if q == "" or line2.to_lower().contains(q):
					body.append_text("• %s\n" % _bb(line2))
					hits += 1
		var snaps := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/snapshots?character_id=" + GameState.cid().uri_encode())
		body.append_text("\n[color=%s][b]Chapters[/b][/color]\n" % gold)
		for sn in snaps.get("snapshots", snaps.get("data", [])):
			if sn is Dictionary:
				var line3 := "%s — %s" % [str(sn.get("title", "")), str(sn.get("story_so_far", ""))]
				if q == "" or line3.to_lower().contains(q):
					body.append_text("💾 %s\n" % _bb(line3.left(220)))
					hits += 1
		if hits == 0:
			body.append_text("[i]Nothing matches — the story hasn't written that yet.[/i]")
	search.text_changed.connect(func(t): render.call(t))
	root.add_child(search)
	root.add_child(body)
	dlg.add_child(root)
	add_child(dlg)
	dlg.popup_centered()
	search.grab_focus()
	render.call("")
	dlg.confirmed.connect(func(): dlg.queue_free())


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

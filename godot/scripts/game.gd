extends Control
## The adventure screen: bubbled narration, streamed tokens, structured
## [[tag]] mechanics, the dice moment, and generated art as a living backdrop.

var _streaming := false
var _acc := ""          # full raw GM reply
var _shown := 0         # chars of _acc already printed (tags are held back)
var _lang_gate := false     # holding the opening back until its language is judged
var _lang_drifted := false  # opening was non-target language — retry on done
var _lang_retry := 0        # at most one silent retry per player turn
var _gm_started := false    # the waiting state has given way to real content
var _thinking: MythThinking = null   # the composed "GM is thinking" wait
var _empty_retry := 0       # a silent reply gets one quiet second attempt
const _GATE_MIN := 40       # visible chars to see before judging the language
var _pending_check := {}
var _last_player_msg := ""  # the visible player line, paired into memory beats
var _last_scene := ""       # the GM's last prose — the scene the player can see
var _suggest: HFlowContainer = null   # contextual verbs above the input (R6 PLAY-04)
var _suggest_plate: PanelContainer = null   # its backing, hidden with it
var _conjuring := false
var _gm_rt: RichTextLabel = null  # the bubble currently receiving tokens
var _panel_mode := "sheet"  # what the right panel shows: sheet | codex
var _sheet_sig := ""        # last-rendered HUD content; unchanged → no repaint
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
var _mood_layer: ColorRect = null   # A3: the presentation mood wash (never touches state)


func _ready() -> void:
	theme = Ui.theme
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	# No model, no narrator, and no server to quietly cover for it. Say so.
	Api.narrator_missing.connect(_on_narrator_missing)
	_send_btn.pressed.connect(func(): _send(_msg.text))
	_msg.text_submitted.connect(func(_t): _send(_msg.text))
	_build_suggestions()   # R6 PLAY-04 — verbs above the box, before the box is empty
	# They depend on the mode (a fight has its own controls), and _render_sheet
	# runs at boot BEFORE the mode settles on Exploration — so without this the
	# row builds once, decides it is hidden, and never reconsiders.
	Mode.changed.connect(func(_p, _n): _render_suggestions())
	# The Sheet button opens THE MENU (the Record and its tabs) — the sidebar
	# stays as the at-a-glance HUD, toggled with Ctrl+S.
	var sheet_btn: Button = $Margin/Split/ChatBox/Input/SheetBtn
	sheet_btn.toggle_mode = false
	sheet_btn.tooltip_text = "The Record — your character sheet and its pages"
	sheet_btn.pressed.connect(func(): _open_character_screen())
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
	$Margin/Split/ChatBox/Input/Lore.pressed.connect(_open_lore_book)
	$Margin/Split/ChatBox/Input/Shop.pressed.connect(_open_shop)
	$Margin/Split/ChatBox/Input/Bag.pressed.connect(_open_inventory)
	$Margin/Split/ChatBox/Input/Retell.pressed.connect(_regen)
	_roll_bar.pressed.connect(_roll_pending)
	_roll_bar.expand_icon = false
	_roll_bar.add_theme_constant_override("icon_max_width", 22)
	for st in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		_roll_bar.add_theme_color_override(st, Ui.c("gold"))
	_sheet_panel.meta_clicked.connect(_on_sheet_action)
	_combat_panel.meta_clicked.connect(_on_combat_action)
	_battle_grid.cell_clicked.connect(_on_grid_move)
	_battle_grid.token_clicked.connect(_on_grid_token)
	Combat.changed.connect(_render_combat)
	GameState.leveled_up.connect(_level_up_ceremony)
	_init_rail = HBoxContainer.new()
	_init_rail.name = "InitRail"
	_init_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_init_rail.add_theme_constant_override("separation", Ui.SPACE["s"])
	_init_rail.visible = false
	var chatbox: VBoxContainer = $Margin/Split/ChatBox
	chatbox.add_child(_init_rail)
	chatbox.move_child(_init_rail, _battle_grid.get_index())
	# The play screen already stands inside SceneArt + Backdrop + scrim; a
	# per-frame mote overlay on top of streaming text read as flicker, so the
	# adventure screen wears no atmosphere overlay (rooms/forges still do).
	_iconify_toolbar()
	_add_leave_button()
	_add_mic_button()
	# A3: a full-screen mood wash the AI can SUGGEST via presentation tags —
	# above the scene art, below the UI, transparent until a mood lands.
	_mood_layer = ColorRect.new()
	_mood_layer.color = Color(0, 0, 0, 0)
	_mood_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mood_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mood_layer)
	move_child(_mood_layer, $ArtScrim.get_index() + 1)
	Chronicle.reset()
	# The campaign name already carries the world — never show the raw world_id.
	$Margin/Split/ChatBox/Header.text = "✦ %s" % str(GameState.character.get("name", "?"))
	_seat_the_hero()
	Sfx.music(WorldSkin.music_for_id(GameState.world_id()))
	# The world's key art is the room you sit in from the first breath.
	#
	# R6 BLANK-01 — and this is root cause #1 of the whole audit in one line.
	# This looked the key art up in the ART CACHE under the bare world_id, but a
	# baked world writes its establishing shot into its PACKAGE as art/key.png.
	# The cache lookup therefore missed for every shipped world, `world_tex` came
	# back null, and the play screen — the screen the player spends the entire
	# game on — rendered ~60% empty void. Six worlds, ~1800 painted images, and
	# the reason none of them showed up here was the wrong lookup. Ask the
	# compiler first; keep the cache as the fallback for uncompiled worlds.
	var world_tex: Texture2D = Compiler.key_art(GameState.world_id())
	if world_tex == null:
		world_tex = Art.texture_for(str(GameState.character.get("world_id", "")))
	if world_tex != null:
		_scene_art.texture = world_tex
		# Empty-state: before any words exist the scene IS the screen — bright.
		# The first bubble eases it back behind the text (see _bubble).
		_scene_art.modulate.a = 0.6
		_ken_burns()
	# Companion chat (non-DM persona): a quiet table for two — no dice, no HUD.
	if not GameState.is_dm():
		Mode.enter("Dialogue")
		for btn in ["SheetBtn", "CodexBtn", "Dice", "Shop", "Bag", "ShortRest", "LongRest", "Scene"]:
			$Margin/Split/ChatBox/Input.get_node(btn).visible = false
		# EAS: the fireside room behind the talk, and the companion's painted
		# face at the table — a conversation, not a bare chat log.
		var comp_name := str(GameState.character.get("name", "?")).split(":")[0]
		Art.ensure_environment("env-fireside")
		var fire := Art.texture_for(Art.env_resolved("env-fireside"))
		if fire != null:
			_scene_art.texture = fire
			_scene_art.modulate.a = 0.5
			_ken_burns()
		var slug := "npc-" + comp_name.to_lower().replace(" ", "-")
		if not Art.has_art(slug):
			Art.ensure(slug, "character portrait of %s, %s, warm firelight, painted head-and-shoulders portrait, dark background, no text" % [comp_name, Art.subject_style("char")], "1024x1024", true)
		var face := MythPortrait.new(132, "gold", true)
		face.set_portrait(Art.round_tex(slug, 132), comp_name.left(1))
		face.anchor_left = 1.0
		face.anchor_right = 1.0
		face.offset_left = -164
		face.offset_top = 18
		face.offset_right = -32
		face.offset_bottom = 150
		add_child(face)
		Ui.breathe(face)
		Art.art_ready.connect(func(k):
			if str(k) == slug and is_instance_valid(face):
				face.set_portrait(Art.round_tex(slug, 132), comp_name.left(1)))
		# Clear-chat: sweep the table and start the talk fresh.
		var clear_b := Button.new()
		clear_b.theme_type_variation = "GhostButton"
		clear_b.text = "Clear the table"
		clear_b.anchor_left = 1.0
		clear_b.anchor_right = 1.0
		clear_b.offset_left = -196
		clear_b.offset_top = 158
		clear_b.offset_right = -32
		clear_b.offset_bottom = 192
		clear_b.pressed.connect(func():
			for r in _thread.get_children():
				r.queue_free()
			Chronicle.reset()
			_say_system("The table is cleared — speak fresh."))
		add_child(clear_b)
		_say_system("You sit down with %s." % comp_name)
		return
	MythLoading.mark(0.6, "Recalling the tale…")
	await GameState.hydrate()
	_seed_forged_party()  # companions chosen at the adventure table ride in on day one
	# The minimap: a corner whisper of the chart; click (or Ctrl+M) → Atlas.
	# Playtest #1: it was pinned at the top-left over the layout and covered the
	# adventure title ("Free Roam" read as "ree Roam"). It belongs where nothing
	# else lives — bottom-left, above the input row, anchored to the corner it
	# actually occupies.
	# R11-03 — and it is hidden outright in combat. It sits over the composer,
	# the dice tray and the action bar (End turn read as "nd turn"), and a chart
	# of the region answers nothing a player needs while a fight is on the table.
	var mini := preload("res://scenes/ui/mini_map.gd").new()
	mini.open_atlas.connect(func(): _open_character_screen("Atlas"))
	mini.anchor_top = 1.0
	mini.anchor_bottom = 1.0
	mini.offset_left = 14
	mini.offset_top = -196
	mini.offset_right = 204
	mini.offset_bottom = -72
	add_child(mini)
	_mini_map = mini
	_build_dice_menu()
	_render_sheet()
	_render_combat()  # a fight persisted mid-round resumes where it stood
	MythLoading.mark(0.9, "Setting the table…")
	# The Hall must be able to find this tale again — stamp the index the moment
	# it truly opens (playtest #1: Continue had no index to read).
	await GameState.load_index()
	GameState.remember_adventure()
	if str(GameState.sheet().get("name", "")) == "":
		Mode.enter("CharacterForge")
		_open_character_forge()  # a fresh adventure begins with a legend
	else:
		Mode.enter("Exploration")
		# R6 BUG-31/CUT-07 — this said "The tale of <name> continues…", which is
		# the header two lines above it, restated. Name the PLACE instead: it is
		# the one thing the player cannot already read on screen.
		var _here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
		_say_system(("You are at %s." % _here) if _here != "" else "The tale continues…", "compass")
		_recap()
	_msg.grab_focus()
	# MIL §7 — the screen is genuinely built now; only now does the curtain lift.
	await get_tree().process_frame
	MythLoading.lift()


## Forged companions picked at the adventure table (Party stage → world.rules
## .party) join the sheet ONCE — partySeeded marks the deed so dismissing one
## later doesn't resurrect them on the next boot.
func _seed_forged_party() -> void:
	var wk: Dictionary = GameState.state.get("world", {}) if GameState.state.get("world") is Dictionary else {}
	var party: Array = wk.get("rules", {}).get("party", []) if wk.get("rules") is Dictionary else []
	if party.is_empty() or bool(GameState.sheet().get("partySeeded", false)) \
			or str(GameState.sheet().get("name", "")) == "":
		return
	for p in party:
		if p is Dictionary and str(p.get("name", "")) != "":
			GameState.add_companion(str(p["name"]), str(p.get("role", "")))
	var s := GameState.sheet()
	s["partySeeded"] = true
	GameState.set_sheet(s)


## The action bar wears the hand-drawn Icon Library, never font glyphs or
## emoji (docs/DesignSystem.md, MDL law). Each button keeps its tooltip.
func _iconify_toolbar() -> void:
	var input := $Margin/Split/ChatBox/Input
	# R12-06 — SheetBtn was the one button this loop skipped, so it sat in a row
	# of drawn glyphs wearing the word "Sheet" while CodexBtn wore the SCROLL,
	# which is exactly what a character sheet looks like. The record gets the
	# scroll; the cast-and-quests panel gets the company's banner.
	for pair in [["Retell", "retell"], ["Bag", "pack"], ["SheetBtn", "scroll"],
			["CodexBtn", "banner"],
			["Dice", "die"], ["Scene", "easel"], ["Lore", "book"], ["Shop", "coins"],
			["ShortRest", "moon"], ["LongRest", "tent"]]:
		var btn: Button = input.get_node_or_null(str(pair[0]))
		if btn == null:
			continue
		btn.text = ""
		btn.custom_minimum_size = Vector2(42, 34)
		var ic := MythIcon.new(str(pair[1]), 24, "gold")
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(ic)


## Leave to the Hall — the tale is already saved (every mutation mirrors to
## the server), so this just returns to the main menu. Blocked mid-stream.
func _add_leave_button() -> void:
	var leave := Button.new()
	leave.flat = true
	leave.tooltip_text = "Leave to the Hall — your tale is saved"
	leave.anchor_left = 1.0
	leave.anchor_right = 1.0
	leave.offset_left = -52
	leave.offset_top = 12
	leave.offset_right = -14
	leave.offset_bottom = 46
	var ic := MythIcon.new("door", 26, "gold_soft")
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	leave.add_child(ic)
	leave.pressed.connect(_leave_to_hall)
	add_child(leave)


# ── STT push-to-talk: hold the quill, speak, release — words land in the box.
## Server side is multi-provider (/api/stt/transcribe) and may 503 without a
## configured provider; the client degrades to a polite line either way.
var _mic_player: AudioStreamPlayer
var _rec: AudioEffectRecord


func _add_mic_button() -> void:
	var mic := Button.new()
	mic.name = "Mic"
	mic.tooltip_text = "Hold to speak — release to transcribe"
	mic.custom_minimum_size = Vector2(42, 34)
	var ic := MythIcon.new("quill", 24, "gold_soft")
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	mic.add_child(ic)
	$Margin/Split/ChatBox/Input.add_child(mic)
	mic.button_down.connect(_mic_start)
	mic.button_up.connect(_mic_stop)


func _mic_start() -> void:
	if _rec == null:
		var idx := AudioServer.get_bus_index("MfRecord")
		if idx == -1:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, "MfRecord")
			AudioServer.add_bus_effect(idx, AudioEffectRecord.new())
			AudioServer.set_bus_mute(idx, true)  # never monitor the mic back out
		_rec = AudioServer.get_bus_effect(idx, 0)
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = "MfRecord"
		add_child(_mic_player)
	_mic_player.play()
	_rec.set_recording_active(true)


func _mic_stop() -> void:
	if _rec == null or not _rec.is_recording_active():
		return
	_rec.set_recording_active(false)
	_mic_player.stop()
	var wav: AudioStreamWAV = _rec.get_recording()
	if wav == null:
		return
	wav.save_to_wav("user://stt.wav")
	var r: Dictionary = await Api.post_file("/api/stt/transcribe", "file", FileAccess.get_file_as_bytes("user://stt.wav"))
	var text := str(r.get("text", "")).strip_edges()
	if int(r.get("_status", 0)) == 200 and text != "":
		_msg.text = text
		_msg.grab_focus()
		_msg.caret_column = _msg.text.length()
	elif int(r.get("_status", 0)) == 503:
		_say_system("No speech provider is configured on the server — typing it is.", "quill")
	else:
		_say_system("The words didn't carry — try again.", "quill")


func _leave_to_hall() -> void:
	# Round-5 blocker: this refused mid-stream and said so at the BOTTOM of a
	# transcript the player wasn't looking at, so the door read as dead — and a
	# turn runs ~45s, so the refusing window is most of the session. The tale is
	# saved continuously; there is nothing to protect by holding them here.
	if _streaming:
		Api.cancel_stream()
		_streaming = false
		Art.hold = false
		_dismiss_thinking()
	GameState.remember_adventure()   # the Hall remembers where you stopped
	Mode.enter("MainMenu")
	Ui.transition("res://scenes/main_menu.tscn", get_tree())


## "Previously, in <adventure>…" — the campaign memory recalls the thread.
## Composed, not dumped: markdown stripped, each beat cut at a sentence or
## word boundary — never a mid-word transcript truncation.
func _recap() -> void:
	var beats: Array = await Chronicle.recall("the most important recent events of our story")
	if beats.is_empty():
		return
	var lines: Array[String] = []
	for b in beats.slice(0, 3):
		var t := _recap_line(str(b.get("text", "")))
		if t != "":
			lines.append("◆ " + t)
	if not lines.is_empty():
		var rt := _bubble("gm")
		var title := str(GameState.character.get("name", "")).split(":")[0]
		# The recap wears the world's face — a small rounded key-art seal.
		var seal := Art.round_tex(GameState.world_id(), 56)
		if seal != null:
			rt.add_image(seal)
			rt.append_text("  ")
		rt.append_text("[color=%s][b]Previously, in %s…[/b][/color]\n%s" % [
			Ui.c("gold_soft").to_html(false), _bb(title if title != "" else "the tale"), _bb("\n".join(lines))])


func _recap_line(raw: String) -> String:
	var t := raw.replace("*", "").replace("#", "").replace("\n", " ").strip_edges()
	if t.length() <= 170:
		return t
	t = t.left(170)
	var cut := maxi(t.rfind(". "), maxi(t.rfind("! "), t.rfind("? ")))
	if cut > 60:
		return t.left(cut + 1)  # end on the sentence
	var sp := t.rfind(" ")
	return (t.left(sp) if sp > 0 else t) + "…"


# ── The Character Forge (docs/forges/CharacterForge.md) ─────────────────────
## The pillar replaces the old hero-forge dialog: a full-screen ritual.
## A legend banked at the main menu resumes at the Quenching.
func _open_character_forge() -> void:
	var forge := preload("res://scenes/forge/character_forge.tscn").instantiate()
	# A banked legend chosen at the Adventure Forge fills the Quenching.
	if not GameState.pending_hero.is_empty():
		forge.draft = GameState.pending_hero.duplicate(true)
		forge.start_at_quench = true
	forge.hero_forged.connect(func(d):
		forge.queue_free()
		GameState.bank_hero(d)       # the legend stays in the roster, playable again
		GameState.pending_hero = {}
		_create_hero_forged(d))
	forge.closed.connect(func():
		forge.queue_free()
		Ui.transition("res://scenes/main_menu.tscn", get_tree()))
	add_child(forge)


## Commit the forged legend through the same engine math as ever, honoring
## the forge's extras: hand-assigned array, chosen kit, appearance, style.
func _create_hero_forged(d: Dictionary) -> void:
	var rolled: Array[int] = []
	for v in d.get("rolled", []):
		rolled.append(int(v))
	_create_hero(str(d.get("name", "The Nameless")), str(d.get("race", "Human")),
		str(d.get("cls", "Fighter")), rolled, str(d.get("bg", "")), d)


func _create_hero(nm: String, race: String, cls: String, rolled: Array[int], background := "", extra := {}) -> void:
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
	if extra.get("assign") is Dictionary and not extra["assign"].is_empty():
		for a2 in Rules.ABILITIES:
			abilities[a2] = int(extra["assign"].get(a2, 10))
	else:
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
	# Preset + heritage + background can grant the same skill — dedup or the
	# sheet reads "insight, religion, insight, religion".
	var skills: Array = []
	for sk in preset.get("skills", []) + heritage.get("skills", []) + bgd.get("skills", []):
		if not skills.has(sk):
			skills.append(sk)
	s["profSkills"] = skills
	var traits: Array = heritage.get("traits", [])
	s["features"] = traits.duplicate()
	# The player's own class/background story — the GM reinterprets it inside
	# whatever world this hero was dropped into (adventure_forge / world card).
	var story := {}
	if str(extra.get("cls_story", "")) != "":
		story["class"] = str(extra["cls_story"])
	if str(extra.get("bg_story", "")) != "":
		story["background"] = str(extra["bg_story"])
	if not story.is_empty():
		s["story"] = story
	if bool(preset.get("caster", false)):
		s["slots"] = Rules.full_caster_slots(1)
		var seed: Array = Rules.tables.get("class_spells", {}).get(cls, [])
		s["spells"] = []
		for sp in seed:
			if sp is Array and sp.size() >= 2 and int(sp[1]) <= 1:
				s["spells"].append({"name": str(sp[0]), "level": int(sp[1])})
	GameState.set_sheet(s)
	# Starting gear. In a compiled world the hero is armed from the world's own
	# catalogue (material-true, world-flavoured) for their class archetype; a
	# world without a compiled kit falls back to the forge's generic loadout.
	var world_kit: Array = Compiler.kit_for(GameState.world_id(), Compiler.archetype_for_class(cls))
	if not world_kit.is_empty():
		for rec in world_kit:
			GameState.add_catalogue_item(rec, 1)
	else:
		for it_nm in extra.get("kit", []):
			GameState.add_item(str(it_nm), "common", 1)
	var inv2 := GameState.inv()
	var eq2: Dictionary = inv2.get("equipped", {})
	for it in inv2.get("items", []):
		var t2 := str(it.get("type", ""))
		if t2 in ["weapon", "armor", "shield"] and not eq2.has(t2):
			eq2[t2] = str(it.get("id", ""))
	if not eq2.is_empty():
		inv2["equipped"] = eq2
		GameState.save_kind("inv", inv2)
	# The face the player approved at the forge becomes the hero's face (copied,
	# not re-rolled). Only when none was struck do we commission a fresh one.
	var pkey := str(extra.get("portrait_key", ""))
	if pkey != "" and Art.has_art(pkey):
		Art.copy(pkey, "hero-" + GameState.cid().validate_filename())
	else:
		var looks := str(extra.get("appearance", ""))
		var brush := str(extra.get("style", ""))
		Art.ensure_hero_portrait(GameState.cid(), s,
			(looks + (", " if looks != "" and brush != "" else "") + brush).strip_edges())
	_build_dice_menu()
	_render_sheet()
	# The HP and purse used to be repeated here. The chips bar states both, one
	# row above and permanently — so the opening read as two bars saying the same
	# thing. An arrival line should say who arrived; the numbers have their own
	# home. (Its earlier fix was to make the CURRENCY match the chip; the real
	# problem was saying it twice at all.)
	_say_system("%s the %s %s steps into the tale." % [nm, race, cls], "anvil")
	# The Campaign Forge already chose the GM's voice? Skip Session Zero and
	# open the tale directly with the forged tone in force.
	if GameState.state.get("gm") is Dictionary and not GameState.state.get("gm", {}).is_empty():
		Mode.enter("Exploration")
		_say_system("The GM speaks in the voice chosen at the forge: %s." % str(GameState.state["gm"].get("style", "as tuned")), "crown")
		_last_player_msg = "I arrive."
		_stream(Composer.envelope("[Session zero: I am %s, a level 1 %s %s%s. Open the adventure — set the very first scene, introduce where I am and why today is different, and end on a choice.]" % [nm, race, cls, (", " + str(Rules.tables.get("backgrounds", {}).get(background, {}).get("line", ""))) if background != "" else ""]))
		return
	_session_zero(nm, race, cls, background)


## Session Zero — Step 3 of 3: set the table's tone before the first scene.

func _session_zero(nm: String, race: String, cls: String, background := "") -> void:
	var tuner := preload("res://scenes/ui/gm_tuner.gd").new()
	tuner.session_zero = true
	tuner.tuned.connect(func(_knobs: Dictionary):
		Mode.enter("Exploration")
		_last_player_msg = "I arrive."
		_stream(Composer.envelope("[Session zero: I am %s, a level 1 %s %s%s. Open the adventure — set the very first scene, introduce where I am and why today is different, and end on a choice.]" % [nm, race, cls, (", " + str(Rules.tables.get("backgrounds", {}).get(background, {}).get("line", ""))) if background != "" else ""])))
	add_child(tuner)
	tuner.popup_centered()


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
	row.set_meta("kind", kind)  # Ctrl+E finds "your last bubble" by this
	row.modulate.a = 0.0
	_thread.add_child(row)
	create_tween().tween_property(row, "modulate:a", 1.0, 0.35)
	if _scene_art.modulate.a > 0.4:  # the bright empty-state scene steps back once words arrive
		create_tween().tween_property(_scene_art, "modulate:a", 0.35, 1.2)
	_scroll_bottom()
	return rt


func _say_me(bb: String) -> void:
	_bubble("me").append_text(bb)

func _say_system(text: String, glyph := "") -> void:
	var l := Label.new()
	l.theme_type_variation = "HintLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if glyph == "":
		# R7-02 — GM and player lines sit on bubble panels, but system lines were
		# bare labels. That was invisible while the play screen was an empty void;
		# restoring the world's key art put small grey text straight onto a bright
		# painting. A quiet plate keeps them legible without pretending to be a
		# bubble. (Regression introduced by the R6 art fix — my own.)
		_thread.add_child(_sys_plate(l))
	else:
		# a hand-drawn glyph leads the line — never an emoji
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 7)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(MythIcon.new(MythIcon.resolve(glyph), 18, "gold_soft"))
		row.add_child(l)
		_thread.add_child(_sys_plate(row))
	_scroll_bottom()


## R6 FUN-20 — the hero the player invented was never on screen while they
## played them. The forge spends ten stages on a face, a voice and a history,
## the portrait is commissioned and cached, and then the whole adventure showed
## the campaign's NAME and nothing else; the only way to see your own character
## was to open a modal. Seat them at the top of the tale, beside the title, and
## repaint when the portrait lands (a freshly forged hero has none for ~25 s).
func _seat_the_hero() -> void:
	if not GameState.is_dm():
		return   # a companion chat has its own face already
	var header: Label = $Margin/Split/ChatBox/Header
	var box: VBoxContainer = $Margin/Split/ChatBox
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	box.add_child(row)
	box.move_child(row, header.get_index())
	# R8-24 — the ring rendered empty while the SAME face rendered fine on the
	# Record, because this rebuilt `hero-<cid>` instead of asking for the key the
	# hero carries. Art.hero_key() is the one answer.
	var key := Art.hero_key()
	var face := MythPortrait.new(38, "gold", false)
	face.set_portrait(Art.round_tex(key, 38), str(GameState.sheet().get("name", "?")).left(1).to_upper())
	face.tooltip_text = "%s — open the Record" % str(GameState.sheet().get("name", "your hero"))
	row.add_child(face)
	header.reparent(row)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# R12-08 — this passed "" as the fallback glyph, on the assumption that art
	# being READY means art being THERE. When round_tex comes back null anyway —
	# the painting failed, or the LRU evicted it between the signal and the read —
	# the ring got no texture and no letter, and drew as an empty circle. Keep the
	# initial: it is what MythPortrait falls back to, and it is never wrong.
	var initial := str(GameState.sheet().get("name", "?")).left(1).to_upper()
	Art.art_ready.connect(func(k):
		if str(k) == key and is_instance_valid(face):
			face.set_portrait(Art.round_tex(key, 38), initial)
			Ui.pulse(face))


## ── Suggested actions (R6 PLAY-04 / STR-02 / STR-03, all Critical) ──────────
## The entire interaction model was one empty box captioned "What do you do?".
## An experienced player fills it happily; a new one stares at it, and nothing on
## screen tells them this is a game where "look behind the bar" is a legal move.
## These are the smallest honest fix: a handful of verbs drawn from what is
## ACTUALLY true right now — the place, its shop, a live quest, whoever travels
## with you — that TYPE THEMSELVES INTO THE BOX rather than firing. The player
## still writes the sentence and can edit it, so the freedom is intact and the
## blank page is gone. They are suggestions, never a menu of the only options.
func _build_suggestions() -> void:
	_suggest = HFlowContainer.new()
	_suggest.alignment = FlowContainer.ALIGNMENT_CENTER
	_suggest.add_theme_constant_override("h_separation", Ui.SPACE["xs"])
	_suggest.add_theme_constant_override("v_separation", Ui.SPACE["xs"])
	# Same lesson as the system lines: ghost buttons over a bright painting are
	# barely there. Give the row its own quiet plate so the verbs read.
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Ui.c("night"), 0.55)
	sb.set_corner_radius_all(Ui.RADIUS["s"])
	sb.content_margin_left = Ui.SPACE["s"]
	sb.content_margin_right = Ui.SPACE["s"]
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	plate.add_theme_stylebox_override("panel", sb)
	plate.add_child(_suggest)
	_suggest_plate = plate
	var box: VBoxContainer = $Margin/Split/ChatBox
	box.add_child(plate)
	box.move_child(plate, $Margin/Split/ChatBox/Input.get_index())


func _render_suggestions() -> void:
	if _suggest == null or not is_instance_valid(_suggest):
		return
	for c in _suggest.get_children():
		c.queue_free()
	# Only in ordinary play: a fight has its own controls, and dialogue its own.
	if _suggest_plate != null and is_instance_valid(_suggest_plate):
		_suggest_plate.visible = Mode.state == "Exploration"
	if Mode.state != "Exploration":
		return
	var world: Dictionary = GameState.state.get("world", {}) if GameState.state.get("world") is Dictionary else {}
	var here := str(world.get("here", ""))
	var acts: Array = []
	acts.append(["Look around", "I look around, taking in the details."])
	if here != "":
		acts.append(["Search this place", "I search %s carefully for anything of interest." % here])
		for l in Rules.world_locations(GameState.world_id()):
			if l is Dictionary and str(l.get("name", "")) == here and str(l.get("shop", "")) != "":
				acts.append(["Browse the wares", "I ask to see what the keeper has for sale."])
				break
	for q in (GameState.state.get("quests", []) if GameState.state.get("quests") is Array else []):
		if q is Dictionary and str(q.get("status", "active")) != "done" and str(q.get("title", "")) != "":
			acts.append(["Ask about the task", "I ask around about %s." % str(q["title"])])
			break
	for cmp in GameState.sheet().get("companions", []):
		if cmp is Dictionary and str(cmp.get("name", "")) != "":
			acts.append(["Talk to %s" % str(cmp["name"]).split(" ")[0], "I turn to %s and speak with them." % str(cmp["name"])])
			break
	acts.append(["Press on", "I press on, and see where the road leads."])
	for a in acts.slice(0, 5):
		var b := Button.new()
		b.theme_type_variation = "GhostButton"
		b.text = str(a[0])
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Puts this in the box — edit it before you send."
		b.pressed.connect(func():
			_msg.text = str(a[1])
			_msg.grab_focus()
			_msg.caret_column = _msg.text.length())
		_suggest.add_child(b)


## An ordinary drop, but the piece is SHOWN. R6 FUN-04/FUN-05: the bake put
## 1 150+ painted items in each world and a common find announced itself as a
## line of grey text — the art existed and the player never saw it at the one
## moment they cared. The icon is already in hand; put it on screen.
func _say_loot(nm: String, icon: Texture2D, rarity: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.custom_minimum_size = Vector2(34, 34)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tr)
	var l := Label.new()
	l.theme_type_variation = "HintLabel"
	l.text = "%s added to your pack" % nm
	l.add_theme_color_override("font_color", Ui.rarity_color(rarity))
	row.add_child(l)
	_thread.add_child(_sys_plate(row))
	Ui.pulse(row)
	_scroll_bottom()


## A quiet backing plate for a system line, so it stays readable over the world's
## painting without dressing up as a speech bubble. R7-02.
func _sys_plate(inner: Control) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Ui.c("night"), 0.55)
	sb.set_corner_radius_all(Ui.RADIUS["s"])
	sb.content_margin_left = Ui.SPACE["m"]
	sb.content_margin_right = Ui.SPACE["m"]
	sb.content_margin_top = Ui.SPACE["xs"]
	sb.content_margin_bottom = Ui.SPACE["xs"]
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_child(inner)
	return pc


func _scroll_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# ── Sending / streaming ──────────────────────────────────────────────────────
func _send(raw: String) -> void:
	if not Mode.can("send_message"):
		# R8-09 — this used to return in silence. The typed words stayed in the
		# box, nothing moved, and the player believed they had acted; I lost a
		# whole action to it mid-playtest. Refusing is fine — refusing quietly
		# is not. Keep the text, say why, and don't pretend.
		if raw.strip_edges() != "":
			Ui.shake(_msg)
			Sfx.ui("deny")
			_say_system("The table is still speaking — your words are held, not lost.")
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	_msg.text = ""
	_set_check({})
	_say_me(_bb(msg))
	_last_player_msg = msg
	_lang_retry = 0  # fresh turn: the language guard's one retry is available again
	if not GameState.is_dm():
		_stream(msg)  # companions get your words, not a rules envelope
		return
	# R8-07 — a fight the PLAYER starts is still a fight. Combat used to open only
	# when the GM's own prose happened to match an attack verb, so declaring an
	# attack got you narration and one loose d20 while the board never appeared.
	# Open it here, before the GM answers, so it narrates into a live round.
	# R9-03 — but only against someone who is ACTUALLY THERE. Opening on the
	# declaration alone staged whatever the player named: "I attack the ice
	# jotun" with no jotun in the scene produced a 16/16 Ice Jotun on the tracker
	# while the GM answered "there is no sign of them nearby". A fight against
	# nothing, and my own regression from the R8-07 fix.
	#
	# The scene the player is looking at is the last thing the GM said, so that is
	# what the target must appear in. Deliberately NOT a wider regex — the trigger
	# was never too narrow, it was too credulous.
	if not Combat.active():
		var declared := Tags.detect_player_attack(msg)
		if declared != "" and _foe_is_present(declared):
			_start_combat(declared)
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
	Art.hold = true    # the GPU belongs to the narrator until the reply lands
	Mode.busy = true
	_acc = ""
	_shown = 0
	_lang_gate = true       # hold the opening until its language is judged
	_lang_drifted = false
	_gm_started = false
	_send_btn.disabled = true
	_gm_rt = _bubble("gm")
	# MIL §7 Tier 3 — the wait belongs to the fiction. A drawn quill and the
	# world's own voice, not three glyphs. Lifted when the first token lands.
	_thinking = MythThinking.new()
	_gm_rt.get_parent().add_child(_thinking)
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	Api.stream_chat(framed)


func _on_delta(t: String) -> void:
	_acc += t
	if _lang_drifted:
		return  # a drifted opening is held, hidden; the retry fires on done
	if _lang_gate:
		if str(Tags.parse(_acc)["clean"]).strip_edges().length() >= _GATE_MIN:
			_open_language_gate()
		return  # nothing shows until the gate opens (imperceptible on clean turns)
	_flush_stream()


## Judge the buffered opening: if it drifted to another language, hold it
## hidden for a silent retry; otherwise release it to the screen.
func _open_language_gate() -> void:
	_lang_gate = false
	var visible := str(Tags.parse(_acc)["clean"]).strip_edges()
	if _lang_retry < 1 and Composer.looks_like_drift(visible, GameState.language()):
		_lang_drifted = true
		_log_drift(visible)
		return
	_flush_stream()


## Print new narration, skipping over [[tags]] as they complete so a mid-reply
## tag never freezes the display. Incomplete tags at the tail are held back.
func _flush_stream() -> void:
	if _gm_rt == null:
		return
	if not _gm_started:
		_gm_rt.clear()
		_gm_started = true
		# MIL §7 — the waiting state CROSSFADES into the words; it never pops.
		_dismiss_thinking()
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
	_lang_retry = 0
	_stream(_last_framed)


## Inline edit (Ctrl+E): your last line comes back into the box to be reworded;
## the stale exchange — your bubble and the GM's reply — leaves the thread.
func _edit_last() -> void:
	if not Mode.can("send_message") or _last_player_msg == "" or _streaming:
		return
	if _gm_rt != null:
		var row := _gm_rt.get_parent().get_parent()
		if row != null and row.get_parent() == _thread:
			row.queue_free()
		_gm_rt = null
	for i in range(_thread.get_child_count() - 1, -1, -1):
		var r := _thread.get_child(i)
		if str(r.get_meta("kind", "")) == "me":
			r.queue_free()
			break
	_msg.text = _last_player_msg
	_msg.grab_focus()
	_msg.caret_column = _msg.text.length()
	_say_system("Reword it and send — the table forgets the old line.", "quill")


## MIL §6 — a dead end is never acceptable. When the storyteller truly can't
## answer, the player gets a way forward in the world's own voice.
func _offer_retry() -> void:
	var again := Button.new()
	again.theme_type_variation = "AccentButton"
	again.text = "Ask the storyteller again"
	again.pressed.connect(func():
		again.queue_free()
		if _last_framed != "":
			_stream(_last_framed))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(again)
	_thread.add_child(row)
	Ui.reveal(row)
	_scroll_bottom()


## Fade the waiting state out, whatever ended it (words, failure, or leaving).
func _dismiss_thinking() -> void:
	if _thinking == null or not is_instance_valid(_thinking):
		_thinking = null
		return
	var t := _thinking
	_thinking = null
	t.set_process(false)
	if Ui.reduce_motion:
		t.queue_free()
		return
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0, Ui.TIME["fast"])
	tw.tween_callback(t.queue_free)


## Silent log of a language-drift incident (Issue 4) — never shown to the player.
func _log_drift(snippet: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	var f := FileAccess.open("user://logs/lang_drift.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://logs/lang_drift.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("[%s] cid=%s :: %s" % [Time.get_datetime_string_from_system(), GameState.cid(), snippet.left(140)])
	f.close()


## The narrator's own error channel. `sse_event` used to also carry
## `type: tool_output` with an image_url — the SERVER's agent loop calling its
## image tool mid-answer. This game never used that: art is requested by the
## CLIENT from the GM's `[[scene]]` / `[[portrait]]` tags via Art.ensure(), and
## the GM system prompt does not mention tools at all. It came from the Odysseus
## assistant and went with the agent loop.
func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		if _gm_rt != null:
			_gm_rt.append_text("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false), _bb(str(d.get("error", "stream error")))])


## The one failure that used to hide behind the server fallback. Name the missing
## thing and where it goes, in the transcript where the player is already looking
## — not a push_error only a developer reads.
func _on_narrator_missing(reason: String) -> void:
	if _gm_rt == null:
		return
	_gm_rt.append_text("\n[color=%s]The storyteller has no voice yet — %s.[/color]\n" % [
		Ui.c("danger").to_html(false), _bb(reason)])
	_gm_rt.append_text("[color=%s]Drop a .gguf model into %s and restart.[/color]\n" % [
		Ui.c("ink_soft").to_html(false),
		_bb(ProjectSettings.globalize_path(LocalGM.MODEL_DIR))])


func _on_done(_ok: bool) -> void:
	# R6 STR-28 — the stream carries whether it ever CONNECTED, and this dropped
	# it on the floor. A backend that is down produced the same message as a
	# model that answered with nothing: "the storyteller loses the thread — the
	# local mind may be busy." That is a wrong diagnosis pointed at the wrong
	# component, and for a friend running the installer it is the difference
	# between "wait a moment" and "your engine is not running". Retrying a dead
	# socket also just burns the empty-retry budget for nothing.
	if not _ok and _acc.strip_edges() == "":
		_streaming = false
		Art.hold = false
		Mode.busy = false
		_send_btn.disabled = false
		_dismiss_thinking()
		if _gm_rt != null:
			_gm_rt.clear()
			_gm_rt.append_text("[color=%s][i]The table is empty — Mythforge cannot reach its engine.[/i][/color]\n%s" % [
				Ui.c("danger").to_html(false),
				"[color=%s]Check that the Mythforge launcher is running, then strike again.[/color]" % Ui.c("ink_dim").to_html(false)])
		_offer_retry()
		return
	# Language guard first: a short reply may never have hit the gate threshold.
	if _lang_gate:
		_open_language_gate()
	if _lang_drifted:
		_lang_drifted = false
		_lang_retry += 1
		# Drop the silent (drifted) bubble and strike again, harder-anchored.
		var row := _gm_rt.get_parent().get_parent() if _gm_rt != null else null
		if row != null and row.get_parent() == _thread:
			row.queue_free()
		_gm_rt = null
		var orig := _last_framed
		_stream("[SYSTEM: your previous reply was in the wrong language. Respond ONLY in %s, from the first word.]\n%s" % [GameState.language(), orig])
		_last_framed = orig  # a later Retell uses the clean framing, not the anchor
		return
	# An EMPTY reply used to end here in a dead bubble — the opening scene of an
	# adventure could simply fail (playtest #14). Only language drift had a
	# retry. Now silence gets one quiet second attempt, and if it fails again
	# the player is handed a way forward instead of a full stop.
	if _acc.strip_edges() == "" and _empty_retry < 1:
		_empty_retry += 1
		var row0 := _gm_rt.get_parent().get_parent() if _gm_rt != null else null
		if row0 != null and row0.get_parent() == _thread:
			row0.queue_free()
		_gm_rt = null
		_stream(_last_framed)
		return
	_empty_retry = 0
	_streaming = false
	Art.hold = false   # the brush may have the card back
	Mode.busy = false
	_send_btn.disabled = false
	_dismiss_thinking()   # a silent/failed turn must never strand the wait
	var tail: Dictionary = Tags.parse(_acc.substr(_shown))
	if _gm_rt != null:
		if str(tail["clean"]) != "":
			_gm_rt.append_text(_bb(tail["clean"]))
		if _acc.strip_edges() == "":
			_gm_rt.clear()
			_gm_rt.append_text("[color=%s][i]The storyteller loses the thread — the local mind may be busy.[/i][/color]"
				% Ui.c("ink_dim").to_html(false))
			_offer_retry()
	if not GameState.is_dm():
		_scroll_bottom()  # pure conversation: no tags, no rolls, no chronicling
		return
	var parsed: Dictionary = Tags.parse(_acc)
	_apply_world_tags(parsed["tags"])          # state — the deterministic domain
	_apply_presentation_tags(parsed["tags"])   # presentation only — never state
	_last_scene = str(parsed["clean"])
	Chronicle.record(_last_player_msg, str(parsed["clean"]))
	# NOTE: "\b" in a GDScript literal is a backspace char, not a regex word
	# boundary — the pattern must be "\\bTHE END\\b" or completion never fires.
	if RegEx.create_from_string("\\bTHE END\\b").search(str(parsed["clean"])) and not GameState.clock().get("done", false):
		Sfx.play("chime")
		Sfx.play("sting")
		var fin_rt := _bubble("gm")
		fin_rt.append_text("%s [color=%s][b]THE TALE IS COMPLETE[/b][/color]
[i]This campaign has reached its end — the world remembers. Free roam continues if you keep talking, or return to the menu for a new tale.[/i]" % [Ui.ico("banner", 20), Ui.c("gold_soft").to_html(false)])
		var clk := GameState.clock()
		clk["done"] = true  # flags the Chronicles cover with a "complete" badge
		GameState.save_kind("clock", clk)
		_save_snapshot()  # auto-chronicle the finale so the ending is always kept
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(str(parsed["clean"]))
	_set_check(check)
	_decorate_speaker(_gm_rt, str(parsed["clean"]))
	_scroll_bottom()


## BG3 intimacy (docs/rituals/Dialogue.md): when a codex-known face speaks
## inside the GM's beat — their name near quoted speech — seat their painted
## portrait beside the words. Heuristic, engine-side; first match wins.
func _decorate_speaker(rt: RichTextLabel, clean: String) -> void:
	if rt == null or not (GameState.state.get("codex") is Array):
		return
	var panel := rt.get_parent()
	var row := panel.get_parent() if panel != null else null
	if not (row is HBoxContainer) or row.get_child_count() != 2:
		return
	for n in GameState.state.get("codex", []):
		if not (n is Dictionary):
			continue
		var nm := str(n.get("name", "")).strip_edges()
		if nm.length() < 3:
			continue
		var idx := clean.find(nm)
		if idx < 0:
			continue
		var window := clean.substr(maxi(0, idx - 80), nm.length() + 160)
		if not (window.contains("\"") or window.contains("“") or window.contains("”")):
			continue
		var chip := MythPortrait.new(38, "amethyst")
		chip.set_portrait(Art.round_tex("npc-" + nm.to_lower().replace(" ", "-")), nm.left(1).to_upper())
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		chip.tooltip_text = "%s — %s" % [nm, str(n.get("role", ""))] if str(n.get("role", "")) != "" else nm
		row.add_child(chip)
		row.move_child(chip, 0)
		return


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
					_say_system("%s %+d — purse now %d" % [GameState.currency(), delta, total], "coins")
			"loot":
				var nm := str(a.get("name", "")).strip_edges()
				var rarity := str(a.get("rarity", "common"))
				var qty := maxi(1, int(a.get("qty", 1)))
				# World-true loot: a generic drop (empty name, an explicit roll, or
				# a placeholder like "treasure") pulls a real item from the compiled
				# catalogue, so it arrives already painted, named and stat-blocked.
				var rolled := {}
				if nm == "" or str(a.get("roll", "")) != "" or nm.to_lower() in ["treasure", "loot", "salvage", "an item", "some loot"]:
					rolled = Compiler.roll_item(GameState.world_id())
				if not rolled.is_empty():
					nm = str(rolled.get("name", nm))
					rarity = str(rolled.get("rarity", rarity))
					GameState.add_catalogue_item(rolled, qty)
				elif nm != "":
					GameState.add_item(nm, rarity, qty)
					Art.ensure_item_icon(nm)
				if nm != "":
					var icon: Texture2D = Art.item_tex_for(rolled) if not rolled.is_empty() else Art.item_tex(nm)
					# MIL §9/§13 — ceremony scales with rarity: a common dagger
					# shimmers, a legendary stops the world.
					if rarity in ["epic", "legendary"]:
						MythCeremony.play(self, {
							"title": nm, "line": "A %s find." % rarity,
							"art": icon, "sound": "loot",
							"weight": "major", "tint": Ui.RARITY.get(rarity, "gold"),
						})
					elif rarity == "rare":
						# R6 FUN-06 — ceremony stopped at epic, so a *rare* drop read
						# exactly like a rusty dagger. Lighter beat, still a moment.
						MythCeremony.play(self, {
							"title": nm, "line": "A rare find.", "art": icon,
							"sound": "loot", "weight": "light",
							"tint": Ui.RARITY.get(rarity, "gold"),
						})
					else:
						Sfx.ui("loot")
						_say_loot(nm, icon, rarity)
			"spell-learned":
				var sp := str(a.get("name", "")).strip_edges()
				if sp != "" and GameState.learn_spell(sp):
					_say_system("You learn %s" % sp, "book")
			"lore":
				var lt := str(a.get("title", "")).strip_edges()
				if lt != "" and GameState.add_lore(str(a.get("cat", a.get("category", "Discoveries"))).strip_edges(), lt, str(a.get("note", a.get("body", ""))).strip_edges()):
					_say_system("The Lore Book records a new entry: %s." % lt)
			"npc":
				GameState.record_npc(a)  # a structured Character Resource (A4)
			"relate":
				GameState.relate(str(a.get("name", "")), int(str(a.get("bond", a.get("delta", "0"))).replace("+", "")), str(a.get("note", "")))
			"time":
				GameState.advance_time(maxi(1, int(a.get("advance", 1))))
				var c: Dictionary = GameState.clock()
				_say_system("%s, day %d" % [GameState.TIMES[int(c["ti"])], int(c["day"])], "hourglass")
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
				if place != "":
					_track_here(place)  # prose moves the pin on the chart
					if not _conjuring:
						_repaint_scene(place)
			"companion":
				var cn := str(a.get("name", "")).strip_edges()
				if not bool(GameState.rule("companions", true)):
					_say_system("The table rules bar companions — %s walks their own road." % (cn if cn != "" else "the stranger"), "shield")
				elif cn != "":
					var note := GameState.add_companion(cn, str(a.get("role", "")))
					if note != "":
						Sfx.play("chime")
						_say_system(note.replace("*", ""))
	if not Combat.active():
		var foe := Tags.detect_combat_start(Tags.parse(_acc)["clean"])
		if foe != "":
			_start_combat(foe)
	_render_sheet()


## A3 — presentation tags: the AI SUGGESTS how the moment looks and sounds.
## HARD RULE: this routes ONLY to presentation systems (the mood wash, Sfx).
## It must never touch GameState / Combat / Rules — state stays the sole domain
## of _apply_world_tags, so the determinism guarantee is preserved.
const _MOODS := {
	"calm": Color(0.03, 0.06, 0.12, 0.10), "warm": Color(0.26, 0.12, 0.03, 0.15),
	"tense": Color(0.10, 0.05, 0.15, 0.22), "eerie": Color(0.04, 0.15, 0.09, 0.20),
	"somber": Color(0.05, 0.06, 0.10, 0.28), "dread": Color(0.12, 0.02, 0.05, 0.30),
	"triumphant": Color(0.30, 0.22, 0.05, 0.14), "neutral": Color(0, 0, 0, 0),
}


func _apply_presentation_tags(tags: Array) -> void:
	for t in tags:
		var a: Dictionary = t["attrs"]
		match str(t["name"]):
			"mood":
				_mood_tint(str(a.get("tone", a.get("value", ""))))
			"music":
				if not Combat.active():  # combat owns its own score
					var track := _music_for_cue(str(a.get("cue", a.get("track", ""))))
					if track != "":
						Sfx.music(track)
			"sfx", "sound":
				var s := _sfx_for_cue(str(a.get("cue", a.get("name", ""))))
				if s != "":
					Sfx.play(s)
			# "portrait" / "camera": parsed and reserved — consumers land in a later slice.


func _mood_tint(tone: String) -> void:
	if _mood_layer == null:
		return
	var c: Color = _MOODS.get(tone.to_lower(), Color(0, 0, 0, 0))
	if Ui.reduce_motion:
		_mood_layer.color = c
	else:
		create_tween().tween_property(_mood_layer, "color", c, 1.5)


func _music_for_cue(cue: String) -> String:
	var c := cue.to_lower()
	if c in ["battle", "combat", "fight", "danger"]:
		return "combat"
	if c in ["tense", "eerie", "dread", "fear", "ominous", "suspense", "sorrow", "somber", "grief"]:
		return "arcane"
	# calm / warm / triumph / unknown → the world's own score (never guess silence)
	return WorldSkin.music_for_id(GameState.world_id())


func _sfx_for_cue(cue: String) -> String:
	var c := cue.to_lower()
	if c in ["impact", "hit", "blow", "strike", "clash"]:
		return "hit"
	if c in ["chime", "reveal", "magic", "shimmer", "discovery"]:
		return "chime"
	if c in ["tension", "sting", "alarm", "danger", "dread"]:
		return "sting"
	return ""  # unknown cue → nothing, rather than a wrong sound


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


# ── The level-up ceremony — extracted to scenes/ui/levelup_window.gd (A0 #4).
## The play screen keeps the mode bracket and the aftermath: dice menu rebuild,
## re-render, the announcement, and the skill-tree reward beat.
func _level_up_ceremony(from_level: int, to_level: int) -> void:
	var prev_mode: StringName = Mode.state
	Mode.enter("LevelUp")
	var win := preload("res://scenes/ui/levelup_window.gd").new()
	win.from_level = from_level
	win.to_level = to_level
	win.sheet_changed.connect(_render_sheet)
	win.ceremony_done.connect(func(lvl: int, gains: Array):
		Mode.enter(prev_mode)
		_build_dice_menu()
		_render_sheet()
		if not gains.is_empty():
			_say_system("Level %d: you gain %s." % [lvl, ", ".join(gains)], "star")
		GameState.remember_adventure()   # a level is worth resuming from
		# MIL §13 — the world stops for this. State is already committed, so a
		# skipped ceremony can never desync; when it ends the Destiny page
		# opens with the new star flaring.
		var s := GameState.sheet()
		var rite := MythCeremony.play(self, {
			"title": "Level %d" % lvl,
			"line": ("You gain %s." % ", ".join(gains)) if not gains.is_empty() else "%s grows stronger." % str(s.get("name", "the hero")),
			"art": Art.round_tex(Art.hero_key(), 256),
			"sound": "levelup",
			"weight": "major",
		})
		rite.finished.connect(func(): _open_character_screen("Destiny", lvl)))
	add_child(win)
	win.popup_centered()


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
	# R11-01 — while a fight is live, the ENGINE rolls attacks.
	#
	# The GM narrates "make an attack roll"; tag_parser reports an attack check,
	# and this raised a generic d20 bar. A generic check has no target, no reach,
	# no AC, no damage and no action economy — so a natural 20 landed on a foe
	# 55 ft away and left him on full HP. Combat.player_attack() does all of
	# that correctly and was simply never the code that ran.
	#
	# The parser is right to report what it saw; the decision belongs here,
	# where the game knows a fight is on. Suppressed, not silently: the action
	# bar's Attack is the affordance, so say so.
	if not check.is_empty() and str(check.get("type", "")) == "attack" and Combat.active():
		_pending_check = {}
		_roll_bar.visible = false
		_say_system("Choose your target on the board — the table keeps the tally now.")
		return
	_pending_check = check
	_roll_bar.visible = not check.is_empty()
	if check.is_empty():
		return
	var sheet := GameState.sheet()
	if check.get("type", "") == "attack":
		_roll_bar.icon = Ui.ico_tex("sword")
		_roll_bar.text = "Roll to hit  d20 %+d%s" % [Rules.attack_mod(sheet, GameState.inv()),
			("  vs AC %d" % int(check["ac"])) if check.get("ac") != null else ""]
	elif check.get("type", "") == "damage":
		_roll_bar.icon = Ui.ico_tex("die")
		_roll_bar.text = "Roll %s  %dd%d%s" % ["healing" if check.get("heal", false) else "damage",
			int(check["n"]), int(check["sides"]),
			(" %+d" % int(check["bonus"])) if int(check.get("bonus", 0)) != 0 else ""]
	else:
		_roll_bar.icon = Ui.ico_tex("die")
		_roll_bar.text = "Roll %s  d20 %+d%s" % [Rules.check_label(check),
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
			rt.append_text("%s [color=%s][b]HERE ENDS THE TALE OF %s[/b][/color]\nLevel %d %s %s · survived to day %d · %d XP · %d %s in the purse\n[i]The dice remember what the living forget.[/i]" % [Ui.ico("skull", 20),
				Ui.c("danger").to_html(false), _bb(str(s.get("name", "?")).to_upper()),
				int(s.get("level", 1)), _bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))),
				int(c.get("day", 1)), int(s.get("xp", 0)), int(s.get("gold", 0)), GameState.currency()])
			if bool(GameState.rule("permadeath", false)):
				# The table rule: the tale truly ends. The save is archived.
				_say_system("Permadeath — this save is being sealed into the archive.", "skull")
				# The save is a file; sealing it is a local act. This used to POST
				# an archive request for a SERVER session id and leave the file
				# exactly where it was.
				GameState.wipe_adventure(GameState.cid())
			else:
				_say_system("A long rest starts a new dawn… if the GM allows it.")
			_stream(Composer.envelope("[Three death saves failed — I am dying, my tale at its end. Narrate my final moment with the weight it deserves.]"))
		else:
			_stream(Composer.envelope(str(dr["msg"])))
		return
	if _insp_armed and str(check.get("adv", "")) == "" and check.get("type", "") != "damage":
		check["adv"] = "adv"
		_insp_armed = false
		GameState.spend_inspiration()
		_say_system("Inspiration spent — advantage.", "star")
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	if int(res.get("roll", 0)) == 20 and GameState.grant_inspiration():
		Sfx.play("chime")
		_say_system("A natural 20 — you gain Inspiration.", "star")
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
	pop.add_separator("Raw dice")
	idx += 1
	for sides in [4, 6, 8, 10, 12, 20, 100]:
		pop.add_item("d%d" % sides, 910 + sides)
		idx += 1
	pop.add_icon_item(Ui.ico_tex("die"), "Roll an expression… (2d6+3)", 909)
	pop.add_separator("Ask the GM")
	idx += 2
	pop.add_icon_item(Ui.ico_tex("book"), "Learn a spell…", 900)
	pop.add_icon_item(Ui.ico_tex("cups"), "Recruit an ally…", 901)
	pop.add_icon_item(Ui.ico_tex("hammer"), "Craft something…", 902)
	# Recipes whose components sit in the pack craft deterministically (v2).
	var recipes: Array = Rules.tables.get("recipes", [])
	for ri in recipes.size():
		if recipes[ri] is Dictionary and GameState.recipe_ready(recipes[ri]):
			pop.add_icon_item(Ui.ico_tex("hammer"), "Craft: %s  (%s)" % [str(recipes[ri]["name"]),
				", ".join(recipes[ri]["components"])], 700 + ri)
	if bool(GameState.sheet().get("inspiration", false)):
		pop.add_icon_item(Ui.ico_tex("star"), "Spend Inspiration — advantage on your next roll", 903)
	for mi in range(pop.item_count):
		if pop.get_item_icon(mi) != null:
			pop.set_item_icon_max_width(mi, 18)
			pop.set_item_icon_modulate(mi, Ui.c("gold_soft"))
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
		_say_system("Inspiration armed — your next roll has advantage.", "star")
		return
	# Recipe crafting (700-799): the engine consumes components and grants the
	# result — the GM only narrates the making.
	if id >= 700 and id < 800:
		var recipes: Array = Rules.tables.get("recipes", [])
		if id - 700 < recipes.size():
			var note := GameState.craft(str(recipes[id - 700].get("name", "")))
			if note != "":
				Sfx.play("chime")
				_say_me(_md(note))
				_render_sheet()
				_build_dice_menu()  # the crafted recipe may no longer be ready
				_last_player_msg = note
				_stream(Composer.envelope("[%s Narrate the making briefly.]" % note.replace("*", "")))
		return
	# Raw dice tray: table candy, resolved and shown — the GM isn't bothered.
	if id >= 910:
		var sides := id - 910
		var r := randi_range(1, sides)
		await _animate_die(sides, r, "d%d" % sides)
		_say_system("You roll a d%d: %d." % [sides, r], "die")
		return
	if id == 909:
		var dlg := ConfirmationDialog.new()
		dlg.title = "Roll dice"
		dlg.ok_button_text = "Roll"
		var expr_in := LineEdit.new()
		expr_in.placeholder_text = "2d6+3"
		expr_in.custom_minimum_size = Vector2(220, 0)
		dlg.add_child(expr_in)
		add_child(dlg)
		dlg.popup_centered()
		expr_in.grab_focus()
		dlg.confirmed.connect(func():
			var m := RegEx.create_from_string("(?i)^\\s*(\\d*)d(\\d+)\\s*([+-]\\s*\\d+)?\\s*$").search(expr_in.text)
			dlg.queue_free()
			if m == null:
				_say_system("That's not a dice expression — try 2d6+3.")
				return
			var n := maxi(1, int(m.get_string(1)) if m.get_string(1) != "" else 1)
			var die_sides := clampi(int(m.get_string(2)), 2, 1000)
			var mod := int(m.get_string(3).replace(" ", "")) if m.get_string(3) != "" else 0
			var total := mod
			var rolls: Array[String] = []
			for i in mini(n, 40):
				var one := randi_range(1, die_sides)
				total += one
				rolls.append(str(one))
			_say_system("You roll %s: [%s]%s = %d." % [expr_in.text.strip_edges(), ", ".join(rolls),
				(" %+d" % mod) if mod != 0 else "", total], "die"))
		dlg.close_requested.connect(dlg.queue_free)
		return
	if id == 902:
		_ask_gm("Craft something", "What do you try to make (and from what)?",
			func(x): return "[I try to craft: %s. Check my pack in the context — decide honestly if my materials and skills allow it, what it costs (time, gold, a roll), and if I succeed, grant it with [[loot name=\"...\"]] and take costs with [[gold delta=-N]]. You may also award raw crafting components as loot (Healing Herbs, Glass Vial, Oil Flask, Wood Branch, Rag Wick, Herb Bundle, Meat Cut, Bitterleaf, Ash Powder) — the engine crafts known recipes from them.]" % x)
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
		_say_system("Inspiration spent — advantage.", "star")
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	if int(res.get("roll", 0)) == 20 and GameState.grant_inspiration():
		Sfx.play("chime")
		_say_system("A natural 20 — you gain Inspiration.", "star")
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


## 🎒 The pack lives in THE MENU's Gear tab now — one place for all of it.
func _open_inventory() -> void:
	_open_character_screen("Gear")


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
		"dest":
			_open_character_screen("Destiny")
			return
		"record":
			_open_character_screen()
			return
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
		# Every one of these is a tab in the menu now — open it there.
		"tune", "snap":
			_open_character_screen("The Table")
			return
		"chron":
			_open_character_screen("Chronicle")
			return
		"atlas", "map":
			_open_character_screen("Atlas")
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
				_say_system("Not enough %s for the %s (%d needed)." % [GameState.currency(), bits[0].uri_decode(), price])
				return
			GameState.add_gold(-price)
			GameState.add_item(bits[0].uri_decode())
			note = "*You buy the %s for %d %s.*" % [bits[0].uri_decode(), price, GameState.currency()]
			tell_gm = true
	if note == "":
		return
	_render_sheet()
	if tell_gm:
		_say_me(_md(note))
		_last_player_msg = note
		_stream(Composer.envelope(note))
	else:
		# ✋ is the internal "action failed — don't tell the GM" sentinel; never shown.
		_say_system(note.trim_prefix("✋ ").replace("*", ""))


# ── Combat actions ───────────────────────────────────────────────────────────
var _init_rail: HBoxContainer       # the initiative rail: faces in turn order
var _mini_map: Control              # the corner chart (it hides itself in combat)
var _rail_turn_id := ""             # whose chip pulsed last
var _rail_chips := {}               # id → MythPortrait, reused across renders
var _rail_ids: Array = []           # roster signature; rebuild only when it changes
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
		_say_system("The GM is mid-tale — wait for the words to settle.", "hourglass")
	elif Mode.state == "Death":
		_say_system("You are down — roll your death save.", "skull")
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
		var res: Dictionary = Combat.player_attack(m.substr(4))
		# B4: your swing gets the dice moment too — the tracker's math, the
		# table's drama.
		if res.has("roll") and str(res.get("msg", "")) != "":
			await _animate_die(20, int(res["roll"]), str(res.get("caption", "Attack")))
		_deliver_player_hit(res)


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
				_say_system("Round %d — your turn: move on the board, attack, or cast." % int(c.get("round", 1)), "sword")
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
## ⚡ Reaction! — extracted to scenes/ui/reaction_prompt.gd (A0 #5). The play
## screen owns only the hit resolution + narration + round resume.
func _reaction_overlay(pend: Dictionary, reactions: Array) -> void:
	var enemy: Dictionary = pend["enemy"]
	var win := preload("res://scenes/ui/reaction_prompt.gd").new()
	win.pend = pend
	win.reactions = reactions
	win.resolved.connect(func(dmg: int, note: String):
		var r: Dictionary = Combat.resolve_enemy_hit(enemy, dmg, bool(pend["crit"]), note)
		_deliver_enemy_result(r))
	add_child(win)
	win.popup_centered()


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
	elif Combat._impassable(cell):
		_say_system("Something solid stands there — no way through.")
	else:
		# A wall on the border refuses a square that looks open, so this can no
		# longer claim "too far" and be sure of it.
		_say_system("No way through from here — blocked, taken, or out of reach.")


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
			_say_me(Ui.ico("sword", 16) + " " + _bb(flourish))
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
	# (R11-03's hide used to live here and never worked: mini_map's own _process
	# reassigns `visible` every frame, so this was overwritten before the next
	# draw. The chart hides itself now — see mini_map.gd.)
	# The living backdrop is the location painting at 0.45, breathing on a Ken
	# Burns loop. Behind a battle board it is a drifting green wash under the
	# composer and the action bar — the "random green blob". During a fight the
	# BOARD is the scene, so the backdrop steps back and holds still.
	if _scene_art != null and _scene_art.texture != null:
		var want := 0.10 if fighting else 0.45
		if not is_equal_approx(_scene_art.modulate.a, want):
			create_tween().tween_property(_scene_art, "modulate:a", want, Ui.TIME["slow"])
	if _init_rail != null and not fighting:
		_init_rail.visible = false
		_rail_ids = []  # next fight rebuilds its own roster of chips
	if fighting:
		Combat.ensure_positions()
		var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
		# R10 — the battlefield is LAID, not sampled. A stencil chosen from where
		# the fiction says we are places ground, obstacles and walls; the world
		# only decides which tiles dress it. Deterministic per fight, so a reload
		# rebuilds the same field.
		if Combat.data().get("cells") == null:
			Combat.lay_battlefield(Combat.stencil_for(here), GameState.world_id(), int(c.get("round", 1)))
		_battle_grid.map_key = ""
	# The room darkens toward ember-red while steel is out — ONCE per state
	# change. (This fired on every combat save: stacked tint tweens pumped
	# the light and the music crossfade restarted constantly — the flicker.)
	if fighting != _was_fighting:
		_was_fighting = fighting
		var tween := create_tween()
		tween.tween_property(_battle_tint, "color:a", 0.05 if fighting else 0.0, 0.8)
		if fighting:
			Sfx.music("combat")
		else:
			Sfx.music(WorldSkin.music_for_id(GameState.world_id()))
	if not fighting:
		return
	if Mode.state not in ["Combat", "Death", "GameOver", "LevelUp"]:
		Mode.enter("Combat")  # steel is out — whatever mode we drifted to yields
	if not Combat.pc_down().is_empty():
		if Mode.state == "Combat":
			Mode.enter("Death")  # the only roll that matters now is the save
		_pending_check = {"type": "death"}
		_roll_bar.icon = Ui.ico_tex("skull")
		_roll_bar.text = "Roll a death save"
		_roll_bar.visible = true
	var gold := Ui.c("gold_soft").to_html(false)
	var danger := Ui.c("danger").to_html(false)
	var cur: Dictionary = Combat.current(c)
	var lines: Array[String] = []
	lines.append("%s [color=%s][b]COMBAT — Round %d[/b][/color]    [url=cnext]End turn ›[/url]    [url=cend]End combat[/url]" % [Ui.ico("sword", 18), gold, int(c.get("round", 1))])
	for m in Combat.order(c):
		var here := "▶ " if str(m.get("id")) == str(cur.get("id")) else "   "
		var hp := int(m.get("hp", 0))
		var hp_max := maxi(1, int(m.get("hpMax", 1)))
		var bar_n := clampi(roundi(10.0 * hp / hp_max), 0, 10)
		var color := gold if m.get("side") == "ally" else danger
		var row := "%s[color=%s]%s[/color]  [color=%s]%s[/color][color=%s]%s[/color] %d/%d" % [here, color, _bb(str(m.get("name", "?"))),
			color, "▰".repeat(bar_n), Ui.c("ink_dim").to_html(false), "▱".repeat(10 - bar_n), hp, hp_max]
		if m.get("side") == "enemy" and hp > 0:
			row += "   [url=atk:%s]%s attack[/url]" % [str(m.get("id")), Ui.ico("sword", 16)]
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
## Reconciled in place: the chips are BUILT once per roster change and then
## only have their vitals/turn-state refreshed. Freeing and re-adding every
## chip on each combat save was the battle-screen flicker.
func _render_init_rail(c: Dictionary, cur: Dictionary) -> void:
	_init_rail.visible = true
	var cur_id := str(cur.get("id", ""))
	var order := Combat.order(c)
	var ids: Array = order.map(func(m): return str(m.get("id", "")))
	if ids != _rail_ids:
		for ch in _init_rail.get_children():
			ch.queue_free()
		_rail_chips.clear()
		for m in order:
			var id := str(m.get("id", ""))
			var chip := MythPortrait.new(46, "gold" if m.get("side") == "ally" else "danger", false)
			chip.set_portrait(Art.combatant_tex(m), str(m.get("name", "?")).left(1).to_upper())
			_init_rail.add_child(chip)
			_rail_chips[id] = chip
		_rail_ids = ids
	for m in order:
		var id := str(m.get("id", ""))
		var chip: MythPortrait = _rail_chips.get(id)
		if chip == null:
			continue
		chip.set_vitals(clampf(float(m.get("hp", 0)) / maxf(1.0, float(m.get("hpMax", 1))), 0.0, 1.0), id == cur_id)
		chip.modulate = Color(1, 1, 1, 0.32) if int(m.get("hp", 0)) <= 0 else Color.WHITE
		chip.tooltip_text = "%s — %d/%d" % [str(m.get("name", "?")), int(m.get("hp", 0)), int(m.get("hpMax", 1))]
	if cur_id != _rail_turn_id and _rail_chips.has(cur_id):
		Ui.pulse(_rail_chips[cur_id])
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
		bits.append("[color=%s]%s %d ft left[/color]" % [dim, Ui.ico("boot", 16), int(Combat.move_budget(c).get("left", 0)) * Combat.FEET_PER_CELL])
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


## The living world breathes between days: off-screen events surface as an aside
## and fold into memory. Chronicle owns the model call; this owns the bubble.
func _worldtick() -> void:
	var r := await Chronicle.world_tick()
	var events: Array = r.get("events", [])
	if events.is_empty():
		return
	var tick := " ".join(events)
	var rt := _bubble("gm")
	rt.append_text("[color=%s][i]Meanwhile… %s[/i][/color]" % [Ui.c("ink_dim").to_html(false), _bb(tick.left(400))])
	var nq: Dictionary = r.get("newQuest", {})
	if not nq.is_empty():
		rt.append_text("\n[color=%s][i]New thread: %s — %s[/i][/color]" % [
			Ui.c("gold").to_html(false), _bb(str(nq.get("title", ""))), _bb(str(nq.get("desc", "")))])
	Chronicle.record("(a day passes)", "Meanwhile: " + tick.left(300))


# ── Images ───────────────────────────────────────────────────────────────────
## Paint a cached painting into the tale AND behind it (the living backdrop).
## Takes an Art KEY now, not a URL — the Art Director owns every fetch, so an
## image can no longer arrive from a request this screen didn't make.
func _show_image(key: String) -> void:
	var tex := Art.texture_for(key)
	if tex == null or not is_inside_tree():
		return
	_show_backdrop(key)
	# Then inline, sized to the thread.
	var img := tex.get_image()
	var w := 520
	if img.get_width() > w:
		img.resize(w, img.get_height() * w / img.get_width(), Image.INTERPOLATE_LANCZOS)
	var rt := _bubble("gm")
	rt.add_image(ImageTexture.create_from_image(img))
	_scroll_bottom()


## The GM moved us somewhere new — quietly repaint the backdrop (no inline).
## Through the Art Director like everything else: this used to POST straight to
## /generate and could collide with a queued portrait on the one GPU, which is
## how a stranger's photograph landed in the scene slot (playtest #1). Keyed by
## place, so returning somewhere reuses its painting instead of repainting it.
func _repaint_scene(place: String) -> void:
	var key := "scene-%s-%s" % [GameState.world_id().validate_filename(),
		place.to_lower().replace(" ", "-").validate_filename().left(48)]
	# R6 FUN-28 / Performance §7 — the room CHANGES the instant you arrive.
	#
	# This used to do one thing: queue a bespoke ~25 s render in the NOW lane and
	# leave the old scene up until it landed. So the world visibly lagged the
	# story by half a minute, on the player's own GPU, competing with the
	# narrator — while six finished biome plates for this very world sat unused
	# in its package. Show the baked plate immediately (free, instant), and let
	# the bespoke painting replace it later from the IDLE lane if the player ever
	# generates one. Nothing waits on the GPU to feel like somewhere new.
	if not Art.has_art(key):
		var kind := ""
		for l in Rules.world_locations(GameState.world_id()):
			if l is Dictionary and str(l.get("name", "")) == place:
				kind = str(l.get("kind", ""))
				break
		var plate: Texture2D = Compiler.biome_art(GameState.world_id(),
			Compiler.biome_for_place(place, kind))
		if plate != null:
			_paint_backdrop(plate)
	var prompt := "%s, in the world of %s. Atmospheric %s establishing scene, cinematic lighting, no people, no text." % [
		place, WorldSkin.world_name(GameState.world_id()), Art.world_flavor()]
	Art.request(key, prompt, {"lane": Art.Lane.IDLE, "owner": self,
		"on_ready": func(k: String): _show_backdrop(k)})


## Fade a cached painting in as the room behind the words.
func _show_backdrop(key: String) -> void:
	var tex := Art.texture_for(key)
	if tex == null:
		return
	_paint_backdrop(tex)


## The actual crossfade, for either source — a baked biome plate on arrival, or
## the bespoke painting once it exists.
func _paint_backdrop(tex: Texture2D) -> void:
	if tex == null or not is_inside_tree():
		return
	_scene_art.texture = tex
	_scene_art.modulate.a = 0.0
	create_tween().tween_property(_scene_art, "modulate:a", 0.45, Ui.TIME["slow"] * 4.0)
	_ken_burns()


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
	_say_system("The scene paints itself…", "easel")
	# Keyed by the moment it depicts, and queued like everything else — the
	# GPU serves one master. A repeat of the same beat reuses its painting.
	var key := "scene-%s-%d" % [GameState.world_id().validate_filename(), abs(last_gm.left(400).hash())]
	var prompt := "The current scene: %s. Cinematic %s illustration, dramatic lighting, no text." % [
		last_gm.left(400), Art.world_flavor()]
	Art.request(key, prompt, {"lane": Art.Lane.NOW, "owner": self,
		"on_ready": func(k: String):
			_conjuring = false
			_show_image(k)})
	# The Director reports honestly: a failure says so instead of hanging.
	if not Art.art_progress.is_connected(_on_art_progress):
		Art.art_progress.connect(_on_art_progress)


func _on_art_progress(key: String, state: String) -> void:
	if state == "failed" and key.begins_with("scene-"):
		_conjuring = false
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
	# The old text-link rail is gone — those six destinations are tabs in the
	# menu now (the Sheet button, or Ctrl+H, opens it).
	var dim := Ui.c("ink_dim").to_html(false)
	lines.append("[center][font_size=22][color=%s][b]%s[/b][/color][/font_size]" % [gold, _bb(str(s.get("name", "?")))])
	lines.append("[color=%s]%s %s  ·  Level %d[/color][/center]" % [dim, _bb(str(s.get("race", ""))), _bb(Rules.class_label(s)), int(s.get("level", 1))])
	lines.append("")
	var hp := int(s.get("hp", 10))
	var hp_max := maxi(1, int(s.get("hpMax", 10)))
	lines.append("AC [b]%d[/b]    %s [b]%d[/b]    Perception [b]%d[/b]" % [Rules.eff_ac(s, GameState.inv()),
		GameState.currency().capitalize(), int(s.get("gold", 0)), Rules.passive_perception(s)])
	# Compact HUD: vitals + things you can DO mid-scene. Everything you'd only
	# read (abilities, proficiencies, pack, feats) lives in THE MENU now.
	if int(s.get("exhaustion", 0)) > 0:
		lines.append("[color=%s]Exhaustion level %d[/color]" % [Ui.c("danger").to_html(false), int(s["exhaustion"])])
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false),
			_bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c))))])
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
	# Only features with an ACTION earn a HUD row; inert ones read in the menu.
	var acted := false
	for f in s.get("features", []):
		var key := GameState.feature_action_key(str(f))
		if key == "":
			continue
		if not acted:
			acted = true
			lines.append("")
			lines.append(_hdr("ACTIONS"))
		var left := GameState.feature_uses_left(key)
		lines.append("  %s  %s" % [_bb(str(f)),
			"[url=feat:%s]◆ use (%d/%d)[/url]" % [key.uri_encode(), left, int(GameState.FEATURE_ACTIONS[key]["uses"])] if left > 0
			else "[color=%s]◇ spent[/color]" % Ui.c("ink_dim").to_html(false)])
	lines.append("")
	lines.append("[center][url=record]Open the Record ›[/url][/center]")
	# Same content → don't clear/rebuild (a needless repaint is a visible blink).
	var face := Art.round_tex(Art.hero_key(), 148)
	var sig := "\n".join(lines) + "|" + str(face)
	if sig == _sheet_sig:
		return
	_sheet_sig = sig
	_sheet_panel.clear()
	if face != null:
		_sheet_panel.append_text("[center]")
		_sheet_panel.add_image(face)
		_sheet_panel.append_text("[/center]\n")
	# Name + class, then a DRAWN HP bar (an image, not ▰▱ font glyphs).
	_sheet_panel.append_text(lines[0] + "\n" + lines[1] + "\n\n")
	_sheet_panel.append_text("HP [b]%d / %d[/b]  " % [hp, hp_max])
	_sheet_panel.add_image(_hud_bar(float(hp) / float(hp_max)))
	_sheet_panel.append_text("\n" + "\n".join(lines.slice(2)))


## The HUD's health bar, drawn: a night trough with an ink-thin frame, filled
## gold while healthy, ember-red once past half. Rebuilt per repaint — cheap.
func _hud_bar(ratio: float) -> ImageTexture:
	var w := 150
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(Ui.c("border"), 0.9))
	img.fill_rect(Rect2i(1, 1, w - 2, h - 2), Ui.c("night").lightened(0.05))
	var fill := int(float(w - 4) * clampf(ratio, 0.0, 1.0))
	if fill > 0:
		var col := Ui.c("gold") if ratio >= 0.5 else Ui.c("danger")
		img.fill_rect(Rect2i(2, 2, fill, h - 4), col)
		img.fill_rect(Rect2i(2, 2, fill, 3), col.lightened(0.25))  # a top light so it reads as a bar, not a stripe
	return ImageTexture.create_from_image(img)


## 🛒 The trading post — extracted to scenes/ui/merchant_window.gd (A0 split).
## The play screen owns only what is its: the Mode transitions, the keeper's
## remembered mood (_shop_markup), and telling the GM about the visit once.
func _open_shop() -> void:
	if not Mode.can("shop"):
		return
	Mode.enter("Merchant")
	var win := preload("res://scenes/ui/merchant_window.gd").new()
	win.markup = _shop_markup
	win.haggled.connect(func(m: float): _shop_markup = m)
	win.counter_left.connect(_on_counter_left)
	add_child(win)
	win.popup_centered()


func _on_counter_left(deals: Array) -> void:
	Mode.enter("Exploration")
	_render_sheet()
	if not deals.is_empty():
		var summary := "*At the trader: %s.*" % "; ".join(deals)
		_say_me(_md(summary))
		_last_player_msg = summary
		_stream(Composer.envelope("[%s Briefly color the exchange — the keeper's manner, a passing detail.]" % summary.replace("*", "")))


# ── The codex panel: the cast you've met and the threads you're pulling ─────
func _render_codex() -> void:
	_sheet_sig = ""  # the panel now holds codex text; the HUD must rebuild on return
	var gold := Ui.c("gold_soft").to_html(false)
	_sheet_panel.clear()
	_sheet_panel.append_text("%s [color=%s][b]The Cast[/b][/color]\n" % [Ui.ico("scroll", 18), gold])
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
				_sheet_panel.append_text("  [url=portrait:%s]%s[/url]" % [str(n["name"]).uri_encode(), Ui.ico("easel", 16)])
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
	_say_system("Painting %s…" % nm, "easel")
	await Art.ensure("npc-" + nm.to_lower().replace(" ", "-"),
		"portrait of %s, %s. %s character portrait, painterly, head and shoulders" % [nm, look,
		{"neonspire": "cyberpunk", "everyday": "contemporary"}.get(GameState.world_id(), "fantasy")])
	if _panel_mode == "codex":
		_render_codex()


# ── M2: tune / snapshots / atlas ─────────────────────────────────────────────
## Re-open the Session Zero knobs mid-campaign; saved live to the gm kind.
func _session_zero_retune() -> void:
	var tuner := preload("res://scenes/ui/gm_tuner.gd").new()
	tuner.initial = GameState.state.get("gm", {}) if GameState.state.get("gm") is Dictionary else {}
	tuner.tuned.connect(func(_knobs: Dictionary): _say_system("The table's tone shifts.", "tune"))
	add_child(tuner)
	tuner.popup_centered()


## 💾 A chapter marker: the backend distills the recent tale into a snapshot.
func _save_snapshot() -> void:
	if Chronicle.transcript.is_empty():
		_say_system("Nothing to chronicle yet — play a little first.")
		return
	_say_system("The chronicler sets down this chapter…", "save")
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/snapshot", {
		"character_id": GameState.cid(), "character_name": str(GameState.character.get("name", "")),
		"world_id": GameState.world_id(), "transcript": Chronicle.transcript})
	if r.get("_status", 0) == 200:
		var snap: Dictionary = r.get("snapshot", r)
		Sfx.ui("save")   # MIL §5 — saving is visible AND audible, or it isn't trusted
		_say_system("Chapter saved: %s" % str(snap.get("title", "untitled")), "save")
		GameState.remember_adventure()
	else:
		# MIL §6 — the world faltering, never a status code.
		Sfx.ui("ui_deny")
		_say_system("The chronicler's ink ran dry — the chapter didn't set. Try again in a moment.")


## Resume from a chapter: its summary re-anchors the GM's context.
func _recall_snapshot(id: String) -> void:
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/snapshots?character_id=" + GameState.cid().uri_encode())
	for sn in r.get("snapshots", r.get("data", [])):
		if sn is Dictionary and str(sn.get("id", "")) == id:
			_say_me(_bb("We pick the tale back up at: %s" % str(sn.get("title", ""))))
			_last_player_msg = "We resume from a saved chapter."
			_stream(Composer.envelope("[We resume from this saved chapter — treat it as where the story stands: %s. Re-set the scene and continue.]" % str(sn.get("story_so_far", ""))))
			return


## 🗺 The painted map: the world's key art with its places marked.
## (The old text atlas bubble folded into this — the map IS the atlas.)
func _open_world_map() -> void:
	var locs: Array = Rules.world_locations(GameState.world_id())
	if locs.is_empty():
		for w in GameState.global_get("cworlds", []):
			if w is Dictionary and str(w.get("id", "")) == GameState.world_id():
				locs = w.get("locations") if w.get("locations") is Array else []
	if locs.is_empty():
		_say_system("No charted places to map yet.")
		return
	var dlg := AcceptDialog.new()
	MythEnvironment.mount(dlg, "env-maptable", "dust", [Vector2(0.93, 0.9)])
	dlg.title = str(GameState.character.get("name", "the world")).split(":")[0]
	dlg.ok_button_text = "Close the map"
	Art.ensure_world_chart(GameState.world_id(), str(GameState.character.get("name", "")).split(":")[0], locs)
	var map := preload("res://scenes/ui/world_map.gd").new()
	map.locations = locs
	var world_d: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	map.here = str(world_d.get("here", ""))
	map.seen = world_d.get("seen") if world_d.get("seen") is Array else []
	map.fog = bool(GameState.rule("fog", true))
	map.quest_text = Chronicle.quests_text()
	map.travel_requested.connect(func(place):
		dlg.queue_free()
		_travel_to(place))
	dlg.add_child(map)
	add_child(dlg)
	dlg.popup_centered()
	Ui.ritual_open(dlg)


## Auto here-tracking: the GM's [[scene]] prose moves the pin when the place
## matches a charted location — the map follows the story without a click.
func _track_here(place: String) -> void:
	var pl := place.to_lower()
	for l in Rules.world_locations(GameState.world_id()):
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", ""))
		if nm == "" or not (pl.contains(nm.to_lower()) or nm.to_lower().contains(pl)):
			continue
		var world = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
		if str(world.get("here", "")) == nm:
			return
		world["here"] = nm
		var seen: Array = world.get("seen") if world.get("seen") is Array else []
		if not seen.has(nm):
			seen.append(nm)
		world["seen"] = seen
		GameState.save_kind("world", world)
		return


func _travel_to(place: String) -> void:
	if not Mode.can("send_message"):
		return
	var world = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	world["here"] = place
	# The map remembers: fog burned away stays away.
	var seen: Array = world.get("seen") if world.get("seen") is Array else []
	if not seen.has(place):
		seen.append(place)
	world["seen"] = seen
	GameState.save_kind("world", world)
	GameState.advance_time(1)
	Sfx.ui("travel")   # MIL — departure has a sound; the road opens
	_say_system("You set off for %s." % place, "compass")
	_repaint_scene(place)
	_last_player_msg = "I travel to %s." % place
	# The road is never guaranteed: 1-in-5 journeys meet something.
	if randf() < 0.2:
		_stream(Composer.envelope("[I travel to %s — but something finds me on the road. Run a brief encounter (a threat, a stranger, or a wonder), then let me arrive.]" % place))
	else:
		_stream(Composer.envelope("[I travel to %s. Describe the journey briefly and my arrival — who is about, what I notice first.]" % place))


## Dusk cools the scene; deep night darkens it (time-of-day tint).
const _TIME_TINT := [Color(1.0, 0.92, 0.85), Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.97, 0.9), Color(0.95, 0.85, 0.85), Color(0.8, 0.78, 0.9), Color(0.62, 0.62, 0.78)]


var _last_tint_ti := -1
var _was_fighting := false


func _apply_time_tint() -> void:
	var ti := clampi(int(GameState.clock().get("ti", 1)), 0, _TIME_TINT.size() - 1)
	if ti == _last_tint_ti:
		return  # stacking a fresh tween every render made the light pump/flicker
	_last_tint_ti = ti
	var target: Color = _TIME_TINT[ti]
	target.a = _scene_art.modulate.a
	create_tween().tween_property(_scene_art, "modulate", target, 1.2)


## The banner chips: time · weather · place · quest · party wounds.
func _render_chips() -> void:
	_apply_time_tint()
	_render_suggestions()   # the verbs track the same state the chips do
	var c: Dictionary = GameState.clock()
	var bits: Array[String] = []
	# R6 PLAY-01 / STR-04 — HP and purse led this row's absence: the two numbers
	# a player needs continuously lived ONLY inside the Record modal, so the
	# honest answer to "am I dying?" was "open a dialog and read". They go first,
	# and HP takes the wound colour as it falls so the state is legible at a
	# glance rather than requiring arithmetic.
	var sh := GameState.sheet()
	var hp := int(sh.get("hp", 0))
	var hp_max := maxi(1, int(sh.get("hpMax", 1)))
	var frac := float(hp) / float(hp_max)
	var hp_col: Color = Ui.c("ink") if frac > 0.5 else (Ui.c("ember") if frac > 0.25 else Ui.c("danger"))
	bits.append("[color=#%s]%s %d/%d[/color]" % [hp_col.to_html(false), Ui.ico("blood", 15), hp, hp_max])
	bits.append("%s %d %s" % [Ui.ico("coins", 15), int(sh.get("gold", 0)), GameState.currency()])
	var wx := str(c.get("wx", {}).get("name", "")) if c.get("wx") is Dictionary else ""
	bits.append("%s %s · Day %d %s" % [Ui.ico("hourglass", 15), GameState.TIMES[clampi(int(c.get("ti", 0)), 0, GameState.TIMES.size() - 1)], int(c.get("day", 1)), wx])
	var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	if here != "":
		bits.append("%s %s" % [Ui.ico("compass", 15), here])
	var quests = GameState.state.get("quests", [])
	if quests is Array:
		for q in quests:
			if q is Dictionary and str(q.get("status", "active")) != "done" and str(q.get("title", "")) != "":
				bits.append("◈ " + str(q["title"]).left(36))
				break
	if bool(GameState.sheet().get("inspiration", false)):
		bits.append("%s Inspiration" % Ui.ico("star", 15))
	for cmp in GameState.sheet().get("companions", []):
		if cmp is Dictionary:
			var chp := int(cmp.get("hp", 0))
			var cmax := maxi(1, int(cmp.get("hpMax", 1)))
			var wound := (Ui.ico("blood", 15) + " ") if chp * 3 < cmax else ""
			bits.append("%s%s %s %d/%d" % [wound, Ui.ico("sword", 15), str(cmp.get("name", "")), chp, cmax])
	var chips: RichTextLabel = $Margin/Split/ChatBox/Chips
	chips.add_theme_color_override("default_color", Ui.c("ink_dim"))
	chips.text = "[center]%s[/center]" % "     ".join(bits)


## Keyboard: Ctrl+S sheet · Ctrl+L codex · Ctrl+R retell · Space next turn
## (combat, when not typing) · Esc back to the message box.
## Controller: the pad's app actions (Pad autoload registers them) and the
## combat grid cursor. Focus traversal itself rides the built-in ui_* actions;
## this only covers the play screen's custom surfaces.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mf_roll") and _roll_bar.visible:
		_roll_pending()
	elif event.is_action_pressed("mf_end_turn") and Mode.is_state("Combat"):
		_on_combat_action("cnext")
	elif event.is_action_pressed("mf_menu"):
		_msg.grab_focus()
	elif Mode.is_state("Combat") and _battle_grid.visible and not _msg.has_focus():
		if event.is_action_pressed("ui_left"):
			_battle_grid.pad_move(-1, 0)
		elif event.is_action_pressed("ui_right"):
			_battle_grid.pad_move(1, 0)
		elif event.is_action_pressed("ui_up"):
			_battle_grid.pad_move(0, -1)
		elif event.is_action_pressed("ui_down"):
			_battle_grid.pad_move(0, 1)
		elif event.is_action_pressed("ui_accept"):
			_battle_grid.pad_activate()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		_panel_mode = "sheet"  # Ctrl+S toggles the sidebar HUD; the button opens the menu
		$Margin/Split/ChatBox/Input/CodexBtn.set_pressed_no_signal(false)
		_sheet_panel.visible = not _sheet_panel.visible
		if _sheet_panel.visible:
			_render_sheet()
	elif event.ctrl_pressed and event.keycode == KEY_L:
		var btn2: Button = $Margin/Split/ChatBox/Input/CodexBtn
		btn2.button_pressed = not btn2.button_pressed
	elif event.ctrl_pressed and event.keycode == KEY_R:
		_regen()
	elif event.ctrl_pressed and event.keycode == KEY_E:
		_edit_last()
	elif event.keycode == KEY_SPACE and Mode.is_state("Combat") and not _msg.has_focus():
		_on_combat_action("cnext")
	elif event.ctrl_pressed and event.keycode == KEY_M:
		_open_character_screen("Atlas")
	elif event.ctrl_pressed and event.keycode == KEY_J:
		# The Journal folded into the Lore Book (A0 split) — Quests, The Cast,
		# and Chronicle tabs cover everything the inline manuscript showed.
		_open_lore_book()
	elif event.ctrl_pressed and event.keycode == KEY_I:
		_open_inventory()
	elif event.ctrl_pressed and event.keycode == KEY_K:
		_open_character_screen("Destiny")
	elif event.ctrl_pressed and event.keycode == KEY_H:
		_open_character_screen()
	elif event.keycode == KEY_ESCAPE:
		_msg.grab_focus()


## ✨ The Constellation of Destiny (docs/rituals/SkillTree.md): the class's
## whole road as a night sky; a fresh level flares alight after the ceremony.
func _open_skill_tree(pulse_level := -1) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "The %s of %s" % [WorldSkin.tree_title(GameState.world_id()), str(GameState.sheet().get("name", "the hero"))]
	dlg.ok_button_text = "Return to the tale"
	var tree := preload("res://scenes/ui/skill_tree.gd").new()
	tree.pulse_level = pulse_level
	dlg.add_child(tree)
	add_child(dlg)
	dlg.popup_centered()
	Ui.ritual_open(dlg)
	dlg.confirmed.connect(dlg.queue_free)


## 🛡 The Hero's Record (docs/rituals/CharacterScreen.md): identity before
## statistics — a reading surface; actions live in the Pack and side sheet.
## The Lore Book (M-C): the world's illustrated encyclopedia, grown from play.
func _open_lore_book(at := "") -> void:
	if _streaming:
		return
	var book := preload("res://scenes/ui/lore_book.tscn").instantiate()
	if at != "":
		book._active = at  # open on a specific tab (e.g. Chronicle)
	book.resume_requested.connect(func(sid: String):
		book.queue_free()
		_recall_snapshot(sid))
	add_child(book)
	Ui.reveal(book)


## THE MENU — one screen, every destination a tab (Record/Gear/Skills/Powers/
## Story/Destiny/Atlas/Chronicle/The Table). Opens on whichever tab you asked
## for, so nothing is buried behind a text link any more.
func _open_character_screen(at := "", pulse := -1) -> void:
	# can_panels() (not can) so the sheet/inventory opens even mid-stream (busy) —
	# viewing is safe; equip/sell inside still honour can("panels").
	if not Mode.can_panels():
		return
	var rec := preload("res://scenes/ui/character_screen.gd").new()
	# R7-03 — the Record is the densest data surface in the game (nine tabs,
	# thirteen equipment wells, stat rows). At the environment's default veil the
	# fireside painting competed with all of it for the eye. A forge screen is
	# mostly empty and can carry a bright room; this one cannot.
	MythEnvironment.mount(rec, "env-fireside", "dust", [Vector2(0.1, 0.2)]).scrim = 0.80
	rec.pulse_level = pulse
	if at != "":
		rec._active = at
	rec.travel_requested.connect(_travel_to)
	rec.resume_requested.connect(_recall_snapshot)
	rec.save_chapter_requested.connect(_save_snapshot)
	rec.leave_requested.connect(_leave_to_hall)
	# Gear changes (equip/sell) happen inside the menu now — repaint the HUD after.
	rec.tree_exited.connect(func():
		if is_inside_tree():
			_render_sheet())
	add_child(rec)
	rec.popup_centered()
	Ui.ritual_open(rec)


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


## R9-03 — is this foe actually in the scene?
##
## The player may name anything; the game may only stage what the story has put
## in front of them. The scene is the GM's last prose, so the target has to
## appear there — by full name, or by a distinctive word of it ("Jenkins" for
## "Samuel Jenkins", "jotun" for "Ice Jotun"). Short words are ignored, or "the"
## would match every scene ever written.
##
## An unrecognised target is not refused, it is simply not STAGED: the message
## still goes to the GM, who is free to answer with a real encounter and open
## the fight properly. The old behaviour built the foe out of the player's
## sentence and then let the GM contradict it.
func _foe_is_present(who: String) -> bool:
	if _last_scene.strip_edges() == "":
		return false
	var hay := _last_scene.to_lower()
	var name := who.to_lower().strip_edges()
	if name != "" and hay.contains(name):
		return true
	for word in name.split(" ", false):
		if word.length() >= 4 and hay.contains(word):
			return true
	return false

class_name MythCeremony extends Control
## MIL §13 — the five-beat grammar every milestone shares:
##   1 Hush    the world quiets (dim, ambient ducks, motion stills)
##   2 Gather  the elements converge (art assembles, light draws inward)
##   3 Strike  the peak (bloom + fanfare, held)
##   4 Bestow  what you gained, stated plainly
##   5 Return  the world comes back, focus lands somewhere useful
##
## Ceremony law: ALWAYS skippable (any input completes it), NEVER blocking
## truth (state is committed before it plays, so an interrupted ceremony can
## never desync), and under reduce_motion the beats survive as crossfade +
## hold — shortened, never removed.
##
## spec = {
##   title:   String            the moment ("Level 4")
##   line:    String            one line of consequence ("+7 HP · the path of the Champion")
##   art:     Texture2D  (opt)  the face of the moment — hero, item, foe
##   sound:   String     (opt)  defaults to "levelup"
##   weight:  "major"|"light"   light skips Hush and shortens the hold
##   tint:    String     (opt)  palette role for the bloom (rarity colour)
## }

signal finished

var spec := {}
var _done := false
var _veil: ColorRect
var _card: Control


static func play(host: Node, ceremony_spec: Dictionary) -> MythCeremony:
	var c := MythCeremony.new()
	c.spec = ceremony_spec
	host.add_child(c)
	return c


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # a ceremony owns the screen while it plays
	z_index = 120
	var major := str(spec.get("weight", "major")) == "major"
	var tint: Color = Ui.c(str(spec.get("tint", "gold")))
	# ── Beat 1 — Hush: the world dims and holds its breath ──
	_veil = ColorRect.new()
	_veil.color = Color(Ui.c("night"), 0.0)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	# ── Beat 2 — Gather: the moment assembles at centre ──
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_card as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_card as VBoxContainer).add_theme_constant_override("separation", Ui.SPACE["m"])
	var glow := TextureRect.new()
	glow.texture = Ui.glow_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.custom_minimum_size = Vector2(420, 420)
	glow.modulate = Color(tint, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_CENTER)
	add_child(glow)
	if spec.get("art") is Texture2D:
		var plate := MythPlate.new(Vector2(260, 260), 0.0)
		plate.set_texture(spec["art"])
		var pc := CenterContainer.new()
		pc.add_child(plate)
		_card.add_child(pc)
	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", tint)
	title.text = str(spec.get("title", ""))
	_card.add_child(title)
	if str(spec.get("line", "")) != "":
		var line := Label.new()
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(560, 0)
		line.add_theme_color_override("font_color", Ui.c("ink"))
		line.text = str(spec["line"])
		_card.add_child(line)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "press anything to continue"
	_card.add_child(hint)
	add_child(_card)
	_card.modulate.a = 0.0
	_run(major, glow)


func _run(major: bool, glow: TextureRect) -> void:
	# Beat 3's fanfare is the spine: if every visual were stripped, the sound
	# alone must still read as "something significant happened" (MIL §13).
	Sfx.play(str(spec.get("sound", "levelup")))
	if Ui.reduce_motion:
		_veil.color.a = Ui.ALPHA["dim"]
		_card.modulate.a = 1.0
		glow.modulate.a = Ui.ALPHA["glow"]
		await get_tree().create_timer(Ui.TIME["ceremony"]).timeout
		_finish()
		return
	var tw := create_tween()
	# 1 Hush
	if major:
		tw.tween_property(_veil, "color:a", Ui.ALPHA["dim"], Ui.TIME["base"])
	else:
		tw.tween_property(_veil, "color:a", Ui.ALPHA["scrim"] * 0.5, Ui.TIME["fast"])
	# 2 Gather + 3 Strike
	tw.parallel().tween_property(_card, "modulate:a", 1.0, Ui.TIME["base"])
	tw.parallel().tween_property(glow, "modulate:a", Ui.ALPHA["glow"], Ui.TIME["base"])
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2.ONE * Ui.SCALE["enter"]
	tw.parallel().tween_property(_card, "scale", Vector2.ONE * Ui.SCALE["bloom"], Ui.TIME["fast"]) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2.ONE, Ui.TIME["base"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 4 Bestow — the held beat where the player reads what they gained
	tw.tween_interval(Ui.TIME["ceremony"] if major else Ui.TIME["beat"])
	tw.tween_callback(_finish)


## 5 Return — the world comes back. Idempotent: skip and natural end share it.
func _finish() -> void:
	if _done:
		return
	_done = true
	if Ui.reduce_motion:
		finished.emit()
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Ui.TIME["slow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


## Ceremony law: any input completes it immediately.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_finish()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_finish()

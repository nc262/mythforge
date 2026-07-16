class_name MythSocket extends PanelContainer
## MDL: a carved equipment well — ghost glyph when empty, gold-lit with the
## piece's art when filled. Drop target; pulses when a piece lands.

signal dropped(data: Dictionary, slot_key: String)

const Tip := preload("res://ui/myth_tooltip.gd")

var slot_key := ""
var ghost := "◇"
var payload: Dictionary = {}
var _icon: TextureRect
var _glyph: Label


func _init(key := "", ghost_glyph := "◇", size_px := 68) -> void:
	slot_key = key
	ghost = ghost_glyph
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_glyph = Label.new()
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.add_theme_font_size_override("font_size", 24)
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)
	set_item({})


func set_item(p: Dictionary, tex: Texture2D = null) -> void:
	var was_empty := payload.is_empty()
	payload = p
	add_theme_stylebox_override("panel", Ui.sb_socket(not p.is_empty()))
	_icon.texture = tex
	_glyph.visible = tex == null
	if p.is_empty():
		_glyph.text = ghost
		_glyph.modulate = Color(1, 1, 1, 0.22)
	else:
		_glyph.text = str(p.get("glyph", "◆"))
		_glyph.modulate = Color(1, 1, 1, 1)
		if was_empty and is_inside_tree():
			Ui.pulse(self)


func _make_custom_tooltip(_t: String) -> Object:
	if not payload.has("tip_title"):
		return null
	return Tip.build(str(payload["tip_title"]), payload.get("tip_rows", []), str(payload.get("rarity", "")))


func _can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary


func _drop_data(_pos: Vector2, data) -> void:
	dropped.emit(data, slot_key)


func _get_drag_data(_pos: Vector2):
	if payload.is_empty():
		return null
	var ghost_rect := TextureRect.new()
	if _icon.texture != null:
		ghost_rect.texture = _icon.texture
		ghost_rect.custom_minimum_size = custom_minimum_size * 0.9
		ghost_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ghost_rect.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(ghost_rect)
	return payload

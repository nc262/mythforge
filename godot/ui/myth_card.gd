class_name MythCard extends PanelContainer
## MDL: THE card — one face for anything ownable (item, save, world, spell).
## Icon art + rarity halo + qty badge + hover lift + framed tooltip + drag
## source. Screens feed it a payload and listen; it never touches game state.
##   payload keys the card understands:
##     rarity, qty, glyph, tip_title, tip_rows ([[text, role], …]), plus
##     whatever the screen needs back on activate/context/drop.

signal activated(payload: Dictionary)          # double-click
signal context_requested(payload: Dictionary)  # right-click

const Tip := preload("res://ui/myth_tooltip.gd")

var payload: Dictionary = {}
var _icon: TextureRect
var _glyph: Label
var _qty: Label


func _init(size_px := 72) -> void:
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
	_qty = Label.new()
	_qty.theme_type_variation = "HintLabel"
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_qty.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qty)


func setup(p: Dictionary, tex: Texture2D = null) -> void:
	payload = p
	add_theme_stylebox_override("panel", Ui.sb_card(str(p.get("rarity", "common"))))
	_icon.texture = tex
	_glyph.visible = tex == null
	_glyph.text = str(p.get("glyph", "◆"))
	var q := int(p.get("qty", 1))
	_qty.text = str(q) if q > 1 else ""


func _ready() -> void:
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))


func _hover(on: bool) -> void:
	if Ui.reduce_motion:
		return
	pivot_offset = size / 2.0
	z_index = 10 if on else 0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * (1.07 if on else 1.0), Ui.TIME["fast"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and not payload.is_empty():
		if e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(payload)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(payload)


func _make_custom_tooltip(_t: String) -> Object:
	if not payload.has("tip_title"):
		return null
	return Tip.build(str(payload["tip_title"]), payload.get("tip_rows", []), str(payload.get("rarity", "")))


func _get_drag_data(_pos: Vector2):
	if payload.is_empty():
		return null
	var ghost := TextureRect.new()
	if _icon.texture != null:
		ghost.texture = _icon.texture
		ghost.custom_minimum_size = custom_minimum_size * 0.9
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ghost.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(ghost)
	return payload

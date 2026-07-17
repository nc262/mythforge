class_name MythChoiceCard extends Button
## MDL: the large decision card both Forges deal in — glyph or art on top,
## title, body, optional footnote. Selected = legendary gold rim + pulse.
## It IS a Button: focus ring, keyboard activation, and Ui.polish hover
## motion come free. payload keys: glyph, art (Texture2D), title, body, foot.

var payload: Dictionary = {}
var selected := false


func _init(p: Dictionary = {}) -> void:
	payload = p
	custom_minimum_size = Vector2(196, 138)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", Ui.SPACE["xs"])
	if p.get("art") is Texture2D:
		var art := TextureRect.new()
		art.texture = p["art"]
		art.custom_minimum_size = Vector2(0, 56)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(art)
	else:
		# Hand-drawn icon, never a font glyph or emoji (MDL law). Legacy emoji
		# payloads resolve to the matching drawn icon; unknowns get a sigil.
		var ic := MythIcon.new(MythIcon.resolve(str(p.get("glyph", "sigil"))), 34, "gold")
		ic.custom_minimum_size = Vector2(0, 40)
		box.add_child(ic)
	var title_l := Label.new()
	title_l.theme_type_variation = "HeaderLabel"
	title_l.text = str(p.get("title", ""))
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_l)
	if str(p.get("body", "")) != "":
		var body := Label.new()
		body.theme_type_variation = "HintLabel"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(170, 0)
		body.text = str(p.get("body", ""))
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(body)
	if str(p.get("foot", "")) != "":
		var foot := Label.new()
		foot.theme_type_variation = "HintLabel"
		foot.add_theme_color_override("font_color", Ui.c("gold_soft"))
		foot.text = str(p.get("foot", ""))
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(foot)
	add_child(box)
	set_selected(false)


func set_selected(on: bool) -> void:
	selected = on
	var sb := Ui.sb_card("legendary" if on else "common")
	if not on:
		sb.border_color = Ui.c("border")
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", Ui.sb_card("legendary" if on else "uncommon"))
	add_theme_stylebox_override("pressed", sb)
	if on and is_inside_tree():
		Ui.pulse(self)

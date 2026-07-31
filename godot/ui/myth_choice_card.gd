class_name MythChoiceCard extends Button
## MDL: the large decision card both Forges deal in — glyph or art on top,
## title, body, optional footnote. Selected = legendary gold rim + pulse.
## It IS a Button: focus ring, keyboard activation, and Ui.polish hover
## motion come free. payload keys: glyph, art (Texture2D), title, body, foot.

var payload: Dictionary = {}
var selected := false

## UI-3 — THE CARD GROWS TO HOLD ITS TEXT.
##
## 196x138 was a hard size and the content box is anchored FULL_RECT, so a body
## that wrapped to three or four lines simply overflowed and was cut off. An
## anchored child never reports a minimum upward, which is why nothing complained.
##
## The height has to be MEASURED and written into `custom_minimum_size`. Two
## things make that the only route: an autowrapping Label reports its minimum
## from its CURRENT width, which before layout is one line; and this card is a
## Button, whose native get_minimum_size() never consults a script's
## `_get_minimum_size()` — a virtual here is dead code that looks like a fix.
const BODY_W := 170.0
const FLOOR_H := 138.0


## Body height at the width the body will actually get, or 0 if there is none.
static func _body_overflow(text: String) -> float:
	if text.strip_edges() == "":
		return 0.0
	var fnt: Font = Ui.sans
	if fnt == null:
		return 0.0
	var fsz := 13
	var wrapped: Vector2 = fnt.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, BODY_W, fsz)
	# One line already fits inside the floor; only what spills past it counts.
	return maxf(0.0, wrapped.y - float(fsz) * 1.4)


func _init(p: Dictionary = {}) -> void:
	payload = p
	custom_minimum_size = Vector2(196, FLOOR_H + _body_overflow(str(p.get("body", ""))))
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

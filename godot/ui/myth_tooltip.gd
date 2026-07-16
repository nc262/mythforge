class_name MythTooltip extends PanelContainer
## MDL: the ONLY tooltip in the game (docs/DesignSystem.md §4).
## rows: Array of [text] or [text, color_role] — comparison rows use
## "gold"/"danger" roles with ▲/▼ in their text.


static func build(title: String, rows: Array = [], rarity := "") -> Control:
	var tip := PanelContainer.new()
	tip.theme = Ui.theme
	tip.add_theme_stylebox_override("panel", Ui._nine(Ui.ornate_frame_tex(Ui.c("night2"), Ui.c("gold")), 10, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Ui.SPACE["xs"])
	var t := Label.new()
	t.theme_type_variation = "HeaderLabel"
	t.text = title
	if rarity != "":
		t.add_theme_color_override("font_color", Ui.rarity_color(rarity))
	box.add_child(t)
	for r in rows:
		var l := Label.new()
		l.text = str(r[0])
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Ui.c(str(r[1])) if r.size() > 1 else Ui.c("ink_soft"))
		box.add_child(l)
	tip.add_child(box)
	return tip

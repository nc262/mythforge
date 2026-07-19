extends Node
## Renders the real action-bar BBCode (Ui.ico inline art) to a PNG so the inline
## [img] rendering can be eyeballed. Windowed run; writes to user://icon_preview.png.
const W := 900
const H := 220


func _ready() -> void:
	Ui.apply("")
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Ui.c("night")
	bg.size = Vector2(W, H)
	vp.add_child(bg)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size = Vector2(W - 40, H - 40)
	rt.position = Vector2(20, 20)
	rt.add_theme_color_override("default_color", Ui.c("ink"))
	rt.add_theme_font_size_override("normal_font_size", 20)
	var bar := func(glyph: String, label: String) -> String:
		return "%s %s" % [Ui.ico(glyph, 18), label]
	rt.append_text("  ".join([bar.call("tune", "tune the GM"), bar.call("save", "save chapter"),
		bar.call("scroll", "chronicle"), bar.call("compass", "atlas"),
		bar.call("star", "destiny"), bar.call("shield", "record")]))
	rt.append_text("\n\n")
	# every baked glyph, so the whole set can be judged at a glance
	var strip := ""
	for nm in MythIcon.NAMES:
		strip += Ui.ico(nm, 30) + " "
	rt.append_text(strip)
	vp.add_child(rt)
	add_child(vp)
	for i in 6:
		await RenderingServer.frame_post_draw
	var err := vp.get_texture().get_image().save_png("user://icon_preview.png")
	print("PREVIEW: %s -> %s" % [err, ProjectSettings.globalize_path("user://icon_preview.png")])
	get_tree().quit(0)

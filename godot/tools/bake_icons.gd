extends Node
## One-time asset bake: render every MythIcon glyph to a white-master PNG under
## res://ui/icons/glyph/ so it can be used as inline [img] art in RichText and as
## Button/PopupMenu .icon textures — the same hand-drawn art, no emoji ever shown.
## Run WINDOWED (needs the GPU; --headless's dummy driver renders blank):
##   Godot_v4.7 --path godot res://tools/bake_icons.tscn
const SIZE := 96
const OUT := "res://ui/icons/glyph/"


func _ready() -> void:
	Ui.apply("")  # canonical palette (white master is palette-independent anyway)
	DirAccess.make_dir_recursive_absolute(OUT)
	var n := 0
	for nm in MythIcon.NAMES:
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE, SIZE)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var ic := MythIcon.new(nm, SIZE, "bake")
		ic.size = Vector2(SIZE, SIZE)
		ic.queue_redraw()
		vp.add_child(ic)
		add_child(vp)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var err := img.save_png(OUT + nm + ".png")
		if err == OK:
			n += 1
		vp.queue_free()
	print("BAKE: wrote %d/%d icons to %s" % [n, MythIcon.NAMES.size(), OUT])
	get_tree().quit(0)

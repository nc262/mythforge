class_name MythPlate extends PanelContainer
## MDL: the ONE way generated art ships in the UI (UIPolish phase 6) — a
## forge-bordered plate, cover-fit, palette-graded toward the skin's accent,
## its backdrop faded into the panel base. Never a raw hard-edged AI image.
## Feed it a texture, or bind an Art key to repaint live when the paint lands.

var _tr: TextureRect
var _key := ""


func _init(plate_size := Vector2(230, 336), fade := 0.85) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Ui.c("night"), 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color(Ui.c("gold"), 0.35)
	sb.set_corner_radius_all(Ui.RADIUS["m"])
	sb.set_content_margin_all(3)
	add_theme_stylebox_override("panel", sb)
	var holder := Control.new()
	holder.custom_minimum_size = plate_size
	holder.clip_contents = true
	_tr = TextureRect.new()
	_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tr.self_modulate = Ui.c("gold").lerp(Color.WHITE, 0.8)  # grade toward the skin accent
	holder.add_child(_tr)
	if fade > 0.0:
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(Ui.c("night"), 0.0), Color(Ui.c("night"), fade)])
		grad.offsets = PackedFloat32Array([0.6, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		var scrim := TextureRect.new()
		scrim.texture = gt
		scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(scrim)
	add_child(holder)


func set_texture(tex: Texture2D) -> void:
	_tr.texture = tex


## Live-bound: shows the key's painting now (or a stand-in) and repaints when
## the commission lands. Connection auto-drops when the plate frees.
func bind_key(key: String, fallback: Texture2D = null) -> void:
	_key = key
	_tr.texture = Art.texture_for(key) if Art.has_art(key) else fallback
	Art.art_ready.connect(func(k):
		if str(k) == _key and is_instance_valid(_tr):
			_tr.texture = Art.texture_for(_key)
			Ui.pulse(_tr))

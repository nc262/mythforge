class_name MythPlate extends PanelContainer
## MDL: the ONE way generated art ships in the UI (UIPolish phase 6) — a
## forge-bordered plate, cover-fit, palette-graded toward the skin's accent,
## its backdrop faded into the panel base. Never a raw hard-edged AI image.
## Feed it a texture, or bind an Art key to repaint live when the paint lands.

var _tr: TextureRect
var _key := ""
var _ghost: VBoxContainer = null   # the "nothing here yet" state (R6 BLANK-03)


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
	# R6 BLANK-03 — an unpainted plate was a bordered VOID, which is how the Gear
	# tab's paper doll read: a dead black box beside a "Re-render" button, with
	# nothing to say whether art was coming, missing, or broken. The commission
	# can take ~25 s; silence for 25 s is indistinguishable from failure. Every
	# plate in the game now carries its own empty state, so this is fixed
	# wherever MythPlate is used, not just on the doll.
	_ghost = VBoxContainer.new()
	_ghost.alignment = BoxContainer.ALIGNMENT_CENTER
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Label.new()
	mark.text = "◈"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 40)
	mark.add_theme_color_override("font_color", Color(Ui.c("gold"), 0.30))
	var say := Label.new()
	say.name = "Say"
	say.theme_type_variation = "HintLabel"
	say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.text = "not painted yet"
	_ghost.add_child(mark)
	_ghost.add_child(say)
	holder.add_child(_ghost)
	add_child(holder)
	_sync_ghost()


func set_texture(tex: Texture2D) -> void:
	_tr.texture = tex
	_sync_ghost()


## The empty state shows only while there is genuinely nothing to look at.
func _sync_ghost(note := "") -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	_ghost.visible = _tr.texture == null
	if note != "":
		var say: Label = _ghost.get_node_or_null("Say")
		if say != null:
			say.text = note


## Live-bound: shows the key's painting now (or a stand-in) and repaints when
## the commission lands. Connection auto-drops when the plate frees.
func bind_key(key: String, fallback: Texture2D = null) -> void:
	_key = key
	_tr.texture = Art.texture_for(key) if Art.has_art(key) else fallback
	_sync_ghost()
	Art.art_ready.connect(func(k):
		if str(k) == _key and is_instance_valid(_tr):
			_tr.texture = Art.texture_for(_key)
			_sync_ghost()
			Ui.pulse(_tr))
	# Narrate the commission, so a long paint reads as work rather than a hang.
	Art.art_progress.connect(func(k, state):
		if str(k) != _key or not is_instance_valid(_tr):
			return
		var st := str(state)
		if st == "queued":
			_sync_ghost("waiting for the forge…")
		elif st == "painting":
			_sync_ghost("the forge paints…")
		elif st == "failed" or st == "cancelled":
			_sync_ghost("not painted — try Re-render"))

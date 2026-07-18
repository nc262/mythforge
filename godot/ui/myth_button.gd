class_name MythButton extends Button
## MDL: the handcrafted control — never a software widget. A plate of real
## material (carved oak / forged steel / aged leather / polished brass),
## an icon from the Mythforge Icon Library, and typography ENGRAVED into
## the surface (dark glyphs, a light kiss beneath). Hover raises the light
## across the plate; press seats it. No default Godot chrome survives.

const Icon := preload("res://ui/myth_icon.gd")

var plate := "oak"
var _light: TextureRect


func _init(label := "", icon_name := "", mat := "oak", subtitle := "") -> void:
	plate = mat
	custom_minimum_size = Vector2(430, 62)
	add_theme_stylebox_override("normal", Ui.material_sb(mat, 0.0))
	add_theme_stylebox_override("hover", Ui.material_sb(mat, 0.07))
	add_theme_stylebox_override("pressed", Ui.material_sb(mat, -0.08))
	add_theme_stylebox_override("focus", Ui._flat(Color(0, 0, 0, 0), Ui.c("amethyst"), Ui.RADIUS["s"], 1, 0))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["m"])
	if icon_name != "":
		var ic := Icon.new(icon_name, 30, "gold")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	var lab := Label.new()
	lab.name = "Engraving"
	lab.text = label
	lab.add_theme_font_override("font", Ui.display)
	lab.add_theme_font_size_override("font_size", 19)
	# Raised metal lettering: warm cream glyphs, a hard dark outline so they stay
	# crisp on ANY plate (the old dark-on-dark engraving was hard to read), and a
	# soft drop-shadow for depth.
	lab.add_theme_color_override("font_color", Color(0.97, 0.92, 0.80))
	lab.add_theme_color_override("font_outline_color", Color(Ui.c("night"), 0.92))
	lab.add_theme_constant_override("outline_size", 5)
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	lab.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(lab)
	if subtitle != "":
		var sub := Label.new()
		sub.name = "Sub"
		sub.text = subtitle
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74, 0.9))
		sub.add_theme_color_override("font_outline_color", Color(Ui.c("night"), 0.85))
		sub.add_theme_constant_override("outline_size", 3)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
	row.add_child(col)
	add_child(row)
	# The hover light: a warm sheen that wakes across the plate.
	_light = TextureRect.new()
	_light.texture = Ui.glow_tex()
	_light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_light.set_anchors_preset(Control.PRESET_FULL_RECT)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.modulate = Color(Ui.c("gold_soft"), 0.0)
	add_child(_light)
	mouse_entered.connect(func(): _sheen(0.22))
	mouse_exited.connect(func(): _sheen(0.0))
	button_down.connect(func(): _sheen(0.05))
	button_up.connect(func(): _sheen(0.22))


func set_engraving(text2: String) -> void:
	var lab := find_child("Engraving", true, false)
	if lab != null:
		lab.text = text2


func set_subtitle(text2: String) -> void:
	var sub := find_child("Sub", true, false)
	if sub != null:
		sub.text = text2


func _sheen(to: float) -> void:
	if Ui.reduce_motion:
		_light.modulate.a = to
		return
	create_tween().tween_property(_light, "modulate:a", to, Ui.TIME["fast"])

class_name MythHeader extends HBoxContainer
## MDL: ──── ✦ SECTION ✦ ──── — the one section header every screen uses.


func _init(text := "") -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", Ui.SPACE["s"])
	_wing()
	var lab := Label.new()
	lab.theme_type_variation = "HeaderLabel"
	lab.text = "✦  %s  ✦" % text.to_upper()
	add_child(lab)
	_wing()


func _wing() -> void:
	var line := ColorRect.new()
	line.color = Color(Ui.c("gold"), 0.4)
	line.custom_minimum_size = Vector2(34, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(line)

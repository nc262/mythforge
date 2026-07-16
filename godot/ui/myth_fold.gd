class_name MythFold extends VBoxContainer
## MDL: a collapsible section — hide complexity until wanted. Gilded ▸/▾
## header button; the content reveals when unfolded.

var content: VBoxContainer
var _btn: Button
var _title := ""


func _init(title := "", open := false) -> void:
	_title = title
	_btn = Button.new()
	_btn.theme_type_variation = "GhostButton"
	_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_btn.text = ("▾  " if open else "▸  ") + title
	add_child(_btn)
	content = VBoxContainer.new()
	content.visible = open
	content.add_theme_constant_override("separation", Ui.SPACE["xs"])
	add_child(content)
	_btn.pressed.connect(_toggle)


func _toggle() -> void:
	content.visible = not content.visible
	_btn.text = ("▾  " if content.visible else "▸  ") + _title
	if content.visible:
		Ui.reveal(content)

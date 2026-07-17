class_name MythForgeStep extends HBoxContainer
## MDL: one step of a long forging — ○ waiting · ⏳ striking · ✅ sealed —
## with a note and an artifact strip (faces, chips) that fills as things
## land. Reusable for any staged generation (campaign forging, art warmup).

var artifacts: HBoxContainer
var _state_l: Label
var _title_l: Label
var _note_l: Label


func _init(title := "") -> void:
	add_theme_constant_override("separation", Ui.SPACE["s"])
	_state_l = Label.new()
	_state_l.text = "○"
	_state_l.add_theme_color_override("font_color", Ui.c("ink_dim"))
	_state_l.custom_minimum_size = Vector2(26, 0)
	add_child(_state_l)
	_title_l = Label.new()
	_title_l.theme_type_variation = "HeaderLabel"
	_title_l.text = title
	add_child(_title_l)
	_note_l = Label.new()
	_note_l.theme_type_variation = "HintLabel"
	add_child(_note_l)
	artifacts = HBoxContainer.new()
	artifacts.add_theme_constant_override("separation", Ui.SPACE["xs"])
	add_child(artifacts)


## state: "wait" | "work" | "done" | "fail"
func set_state(state: String, note := "") -> void:
	_note_l.text = note
	if state == "work":
		_state_l.text = "⏳"
		_state_l.add_theme_color_override("font_color", Ui.c("gold_soft"))
	elif state == "done":
		_state_l.text = "✅"
		_state_l.add_theme_color_override("font_color", Ui.c("gold"))
		if is_inside_tree():
			Ui.pulse(self)
			Sfx.play("chime")
	elif state == "fail":
		_state_l.text = "✕"
		_state_l.add_theme_color_override("font_color", Ui.c("danger"))
	else:
		_state_l.text = "○"
		_state_l.add_theme_color_override("font_color", Ui.c("ink_dim"))

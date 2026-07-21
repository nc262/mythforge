extends ConfirmationDialog
## The GM's tone knobs — one dialog serves both Session Zero (the first
## arrival) and mid-tale retuning. Extracted from game.gd (A0 split). The
## tuner persists the knobs itself (GameState is an autoload); the play
## screen hears tuned(knobs) and owns what happens next — the session-zero
## opening stream, or the quiet "tone shifts" note.

signal tuned(knobs: Dictionary)

const KNOBS := [
	["humor", "Humor", "Serious", "Comedic", 40],
	["spice", "Romance & spice", "None", "Bold", 0],
	["grit", "Grit & danger", "Gentle", "Brutal", 50],
	["pace", "Pace", "Slow", "Fast", 55],
	["rules", "Rules", "Loose", "Strict 5e", 50],
]

var initial: Dictionary = {}   # current gm knobs (retune) or {} for defaults
var session_zero := false      # first arrival: no cancel, bigger send-off

var _sliders := {}


func _ready() -> void:
	title = "Session Zero — set the tone" if session_zero else "Tune the GM"
	ok_button_text = "Begin the adventure ›" if session_zero else "So be it"
	if session_zero:
		get_cancel_button().visible = false
		min_size = Vector2i(460, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for k in KNOBS:
		var row := Label.new()
		row.theme_type_variation = "HintLabel"
		row.text = "%s   %s ↔ %s" % [k[1], k[2], k[3]]
		box.add_child(row)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int(initial.get(k[0], k[4]))
		sl.custom_minimum_size = Vector2(400, 0)
		box.add_child(sl)
		_sliders[k[0]] = sl
	add_child(box)
	confirmed.connect(func():
		var out := {}
		for key in _sliders:
			out[key] = int(_sliders[key].value)
		GameState.save_kind("gm", out)
		tuned.emit(out)
		queue_free())

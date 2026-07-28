class_name MythForgeWait extends VBoxContainer
## The forge's long wait, made honest (UXAudit R6 LAT-10, Round-5 VIS-09).
##
## Forging a world is SIX sequential LLM calls — the world's core, its places,
## its people, its campaigns, its beasts, its tongue — and on a local model that
## is two to three minutes. The player was given one static grey line for all of
## it ("The smith works — the world takes shape (about a minute)…"), which was
## both the least information in the game and, at "about a minute", wrong.
##
## Two rules this obeys, because the alternative is a lie:
##   · It never claims to KNOW which call is running. The backend does all six
##     inside one request and reports nothing until the end, so a progress bar
##     here would be invented. Instead the smith NARRATES the work in the order
##     it genuinely happens, which is true whether or not the timing lines up.
##   · It shows real elapsed seconds. Past the point where a player starts to
##     wonder, a ticking number is the difference between waiting and worrying —
##     the same lesson MythThinking learned for the narration wait.

## The worldsmith's actual call order (routes/character_studio_routes.py):
## core → life (cast/stories/creatures) → stories retry → beasts → reskins.
const BEATS := [
	["the world takes its name", 0.0],
	["its coasts and roads are drawn", 22.0],
	["its people are gathered", 52.0],
	["its campaigns are written", 86.0],
	["its beasts are bred", 116.0],
	["its tongue is set — the classes take world names", 146.0],
]
## Past this, say plainly that slow is not broken.
const PATIENCE := 175.0

var _line: Label
var _sub: Label
var _quill: MythIcon
var _t := 0.0
var _idx := -1


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", Ui.SPACE["s"])


func _ready() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	_quill = MythIcon.new("hammer", 22, "gold_soft")
	_quill.custom_minimum_size = Vector2(24, 24)
	row.add_child(_quill)
	_line = Label.new()
	_line.add_theme_color_override("font_color", Ui.c("gold_soft"))
	row.add_child(_line)
	add_child(row)
	_sub = Label.new()
	_sub.theme_type_variation = "HintLabel"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(520, 0)
	add_child(_sub)
	_advance(0)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# The hammer falls, paced to the breath token (still under reduce_motion).
	if not Ui.reduce_motion and is_instance_valid(_quill):
		_quill.position.y = absf(sin(_t / float(Ui.TIME["breath"]) * TAU)) * -3.0
	var want := 0
	for i in BEATS.size():
		if _t >= float(BEATS[i][1]):
			want = i
	if want != _idx:
		_advance(want)
	if is_instance_valid(_sub):
		var note := "Six passes of the smith's hammer — two to three minutes on a local model."
		if _t > PATIENCE:
			note = "Longer than usual, but still working — a local mind takes its time."
		_sub.text = "%s   ·   %ds" % [note, int(_t)]


func _advance(i: int) -> void:
	_idx = i
	if is_instance_valid(_line):
		_line.text = "%d of %d — %s…" % [i + 1, BEATS.size(), str(BEATS[i][0])]
		Ui.pulse(_line)

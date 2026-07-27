class_name MythThinking extends HBoxContainer
## MIL §7 Tier 3 — "the GM is thinking". The most-seen wait in the game.
##
## A local model can take many seconds to produce its first token. Unmasked,
## that reads as a hang; dressed as a Game Master composing, the same seconds
## read as care. So: a quill drawing its stroke, a breathing ink line, and a
## status line in the WORLD'S OWN VOICE — never "Loading", never a spinner.
##
## Under reduce_motion the quill stops moving but the words keep rotating —
## the information survives, only the movement goes (MIL §16).

## World-specific waiting copy, keyed to the active WorldSkin family. The wait
## belongs to the fiction, so the fiction speaks during it.
const LINES := {
	"fantasy": ["Consulting the Chronicle…", "The quill moves…", "Candles gutter as the tale turns…"],
	"cyber": ["Querying the net…", "Decrypting the next frame…", "The city answers…"],
	"everyday": ["Thinking it over…", "Turning the page…", "Finding the words…"],
	"space": ["Charting the next jump…", "Long-range scan resolving…", "The dark between stars answers…"],
	"steam": ["The difference engine turns…", "Steam builds…", "Gears find their teeth…"],
	"pirate": ["Reading the wind…", "The log fills…", "Charting by dead reckoning…"],
	"horror": ["Something considers you…", "The dark deliberates…", "The house decides…"],
	"norse": ["The threads are spun…", "The saga gathers…", "The Norns confer…"],
}
## Past this, reassure: a slow local mind is not a broken one.
const PATIENCE := 20.0

var _quill: MythIcon
var _label: Label
var _lines: Array = []
var _t := 0.0
var _idx := 0


func _init() -> void:
	add_theme_constant_override("separation", Ui.SPACE["s"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var fam := WorldSkin.family_for_id(GameState.world_id())
	_lines = LINES.get(fam, LINES["fantasy"])
	_quill = MythIcon.new("quill", 22, "gold_soft")
	_quill.custom_minimum_size = Vector2(24, 24)
	add_child(_quill)
	_label = Label.new()
	_label.theme_type_variation = "HintLabel"
	_label.text = str(_lines[0])
	add_child(_label)
	Ui.breathe(_label)          # the line lives, even when still
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# The quill draws: a small figure-of-eight, paced to the breath token.
	if not Ui.reduce_motion and is_instance_valid(_quill):
		var p := _t / float(Ui.TIME["breath"]) * TAU
		_quill.position = Vector2(sin(p) * 3.0, sin(p * 2.0) * 1.6)
	if not is_instance_valid(_label):
		return
	# The world speaks, and keeps speaking, so the pause never feels dead.
	var want := int(_t / float(Ui.DELAY["status_cycle"])) % _lines.size()
	if want != _idx:
		_idx = want
		_label.text = str(_lines[_idx])
	# R6 LAT-08, the half of it that was real. The wait is already dressed (a
	# drawing quill, the world's own rotating voice), but past the patience
	# threshold "still working" and "wedged" look identical, and on this hardware
	# a turn can genuinely run a minute. A ticking count is the difference between
	# waiting and wondering — and it costs nothing.
	if _t > PATIENCE:
		_label.text = "Still composing — the local mind is slow tonight, but it is working.  (%ds)" % int(_t)

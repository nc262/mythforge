extends Node
## Wall-clock per GM turn on the local narrator — the thing a player feels.
## Turn 1 pays the model load; turns 2+ are the steady state.
var _acc := ""
var _t0 := 0
var _n := 0
var _openings: Array = []
const TURNS := 3
const LINES := ["I step out of the cottage and look toward the mountains.",
	"I ask Mira what she knows about the new path.",
	"I shoulder my pack and set off up the valley."]

func _ready() -> void:
	await get_tree().process_frame
	GameState.character = {"id": "dm-embervale-freeroam", "world_id": "embervale"}
	GameState.state = GameState.state_for("dm-embervale-freeroam")
	if not LocalGM.available():
		print("unavailable: ", LocalGM.why_unavailable()); get_tree().quit(); return
	Api.sse_delta.connect(func(t): _acc += t)
	Api.sse_done.connect(_done)
	_go()

func _go() -> void:
	_acc = ""
	var env := Composer.envelope(LINES[_n])
	if _n == 0:
		print("envelope %d chars + system %d chars" % [env.length(), Composer.system_prompt().length()])
	_t0 = Time.get_ticks_msec()
	LocalGM.stream(env, Composer.system_prompt())

func _done(_ok: bool) -> void:
	var s := (Time.get_ticks_msec() - _t0) / 1000.0
	print("turn %d: %5.1fs  %4d chars%s" % [_n + 1, s, _acc.length(),
		"   (includes model load)" if _n == 0 else ""])
	print("   \"%s…\"" % _acc.strip_edges().replace("\n", " ").left(90))
	_openings.append(_acc)
	# RECORD IT, so the next turn's envelope can tell the GM what it just wrote.
	# Without this the bench measured a narrator that never sees its own prose,
	# which is the exact condition that produced "the smell of bread" in every
	# response of a real playthrough.
	Chronicle.record(LINES[_n], _acc)
	_n += 1
	if _n < TURNS:
		_go()
	else:
		_report_repetition("this run")
		get_tree().quit()


## The atmosphere words a GM reaches for when it opens by setting a mood instead
## of by moving the story. This is the ACTUAL complaint from the playtest — "the
## smell of bread and the lighting in the room, every response".
const ATMOSPHERE := ["air", "sun", "dim", "fog", "mist", "damp",
	"light", "lights", "glow", "glows", "glowing", "sunlight",
	"sunset", "dusk", "twilight", "shadow", "shadows", "warm", "warmth", "amber",
	"golden", "smell", "smells", "scent", "aroma", "air", "breeze", "flicker",
	"flickering", "candles", "candlelight", "haze", "dim", "gloom"]


## Does this reply OPEN by setting a mood? First clause only — atmosphere later
## in a paragraph is good writing; atmosphere in the first breath, every single
## turn, is the tic.
func _opens_on_atmosphere(s: String) -> bool:
	var head := s.strip_edges().replace("\n", " ")
	var cut := head.find(",")
	if cut > 0:
		head = head.left(cut)
	head = head.left(90)
	# Tokenised HERE rather than through _words(), which drops anything under four
	# characters — that quietly excluded "air", "sun" and "dim", and "the smell of
	# bread in the air" is the exact sentence this is meant to catch.
	for raw in head.to_lower().split(" ", false):
		if ATMOSPHERE.has(raw.strip_edges().lstrip("\"'([*—-").rstrip("\"'.,;:!?)]*—-")):
			return true
	return false


## How much each turn reuses the previous turn's words.
##
## KEPT, BUT NOT TRUSTED ALONE. It reported 19% and "OK" on three consecutive
## replies that all opened on sunset — because "warm glow" and "the last rays of
## sunlight" share no vocabulary at all. Recurring imagery survives paraphrase,
## so the atmosphere-opening count above is the number that matches the
## complaint, and this one is context.
func _report_repetition(label: String) -> float:
	var worst := 0.0
	for i in range(1, _openings.size()):
		var a := _words(_openings[i - 1])
		var b := _words(_openings[i])
		if a.is_empty() or b.is_empty():
			continue
		var shared := 0
		for w in b:
			if a.has(w):
				shared += 1
		var overlap := float(shared) / float(b.size())
		worst = maxf(worst, overlap)
		print("   turn %d reuses %.0f%% of turn %d's vocabulary" % [i + 1, overlap * 100.0, i])
	var moody := 0
	for o in _openings:
		if _opens_on_atmosphere(o):
			moody += 1
	print("REPETITION %s: vocabulary worst=%.0f%% | opens on atmosphere %d/%d %s"
		% [label, worst * 100.0, moody, _openings.size(),
			"" if moody < _openings.size() else "  <- every single turn"])
	# The atmosphere count is the score; vocabulary overlap is printed for
	# context and deliberately NOT what the verdict turns on.
	return float(moody) / float(maxi(1, _openings.size()))


## Content words only: the shared scaffolding of English tells us nothing about
## whether two descriptions are the same description.
const STOP := ["the", "a", "an", "and", "of", "to", "in", "on", "at", "is", "as",
	"it", "its", "you", "your", "with", "for", "from", "into", "that", "this",
	"but", "or", "by", "be", "are", "was", "were", "has", "have", "not", "all"]

func _words(s: String) -> Array:
	var out: Array = []
	for w in s.to_lower().replace("\n", " ").split(" ", false):
		var t := w.strip_edges().lstrip("\"'([*—-").rstrip("\"'.,;:!?)]*—-")
		if t.length() > 3 and not STOP.has(t) and not out.has(t):
			out.append(t)
	return out

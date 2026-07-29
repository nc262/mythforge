extends Node
## Wall-clock per GM turn on the local narrator — the thing a player feels.
## Turn 1 pays the model load; turns 2+ are the steady state.
var _acc := ""
var _t0 := 0
var _n := 0
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
	_n += 1
	if _n < TURNS:
		_go()
	else:
		get_tree().quit()

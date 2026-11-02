extends Node
## PY-8. Drives the REAL art pipeline against the REAL engine, headless, and says
## exactly where a commission dies.
##
## This exists because `local_stack` — the only harness that touches the GPU —
## never exercises art at all, which is how "Envision this hero" stayed inert:
## the engine burned 16 s of CPU, no PNG landed, and nothing anywhere said a word.
##
##   godot --headless --path godot res://tests/art_probe.tscn
##
## It reports the state machine at every step rather than a pass/fail, because
## the question is WHERE it stops, not WHETHER it works.

## NOT "heroprev". Running against the forge's live scratch key was how PY-8 was
## measured (it behaves identically, 20.6 s, PNG written) but a harness that
## overwrites the key the next forging reads is a harness that plants a bug.
const KEY := "probe-envision"
const PROMPT := "character portrait of a hero, a Tiefling Warlock, lean with dark horns and a red coat, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face"

var _t0 := 0
var _events: Array = []


func _ready() -> void:
	await get_tree().process_frame
	GameState.character = {"id": "dm-art-probe", "world_id": "embervale"}
	Art.forget(KEY)   # exactly what the Envision button does first

	Art.art_progress.connect(_on_progress)
	Art.art_ready.connect(_on_ready)

	print("probe: engine reachable? ", await _engine_up())
	print("probe: Art.hold = ", Art.hold, "   (a true here stalls the pump for up to %.0f s)" % Art.HOLD_MAX)
	print("probe: status before = '%s', has_art = %s" % [Art.status(KEY), Art.has_art(KEY)])

	_t0 = Time.get_ticks_msec()
	Art.ensure(KEY, PROMPT)
	print("probe: ensure() returned; status now = '%s'" % Art.status(KEY))

	# Poll the STATE, not just the file — a commission that never dispatches and
	# one that dispatches and is thrown away look identical from the outside.
	var deadline := _t0 + 180 * 1000
	while Time.get_ticks_msec() < deadline:
		if Art.has_art(KEY):
			break
		await get_tree().create_timer(2.0).timeout
	var el := (Time.get_ticks_msec() - _t0) / 1000.0

	print("")
	print("probe: ---- events ----")
	for e in _events:
		print("probe:   ", e)
	print("probe: ---- result ----")
	print("probe: elapsed        %.1f s" % el)
	print("probe: has_art        %s" % Art.has_art(KEY))
	print("probe: status         '%s'" % Art.status(KEY))
	print("probe: pending        %d" % Art.pending())
	print("probe: file           %s" % (Art.path_for(KEY) if Art.has_art(KEY) else "(none written)"))
	if Art.has_art(KEY):
		print("ART-PROBE OK")
	else:
		print("ART-PROBE STALLED — no PNG after %.1f s; the events above say how far it got" % el)
	get_tree().quit(0 if Art.has_art(KEY) else 1)


func _on_progress(key: String, state: String) -> void:
	if key == KEY:
		_events.append("%6.1fs  progress: %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, state])


func _on_ready(key: String) -> void:
	if key == KEY:
		_events.append("%6.1fs  art_ready" % ((Time.get_ticks_msec() - _t0) / 1000.0))


## Is anything actually listening on the image port? A stalled probe means a very
## different thing with no engine than with one.
func _engine_up() -> bool:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 3.0
	if req.request(Art.IMAGE_SERVER + "/v1/models") != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return int(res[1]) == 200

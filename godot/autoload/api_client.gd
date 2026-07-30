extends Node
## Api — the narrator's signal surface, and the switch that makes the harnesses
## deterministic. Not a client: there is no server, and nothing here opens a
## socket. The name survives because every scene already listens to these
## signals, and renaming a seam is not a change.

## Local settings: the chosen narrator, UI prefs. A ConfigFile in user://.
const SETTINGS_FILE := "user://session.cfg"

signal sse_delta(text: String)
signal sse_event(data: Dictionary)
signal sse_done(ok: bool)
## The narrator could not speak because the local model is missing. There is no
## second path by design, so this must surface to the player instead of failing
## quietly — carries the reason from LocalGM.why_unavailable().
signal narrator_missing(reason: String)


## Harness hook (tests/ui_playthrough, tests/click_driver). With test_mode on,
## no model is ever loaded: stream_chat replays scripted GM turns through the
## REAL tag pipeline, art resolves to nothing, and saves go to their own drawer.
## The shipped scenes run headless, unchanged.
var test_mode := false
var test_replies: Array = []  # queue of GM reply strings for stream_chat


## The Worldsmith. Kept here as the entry point so all four call sites read the
## same; the work is in autoload/worldsmith.gd.
func worldsmith(payload: Dictionary) -> Dictionary:
	if test_mode:
		return {}
	return await Worldsmith.forge(payload)


## Stop the narrator mid-sentence. The player leaving the table must not have to
## wait out a reply they've already walked away from; the tale is saved
## continuously, so an abandoned turn costs nothing.
func cancel_stream() -> void:
	LocalGM.stop()


## Stream one GM turn. Emits sse_delta per token batch, sse_event for structured
## side-effects, then sse_done exactly once.
##
## `message` is the full per-turn envelope and `system_prompt()` the GM's
## framing; both are built by the same `compose_world_gm` the forges call, so the
## table and the forge cannot drift apart.
func stream_chat(message: String) -> void:
	if test_mode:
		var reply := str(test_replies.pop_front()) if not test_replies.is_empty() else "The quiet holds a moment longer."
		await get_tree().process_frame
		await get_tree().process_frame
		sse_delta.emit(reply)  # one batch — the game's language gate + tag pipeline run for real
		await get_tree().process_frame
		sse_done.emit(true)
		return
	if LocalGM.stream(message, Composer.system_prompt()):
		return
	# Only reachable if the model is absent or a turn is already in flight. A
	# game ships its assets and requires them; a missing narrator is a plain,
	# honest failure, not a silent degradation into something quieter.
	var why := LocalGM.why_unavailable()
	if why != "":
		push_error("Narrator unavailable: %s" % why)
		narrator_missing.emit(why)
	sse_done.emit(false)

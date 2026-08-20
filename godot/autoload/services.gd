extends Node
## Services — the image engine's whole life, owned by the game.
##
## Mythforge runs its own language model in-process, so the exe is very nearly
## the whole app. The one other process is stable-diffusion.cpp on :8189, and
## art is decoration — the Hall opens off the save shelf on disk whether or not
## it ever answers. This used to say "no supervisor", and that was true only
## because something OUTSIDE the game was starting the engine: the Start-Menu
## launcher, or a pm2 app doing the same job twice. Double-click the exe itself
## and nothing started it and nothing stopped it.
##
## So the exe now supervises it, and the rules are the interesting part:
##
##   ADOPT, NEVER SEIZE. If :8189 already answers, someone else owns that
##   process — the launcher, another copy of the game, a developer with a pour
##   server. We use it and we do not touch it on the way out.
##   STOP ONLY WHAT WE STARTED. `_engine_pid` is set from the pid file the
##   launcher script writes, and ONLY on the path that actually spawned
##   something. No pid, no kill.
##   NEVER BLOCK THE GAME. The engine takes ~25 s to read a 6.5 GB checkpoint.
##   Spawning is fire-and-forget and the Hall opens immediately.
##
## IN-PROCESS WAS CONSIDERED AND REJECTED, with numbers. llama.cpp fixes its
## GPU/CPU split once at load time, so a resident image stack costs 19.3 s per
## narrator turn against 3.7 s with a clear card — five times slower on every
## turn, to save the few milliseconds an HTTP POST costs against a ~20 s
## generation. sd-server idles at ~118 MB precisely BECAUSE it is separate and
## loads per request, and stable-diffusion.cpp ships as a server binary with no
## library form, so in-process would mean authoring a GDExtension for it. The
## separation is also what keeps an image crash from taking the session down.

signal art_ready

var _up := false
## The engine WE spawned. -1 means we did not start one — either it was already
## answering when we looked, or it never came up. Only ever kill this.
var _engine_pid := -1
## `_shutdown()` is reachable from three different notifications and must not
## run twice; the first one to arrive wins.
var _stopped := false


## Fire-and-forget from the menu. Never blocks a screen: callers do not await.
func warm_art(max_seconds := 60.0) -> bool:
	if _up:
		art_ready.emit()
		return true
	var waited := 0.0
	while waited < max_seconds:
		if await _probe():
			_up = true
			art_ready.emit()
			return true
		await get_tree().create_timer(3.0).timeout
		waited += 3.0
	return false


func _probe() -> bool:
	if Api.test_mode:
		return false
	var req := HTTPRequest.new()
	# A TIMEOUT, or this never returns. HTTPRequest.timeout defaults to 0, which
	# means "wait for ever" — so probing a port with nothing behind it parked the
	# caller permanently. Measured: the exported game reached "probing :8189" and
	# printed nothing again, so the engine was never started and `warm_art`'s poll
	# loop had been stalling on its first probe rather than retrying. Two seconds
	# is generous for a loopback connection that either answers or refuses.
	req.timeout = 2.0
	add_child(req)
	if req.request(Art.IMAGE_SERVER + "/v1/models") != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return int(res[1]) == 200


# ── The engine's lifecycle ───────────────────────────────────────────────────
## Where the launcher script records the pid of an engine IT spawned. Matches
## the default in scripts/start-image-sdcpp.ps1; the port is in the name so a
## material pour on :8190 keeps its own.
func _ready() -> void:
	# Not in the harnesses. `Api.test_mode` means "no real services", and a
	# headless gate that spawned a 6.5 GB checkpoint reader five times a run
	# would be neither fast nor honest about what it was measuring.
	if Api.test_mode or OS.has_feature("editor"):
		return
	# NOT HERE. Starting the engine at boot is what a supervisor obviously ought
	# to do and it is wrong on this hardware, because sd-server takes the card
	# before the narrator does.
	#
	# Measured from its own log: sd-server loads the WHOLE checkpoint into VRAM at
	# startup, before it begins listening -
	#   total params memory size = 6624.11MB (VRAM 6624.11MB, RAM 0.00MB)
	# and only then prints "listening on". Its ~105 MB working set is system RAM,
	# which is why "sd-server idles at 118 MB because it loads per request" has
	# been repeated in this repo and is not true - the 6.6 GB is resident on the
	# GPU for as long as the process lives.
	#
	# llama.cpp fixes its GPU/CPU split ONCE, at load time. Bring the image engine
	# up first and the narrator inherits a card that is 6.6 GB down for the rest of
	# the session: the 19.3 s per turn against 3.7 s that CLAUDE.md records. So the
	# engine is started by `_open_the_adventure`, immediately AFTER `LocalGM.warm()`
	# has finished taking what it needs. Order is the whole point.


## Start the image engine unless someone else already has. Fire-and-forget: the
## checkpoint takes ~25 s to read and no screen waits for it.
func ensure_engine() -> void:
	if Api.test_mode:
		return
	if await _probe():          # somebody else's — adopt it, never seize it
		print("Services: image engine already up — adopted, and not ours to stop")
		_up = true
		art_ready.emit()
		return
	# SOMEONE MAY ALREADY BE STARTING ONE. The launcher spawns the engine and then
	# the game a second later, and the checkpoint takes ~25 s to read - so for that
	# whole window the port is dead while an engine is very much on its way. Only
	# the port would be a race that starts a SECOND engine to fight for :8189.
	# A live pid means it is already someone's, and theirs to stop.
	var existing := _pid_path()
	if FileAccess.file_exists(existing):
		var prior := FileAccess.get_file_as_string(existing).strip_edges()
		if prior.is_valid_int() and OS.is_process_running(int(prior)):
			print("Services: engine pid %s is already starting — leaving it to its owner" % prior)
			return
	var script := _launcher_script()
	if script == "":
		# NEVER SILENTLY. This returned "" and said nothing, so a Desktop copy with
		# no scripts/ beside it looked exactly like a working supervisor that had
		# decided not to bother. Name what was looked for.
		push_warning("Services: no start-image-sdcpp.ps1 beside the exe or in the project — art will be baked-only. Looked in: %s" % ", ".join(_script_candidates()))
		print("Services: no image-engine launcher found; playing with baked art only")
		return
	var pid_file := _pid_path()
	DirAccess.remove_absolute(pid_file)
	# OUR OWN PID goes with it. The script arms a watchdog on it, so the engine
	# stops when this process stops EVEN IF this process never runs another line
	# of code - which is the case the notification handlers below cannot cover,
	# and the one that actually strands 6.5 GB: llama.cpp aborting us (0xC0000409,
	# seen this month) or the player reaching for Task Manager.
	var args := ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
		"-PidFile", pid_file, "-ParentPid", str(OS.get_process_id())]
	# create_process, not execute: execute BLOCKS, and this script waits up to two
	# minutes for the port. The Hall must open now.
	print("Services: starting the image engine via %s" % script)
	if OS.create_process("powershell.exe", args) <= 0:
		push_warning("Services: could not start the image engine; art will be baked-only")
		return
	_adopt_spawned_pid(pid_file)


## The script writes its child's pid once the engine is actually spawned, so this
## polls briefly rather than assuming. It is the ONLY thing that gives us the
## right to kill anything later.
func _adopt_spawned_pid(pid_file: String) -> void:
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		if not FileAccess.file_exists(pid_file):
			continue
		var txt := FileAccess.get_file_as_string(pid_file).strip_edges()
		if txt.is_valid_int():
			_engine_pid = int(txt)
			print("Services: image engine started as pid %d — ours to stop" % _engine_pid)
			return


## Stop ONLY an engine this process started. Idempotent, and reachable from
## every teardown notification because which one arrives depends on how the
## player quit.
func _shutdown() -> void:
	if _stopped:
		return
	_stopped = true
	if _engine_pid <= 0:
		return                  # adopted, or never started: not ours to stop
	OS.kill(_engine_pid)
	DirAccess.remove_absolute(_pid_path())


## The TIDY path, not the guarantee - the watchdog armed in `ensure_engine` is
## what makes the promise, because it survives us dying without warning. This
## just means a clean quit does not wait two seconds for a poll.
##
## THE HOOK IS THE RISK, not the body. PL-8 shipped an `_exit_tree` fix for the
## audio leak that moved nothing because that hook never fired on the quit path
## it was written for, and the print inside it had never been checked. So all
## three are wired and `_shutdown` is idempotent: whichever the platform sends
## first does the work, and the others find it already done.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_PREDELETE:
		_shutdown()


func _exit_tree() -> void:
	_shutdown()


## `{app}\scripts\start-image-sdcpp.ps1` beside the exe in a real install, or
## `<repo>/scripts/…` when running from source. Returns "" when neither exists,
## which is a normal state — a player without the image engine still plays.
func _launcher_script() -> String:
	for cand in _script_candidates():
		if FileAccess.file_exists(cand):
			return cand
	return ""


func _script_candidates() -> Array:
	var here := OS.get_executable_path().get_base_dir()
	var repo := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	return [here.path_join("scripts/start-image-sdcpp.ps1"),
		repo.path_join("scripts/start-image-sdcpp.ps1")]


func _pid_path() -> String:
	return OS.get_environment("TEMP").path_join("mythforge-sd-8189.pid")

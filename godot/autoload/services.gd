extends Node
## Services — Mythforge boots and dies as one app.
##
## The game exe launches the service supervisor (scripts/mythforge_supervisor.py)
## at startup, passing its own PID. The supervisor starts Ollama, Chroma,
## ComfyUI, the image bridge and the FastAPI backend into a Windows Job Object
## and watches this process; when the game exits — cleanly OR by crash — the job
## closes and every service dies with it. No "start the server first", no
## orphaned Python after the window shuts. One icon, one lifecycle.
##
## Safe by construction: the supervisor ADOPTS anything already running and only
## kills what it started, so a hand-started dev stack is never disturbed. And
## this autoload only launches it in a real exported build — never in the editor
## or a headless test run, where services are managed by hand.

signal backend_ready
signal boot_progress(line: String)

const BACKEND_PROBE := "http://127.0.0.1:7000/api/version"

var _supervising := false
var _backend_up := false


func _ready() -> void:
	# Only own the lifecycle from the shipped app. In the editor and in
	# headless harness runs, whoever launched the services owns them.
	if not OS.has_feature("standalone") or OS.has_feature("headless"):
		return
	_launch_supervisor()


## Fire-and-forget: the supervisor is detached and self-watching, so the game
## never has to babysit it. It reaches back only by the ports coming alive.
func _launch_supervisor() -> void:
	var py := _find_python()
	if py == "":
		push_warning("Services: no Python found — assuming the backend is already running")
		return
	var script := _repo_script("scripts/mythforge_supervisor.py")
	if script == "":
		push_warning("Services: supervisor script not found — assuming external services")
		return
	var pid := OS.get_process_id()
	# Detached: it must OUTLIVE this call and watch us by PID, not by pipe.
	OS.create_process(py, [script, "--game-pid", str(pid)])
	_supervising = true


## Poll until the backend answers, so the boot screen can release to the menu
## the moment the realm is awake (ComfyUI keeps warming behind play). Emits
## progress lines for the loading frame and backend_ready when it's up.
func await_backend(max_seconds := 180.0) -> bool:
	if _backend_up:
		backend_ready.emit()
		return true
	var waited := 0.0
	while waited < max_seconds:
		if await _probe():
			_backend_up = true
			backend_ready.emit()
			return true
		boot_progress.emit(_boot_line(waited))
		await get_tree().create_timer(1.5).timeout
		waited += 1.5
	return false


func _probe() -> bool:
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/version")
	return int(r.get("_status", 0)) != 0


## Honest, world-flavoured waiting copy — the boot is a real minute on a cold
## start (ComfyUI kernel compile), so it must read as work, not a hang.
func _boot_line(t: float) -> String:
	if not _supervising:
		return "Reaching the realm…"
	if t < 8.0:
		return "Waking the realm…"
	if t < 25.0:
		return "Lighting the forges…"
	if t < 60.0:
		return "The storytellers gather…"
	return "Still waking — the first boot warms the local mind, give it a moment…"


# ── Finding the pieces on a real machine ────────────────────────────────────
func _find_python() -> String:
	# The repo venv first (it has the deps), then anything on PATH.
	for cand in [_repo_path("venv/Scripts/python.exe"), _repo_path("venv/Scripts/pythonw.exe")]:
		if cand != "" and FileAccess.file_exists(cand):
			return cand
	for name in ["python.exe", "python", "py.exe"]:
		var p: String = _which(name)
		if p != "":
			return p
	return ""


func _which(exe: String) -> String:
	var out: Array = []
	if OS.execute("where", [exe], out) == 0 and not out.is_empty():
		var first := str(out[0]).strip_edges().split("\n")[0].strip_edges()
		if first != "" and FileAccess.file_exists(first):
			return first
	return ""


## The exe sits in <repo>/dist/ or on the Desktop; the scripts live in the repo.
## Resolve the repo relative to the executable, falling back to a couple of
## known layouts so a Desktop copy still finds its scripts.
func _repo_path(rel: String) -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	for base in [exe_dir.path_join(".."), exe_dir, exe_dir.path_join("../..")]:
		var p: String = str(base).path_join(rel).simplify_path()
		if FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p):
			return p
	# Dev fallback: the well-known checkout.
	var dev := "C:/Users/cptahabb/Documents/Code/mythforge".path_join(rel)
	return dev if FileAccess.file_exists(dev) else ""


func _repo_script(rel: String) -> String:
	return _repo_path(rel)

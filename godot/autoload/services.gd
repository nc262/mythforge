extends Node
## Services — there is one, and the game does not wait for it.
##
## Mythforge runs its own language model in-process, so the exe is the whole
## app: no server to boot, no supervisor, no Python lifecycle to own. The only
## other process is stable-diffusion.cpp on :8189, and art is decoration —
## the Hall opens off the save shelf on disk whether or not it ever answers.
##
## So this autoload does exactly one thing: notice, in the background, when the
## image engine is up, so the first paint request doesn't have to discover it.

signal art_ready

var _up := false


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
	add_child(req)
	if req.request(Art.IMAGE_SERVER + "/v1/models") != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return int(res[1]) == 200

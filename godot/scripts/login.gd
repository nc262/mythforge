extends CenterContainer

const SELECT_SCENE := "res://scenes/character_select.tscn"


func _ready() -> void:
	$Box/Enter.pressed.connect(_login)
	$Box/Pass.text_submitted.connect(func(_t): _login())
	_try_resume()


## A saved cookie (or an unauthenticated single-user backend) skips the form.
func _try_resume() -> void:
	$Box/Status.text = "Reaching the realm…"
	if await Api.auth_ok():
		get_tree().change_scene_to_file(SELECT_SCENE)
	else:
		$Box/Status.text = ""


func _login() -> void:
	$Box/Status.text = "…"
	var r := await Api.login($Box/User.text.strip_edges(), $Box/Pass.text)
	if r.get("ok", false):
		get_tree().change_scene_to_file(SELECT_SCENE)
	elif r.get("requires_totp", false):
		$Box/Status.text = "2FA accounts aren't supported in the desktop client yet."
	else:
		$Box/Status.text = "Login failed (%s)" % str(r.get("_status", 0))

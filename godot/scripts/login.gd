extends Control
## The threshold. This is the first screen a stranger ever sees, so MIL §6
## applies at its strictest: no status codes, no engineering nouns, and a
## realm that is merely asleep must never read as the player's mistake.

const SELECT_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	theme = Ui.theme
	Ui.polish(self)
	$Center/Box/Enter.pressed.connect(_login)
	$Center/Box/Pass.text_submitted.connect(func(_t): _login())
	_try_resume()


## A saved cookie (or an unauthenticated single-user backend) skips the form.
func _try_resume() -> void:
	$Center/Box/Status.text = "Reaching the realm…"
	if await Api.auth_ok():
		Ui.transition(SELECT_SCENE, get_tree())
	else:
		$Center/Box/Status.text = ""


func _login() -> void:
	$Center/Box/Status.text = "…"
	var r := await Api.login($Center/Box/User.text.strip_edges(), $Center/Box/Pass.text)
	if r.get("ok", false):
		Ui.transition(SELECT_SCENE, get_tree())
		return
	Ui.shake($Center/Box)
	if r.get("requires_totp", false):
		$Center/Box/Status.text = "This account guards itself with a second key — the desktop client can't carry that yet."
	elif int(r.get("_status", 0)) == 0:
		# Transport failure: the realm is asleep, not the player wrong.
		$Center/Box/Status.text = "The realm isn't answering. Mythforge's own backend may not be running yet — start it, then try again."
	else:
		$Center/Box/Status.text = "That name and word don't open the door."

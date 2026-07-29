extends Control
## The threshold. This is the first screen a stranger ever sees, so MIL §6
## applies at its strictest: no status codes, no engineering nouns, and a
## realm that is merely asleep must never read as the player's mistake.

const SELECT_SCENE := "res://scenes/main_menu.tscn"


## The door only appears if it is actually locked.
##
## R12-02 — login was retired in 2026-07-22, and it was: a saved cookie (or an
## unauthenticated single-user backend) resumes straight through. But this scene
## is the boot scene, and it showed the NAME AND WORD FIELDS the whole time it
## was waiting for the backend to wake and answer — then vanished. What the
## player sees is a login prompt flashing at every start of a game that does not
## ask anyone to log in. It reads as a regression because it looks like one.
##
## The form now starts hidden. It is revealed only when the realm answers and
## says the door really is shut.
func _ready() -> void:
	theme = Ui.theme
	Ui.polish(self)
	$Center/Box/Enter.pressed.connect(_login)
	$Center/Box/Pass.text_submitted.connect(func(_t): _login())
	_show_door(false)
	_try_resume()


func _show_door(on: bool) -> void:
	for n in ["Spacer", "User", "Pass", "Enter"]:
		var c := $Center/Box.get_node_or_null(n)
		if c != null:
			c.visible = on
	$Center/Box/Sub.visible = on


## A saved cookie (or an unauthenticated single-user backend) skips the form.
## On a shipped build the backend may still be BOOTING (the exe just started it),
## so wait for the realm to wake — showing honest, world-flavoured progress —
## before deciding the door is shut.
func _try_resume() -> void:
	$Center/Box/Status.text = "Reaching the realm…"
	Services.boot_progress.connect(func(line): $Center/Box/Status.text = line)
	await Services.await_backend()
	if await Api.auth_ok():
		Ui.transition(SELECT_SCENE, get_tree())
	else:
		_show_door(true)
		$Center/Box/Status.text = ""
		$Center/Box/User.grab_focus()


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

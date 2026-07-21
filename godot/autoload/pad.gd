extends Node
## Controller support (Roadmap: input-map-per-state via the FSM). Registers
## the app's pad actions at runtime — no project.godot [input] section to rot —
## extends the built-in ui_* actions with joypad events, and seeds FOCUS when
## the pad speaks while nothing is focused. That one universal rule makes every
## Button-built surface (menu pillars, forge cards and nav, windows, dialogs —
## AcceptDialogs already focus their OK button) pad-navigable with no
## per-screen wiring. The custom surfaces listen to the mf_* actions
## themselves: game.gd routes mf_roll/mf_end_turn and steers the combat
## grid's pad cursor.
##
## Known ceilings (tracked in Backlog): the forge stage rail and the combat
## panel's inline spell links stay mouse-only — the nav buttons and grid
## tokens cover their functions on pad.

const ACTIONS := {
	"mf_roll": JOY_BUTTON_Y,       # the dice moment / roll bar
	"mf_end_turn": JOY_BUTTON_X,   # combat: end the turn
	"mf_menu": JOY_BUTTON_START,   # focus the message box
}


func _ready() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		_ensure_button(a, ACTIONS[a])
	# The built-ins drive all focus traversal — make sure a pad can speak them.
	_ensure_button("ui_accept", JOY_BUTTON_A)
	_ensure_button("ui_cancel", JOY_BUTTON_B)
	_ensure_dir("ui_up", JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0)
	_ensure_dir("ui_down", JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	_ensure_dir("ui_left", JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_ensure_dir("ui_right", JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0)


func _ensure_button(action: String, btn: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == btn:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	InputMap.action_add_event(action, ev)


func _ensure_dir(action: String, btn: int, axis: int, sign_v: float) -> void:
	_ensure_button(action, btn)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis:
			return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = sign_v
	InputMap.action_add_event(action, ev)


## The seed: pad input while nothing is focused → focus the scene's first
## focusable control, so d-pad traversal has somewhere to start.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var vp := get_viewport()
	if vp == null or vp.gui_get_focus_owner() != null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var first := _first_focusable(scene)
	if first != null:
		first.grab_focus()


func _first_focusable(node: Node) -> Control:
	if node is Control and node.focus_mode == Control.FOCUS_ALL and node.is_visible_in_tree() and not (node is Window):
		return node
	for ch in node.get_children():
		if ch is Window:
			continue  # dialogs manage their own focus
		var f := _first_focusable(ch)
		if f != null:
			return f
	return null

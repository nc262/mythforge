extends MarginContainer

const GAME_SCENE := "res://scenes/game.tscn"

var _chars: Array = []


func _ready() -> void:
	$Box/Play.pressed.connect(_play)
	$Box/List.item_activated.connect(func(_i): _play())
	_load()


func _load() -> void:
	$Box/Status.text = "Summoning the roster…"
	_chars = await Api.list_characters()
	$Box/List.clear()
	for c in _chars:
		$Box/List.add_item(str(c.get("name", "Unnamed")))
	$Box/Status.text = "" if not _chars.is_empty() else "No characters found — forge one in the web studio first."


func _play() -> void:
	var sel: PackedInt32Array = $Box/List.get_selected_items()
	if sel.is_empty():
		return
	var c: Dictionary = _chars[sel[0]]
	$Box/Status.text = "Opening the adventure…"
	$Box/Play.disabled = true
	GameState.character = c
	GameState.session_id = await Api.ensure_session(str(c.get("id", "")), str(c.get("name", "")))
	if GameState.session_id == "":
		$Box/Status.text = "Could not create a session (is a chat model endpoint configured?)."
		$Box/Play.disabled = false
		return
	get_tree().change_scene_to_file(GAME_SCENE)

extends Control

const GAME_SCENE := "res://scenes/game.tscn"

var _chars: Array = []


func _ready() -> void:
	theme = Ui.theme
	Ui.apply("")  # roster shows the neutral arcane sky
	$Margin/Box/Play.pressed.connect(_play)
	$Margin/Box/List.item_activated.connect(func(_i): _play())
	_load()


func _load() -> void:
	$Margin/Box/Status.text = "Summoning the roster…"
	# Adventures only (dm-* templates, same test as the web client's _isDM):
	# they own the hero sheet, world state, and GM rules. Plain personas are
	# chat companions, not games.
	_chars = (await Api.list_characters()).filter(func(c): return str(c.get("id", "")).begins_with("dm-"))
	$Margin/Box/List.clear()
	for c in _chars:
		var world := str(c.get("world_id", ""))
		$Margin/Box/List.add_item(str(c.get("name", "Unnamed")) + ("   ·  %s" % world if world != "" else ""))
	$Margin/Box/Status.text = "" if not _chars.is_empty() else "No adventures found — start one in the web studio first."


func _play() -> void:
	var sel: PackedInt32Array = $Margin/Box/List.get_selected_items()
	if sel.is_empty():
		return
	var c: Dictionary = _chars[sel[0]]
	$Margin/Box/Status.text = "Opening the adventure…"
	$Margin/Box/Play.disabled = true
	GameState.character = c
	Ui.apply(str(c.get("world_id", "")))  # the world paints the whole client
	GameState.session_id = await Api.ensure_session(str(c.get("id", "")), str(c.get("name", "")))
	if GameState.session_id == "":
		$Margin/Box/Status.text = "Could not create a session (is a chat model endpoint configured?)."
		$Margin/Box/Play.disabled = false
		return
	get_tree().change_scene_to_file(GAME_SCENE)

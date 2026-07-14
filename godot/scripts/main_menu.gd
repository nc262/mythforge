extends Control
## The title screen: the brand, Continue (last adventure), and every
## adventure as a world-tinted card. Cards carry the world's own accent
## color, so the menu already speaks fantasy / sci-fi / slice-of-life.

const GAME_SCENE := "res://scenes/game.tscn"
const WORLD_LINES := {
	"embervale": "High fantasy — candlelight and old roads",
	"neonspire": "Sci-fi — neon rain over the spire",
	"everyday": "Slice of life — the quiet hours",
}

var _busy := false


func _ready() -> void:
	theme = Ui.theme
	Ui.apply("")
	$Center/Box/Continue.pressed.connect(_continue_last)
	_load()


func _load() -> void:
	$Center/Box/Status.text = "Summoning the realms…"
	var advs: Array = (await Api.list_characters()).filter(func(c): return str(c.get("id", "")).begins_with("dm-"))
	var grid: GridContainer = $Center/Box/Scroll/Grid
	for child in grid.get_children():
		child.queue_free()
	for c in advs:
		grid.add_child(_card(c))
	$Center/Box/Status.text = "" if not advs.is_empty() else "No adventures yet — forge one in the web studio."
	# Continue = the adventure you last walked out of.
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	var last = JSON.parse_string(str(cfg.get_value("last", "adventure", "")))
	if last is Dictionary and advs.any(func(c): return str(c.get("id")) == str(last.get("id"))):
		var btn: Button = $Center/Box/Continue
		btn.text = "▶ Continue — %s" % str(last.get("name", "?"))
		btn.visible = true
		btn.set_meta("char", last)


func _card(c: Dictionary) -> Button:
	var world := str(c.get("world_id", ""))
	var pal: Dictionary = Ui.PALETTES.get(world if Ui.PALETTES.has(world) else "arcane", Ui.PALETTES["arcane"])
	var accent: Color = pal["gold"]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(410, 92)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The world paints its card: its accent on the left edge and the name.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(pal["surface"], 0.9)
	sb.border_color = Color(accent, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.border_color = accent
	sb_hover.bg_color = Color(pal["surface2"], 0.95)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	var flavor: String = WORLD_LINES.get(world, "A forged world — its own rules, its own dawn")
	btn.text = "%s\n" % str(c.get("name", "Unnamed"))
	# Two-line label via child labels (Button text can't mix colors).
	btn.text = ""
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = str(c.get("name", "Unnamed"))
	name_l.add_theme_color_override("font_color", Color(accent).lightened(0.2))
	name_l.add_theme_font_override("font", Ui.serif)
	name_l.add_theme_font_size_override("font_size", 20)
	var line_l := Label.new()
	line_l.text = flavor
	line_l.theme_type_variation = "HintLabel"
	box.add_child(name_l)
	box.add_child(line_l)
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(18, 0)
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	btn.add_child(box)
	btn.pressed.connect(func(): _play(c))
	return btn


func _continue_last() -> void:
	_play($Center/Box/Continue.get_meta("char"))


func _play(c: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	$Center/Box/Status.text = "Opening %s…" % str(c.get("name", ""))
	GameState.character = c
	Ui.apply(str(c.get("world_id", "")))
	GameState.session_id = await Api.ensure_session(str(c.get("id", "")), str(c.get("name", "")))
	if GameState.session_id == "":
		$Center/Box/Status.text = "Could not create a session (is a chat model endpoint configured?)."
		Ui.apply("")
		_busy = false
		return
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	cfg.set_value("last", "adventure", JSON.stringify({"id": c.get("id"), "name": c.get("name"), "world_id": c.get("world_id", "")}))
	cfg.save(Api.COOKIE_FILE)
	get_tree().change_scene_to_file(GAME_SCENE)

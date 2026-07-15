extends Control
## The title screen: the brand, Continue, world-tinted adventure cards with
## generated key art, and the World Forge — co-create a world with the AI
## and its campaigns become playable cards.

const GAME_SCENE := "res://scenes/game.tscn"
const WORLD_LINES := {
	"embervale": "High fantasy — candlelight and old roads",
	"neonspire": "Sci-fi — neon rain over the spire",
	"everyday": "Slice of life — the quiet hours",
}

var _busy := false
var _worlds: Dictionary = {}  # world_id -> custom world dict (for art prompts)


func _ready() -> void:
	theme = Ui.theme
	Ui.apply("")
	$Center/Box/Continue.pressed.connect(_continue_last)
	$Center/Box/Forge.pressed.connect(_open_forge)
	Art.art_ready.connect(func(_wid): _load())
	_load()


func _load() -> void:
	$Center/Box/Status.text = "Summoning the realms…"
	# Custom worlds live in the global state kind 'cworlds'.
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	_worlds = {}
	if g.get("state") is Dictionary and g["state"].get("cworlds") is Array:
		for w in g["state"]["cworlds"]:
			if w is Dictionary and str(w.get("id", "")) != "":
				_worlds[str(w["id"])] = w
	var advs: Array = (await Api.list_characters()).filter(func(c): return str(c.get("id", "")).begins_with("dm-"))
	var grid: GridContainer = $Center/Box/Scroll/Grid
	for child in grid.get_children():
		child.queue_free()
	for c in advs:
		grid.add_child(_card(c))
		var wid := str(c.get("world_id", ""))
		Art.ensure(wid, str(_worlds.get(wid, {}).get("backdrop", "")))  # backfill key art quietly
	$Center/Box/Status.text = "" if not advs.is_empty() else "No adventures yet — forge a world below."
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
	btn.clip_contents = true
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
	# Key art behind the text, dimmed to keep the name readable.
	var tex := Art.texture_for(world)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.modulate = Color(0.62, 0.6, 0.7, 0.5)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(art)
	var flavor: String = WORLD_LINES.get(world,
		str(_worlds.get(world, {}).get("tagline", "A forged world — its own rules, its own dawn")))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = str(c.get("name", "Unnamed"))
	name_l.add_theme_color_override("font_color", Color(accent).lightened(0.2))
	name_l.add_theme_font_override("font", Ui.serif)
	name_l.add_theme_font_size_override("font_size", 20)
	var line_l := Label.new()
	line_l.text = flavor.left(58)
	line_l.theme_type_variation = "HintLabel"
	box.add_child(name_l)
	box.add_child(line_l)
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(18, 0)
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	btn.add_child(box)
	btn.pressed.connect(func(): _play(c))
	return btn


# ── The World Forge ──────────────────────────────────────────────────────────
func _open_forge() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "⚒ Forge a world"
	dlg.ok_button_text = "Forge it"
	dlg.min_size = Vector2i(520, 200)
	var box := VBoxContainer.new()
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.text = "Describe the world you want — genre, mood, one striking image.\nThe forge writes its lore, places, people, beasts, and two campaigns."
	var input := LineEdit.new()
	input.placeholder_text = "e.g. a drowned kingdom where lighthouse keepers bargain with the tide"
	box.add_child(hint)
	box.add_child(input)
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	input.grab_focus()
	var go := func():
		var idea := input.text.strip_edges()
		dlg.queue_free()
		if idea != "":
			_forge(idea)
	dlg.confirmed.connect(go)
	input.text_submitted.connect(func(_t): dlg.hide(); go.call())


func _forge(idea: String) -> void:
	if _busy:
		return
	_busy = true
	$Center/Box/Status.text = "⚒ The forge burns — shaping a world (about a minute)…"
	var w := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/worldsmith",
		{"idea": idea, "mode": "world"})
	if w.get("_status", 0) != 200 or str(w.get("name", "")) == "":
		$Center/Box/Status.text = "The forge sputtered (%s) — try again." % str(w.get("_status", 0))
		_busy = false
		return
	var wid := "cw-%s-%04x" % [str(w["name"]).to_lower().replace(" ", "-").left(20), randi() % 65536]
	var world := {"id": wid, "custom": true}
	for k in ["name", "kind", "tagline", "lore", "backdrop", "locations", "cast", "stories", "creatures"]:
		world[k] = w.get(k)
	# Persist the world into the global codex of forged worlds.
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	var cworlds: Array = g.get("state", {}).get("cworlds", []) if g.get("state") is Dictionary else []
	if not (cworlds is Array):
		cworlds = []
	cworlds.append(world)
	await Api.call_json(HTTPClient.METHOD_PUT, "/api/characters/studio/state/_global/cworlds", {"value": cworlds})
	# Free roam + each forged campaign become playable adventures.
	$Center/Box/Status.text = "⚒ Binding its campaigns…"
	await _save_adventure("dm-%s-freeroam" % wid, "%s: Free Roam" % str(world["name"]), world, {})
	var stories: Array = world.get("stories") if world.get("stories") is Array else []
	for st in stories:
		if st is Dictionary and str(st.get("title", "")) != "":
			var slug := str(st["title"]).to_lower().replace(" ", "-").left(24)
			await _save_adventure("dm-%s-%s" % [wid, slug], str(st["title"]), world, st)
	$Center/Box/Status.text = "⚒ Painting its sky…"
	await Art.ensure(wid, str(world.get("backdrop", "")))
	$Center/Box/Status.text = "%s stands ready." % str(world["name"])
	_busy = false
	_load()


func _save_adventure(id: String, name: String, world: Dictionary, story: Dictionary) -> void:
	await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/save", {
		"id": id, "name": name,
		"personality": Composer.compose_world_gm(world, story),
		"relationship": "Dungeon Master",
		"world_id": str(world["id"]),
	})


# ── Play ─────────────────────────────────────────────────────────────────────
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

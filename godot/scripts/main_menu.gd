extends Control
## The original shell, native: title screen (Continue · New Adventure ·
## Companion chat · Settings), the worlds gallery → world detail flow
## (free roam / campaigns / craft-a-campaign / the cast), the guided
## pillar-form World Forge with a refine loop, and settings.

const GAME_SCENE := "res://scenes/game.tscn"

var _busy := false
var _cworlds: Array = []
var _templates: Array = []

@onready var _title: CenterContainer = $Title
@onready var _sub: Control = $Sub
@onready var _content: VBoxContainer = $Sub/Margin/Box/Scroll/Content
@onready var _heading: Label = $Sub/Margin/Box/Bar/Heading
@onready var _step: Label = $Sub/Margin/Box/Bar/Step
@onready var _sub_status: Label = $Sub/Margin/Box/SubStatus


func _ready() -> void:
	theme = Ui.theme
	Ui.apply("")
	Mode.enter("MainMenu")
	$Title/Box/Divider.draw.connect(func():
		var d: Control = $Title/Box/Divider
		var w := d.size.x
		var y := d.size.y / 2.0
		var gold: Color = Ui.c("gold")
		d.draw_line(Vector2(0, y), Vector2(w * 0.42, y), Color(gold, 0.0).lerp(Color(gold, 0.7), 1.0), 1.0)
		d.draw_line(Vector2(w * 0.58, y), Vector2(w, y), Color(gold, 0.7), 1.0)
		for k in [[w * 0.5, 5.0], [w * 0.44, 2.6], [w * 0.56, 2.6]]:
			var cx: float = k[0]
			var r: float = k[1]
			d.draw_colored_polygon(PackedVector2Array([Vector2(cx, y - r), Vector2(cx + r, y), Vector2(cx, y + r), Vector2(cx - r, y)]), gold))
	_load_settings()
	_build_primary_controls()
	$Sub/Margin/Box/Bar/Back.pressed.connect(_show_title)
	Art.art_ready.connect(func(_w): if _sub.visible and _heading.text == "Choose a world": _show_worlds())
	# EAS: the Hall ITSELF is a painting — the title never sits on a void.
	# (Continue's world key-art still takes over once a tale exists.)
	Art.ensure("env-hall", "the grand hall of an adventurers' guild at night: a long candlelit stone hall, banners hanging from oak rafters, a great hearth glowing at the far end, trophies, maps and mounted arms on the walls, volumetric warm light against deep shadow, ultra detailed fantasy interior illustration, no people, no text", "1344x768")
	if $KeyArt.texture == null and Art.has_art("env-hall"):
		$KeyArt.texture = Art.texture_for("env-hall")
	Art.art_ready.connect(func(k):
		if str(k) == "env-hall" and $KeyArt.texture == null:
			$KeyArt.texture = Art.texture_for("env-hall"))
	# A woven banner crowns the title — a generated prop, framed, never raw.
	Art.ensure("prop-banner", "a single ornate medieval heraldic banner hanging flat, rich crimson and gold embroidery, a sword-and-star crest, tasseled lower edge, painted fantasy prop on a plain black background, no text", "1024x1024")
	var banner := TextureRect.new()
	banner.custom_minimum_size = Vector2(0, 84)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.modulate = Color(1, 1, 1, 0.9)
	banner.texture = Art.texture_for("prop-banner")
	banner.visible = banner.texture != null
	$Title/Box.add_child(banner)
	$Title/Box.move_child(banner, 0)
	Art.art_ready.connect(func(k):
		if str(k) == "prop-banner" and is_instance_valid(banner):
			banner.texture = Art.texture_for("prop-banner")
			banner.visible = true)
	_boot_cinematic()
	_refresh()


var _btn_continue: MythButton = null
var _btn_forge_hero: MythButton = null


## The FORGE A HERO plate wears its roster count, so a saved legend is
## visibly saved the moment you return to the Hall (fixes "my hero vanished").
func _refresh_hero_count() -> void:
	if _btn_forge_hero == null:
		return
	var n := GameState.banked_heroes().size()
	_btn_forge_hero.set_subtitle(("%d waiting at the anvil" % n) if n > 0 else "")


## The primary controls: handcrafted material plates from the Icon Library —
## never a software widget (docs/DesignSystem.md, EAS + MDL law).
func _build_primary_controls() -> void:
	var box: VBoxContainer = $Title/Box/Buttons
	_btn_continue = MythButton.new("CONTINUE  ADVENTURE", "banner", "brass")
	_btn_continue.visible = false
	_btn_continue.pressed.connect(_continue_last)
	box.add_child(_btn_continue)
	# R6 CUT-10 / BUG-02: this column carried TWELVE buttons — five of them
	# "FORGE A …" — and at 1280×800 the last two rendered entirely BELOW the
	# viewport with no scroll: unreachable, and the wordmark was clipped off the
	# top by the same overflow. Folding the five forges behind one destination
	# fixes the overflow at its cause and stops the menu reading as a wall of
	# near-identical options. Material now means RANK (oak = play, steel = make,
	# leather = browse), not decoration — R6 AAA-01.
	var specs := [
		["BEGIN  A  NEW  ADVENTURE", "compass", "oak", _open_adventure_forge, "the table is set"],
		["THE  FORGE", "anvil", "steel", _show_forges, "hero · world · campaign · GM · companion"],
		["CAMPAIGNS", "scroll", "leather", _show_campaigns, "premises across every world"],
		["CHRONICLES", "book", "leather", _open_chronicles, "the saved tales"],
		["A  QUIET  TABLE", "cups", "leather", _show_companions, "chat with a companion"],
		["SETTINGS", "runewheel", "steel", _show_settings, "sound, motion, contrast"],
		["EXIT  THE  HALL", "door", "leather", _quit_game, ""],
	]
	for sp in specs:
		var b := MythButton.new(str(sp[0]), str(sp[1]), str(sp[2]), str(sp[4]))
		b.pressed.connect(sp[3])
		box.add_child(b)
		if str(sp[1]) == "anvil":
			_btn_forge_hero = b
	box.get_child(1).grab_focus()
	_fit_title_column()


## R6 BUG-02/03/04 — a self-healing floor under the menu's height. Consolidating
## the buttons is what actually made it fit, but nothing STOPPED it overflowing
## again the next time someone adds an entry, and the failure mode is silent:
## a CenterContainer overflows off BOTH edges, so the wordmark clips and the
## bottom buttons become mouse-unreachable with no error. Measure the column and
## tighten spacing/wordmark until it fits the window it actually has.
func _fit_title_column() -> void:
	var box: VBoxContainer = $Title/Box
	var brand: Label = $Title/Box/Brand
	for attempt in 6:
		await get_tree().process_frame
		var need := box.get_combined_minimum_size().y
		var have := get_viewport_rect().size.y - 24.0
		if need <= have:
			return
		# Squeeze the two things that cost the most height and matter the least.
		var sep := maxi(2, box.get_theme_constant("separation") - 3)
		box.add_theme_constant_override("separation", sep)
		brand.add_theme_font_size_override("font_size",
			maxi(44, brand.get_theme_font_size("font_size") - 10))


func _quit_game() -> void:
	get_tree().quit()


## R6 CUT-10 — the five forges, behind one door. They were five of the twelve
## buttons on the title screen, which is what pushed two of them off the bottom
## of the window entirely. Grouped here they read as one workshop with five
## benches, and each card says what it MAKES rather than repeating the verb.
func _show_forges() -> void:
	_show_sub("The Forge", "make something of your own")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for f in [
			["A Hero", "Race, class, background, face and voice — someone to be.", _open_character_forge_pillar],
			["A World", "The smith writes lore, places, people and beasts from your idea.", _open_world_forge_pillar],
			["A Campaign", "A story to play through, shaped to the world it lives in.", _open_campaign_forge_pillar],
			["A Game Master", "The voice at the table — its humour, grit and pace.", _open_gm_forge_pillar],
			["A Companion", "A friend for the road, with a face and a history.", _open_persona_forge_pillar]]:
		var card := _big_card(str(f[0]), str(f[1]), Ui.pal["gold"])
		card.pressed.connect(f[2])
		grid.add_child(card)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_content.add_child(gc)
	Ui.reveal_children(grid, 0.05)


## 🧭 Begin a New Adventure — the table-setting ritual orchestrating both
## Forges (hero → campaign → party → difficulty → house rules → preview).
var _adv_forge: Control = null


func _open_adventure_forge() -> void:
	Mode.enter("CampaignForge")
	_title.visible = false
	_sub.visible = false
	if _adv_forge == null:
		_adv_forge = preload("res://scenes/forge/adventure_forge.tscn").instantiate()
		_adv_forge.adventure_ready.connect(func(adv):
			_adv_forge.visible = false
			Mode.enter("MainMenu")
			_play(adv))
		_adv_forge.closed.connect(func():
			_adv_forge.visible = false
			Mode.enter("MainMenu")
			_show_title())
		add_child(_adv_forge)
	else:
		_adv_forge.visible = true
	Ui.polish(_adv_forge)


## Every tale the player has actually played, newest first. This used to
## intersect local session ids with the PRESET TEMPLATE list — the same bug
## that killed Continue — so custom-world tales were invisible here too.
func _open_chronicles() -> void:
	var saved: Array = []
	for a in await GameState.load_index():
		if a is Dictionary and str(a.get("id", "")).begins_with("dm-"):
			saved.append({"id": a.get("id"), "name": a.get("name"),
				"world_id": a.get("world_id", ""), "hero": a.get("hero", ""),
				"level": a.get("level", 1), "day": a.get("day", 1), "done": a.get("done", false)})
	_show_saves(saved)


## The first impression: four worlds in one breath, then the name is forged.
## Plays once per launch; any input skips it.
func _boot_cinematic() -> void:
	if Engine.has_meta("mf_cine_played") or OS.get_environment("MF_SKIP_CINE") == "1":
		return
	Engine.set_meta("mf_cine_played", true)
	# R12-04 — this was once per LAUNCH. A first impression can only happen once;
	# every showing after that is a toll between the player and the game, and it
	# is paid by the person testing the build most often. Remembered across runs.
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	if bool(cfg.get_value("settings", "cine_seen", false)):
		return
	cfg.set_value("settings", "cine_seen", true)
	cfg.save(Api.COOKIE_FILE)
	_title.visible = false
	var cine := preload("res://scenes/ui/cinematic.gd").new()
	add_child(cine)
	cine.finished.connect(func():
		_title.visible = true
		Ui.reveal_children($Title/Box/Buttons, 0.08))
	for k in Art.CINE_PROMPTS:
		Art.ensure(str(k), str(Art.CINE_PROMPTS[k]), "1344x768")


## The Hall paints from DISK first, and only then talks to anything.
##
## It used to open with `await Api.list_characters()`, so every local thing on
## this screen — the resume shelf, the hero count, the custom worlds — waited
## behind a network round trip. With the backend slow or not answering, the
## Hall simply never reached the code that shows CONTINUE: no error, no status,
## just a title screen that quietly pretends you have never played.
##
## Saves are local now, so nothing here needs the network at all. The one call
## that still does (preset templates, for the Campaign shelf) happens last, and
## the screen is already complete before it starts.
func _refresh() -> void:
	_refresh_hero_count()
	_paint_continue()
	_cworlds = GameState.global_get("cworlds", [])
	for w in _all_worlds():  # warm the World Skin cache so every world themes correctly in play
		WorldSkin.remember(w)
	$Title/Box/Status.text = ""
	_templates = await Api.list_characters()
	await GameState.import_global_once()   # first run only: seed the shelf, once
	if _cworlds.is_empty():
		_cworlds = GameState.global_get("cworlds", [])
		for w in _all_worlds():
			WorldSkin.remember(w)


func _paint_continue() -> void:
	# Continue: the newest record in the ADVENTURE INDEX. It used to match the
	# last-played id against the preset-template list, which never contains a
	# custom-world tale — so Continue died while the save sat safe on the
	# server (playtest #1 RCA). The index is now the source of truth, and it
	# also carries its own caption, so no second fetch is needed.
	var index := await GameState.load_index()
	var last: Dictionary = index[0] if not index.is_empty() and index[0] is Dictionary else {}
	if not last.is_empty():
		_btn_continue.set_engraving("CONTINUE — %s" % str(last.get("name", "?")).to_upper().left(24))
		_btn_continue.set_subtitle("%s · Level %d · Day %d" % [str(last.get("hero", "a new hero")),
			int(last.get("level", 1)), int(last.get("day", 1))])
		_btn_continue.visible = true
		_btn_continue.set_meta("char", {"id": last.get("id"), "name": last.get("name"),
			"world_id": last.get("world_id", "")})
		# R6 root cause #1 again: prefer the world's BAKED establishing shot over
		# whatever the art cache happens to hold under the bare world id.
		var tex: Texture2D = Compiler.key_art(str(last.get("world_id", "")))
		if tex == null:
			tex = Art.texture_for(str(last.get("world_id", "")))
		if tex != null:
			$KeyArt.texture = tex


# ── View plumbing ────────────────────────────────────────────────────────────
func _show_title() -> void:
	Mode.enter("MainMenu")
	$Scrim.color = Color(0.047, 0.039, 0.11, 0.45)   # let the art breathe again
	_sub.visible = false
	_title.visible = true
	Ui.apply("")


func _show_sub(heading: String, step := "") -> void:
	_title.visible = false
	_sub.visible = true
	# R6 BUG-15 / AAA-22 / AES-03/06 — the title screen is mostly wordmark over
	# art and reads fine at the shipped scrim, but a SUB view lays paragraphs of
	# body copy over the same photograph, where it measured at roughly a tenth of
	# usable contrast. Deepen the scrim while text is the subject, restore it when
	# the art is.
	$Scrim.color = Color(Ui.c("night"), 0.78)
	_heading.text = heading
	_step.text = step
	_sub_status.text = ""
	for c in _content.get_children():
		c.queue_free()


func _all_worlds() -> Array:
	return Rules.builtin_worlds() + _cworlds


func _world_by_id(wid: String) -> Dictionary:
	for w in _all_worlds():
		if str(w.get("id", "")) == wid:
			return w
	return {}


# ── Worlds gallery (New Adventure · step 1) ──────────────────────────────────
func _show_worlds() -> void:
	_show_sub("Choose a world", "New adventure · Step 1 of 3 — world › campaign › hero")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for w in _all_worlds():
		grid.add_child(_world_card(w))
		Art.ensure(str(w.get("id", "")), str(w.get("backdrop", "")))
	var forge := _big_card("Forge a new world", "The smith writes lore, places, people, beasts, and campaigns from your idea.", Ui.pal["gold"])
	forge.pressed.connect(_open_world_forge_pillar)
	grid.add_child(forge)
	var imp := _big_card("⬆  Import a world file", "A .world.json forged on any table.", Ui.pal["ink_soft"])
	imp.pressed.connect(_import_world)
	grid.add_child(imp)
	_content.add_child(grid)
	Ui.reveal_children(grid, 0.05)  # the worlds arrive one by one


## The campaign shelf: every authored premise across EVERY world in one
## place — browse cross-world, then go set the table.
##
## The shelf used to hand-roll a flat PanelContainer with one ghost button that
## called _open_adventure_forge() — which takes no arguments, so the tale the
## player had just chosen was THROWN AWAY: the whole point of the screen. The
## card was also the only card in the game that wasn't a _big_card, which is why
## it alone had no hover state and read as dead (UXAudit R5 BLK-03 / VIS-05).
## Now it is the same card as everywhere else, bound to its tale, and the whole
## card is the target — not a 254 px button in the corner.
func _show_campaigns() -> void:
	_show_sub("The Campaign Shelf", "every authored premise, across every world")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	for w in _all_worlds():
		var wid := str(w.get("id", ""))
		var stories: Array = w.get("stories") if w.get("stories") is Array else Rules.world_stories(wid)
		for st in stories:
			if not (st is Dictionary) or str(st.get("title", "")) == "":
				continue
			var card := _big_card("%s   ·   %s" % [str(st["title"]), str(w.get("name", ""))],
				str(st.get("premise", "")).left(240), Ui.pal["amethyst"])
			card.custom_minimum_size = Vector2(720, 104)
			card.tooltip_text = "Set the table with this tale"
			card.pressed.connect(func(): _start_adventure(w, st))
			list.add_child(card)
	if list.get_child_count() == 0:
		var empty := Label.new()
		empty.theme_type_variation = "HintLabel"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.text = "No campaigns authored yet — the Campaign Forge writes them."
		list.add_child(empty)
	_content.add_child(list)
	Ui.reveal_children(list, 0.04)


func _import_world() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters = PackedStringArray(["*.world.json ; Mythforge worlds", "*.json ; JSON"])
	dlg.min_size = Vector2i(720, 480)
	add_child(dlg)
	dlg.popup_centered()
	dlg.file_selected.connect(func(path):
		dlg.queue_free()
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary) or str(parsed.get("name", "")) == "" or str(parsed.get("lore", "")) == "":
			_sub_status.text = "That file isn't a world — it needs at least a name and lore."
			return
		var world: Dictionary = parsed
		if str(world.get("id", "")) == "" or _cworlds.any(func(cw): return str(cw.get("id")) == str(world.get("id"))):
			world["id"] = "cw-%s-%04x" % [str(world["name"]).to_lower().replace(" ", "-").left(20), randi() % 65536]
		world["custom"] = true
		_cworlds.append(world)
		GameState.global_set("cworlds", _cworlds)
		Art.ensure(str(world["id"]), str(world.get("backdrop", "")))
		_show_detail(world))
	dlg.canceled.connect(func(): dlg.queue_free())


func _world_card(w: Dictionary) -> Button:
	var wid := str(w.get("id", ""))
	# The card wears the world's own skin palette (M-B), not a fantasy default.
	var pal: Dictionary = Ui.PALETTES.get(str(WorldSkin.skin_for_id(wid).get("palette", "arcane")), Ui.PALETTES["arcane"])
	var btn := _big_card("%s\n" % str(w.get("name", "?")), "", pal["gold"])
	btn.clip_contents = true
	var tex := Art.texture_for(wid)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.modulate = Color(0.6, 0.58, 0.68, 0.5)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(art)
		btn.move_child(art, 0)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := Label.new()
	kind.theme_type_variation = "HintLabel"
	kind.text = str(w.get("kind", "")).to_upper()
	var name_l := Label.new()
	name_l.text = str(w.get("name", "?"))
	name_l.add_theme_font_override("font", Ui.serif)
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", Color(pal["gold"]).lightened(0.2))
	var tag := Label.new()
	tag.theme_type_variation = "HintLabel"
	tag.text = str(w.get("tagline", "")).left(64)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(320, 0)
	for n in [kind, name_l, tag]:
		box.add_child(n)
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(18, 8)
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	btn.add_child(box)
	btn.text = ""
	btn.pressed.connect(func(): _show_detail(w))
	return btn


func _big_card(title: String, sub: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 118)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Ui.c("surface"), 0.9)
	sb.border_color = Color(accent, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	var hov: StyleBoxFlat = sb.duplicate()
	hov.border_color = accent
	hov.bg_color = Color(Ui.c("surface2"), 0.95)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	if title != "" and sub != "":
		btn.text = ""
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := Label.new()
		t.text = title
		t.add_theme_color_override("font_color", Color(accent).lightened(0.2))
		var s := Label.new()
		s.theme_type_variation = "HintLabel"
		s.text = sub
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(300, 0)
		box.add_child(t)
		box.add_child(s)
		box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		box.position = Vector2(18, 8)
		box.grow_vertical = Control.GROW_DIRECTION_BOTH
		btn.add_child(box)
	else:
		btn.text = title
	return btn


# ── World detail (step 2: pick a campaign, or meet the cast) ─────────────────
func _show_detail(w: Dictionary) -> void:
	var wid := str(w.get("id", ""))
	WorldSkin.remember(w)  # this world may be freshly forged — resolve its skin now
	_show_sub(str(w.get("name", "?")), "New adventure · Step 2 of 3 — world › campaign › hero")
	Ui.apply(wid)
	# A vivid reveal: tagline, lore, and the world's places and beasts named
	# with their own descriptions — a world you can read (#6).
	var reveal := RichTextLabel.new()
	reveal.bbcode_enabled = true
	reveal.fit_content = true
	reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reveal.custom_minimum_size = Vector2(720, 0)
	reveal.text = _world_reveal_text(w)
	_content.add_child(reveal)
	_content.add_child(_section("ADVENTURES — a Dungeon Master narrates & drives the story"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var free := _big_card("Free Roam", "No script — the GM improvises around whatever you chase.", Ui.pal["gold"])
	free.pressed.connect(func(): _start_adventure(w, {}))
	grid.add_child(free)
	var stories: Array = w.get("stories") if w.get("stories") is Array else Rules.world_stories(wid)
	for st in stories:
		if st is Dictionary and str(st.get("title", "")) != "":
			var card := _big_card(str(st["title"]), str(st.get("premise", "")).left(110), Ui.pal["amethyst"])
			card.pressed.connect(func(): _start_adventure(w, st))
			grid.add_child(card)
	var craft := _big_card("Craft a campaign", "Tell the smith the story you want in this world.", Ui.pal["gold"])
	craft.pressed.connect(func(): _open_campaign_forge(w))
	grid.add_child(craft)
	_content.add_child(grid)
	if bool(w.get("custom", false)):
		var admin := HBoxContainer.new()
		admin.add_theme_constant_override("separation", 10)
		var exp := Button.new()
		exp.text = "Export world file"
		exp.pressed.connect(func():
			DirAccess.make_dir_recursive_absolute("user://exports")
			var path := "user://exports/%s.world.json" % wid
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify(w, "\t"))
			f.close()
			_sub_status.text = "Exported to %s" % ProjectSettings.globalize_path(path)
			OS.shell_open(ProjectSettings.globalize_path("user://exports")))
		var unmake := Button.new()
		unmake.text = "Unmake this world"
		unmake.pressed.connect(func():
			_cworlds = _cworlds.filter(func(cw): return str(cw.get("id", "")) != wid)
			GameState.global_set("cworlds", _cworlds)
			_show_worlds())
		admin.add_child(exp)
		admin.add_child(unmake)
		_content.add_child(admin)
	var cast: Array = w.get("cast") if w.get("cast") is Array else []
	if not cast.is_empty():
		_content.add_child(_section("THE CAST — sit with them one-on-one, no dice"))
		var cgrid := GridContainer.new()
		cgrid.columns = 3
		cgrid.add_theme_constant_override("h_separation", 14)
		cgrid.add_theme_constant_override("v_separation", 14)
		for c in cast:
			if c is Dictionary and str(c.get("name", "")) != "":
				var cc := _big_card(str(c["name"]), str(c.get("role", "")), Ui.pal["ink_soft"])
				cc.custom_minimum_size = Vector2(360, 84)
				cc.pressed.connect(func(): _chat_companion(w, c))
				cgrid.add_child(cc)
		_content.add_child(cgrid)


## A world you can read: tagline, lore, then its places and beasts named with
## their own lines. Kept compact — the full atlas lives in the World Forge.
func _world_reveal_text(w: Dictionary) -> String:
	var gold := Ui.c("gold_soft").to_html(false)
	var esc := func(s): return str(s).replace("[", "[lb]")
	var out := ""
	if str(w.get("tagline", "")) != "":
		out += "[i][color=%s]%s[/color][/i]\n\n" % [gold, esc.call(w.get("tagline", ""))]
	out += esc.call(w.get("lore", ""))
	var locs: Array = w.get("locations") if w.get("locations") is Array else []
	if not locs.is_empty():
		out += "\n\n[color=%s][b]Places[/b][/color]\n" % gold
		for l in locs.slice(0, 6):
			if l is Dictionary:
				var d := str(l.get("desc", l.get("blurb", "")))
				out += "• [b]%s[/b]%s\n" % [esc.call(l.get("name", "?")), (" — " + esc.call(d)) if d != "" else ""]
	var beasts: Array = w.get("creatures") if w.get("creatures") is Array else []
	if not beasts.is_empty():
		var names: Array = beasts.map(func(b): return esc.call(b.get("name", "?")) if b is Dictionary else esc.call(b))
		out += "\n[color=%s][b]Beasts[/b][/color] %s" % [gold, ", ".join(names)]
	return out


func _section(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "HintLabel"
	l.text = text
	return l


# ── Companions (title-screen entry: every non-DM persona) ────────────────────
func _show_companions() -> void:
	_show_sub("Companions", "A quiet table for two — no dice, just talk")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var any := false
	for c in _templates:
		var id := str(c.get("id", ""))
		if id.begins_with("dm-"):
			continue
		any = true
		var card := _big_card(str(c.get("name", "Unnamed")), str(c.get("relationship", c.get("world", ""))).left(60), Ui.pal["amethyst"])
		card.custom_minimum_size = Vector2(360, 84)
		card.pressed.connect(func(): _play({"id": id, "name": c.get("name", ""), "world_id": c.get("world_id", "")}))
		grid.add_child(card)
	if not any:
		_content.add_child(_section("No companions yet — meet a world's cast (New Adventure › a world › The Cast)."))
	_content.add_child(grid)


func _chat_companion(w: Dictionary, c: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	_sub_status.text = "Waking %s…" % str(c.get("name", ""))
	var wid := str(w.get("id", ""))
	var id := "wc-%s-%s" % [wid, str(c.get("slug", str(c.get("name", "")).to_lower().replace(" ", "-")))]
	await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/save", {
		"id": id, "name": str(c.get("name", "")),
		"personality": "%s\nThe world you live in: %s — %s" % [str(c.get("persona", "")), str(w.get("name", "")), str(w.get("lore", ""))],
		"relationship": str(c.get("role", "")),
		"world_id": wid,
	})
	_busy = false
	_play({"id": id, "name": c.get("name", ""), "world_id": wid})


# ── Settings ─────────────────────────────────────────────────────────────────
func _show_settings() -> void:
	Mode.enter("Settings")
	_show_sub("Settings", "")
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	_content.add_child(_section("GAME MASTER"))
	var model_in := OptionButton.new()
	model_in.custom_minimum_size = Vector2(420, 0)
	model_in.add_item("Auto — the fastest capable narrator")
	var picks: Array = []
	var mods := await Api.call_json(HTTPClient.METHOD_GET, "/api/models")
	for host in mods.get("items", []):
		for mn in host.get("models", []):
			picks.append({"url": str(host.get("url", "")), "model": str(mn)})
			model_in.add_item(str(mn))
	var saved_pick = JSON.parse_string(str(cfg.get_value("settings", "gm_model", "")))
	if saved_pick is Dictionary:
		for i in picks.size():
			if picks[i]["model"] == str(saved_pick.get("model", "")):
				model_in.selected = i + 1
	model_in.item_selected.connect(func(idx):
		_set_setting("gm_model", "" if idx == 0 else JSON.stringify(picks[idx - 1])))
	var model_hint := Label.new()
	model_hint.theme_type_variation = "HintLabel"
	model_hint.text = "The narrator's mind — applies to newly opened adventures. Auto keeps the biggest models out of the chair — they narrate no better and cost minutes a turn."
	_content.add_child(model_in)
	_content.add_child(model_hint)
	_content.add_child(_section("SOUND & MOTION"))
	var sfx := CheckButton.new()
	sfx.text = "Sound effects — dice, blows, stings, chimes"
	sfx.button_pressed = bool(cfg.get_value("settings", "sfx", true))
	sfx.toggled.connect(func(on): _set_setting("sfx", on); Sfx.enabled = on)
	_content.add_child(sfx)
	var amb := CheckButton.new()
	amb.text = "Ambient score — hearth drones, neon rain, war drums"
	amb.button_pressed = bool(cfg.get_value("settings", "ambient", true))
	var vol := HSlider.new()
	vol.min_value = 0.05
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(cfg.get_value("settings", "ambient_vol", 0.6))
	vol.custom_minimum_size = Vector2(320, 0)
	amb.toggled.connect(func(on): _set_setting("ambient", on); Sfx.set_ambient(on, vol.value))
	vol.value_changed.connect(func(v): _set_setting("ambient_vol", v); Sfx.set_ambient(amb.button_pressed, v))
	_content.add_child(amb)
	_content.add_child(vol)
	var motion := CheckButton.new()
	motion.text = "Reduce motion — calmer, fewer animations"
	motion.button_pressed = bool(cfg.get_value("settings", "reduce_motion", false))
	motion.toggled.connect(func(on): _set_setting("reduce_motion", on); Ui.reduce_motion = on)
	_content.add_child(motion)
	# R6 STR-24/25 — the only accessibility control was reduce-motion, while the
	# app lays body text over paintings in a dozen places, several of which
	# measured well under WCAG AA. This deepens every scrim and backing plate at
	# once (they all route through Ui). Takes effect on the next screen built.
	var contrast := CheckButton.new()
	contrast.text = "Higher contrast — darker panels behind text"
	contrast.button_pressed = bool(cfg.get_value("settings", "high_contrast", false))
	contrast.toggled.connect(func(on): _set_setting("high_contrast", on); Ui.high_contrast = on)
	_content.add_child(contrast)
	_content.add_child(_section("ACCOUNT"))
	var out := Button.new()
	out.text = "Sign out"
	out.custom_minimum_size = Vector2(240, 0)
	out.pressed.connect(func():
		await Api.call_json(HTTPClient.METHOD_POST, "/api/auth/logout")
		Api.cookie = ""
		Api._save_cookie()
		Ui.transition("res://scenes/login.tscn", get_tree()))
	_content.add_child(out)
	var ver := await Api.call_json(HTTPClient.METHOD_GET, "/api/version")
	_content.add_child(_section("Mythforge desktop · backend %s" % str(ver.get("version", ver.get("data", "?")))))


func _set_setting(key: String, val) -> void:
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	cfg.set_value("settings", key, val)
	cfg.save(Api.COOKIE_FILE)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	Sfx.enabled = bool(cfg.get_value("settings", "sfx", true))
	Sfx.ambient_enabled = bool(cfg.get_value("settings", "ambient", true))
	Sfx.ambient_volume = float(cfg.get_value("settings", "ambient_vol", 0.6))
	Ui.reduce_motion = bool(cfg.get_value("settings", "reduce_motion", false))
	Ui.high_contrast = bool(cfg.get_value("settings", "high_contrast", false))


# ── The World Forge (full-screen pillar, docs/forges — a realm of your own) ──
var _world_forge: Control = null
var _gm_forge: Control = null
var _persona_forge: Control = null


## The two persona pillars share one launcher shape: full-screen forge, kept
## hidden between visits so a half-finished draft survives, Hall on close.
func _open_gm_forge_pillar() -> void:
	_gm_forge = _open_minor_forge(_gm_forge, "res://scenes/forge/gm_forge.tscn")


func _open_persona_forge_pillar() -> void:
	_persona_forge = _open_minor_forge(_persona_forge, "res://scenes/forge/persona_forge.tscn")


func _open_minor_forge(inst: Control, path: String) -> Control:
	Mode.enter("CampaignForge")
	_title.visible = false
	_sub.visible = false
	if inst == null:
		inst = load(path).instantiate()
		inst.closed.connect(func():
			inst.visible = false
			Mode.enter("MainMenu")
			_show_title())
		add_child(inst)
	else:
		inst.visible = true
	Ui.polish(inst)
	return inst


func _open_world_forge_pillar() -> void:
	Mode.enter("CampaignForge")
	_title.visible = false
	_sub.visible = false
	if _world_forge == null:
		_world_forge = preload("res://scenes/forge/world_forge.tscn").instantiate()
		_world_forge.world_created.connect(func(world):
			_world_forge.visible = false
			Mode.enter("MainMenu")
			if not _cworlds.any(func(c): return str(c.get("id", "")) == str(world.get("id", ""))):
				_cworlds.append(world)
			_show_detail(world))
		_world_forge.closed.connect(func():
			_world_forge.visible = false
			Mode.enter("MainMenu")
			_show_title())
		add_child(_world_forge)
	else:
		_world_forge.visible = true
	Ui.polish(_world_forge)


## ⚒ The Campaign Forge pillar (docs/forges/CampaignForge.md) — the war
## table. The instance is kept (hidden) so a banked draft survives until
## the menu closes. On seal: the new world joins the gallery and opens.
var _forge_scene: Control = null


func _open_campaign_forge_pillar() -> void:
	Mode.enter("CampaignForge")
	_title.visible = false
	_sub.visible = false
	if _forge_scene == null:
		_forge_scene = preload("res://scenes/forge/campaign_forge.tscn").instantiate()
		_forge_scene.campaign_begun.connect(func(adv):
			_forge_scene.visible = false
			Mode.enter("MainMenu")
			_play(adv))
		_forge_scene.closed.connect(func():
			_forge_scene.visible = false
			_show_title())
		add_child(_forge_scene)
	else:
		_forge_scene.visible = true
	Ui.polish(_forge_scene)


## ⚔ The Character Forge pillar, from the menu: forge a legend as a DRAFT —
## banked to user://forged_hero.json; any new adventure offers them at the
## Quenching (walk the runes back to reshape, or begin at once).
var _char_forge: Control = null


func _open_character_forge_pillar() -> void:
	Mode.enter("CharacterForge")
	_title.visible = false
	_sub.visible = false
	if _char_forge == null:
		_char_forge = preload("res://scenes/forge/character_forge.tscn").instantiate()
		_char_forge.menu_mode = true
		_char_forge.hero_forged.connect(func(d):
			GameState.bank_hero(d)
			_char_forge.visible = false
			Mode.enter("MainMenu")
			_show_title()
			_refresh_hero_count()
			$Title/Box/Status.text = "%s rests at the anvil — begin any adventure to play them." % str(d.get("name", "The legend")))
		_char_forge.closed.connect(func():
			_char_forge.visible = false
			Mode.enter("MainMenu")
			_show_title())
		add_child(_char_forge)
	else:
		_char_forge.visible = true
	Ui.polish(_char_forge)


# ── Campaign smith (worldsmith mode=story, per-world craft) ──────────────────
func _open_campaign_forge(w: Dictionary) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "✦ Craft a campaign — %s" % str(w.get("name", ""))
	dlg.ok_button_text = "✦ Draft it"
	dlg.min_size = Vector2i(560, 220)
	var idea := TextEdit.new()
	idea.placeholder_text = "e.g. I want to infiltrate the Thorn Court masquerade and steal back a stolen name…"
	idea.custom_minimum_size = Vector2(520, 100)
	dlg.add_child(idea)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		var txt := idea.text.strip_edges()
		dlg.queue_free()
		if txt == "":
			return
		_busy = true
		_sub_status.text = "✦ Drafting the campaign…"
		var r := await Api.worldsmith({
			"idea": txt, "mode": "story",
			"world": {"name": w.get("name", ""), "kind": w.get("kind", ""), "lore": w.get("lore", "")}})
		_busy = false
		_sub_status.text = ""
		if r.get("_status", 0) != 200 or str(r.get("title", "")) == "":
			_sub_status.text = "The smith lost the thread — try again."
			return
		var story := {"slug": str(r["title"]).to_lower().replace(" ", "-").left(24),
			"title": r["title"], "premise": r.get("premise", ""), "hook": r.get("hook", "")}
		# Graft onto the world so it shows as a card from now on.
		if bool(w.get("custom", false)):
			var ws: Array = w.get("stories") if w.get("stories") is Array else []
			ws.append(story)
			w["stories"] = ws
			GameState.global_set("cworlds", _cworlds)
		_start_adventure(w, story))


# ── Play ─────────────────────────────────────────────────────────────────────
func _start_adventure(w: Dictionary, story: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var wid := str(w.get("id", ""))
	var adv_id := Rules.adventure_id(wid, story)
	var name := str(story.get("title", "")) if not story.is_empty() else "%s: Free Roam" % str(w.get("name", ""))
	_sub_status.text = "Opening %s…" % name
	var full := w.duplicate(true)
	if not (full.get("locations") is Array) or full.get("locations", []).is_empty():
		full["locations"] = Rules.world_locations(wid)
	await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/save", {
		"id": adv_id, "name": name,
		"personality": Composer.compose_world_gm(full, story),
		"relationship": "Dungeon Master", "world_id": wid,
	})
	await _seed_forge_defaults(w, adv_id)
	_busy = false
	var adv := {"id": adv_id, "name": name, "world_id": wid}
	# A live save already? Continue it or start over (archive + wipe).
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	var sid := str(cfg.get_value("sessions", str(adv["id"]), ""))
	if sid != "" and (await Api.call_json(HTTPClient.METHOD_GET, "/api/history/" + sid)).get("_status", 0) == 200:
		_ask_continue_or_new(adv, sid)
	else:
		_play(adv)


## The forge's voice and table rules seed every adventure begun in a forged
## world — including fresh starts after a reset.
func _seed_forge_defaults(w: Dictionary, adv_id: String) -> void:
	var fd: Dictionary = w.get("forge_defaults") if w.get("forge_defaults") is Dictionary else {}
	if fd.is_empty():
		return
	if fd.get("gm") is Dictionary and not fd["gm"].is_empty():
		GameState.set_kind_for(adv_id, "gm", fd["gm"])
	if fd.get("rules") is Dictionary and not fd["rules"].is_empty():
		GameState.set_kind_for(adv_id, "world", {"rules": fd["rules"]})


func _ask_continue_or_new(adv: Dictionary, sid: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = str(adv.get("name", "This adventure"))
	dlg.ok_button_text = "▶ Continue"
	dlg.get_cancel_button().text = "↻ New game"
	var note := Label.new()
	note.theme_type_variation = "HintLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	note.text = "A new game starts this adventure over — your sheet, pack, gold, and progress here are reset (the old save is archived). Your other adventures are untouched."
	dlg.add_child(note)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func(): dlg.queue_free(); _play(adv))
	dlg.canceled.connect(func():
		dlg.queue_free()
		await Api.call_json(HTTPClient.METHOD_POST, "/api/session/%s/archive" % sid)
		var cfg := ConfigFile.new()
		cfg.load(Api.COOKIE_FILE)
		cfg.set_value("sessions", str(adv["id"]), null)
		cfg.save(Api.COOKIE_FILE)
		# Reset this adventure's world-state so the hero forge runs fresh.
		GameState.wipe_adventure(str(adv["id"]))
		# A forged world's voice and rules survive the reset.
		await _seed_forge_defaults(_world_by_id(str(adv.get("world_id", ""))), str(adv["id"]))
		_play(adv))


func _continue_last() -> void:
	# Several live adventures → the save-file screen; one → straight in.
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	var saved: Array = []
	if cfg.has_section("sessions"):
		for cid in cfg.get_section_keys("sessions"):
			for t in _templates:
				if str(t.get("id")) == cid and cid.begins_with("dm-"):
					saved.append(t)
	if saved.size() <= 1:
		_play(_btn_continue.get_meta("char"))
		return
	_show_saves(saved)


## Chronicles: every begun tale as an illustrated cover card — take up the
## thread (Continue, folded in here) or open its Lore Book from the Hall.
func _show_saves(saved: Array) -> void:
	_show_sub("Chronicles", "Every tale you've begun — take up the thread, or open its book")
	var cfg := ConfigFile.new()
	cfg.load(Api.COOKIE_FILE)
	var last = JSON.parse_string(str(cfg.get_value("last", "adventure", "")))
	var last_id := str(last.get("id", "")) if last is Dictionary else ""
	if saved.is_empty():
		_content.add_child(_section("No chronicles yet — begin an adventure and its story is kept here."))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_content.add_child(grid)
	# Build every card synchronously and fire its state fetch WITHOUT awaiting, so
	# all fetches run concurrently (was serial: N round-trips back-to-back). Each
	# card fills its own caption when its fetch lands. (B1)
	for t in saved:
		grid.add_child(_chronicle_card(t, last_id))


func _chronicle_card(t: Dictionary, last_id: String) -> Control:
	var cid := str(t.get("id"))
	var wid := str(t.get("world_id", ""))
	var is_last := cid == last_id
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 172)
	panel.add_theme_stylebox_override("panel", Ui.sb_card("legendary" if is_last else "common"))
	panel.clip_contents = true
	var tex := Art.texture_for(wid)
	if tex != null:  # the world's key art is the cover
		var art := TextureRect.new()
		art.texture = tex
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.62, 0.6, 0.68, 0.6)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(art)
		var scrim := ColorRect.new()
		scrim.color = Color(Ui.c("night"), 0.45)
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(scrim)
	var mar := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mar.add_theme_constant_override(m, 16)
	panel.add_child(mar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	mar.add_child(box)
	var nm := Label.new()
	nm.text = str(t.get("name", "?"))
	nm.add_theme_font_override("font", Ui.serif)
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Ui.c("gold_soft") if is_last else Ui.c("ink"))
	box.add_child(nm)
	var cap := Label.new()
	cap.theme_type_variation = "HintLabel"
	cap.text = "opening the chronicle…" + ("   ·   latest" if is_last else "")
	box.add_child(cap)
	_fill_card_caption(cap, cid, is_last)  # concurrent fetch; fills when it lands
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var cont := Button.new()
	cont.theme_type_variation = "AccentButton"
	cont.text = "▶ Continue"
	cont.pressed.connect(func(): _play({"id": cid, "name": t.get("name", ""), "world_id": wid}))
	var chron := Button.new()
	chron.theme_type_variation = "GhostButton"
	chron.text = "Open the Lore Book"
	chron.pressed.connect(func(): _open_campaign_chronicle(t))
	actions.add_child(cont)
	actions.add_child(chron)
	box.add_child(actions)
	return panel


## Fetch one chronicle's state and fill its caption. Called fire-and-forget so
## every card's fetch is in flight at once rather than serialized. (B1)
func _fill_card_caption(cap: Label, cid: String, is_last: bool) -> void:
	var state = GameState.state_for(cid)
	if not is_instance_valid(cap):
		return  # the Chronicles view was closed before the read landed
	var sheet: Dictionary = state.get("sheet", {}) if state is Dictionary and state.get("sheet") is Dictionary else {}
	var clock: Dictionary = state.get("clock", {}) if state is Dictionary and state.get("clock") is Dictionary else {}
	var tail := "   ·   ✦ complete" if clock.get("done", false) else ("   ·   latest" if is_last else "")
	cap.text = "%s · Level %d · Day %d%s" % [str(sheet.get("name", "a new hero")), int(sheet.get("level", 1)),
		int(clock.get("day", 1)), tail]


## Open a campaign's Lore Book from the Hall: load its state read-only, theme
## the Hall to its world, show the book, and restore the Hall on close.
func _open_campaign_chronicle(t: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	_sub_status.text = "Opening the chronicle…"
	GameState.character = {"id": t.get("id"), "name": t.get("name", ""), "world_id": t.get("world_id", "")}
	await GameState.hydrate()
	WorldSkin.remember(_world_by_id(str(t.get("world_id", ""))))
	Ui.apply(str(t.get("world_id", "")))
	_busy = false
	_sub_status.text = ""
	var book := preload("res://scenes/ui/lore_book.tscn").instantiate()
	book.closed.connect(func(): Ui.apply(""))  # restore the Hall's own theme
	add_child(book)
	Ui.reveal(book)


func _play(c: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	Mode.enter("Loading")
	GameState.character = c
	Ui.apply(str(c.get("world_id", "")))
	# MIL §7 — the curtain goes up BEFORE the work, and survives the scene
	# change beneath it: one continuous composed frame, never a hard cut into
	# a half-built play screen.
	var curtain := MythLoading.begin(get_tree(), str(c.get("world_id", "")),
		str(c.get("name", "")).split(":")[0])
	Sfx.music(WorldSkin.music_for_id(str(c.get("world_id", ""))))  # sound arrives before picture
	curtain.step(0.15, "Opening the way…")
	GameState.session_id = await Api.ensure_session(str(c.get("id", "")), str(c.get("name", "")))
	if GameState.session_id == "":
		# The realm faltered — say so in the world's voice, and go back gently.
		curtain.step(1.0, "The way will not open — no storyteller answered.")
		MythLoading.lift()
		var status := _sub_status if _sub.visible else $Title/Box/Status
		status.text = "No storyteller answered. Check that a chat model endpoint is configured, then try again."
		Ui.apply("")
		Mode.enter("MainMenu")
		_busy = false
		return
	curtain.step(0.4, "Waking the world…")
	if str(c.get("id", "")).begins_with("dm-"):
		var cfg := ConfigFile.new()
		cfg.load(Api.COOKIE_FILE)
		cfg.set_value("last", "adventure", JSON.stringify({"id": c.get("id"), "name": c.get("name"), "world_id": c.get("world_id", "")}))
		cfg.save(Api.COOKIE_FILE)
	get_tree().change_scene_to_file(GAME_SCENE)  # under the curtain — game.gd lifts it

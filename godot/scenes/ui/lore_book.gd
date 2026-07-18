extends Control
## The Lore Book (Sprint M-C, Issues 1+3) — a fully illustrated encyclopedia
## that writes itself. It aggregates what the game already knows — the world's
## places, cast, bestiary, campaigns, the quests you've sworn, the chapters
## you've closed — into a paginated book, and paints any missing art on demand
## (skin-styled via the World Skin). Opened in play as the world's codex, and
## from the Hall's Chronicles as a campaign's history.

signal closed

const CATS := ["Places", "The Cast", "Bestiary", "Campaigns", "Discoveries", "Quests", "Chronicle"]

var _world := {}
var _host: VBoxContainer
var _tabs := {}
var _active := "Places"
var _art_targets := {}   # art key → [TextureRect…] awaiting the paint
var _title_l: Label


func _ready() -> void:
	theme = Ui.theme
	MythEnvironment.mount(self, "env-journal", "dust", [Vector2(0.12, 0.86), Vector2(0.88, 0.86)])
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, Ui.SPACE["xl"] * 2)
	margin.add_theme_constant_override("margin_top", Ui.SPACE["l"])
	margin.add_theme_constant_override("margin_bottom", Ui.SPACE["l"])
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	margin.add_child(col)
	# Header: the book's title + the way out.
	var head := HBoxContainer.new()
	_title_l = Label.new()
	_title_l.theme_type_variation = "TitleLabel"
	_title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_l.text = "The Lore Book"
	head.add_child(_title_l)
	var close := Button.new()
	close.theme_type_variation = "GhostButton"
	close.text = "Close the book"
	close.pressed.connect(func(): closed.emit(); queue_free())
	head.add_child(close)
	col.add_child(head)
	# The category rail.
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", Ui.SPACE["xs"])
	for cat in CATS:
		var b := Button.new()
		b.text = cat
		b.custom_minimum_size = Vector2(140, 40)
		b.pressed.connect(_show_cat.bind(cat))
		_tabs[cat] = b
		rail.add_child(b)
	col.add_child(rail)
	var line := ColorRect.new()
	line.color = Color(Ui.c("border"), 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	col.add_child(line)
	# The pages.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_host = VBoxContainer.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.add_theme_constant_override("separation", Ui.SPACE["m"])
	scroll.add_child(_host)
	col.add_child(scroll)
	Art.art_ready.connect(_on_art)
	await _load_world()
	_title_l.text = "The Lore of %s" % str(_world.get("name", GameState.character.get("world_id", "the world"))).capitalize()
	_show_cat(_active)


func _load_world() -> void:
	var wid := GameState.world_id()
	for w in Rules.builtin_worlds():
		if str(w.get("id", "")) == wid:
			_world = w
			return
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	var cw: Array = g.get("state", {}).get("cworlds", []) if g.get("state") is Dictionary and g["state"].get("cworlds") is Array else []
	for w in cw:
		if w is Dictionary and str(w.get("id", "")) == wid:
			_world = w
			return


func _show_cat(cat: String) -> void:
	_active = cat
	for k in _tabs:
		_style_tab(_tabs[k], k == cat)
	for ch in _host.get_children():
		ch.queue_free()
	match cat:
		"Places":
			_places()
		"The Cast":
			_cast()
		"Bestiary":
			_bestiary()
		"Campaigns":
			_campaigns()
		"Discoveries":
			_discoveries()
		"Quests":
			_quests()
		"Chronicle":
			await _chronicle()
	if _host.get_child_count() == 0:
		_host.add_child(_empty("These pages are still blank — they fill as you explore, meet, fight, and remember."))
	Ui.reveal_children(_host, 0.03)


func _style_tab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(Ui.SPACE["s"])
	sb.corner_radius_top_left = Ui.RADIUS["m"]
	sb.corner_radius_top_right = Ui.RADIUS["m"]
	sb.bg_color = Color(Ui.c("surface2"), 0.85) if active else Color(Ui.c("surface"), 0.0)
	if active:
		sb.border_width_bottom = 2
		sb.border_color = Ui.c("gold")
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_color_override("font_color", Ui.c("gold") if active else Ui.c("ink_dim"))


# ── Category builders ────────────────────────────────────────────────────────
func _places() -> void:
	var locs: Array = _world.get("locations") if _world.get("locations") is Array else Rules.world_locations(GameState.world_id())
	for l in locs:
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", "?"))
		var key := "map-" + nm.to_lower().replace(" ", "-").validate_filename()
		var body := str(l.get("desc", l.get("lore", l.get("blurb", ""))))
		var kind := str(l.get("kind", ""))
		_host.add_child(_entry(nm, (("[i]%s[/i]\n" % kind) if kind != "" else "") + body, key,
			"top-down illustrated map vignette of %s, %s, painted, no text" % [nm, Art.world_flavor()]))


func _cast() -> void:
	var seen := {}
	for c in (_world.get("cast") if _world.get("cast") is Array else []):
		if c is Dictionary and str(c.get("name", "")) != "":
			var nm := str(c["name"])
			seen[nm.to_lower()] = true
			var key := "npc-" + nm.to_lower().replace(" ", "-")
			_host.add_child(_entry(nm, str(c.get("role", "")) + ("\n" + str(c.get("persona", "")) if str(c.get("persona", "")) != "" else ""),
				key, "character portrait of %s, %s, %s, dramatic rim light, dark background, no text" % [nm, str(c.get("role", "a figure of this world")), Art.world_flavor()]))
	# The cast you've actually met (codex), beyond the world's authored roster.
	for n in (GameState.state.get("codex") if GameState.state.get("codex") is Array else []):
		if n is Dictionary and str(n.get("name", "")) != "" and not seen.has(str(n["name"]).to_lower()):
			var nm2 := str(n["name"])
			var key2 := "npc-" + nm2.to_lower().replace(" ", "-")
			_host.add_child(_entry(nm2, str(n.get("role", "")) + ("\n" + str(n.get("note", "")) if str(n.get("note", "")) != "" else ""), key2, ""))


func _bestiary() -> void:
	for b in (_world.get("creatures") if _world.get("creatures") is Array else []):
		if not (b is Dictionary):
			continue
		var nm := str(b.get("name", "?"))
		var slug := str(b.get("slug", nm.to_lower().replace(" ", "-")))
		_host.add_child(_entry(nm, str(b.get("desc", b.get("art", ""))), "beast-" + slug,
			str(b.get("art", "a %s" % nm)) + ", painted creature portrait, dark background, no text"))


func _campaigns() -> void:
	for st in (_world.get("stories") if _world.get("stories") is Array else Rules.world_stories(GameState.world_id())):
		if st is Dictionary and str(st.get("title", "")) != "":
			_host.add_child(_entry(str(st["title"]), str(st.get("premise", "")) + ("\n\n[i]" + str(st.get("hook", "")) + "[/i]" if str(st.get("hook", "")) != "" else ""), "", ""))


func _discoveries() -> void:
	var lore = GameState.state.get("lore")
	var entries: Array = lore.get("entries", []) if lore is Dictionary else []
	for e in entries:
		if e is Dictionary and str(e.get("title", "")) != "":
			_host.add_child(_entry(str(e["title"]),
				"[i]%s · day %d[/i]\n%s" % [str(e.get("category", "")), int(e.get("day", 1)), str(e.get("note", ""))], "", ""))


func _quests() -> void:
	for q in (GameState.state.get("quests") if GameState.state.get("quests") is Array else []):
		if q is Dictionary and str(q.get("title", "")) != "":
			var done := str(q.get("status", "active")) == "done"
			_host.add_child(_entry(("✓ " if done else "◈ ") + str(q["title"]), str(q.get("desc", "")), "", ""))


func _chronicle() -> void:
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/snapshots?character_id=" + GameState.cid().uri_encode())
	for sn in r.get("snapshots", r.get("data", [])):
		if sn is Dictionary:
			_host.add_child(_entry(str(sn.get("title", "A chapter")), str(sn.get("summary", sn.get("text", ""))), "", ""))


# ── One illustrated entry ────────────────────────────────────────────────────
func _entry(title: String, body: String, art_key := "", ensure_prompt := "") -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.sb_card())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Ui.SPACE["m"])
	if art_key != "":
		var art := TextureRect.new()
		art.custom_minimum_size = Vector2(150, 150)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.clip_contents = true
		var tex := Art.round_tex(art_key, 150) if art_key.begins_with("npc-") or art_key.begins_with("beast-") else Art.texture_for(art_key)
		if tex != null:
			art.texture = tex
		elif ensure_prompt != "":
			if not _art_targets.has(art_key):
				_art_targets[art_key] = []
			_art_targets[art_key].append(art)
			Art.ensure(art_key, ensure_prompt)
		row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.theme_type_variation = "HeaderLabel"
	t.text = title
	text.add_child(t)
	if body.strip_edges() != "":
		var b := RichTextLabel.new()
		b.bbcode_enabled = true
		b.fit_content = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("default_color", Ui.c("ink_soft"))
		b.text = body.replace("[", "[lb]").replace("[lb]i]", "[i]").replace("[lb]/i]", "[/i]")
		text.add_child(b)
	row.add_child(text)
	panel.add_child(row)
	return panel


func _empty(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "HintLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	return l


func _on_art(key: String) -> void:
	if not _art_targets.has(key):
		return
	for tr in _art_targets[key]:
		if is_instance_valid(tr):
			tr.texture = Art.round_tex(key, 150) if key.begins_with("npc-") or key.begins_with("beast-") else Art.texture_for(key)
			Ui.pulse(tr)
	_art_targets.erase(key)

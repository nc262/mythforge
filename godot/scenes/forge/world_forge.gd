extends ForgeFlow
## The World Forge — a permanent pillar, equal to the Character and Campaign
## forges. Not a dialog: a full-screen staged ritual at the smith's table
## where a WORLD is struck from an idea, revealed in vivid detail, and sealed
## into the gallery. Spark → Pillars → Forging (smith strike + refine) →
## the Atlas (a full world reveal). This node IS the WorldForgeManager.
## Scaffold (rail/stage box/nav/status) lives in ForgeFlow; this is stages only.

signal world_created(world: Dictionary)

const STAGES := ["The Spark", "The Pillars", "The Forging", "The Atlas"]
## Theme cards → worldsmith pillar presets + an idea seasoning line.
const THEMES := [
	{"glyph": "🌑", "title": "Dark Fantasy", "body": "grim roads, costly magic", "idea": "a grim dark-fantasy land where hope is scarce currency",
		"fields": {"Magic system": "Forbidden & feared", "Technology": "Medieval", "Era & timeline": "After the cataclysm", "Beast variants": "Corrupted wildlife", "Tone": "Grim & gritty"}},
	{"glyph": "🏔", "title": "High Fantasy", "body": "bright banners, old dragons", "idea": "a sweeping high-fantasy realm of banners, prophecy, and dragonfire",
		"fields": {"Magic system": "Elemental pacts", "Technology": "Medieval", "Era & timeline": "A golden age fading", "Beast variants": "Dragons & their kin", "Tone": "Heroic & bright"}},
	{"glyph": "🕯", "title": "Horror", "body": "creeping dread, thin walls", "idea": "a horror world of creeping dread where the dark has patience",
		"fields": {"Magic system": "Forbidden & feared", "Technology": "Medieval", "Era & timeline": "Under occupation", "Beast variants": "Spirits & shades", "Tone": "Noir & conspiratorial"}},
	{"glyph": "🗡", "title": "Intrigue", "body": "courts, daggers, debts", "idea": "a web of courts and conspiracies where words kill quicker than blades",
		"fields": {"Magic system": "Divine bargains", "Technology": "Medieval", "Era & timeline": "A long peace cracking", "Beast variants": "Ancient constructs", "Tone": "Noir & conspiratorial"}},
	{"glyph": "🪓", "title": "Norse", "body": "fjords, runes, ravens", "idea": "a norse saga of fjords, rune-speakers, and the long winter coming",
		"fields": {"Magic system": "Wild & untamed", "Technology": "Medieval", "Era & timeline": "After the cataclysm", "Beast variants": "Dragons & their kin", "Tone": "Grim & gritty"}},
	{"glyph": "⚓", "title": "Pirates", "body": "salt, powder, charts", "idea": "an age-of-sail world of pirate havens, sea monsters, and buried charts",
		"fields": {"Magic system": "Elemental pacts", "Technology": "Age of sail & gunpowder", "Era & timeline": "Frontier boom", "Beast variants": "Sea leviathans & drowned things", "Tone": "Heroic & bright"}},
	{"glyph": "⚙", "title": "Steampunk", "body": "brass, soot, wonder", "idea": "a steam-and-clockwork world of brass towers, soot, and impossible machines",
		"fields": {"Magic system": "Tech-grafted mods", "Technology": "Steam & clockwork", "Era & timeline": "A golden age fading", "Beast variants": "Ancient constructs", "Tone": "Whimsical"}},
	{"glyph": "🛰", "title": "Sci-Fi", "body": "stars, salvage, neon", "idea": "a starfaring frontier of salvage crews, neon ports, and cold void",
		"fields": {"Magic system": "Tech-grafted mods", "Technology": "Starfaring", "Era & timeline": "Frontier boom", "Beast variants": "Bio-engineered horrors", "Tone": "Noir & conspiratorial"}},
]

const Card := preload("res://ui/myth_choice_card.gd")
const Fold := preload("res://ui/myth_fold.gd")

var draft := {"name": "", "idea": "", "theme": {}, "fields": {}}
var _forged: Dictionary = {}   # the smith's latest take, pre-seal
var _sealed: Dictionary = {}   # the world after the wax came down


func _stages() -> Array:
	return STAGES


## Fallback atmosphere while the painted war room is still on the easel.
func _draw() -> void:
	if Art.has_art("env-wartable"):
		return
	draw_rect(Rect2(Vector2.ZERO, size), Ui.c("night").darkened(0.25))
	for i in 60:
		var h1 := absf(fmod(sin(i * 127.1) * 43758.5453, 1.0))
		var h2 := absf(fmod(sin(i * 311.7) * 12543.8367, 1.0))
		draw_circle(Vector2(h1 * size.x, h2 * size.y * 0.4), 0.9, Color(Ui.c("ink_soft"), 0.2))


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_spark()
		1:
			_stage_pillars()
		2:
			_stage_forging()
		3:
			_stage_atlas()


# ── Stage 0: the spark ───────────────────────────────────────────────────────
func _stage_spark() -> void:
	_title_label("The Spark")
	var line := Label.new()
	line.theme_type_variation = "HintLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.text = "Every world begins as one idea, spoken into the dark."
	_stage_box.add_child(line)
	var name_in := LineEdit.new()
	name_in.placeholder_text = "A name, if you have one — or leave blank and let the world name itself"
	name_in.text = str(draft["name"])
	name_in.custom_minimum_size = Vector2(560, 0)
	var nc := CenterContainer.new()
	nc.add_child(name_in)
	_stage_box.add_child(nc)
	var idea := TextEdit.new()
	idea.placeholder_text = "e.g. A drowned Venice of sky-whales and salvage guilds, melancholy but hopeful…"
	idea.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	idea.custom_minimum_size = Vector2(560, 84)
	idea.text = str(draft["idea"])
	var ic := CenterContainer.new()
	ic.add_child(idea)
	_stage_box.add_child(ic)
	_nav(-1, "To the pillars ›", func():
		draft["name"] = name_in.text.strip_edges()
		draft["idea"] = idea.text.strip_edges()
		_enter_stage(1))


# ── Stage 1: the pillars ─────────────────────────────────────────────────────
func _stage_pillars() -> void:
	_title_label("Raise the Pillars")
	var cards: Array = []
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for t in THEMES:
		var card := Card.new(t)
		card.set_selected(str(draft["theme"].get("title", "")) == str(t["title"]))
		card.pressed.connect(func():
			draft["theme"] = t
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		grid.add_child(card)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_stage_box.add_child(gc)
	# Advanced: the five pillars, written by hand — overrides the theme.
	var adv := Fold.new("Advanced: shape the five pillars by hand", not draft["fields"].is_empty())
	var pillar_inputs := {}
	for pillar in _smith_guide():
		var lbl := Label.new()
		lbl.theme_type_variation = "HintLabel"
		lbl.text = str(pillar[0])
		adv.content.add_child(lbl)
		var pin := LineEdit.new()
		pin.text = str(draft["fields"].get(pillar[0], ""))
		pin.placeholder_text = "anything you like — or tap a suggestion"
		adv.content.add_child(pin)
		var chips := HFlowContainer.new()
		for sug in pillar[1]:
			var chip := Button.new()
			chip.theme_type_variation = "GhostButton"
			chip.text = str(sug)
			chip.add_theme_font_size_override("font_size", 12)
			chip.pressed.connect(func(): pin.text = str(sug))
			chips.add_child(chip)
		adv.content.add_child(chips)
		pillar_inputs[pillar[0]] = pin
	var ac := CenterContainer.new()
	ac.add_child(adv)
	_stage_box.add_child(ac)
	_nav(0, "Strike the world ›", func():
		draft["fields"] = {}
		for k in pillar_inputs:
			var v: String = pillar_inputs[k].text.strip_edges()
			if v != "":
				draft["fields"][k] = v
		if draft["theme"].is_empty() and str(draft["idea"]) == "" and draft["fields"].is_empty():
			_status.text = "Choose a pillar-theme, write an idea, or shape the pillars by hand."
			return
		_forged = {}
		_enter_stage(2))


func _smith_guide() -> Array:
	return [
		["Magic system", ["Forbidden & feared", "Elemental pacts", "Tech-grafted mods", "Divine bargains", "Wild & untamed", "None — mundane grit"]],
		["Technology", ["Medieval", "Steam & clockwork", "Modern day", "Neon cyberpunk", "Starfaring"]],
		["Era & timeline", ["A golden age fading", "After the cataclysm", "Frontier boom", "A long peace cracking", "Under occupation"]],
		["Beast variants", ["Corrupted wildlife", "Ancient constructs", "Spirits & shades", "Bio-engineered horrors", "Dragons & their kin"]],
		["Tone", ["Grim & gritty", "Heroic & bright", "Whimsical", "Noir & conspiratorial"]],
	]


# ── Stage 2: the forging (smith strike + refine loop + seal) ─────────────────
func _stage_forging() -> void:
	_title_label("The Forging")
	if _forged.is_empty():
		_strike("")
		return
	_show_take()


func _strike(refine: String) -> void:
	_clear_stage()
	_title_label("The Forging")
	_busy = true
	var wait := Label.new()
	wait.theme_type_variation = "HintLabel"
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.text = "The smith works — the world takes shape (about a minute)…"
	_stage_box.add_child(wait)
	var t: Dictionary = draft["theme"]
	var idea := str(draft["idea"])
	if idea == "":
		idea = str(t.get("idea", "a world built from these pillars"))
	if str(draft["name"]) != "":
		idea += ". The world is named \"%s\" — let it suit the name" % str(draft["name"])
	var fields: Dictionary = {}
	for k in t.get("fields", {}):
		fields[k] = t["fields"][k]
	for k in draft["fields"]:
		fields[k] = draft["fields"][k]
	var payload := {"idea": refine if refine != "" else idea, "mode": "world", "fields": fields}
	if refine != "" and not _forged.is_empty():
		payload["prior"] = _forged
	var w := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/worldsmith", payload)
	_busy = false
	if w.get("_status", 0) != 200 or str(w.get("name", "")) == "":
		_status.text = "The forge sputtered (%s) — strike again." % str(w.get("_status", 0))
		_forged = {}
		_enter_stage(1)
		return
	_status.text = ""
	_forged = w
	_enter_stage(2)


func _show_take() -> void:
	var w := _forged
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(640, 0)
	var casts: Array = w.get("cast") if w.get("cast") is Array else []
	var locs: Array = w.get("locations") if w.get("locations") is Array else []
	var beasts: Array = w.get("creatures") if w.get("creatures") is Array else []
	body.append_text("[center][color=%s][font_size=20][b]%s[/b][/font_size][/color]  ·  %s[/center]\n[i]%s[/i]\n\n%s\n\n[b]Places:[/b] %s\n[b]The cast:[/b] %s\n[b]Beasts:[/b] %d threats bred for this world" % [
		Ui.c("gold_soft").to_html(false), _esc(str(w.get("name", "?"))), _esc(str(w.get("kind", ""))),
		_esc(str(w.get("tagline", ""))), _esc(str(w.get("lore", ""))),
		", ".join(locs.map(func(l): return _esc(str(l.get("name", "?"))))),
		", ".join(casts.map(func(c): return _esc(str(c.get("name", "?"))))), beasts.size()])
	var bs := ScrollContainer.new()
	bs.custom_minimum_size = Vector2(660, 260)
	bs.add_child(body)
	var bc := CenterContainer.new()
	bc.add_child(bs)
	_stage_box.add_child(bc)
	var refine := LineEdit.new()
	refine.placeholder_text = "What should change? darker tone, a pirate faction, rename it…"
	refine.custom_minimum_size = Vector2(540, 0)
	var rc := CenterContainer.new()
	rc.add_child(refine)
	_stage_box.add_child(rc)
	refine.text_submitted.connect(func(txt):
		if txt.strip_edges() != "":
			_strike(txt.strip_edges()))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	var again := Button.new()
	again.theme_type_variation = "GhostButton"
	again.text = "↻ Another take"
	again.pressed.connect(func():
		_forged = {}
		_strike(""))
	row.add_child(again)
	var seal := Button.new()
	seal.theme_type_variation = "AccentButton"
	seal.text = "Seal this world ›"
	seal.pressed.connect(_seal)
	row.add_child(seal)
	var back := Button.new()
	back.theme_type_variation = "GhostButton"
	back.text = "‹ the pillars"
	back.pressed.connect(func(): _enter_stage(1))
	row.add_child(back)
	_stage_box.add_child(row)


func _seal() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Pressing the seal — binding the world…"
	var w := _forged
	var wid := "cw-%s-%04x" % [str(w["name"]).to_lower().replace(" ", "-").left(20), randi() % 65536]
	var world := {"id": wid, "custom": true}
	for k in ["name", "kind", "tagline", "lore", "backdrop", "locations", "cast", "stories", "creatures"]:
		world[k] = w.get(k)
	world["skin_family"] = WorldSkin.family_of(world)  # freeze its visual language, travels with the world
	WorldSkin.remember(world)
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	var cworlds: Array = g.get("state", {}).get("cworlds", []) if g.get("state") is Dictionary and g["state"].get("cworlds") is Array else []
	cworlds.append(world)
	await Api.call_json(HTTPClient.METHOD_PUT, "/api/characters/studio/state/_global/cworlds", {"value": cworlds})
	_sealed = world
	Art.ensure(wid, str(world.get("backdrop", "")))
	# Compile the world's SEED — its Style Guide + Asset Language. Text only,
	# ~40s, no GPU; it is what every later stage (and every image) consults, so
	# it is laid down the moment the world is bound. (docs/WorldCompiler.md)
	_status.text = "Compiling the world — reading its own mind…"
	Compiler.stage_started.connect(func(_s, human): _status.text = human)
	await Compiler.compile_seed(world)
	_busy = false
	_status.text = ""
	Sfx.play("sting")
	_enter_stage(3)


# ── Stage 3: the Atlas — the world revealed in full, vivid detail ───────────
func _stage_atlas() -> void:
	var w := _sealed
	if w.is_empty():
		_enter_stage(2)
		return
	_title_label("The Atlas")
	# The world's painted sky, as it dries.
	var sky := TextureRect.new()
	sky.custom_minimum_size = Vector2(680, 190)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.texture = Art.texture_for(str(w.get("id", "")))
	Art.art_ready.connect(func(k):
		if str(k) == str(w.get("id", "")) and is_instance_valid(sky):
			sky.texture = Art.texture_for(str(k)))
	var skc := CenterContainer.new()
	skc.add_child(sky)
	_stage_box.add_child(skc)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(700, 0)
	body.append_text(_world_dossier(w))
	var bs := ScrollContainer.new()
	bs.custom_minimum_size = Vector2(720, 300)
	bs.add_child(body)
	var bc := CenterContainer.new()
	bc.add_child(bs)
	_stage_box.add_child(bc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	var refine := Button.new()
	refine.theme_type_variation = "GhostButton"
	refine.text = "↻ Re-forge the world"
	refine.pressed.connect(func():
		_forged = {}
		_enter_stage(2))
	row.add_child(refine)
	var enter := Button.new()
	enter.theme_type_variation = "AccentButton"
	enter.text = "Into the gallery ›"
	enter.pressed.connect(func(): world_created.emit(_sealed))
	row.add_child(enter)
	_stage_box.add_child(row)


## The vivid dossier: lore, then every place, face, beast and campaign with
## its own line — a world you can read, not a name you have to imagine (#6).
func _world_dossier(w: Dictionary) -> String:
	var gold := Ui.c("gold_soft").to_html(false)
	var out := "[center][font_size=22][color=%s][b]%s[/b][/color][/font_size]  ·  %s\n[i]%s[/i][/center]\n\n%s\n" % [
		gold, _esc(str(w.get("name", "?"))), _esc(str(w.get("kind", ""))),
		_esc(str(w.get("tagline", ""))), _esc(str(w.get("lore", "")))]
	var locs: Array = w.get("locations") if w.get("locations") is Array else []
	if not locs.is_empty():
		out += "\n[color=%s][b]The Places[/b][/color]\n" % gold
		for l in locs:
			if l is Dictionary:
				out += "• [b]%s[/b]%s — %s\n" % [_esc(str(l.get("name", "?"))),
					(" (%s)" % _esc(str(l.get("kind", "")))) if str(l.get("kind", "")) != "" else "",
					_esc(str(l.get("desc", l.get("blurb", "a place in this world"))))]
	var cast: Array = w.get("cast") if w.get("cast") is Array else []
	if not cast.is_empty():
		out += "\n[color=%s][b]The Cast[/b][/color]\n" % gold
		for c in cast:
			if c is Dictionary:
				out += "• [b]%s[/b] — %s%s\n" % [_esc(str(c.get("name", "?"))), _esc(str(c.get("role", "a figure of this world"))),
					(". " + _esc(str(c.get("persona", "")).left(120))) if str(c.get("persona", "")) != "" else ""]
	var beasts: Array = w.get("creatures") if w.get("creatures") is Array else []
	if not beasts.is_empty():
		out += "\n[color=%s][b]The Beasts[/b][/color]\n" % gold
		for b in beasts:
			if b is Dictionary:
				out += "• [b]%s[/b] — %s\n" % [_esc(str(b.get("name", "?"))), _esc(str(b.get("desc", b.get("art", "a threat of this world")).left(120)))]
	var stories: Array = w.get("stories") if w.get("stories") is Array else []
	if not stories.is_empty():
		out += "\n[color=%s][b]Campaigns Waiting[/b][/color]\n" % gold
		for st in stories:
			if st is Dictionary:
				out += "• [b]%s[/b] — %s\n" % [_esc(str(st.get("title", "?"))), _esc(str(st.get("premise", st.get("hook", ""))).left(140))]
	return out


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

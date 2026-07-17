extends Control
## ⚒ The Campaign Forge — a permanent pillar (docs/forges/CampaignForge.md).
## The DM's war table: candlelight, a blank map, a quill. C1 milestone:
## the shell + rail + Welcome/Name/Ruleset/Theme stages + the Forging
## wrapping the existing worldsmith contract (refine loop kept), sealing
## the world into the gallery. The GM's Voice, Table Rules, staged NPC/
## settlement/intro generation and the Dossier arrive C2-C4 — their
## rune-stones already stand on the rail, dim but visible.
## This node IS the CampaignForgeManager: stage FSM + draft + generation.

signal world_sealed(world: Dictionary, campaign_name: String)
signal closed

const STAGES := ["The Table", "The Name", "Ruleset", "Theme", "The Voice", "Table Rules", "The Forging", "Dossier"]
## Theme cards → worldsmith pillar presets (SMITH_GUIDE field names) + an
## idea seasoning line. Free text fields — not limited to the chip lists.
const THEMES := [
	{"glyph": "🌑", "title": "Dark Fantasy", "body": "grim roads, costly magic", "idea": "a grim dark-fantasy land where hope is scarce currency",
		"fields": {"Magic system": "Forbidden & feared", "Technology": "Medieval", "Era & timeline": "After the cataclysm", "Beast variants": "Corrupted wildlife", "Tone": "Grim & gritty"}},
	{"glyph": "🏔", "title": "High Fantasy", "body": "bright banners, old dragons", "idea": "a sweeping high-fantasy realm of banners, prophecy, and dragonfire",
		"fields": {"Magic system": "Elemental pacts", "Technology": "Medieval", "Era & timeline": "A golden age fading", "Beast variants": "Dragons & their kin", "Tone": "Heroic & bright"}},
	{"glyph": "🕯", "title": "Horror", "body": "creeping dread, thin walls", "idea": "a horror campaign of creeping dread where the dark has patience",
		"fields": {"Magic system": "Forbidden & feared", "Technology": "Medieval", "Era & timeline": "Under occupation", "Beast variants": "Spirits & shades", "Tone": "Noir & conspiratorial"}},
	{"glyph": "🗡", "title": "Political Intrigue", "body": "courts, daggers, debts", "idea": "a web of courts and conspiracies where words kill quicker than blades",
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
const Rail := preload("res://ui/myth_stage_rail.gd")
const Header := preload("res://ui/myth_header.gd")
const Fold := preload("res://ui/myth_fold.gd")

var draft := {"name": "", "theme": {}, "fields": {}, "idea": ""}
var _rail: MythStageRail
var _stage_box: VBoxContainer
var _table_note: Label
var _status: Label
var _phase := 0.0
var _busy := false
var _forged: Dictionary = {}   # the smith's latest take, pre-seal


func _ready() -> void:
	theme = Ui.theme
	set_process(not Ui.reduce_motion)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, Ui.SPACE["xl"] * 2)
	margin.add_theme_constant_override("margin_top", Ui.SPACE["l"])
	margin.add_theme_constant_override("margin_bottom", Ui.SPACE["l"])
	margin.add_child(col)
	add_child(margin)
	_rail = Rail.new(STAGES)
	_rail.stage_clicked.connect(_enter_stage)
	col.add_child(_rail)
	_stage_box = VBoxContainer.new()
	_stage_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_box.add_theme_constant_override("separation", Ui.SPACE["m"])
	col.add_child(_stage_box)
	# The table's ledger: what has been set down so far, plus status.
	_table_note = Label.new()
	_table_note.theme_type_variation = "HintLabel"
	_table_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_table_note)
	_status = Label.new()
	_status.theme_type_variation = "HintLabel"
	_status.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	# Harness hook: land on a given stage for visual regression shots.
	var shot_stage := OS.get_environment("MF_FORGE_STAGE")
	_enter_stage(int(shot_stage) if shot_stage != "" else 0)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


## The war table itself: dark wood, candle glow, the map that inks in.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Ui.c("night").darkened(0.25))
	# Constellations through the window.
	for i in 70:
		var h1 := absf(fmod(sin(i * 127.1) * 43758.5453, 1.0))
		var h2 := absf(fmod(sin(i * 311.7) * 12543.8367, 1.0))
		draw_circle(Vector2(h1 * size.x, h2 * size.y * 0.35), 0.9,
			Color(Ui.c("ink_soft"), 0.2 + 0.15 * sin(_phase + i)))
	# The table surface (lower two-thirds, warm wood).
	var table_y := size.y * 0.3
	draw_rect(Rect2(Vector2(0, table_y), Vector2(size.x, size.y - table_y)),
		Ui.c("night2").lerp(Color(0.24, 0.15, 0.08), 0.35))
	draw_line(Vector2(0, table_y), Vector2(size.x, table_y), Color(Ui.c("gold"), 0.25), 2.0)
	# The map, weighted open — it inks in as the campaign takes shape.
	var progress := clampf(_rail.current / 6.0, 0.08, 1.0)
	var map_r := Rect2(Vector2(size.x * 0.2, size.y * 0.42), Vector2(size.x * 0.6, size.y * 0.42))
	draw_rect(map_r, Color(0.82, 0.74, 0.58, 0.06 + 0.1 * progress))
	draw_rect(map_r, Color(Ui.c("gold"), 0.15 + 0.2 * progress), false, 1.5)
	# Candlelight, guttering.
	if not Ui.reduce_motion:
		for spec in [[0.08, 0.34, 1.0], [0.92, 0.34, 1.6]]:
			var flick := 0.16 + 0.05 * sin(_phase * 7.0 + float(spec[2])) + 0.03 * sin(_phase * 13.0)
			var cp := Vector2(size.x * float(spec[0]), size.y * float(spec[1]))
			draw_texture_rect(Ui.glow_tex(), Rect2(cp - Vector2(90, 90), Vector2(180, 180)),
				false, Color(Ui.c("gold"), flick))
			draw_circle(cp, 3.0, Color(1.0, 0.9, 0.6, 0.9))


func _clear_stage() -> void:
	for ch in _stage_box.get_children():
		ch.queue_free()


func _ledger() -> void:
	var bits: Array[String] = []
	if str(draft["name"]) != "":
		bits.append("“%s”" % str(draft["name"]))
	if not draft["theme"].is_empty():
		bits.append(str(draft["theme"].get("title", "")))
	_table_note.text = ("On the table:   " + "   ·   ".join(bits)) if not bits.is_empty() else ""


func _enter_stage(i: int) -> void:
	if _busy:
		return
	_rail.set_stage(i)
	_clear_stage()
	_ledger()
	match i:
		0:
			_stage_welcome()
		1:
			_stage_name()
		2:
			_stage_ruleset()
		3:
			_stage_theme()
		6:
			_stage_forging()
	Ui.polish(_stage_box)
	Ui.reveal_children(_stage_box, 0.05)


func _title_label(text: String) -> void:
	var t := Label.new()
	t.theme_type_variation = "TitleLabel"
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_box.add_child(t)


func _nav(back_to: int, fwd_text: String, fwd: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	if back_to >= 0:
		var back := Button.new()
		back.theme_type_variation = "GhostButton"
		back.text = "‹ back"
		back.pressed.connect(func(): _enter_stage(back_to))
		row.add_child(back)
	var go := Button.new()
	go.theme_type_variation = "AccentButton"
	go.text = fwd_text
	go.pressed.connect(fwd)
	row.add_child(go)
	var leave := Button.new()
	leave.theme_type_variation = "GhostButton"
	leave.text = "snuff the candles"
	leave.pressed.connect(func(): closed.emit())
	row.add_child(leave)
	_stage_box.add_child(row)


# ── Stage 0: the war table ───────────────────────────────────────────────────
func _stage_welcome() -> void:
	_title_label("The War Table")
	var line := Label.new()
	line.theme_type_variation = "HintLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.text = "A blank map. A quill. Every legendary campaign began exactly here."
	_stage_box.add_child(line)
	_nav(-1, "⚒ Take your seat ›", func(): _enter_stage(1))


# ── Stage 1: the name ────────────────────────────────────────────────────────
func _stage_name() -> void:
	_title_label("Name the Campaign")
	var input := LineEdit.new()
	input.placeholder_text = "e.g. The Hollow Bell — or leave blank and let the world name itself"
	input.text = str(draft["name"])
	input.custom_minimum_size = Vector2(460, 0)
	var ic := CenterContainer.new()
	ic.add_child(input)
	_stage_box.add_child(ic)
	var go := func():
		draft["name"] = input.text.strip_edges()
		_enter_stage(2)
	input.text_submitted.connect(func(_t): go.call())
	_nav(0, "Set it down ›", go)


# ── Stage 2: ruleset ─────────────────────────────────────────────────────────
func _stage_ruleset() -> void:
	_title_label("Choose the Ruleset")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["m"])
	var mf := Card.new({"glyph": "⚒", "title": "The Mythforge Rules",
		"body": "the engine's own d20 — dice, death, and gold all engine-owned", "foot": "chosen"})
	mf.set_selected(true)
	row.add_child(mf)
	for future in [["📜", "Strict 5e"], ["🧪", "Homebrew"]]:
		var fc := Card.new({"glyph": future[0], "title": future[1], "body": "a future forging"})
		fc.disabled = true
		fc.modulate = Color(1, 1, 1, 0.45)
		row.add_child(fc)
	_stage_box.add_child(row)
	_nav(1, "Continue ›", func(): _enter_stage(3))


# ── Stage 3: theme ───────────────────────────────────────────────────────────
func _stage_theme() -> void:
	_title_label("Choose the Campaign's Theme")
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
				c.set_selected(c == card)
			_ledger())
		cards.append(card)
		grid.add_child(card)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_stage_box.add_child(gc)
	# Advanced: the five pillars, verbatim — the old forge absorbed, not lost.
	var adv := Fold.new("Advanced: the five pillars", false)
	var idea := TextEdit.new()
	idea.placeholder_text = "Your own idea line — overrides the theme's seasoning…"
	idea.custom_minimum_size = Vector2(560, 56)
	idea.text = str(draft["idea"])
	adv.content.add_child(idea)
	var pillar_inputs := {}
	for pillar in _smith_guide():
		var lbl := Label.new()
		lbl.theme_type_variation = "HintLabel"
		lbl.text = str(pillar[0])
		adv.content.add_child(lbl)
		var pin := LineEdit.new()
		pin.text = str(draft["fields"].get(pillar[0], ""))
		pin.placeholder_text = "anything you like"
		adv.content.add_child(pin)
		pillar_inputs[pillar[0]] = pin
	var ac := CenterContainer.new()
	ac.add_child(adv)
	_stage_box.add_child(ac)
	var note := Label.new()
	note.theme_type_variation = "HintLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "The GM's Voice and Table Rules stones arrive with the next forging (C2)."
	_stage_box.add_child(note)
	_nav(2, "⚒ To the forging ›", func():
		draft["idea"] = idea.text.strip_edges()
		for k in pillar_inputs:
			var v: String = pillar_inputs[k].text.strip_edges()
			if v != "":
				draft["fields"][k] = v
		if draft["theme"].is_empty() and draft["idea"] == "" and draft["fields"].is_empty():
			_status.text = "Choose a theme — or open the pillars and write your own."
			return
		_enter_stage(6))


func _smith_guide() -> Array:
	return [["Magic system", []], ["Technology", []], ["Era & timeline", []], ["Beast variants", []], ["Tone", []]]


# ── Stage 6: THE FORGING (C1: one smith strike + refine loop + the seal) ────
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
	wait.text = "⚒ The smith works — the world takes shape (about a minute)…"
	_stage_box.add_child(wait)
	var t: Dictionary = draft["theme"]
	var idea := str(draft["idea"])
	if idea == "":
		idea = str(t.get("idea", "a world built from these pillars"))
	if str(draft["name"]) != "":
		idea += ". The campaign is named \"%s\" — let the world suit the name" % str(draft["name"])
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
		_enter_stage(3)
		return
	_status.text = ""
	_forged = w
	_enter_stage(6)


func _show_take() -> void:
	var w := _forged
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(620, 0)
	var casts: Array = w.get("cast") if w.get("cast") is Array else []
	var locs: Array = w.get("locations") if w.get("locations") is Array else []
	var stories: Array = w.get("stories") if w.get("stories") is Array else []
	body.append_text("[center][color=%s][font_size=20][b]%s[/b][/font_size][/color]  ·  %s[/center]\n[i]%s[/i]\n\n%s\n\n[b]Campaigns:[/b] %s\n[b]The cast:[/b] %s\n[b]Places:[/b] %s" % [
		Ui.c("gold_soft").to_html(false), str(w.get("name", "?")).replace("[", "[lb]"), str(w.get("kind", "")),
		str(w.get("tagline", "")).replace("[", "[lb]"), str(w.get("lore", "")).replace("[", "[lb]"),
		", ".join(stories.map(func(st): return str(st.get("title", "?")))),
		", ".join(casts.map(func(c): return str(c.get("name", "?")))),
		", ".join(locs.map(func(l): return str(l.get("name", "?"))))])
	var bs := ScrollContainer.new()
	bs.custom_minimum_size = Vector2(640, 260)
	bs.add_child(body)
	var bc := CenterContainer.new()
	bc.add_child(bs)
	_stage_box.add_child(bc)
	var refine := LineEdit.new()
	refine.placeholder_text = "✎ What should change? darker tone, a pirate faction, rename it…"
	refine.custom_minimum_size = Vector2(520, 0)
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
	seal.text = "🕯 Seal this world ›"
	seal.pressed.connect(_seal)
	row.add_child(seal)
	var back := Button.new()
	back.theme_type_variation = "GhostButton"
	back.text = "‹ the theme"
	back.pressed.connect(func(): _enter_stage(3))
	row.add_child(back)
	_stage_box.add_child(row)


## The wax comes down: the world joins the gallery, its sky gets painted,
## and the forge hands the campaign on (adventure binding arrives C4).
func _seal() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "🕯 Pressing the seal — binding the world…"
	var w := _forged
	var wid := "cw-%s-%04x" % [str(w["name"]).to_lower().replace(" ", "-").left(20), randi() % 65536]
	var world := {"id": wid, "custom": true}
	for k in ["name", "kind", "tagline", "lore", "backdrop", "locations", "cast", "stories", "creatures"]:
		world[k] = w.get(k)
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	var cworlds: Array = g.get("state", {}).get("cworlds", []) if g.get("state") is Dictionary and g["state"].get("cworlds") is Array else []
	cworlds.append(world)
	await Api.call_json(HTTPClient.METHOD_PUT, "/api/characters/studio/state/_global/cworlds", {"value": cworlds})
	_status.text = "🎨 Painting its sky…"
	Art.ensure(wid, str(world.get("backdrop", "")))
	Sfx.play("chime")
	_busy = false
	_status.text = ""
	world_sealed.emit(world, str(draft["name"]))

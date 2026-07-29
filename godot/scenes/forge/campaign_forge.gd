extends ForgeFlow
## ⚒ The Campaign Forge — a permanent pillar (docs/forges/CampaignForge.md).
## The DM's war table: candlelight, a blank map, a quill. C1 milestone:
## the shell + rail + Welcome/Name/Ruleset/Theme stages + the Forging
## wrapping the existing worldsmith contract (refine loop kept), sealing
## the world into the gallery. The GM's Voice, Table Rules, staged NPC/
## settlement/intro generation and the Dossier arrive C2-C4 — their
## rune-stones already stand on the rail, dim but visible.
## This node IS the CampaignForgeManager: stage FSM + draft + generation.

signal campaign_begun(adv: Dictionary)

## R6 CUT-04/CUT-15 — "The War Table" is gone. One line ("A blank map. A quill.
## Every legendary campaign began exactly here.") and a button reading **Take
## your seat ›**. That is the third forge to open by asking the player to sit
## down before doing the thing they clicked — after the Character Forge's Cold
## Anvil and the Adventure Forge's SIT DOWN. Same defect, same treatment; the
## forge opens on naming the campaign, which is a real decision.
const STAGES := ["The Name", "Ruleset", "Theme", "The Voice", "Table Rules", "The Forging", "Dossier"]
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
const Fold := preload("res://ui/myth_fold.gd")

## The GM's Voice presets → Session-Zero knob bundles (humor/spice/grit/
## pace/rules, 0-100) + a persona line the envelope carries every turn.
const VOICES := [
	{"glyph": "🎩", "title": "Classic DM", "body": "fair, steady, by the book", "knobs": {"humor": 40, "spice": 0, "grit": 55, "pace": 50, "rules": 75}},
	{"glyph": "📖", "title": "Narrative", "body": "story first, rules soft", "knobs": {"humor": 55, "spice": 40, "grit": 45, "pace": 40, "rules": 25}},
	{"glyph": "💀", "title": "Hardcore", "body": "brutal, strict, earned", "knobs": {"humor": 20, "spice": 0, "grit": 95, "pace": 60, "rules": 90}},
	{"glyph": "🧭", "title": "Sandbox", "body": "player-led, world breathes", "knobs": {"humor": 45, "spice": 20, "grit": 50, "pace": 70, "rules": 40}},
	{"glyph": "🎬", "title": "Cinematic", "body": "set pieces, hard cuts", "knobs": {"humor": 50, "spice": 30, "grit": 65, "pace": 85, "rules": 35}},
]
const DIFFICULTIES := [
	{"glyph": "🕊", "title": "Story", "body": "foes soften — the tale leads", "mult": 0.75},
	{"glyph": "⚔", "title": "Adventurer", "body": "the intended fight", "mult": 1.0},
	{"glyph": "🛡", "title": "Veteran", "body": "foes hit harder, last longer", "mult": 1.25},
	{"glyph": "☠", "title": "Merciless", "body": "the world does not blink", "mult": 1.5},
]

var draft := {"name": "", "theme": {}, "fields": {}, "idea": "", "gm": {}, "rules": {}}
var _table_note: Label
var _forged: Dictionary = {}        # the smith's latest take, pre-seal
var _sealed_world: Dictionary = {}  # the world after the wax came down
var _story: Dictionary = {}         # the forged opening campaign
var _settlement := ""               # where the tale begins


var _cgms: Array = []   # forged GM personas from the gallery (GM Forge)


func _ready() -> void:
	# The table's ledger — built BEFORE the scaffold because entering stage 0
	# (inside super._ready) already writes it via _ledger().
	_table_note = Label.new()
	_table_note.theme_type_variation = "HintLabel"
	_table_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_cgms()  # fire-and-forget; the Voice stage comes long after
	super._ready()
	_col.add_child(_table_note)
	_col.move_child(_table_note, _col.get_child_count() - 2)  # between stage box and status


func _load_cgms() -> void:
	_cgms = GameState.global_get("cgms", [])


func _stages() -> Array:
	return STAGES


func _leave_label() -> String:
	return "snuff the candles"


func _on_stage_entered(_i: int) -> void:
	_ledger()  # NOTE: _status is deliberately NOT reset — _strike's error status survives re-enter


## The procedural war table — the FALLBACK while the painted room is still
## on the easel (first run only; the environment is cached forever after).
func _draw() -> void:
	if Art.has_art("env-wartable"):
		return  # the illustrated room carries the scene
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


func _ledger() -> void:
	var bits: Array[String] = []
	if str(draft["name"]) != "":
		bits.append("“%s”" % str(draft["name"]))
	if not draft["theme"].is_empty():
		bits.append(str(draft["theme"].get("title", "")))
	_table_note.text = ("On the table:   " + "   ·   ".join(bits)) if not bits.is_empty() else ""


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_name()
		1:
			_stage_ruleset()
		2:
			_stage_theme()
		3:
			_stage_voice()
		4:
			_stage_rules()
		5:
			_stage_forging()
		6:
			_stage_dossier()


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
		_enter_stage(1)
	input.text_submitted.connect(func(_t): go.call())
	_nav(-1, "Set it down ›", go)   # first stage now — nothing behind it


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
	_nav(0, "Continue ›", func(): _enter_stage(2))


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
	_nav(1, "Continue ›", func():
		draft["idea"] = idea.text.strip_edges()
		for k in pillar_inputs:
			var v: String = pillar_inputs[k].text.strip_edges()
			if v != "":
				draft["fields"][k] = v
		if draft["theme"].is_empty() and draft["idea"] == "" and draft["fields"].is_empty():
			_status.text = "Choose a theme — or open the pillars and write your own."
			return
		_enter_stage(3))


# ── Stage 4: the GM's Voice (Session Zero, absorbed) ────────────────────────
func _stage_voice() -> void:
	_title_label("Choose the GM's Voice")
	var cards: Array = []
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	for v in VOICES:
		var card := Card.new(v)
		card.set_selected(str(draft["gm"].get("style", "")) == str(v["title"]))
		card.pressed.connect(func():
			draft["gm"] = v["knobs"].duplicate()
			draft["gm"]["style"] = v["title"]
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		row.add_child(card)
	# Forged GM personas from the gallery sit beside the archetypes.
	for v2 in _cgms:
		if not (v2 is Dictionary) or str(v2.get("title", "")) == "":
			continue
		var card2 := Card.new({"glyph": "crown", "title": str(v2["title"]),
			"body": str(v2.get("body", "a forged voice")), "foot": "forged"})
		card2.set_selected(str(draft["gm"].get("style", "")) == str(v2["title"]))
		card2.pressed.connect(func():
			draft["gm"] = v2.get("knobs", {}).duplicate()
			draft["gm"]["style"] = str(v2["title"])
			for c in cards:
				c.set_selected(c == card2))
		cards.append(card2)
		row.add_child(card2)
	_stage_box.add_child(row)
	# Tune by hand: the raw Session-Zero knobs, for those who know the table.
	var adv := Fold.new("Tune the voice by hand", false)
	var sliders := {}
	for k in [["humor", "Humor — serious ↔ comedic"], ["spice", "Romance & spice — none ↔ bold"],
			["grit", "Grit & danger — gentle ↔ brutal"], ["pace", "Pace — slow ↔ fast"], ["rules", "Rules — loose ↔ strict"]]:
		var lbl := Label.new()
		lbl.theme_type_variation = "HintLabel"
		lbl.text = str(k[1])
		adv.content.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int(draft["gm"].get(k[0], 50))
		sl.custom_minimum_size = Vector2(360, 0)
		adv.content.add_child(sl)
		sliders[k[0]] = sl
	var ac := CenterContainer.new()
	ac.add_child(adv)
	_stage_box.add_child(ac)
	_nav(2, "Continue ›", func():
		if adv.content.visible:
			for key in sliders:
				draft["gm"][key] = int(sliders[key].value)
			if str(draft["gm"].get("style", "")) == "":
				draft["gm"]["style"] = "Tuned by hand"
		if draft["gm"].is_empty():
			draft["gm"] = VOICES[0]["knobs"].duplicate()
			draft["gm"]["style"] = VOICES[0]["title"]
		_enter_stage(4))


# ── Stage 5: table rules — every lever engine-enforced ──────────────────────
func _stage_rules() -> void:
	_title_label("Set the Table Rules")
	var cards: Array = []
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	for d in DIFFICULTIES:
		var card := Card.new(d)
		card.set_selected(float(draft["rules"].get("difficulty", 1.0)) == float(d["mult"]))
		card.pressed.connect(func():
			draft["rules"]["difficulty"] = float(d["mult"])
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		row.add_child(card)
	_stage_box.add_child(row)
	var toggles := VBoxContainer.new()
	toggles.add_theme_constant_override("separation", Ui.SPACE["xs"])
	var toggle_defs := [["permadeath", "Permadeath — death archives the save; the tale truly ends", false],
		["companions", "Companions — allies may join the party", true],
		["fog", "Fog of War — the map hides what you haven't walked", true]]
	var checks := {}
	for td in toggle_defs:
		var cb := CheckButton.new()
		cb.text = str(td[1])
		cb.button_pressed = bool(draft["rules"].get(td[0], td[2]))
		toggles.add_child(cb)
		checks[td[0]] = cb
	var tc := CenterContainer.new()
	tc.add_child(toggles)
	_stage_box.add_child(tc)
	var house := LineEdit.new()
	house.placeholder_text = "House rules, in your words — e.g. no resurrection, critical fumbles hurt…"
	house.text = str(draft["rules"].get("house", ""))
	house.custom_minimum_size = Vector2(520, 0)
	var hc := CenterContainer.new()
	hc.add_child(house)
	_stage_box.add_child(hc)
	_nav(3, "To the forging ›", func():
		if not draft["rules"].has("difficulty"):
			draft["rules"]["difficulty"] = 1.0
		for key in checks:
			draft["rules"][key] = checks[key].button_pressed
		draft["rules"]["house"] = house.text.strip_edges()
		_enter_stage(5))


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
	wait.text = "The smith works — the world takes shape (a few minutes; the local models are thinking)…"
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
	var w := await Api.worldsmith(payload)
	_busy = false
	if w.get("_status", 0) != 200 or str(w.get("name", "")) == "":
		_status.text = "The forge sputtered (%s) — strike again." % str(w.get("_status", 0))
		_forged = {}
		_enter_stage(2)
		return
	_status.text = ""
	_forged = w
	_enter_stage(5)


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
	refine.placeholder_text = "What should change? darker tone, a pirate faction, rename it…"
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
	seal.text = "Seal this world ›"
	seal.pressed.connect(_seal)
	row.add_child(seal)
	var back := Button.new()
	back.theme_type_variation = "GhostButton"
	back.text = "‹ the rules"
	back.pressed.connect(func(): _enter_stage(4))
	row.add_child(back)
	_stage_box.add_child(row)


## The wax comes down: the world joins the gallery — then THE FORGING
## proper: each artifact lands on the table as it completes.
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
	# The table's choices ride with the world: every adventure begun in it
	# is seeded with this voice and these rules (menu applies them on start).
	world["forge_defaults"] = {"gm": draft["gm"], "rules": draft["rules"], "campaign": str(draft["name"])}
	var cworlds: Array = GameState.global_get("cworlds", [])
	cworlds.append(world)
	GameState.global_set("cworlds", cworlds)
	_sealed_world = world
	# Fire the World Compiler in the BACKGROUND (not awaited): its Style Guide,
	# Asset Language, item catalogue, kits, creatures, NPCs and ~80 images take
	# several minutes of local LLM/GPU on this box, so we DON'T make the player
	# wait. The world becomes world-true (world-specific gear, monsters, theme)
	# over the next few minutes while they already play; assets swap in as each
	# stage lands. (docs/WorldCompiler.md — "compile doesn't block play".)
	Compiler.compile_seed(world)
	_busy = false
	_status.text = ""
	await _run_sequence()


## THE FORGING sequence: world seal → the cast's faces → the settlement →
## the opening scene → the DM's notes. Each step lands with its wax thunk.
func _run_sequence() -> void:
	_clear_stage()
	_title_label("The Forging")
	var world := _sealed_world
	var steps := {}
	for spec in [["world", "The world"], ["cast", "The key faces"], ["settle", "The first settlement"], ["intro", "The opening scene"], ["notes", "The DM's notes"]]:
		var step := MythForgeStep.new(str(spec[1]))
		steps[spec[0]] = step
		_stage_box.add_child(step)
	Ui.reveal_children(_stage_box, 0.04)
	_busy = true
	# 1. The world — the wax already came down; paint its sky in the queue.
	Art.ensure(str(world["id"]), str(world.get("backdrop", "")))
	steps["world"].set_state("done", "%s — sealed into the gallery" % str(world.get("name", "")))
	# 2. The key faces — commissioned to the queue; they land as they finish.
	steps["cast"].set_state("work", "the painters are called…")
	var cast: Array = world.get("cast") if world.get("cast") is Array else []
	var commissioned := 0
	for c in cast.slice(0, 5):
		var nm := str(c.get("name", "")).strip_edges()
		if nm == "":
			continue
		var key := "npc-" + nm.to_lower().replace(" ", "-")
		Art.ensure(key, "character portrait of %s, %s, painted head-and-shoulders portrait, dramatic rim light, dark background, no text" % [nm, str(c.get("role", "a figure of this world"))])
		var chip := MythPortrait.new(34, "amethyst")
		chip.set_portrait(Art.round_tex(key), nm.left(1).to_upper())
		chip.tooltip_text = "%s — %s" % [nm, str(c.get("role", ""))]
		steps["cast"].artifacts.add_child(chip)
		commissioned += 1
	steps["cast"].set_state("done", "%d faces commissioned — they arrive as the paint dries" % commissioned)
	# 3. The first settlement — where the tale opens.
	steps["settle"].set_state("work", "")
	var locs: Array = world.get("locations") if world.get("locations") is Array else []
	_settlement = ""
	for l in locs:
		if l is Dictionary and str(l.get("kind", "")) in ["tavern", "home"]:
			_settlement = str(l.get("name", ""))
			break
	if _settlement == "" and not locs.is_empty() and locs[0] is Dictionary:
		_settlement = str(locs[0].get("name", ""))
	steps["settle"].set_state("done", ("its lamps are lit: %s" % _settlement) if _settlement != "" else "the road itself, for now")
	# 4. The opening scene — the campaign smith writes the first page.
	steps["intro"].set_state("work", "the quill scratches…")
	var intro_idea := str(draft["name"]) if str(draft["name"]) != "" else "an opening campaign true to this world's theme"
	var r := await Api.worldsmith({
		"idea": "The opening campaign: %s. Begin it at %s." % [intro_idea, _settlement if _settlement != "" else "the world's heart"],
		"mode": "story",
		"world": {"name": world.get("name", ""), "kind": world.get("kind", ""), "lore": world.get("lore", "")}})
	if r.get("_status", 0) == 200 and str(r.get("title", "")) != "":
		_story = {"slug": str(r["title"]).to_lower().replace(" ", "-").left(24),
			"title": str(r["title"]), "premise": str(r.get("premise", "")), "hook": str(r.get("hook", ""))}
		if str(draft["name"]) != "":
			_story["title"] = str(draft["name"])
			_story["slug"] = str(draft["name"]).to_lower().replace(" ", "-").left(24)
		steps["intro"].set_state("done", "“%s”" % str(_story.get("title", "")))
	else:
		_story = {}
		steps["intro"].set_state("fail", "the quill broke — the Dossier can re-strike it")
	# 5. The DM's notes — the campaign prompt, composed and sealed.
	steps["notes"].set_state("done", "persona composed — inspect it in the Dossier")
	_busy = false
	var onward := Button.new()
	onward.theme_type_variation = "AccentButton"
	onward.text = "To the Dossier ›"
	onward.pressed.connect(func(): _enter_stage(6))
	var oc := CenterContainer.new()
	oc.add_child(onward)
	_stage_box.add_child(onward if false else oc)
	Ui.polish(_stage_box)


# ── Stage 7: the Dossier — the campaign, ready to begin ─────────────────────
func _stage_dossier() -> void:
	var world := _sealed_world
	_title_label("The Campaign Dossier")
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(640, 0)
	var rules: Dictionary = draft["rules"]
	var rule_bits: Array[String] = []
	for d in DIFFICULTIES:
		if float(d["mult"]) == float(rules.get("difficulty", 1.0)):
			rule_bits.append(str(d["title"]))
	if bool(rules.get("permadeath", false)):
		rule_bits.append("permadeath")
	if not bool(rules.get("companions", true)):
		rule_bits.append("no companions")
	if not bool(rules.get("fog", true)):
		rule_bits.append("no fog")
	if str(rules.get("house", "")) != "":
		rule_bits.append("house: " + str(rules.get("house", "")))
	body.append_text("[center][font_size=20][color=%s][b]%s[/b][/color][/font_size]\n[i]%s[/i][/center]\n\n[b]World:[/b] %s — %s\n[b]The GM:[/b] %s\n[b]Table rules:[/b] %s\n[b]It begins at:[/b] %s\n\n[b]The hook:[/b] %s" % [
		Ui.c("gold_soft").to_html(false),
		str(_story.get("title", str(draft["name"]) if str(draft["name"]) != "" else "An Untitled Campaign")).replace("[", "[lb]"),
		str(_story.get("premise", "")).replace("[", "[lb]"),
		str(world.get("name", "")).replace("[", "[lb]"), str(world.get("tagline", "")).replace("[", "[lb]"),
		str(draft["gm"].get("style", "as tuned")),
		", ".join(rule_bits) if not rule_bits.is_empty() else "the intended fight",
		_settlement if _settlement != "" else "the open road",
		str(_story.get("hook", "the world waits")).replace("[", "[lb]")])
	var bc := CenterContainer.new()
	bc.add_child(body)
	_stage_box.add_child(bc)
	var notes := Fold.new("The DM's notes (the composed campaign prompt)", false)
	var np := Label.new()
	np.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	np.theme_type_variation = "HintLabel"
	np.custom_minimum_size = Vector2(620, 0)
	np.text = Composer.compose_world_gm(world, _story)
	notes.content.add_child(np)
	var nc := CenterContainer.new()
	nc.add_child(notes)
	_stage_box.add_child(nc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	var reroll := Button.new()
	reroll.theme_type_variation = "GhostButton"
	reroll.text = "↻ Re-strike the opening"
	reroll.pressed.connect(func():
		_story = {}
		_enter_stage(5))
	row.add_child(reroll)
	var begin := Button.new()
	begin.theme_type_variation = "AccentButton"
	begin.text = "BEGIN THE CAMPAIGN"
	begin.pressed.connect(_begin_campaign)
	row.add_child(begin)
	var leave := Button.new()
	leave.theme_type_variation = "GhostButton"
	leave.text = "snuff the candles"
	leave.pressed.connect(func(): closed.emit())
	row.add_child(leave)
	_stage_box.add_child(row)


## The save slot: the dm- adventure, seeded with everything the table chose.
func _begin_campaign() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Opening the campaign…"
	var world := _sealed_world
	var wid := str(world.get("id", ""))
	var story := _story
	var adv_name := str(story.get("title", "")) if not story.is_empty() else "%s: Free Roam" % str(world.get("name", ""))
	var adv_id := Rules.adventure_id(wid, story)
	await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/save", {
		"id": adv_id, "name": adv_name,
		"personality": Composer.compose_world_gm(world, story),
		"relationship": "Dungeon Master", "world_id": wid,
	})
	if draft["gm"] is Dictionary and not draft["gm"].is_empty():
		GameState.set_kind_for(adv_id, "gm", draft["gm"])
	var world_kind := {"rules": draft["rules"]}
	if _settlement != "":
		world_kind["here"] = _settlement
		world_kind["seen"] = [_settlement]
	GameState.set_kind_for(adv_id, "world", world_kind)
	_busy = false
	_status.text = ""
	Sfx.play("sting")
	campaign_begun.emit({"id": adv_id, "name": adv_name, "world_id": wid})

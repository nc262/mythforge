extends Control
## ⚒ The Character Forge — a permanent pillar (docs/forges/CharacterForge.md).
## Not character creation: the ancient forge where a legend is struck.
## Embers rise, runes light along the rail, every stage is a hammer blow,
## and the Quenching reveals the finished hero. This node IS the
## CharacterForgeManager: stage FSM + draft + commit signal.
## Two homes: launched in-game when an adventure has no hero (commits via
## hero_forged), or from the main menu as a draft (banked to user://).

signal hero_forged(draft: Dictionary)
signal closed

const STAGES := ["The Anvil", "Origin", "Ruleset", "Heritage", "Class", "Background", "Nature", "Appearance", "The Voice", "Equipment", "Quenching"]
const PREBUILT := [
	{"glyph": "🪓", "title": "Brakka Ironhide", "body": "Half-Orc Fighter — the wall that walks", "race": "Half-Orc", "cls": "Fighter", "bg": "Soldier"},
	{"glyph": "🔮", "title": "Elara Venn", "body": "Elf Wizard — patience, then fire", "race": "Elf", "cls": "Wizard", "bg": "Sage"},
	{"glyph": "🗡", "title": "Finch", "body": "Halfling Rogue — never met a lock he liked", "race": "Halfling", "cls": "Rogue", "bg": "Criminal"},
	{"glyph": "✨", "title": "Sister Maren", "body": "Human Cleric — mercy with a mace", "race": "Human", "cls": "Cleric", "bg": "Acolyte"},
]
const KITS := [
	{"glyph": "🛡", "title": "Soldier's Kit", "body": "longsword, oak shield, leathers", "items": ["Longsword", "Oak Shield", "Traveler's Leathers"]},
	{"glyph": "🏹", "title": "Skirmisher's Kit", "body": "shortbow, dagger, leathers", "items": ["Shortbow", "Dagger", "Traveler's Leathers"]},
	{"glyph": "📚", "title": "Scholar's Kit", "body": "quarterstaff, leathers, a potion", "items": ["Quarterstaff", "Traveler's Leathers", "Healing Potion"]},
]
const STYLES := ["painted", "ink & wash", "dark oil", "neon noir", "storybook"]
const ARRAY_VALUES := [15, 14, 13, 12, 10, 8]

const Card := preload("res://ui/myth_choice_card.gd")
const Rail := preload("res://ui/myth_stage_rail.gd")
const Fold := preload("res://ui/myth_fold.gd")

var draft := {"name": "", "race": "", "cls": "", "bg": "", "rolled": [], "assign": {},
	"appearance": "", "style": "painted", "kit": [], "origin": ""}
var menu_mode := false        # true = forging a draft from the main menu
var start_at_quench := false  # a banked draft resumes at the reveal
var _rail: MythStageRail
var _stage_box: VBoxContainer
var _status: Label
var _phase := 0.0
var _embers: Array = []


func _ready() -> void:
	theme = Ui.theme
	set_process(not Ui.reduce_motion)
	# EAS: the player stands inside the ancient forge; its embers are the air.
	MythEnvironment.mount(self, "env-forge", "embers", [Vector2(0.5, 0.88)])
	for i in 26:
		_embers.append([randf(), randf(), 0.35 + randf() * 0.9])
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
	_rail = Rail.new(STAGES)
	_rail.stage_clicked.connect(_enter_stage)
	col.add_child(_rail)
	_stage_box = VBoxContainer.new()
	_stage_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_box.add_theme_constant_override("separation", Ui.SPACE["m"])
	col.add_child(_stage_box)
	_status = Label.new()
	_status.theme_type_variation = "HintLabel"
	_status.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var shot_stage := OS.get_environment("MF_FORGE_STAGE")
	if shot_stage != "":
		_enter_stage(int(shot_stage))
	elif start_at_quench:
		_enter_stage(10)
	else:
		_enter_stage(0)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


## The procedural forge — the FALLBACK while the painted interior is still
## on the easel (first run only; cached forever after).
func _draw() -> void:
	if Art.has_art("env-forge"):
		return  # the illustrated forge carries the scene
	draw_rect(Rect2(Vector2.ZERO, size), Ui.c("night").darkened(0.35))
	for i in 60:
		var h1 := absf(fmod(sin(i * 127.1) * 43758.5453, 1.0))
		var h2 := absf(fmod(sin(i * 311.7) * 12543.8367, 1.0))
		draw_circle(Vector2(h1 * size.x, h2 * size.y * 0.3), 0.9, Color(Ui.c("ink_soft"), 0.22))
	# The anvil silhouette, center-low.
	var ax := size.x / 2.0
	var ay := size.y * 0.9
	var anvil := PackedVector2Array([
		Vector2(ax - 130, ay - 34), Vector2(ax + 96, ay - 34), Vector2(ax + 150, ay - 22),
		Vector2(ax + 96, ay - 12), Vector2(ax + 44, ay - 12), Vector2(ax + 44, ay),
		Vector2(ax - 78, ay), Vector2(ax - 78, ay - 12), Vector2(ax - 130, ay - 20)])
	draw_colored_polygon(anvil, Color(Ui.c("night2").darkened(0.3), 0.95))
	# The molten seam breathes under it.
	var heat := 0.25 + 0.12 * sin(_phase * 1.8) if not Ui.reduce_motion else 0.3
	draw_texture_rect(Ui.glow_tex(), Rect2(Vector2(ax - 170, ay - 60), Vector2(340, 100)), false, Color(Ui.c("ember"), heat))
	# Embers rise from the seam toward the stars.
	if not Ui.reduce_motion:
		for e in _embers:
			var t := fmod(_phase * 0.07 * float(e[2]) + float(e[1]), 1.0)
			var ex := ax + (float(e[0]) - 0.5) * 320.0 + sin(_phase * 1.3 + float(e[0]) * 20.0) * 14.0
			var ey := ay - 30.0 - t * size.y * 0.75
			draw_circle(Vector2(ex, ey), 1.6, Color(Ui.c("ember"), (1.0 - t) * 0.6))


func _clear_stage() -> void:
	for ch in _stage_box.get_children():
		ch.queue_free()


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
	leave.text = "bank the fire"
	leave.pressed.connect(func(): closed.emit())
	row.add_child(leave)
	_stage_box.add_child(row)


func _card_grid(entries: Array, cols: int, selected_title: String, on_pick: Callable) -> void:
	var cards: Array = []
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for e in entries:
		var card := Card.new(e)
		card.set_selected(str(e.get("title", "")) == selected_title)
		card.pressed.connect(func():
			for c in cards:
				c.set_selected(c == card)
			on_pick.call(e))
		cards.append(card)
		grid.add_child(card)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_stage_box.add_child(gc)


func _enter_stage(i: int) -> void:
	_rail.set_stage(i)
	_clear_stage()
	_status.text = ""
	match i:
		0:
			_stage_anvil()
		1:
			_stage_origin()
		2:
			_stage_ruleset()
		3:
			_stage_heritage()
		4:
			_stage_class()
		5:
			_stage_background()
		6:
			_stage_nature()
		7:
			_stage_appearance()
		8:
			_stage_voice()
		9:
			_stage_equipment()
		10:
			_stage_quenching()
	Ui.polish(_stage_box)
	Ui.reveal_children(_stage_box, 0.05)


func _stage_anvil() -> void:
	_title_label("The Cold Anvil")
	var line := Label.new()
	line.theme_type_variation = "HintLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.text = "Every legend begins as raw metal."
	_stage_box.add_child(line)
	_nav(-1, "⚒ Light the forge ›", func(): _enter_stage(1))


func _stage_origin() -> void:
	_title_label("Choose Your Origin")
	var entries: Array = [{"glyph": "⛏", "title": "Raw Metal", "body": "forge a hero from nothing", "foot": "the full journey"}]
	for pb in PREBUILT:
		entries.append(pb)
	_card_grid(entries, 5, str(draft["origin"]), func(e):
		draft["origin"] = str(e.get("title", ""))
		if e.has("race"):
			draft["name"] = str(e["title"])
			draft["race"] = str(e["race"])
			draft["cls"] = str(e["cls"])
			draft["bg"] = str(e["bg"])
			draft["kit"] = KITS[0]["items"] if str(e["cls"]) in ["Fighter", "Cleric"] else (KITS[1]["items"] if str(e["cls"]) == "Rogue" else KITS[2]["items"])
			_roll_destiny()
			_status.text = "%s stands ready — the Quenching awaits (walk back through any rune to reshape them)." % draft["name"]
			_enter_stage(10)
		)
	_nav(0, "Continue ›", func():
		if str(draft["origin"]) == "":
			draft["origin"] = "Raw Metal"
		_enter_stage(2))


func _stage_ruleset() -> void:
	_title_label("Choose the Ruleset")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["m"])
	var mf := Card.new({"glyph": "⚒", "title": "The Mythforge Rules", "body": "the engine's own d20", "foot": "chosen"})
	mf.set_selected(true)
	row.add_child(mf)
	for future in [["📜", "Strict 5e"], ["🧪", "Homebrew"]]:
		var fc := Card.new({"glyph": future[0], "title": future[1], "body": "a future forging"})
		fc.disabled = true
		fc.modulate = Color(1, 1, 1, 0.45)
		row.add_child(fc)
	_stage_box.add_child(row)
	_nav(1, "Continue ›", func(): _enter_stage(3))


func _stage_heritage() -> void:
	_title_label("Choose Your Heritage")
	var entries: Array = []
	var hs: Dictionary = Rules.tables.get("heritages", {})
	var names := hs.keys()
	names.sort()
	for nm in names:
		var h: Dictionary = hs[nm]
		var traits: Array = h.get("traits", [])
		entries.append({"glyph": "🧬", "title": str(nm),
			"body": str(traits[0]).split("—")[0].strip_edges() if not traits.is_empty() else "",
			"foot": "%d ft" % int(h.get("speed", 30))})
	_card_grid(entries, 5, str(draft["race"]), func(e): draft["race"] = str(e["title"]))
	_nav(2, "Strike ›", func():
		if str(draft["race"]) == "":
			_status.text = "The metal needs a heritage — choose one."
			return
		_enter_stage(4))


func _stage_class() -> void:
	_title_label("Choose Your Class")
	var entries: Array = []
	var lore: Dictionary = Rules.class_lore
	var names: Array = Rules.tables.get("class_presets", {}).keys()
	names.sort()
	for nm in names:
		var l: Dictionary = lore.get(nm, {}) if lore is Dictionary else {}
		entries.append({"glyph": str(l.get("icon", "⚔")), "title": str(nm),
			"body": str(l.get("blurb", "")).left(90),
			"foot": "d%d" % int(Rules.tables["class_presets"][nm].get("hitDie", 8))})
	_card_grid(entries, 4, str(draft["cls"]), func(e): draft["cls"] = str(e["title"]))
	_nav(3, "Strike ›", func():
		if str(draft["cls"]) == "":
			_status.text = "The blade needs a shape — choose a class."
			return
		_enter_stage(5))


func _stage_background() -> void:
	_title_label("Choose Your Background")
	var entries: Array = []
	var bgs: Dictionary = Rules.tables.get("backgrounds", {})
	var names := bgs.keys()
	names.sort()
	for nm in names:
		var b: Dictionary = bgs[nm]
		entries.append({"glyph": "🕯", "title": str(nm), "body": str(b.get("line", "")).left(90),
			"foot": ", ".join(b.get("skills", []))})
	_card_grid(entries, 4, str(draft["bg"]), func(e): draft["bg"] = str(e["title"]))
	_nav(4, "Strike ›", func():
		if str(draft["bg"]) == "":
			_status.text = "Every legend was someone first — choose a background."
			return
		_enter_stage(6))


func _roll_destiny() -> void:
	var rolled: Array = []
	for i in 6:
		var d := [randi_range(1, 6), randi_range(1, 6), randi_range(1, 6), randi_range(1, 6)]
		d.sort()
		rolled.append(d[1] + d[2] + d[3])
	rolled.sort()
	rolled.reverse()
	draft["rolled"] = rolled
	draft["assign"] = {}


func _stage_nature() -> void:
	_title_label("Your Nature")
	if draft["rolled"].is_empty() and draft["assign"].is_empty():
		_roll_destiny()
	var dice_l := Label.new()
	dice_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_l.add_theme_color_override("font_color", Ui.c("gold_soft"))
	var show_roll := func():
		dice_l.text = "🎲 Destiny: %s   (best scores land where your class wants them)" % ", ".join(draft["rolled"].map(func(x): return str(x)))
	if not draft["rolled"].is_empty():
		show_roll.call()
	_stage_box.add_child(dice_l)
	var reroll := Button.new()
	reroll.text = "🎲 Reroll destiny (4d6, drop lowest)"
	reroll.pressed.connect(func():
		Sfx.play("dice")
		_roll_destiny()
		show_roll.call())
	var rc := CenterContainer.new()
	rc.add_child(reroll)
	_stage_box.add_child(rc)
	# Or take fate into your own hands: the standard array, assigned by hand.
	var adv := Fold.new("Or take the standard array (15 14 13 12 10 8), assigned by hand", false)
	var pickers := {}
	for ab in Rules.ABILITIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Ui.SPACE["s"])
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(48, 0)
		lbl.text = ab
		row.add_child(lbl)
		var opt := OptionButton.new()
		for v in ARRAY_VALUES:
			opt.add_item(str(v))
		opt.selected = Rules.ABILITIES.find(ab)
		row.add_child(opt)
		pickers[ab] = opt
		adv.content.add_child(row)
	var ac := CenterContainer.new()
	ac.add_child(adv)
	_stage_box.add_child(ac)
	_nav(5, "Strike ›", func():
		if adv.content.visible:
			var used: Array = []
			var assign := {}
			for ab in pickers:
				var v: int = ARRAY_VALUES[pickers[ab].selected]
				assign[ab] = v
				used.append(v)
			used.sort()
			var want := ARRAY_VALUES.duplicate()
			want.sort()
			if used != want:
				_status.text = "Each array value must be used exactly once — %s remains unbalanced." % str(used)
				return
			draft["assign"] = assign
			draft["rolled"] = []
		_enter_stage(7))


func _stage_appearance() -> void:
	_title_label("Their Face, In Words")
	var desc := TextEdit.new()
	desc.placeholder_text = "e.g. wind-burned, silver-braided, eyes like a storm about to break…"
	desc.custom_minimum_size = Vector2(520, 70)
	desc.text = str(draft["appearance"])
	var dc := CenterContainer.new()
	dc.add_child(desc)
	_stage_box.add_child(dc)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", Ui.SPACE["s"])
	var chips: Array = []
	for st in STYLES:
		var chip := Button.new()
		chip.theme_type_variation = "GhostButton"
		chip.text = ("● " if str(draft["style"]) == st else "○ ") + st
		chip.pressed.connect(func():
			draft["style"] = st
			for c2 in chips:
				var nm2: String = c2.text.substr(2)
				c2.text = ("● " if nm2 == st else "○ ") + nm2)
		chips.append(chip)
		chip_row.add_child(chip)
	_stage_box.add_child(chip_row)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "These words become the portrait's commission — the style chip sets its brush."
	_stage_box.add_child(hint)
	_nav(6, "Strike ›", func():
		draft["appearance"] = desc.text.strip_edges()
		_enter_stage(8))


func _stage_voice() -> void:
	_title_label("The Voice")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var vc := Card.new({"glyph": "🔇", "title": "Awaiting the Bards", "body": "the voice provider sleeps — this rune wakes when it does"})
	vc.disabled = true
	vc.modulate = Color(1, 1, 1, 0.45)
	row.add_child(vc)
	_stage_box.add_child(row)
	_nav(7, "Continue ›", func(): _enter_stage(9))


func _stage_equipment() -> void:
	_title_label("Choose Your Kit")
	var sel := ""
	for k in KITS:
		if draft["kit"] == k["items"]:
			sel = str(k["title"])
	_card_grid(KITS, 3, sel, func(e): draft["kit"] = e["items"])
	_nav(8, "To the Quenching ›", func():
		if draft["kit"].is_empty():
			draft["kit"] = KITS[0]["items"]
		_enter_stage(10))


# ── The Quenching: steam, gold, the finished legend ─────────────────────────
func _stage_quenching() -> void:
	_title_label("The Quenching")
	var portrait := MythPortrait.new(150, "gold", true)
	var pkey := ""
	if not menu_mode:
		pkey = "hero-" + GameState.cid().validate_filename()
		var prompt := "character portrait of %s, a %s %s, %s%s style, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face, no text" % [
			str(draft["name"]) if str(draft["name"]) != "" else "a hero", str(draft["race"]), str(draft["cls"]),
			(str(draft["appearance"]) + ", ") if str(draft["appearance"]) != "" else "", str(draft["style"])]
		Art.ensure(pkey, prompt)
		portrait.set_portrait(Art.round_tex(pkey), str(draft["name"]).left(1) if str(draft["name"]) != "" else "?")
		Art.art_ready.connect(func(k):
			if str(k) == pkey and is_instance_valid(portrait):
				portrait.set_portrait(Art.round_tex(pkey), "?")
				Ui.pulse(portrait))
	else:
		portrait.set_portrait(null, str(draft["name"]).left(1) if str(draft["name"]) != "" else "?")
	var pc := CenterContainer.new()
	pc.add_child(portrait)
	_stage_box.add_child(pc)
	Ui.breathe(portrait)
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Strike the name…"
	name_in.text = str(draft["name"])
	name_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_in.custom_minimum_size = Vector2(340, 0)
	var nc := CenterContainer.new()
	nc.add_child(name_in)
	_stage_box.add_child(nc)
	var epithet := Label.new()
	epithet.theme_type_variation = "HintLabel"
	epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nature := ("destiny: " + ", ".join(draft["rolled"].map(func(x): return str(x)))) if not draft["rolled"].is_empty() \
		else "the standard array, by hand"
	epithet.text = "%s %s · %s · %s · kit: %s%s" % [str(draft["race"]), str(draft["cls"]), str(draft["bg"]), nature,
		", ".join(draft["kit"]),
		("   ·   the portrait cools on the anvil…" if not menu_mode else "   ·   the portrait is commissioned when the tale begins")]
	epithet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epithet.custom_minimum_size = Vector2(620, 0)
	_stage_box.add_child(epithet)
	if not menu_mode:
		var restrike := Button.new()
		restrike.theme_type_variation = "GhostButton"
		restrike.text = "↻ Re-strike the portrait"
		restrike.pressed.connect(func():
			Art.forget(pkey)
			portrait.set_portrait(null, "…")
			var prompt2 := "character portrait of %s, a %s %s, %s%s style, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face, no text" % [
				name_in.text.strip_edges() if name_in.text.strip_edges() != "" else "a hero", str(draft["race"]), str(draft["cls"]),
				(str(draft["appearance"]) + ", ") if str(draft["appearance"]) != "" else "", str(draft["style"])]
			Art.ensure(pkey, prompt2))
		var rsc := CenterContainer.new()
		rsc.add_child(restrike)
		_stage_box.add_child(rsc)
	_nav(9, "⚒ BEGIN THE ADVENTURE" if not menu_mode else "⚒ BANK THIS LEGEND", func():
		draft["name"] = name_in.text.strip_edges()
		if draft["name"] == "":
			_status.text = "A legend needs a name — strike it."
			return
		if str(draft["race"]) == "" or str(draft["cls"]) == "":
			_status.text = "The metal is not ready — heritage and class await their strikes."
			return
		if draft["rolled"].is_empty() and draft["assign"].is_empty():
			_roll_destiny()
		if draft["kit"].is_empty():
			draft["kit"] = KITS[0]["items"]
		Sfx.play("sting")
		Sfx.play("chime")
		hero_forged.emit(draft))

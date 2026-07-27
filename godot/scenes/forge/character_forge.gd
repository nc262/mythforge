extends ForgeFlow
## ⚒ The Character Forge — a permanent pillar (docs/forges/CharacterForge.md).
## Not character creation: the ancient forge where a legend is struck.
## Embers rise, runes light along the rail, every stage is a hammer blow,
## and the Quenching reveals the finished hero. This node IS the
## CharacterForgeManager: stage FSM + draft + commit signal.
## Two homes: launched in-game when an adventure has no hero (commits via
## hero_forged), or from the main menu as a draft (banked to user://).

signal hero_forged(draft: Dictionary)

## R6 CUT-01/CUT-02 — "The Anvil" is gone. It was an entire stage whose whole
## content was the line "Every legend begins as raw metal." and a button reading
## "Light the forge ›": no input, no choice, nothing to look at, and one more
## click between the player and the thing they asked for. Ceremony belongs where
## there is something to be ceremonious about — the forge now OPENS on the first
## real decision, and the eleven-dot progress rail is a ten.
const STAGES := ["Origin", "Ruleset", "Heritage", "Class", "Background", "Nature", "Appearance", "The Voice", "Equipment", "Quenching"]
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
const Fold := preload("res://ui/myth_fold.gd")

var draft := {"name": "", "race": "", "cls": "", "bg": "", "rolled": [], "assign": {},
	"appearance": "", "style": "painted", "kit": [], "origin": "",
	"cls_story": "", "bg_story": "", "portrait_key": ""}
var menu_mode := false        # true = forging a draft from the main menu
var start_at_quench := false  # a banked draft resumes at the reveal
var _embers: Array = []
var _story_edit: TextEdit = null   # the current stage's optional free-text story


func _ready() -> void:
	for i in 26:
		_embers.append([randf(), randf(), 0.35 + randf() * 0.9])
	super._ready()


func _stages() -> Array:
	return STAGES


## EAS: the player stands inside the ancient forge; its embers are the air.
func _env() -> Array:
	return ["env-forge", "embers", [Vector2(0.5, 0.88)]]


func _leave_label() -> String:
	return "bank the fire"


func _initial_stage() -> int:
	var shot_stage := OS.get_environment("MF_FORGE_STAGE")
	if shot_stage != "":
		return int(shot_stage)
	return STAGES.size() - 1 if start_at_quench else 0   # Quenching is the last rune


func _on_stage_entered(_i: int) -> void:
	_status.text = ""
	_story_edit = null


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


## A collapsible free-text panel: the player's own story for a class or
## background. The GM adapts whatever's written to the world they land in.
func _story_fold(title: String, hint: String, draft_key: String) -> Control:
	var fold := Fold.new(title, str(draft[draft_key]) != "")
	var hl := Label.new()
	hl.theme_type_variation = "HintLabel"
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size = Vector2(560, 0)
	hl.text = hint
	fold.content.add_child(hl)
	var edit := TextEdit.new()
	edit.placeholder_text = "In your own words…"
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(560, 80)
	edit.text = str(draft[draft_key])
	fold.content.add_child(edit)
	_story_edit = edit
	var cc := CenterContainer.new()
	cc.add_child(fold)
	return cc


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_origin()
		1:
			_stage_ruleset()
		2:
			_stage_heritage()
		3:
			_stage_class()
		4:
			_stage_background()
		5:
			_stage_nature()
		6:
			_stage_appearance()
		7:
			_stage_voice()
		8:
			_stage_equipment()
		9:
			_stage_quenching()


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
			_enter_stage(9)
		)
	_nav(-1, "Continue ›", func():   # first stage now — nothing behind it
		if str(draft["origin"]) == "":
			draft["origin"] = "Raw Metal"
		_enter_stage(1))


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
	_nav(0, "Continue ›", func(): _enter_stage(2))


## The heritages, each with a generated portrait that fills in as you browse
## (the "pictures of each race" — painted once, cached forever after).
func _stage_heritage() -> void:
	_title_label("Choose Your Heritage")
	var hs: Dictionary = Rules.tables.get("heritages", {})
	var names := hs.keys()
	names.sort()
	var split := HBoxContainer.new()
	split.alignment = BoxContainer.ALIGNMENT_CENTER
	split.add_theme_constant_override("separation", Ui.SPACE["l"])
	# Left: the race portrait preview.
	var preview := VBoxContainer.new()
	preview.alignment = BoxContainer.ALIGNMENT_CENTER
	preview.custom_minimum_size = Vector2(280, 0)
	var port := TextureRect.new()
	port.custom_minimum_size = Vector2(256, 256)
	port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(port)
	var pname := Label.new()
	pname.theme_type_variation = "HeaderLabel"
	pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_child(pname)
	var ptraits := RichTextLabel.new()
	ptraits.bbcode_enabled = true
	ptraits.fit_content = true
	ptraits.custom_minimum_size = Vector2(280, 90)
	preview.add_child(ptraits)
	split.add_child(preview)
	# Right: the roster of heritages.
	var cards: Array = []
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	var cur_key := {"k": ""}
	var show_race := func(nm: String):
		var h: Dictionary = hs[nm]
		pname.text = nm
		var traits: Array = h.get("traits", [])
		ptraits.text = "[color=%s]%d ft speed[/color]\n%s" % [Ui.c("gold_soft").to_html(false),
			int(h.get("speed", 30)), "\n".join(traits.map(func(t): return "• " + str(t).replace("[", "[lb]")))]
		var key := "race-" + str(nm).to_lower().replace(" ", "-").validate_filename()
		cur_key["k"] = key
		var tex := Art.texture_for(key)
		if tex != null:
			port.texture = tex
		else:
			port.texture = null
			_status.text = "Painting the %s…" % nm
			Art.ensure(key, _race_prompt(nm, h))
	for nm in names:
		var h: Dictionary = hs[nm]
		var traits: Array = h.get("traits", [])
		var card := Card.new({"glyph": "shield", "title": str(nm),
			"body": str(traits[0]).split("—")[0].strip_edges() if not traits.is_empty() else "",
			"foot": "%d ft" % int(h.get("speed", 30))})
		card.set_selected(str(draft["race"]) == str(nm))
		card.pressed.connect(func():
			draft["race"] = str(nm)
			for c in cards:
				c.set_selected(c == card)
			show_race.call(str(nm)))
		cards.append(card)
		grid.add_child(card)
	split.add_child(grid)
	_stage_box.add_child(split)
	Art.art_ready.connect(func(k):
		if str(k) == cur_key["k"] and is_instance_valid(port):
			port.texture = Art.texture_for(str(k))
			_status.text = ""
			Ui.pulse(port))
	if str(draft["race"]) != "":
		show_race.call(str(draft["race"]))
	_nav(1, "Strike ›", func():
		if str(draft["race"]) == "":
			_status.text = "The metal needs a heritage — choose one."
			return
		_enter_stage(3))


## The commission for a heritage reference portrait — world-flavored.
func _race_prompt(nm: String, h: Dictionary) -> String:
	var traits: Array = h.get("traits", [])
	var look := str(traits[0]).split("—")[0].strip_edges() if not traits.is_empty() else ""
	return "character concept portrait of a %s%s, %s fantasy, head and shoulders, neutral heroic pose, detailed face and costume, dramatic rim light, dark background, painted illustration, no text" % [
		nm, (", " + look) if look != "" else "", Art.world_flavor()]


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
	var story := _story_fold("Make this path your own (optional)",
		"Why did you take up this class? A mentor, a curse, a debt, a calling — the GM weaves it into whatever world you're dropped into.",
		"cls_story")
	_stage_box.add_child(story)
	_nav(2, "Strike ›", func():
		if str(draft["cls"]) == "":
			_status.text = "The blade needs a shape — choose a class."
			return
		if _story_edit != null:
			draft["cls_story"] = _story_edit.text.strip_edges()
		_enter_stage(4))


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
	var story := _story_fold("Your story, in your words (optional)",
		"Where do you come from, and what set you on the road? The GM reinterprets your past inside whatever world the tale drops you into.",
		"bg_story")
	_stage_box.add_child(story)
	_nav(3, "Strike ›", func():
		if str(draft["bg"]) == "":
			_status.text = "Every legend was someone first — choose a background."
			return
		if _story_edit != null:
			draft["bg_story"] = _story_edit.text.strip_edges()
		_enter_stage(5))


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
	# R5 VIS-08 / R6 FUN-03 — the one place in the game where dice genuinely are
	# NOT shown. Combat rolls animate (game.gd `_animate_die`), but the moment a
	# hero's whole nature is decided printed "Destiny: 15, 14, 13, 10, 10, 9" as a
	# comma list, with no roll and no ability names — so the player never met
	# STR/DEX/CON until the sheet, after creation. The six numbers now land as
	# faces, one after another, and each says what it will become.
	var dice_row := HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", Ui.SPACE["s"])
	var dice_l := Label.new()
	dice_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_l.theme_type_variation = "HintLabel"
	dice_l.text = "the best land where your class wants them"
	var show_roll := func():
		for ch in dice_row.get_children():
			ch.queue_free()
		var order: Array = Rules.ABILITIES
		for i in draft["rolled"].size():
			var face := PanelContainer.new()
			face.add_theme_stylebox_override("panel", Ui.sb_card())
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 0)
			var v := Label.new()
			v.text = str(draft["rolled"][i])
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_theme_font_size_override("font_size", 26)
			v.add_theme_color_override("font_color", Ui.c("gold"))
			var nm := Label.new()
			nm.theme_type_variation = "HintLabel"
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.add_theme_font_size_override("font_size", 10)
			nm.text = str(order[i]) if i < order.size() else ""
			box.add_child(v)
			box.add_child(nm)
			face.add_child(box)
			face.custom_minimum_size = Vector2(58, 58)
			dice_row.add_child(face)
			Ui.reveal(face, i * 0.07)   # they arrive as a roll, not as a list
	if not draft["rolled"].is_empty():
		show_roll.call()
	_stage_box.add_child(dice_row)
	_stage_box.add_child(dice_l)
	var reroll := Button.new()
	reroll.text = "Reroll destiny (4d6, drop lowest)"
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
	_nav(4, "Strike ›", func():
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
		_enter_stage(6))


## The portrait commission — shared by the live Appearance preview and the
## Quenching so the face the player approves is the face the hero wears.
func _portrait_prompt(nm: String) -> String:
	return "character portrait of %s, a %s %s, %s%s style, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face, no text" % [
		nm if nm != "" else "a hero", str(draft["race"]), str(draft["cls"]),
		(str(draft["appearance"]) + ", ") if str(draft["appearance"]) != "" else "", str(draft["style"])]


const LOOK_GUIDES := ["build", "age", "hair", "eyes", "skin", "garb", "bearing", "a scar or mark", "a color they wear"]


func _stage_appearance() -> void:
	_title_label("Their Face, In Words")
	var split := HBoxContainer.new()
	split.alignment = BoxContainer.ALIGNMENT_CENTER
	split.add_theme_constant_override("separation", Ui.SPACE["l"])
	# The living portrait — it forms from the words on the right.
	var port := TextureRect.new()
	port.custom_minimum_size = Vector2(236, 236)
	port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if str(draft["portrait_key"]) != "" and Art.has_art(str(draft["portrait_key"])):
		port.texture = Art.texture_for(str(draft["portrait_key"]))
	split.add_child(port)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(540, 0)
	right.add_theme_constant_override("separation", Ui.SPACE["s"])
	var desc := TextEdit.new()
	desc.placeholder_text = "e.g. wind-burned and lean, silver-braided, past forty, eyes like a storm about to break, a soldier's grey coat…"
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.custom_minimum_size = Vector2(540, 88)
	desc.text = str(draft["appearance"])
	right.add_child(desc)
	# Writing guides: tap to add a detail the painter should know.
	var guide_hint := Label.new()
	guide_hint.theme_type_variation = "HintLabel"
	guide_hint.text = "The more you name, the truer the face. Tap to add a detail:"
	right.add_child(guide_hint)
	var guides := HFlowContainer.new()
	guides.add_theme_constant_override("h_separation", Ui.SPACE["xs"])
	guides.add_theme_constant_override("v_separation", Ui.SPACE["xs"])
	for gd in LOOK_GUIDES:
		var chip := Button.new()
		chip.theme_type_variation = "GhostButton"
		chip.text = "+ " + gd
		chip.pressed.connect(func():
			var pre: String = desc.text.strip_edges()
			desc.text = pre + (("\n" if pre != "" else "") + gd + ": ")
			desc.set_caret_line(desc.get_line_count() - 1)
			desc.set_caret_column(desc.get_line(desc.get_line_count() - 1).length())
			desc.grab_focus())
		guides.add_child(chip)
	right.add_child(guides)
	# The brush: style chips.
	var chip_row := HFlowContainer.new()
	chip_row.add_theme_constant_override("h_separation", Ui.SPACE["xs"])
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
	right.add_child(chip_row)
	# Envision — paint the hero from the words, live.
	var envision := Button.new()
	envision.theme_type_variation = "AccentButton"
	envision.text = "Envision this hero"
	envision.pressed.connect(func():
		draft["appearance"] = desc.text.strip_edges()
		draft["portrait_key"] = "heroprev"
		Art.forget("heroprev")
		port.texture = null
		_status.text = "The painter takes up the brush…"
		Art.ensure("heroprev", _portrait_prompt(str(draft["name"]))))
	right.add_child(envision)
	split.add_child(right)
	_stage_box.add_child(split)
	Art.art_ready.connect(func(k):
		if str(k) == "heroprev" and is_instance_valid(port):
			port.texture = Art.texture_for("heroprev")
			_status.text = ""
			Ui.pulse(port))
	_nav(5, "Strike ›", func():
		draft["appearance"] = desc.text.strip_edges()
		_enter_stage(7))


func _stage_voice() -> void:
	_title_label("The Voice")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var vc := Card.new({"glyph": "🔇", "title": "Awaiting the Bards", "body": "the voice provider sleeps — this rune wakes when it does"})
	vc.disabled = true
	vc.modulate = Color(1, 1, 1, 0.45)
	row.add_child(vc)
	_stage_box.add_child(row)
	_nav(6, "Continue ›", func(): _enter_stage(8))


func _stage_equipment() -> void:
	_title_label("Choose Your Kit")
	var sel := ""
	for k in KITS:
		if draft["kit"] == k["items"]:
			sel = str(k["title"])
	_card_grid(KITS, 3, sel, func(e): draft["kit"] = e["items"])
	_nav(7, "To the Quenching ›", func():
		if draft["kit"].is_empty():
			draft["kit"] = KITS[0]["items"]
		_enter_stage(9))


# ── The Quenching: steam, gold, the finished legend ─────────────────────────
func _stage_quenching() -> void:
	_title_label("The Quenching")
	var portrait := MythPortrait.new(150, "gold", true)
	# Prefer the face the player already approved at Appearance; else commission
	# it now (works in menu mode too — the Quenching always shows a face).
	var pkey: String = str(draft["portrait_key"]) if str(draft["portrait_key"]) != "" and Art.has_art(str(draft["portrait_key"])) else ""
	if pkey == "":
		pkey = "heroprev" if menu_mode else ("hero-" + GameState.cid().validate_filename())
		draft["portrait_key"] = pkey
		Art.ensure(pkey, _portrait_prompt(str(draft["name"])))
	portrait.set_portrait(Art.round_tex(pkey), str(draft["name"]).left(1) if str(draft["name"]) != "" else "?")
	Art.art_ready.connect(func(k):
		if str(k) == pkey and is_instance_valid(portrait):
			portrait.set_portrait(Art.round_tex(pkey), "?")
			Ui.pulse(portrait))
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
	epithet.text = "%s %s · %s · %s · kit: %s" % [str(draft["race"]), str(draft["cls"]), str(draft["bg"]), nature,
		", ".join(draft["kit"])]
	epithet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epithet.custom_minimum_size = Vector2(620, 0)
	_stage_box.add_child(epithet)
	var restrike := Button.new()
	restrike.theme_type_variation = "GhostButton"
	restrike.text = "Re-strike the portrait"
	restrike.pressed.connect(func():
		Art.forget(pkey)
		portrait.set_portrait(null, "…")
		draft["name"] = name_in.text.strip_edges()
		Art.ensure(pkey, _portrait_prompt(name_in.text.strip_edges())))
	var rsc := CenterContainer.new()
	rsc.add_child(restrike)
	_stage_box.add_child(rsc)
	_nav(8, "BEGIN THE ADVENTURE" if not menu_mode else "BANK THIS LEGEND", func():
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

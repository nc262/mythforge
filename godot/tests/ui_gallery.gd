extends Control
## MDL gallery — every design-system component on one screen, with fake data.
## The visual-regression page: screenshot before/after any system change.
##   MF_SHOT_SCENE=res://tests/ui_gallery.tscn (via screenshot.tscn), or run
##   directly to eyeball hover/press/reveal motion.

const Card := preload("res://ui/myth_card.gd")
const Socket := preload("res://ui/myth_socket.gd")
const Header := preload("res://ui/myth_header.gd")
const Gauge := preload("res://ui/myth_gauge.gd")
const Portrait := preload("res://ui/myth_portrait.gd")


func _ready() -> void:
	Ui.apply("embervale")
	theme = Ui.theme
	var bg := ColorRect.new()
	bg.color = Ui.c("night")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", Ui.SPACE["xl"])
	margin.add_theme_constant_override("margin_top", Ui.SPACE["l"])
	margin.add_theme_constant_override("margin_right", Ui.SPACE["xl"])
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	margin.add_child(col)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Mythforge Design Language"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	Ui.breathe(title)

	col.add_child(Header.new("Buttons"))
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", Ui.SPACE["m"])
	for spec in [["Forged", ""], ["Primary", "AccentButton"], ["Ghost", "GhostButton"]]:
		var b := Button.new()
		b.text = spec[0]
		if spec[1] != "":
			b.theme_type_variation = spec[1]
		brow.add_child(b)
	col.add_child(brow)

	col.add_child(Header.new("Cards & rarity halos"))
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", Ui.SPACE["m"])
	for rar in ["common", "uncommon", "rare", "epic", "legendary"]:
		var card := Card.new()
		card.setup({"rarity": rar, "glyph": "⚔", "qty": 3 if rar == "common" else 1,
			"tip_title": rar.capitalize() + " Blade",
			"tip_rows": [["1d8 slashing"], ["+1 to hit", "gold"], ["vs equipped: ▲ +1 ATK", "gold"], ["sells for 32", "ink_dim"]]})
		crow.add_child(card)
	col.add_child(crow)

	col.add_child(Header.new("Sockets — empty · filled"))
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", Ui.SPACE["m"])
	srow.add_child(Socket.new("weapon", "⚔"))
	var filled := Socket.new("armor", "🥋")
	filled.set_item({"glyph": "🥋", "tip_title": "Traveler's Leathers", "rarity": "uncommon"})
	srow.add_child(filled)
	col.add_child(srow)

	col.add_child(Header.new("Portraits & gauges"))
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", Ui.SPACE["l"])
	var hero := Portrait.new(84, "gold", true)
	hero.set_portrait(Art.round_tex("hero-dm-godot-demo", 84), "W")
	prow.add_child(hero)
	var foe := Portrait.new(64, "danger")
	foe.set_portrait(null, "G")
	prow.add_child(foe)
	var gcol := VBoxContainer.new()
	gcol.add_theme_constant_override("separation", Ui.SPACE["s"])
	for spec in [["Pack", "gold", 17.0, 24.0], ["HP", "danger", 21.0, 26.0], ["XP", "amethyst", 640.0, 1000.0]]:
		var gauge := Gauge.new(spec[0], spec[1])
		gauge.custom_minimum_size = Vector2(220, 18)
		gauge.set_value(spec[2], spec[3])
		gcol.add_child(gauge)
	prow.add_child(gcol)
	col.add_child(prow)

	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.text = "hover lifts · press dips · rarity glows · framed tooltips · reveal stagger on entry"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	Ui.polish(self)
	Ui.reveal_children(col)
	if OS.get_environment("MF_GALLERY_QUIT") == "1":
		await get_tree().create_timer(1.2).timeout
		print("GALLERY OK")
		get_tree().quit(0)

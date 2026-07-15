extends Node
## Skin — the web studio's "Enchanted Arcane" design system, ported.
## Palettes lifted verbatim from static/studio.css (.studio-root tokens and
## the per-world overrides). apply(world_id) rebuilds the Theme; screens set
## `theme = Skin.theme` and listen to `changed` if they're already on screen.

signal changed

const PALETTES := {
	"arcane": {  # Embervale / default — candlelit fantasy
		"night": Color("0c0a1c"), "night2": Color("120e26"),
		"surface": Color("1a1432"), "surface2": Color("221a3e"), "sheet": Color("241d3a"),
		"border": Color("3a2f5c"), "border_soft": Color("2a2247"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9286b8"),
		"gold": Color("e8c171"), "gold_soft": Color("f0d49a"),
		"amethyst": Color("b79cf6"), "amethyst_deep": Color("7c5cd6"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
	"neonspire": {  # sci-fi — neon cyan + magenta
		"night": Color("05070f"), "night2": Color("0a0f1f"),
		"surface": Color("0f1830"), "surface2": Color("142244"), "sheet": Color("101a33"),
		"border": Color("214066"), "border_soft": Color("16294a"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9286b8"),
		"gold": Color("2de2e6"), "gold_soft": Color("7ef0f2"),
		"amethyst": Color("ff5fd2"), "amethyst_deep": Color("b026ff"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
	"everyday": {  # slice of life — warm café tones
		"night": Color("0d0f14"), "night2": Color("15171e"),
		"surface": Color("1b1e26"), "surface2": Color("232733"), "sheet": Color("1d2129"),
		"border": Color("353b49"), "border_soft": Color("262b36"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9286b8"),
		"gold": Color("e0a96d"), "gold_soft": Color("f0c79a"),
		"amethyst": Color("6ea8fe"), "amethyst_deep": Color("4571c4"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
}

var world_id := ""
var reduce_motion := false
var pal: Dictionary = PALETTES["arcane"]
var theme := Theme.new()
var serif := SystemFont.new()
var sans := SystemFont.new()


func _ready() -> void:
	serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia"])
	sans.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial"])
	_build()


func apply(wid: String) -> void:
	world_id = wid
	pal = PALETTES.get(wid if PALETTES.has(wid) else "arcane", PALETTES["arcane"])
	_build()
	changed.emit()


func c(name: String) -> Color:
	return pal[name]


func _flat(bg: Color, border: Color, radius := 9, border_w := 1, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _build() -> void:
	theme.default_font = sans
	theme.default_font_size = 15

	# Buttons — quiet surface, gold on hover (the studio's tab/button feel).
	theme.set_stylebox("normal", "Button", _flat(c("surface2"), c("border")))
	var hover := _flat(c("surface2").lightened(0.05), c("gold"))
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", _flat(c("night2"), c("gold")))
	theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, c("amethyst")))
	theme.set_stylebox("disabled", "Button", _flat(c("surface"), c("border_soft")))
	theme.set_color("font_color", "Button", c("ink_soft"))
	theme.set_color("font_hover_color", "Button", c("gold_soft"))
	theme.set_color("font_pressed_color", "Button", c("gold"))
	theme.set_color("font_disabled_color", "Button", c("ink_dim"))

	# Accent button — the roll bar / primary action, gold-glow style.
	theme.set_type_variation("AccentButton", "Button")
	var acc := _flat(Color(c("gold"), 0.12), c("gold"), 12, 1, 12)
	theme.set_stylebox("normal", "AccentButton", acc)
	theme.set_stylebox("hover", "AccentButton", _flat(Color(c("gold"), 0.22), c("gold_soft"), 12, 1, 12))
	theme.set_stylebox("pressed", "AccentButton", _flat(Color(c("gold"), 0.30), c("gold_soft"), 12, 1, 12))
	theme.set_color("font_color", "AccentButton", c("gold_soft"))
	theme.set_color("font_hover_color", "AccentButton", c("gold_soft"))
	theme.set_font("font", "AccentButton", sans)
	theme.set_font_size("font_size", "AccentButton", 16)

	# Inputs — night wells with an amethyst focus ring.
	theme.set_stylebox("normal", "LineEdit", _flat(c("night2"), c("border_soft")))
	theme.set_stylebox("focus", "LineEdit", _flat(c("night2"), c("amethyst")))
	theme.set_color("font_color", "LineEdit", c("ink"))
	theme.set_color("font_placeholder_color", "LineEdit", c("ink_dim"))
	theme.set_color("caret_color", "LineEdit", c("gold"))

	# Panels / lists / text.
	theme.set_stylebox("panel", "PanelContainer", _flat(c("surface"), c("border_soft"), 14, 1, 14))
	theme.set_stylebox("panel", "ItemList", _flat(c("surface"), c("border_soft"), 14, 1, 10))
	theme.set_stylebox("selected", "ItemList", _flat(Color(c("gold"), 0.14), c("gold"), 7, 1, 6))
	theme.set_stylebox("selected_focus", "ItemList", _flat(Color(c("gold"), 0.18), c("gold"), 7, 1, 6))
	theme.set_color("font_color", "ItemList", c("ink_soft"))
	theme.set_color("font_selected_color", "ItemList", c("gold_soft"))
	theme.set_stylebox("normal", "RichTextLabel", _flat(Color(c("sheet"), 0.82), c("border_soft"), 14, 1, 16))
	theme.set_color("default_color", "RichTextLabel", c("ink"))
	theme.set_color("font_color", "Label", c("ink_soft"))

	# Title — the serif, candle-gold brand line ("MYTHFORGE ✦").
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", serif)
	theme.set_font_size("font_size", "TitleLabel", 30)
	theme.set_color("font_color", "TitleLabel", c("gold_soft"))

	# Dim hint text.
	theme.set_type_variation("HintLabel", "Label")
	theme.set_color("font_color", "HintLabel", c("ink_dim"))
	theme.set_font_size("font_size", "HintLabel", 13)

	# Chat bubbles — the studio's parchment GM / candle-gold player look.
	theme.set_type_variation("BubbleGm", "PanelContainer")
	var gm_sb := _flat(Color(c("sheet"), 0.92), c("border_soft"), 14, 1, 14)
	gm_sb.corner_radius_top_left = 4  # speech points back at the teller
	theme.set_stylebox("panel", "BubbleGm", gm_sb)
	theme.set_type_variation("BubbleMe", "PanelContainer")
	var me_sb := _flat(Color(c("gold"), 0.10), Color(c("gold"), 0.55), 14, 1, 14)
	me_sb.corner_radius_top_right = 4
	theme.set_stylebox("panel", "BubbleMe", me_sb)

	# The dice overlay — a candle-lit card the roll tumbles on.
	theme.set_type_variation("DicePanel", "PanelContainer")
	var dice_sb := _flat(c("surface2"), c("gold"), 18, 2, 26)
	dice_sb.shadow_color = Color(c("gold"), 0.25)
	dice_sb.shadow_size = 24
	theme.set_stylebox("panel", "DicePanel", dice_sb)
	theme.set_type_variation("DieLabel", "Label")
	theme.set_font("font", "DieLabel", serif)
	theme.set_font_size("font_size", "DieLabel", 54)
	theme.set_color("font_color", "DieLabel", c("gold_soft"))

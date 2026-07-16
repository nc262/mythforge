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

# ── Design-language tokens (docs/DesignSystem.md) — the ONLY numbers allowed
const SPACE := {"xs": 4, "s": 8, "m": 14, "l": 22, "xl": 34}
const TIME := {"fast": 0.12, "base": 0.22, "slow": 0.45, "breath": 3.2}
const RADIUS := {"s": 4, "m": 9, "l": 18}
const RARITY := {"common": "border", "uncommon": "gold_soft", "rare": "amethyst",
	"epic": "ember", "legendary": "gold"}

var world_id := ""
var reduce_motion := false
var pal: Dictionary = PALETTES["arcane"]
var theme := Theme.new()
var serif := SystemFont.new()
var sans := SystemFont.new()
var display: FontVariation  # tracked serif — titles and headers
var _glow: ImageTexture     # cached radial halo


func rarity_color(r: String) -> Color:
	return c(RARITY.get(r, "border"))


func _ready() -> void:
	serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia"])
	sans.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial"])
	display = FontVariation.new()
	display.base_font = serif
	display.spacing_glyph = 2  # letter-spaced smallcaps energy
	_build()


# ── Procedural surfaces: forged slabs, ornate frames, parchment grain ───────
## A nine-patch slab: vertical steel gradient, black outer line, trim inner
## line, a highlight kiss on top and a shadow bite below — buttons struck on
## an anvil instead of drawn in a spreadsheet.
func forged_tex(base: Color, trim: Color, trim_alpha := 0.8) -> ImageTexture:
	var s := 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		var t := float(y) / float(s - 1)
		var row := base.lightened(0.10).lerp(base.darkened(0.30), t)
		for x in s:
			img.set_pixel(x, y, row)
	var outer := base.darkened(0.75)
	for i in s:
		img.set_pixel(i, 0, outer)
		img.set_pixel(i, s - 1, outer)
		img.set_pixel(0, i, outer)
		img.set_pixel(s - 1, i, outer)
	var tr := Color(trim, trim_alpha)
	for i in range(1, s - 1):
		img.set_pixel(i, 1, tr)
		img.set_pixel(i, s - 2, Color(trim, trim_alpha * 0.55))
		img.set_pixel(1, i, tr)
		img.set_pixel(s - 2, i, Color(trim, trim_alpha * 0.55))
	for i in range(2, s - 2):
		img.set_pixel(i, 2, Color(1, 1, 1, 0.10))       # anvil highlight
		img.set_pixel(i, s - 3, Color(0, 0, 0, 0.30))   # under-shadow
	return ImageTexture.create_from_image(img)


## An ornate frame: double trim lines with corner diamonds over a deep panel —
## the BG3 window language, drawn from math.
func ornate_frame_tex(base: Color, trim: Color) -> ImageTexture:
	var s := 48
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(base, 0.96))
	var edge := base.darkened(0.8)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	for spec in [[0.95, 2], [0.35, 5]]:
		var cc := Color(trim, spec[0])
		var inset: int = spec[1]
		for i in range(inset, s - inset):
			img.set_pixel(i, inset, cc)
			img.set_pixel(i, s - 1 - inset, cc)
			img.set_pixel(inset, i, cc)
			img.set_pixel(s - 1 - inset, i, cc)
	for corner in [[2, 2], [s - 3, 2], [2, s - 3], [s - 3, s - 3]]:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					var px: int = corner[0] + dx
					var py: int = corner[1] + dy
					if px >= 0 and px < s and py >= 0 and py < s:
						img.set_pixel(px, py, trim)
	return ImageTexture.create_from_image(img)


## Parchment grain: the panel color with a whisper of noise — surfaces stop
## being flat without shouting about it.
func grain_tex(base: Color, strength := 0.045) -> ImageTexture:
	var s := 64
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.55
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var n := noise.get_noise_2d(x, y) * strength
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n, 0.94))
	return ImageTexture.create_from_image(img)


## A radial halo — modulate to tint (rarity glows, milestones, portrait rims).
func glow_tex() -> ImageTexture:
	if _glow != null:
		return _glow
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var r := s / 2.0
	for y in s:
		for x in s:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length() / r
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.9))
	_glow = ImageTexture.create_from_image(img)
	return _glow


## A carved socket: the dark well an equipment piece sits in. Lit = filled.
func sb_socket(lit := false) -> StyleBoxFlat:
	var sb := _flat(c("night").darkened(0.2), Color(c("gold"), 0.55) if lit else c("border_soft"), RADIUS["m"], 2, 8)
	if lit:
		sb.shadow_color = Color(c("gold"), 0.25)
		sb.shadow_size = 8
	return sb


## An item/entity card face: night steel wearing its rarity's halo.
func sb_card(rarity := "common") -> StyleBoxFlat:
	var rc := rarity_color(rarity)
	var sb := _flat(Color(c("night2"), 0.92), rc, RADIUS["m"], 2, 6)
	if rarity != "common":
		sb.shadow_color = Color(rc, 0.4)
		sb.shadow_size = 7
	return sb


# ── Motion vocabulary (docs/DesignSystem.md §3) — all honor reduce_motion ───
## Hover-lift + press-dip for every Button under root. One call per screen;
## call again after building dynamic dialogs. Audio hook mounts here later.
func polish(root: Node) -> void:
	if reduce_motion:
		return
	var targets: Array = root.find_children("*", "Button", true, false)
	if root is Button:
		targets.append(root)
	for n in targets:
		if n.has_meta("_polished"):
			continue
		n.set_meta("_polished", true)
		n.mouse_entered.connect(_lift.bind(n, 1.045))
		n.mouse_exited.connect(_lift.bind(n, 1.0))
		n.button_down.connect(_lift.bind(n, 0.96))
		n.button_up.connect(_lift.bind(n, 1.045))


func _lift(n: Control, to: float) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	n.pivot_offset = n.size / 2.0
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2.ONE * to, TIME["fast"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Entry ceremony: fade in + settle. Container-safe (no position animation).
func reveal(ctrl: Control, delay := 0.0) -> void:
	if reduce_motion or not ctrl.is_inside_tree():
		return
	ctrl.modulate.a = 0.0
	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.scale = Vector2.ONE * 0.985
	var tw := ctrl.create_tween().set_parallel(true)
	tw.tween_property(ctrl, "modulate:a", 1.0, TIME["base"]).set_delay(delay)
	tw.tween_property(ctrl, "scale", Vector2.ONE, TIME["slow"]).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func reveal_children(container: Node, stagger := 0.05) -> void:
	var i := 0
	for ch in container.get_children():
		if ch is Control and ch.visible:
			reveal(ch, i * stagger)
			i += 1


## A slow luminous breath. ONE monumental element per screen, max.
func breathe(ctrl: CanvasItem) -> void:
	if reduce_motion:
		return
	var tw := ctrl.create_tween().set_loops()
	tw.tween_property(ctrl, "modulate", Color(1.06, 1.05, 1.0), TIME["breath"] / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ctrl, "modulate", Color(0.97, 0.96, 1.0), TIME["breath"] / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## One-shot attention pop: a slot fills, a chip lands, a node unlocks.
func pulse(ctrl: Control) -> void:
	if reduce_motion:
		return
	ctrl.pivot_offset = ctrl.size / 2.0
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "scale", Vector2.ONE * 1.10, TIME["fast"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2.ONE, TIME["base"]).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rising ghost text (damage, gold, XP) at a canvas position.
func rise_text(parent: Node, text: String, color: Color, at: Vector2) -> void:
	var lab := Label.new()
	lab.text = text
	lab.theme_type_variation = "TitleLabel"
	lab.add_theme_color_override("font_color", color)
	lab.position = at
	lab.z_index = 100
	parent.add_child(lab)
	if reduce_motion:
		lab.queue_free()
		return
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", at.y - 46.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(lab.queue_free)


func _nine(tex: ImageTexture, margin: int, content: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb


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

	# Buttons — forged slabs: steel gradient, black edge, trim line, bevel.
	theme.set_stylebox("normal", "Button", _nine(forged_tex(c("surface2"), c("border")), 6, 12))
	theme.set_stylebox("hover", "Button", _nine(forged_tex(c("surface2").lightened(0.07), c("gold"), 0.95), 6, 12))
	theme.set_stylebox("pressed", "Button", _nine(forged_tex(c("night2"), c("gold")), 6, 12))
	theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, c("amethyst"), 6, 1, 12))
	theme.set_stylebox("disabled", "Button", _nine(forged_tex(c("surface"), c("border_soft"), 0.4), 6, 12))
	theme.set_color("font_color", "Button", c("ink_soft"))
	theme.set_color("font_hover_color", "Button", c("gold_soft"))
	theme.set_color("font_pressed_color", "Button", c("gold"))
	theme.set_color("font_disabled_color", "Button", c("ink_dim"))
	theme.set_font("font", "Button", display)
	theme.set_font_size("font_size", "Button", 15)

	# Accent button — gold-trimmed dark iron; the primary action sings.
	theme.set_type_variation("AccentButton", "Button")
	theme.set_stylebox("normal", "AccentButton", _nine(forged_tex(c("night2").lerp(c("gold"), 0.10), c("gold"), 1.0), 6, 14))
	theme.set_stylebox("hover", "AccentButton", _nine(forged_tex(c("night2").lerp(c("gold"), 0.20), c("gold_soft"), 1.0), 6, 14))
	theme.set_stylebox("pressed", "AccentButton", _nine(forged_tex(c("night2"), c("gold_soft"), 1.0), 6, 14))
	theme.set_color("font_color", "AccentButton", c("gold_soft"))
	theme.set_color("font_hover_color", "AccentButton", Color(c("gold_soft")).lightened(0.15))
	theme.set_font("font", "AccentButton", display)
	theme.set_font_size("font_size", "AccentButton", 17)

	# Inputs — night wells with an amethyst focus ring.
	theme.set_stylebox("normal", "LineEdit", _flat(c("night2"), c("border_soft")))
	theme.set_stylebox("focus", "LineEdit", _flat(c("night2"), c("amethyst")))
	theme.set_color("font_color", "LineEdit", c("ink"))
	theme.set_color("font_placeholder_color", "LineEdit", c("ink_dim"))
	theme.set_color("caret_color", "LineEdit", c("gold"))

	# Panels — ornate double-trim frames with corner diamonds; lists ride the
	# same language; long-form text sits on parchment grain.
	theme.set_stylebox("panel", "PanelContainer", _nine(ornate_frame_tex(c("surface"), c("border")), 10, 16))
	theme.set_stylebox("panel", "ItemList", _nine(ornate_frame_tex(c("surface"), c("border_soft")), 10, 12))
	theme.set_stylebox("selected", "ItemList", _flat(Color(c("gold"), 0.14), c("gold"), 4, 1, 6))
	theme.set_stylebox("selected_focus", "ItemList", _flat(Color(c("gold"), 0.18), c("gold"), 4, 1, 6))
	theme.set_color("font_color", "ItemList", c("ink_soft"))
	theme.set_color("font_selected_color", "ItemList", c("gold_soft"))
	var parchment := _nine(grain_tex(c("sheet")), 4, 16)
	theme.set_stylebox("normal", "RichTextLabel", parchment)
	theme.set_color("default_color", "RichTextLabel", c("ink"))
	theme.set_color("font_color", "Label", c("ink_soft"))
	# Windows/dialogs wear the ornate frame too.
	theme.set_stylebox("embedded_border", "Window", _nine(ornate_frame_tex(c("night2"), c("gold")), 12, 20))
	theme.set_color("title_color", "Window", c("gold_soft"))
	theme.set_font("title_font", "Window", display)
	theme.set_font_size("title_font_size", "Window", 18)

	# Ghost button — low-emphasis actions; quiet until courted.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_stylebox("normal", "GhostButton", _flat(Color(c("night2"), 0.0), Color(c("border"), 0.0), RADIUS["s"], 1, 8))
	theme.set_stylebox("hover", "GhostButton", _flat(Color(c("gold"), 0.07), Color(c("gold"), 0.35), RADIUS["s"], 1, 8))
	theme.set_stylebox("pressed", "GhostButton", _flat(Color(c("gold"), 0.12), c("gold"), RADIUS["s"], 1, 8))

	# The engine's own tooltip wears the frame — no OS default ever shows.
	theme.set_stylebox("panel", "TooltipPanel", _nine(ornate_frame_tex(c("night2"), c("gold")), 10, 12))
	theme.set_color("font_color", "TooltipLabel", c("ink_soft"))

	# Sockets and cards as theme variations (styleboxes also exposed as fns).
	theme.set_type_variation("SocketPanel", "PanelContainer")
	theme.set_stylebox("panel", "SocketPanel", sb_socket())
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", sb_card())

	# Title — tracked serif with a candle-glow outline.
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", display)
	theme.set_font_size("font_size", "TitleLabel", 30)
	theme.set_color("font_color", "TitleLabel", c("gold_soft"))
	theme.set_color("font_outline_color", "TitleLabel", Color(c("gold"), 0.22))
	theme.set_constant("outline_size", "TitleLabel", 10)

	# Section headers — small tracked gold caps.
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", display)
	theme.set_font_size("font_size", "HeaderLabel", 16)
	theme.set_color("font_color", "HeaderLabel", c("gold"))

	# Dim hint text.
	theme.set_type_variation("HintLabel", "Label")
	theme.set_color("font_color", "HintLabel", c("ink_dim"))
	theme.set_font_size("font_size", "HintLabel", 13)

	# Chat bubbles — grained parchment for the GM, gold-edged vellum for you.
	theme.set_type_variation("BubbleGm", "PanelContainer")
	var gm_sb := _nine(grain_tex(c("sheet")), 4, 14)
	theme.set_stylebox("panel", "BubbleGm", gm_sb)
	theme.set_type_variation("BubbleMe", "PanelContainer")
	var me_sb := _flat(Color(c("gold"), 0.10), Color(c("gold"), 0.55), 10, 1, 14)
	me_sb.corner_radius_top_right = 3
	me_sb.shadow_color = Color(c("gold"), 0.10)
	me_sb.shadow_size = 8
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

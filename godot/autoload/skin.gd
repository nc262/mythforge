extends Node
## Skin — the web studio's "Enchanted Arcane" design system, ported.
## Palettes lifted verbatim from static/studio.css (.studio-root tokens and
## the per-world overrides). apply(world_id) rebuilds the Theme; screens set
## `theme = WorldSkin.theme` and listen to `changed` if they're already on screen.

signal changed

const PALETTES := {
	"arcane": {  # Embervale / default — candlelit fantasy
		"night": Color("0c0a1c"), "night2": Color("120e26"),
		"surface": Color("1a1432"), "surface2": Color("221a3e"), "sheet": Color("241d3a"),
		"border": Color("3a2f5c"), "border_soft": Color("2a2247"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9f95c1"),
		"gold": Color("e8c171"), "gold_soft": Color("f0d49a"),
		"amethyst": Color("b79cf6"), "amethyst_deep": Color("7c5cd6"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
	"neonspire": {  # sci-fi — neon cyan + magenta
		"night": Color("05070f"), "night2": Color("0a0f1f"),
		"surface": Color("0f1830"), "surface2": Color("142244"), "sheet": Color("101a33"),
		"border": Color("214066"), "border_soft": Color("16294a"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9f95c1"),
		"gold": Color("2de2e6"), "gold_soft": Color("7ef0f2"),
		"amethyst": Color("ff5fd2"), "amethyst_deep": Color("b026ff"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
	"everyday": {  # slice of life — warm café tones
		"night": Color("0d0f14"), "night2": Color("15171e"),
		"surface": Color("1b1e26"), "surface2": Color("232733"), "sheet": Color("1d2129"),
		"border": Color("353b49"), "border_soft": Color("262b36"),
		"ink": Color("efeafb"), "ink_soft": Color("c3b9e0"), "ink_dim": Color("9f95c1"),
		"gold": Color("e0a96d"), "gold_soft": Color("f0c79a"),
		"amethyst": Color("6ea8fe"), "amethyst_deep": Color("4571c4"),
		"ember": Color("f0a868"), "danger": Color("f0788a"),
	},
	"space": {  # cold void — starlight blue on deep black
		"night": Color("03060f"), "night2": Color("070c1a"),
		"surface": Color("0c1424"), "surface2": Color("111d33"), "sheet": Color("0d1626"),
		"border": Color("1e3358"), "border_soft": Color("15243f"),
		"ink": Color("eaf1ff"), "ink_soft": Color("b7c6e6"), "ink_dim": Color("8d9cc1"),
		"gold": Color("7fb2ff"), "gold_soft": Color("aecdff"),
		"amethyst": Color("62e0ff"), "amethyst_deep": Color("2b7fd6"),
		"ember": Color("ffb066"), "danger": Color("ff6b7a"),
	},
	"steam": {  # brass & soot — copper on warm bitumen
		"night": Color("120c07"), "night2": Color("1c1109"),
		"surface": Color("241811"), "surface2": Color("2f2013"), "sheet": Color("241a10"),
		"border": Color("4a3320"), "border_soft": Color("332416"),
		"ink": Color("f4ead9"), "ink_soft": Color("d8c3a5"), "ink_dim": Color("b1987a"),
		"gold": Color("d69a52"), "gold_soft": Color("edc088"),
		"amethyst": Color("9cc0d0"), "amethyst_deep": Color("5c8496"),
		"ember": Color("f0a868"), "danger": Color("e0788a"),
	},
	"pirate": {  # salt & teak — weathered gold on deep teal
		"night": Color("06110f"), "night2": Color("0a1a17"),
		"surface": Color("102420"), "surface2": Color("163029"), "sheet": Color("11211d"),
		"border": Color("264840"), "border_soft": Color("18302a"),
		"ink": Color("f1ede0"), "ink_soft": Color("c6cabb"), "ink_dim": Color("98a295"),
		"gold": Color("e0c070"), "gold_soft": Color("f0d79a"),
		"amethyst": Color("6fb0a8"), "amethyst_deep": Color("3e7a72"),
		"ember": Color("f0a868"), "danger": Color("e8707e"),
	},
	"horror": {  # candlelit dread — sickly green & blood
		"night": Color("07090a"), "night2": Color("0d1012"),
		"surface": Color("121517"), "surface2": Color("1a1e20"), "sheet": Color("141719"),
		"border": Color("2c3330"), "border_soft": Color("1f2422"),
		"ink": Color("e6e8e0"), "ink_soft": Color("b3b8a8"), "ink_dim": Color("878f7f"),
		"gold": Color("9fb08a"), "gold_soft": Color("c2cfa8"),
		"amethyst": Color("8a9c7a"), "amethyst_deep": Color("5a6b4c"),
		"ember": Color("c98a4a"), "danger": Color("d0455a"),
	},
	"norse": {  # cold slate — pale steel on fjord blue-grey
		"night": Color("0a0d12"), "night2": Color("11151c"),
		"surface": Color("161c24"), "surface2": Color("1e2732"), "sheet": Color("171d26"),
		"border": Color("303e4c"), "border_soft": Color("212b35"),
		"ink": Color("eef2f6"), "ink_soft": Color("bcc7d2"), "ink_dim": Color("8d99a4"),
		"gold": Color("cbd3dc"), "gold_soft": Color("e6ebf0"),
		"amethyst": Color("7fa8c0"), "amethyst_deep": Color("4d7288"),
		"ember": Color("e0a868"), "danger": Color("d97684"),
	},
}

# ── Design-language tokens (docs/DesignSystem.md) — the ONLY numbers allowed
const SPACE := {"xs": 4, "s": 8, "m": 14, "l": 22, "xl": 34}
const RADIUS := {"s": 4, "m": 9, "l": 18}
const RARITY := {"common": "border", "uncommon": "gold_soft", "rare": "amethyst",
	"epic": "ember", "legendary": "gold"}

# ── Interaction tokens (docs/InteractionLanguage.md §2) ─────────────────────
# MIL law: no literal timing, scale, alpha, offset or dB may appear in an
# interaction. Tune the game HERE during playtest — never at the call site.
const TIME := {
	"instant": 0.06,   # sub-perceptual state flips
	"fast": 0.12,      # hover, press, tooltip, micro-feedback
	"base": 0.22,      # reveals, tab swaps, deltas, window ritual
	"slow": 0.45,      # scene transitions, art crossfade, settle
	"beat": 0.80,      # a held pause inside a ceremony
	"ceremony": 1.40,  # the full length of a ceremony peak
	"breath": 3.20,    # idle life loops (portraits, candles, waiting)
}
const SCALE := {"press": 0.96, "exit": 0.99, "enter": 0.985, "lift": 1.045, "pulse": 1.06, "bloom": 1.18}
const ALPHA := {"ghost": 0.22, "glow": 0.35, "scrim": 0.45, "rim": 0.55, "dim": 0.62}
const MOTION := {"shake_px": 5.0, "shake_cycles": 3, "rise_px": 34.0,
	"stagger": 0.04, "stagger_max": 12, "drift_px": 14.0}
const DELAY := {"hover_gate": 0.08, "tooltip": 0.45, "load_min": 0.70,
	"status_cycle": 2.40, "ceremony_hold": 0.55}
const MIX := {"ui": -22.0, "reward": -12.0, "ceremony": -8.0}
const INTERACT := {"budget": 0.60}  # max length of an ORDINARY interaction

var world_id := ""
var reduce_motion := false
var pal: Dictionary = PALETTES["arcane"]
var skin: Dictionary = {}   # the active World Skin (WorldSkin.FAMILIES entry); set by apply()
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
	# MIL §3/§4 made SYSTEMIC: every Button that ever enters the tree gets
	# hover, press, cursor and sound — no screen can forget, and no new screen
	# can regress. _wire is idempotent (a meta guard) and costs one call.
	get_tree().node_added.connect(func(n: Node):
		if n is Button:
			_wire(n))


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


## ── The panel contract (UXAudit R6, root cause #2) ──────────────────────────
## Every full-screen surface used to dress itself, and none of them agreed:
## the Record and the Shop were raw AcceptDialogs wearing the OS title bar, a
## stock white ✕ and a grey unthemed chrome band, while the Lore Book was a
## bare Control with NO background at all — the play screen's toolbar showed
## straight through the "page". On top of that the Record's only exit sat below
## the window's bottom edge, because the dialog sized its CONTENT to the whole
## screen and then had to find room for the button underneath.
##
## One call now dresses any of them: opaque themed panel, no OS chrome, and —
## the part that was actually broken — content height capped so the exit button
## always has somewhere to live. Fixes R6 BUG-01/06/07/09/10/11, AAA-06, AES-02.
const PANEL_RESERVE := 76   # px kept free at the bottom for the exit control


func dress_dialog(dlg: AcceptDialog, content: Control = null) -> void:
	dlg.borderless = true          # no OS-style title bar, no stock ✕
	dlg.transparent_bg = false
	var sb := _flat(c("night"), Color(c("gold_soft"), 0.34), RADIUS["m"], 2, 0)
	sb.shadow_color = Color(0, 0, 0, 0.55)   # R6 AAA-28: panels sit ABOVE, not on
	sb.shadow_size = 18
	dlg.add_theme_stylebox_override("panel", sb)
	# The grey band was the dialog's own button strip showing through unthemed.
	var ok := dlg.get_ok_button()
	ok.theme_type_variation = "AccentButton"
	ok.custom_minimum_size = Vector2(240, 44)   # R6 STR-27: a real 44px target
	if content != null:
		_cap_panel_content(dlg, content)


## Cap the content so `wrap_controls` can never grow the window past the screen
## and push the exit off the bottom. Re-applied on resize — a windowed player
## can change the screen out from under us.
func _cap_panel_content(dlg: AcceptDialog, content: Control) -> void:
	var apply := func():
		if not is_instance_valid(dlg) or not is_instance_valid(content) or not content.is_inside_tree():
			return
		var avail: Vector2 = Vector2(dlg.get_tree().root.get_visible_rect().size)
		content.custom_minimum_size.y = 0
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dlg.max_size = Vector2i(int(avail.x) - 8, int(avail.y) - 8)
		# The ceiling the content may occupy, once the exit strip is spoken for.
		var cap := maxf(120.0, avail.y - 8.0 - PANEL_RESERVE)
		if content.get_combined_minimum_size().y > cap:
			content.custom_minimum_size.y = cap
	# Deferred: the content's real minimum height only exists once its children
	# are in the tree, and callers dress the panel while still building it.
	apply.call_deferred()
	if not dlg.get_tree().root.size_changed.is_connected(apply):
		dlg.get_tree().root.size_changed.connect(apply)


## A full-bleed opaque backing for a plain-Control surface (the Lore Book), so
## it stops compositing over live gameplay. R6 BUG-05 / BLANK-09 / AES-24.
func panel_backing(host: Control, opacity := 0.985) -> PanelContainer:
	var back := PanelContainer.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP   # and stop clicks reaching the game
	var sb := _flat(Color(c("night"), opacity), Color(c("gold_soft"), 0.22), 0, 0, 0)
	back.add_theme_stylebox_override("panel", sb)
	host.add_child(back)
	host.move_child(back, 0)
	return back


## A scrim between a photographic backdrop and the text laid over it. The Round-5
## diagnosis named this as a root cause and it was still unfixed at Round 6:
## the Campaign Shelf and The Table rendered body copy directly onto a
## full-brightness photograph, at roughly 10% effective contrast.
## R6 BUG-15, AAA-22, AES-03/06.
func scrim(host: Control, strength := 0.72) -> ColorRect:
	var s := ColorRect.new()
	s.color = Color(c("night"), strength)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(s)
	host.move_child(s, 0)
	return s


## Worn leather with stitching at the border — the pack/merchant material.
## Palette-tinted: Neonspire reads as coated canvas, Everyday as satchel cloth.
func leather_tex() -> ImageTexture:
	var s := 48
	var base: Color = c("night2").lerp(Color(0.30, 0.20, 0.11), 0.30)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.4
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var n := noise.get_noise_2d(x * 1.7, y) * 0.05
			img.set_pixel(x, y, Color(base.r + n, base.g + n * 0.8, base.b + n * 0.6, 0.97))
	var edge := base.darkened(0.55)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	# Stitches: short gold-thread dashes inset from the edge.
	var thread := Color(c("gold"), 0.35)
	for i in range(4, s - 4):
		if (i / 3) % 2 == 0:
			img.set_pixel(i, 4, thread)
			img.set_pixel(i, s - 5, thread)
			img.set_pixel(4, i, thread)
			img.set_pixel(s - 5, i, thread)
	return ImageTexture.create_from_image(img)


func sb_leather() -> StyleBoxTexture:
	return _nine(leather_tex(), 12, 14)


## Carved oak: directional grain, a carved edge (dark above, lit below).
func wood_tex(lit := 0.0) -> ImageTexture:
	var s := 48
	var base: Color = Color(0.30, 0.19, 0.10).lerp(c("surface2"), 0.25).lightened(lit)
	var noise := FastNoiseLite.new()
	noise.seed = 23
	noise.frequency = 1.0
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var n := noise.get_noise_2d(x * 0.12, y * 2.2) * 0.07
			img.set_pixel(x, y, Color(base.r + n, base.g + n * 0.75, base.b + n * 0.5, 1.0))
	var edge := base.darkened(0.65)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	for i in range(1, s - 1):
		img.set_pixel(i, 1, Color(0, 0, 0, 0.35))              # carve shadow
		img.set_pixel(i, s - 2, Color(1, 0.9, 0.7, 0.14))      # carve light
	return ImageTexture.create_from_image(img)


## Polished brass: warm metal gradient, speckle, bright top kiss.
func brass_tex(lit := 0.0) -> ImageTexture:
	var s := 48
	var base: Color = Color(0.55, 0.42, 0.18).lightened(lit)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.9
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		var row := base.lightened(0.16).lerp(base.darkened(0.35), float(y) / (s - 1))
		for x in s:
			var n := noise.get_noise_2d(x, y) * 0.05
			img.set_pixel(x, y, Color(row.r + n, row.g + n, row.b + n * 0.6, 1.0))
	var edge := base.darkened(0.7)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	for i in range(2, s - 2):
		img.set_pixel(i, 2, Color(1, 1, 0.85, 0.20))
	return ImageTexture.create_from_image(img)


## Glass / holo panel (cyber "steel"): a cool translucent slab, bright rim,
## a diagonal reflection streak. The rim uses the palette accent (cyan in the
## Neonspire skin), so it reads as lit glass, not metal.
func glass_tex(lit := 0.0) -> ImageTexture:
	var s := 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var base: Color = c("surface2").lightened(lit)
	for y in s:
		var t := float(y) / float(s - 1)
		var row := base.lightened(0.16).lerp(base.darkened(0.12), t)
		var a := 0.58 + 0.18 * (1.0 - t)
		for x in s:
			img.set_pixel(x, y, Color(row.r, row.g, row.b, a))
	var rim := Color(c("gold"), 0.9)
	for i in s:
		img.set_pixel(i, 0, rim)
		img.set_pixel(0, i, rim)
		img.set_pixel(i, s - 1, Color(c("gold"), 0.4))
		img.set_pixel(s - 1, i, Color(c("gold"), 0.4))
	for i in range(2, s - 2):
		img.set_pixel(i, 2, Color(1, 1, 1, 0.16))  # glass streak
	return ImageTexture.create_from_image(img)


## Neon panel (cyber "brass"): a near-black slab ringed by a glowing tube —
## magenta outer, cyan inner (the palette's amethyst + gold accents).
func neon_tex(lit := 0.0) -> ImageTexture:
	var s := 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(c("night2").lightened(lit), 0.96))
	var edge := Color(0, 0, 0, 0.6)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	for i in range(1, s - 1):
		img.set_pixel(i, 1, Color(c("amethyst"), 0.95))
		img.set_pixel(1, i, Color(c("amethyst"), 0.95))
		img.set_pixel(i, s - 2, Color(c("gold"), 0.85))
		img.set_pixel(s - 2, i, Color(c("gold"), 0.85))
	return ImageTexture.create_from_image(img)


## Riveted copper (steam "steel"/"brass"): a warm metal gradient with four
## corner rivets. Palette gold reads as copper in the Steam skin.
func copper_tex(lit := 0.0) -> ImageTexture:
	var s := 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var base: Color = c("surface2").lerp(c("gold"), 0.35).lightened(lit)
	for y in s:
		var t := float(y) / float(s - 1)
		var row := base.lightened(0.12).lerp(base.darkened(0.28), t)
		for x in s:
			img.set_pixel(x, y, row)
	var outer := base.darkened(0.7)
	for i in s:
		img.set_pixel(i, 0, outer)
		img.set_pixel(i, s - 1, outer)
		img.set_pixel(0, i, outer)
		img.set_pixel(s - 1, i, outer)
	for rv in [[3, 3], [s - 4, 3], [3, s - 4], [s - 4, s - 4]]:  # corner rivets
		img.set_pixel(rv[0], rv[1], Color(c("gold_soft"), 0.95))
		img.set_pixel(rv[0], rv[1] + 1, Color(0, 0, 0, 0.4))
	return ImageTexture.create_from_image(img)


## Carbon fibre (cyber/space "leather"): a fine dark cross-weave.
func carbon_tex(lit := 0.0) -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var base: Color = c("night2").lightened(lit)
	for y in s:
		for x in s:
			var block := (int(x / 3.0) + int(y / 3.0)) % 2 == 0
			var shade := base.lightened(0.06) if block else base.darkened(0.06)
			img.set_pixel(x, y, Color(shade.r, shade.g, shade.b, 0.98))
	var edge := base.darkened(0.6)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	return ImageTexture.create_from_image(img)


## Carved stone (fantasy/norse/horror "panel"): cool mottled rock, a chiseled
## edge — dark seam above, dusty light below. Kept DARK so ink stays readable.
func stone_tex(lit := 0.0) -> ImageTexture:
	var s := 48
	var base: Color = c("night2").lerp(Color(0.32, 0.32, 0.36), 0.35).lightened(lit)
	var noise := FastNoiseLite.new()
	noise.seed = 41
	noise.frequency = 0.22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var n := noise.get_noise_2d(x, y) * 0.06
			var crack := noise.get_noise_2d(x * 3.0 + 100, y * 3.0) > 0.42
			var px := Color(base.r + n, base.g + n, base.b + n * 1.1, 0.97)
			img.set_pixel(x, y, px.darkened(0.25) if crack else px)
	var edge := base.darkened(0.6)
	for i in s:
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, s - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(s - 1, i, edge)
	for i in range(1, s - 1):
		img.set_pixel(i, 1, Color(0, 0, 0, 0.3))               # chisel shadow
		img.set_pixel(i, s - 2, Color(0.9, 0.9, 1.0, 0.08))    # dusty light
	return ImageTexture.create_from_image(img)


## Aged page (the book's "page"): deep umber paper — mottled fibre, a deckled
## darker rim. DARK parchment, not tan: the ink ramp must keep its contrast.
func parchment_tex(lit := 0.0) -> ImageTexture:
	var s := 48
	var base: Color = c("night2").lerp(Color(0.34, 0.27, 0.16), 0.3).lightened(lit)
	var noise := FastNoiseLite.new()
	noise.seed = 53
	noise.frequency = 0.5
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var n := noise.get_noise_2d(x * 1.4, y * 1.4) * 0.05
			var fleck := noise.get_noise_2d(x * 5.0 + 40, y * 5.0) > 0.55
			var px := Color(base.r + n, base.g + n * 0.9, base.b + n * 0.6, 0.97)
			img.set_pixel(x, y, px.darkened(0.18) if fleck else px)
	var rim := base.darkened(0.45)
	for i in s:
		for off in [0, 1]:  # deckled double rim
			img.set_pixel(i, off, rim)
			img.set_pixel(i, s - 1 - off, rim)
			img.set_pixel(off, i, rim)
			img.set_pixel(s - 1 - off, i, rim)
	return ImageTexture.create_from_image(img)


## A material plate for MythButton. The four callers name SEMANTIC roles
## (steel/leather/brass/oak); the active World Skin remaps each role to its own
## material vocabulary, each with its own bespoke procedural texture. Every
## generator pulls palette colours, so the plate is also tinted to the world.
func material_sb(role: String, lit := 0.0) -> StyleBoxTexture:
	var mat := str(skin.get("materials", {}).get(role, role))
	match mat:
		"glass":
			return _nine(glass_tex(lit), 6, 12)
		"neon":
			return _nine(neon_tex(lit), 6, 12)
		"copper":
			return _nine(copper_tex(lit), 6, 12)
		"carbon":
			return _nine(carbon_tex(lit), 8, 12)
		"leather":
			return _nine(leather_tex(), 12, 12)
		"stone":
			return _nine(stone_tex(lit), 6, 12)
		"parchment":
			return _nine(parchment_tex(lit), 6, 12)
		"brass":
			return _nine(brass_tex(lit), 6, 12)
		"oak":
			return _nine(wood_tex(lit), 6, 12)
		_:  # steel and anything unmapped: the forged plate
			return _nine(forged_tex(c("surface2").lightened(lit), c("border")), 6, 12)


# ── Motion vocabulary (docs/InteractionLanguage.md §14) — reduce_motion aware ─
## MIL §3+§4: hover and press for every Button under root — lift, rim, cursor,
## and the sounds. Sound and cursor apply even under reduce_motion (the state
## must stay perceivable without movement); only the scaling drops out.
## One call per screen; call again after building dynamic dialogs.
## Explicit sweep — rarely needed now that node_added wires everything, but
## kept for nodes built before this autoload existed and for tests.
func polish(root: Node) -> void:
	var targets: Array = root.find_children("*", "Button", true, false)
	if root is Button:
		targets.append(root)
	for n in targets:
		_wire(n)


## One button, wired to the interaction language. Idempotent.
func _wire(n: Button) -> void:
	if n.has_meta("_polished"):
		return
	n.set_meta("_polished", true)
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Beginning: anticipation. Hover speaks (quietly), press confirms.
	n.mouse_entered.connect(func():
		if not n.disabled:
			Sfx.ui("ui_hover")
			_lift(n, SCALE["lift"]))
	n.mouse_exited.connect(_lift.bind(n, 1.0))
	n.button_down.connect(func():
		Sfx.ui("ui_click")  # on PRESS, not release — perceived latency
		_lift(n, SCALE["press"]))
	n.button_up.connect(_lift.bind(n, SCALE["lift"]))


func _lift(n: Control, to: float) -> void:
	if reduce_motion or not is_instance_valid(n) or not n.is_inside_tree():
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
	ctrl.scale = Vector2.ONE * SCALE["enter"]
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


## The window ritual every screen shares (docs/DesignSystem.md — Rituals):
## anticipation (the world dims), reveal (contents settle in, staggered),
## graceful exit (the scrim lifts as the window goes). Call after add_child.
## MIL §12. The dim is HIERARCHY, not decoration — it survives reduce_motion
## (instantly, rather than faded). Open and close each speak once.
func ritual_open(dlg: Window) -> void:
	polish(dlg)
	Sfx.ui("ui_open")
	var host := dlg.get_parent()
	if host is Control:
		var scrim := ColorRect.new()
		scrim.color = Color(c("night"), ALPHA["scrim"] if reduce_motion else 0.0)
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(scrim)
		if not reduce_motion:
			scrim.create_tween().tween_property(scrim, "color:a", ALPHA["scrim"], TIME["base"])
		var closed := [false]  # the close sound fires once, however the window dies
		var lift := func():
			if not is_instance_valid(scrim):
				return
			if not closed[0]:
				closed[0] = true
				Sfx.ui("ui_close")
			if reduce_motion:
				scrim.queue_free()
				return
			var tw := scrim.create_tween()
			tw.tween_property(scrim, "color:a", 0.0, TIME["base"])
			tw.tween_callback(scrim.queue_free)
		dlg.visibility_changed.connect(func():
			if not dlg.visible:
				lift.call())
		dlg.tree_exited.connect(lift)
	for ch in dlg.get_children():
		if ch is Control:
			reveal(ch)


## Rising ghost text (damage, gold, XP) at a canvas position.
## parent may be a Control or a Window — deltas rise inside dialogs too.
func rise_text(parent: Node, text: String, color: Color, at: Vector2) -> void:
	var lab := Label.new()
	lab.text = text
	lab.theme_type_variation = "TitleLabel"
	lab.add_theme_color_override("font_color", color)
	lab.position = at
	lab.z_index = 100
	parent.add_child(lab)
	if reduce_motion:
		# MIL §16: the delta APPEARS AND HOLDS — the information is never lost
		# to accessibility, only the movement is.
		var hold := lab.create_tween()
		hold.tween_interval(TIME["ceremony"])
		hold.tween_property(lab, "modulate:a", 0.0, TIME["base"])
		hold.tween_callback(lab.queue_free)
		return
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", at.y - MOTION["rise_px"], TIME["ceremony"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, TIME["ceremony"]).set_delay(TIME["base"])
	tw.chain().tween_callback(lab.queue_free)


# ── MIL primitives (InteractionLanguage.md §14) ─────────────────────────────
## MIL §6 — refusal. The shake is the only thing reduce_motion removes; the
## colour pulse and the sound still say no.
func shake(ctrl: Control) -> void:
	Sfx.ui("ui_deny")
	if ctrl == null or not is_instance_valid(ctrl):
		return
	_deny_pulse(ctrl)
	if reduce_motion:
		return
	var base_x := ctrl.position.x
	var tw := ctrl.create_tween()
	var cycles := int(MOTION["shake_cycles"])
	for i in cycles:
		var amp: float = float(MOTION["shake_px"]) * (1.0 - float(i) / float(cycles))
		tw.tween_property(ctrl, "position:x", base_x + amp, TIME["fast"] / 2.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ctrl, "position:x", base_x - amp, TIME["fast"] / 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ctrl, "position:x", base_x, TIME["fast"] / 2.0)


## The danger wash that rides every refusal — a second channel, so the message
## survives without motion and without relying on colour alone (sound is third).
func _deny_pulse(ctrl: Control) -> void:
	var wash := ColorRect.new()
	wash.color = Color(c("danger"), 0.0)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(wash)
	var tw := wash.create_tween()
	tw.tween_property(wash, "color:a", ALPHA["glow"], TIME["fast"])
	tw.tween_property(wash, "color:a", 0.0, TIME["base"])
	tw.tween_callback(wash.queue_free)


## MIL §5 — the MIDDLE act made visible: a thing travels from where it was to
## where it now belongs. Rects are in the host's canvas space.
## host may be any Control OR Window (dialogs are Windows and fly too).
func fly_to(host: Node, tex: Texture2D, from_rect: Rect2, to_rect: Rect2, done := Callable()) -> void:
	if host == null or not is_instance_valid(host) or reduce_motion or tex == null:
		if done.is_valid():
			done.call()
		return
	var fly := TextureRect.new()
	fly.texture = tex
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.position = from_rect.position
	fly.size = from_rect.size
	fly.z_index = 90
	host.add_child(fly)
	var tw := fly.create_tween().set_parallel(true)
	tw.tween_property(fly, "position", to_rect.position, TIME["base"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(fly, "size", to_rect.size, TIME["base"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func():
		fly.queue_free()
		if done.is_valid():
			done.call())


## MIL §9 — numbers roll rather than snap, so a purse feels spent.
func count_to(label: Label, from_v: int, to_v: int, fmt := "%d") -> void:
	if label == null or not is_instance_valid(label):
		return
	if reduce_motion or from_v == to_v:
		label.text = fmt % to_v
		return
	var setter := func(v: float):
		if is_instance_valid(label):
			label.text = fmt % int(round(v))
	var tw := label.create_tween()
	tw.tween_method(setter, float(from_v), float(to_v), TIME["base"]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## MIL §12/§7 — the scene wipe. The world never cuts: it darkens through the
## skin's own night, swaps, and returns. reduce_motion keeps the beat but not
## the fade, so the change is still deliberate rather than instant.
func transition(scene_path: String, tree: SceneTree) -> void:
	if tree == null:
		return
	Sfx.ui("ui_close")
	var layer := CanvasLayer.new()
	layer.layer = 128
	var veil := ColorRect.new()
	veil.color = Color(c("night"), 0.0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP  # the curtain eats stray clicks
	layer.add_child(veil)
	tree.root.add_child(layer)
	if reduce_motion:
		veil.color.a = 1.0
		await tree.create_timer(TIME["fast"]).timeout
	else:
		var tw := veil.create_tween()
		tw.tween_property(veil, "color:a", 1.0, TIME["slow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		await tw.finished
	tree.change_scene_to_file(scene_path)
	await tree.process_frame
	await tree.process_frame  # let the new scene build behind the veil
	if reduce_motion:
		layer.queue_free()
		return
	var out := veil.create_tween()
	out.tween_property(veil, "color:a", 0.0, TIME["slow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	out.tween_callback(layer.queue_free)


func _nine(tex: ImageTexture, margin: int, content: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb


## Install the active world's skin: its palette drives the whole theme, and
## its material/flavor vocabulary drives material_sb() and downstream nouns.
func apply(wid: String) -> void:
	world_id = wid
	skin = WorldSkin.skin_for_id(wid)
	var pkey := str(skin.get("palette", "arcane"))
	# Duplicate so a per-world overlay never mutates the shared const palette.
	pal = (PALETTES[pkey] if PALETTES.has(pkey) else PALETTES["arcane"]).duplicate()
	_overlay_world_palette(wid)
	_build()
	changed.emit()


## S10 — a compiled world's own Style Guide colours refine its family palette, so
## each world's UI carries its specific identity, not just its family's. Only the
## accent (and a soft variant) are overlaid — surface/ink/text stay the family's,
## so contrast can never regress (design gate).
func _overlay_world_palette(wid: String) -> void:
	if wid == "" or not Compiler.is_compiled(wid):
		return
	var cols = Compiler.style_for(wid).get("colors")
	if not (cols is Dictionary):
		return
	var acc = _hex(str(cols.get("accent", "")))
	if acc != null:
		pal["gold"] = acc
		pal["gold_soft"] = acc.lightened(0.28)


## Parse a #rrggbb string to a Color, or null if it isn't a valid opaque hex.
func _hex(s: String):
	s = s.strip_edges()
	if not (s.begins_with("#") and s.length() == 7):
		return null
	var col := Color.from_string(s, Color.TRANSPARENT)
	return col if col.a > 0.0 else null


func c(name: String) -> Color:
	return pal[name]


## Inline hand-drawn icon for RichText — a baked white master (ui/icons/glyph)
## tinted to a palette role. Takes an icon name OR a legacy emoji; both resolve
## to real art, so a AAA UI never renders a raw glyph. Pair with a trailing space.
func ico(glyph: String, px := 20, role := "gold_soft") -> String:
	return "[img width=%d height=%d color=#%s]res://ui/icons/glyph/%s.png[/img]" % [
		px, px, c(role).to_html(true), MythIcon.resolve(glyph)]


## Baked white icon master for real controls (Button.icon, PopupMenu items).
## Tint it via the control: btn.add_theme_color_override("icon_normal_color", ...)
## or pop.set_item_icon_modulate(i, ...) — no per-pixel work.
func ico_tex(glyph: String) -> Texture2D:
	return load("res://ui/icons/glyph/%s.png" % MythIcon.resolve(glyph)) as Texture2D


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
	theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, c("amethyst"), 6, 2, 12))  # 2px: readable from the couch (pad focus)
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

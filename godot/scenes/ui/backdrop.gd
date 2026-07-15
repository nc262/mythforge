extends Control
## Backdrop — the studio's living background: night gradient, two soft
## radial glows (amethyst high, gold low), and a slow-drifting star field.
## Colors come from Skin and rebuild when the world theme changes.

const STARS := 70

var _base := TextureRect.new()
var _glow_hi := TextureRect.new()
var _glow_lo := TextureRect.new()
var _stars: Array = []  # [{pos: Vector2 (0-1), r: float, col: Color}]
var _drift := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for t in [_base, _glow_hi, _glow_lo]:
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(t)
	_seed_stars()
	_paint()
	Ui.changed.connect(_paint)


func _seed_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # deterministic sky
	for i in STARS:
		_stars.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"r": rng.randf_range(0.7, 1.6),
			"kind": i % 3,  # gold / amethyst / white
			"a": rng.randf_range(0.35, 0.8),
		})


func _paint() -> void:
	_base.texture = _linear(Ui.c("night2"), Ui.c("night"))
	_glow_hi.texture = _radial(Color(Ui.c("amethyst_deep"), 0.18), Vector2(0.78, -0.08))
	_glow_lo.texture = _radial(Color(Ui.c("gold"), 0.10), Vector2(0.12, 1.08))
	queue_redraw()


func _linear(from: Color, to: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([from, to])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t


func _radial(col: Color, center: Vector2) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(col, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = center
	t.fill_to = center + Vector2(0.55, 0.55)
	t.width = 256
	t.height = 256
	return t


func _process(delta: float) -> void:
	if Ui.reduce_motion:
		return
	_drift = fmod(_drift + delta * 4.0, 10000.0)  # ~4px/s upward, the CSS st-drift
	queue_redraw()


func _draw() -> void:
	var cols := [Color(Ui.c("gold"), 1.0), Color(Ui.c("amethyst"), 1.0), Color.WHITE]
	for s in _stars:
		var p: Vector2 = s["pos"] * size
		p.y = fposmod(p.y - _drift, size.y + 8.0) - 4.0
		var col: Color = cols[s["kind"]]
		col.a = s["a"] * 0.5
		draw_circle(p, s["r"], col)

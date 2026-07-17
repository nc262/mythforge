extends Control
## The opening cinematic: Mythforge's first impression. Four worlds in one
## breath — a dragon over castles, its hologram over Neonspire, a quiet
## suburb at sunset, deep space — then the stars collapse into the particles
## that forge the logo. Skippable on any input; reduce_motion (or missing
## panoramas on a cold cache) jumps straight to the logo. Emits `finished`
## when the interface may emerge.

signal finished

const SHOTS := ["cine-fantasy", "cine-neonspire", "cine-everyday", "cine-space"]
const SHOT_TIME := 4.4
const FADE_TIME := 1.1

var _t := 0.0
var _logo_t := -1.0
var _sparks: Array = []
var _done := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	for k in SHOTS:
		Art.ensure(k, str(Art.CINE_PROMPTS.get(k, "")), "1344x768")
	for i in 90:
		_sparks.append([randf(), randf(), 0.4 + randf() * 0.9, randf() * TAU])
	var all_present := SHOTS.all(func(k): return Art.has_art(k))
	if Ui.reduce_motion or not all_present:
		_logo_t = 0.0  # straight to the forging of the name
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	if _logo_t >= 0.0:
		_logo_t += delta
		if _logo_t > 3.6:
			_finish()
	else:
		_t += delta
		if _t >= SHOT_TIME * SHOTS.size():
			_logo_t = 0.0
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)


func _draw_shot(key: String, alpha: float, phase: float) -> void:
	var tex := Art.texture_for(key)
	if tex == null:
		return
	var tsize := Vector2(tex.get_width(), tex.get_height())
	var zoom := (1.06 + 0.12 * phase)
	var s := maxf(size.x / tsize.x, size.y / tsize.y) * zoom
	var draw_size := tsize * s
	var pan := Vector2((phase - 0.5) * 40.0, (0.5 - phase) * 18.0)
	var offset := (Vector2(size.x, size.y) - draw_size) / 2.0 + pan
	draw_texture_rect(tex, Rect2(offset, draw_size), false, Color(1, 1, 1, alpha))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03))
	if _logo_t < 0.0:
		# The journey across the worlds: current shot + the next bleeding in.
		var idx := clampi(int(_t / SHOT_TIME), 0, SHOTS.size() - 1)
		var local := _t - idx * SHOT_TIME
		_draw_shot(SHOTS[idx], 1.0, local / SHOT_TIME)
		if local > SHOT_TIME - FADE_TIME and idx + 1 < SHOTS.size():
			_draw_shot(SHOTS[idx + 1], (local - (SHOT_TIME - FADE_TIME)) / FADE_TIME, 0.0)
		# Letterbox: the cinema's frame.
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.07)), Color(0, 0, 0, 0.9))
		draw_rect(Rect2(Vector2(0, size.y * 0.93), Vector2(size.x, size.y * 0.07)), Color(0, 0, 0, 0.9))
		var hint := get_theme_default_font()
		draw_string(hint, Vector2(size.x - 220, size.y - 14), "press anything to skip",
			HORIZONTAL_ALIGNMENT_RIGHT, 200, 12, Color(Ui.c("ink_dim"), 0.6))
		return
	# The forging of the name: stars collapse into the logo's particles.
	var center := Vector2(size.x / 2.0, size.y * 0.44)
	var conv := clampf(_logo_t / 1.9, 0.0, 1.0)
	var ease_c := 1.0 - pow(1.0 - conv, 3.0)
	for sp in _sparks:
		var start := Vector2(float(sp[0]) * size.x, float(sp[1]) * size.y)
		var orbit := Vector2(sin(float(sp[3]) + _logo_t * 1.4), cos(float(sp[3]) + _logo_t * 1.4)) * (26.0 * (1.0 - ease_c) + 88.0 * (1.0 - ease_c))
		var p := start.lerp(center + orbit * (1.0 - ease_c), ease_c)
		var a := 0.35 + 0.5 * ease_c - maxf(0.0, (_logo_t - 2.3)) * 0.5
		draw_circle(p, 1.3 + 1.2 * ease_c * float(sp[2]), Color(Ui.c("gold_soft"), clampf(a, 0.0, 0.9)))
	if _logo_t > 1.4:
		var la := clampf((_logo_t - 1.4) / 1.0, 0.0, 1.0)
		var breathe := 1.0 + 0.012 * sin(_logo_t * 2.0)
		var fs := int(64 * breathe)
		var title := "M Y T H F O R G E"
		var ts := Ui.display.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_texture_rect(Ui.glow_tex(), Rect2(center - Vector2(ts.x, ts.x * 0.5) / 2.0, Vector2(ts.x, ts.x * 0.5)),
			false, Color(Ui.c("gold"), 0.14 * la))
		draw_string(Ui.display, center + Vector2(-ts.x / 2.0, ts.y / 3.0), title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(Ui.c("gold_soft"), la))
		var tag := "every world is a door"
		var gs := Ui.display.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(Ui.display, center + Vector2(-gs.x / 2.0, ts.y / 3.0 + 34), tag,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(Ui.c("ink_soft"), la * 0.8))

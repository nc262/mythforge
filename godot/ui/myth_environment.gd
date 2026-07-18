class_name MythEnvironment extends Control
## EAS — the Environmental Art System (docs/DesignSystem.md §6).
## Every screen stands INSIDE an illustrated environment: a generated
## painting (background), volumetric light shafts and a legibility scrim
## (midground), flickering candle anchors and drifting particles
## (atmosphere), and a whisper of mouse parallax (depth). UI controls are
## layered on top of this — the world is the interface.
## With env_key == "" it becomes a pure atmosphere overlay (shafts +
## particles only, fully transparent) for screens that already own art.

var env_key := ""
var mood := "dust"        # "dust" | "embers" | "none"
var lights: Array = []    # normalized Vector2 anchors → flickering candle glows
var parallax := 7.0       # px of painting drift against the cursor
var scrim := 0.45         # legibility veil over the painting
var _phase := 0.0
var _motes: Array = []


func _init(key := "", m := "dust", light_anchors: Array = []) -> void:
	env_key = key
	mood = m
	lights = light_anchors
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	clip_contents = true
	for i in 34:
		_motes.append([randf(), randf(), 0.35 + randf()])
	set_process(not Ui.reduce_motion)
	Art.art_ready.connect(func(k):
		if str(k) == env_key:
			queue_redraw())


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var has_bg := env_key != ""
	if has_bg:
		var tex := Art.texture_for(env_key)
		if tex != null:
			# The painting, cover-fit, drifting a breath against the cursor.
			var tsize := Vector2(tex.get_width(), tex.get_height())
			var s := maxf((size.x + parallax * 2.0) / tsize.x, (size.y + parallax * 2.0) / tsize.y)
			var draw_size := tsize * s
			var mouse_n := (get_local_mouse_position() / size - Vector2(0.5, 0.5)) if not Ui.reduce_motion else Vector2.ZERO
			var offset := (Vector2(size.x, size.y) - draw_size) / 2.0 - mouse_n.limit_length(0.5) * parallax * 2.0
			draw_texture_rect(tex, Rect2(offset, draw_size), false, Color(0.96, 0.94, 0.98))
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.92))
		# Legibility veil + edge vignette: the eye stays on the content.
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), scrim))
		for edge_r in [[Rect2(Vector2.ZERO, Vector2(size.x, 46)), true], [Rect2(Vector2(0, size.y - 46), Vector2(size.x, 46)), true]]:
			draw_rect(edge_r[0], Color(Ui.c("night"), 0.28))
	# Volumetric shafts breathe from the upper light — only in rooms with a
	# painting; over live play they read as screen flicker, so the pure
	# atmosphere overlay keeps its dust and loses the shafts.
	if not Ui.reduce_motion and has_bg:
		for i in 2:
			var breathe := 0.028 + 0.016 * sin(_phase * 0.5 + i * 2.1)
			var x0 := size.x * (0.18 + i * 0.42)
			var shaft := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 90, 0),
				Vector2(x0 + 260, size.y), Vector2(x0 + 60, size.y)])
			draw_colored_polygon(shaft, Color(Ui.c("gold_soft"), breathe))
	# Candlelight at its anchors, guttering.
	for li in lights.size():
		var l: Vector2 = lights[li]
		var flick := (0.16 + 0.05 * sin(_phase * 7.0 + li * 1.7) + 0.03 * sin(_phase * 12.3 + li)) if not Ui.reduce_motion else 0.18
		var cp := Vector2(size.x * l.x, size.y * l.y)
		draw_texture_rect(Ui.glow_tex(), Rect2(cp - Vector2(95, 95), Vector2(190, 190)), false, Color(Ui.c("gold"), flick))
		draw_circle(cp, 2.6, Color(1.0, 0.9, 0.62, 0.9))
	# The air itself: dust in the light, or embers on the rise.
	if Ui.reduce_motion or mood == "none":
		return
	for m in _motes:
		var speed := float(m[2])
		if mood == "embers":
			var t := fmod(_phase * 0.05 * speed + float(m[1]), 1.0)
			var ex := size.x * float(m[0]) + sin(_phase * 1.2 + float(m[0]) * 22.0) * 12.0
			draw_circle(Vector2(ex, size.y - t * size.y), 1.5, Color(Ui.c("ember"), (1.0 - t) * 0.5))
		else:
			var t2 := fmod(_phase * 0.022 * speed + float(m[1]), 1.0)
			var dx := size.x * fmod(float(m[0]) + _phase * 0.004 * speed, 1.0)
			draw_circle(Vector2(dx, t2 * size.y), 1.1,
				Color(Ui.c("gold_soft"), 0.10 + 0.08 * sin(_phase * 1.5 + float(m[0]) * 30.0)))


## Mount an environment behind a host's existing children. The room key is
## resolved through the active World Skin, so each world wears its own rooms.
static func mount(host: Node, key: String, m := "dust", light_anchors: Array = []) -> MythEnvironment:
	var resolved := Art.env_resolved(key) if key != "" else key
	var env := MythEnvironment.new(resolved, m, light_anchors)
	host.add_child(env)
	host.move_child(env, 0)
	if key != "":
		Art.ensure_environment(key)
	return env

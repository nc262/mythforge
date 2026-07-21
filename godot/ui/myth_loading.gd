class_name MythLoading extends CanvasLayer
## MIL §7 Tier 2 — the loading experience. The game may never cut to a
## half-built screen: this composed frame stands in front while the world
## hydrates and its first paintings warm, then lifts.
##
## It lives on the tree ROOT as a CanvasLayer, so it survives the scene change
## it is covering — the player sees one continuous held frame, not a flicker
## of menu → black → half-built play screen.
##
## Progress is HONEST: callers push real milestones (`step()`), never a timer.
## Under reduce_motion the art stops drifting but the progress rule still
## moves — it is information, not decoration (MIL §16).

const LORE_FALLBACK := "The road waits."

## The curtain outlives the scene that raised it — the incoming scene finds it
## here and lifts it once IT is genuinely ready.
static var active: MythLoading = null

var _art: TextureRect
var _rule: ColorRect
var _rule_host: Control
var _status: Label
var _t := 0.0
var _shown_at := 0.0
var _progress := 0.0
var _target := 0.0
var _done := false


## Raise the curtain over whatever is on screen now. Call before the work.
static func begin(tree: SceneTree, world_id: String, title: String) -> MythLoading:
	var l := MythLoading.new()
	l.layer = 127
	tree.root.add_child(l)
	l._build(world_id, title)
	active = l
	return l


## Milestone from anywhere (the incoming scene doesn't hold the reference).
static func mark(fraction: float, line := "") -> void:
	if active != null and is_instance_valid(active):
		active.step(fraction, line)


## Lift whatever curtain is up, if any. Safe to call when there is none.
static func lift() -> void:
	if active != null and is_instance_valid(active):
		var l := active
		active = null
		l.finish()
	else:
		active = null


func _build(world_id: String, title: String) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # the curtain eats stray clicks
	add_child(root)
	# The world itself, dimmed — you are already somewhere, not nowhere.
	_art = TextureRect.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture = Art.texture_for(world_id)
	_art.modulate = Color(1, 1, 1, Ui.ALPHA["dim"])
	root.add_child(_art)
	var veil := ColorRect.new()
	veil.color = Color(Ui.c("night"), Ui.ALPHA["scrim"])
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.theme_type_variation = "TitleLabel"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text = title
	col.add_child(name_l)
	# The world's OWN words — never the syllable "Loading".
	var lore := Label.new()
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.custom_minimum_size = Vector2(680, 0)
	lore.add_theme_color_override("font_color", Ui.c("ink_soft"))
	lore.text = _lore_for(world_id)
	col.add_child(lore)
	# The progress rule: thin, gold, and honest.
	_rule_host = Control.new()
	_rule_host.custom_minimum_size = Vector2(420, 3)
	var trough := ColorRect.new()
	trough.color = Color(Ui.c("border"), 0.7)
	trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rule_host.add_child(trough)
	_rule = ColorRect.new()
	_rule.color = Ui.c("gold")
	_rule.size = Vector2(0, 3)
	_rule_host.add_child(_rule)
	var rc := CenterContainer.new()
	rc.add_child(_rule_host)
	col.add_child(rc)
	_status = Label.new()
	_status.theme_type_variation = "HintLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	root.add_child(col)
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, Ui.TIME["fast"] if Ui.reduce_motion else Ui.TIME["base"])
	_shown_at = Time.get_ticks_msec() / 1000.0
	set_process(true)


## One line of the world's own lore — its tagline, else its first location's
## story, else a plain honest line. Never engineering copy.
func _lore_for(world_id: String) -> String:
	for w in Rules.builtin_worlds():
		if w is Dictionary and str(w.get("id", "")) == world_id:
			var t := str(w.get("tagline", "")).strip_edges()
			if t != "":
				return t
			var l := str(w.get("lore", "")).strip_edges()
			if l != "":
				return l.left(160)
	for loc in Rules.world_locations(world_id):
		if loc is Dictionary and str(loc.get("lore", "")) != "":
			return str(loc["lore"]).left(160)
	return LORE_FALLBACK


func _process(delta: float) -> void:
	_t += delta
	# The rule eases toward its target — real work, smoothly shown.
	_progress = lerpf(_progress, _target, clampf(delta * 6.0, 0.0, 1.0))
	if is_instance_valid(_rule) and is_instance_valid(_rule_host):
		_rule.size.x = _rule_host.size.x * _progress
	# Ken Burns on the world art — stilled for reduce_motion, per MIL §16.
	if not Ui.reduce_motion and is_instance_valid(_art):
		var drift: float = float(Ui.MOTION["drift_px"])
		_art.pivot_offset = _art.size / 2.0
		_art.scale = Vector2.ONE * (1.02 + 0.01 * sin(_t / float(Ui.TIME["breath"])))
		_art.position.x = sin(_t / (float(Ui.TIME["breath"]) * 1.7)) * drift * 0.25


## Push a real milestone: 0..1 with a line the player can read.
func step(fraction: float, line := "") -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if line != "" and is_instance_valid(_status):
		_status.text = line


## The work is done — hold the minimum beat, then lift. A flash is worse than
## a beat (MIL §7), so a fast machine still sees a composed frame.
func finish() -> void:
	if _done:
		return
	_done = true
	step(1.0)
	var elapsed := Time.get_ticks_msec() / 1000.0 - _shown_at
	var wait: float = maxf(0.0, float(Ui.DELAY["load_min"]) - elapsed)
	await get_tree().create_timer(wait).timeout
	var root := get_child(0) as Control
	if root == null:
		queue_free()
		return
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, Ui.TIME["slow"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(queue_free)

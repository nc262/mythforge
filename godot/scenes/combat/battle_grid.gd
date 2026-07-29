extends Control
## The tactical board, painted: a generated overhead battle map of the
## ACTUAL place underneath, whisper-thin grid lines, and art tokens —
## the hero's portrait, bestiary paintings for the foes — ringed in their
## side's color with an HP arc and a name plate. Movement and reach math
## live in Combat; this draws and routes clicks.

signal cell_clicked(cell: Array)
signal token_clicked(id: String)

var map_key := ""  # Art cache key of the underlay ("" = scrimmed scene art)
const TILE_VARIANTS := 4   # how many painted variants a role may have
const BoardPaint = preload("res://scenes/combat/board_paint.gd")
var _hover := [-1, -1]
var _disp := {}        # id -> displayed pixel center (eases toward the square)
var _hp_seen := {}     # id -> last hp, for damage/heal feedback
var _shake := Vector2.ZERO
var _lunge_id := ""
var _lunge_off := Vector2.ZERO
var _drag_pc := false          # your token lifts and rides the cursor
var _drag_pt := Vector2.ZERO
var _press_cell: Array = [-1, -1]


func _ready() -> void:
	# The cover-fit underlay overshoots the rect on purpose — clip it, or the
	# painting floods the whole chat column (RCA'd: "only map, no text").
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Combat.changed.connect(_on_combat_changed)
	Art.art_ready.connect(func(_k): queue_redraw())
	# The movement overlay keys off the hover cell, so the cursor leaving the
	# board has to put it away — otherwise "only while choosing" becomes "always,
	# after the first time you touched it".
	mouse_exited.connect(func():
		_hover = [-1, -1]
		queue_redraw())
	custom_minimum_size = Vector2(Combat.MAP_COLS * 40, Combat.MAP_ROWS * 40)


## Tokens slide, blows land: diff the state, spawn the feedback, ease frames.
func _on_combat_changed() -> void:
	var c := Combat.data()
	if not bool(c.get("active", false)):
		_disp.clear()
		_hp_seen.clear()
		set_process(false)
		queue_redraw()
		return
	set_process(not Ui.reduce_motion)
	var cur_id := str(Combat.current(c).get("id", ""))
	for m in c.get("combatants", []):
		var id := str(m.get("id", ""))
		var hp := int(m.get("hp", 0))
		if _hp_seen.has(id) and hp != int(_hp_seen[id]) and not Ui.reduce_motion:
			# _disp and _cell_center are BOARD space; these spawn child controls,
			# which are control space — so the centred board's origin comes back.
			var at: Vector2 = _disp.get(id, _cell_center(Combat.cell_of(id))) + _origin()
			var delta := hp - int(_hp_seen[id])
			Ui.rise_text(self, ("%+d" if delta > 0 else "%d") % delta,
				Ui.c("gold") if delta > 0 else Ui.c("danger"), at + Vector2(-12, -34))
			if delta < 0:
				_impact(at)
				_lunge(cur_id, id)
				if id == "pc":
					_shudder()
		_hp_seen[id] = hp
	queue_redraw()


func _cell_center(cell: Array) -> Vector2:
	var cs := _cell_size()
	return Vector2((int(cell[0]) + 0.5) * cs.x, (int(cell[1]) + 0.5) * cs.y)


func _process(delta: float) -> void:
	var moving := false
	var pos := Combat.positions()
	for id in pos:
		var target := _cell_center(pos[id])
		var at: Vector2 = _disp.get(id, target)
		if at.distance_to(target) > 0.5:
			_disp[id] = at.lerp(target, 1.0 - exp(-10.0 * delta))
			moving = true
		else:
			_disp[id] = target
	if moving or _shake != Vector2.ZERO or _lunge_off != Vector2.ZERO:
		queue_redraw()


## A radial bloom where the blow landed.
func _impact(at: Vector2) -> void:
	var flash := TextureRect.new()
	flash.texture = Ui.glow_tex()
	flash.modulate = Color(Ui.c("danger"), 0.85)
	flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := 26.0
	flash.position = at - Vector2(s, s) / 2.0
	flash.size = Vector2(s, s)
	flash.pivot_offset = Vector2(s, s) / 2.0
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2.ONE * 3.2, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(flash.queue_free)


## The attacker leans into the blow and settles back.
func _lunge(attacker_id: String, victim_id: String) -> void:
	if attacker_id == "" or attacker_id == victim_id:
		return
	var a: Vector2 = _disp.get(attacker_id, _cell_center(Combat.cell_of(attacker_id)))
	var v: Vector2 = _disp.get(victim_id, _cell_center(Combat.cell_of(victim_id)))
	var dir := (v - a).normalized() * minf(a.distance_to(v) * 0.35, 22.0)
	_lunge_id = attacker_id
	var tw := create_tween()
	tw.tween_method(func(t): _lunge_off = dir * t; queue_redraw(), 0.0, 1.0, 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t): _lunge_off = dir * t; queue_redraw(), 1.0, 0.0, 0.16).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _lunge_id = "")


## The board itself shudders when the hero takes the hit.
func _shudder() -> void:
	var tw := create_tween()
	for i in 4:
		var off := Vector2(randf_range(-5, 5), randf_range(-4, 4)) * (1.0 - i / 4.0)
		tw.tween_method(func(t): _shake = off * t; queue_redraw(), 1.0, 0.0, 0.05)
	tw.tween_callback(func(): _shake = Vector2.ZERO)


## R11-02 — ONE cell size, both axes. Dividing width and height independently
## drew 5-ft squares as 75x40 rectangles: every baked tile stretched to double
## width, and a Chebyshev grid — where a diagonal step costs what an orthogonal
## one costs — drawn in a shape where it visibly does not.
func _cell_size() -> Vector2:
	var s := minf(size.x / Combat.MAP_COLS, size.y / Combat.MAP_ROWS)
	return Vector2(s, s)


func _board_size() -> Vector2:
	var cs := _cell_size()
	return Vector2(cs.x * Combat.MAP_COLS, cs.y * Combat.MAP_ROWS)


## Square cells rarely fill the control, so the board is centred in it. `_draw`
## applies this once as a transform; everything inside it works in board space.
func _origin() -> Vector2:
	return ((size - _board_size()) * 0.5).floor()


func _cell_at(p: Vector2) -> Array:
	var cs := _cell_size()
	var b := p - _origin()
	return [clampi(int(b.x / cs.x), 0, Combat.MAP_COLS - 1), clampi(int(b.y / cs.y), 0, Combat.MAP_ROWS - 1)]


## Pad cursor (controller): the d-pad steers the hover cell; accept clicks it —
## the same signals a mouse click emits, so the engine can't tell them apart.
func pad_move(dx: int, dy: int) -> void:
	if _hover[0] < 0:
		@warning_ignore("integer_division")
		_hover = [Combat.MAP_COLS / 2, Combat.MAP_ROWS / 2]
	else:
		_hover = [clampi(int(_hover[0]) + dx, 0, Combat.MAP_COLS - 1),
			clampi(int(_hover[1]) + dy, 0, Combat.MAP_ROWS - 1)]
	queue_redraw()


func pad_activate() -> void:
	if _hover[0] < 0:
		return
	var pos := Combat.positions()
	for id in pos:
		if int(pos[id][0]) == int(_hover[0]) and int(pos[id][1]) == int(_hover[1]):
			token_clicked.emit(str(id))
			return
	cell_clicked.emit([int(_hover[0]), int(_hover[1])])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		if _drag_pc:
			_drag_pt = event.position
		if c != _hover or _drag_pc:
			_hover = c
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		var pos := Combat.positions()
		if event.pressed:
			_press_cell = cell
			# Your own token lifts under the press — drop it to move, tap it to
			# select. Foes and floor keep the immediate click (attack / move).
			if pos.has("pc") and int(pos["pc"][0]) == cell[0] and int(pos["pc"][1]) == cell[1]:
				_drag_pc = true
				_drag_pt = event.position
				queue_redraw()
				return
			for id in pos:
				if int(pos[id][0]) == cell[0] and int(pos[id][1]) == cell[1]:
					token_clicked.emit(str(id))
					return
			cell_clicked.emit(cell)
		elif _drag_pc:
			_drag_pc = false
			queue_redraw()
			if cell != _press_cell:
				cell_clicked.emit(cell)   # the drop IS the move order
			else:
				token_clicked.emit("pc")  # a tap in place selects, as before


var _painted: ImageTexture = null
var _painted_for := ""


## The composed field, rebuilt only when the field or the world actually changes
## — a fight lasts minutes and the ground does not move under it.
func _composite(laid: Dictionary) -> ImageTexture:
	var wid := GameState.world_id()
	var sig := "%s|%d|%s" % [wid, laid.size(), str(laid.hash())]
	if sig == _painted_for:
		return _painted
	_painted_for = sig
	_painted = BoardPaint.compose(wid, laid, Combat.MAP_COLS, Combat.MAP_ROWS, TILE_VARIANTS)
	return _painted


## The art a combatant's token wears — one source with the initiative rail.
func _token_art(m: Dictionary) -> Texture2D:
	return Art.combatant_tex(m)


func _draw() -> void:
	# The origin rides in the transform so every cell rect below is board space.
	draw_set_transform(_shake + _origin(), 0.0, Vector2.ONE)  # the whole field shudders
	var cs := _cell_size()
	var board := _board_size()
	# ── The battlefield itself: painted underlay, framed and scrimmed ──
	# R10 — a laid battlefield draws itself cell by cell. Each square knows its
	# own role, so the mechanical layer and the picture cannot drift apart the
	# way a sampled painting always did. `tile-<role>-<world>` art replaces the
	# flat tint as the bake lands; until then the tint IS the map, and it is
	# legible, which is the whole point of proving the layout before the GPU.
	var laid: Dictionary = Combat.data().get("cells", {}) if Combat.data().get("cells") is Dictionary else {}
	if not laid.is_empty():
		# One composed image, built once per field (BoardPaint): dual-grid
		# blending across material seams, object backgrounds keyed away, variant
		# brightness levelled. Drawing it per cell is what made every boundary a
		# hard rectangle — there are no transition tiles in the library to draw.
		var painted := _composite(laid)
		if painted != null:
			draw_texture_rect(painted, Rect2(Vector2.ZERO, board), false, Color(0.94, 0.92, 0.96))
		else:
			for x in Combat.MAP_COLS:
				for y in Combat.MAP_ROWS:
					var role := str(laid.get("%d,%d" % [x, y], ""))
					draw_rect(Rect2(Vector2(x * cs.x, y * cs.y), cs),
						Color(Combat.ROLES.get(role, {}).get("tint", Color(0.18, 0.18, 0.2))))
		draw_rect(Rect2(Vector2.ZERO, board), Color(Ui.c("night"), 0.06))
		# R11 — the permanent mechanical overlay lived here: hatching on every
		# impassable square, drag-stripes on every difficult one, a cover pip on
		# every third cell. It was defended as "stated rather than implied", but
		# it stamped a diagram over four GPU-hours of painted terrain and never
		# switched off. The VTT guidance is the other way round: bake the answer
		# into the map, and the player never has to ask during combat. A boulder
		# reads as impassable because it looks like a boulder.
		#
		# Reachability is a QUESTION, not a property of the ground, so it is
		# answered while the player is asking it — see the movement overlay below.
	var under := Art.texture_for(map_key) if map_key != "" and laid.is_empty() else null
	if under == null and laid.is_empty():
		under = Art.texture_for(GameState.world_id())
	if under != null:
		# Cover-fit the painting.
		var tsize := Vector2(under.get_width(), under.get_height())
		var scale := maxf(board.x / tsize.x, board.y / tsize.y)
		var draw_size := tsize * scale
		var offset := (board - draw_size) / 2.0
		draw_texture_rect(under, Rect2(offset, draw_size), false, Color(0.92, 0.9, 0.95))
		draw_rect(Rect2(Vector2.ZERO, board), Color(Ui.c("night"), 0.32))
	elif laid.is_empty():
		draw_rect(Rect2(Vector2.ZERO, board), Color(Ui.c("night2"), 0.7))
	# Ornate board frame.
	draw_rect(Rect2(Vector2.ZERO, board), Color(Ui.c("night"), 0.9), false, 3.0)
	draw_rect(Rect2(Vector2(2, 2), board - Vector2(4, 4)), Color(Ui.c("gold"), 0.55), false, 1.5)
	var pos := Combat.positions()
	var c := Combat.data()
	var budget: Dictionary = Combat.move_budget(c) if bool(c.get("active", false)) else {"left": 0}
	var pc_cell: Array = pos.get("pc", [0, 0])
	var my_turn: bool = str(Combat.current(c).get("id", "")) == "pc"
	# ── The movement overlay: on while the player is choosing, off otherwise ──
	# Shown only when it is your turn, you have movement left, AND the cursor is
	# actually on the board (or dragging your token) — the moment you are asking
	# "where can I go?". It is not the board's permanent clothing.
	if my_turn and int(budget.get("left", 0)) > 0 and (_drag_pc or _hover[0] >= 0):
		# R10 — glow what you can actually WALK to. The old test was Chebyshev
		# distance, which lit squares on the far side of a wall.
		var reach := Combat.reachable(pc_cell, int(budget["left"]))
		for key in reach:
			var rxy := str(key).split(",")
			draw_rect(Rect2(Vector2(int(rxy[0]) * cs.x, int(rxy[1]) * cs.y), cs), Color(Ui.c("gold"), 0.16))
		# What refuses you, in light red — and only the squares near enough to be
		# a real choice. Lighting up all 160 would be the old overlay again.
		for key in reach:
			var rxy := str(key).split(",")
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = int(rxy[0]) + d[0]
				var ny: int = int(rxy[1]) + d[1]
				if nx < 0 or nx >= Combat.MAP_COLS or ny < 0 or ny >= Combat.MAP_ROWS:
					continue
				if reach.has("%d,%d" % [nx, ny]) or not Combat._impassable([nx, ny]):
					continue
				draw_rect(Rect2(Vector2(nx * cs.x, ny * cs.y), cs), Color(Ui.c("danger"), 0.18))
	# R10 — borders. Walls are drawn ON the line between two squares, which is
	# where they actually are. Procedural, not sprites: a wall is a thin strip
	# with corner joins and generated art will never tile cleanly at that scale,
	# while edges are exactly where a seam shows worst.
	for key in Combat.edges():
		var parts := str(key).split(",")
		if parts.size() != 3:
			continue
		var ex := int(parts[0])
		var ey := int(parts[1])
		var horizontal: bool = str(parts[2]) == "N"
		var a := Vector2(ex * cs.x, ey * cs.y)
		var b := a + (Vector2(cs.x, 0) if horizontal else Vector2(0, cs.y))
		var kind := str(Combat.edges()[key])
		var spec: Dictionary = Combat.EDGE_KINDS.get(kind, {})
		var solid: bool = not bool(spec.get("move", true))
		var opaque: bool = not bool(spec.get("sight", true))
		var col: Color = Ui.c("ink_dim") if solid else Color(Ui.c("gold"), 0.55)
		if kind == "door_open":
			col = Color(Ui.c("gold"), 0.75)
		elif kind == "door_shut":
			col = Ui.c("gold")
		draw_line(a, b, Color(Ui.c("night"), 0.9), 7.0)   # a shadow so it reads on any tile
		draw_line(a, b, col, 5.0 if solid else 3.0)
		if not opaque and solid:                          # a window: you see, you do not pass
			var mid := a.lerp(b, 0.5)
			draw_line(a.lerp(mid, 0.55), b.lerp(mid, 0.55), Color(0.6, 0.85, 1.0, 0.85), 2.0)
		if kind == "door_open":
			draw_circle(a.lerp(b, 0.5), 3.0, Ui.c("gold"))
	# The grid, at the VTT default. It was 0.07 — a third of this — on the theory
	# that the painting should show through, which left the seams between tiles
	# reading as accidents. Foundry ships 0.2, and it works for the reason the
	# whisper did not: a visible grid gives the eye a REASON for the seams, so a
	# tiled field reads as a board rather than as a patchwork.
	var grid_col := Color(Ui.c("ink"), 0.2)
	for x in Combat.MAP_COLS + 1:
		draw_line(Vector2(x * cs.x, 0), Vector2(x * cs.x, board.y), grid_col)
	for y in Combat.MAP_ROWS + 1:
		draw_line(Vector2(0, y * cs.y), Vector2(board.x, y * cs.y), grid_col)
	if _hover[0] >= 0:
		draw_rect(Rect2(Vector2(_hover[0] * cs.x, _hover[1] * cs.y), cs), Color(Ui.c("gold"), 0.5), false, 2.0)
	# ── Tokens: art discs ringed by their side, HP arc, name plate ──
	var cur_id := str(Combat.current(c).get("id", ""))
	var font := get_theme_default_font()
	for m in c.get("combatants", []):
		var id := str(m.get("id", ""))
		if not pos.has(id):
			continue
		var center: Vector2 = _disp.get(id, _cell_center(pos[id]))
		if id == _lunge_id:
			center += _lunge_off
		var r := minf(cs.x, cs.y) * 0.46
		var alive := int(m.get("hp", 0)) > 0
		var col: Color = Ui.c("gold") if m.get("side") == "ally" else Ui.c("danger")
		if not alive:
			col = Color(col, 0.3)
		# Shadow, art (or tinted disc), ring.
		draw_circle(center + Vector2(2, 3), r, Color(0, 0, 0, 0.45))
		var art := _token_art(m)
		if art != null:
			var d := r * 2.0
			draw_texture_rect(art, Rect2(center - Vector2(r, r), Vector2(d, d)), false,
				Color(1, 1, 1, 1.0 if alive else 0.35))
		else:
			draw_circle(center, r, Color(col.darkened(0.4), 0.9))
			var letter := str(m.get("name", "?")).left(1).to_upper()
			var fs := int(r)
			var sz := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(font, center + Vector2(-sz.x / 2, sz.y / 3), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Ui.c("ink"))
		draw_arc(center, r, 0, TAU, 40, col, 2.5)
		if alive:
			var frac := clampf(float(m.get("hp", 0)) / maxf(1.0, float(m.get("hpMax", 1))), 0.0, 1.0)
			draw_arc(center, r + 3.5, -PI / 2, -PI / 2 + TAU * frac, 40, Color(col, 0.95), 3.5)
		if id == cur_id:
			draw_arc(center, r + 8, 0, TAU, 40, Ui.c("gold_soft"), 2.0)
		if not alive:
			var xs := r * 0.5
			draw_line(center - Vector2(xs, xs), center + Vector2(xs, xs), Color(Ui.c("danger"), 0.9), 3.0)
			draw_line(center + Vector2(-xs, xs), center + Vector2(xs, -xs), Color(Ui.c("danger"), 0.9), 3.0)
		# Name plate.
		var nm := str(m.get("name", ""))
		var nsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var np := center + Vector2(-nsz.x / 2, r + 16)
		draw_rect(Rect2(np + Vector2(-4, -11), Vector2(nsz.x + 8, 15)), Color(Ui.c("night"), 0.72))
		draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Ui.c("ink") if alive else Ui.c("ink_dim"))
	# The lifted token rides the cursor as a ghost until it's dropped.
	if _drag_pc:
		var gr := minf(cs.x, cs.y) * 0.46
		var ghost := Art.combatant_tex({"id": "pc"})
		if ghost != null:
			draw_texture_rect(ghost, Rect2((_drag_pt - _origin()) - Vector2(gr, gr), Vector2(gr * 2, gr * 2)), false, Color(1, 1, 1, 0.6))
		else:
			draw_circle(_drag_pt - _origin(), gr, Color(Ui.c("gold"), 0.4))
		draw_arc(_drag_pt - _origin(), gr, 0, TAU, 40, Color(Ui.c("gold"), 0.8), 2.0)

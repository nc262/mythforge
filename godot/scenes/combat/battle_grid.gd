extends Control
## The tactical board, painted: a generated overhead battle map of the
## ACTUAL place underneath, whisper-thin grid lines, and art tokens —
## the hero's portrait, bestiary paintings for the foes — ringed in their
## side's color with an HP arc and a name plate. Movement and reach math
## live in Combat; this draws and routes clicks.

signal cell_clicked(cell: Array)
signal token_clicked(id: String)

var map_key := ""  # Art cache key of the underlay ("" = scrimmed scene art)
var _hover := [-1, -1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Combat.changed.connect(queue_redraw)
	Art.art_ready.connect(func(_k): queue_redraw())
	custom_minimum_size = Vector2(Combat.MAP_COLS * 40, Combat.MAP_ROWS * 40)


func _cell_size() -> Vector2:
	return Vector2(size.x / Combat.MAP_COLS, size.y / Combat.MAP_ROWS)


func _cell_at(p: Vector2) -> Array:
	var cs := _cell_size()
	return [clampi(int(p.x / cs.x), 0, Combat.MAP_COLS - 1), clampi(int(p.y / cs.y), 0, Combat.MAP_ROWS - 1)]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		if c != _hover:
			_hover = c
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		var pos := Combat.positions()
		for id in pos:
			if int(pos[id][0]) == cell[0] and int(pos[id][1]) == cell[1]:
				token_clicked.emit(str(id))
				return
		cell_clicked.emit(cell)


## The art a combatant's token wears: hero portrait / bestiary painting.
func _token_art(m: Dictionary) -> ImageTexture:
	var id := str(m.get("id", ""))
	if id == "pc":
		return Art.round_tex("hero-" + GameState.cid().validate_filename())
	if id.begins_with("cmp"):
		return Art.round_tex("npc-" + str(m.get("name", "")).to_lower().replace(" ", "-"))
	var entry := Combat.bestiary_for(str(m.get("name", "")))
	if not entry.is_empty():
		var key := "beast-" + str(entry.get("slug", ""))
		if Art.has_art(key):
			return Art.round_tex(key)
		Art.ensure(key, str(entry.get("art", "")) + ", painted creature portrait, dark background, no text")
	return null


func _draw() -> void:
	var cs := _cell_size()
	# ── The battlefield itself: painted underlay, framed and scrimmed ──
	var under := Art.texture_for(map_key) if map_key != "" else null
	if under == null:
		under = Art.texture_for(GameState.world_id())
	if under != null:
		# Cover-fit the painting.
		var tsize := Vector2(under.get_width(), under.get_height())
		var scale := maxf(size.x / tsize.x, size.y / tsize.y)
		var draw_size := tsize * scale
		var offset := (Vector2(size.x, size.y) - draw_size) / 2.0
		draw_texture_rect(under, Rect2(offset, draw_size), false, Color(0.92, 0.9, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.32))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night2"), 0.7))
	# Ornate board frame.
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night"), 0.9), false, 3.0)
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(Ui.c("gold"), 0.55), false, 1.5)
	var pos := Combat.positions()
	var c := Combat.data()
	var budget: Dictionary = Combat.move_budget(c) if bool(c.get("active", false)) else {"left": 0}
	var pc_cell: Array = pos.get("pc", [0, 0])
	var my_turn: bool = str(Combat.current(c).get("id", "")) == "pc"
	# Reachable squares glow faint gold on your turn.
	if my_turn and int(budget.get("left", 0)) > 0:
		for x in Combat.MAP_COLS:
			for y in Combat.MAP_ROWS:
				if Combat.distance(pc_cell, [x, y]) <= int(budget["left"]):
					draw_rect(Rect2(Vector2(x * cs.x, y * cs.y), cs), Color(Ui.c("gold"), 0.06))
	# Whisper-thin grid — the painting shows through.
	var grid_col := Color(Ui.c("ink"), 0.07)
	for x in Combat.MAP_COLS + 1:
		draw_line(Vector2(x * cs.x, 0), Vector2(x * cs.x, size.y), grid_col)
	for y in Combat.MAP_ROWS + 1:
		draw_line(Vector2(0, y * cs.y), Vector2(size.x, y * cs.y), grid_col)
	if _hover[0] >= 0:
		draw_rect(Rect2(Vector2(_hover[0] * cs.x, _hover[1] * cs.y), cs), Color(Ui.c("gold"), 0.5), false, 2.0)
	# ── Tokens: art discs ringed by their side, HP arc, name plate ──
	var cur_id := str(Combat.current(c).get("id", ""))
	var font := get_theme_default_font()
	for m in c.get("combatants", []):
		var id := str(m.get("id", ""))
		if not pos.has(id):
			continue
		var center := Vector2((int(pos[id][0]) + 0.5) * cs.x, (int(pos[id][1]) + 0.5) * cs.y)
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

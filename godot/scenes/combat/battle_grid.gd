extends Control
## The tactical board: 16×10 cells, 5 ft each. Tokens are the real
## combatants; movement spends the round's budget; melee needs adjacency.
## Draws itself from Combat state — no state of its own.

signal cell_clicked(cell: Array)
signal token_clicked(id: String)

var _hover := [-1, -1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Combat.changed.connect(queue_redraw)
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


func _draw() -> void:
	var cs := _cell_size()
	var grid_col := Color(Ui.c("border_soft"), 0.6)
	var pos := Combat.positions()
	var c := Combat.data()
	var budget: Dictionary = Combat.move_budget(c) if bool(c.get("active", false)) else {"left": 0}
	var pc_cell: Array = pos.get("pc", [0, 0])
	var my_turn: bool = str(Combat.current(c).get("id", "")) == "pc"
	# Board wash + reachable cells while it's your turn.
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.c("night2"), 0.55))
	if my_turn and int(budget.get("left", 0)) > 0:
		for x in Combat.MAP_COLS:
			for y in Combat.MAP_ROWS:
				if Combat.distance(pc_cell, [x, y]) <= int(budget["left"]):
					draw_rect(Rect2(Vector2(x * cs.x, y * cs.y), cs), Color(Ui.c("gold"), 0.05))
	for x in Combat.MAP_COLS + 1:
		draw_line(Vector2(x * cs.x, 0), Vector2(x * cs.x, size.y), grid_col)
	for y in Combat.MAP_ROWS + 1:
		draw_line(Vector2(0, y * cs.y), Vector2(size.x, y * cs.y), grid_col)
	if _hover[0] >= 0:
		draw_rect(Rect2(Vector2(_hover[0] * cs.x, _hover[1] * cs.y), cs), Color(Ui.c("gold"), 0.35), false, 2.0)
	# Tokens: gold allies / danger foes, initial letter, HP arc, turn ring.
	var cur_id := str(Combat.current(c).get("id", ""))
	for m in c.get("combatants", []):
		var id := str(m.get("id", ""))
		if not pos.has(id):
			continue
		var center := Vector2((int(pos[id][0]) + 0.5) * cs.x, (int(pos[id][1]) + 0.5) * cs.y)
		var r := minf(cs.x, cs.y) * 0.38
		var alive := int(m.get("hp", 0)) > 0
		var col: Color = Ui.c("gold") if m.get("side") == "ally" else Ui.c("danger")
		if not alive:
			col = Color(col, 0.25)
		draw_circle(center, r, Color(col, 0.28))
		draw_arc(center, r, 0, TAU, 32, col, 2.0)
		if alive:
			var frac := clampf(float(m.get("hp", 0)) / maxf(1.0, float(m.get("hpMax", 1))), 0.0, 1.0)
			draw_arc(center, r + 3, -PI / 2, -PI / 2 + TAU * frac, 32, Color(col, 0.9), 3.0)
		if id == cur_id:
			draw_arc(center, r + 7, 0, TAU, 32, Ui.c("gold_soft"), 2.0)
		var letter := str(m.get("name", "?")).left(1).to_upper()
		var font := get_theme_default_font()
		var fs := int(r)
		var sz := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, center + Vector2(-sz.x / 2, sz.y / 3), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Ui.c("ink"))

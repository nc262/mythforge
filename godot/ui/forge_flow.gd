class_name ForgeFlow extends Control
## MDL: the staged-ritual scaffold every forge shares — the margined column,
## the MythStageRail, the stage box, the status line, the nav row, the card
## grid. A forge subclass supplies its rail labels via _stages(), builds each
## stage in _build_stage(i), and overrides the small hooks where its table
## differs (_env, _leave_label, _initial_stage, _on_stage_entered, _nav).
## Extracted verbatim from the four forges (character/campaign/world/adventure)
## so a new forge is stage-content only — never scaffold again.

signal closed

const RailT := preload("res://ui/myth_stage_rail.gd")
const CardT := preload("res://ui/myth_choice_card.gd")

var _rail: MythStageRail
var _stage_box: VBoxContainer
var _status: Label
## The same hint, beside the nav row — see _refuse(). Rebuilt per stage.
var _nav_hint: Label = null
var _col: VBoxContainer   # exposed so a forge can slot extra rows (the ledger)
var _phase := 0.0
var _busy := false


# ── The subclass contract ────────────────────────────────────────────────────
func _stages() -> Array:
	return []


func _build_stage(_i: int) -> void:
	pass


func _leave_label() -> String:
	return "leave the table"


## [env_key, particle_kind, points] for MythEnvironment.mount.
func _env() -> Array:
	return ["env-wartable", "dust", [Vector2(0.08, 0.34), Vector2(0.92, 0.34)]]


func _initial_stage() -> int:
	# Harness hook: land on a given stage for visual regression shots.
	var shot := OS.get_environment("MF_FORGE_STAGE")
	return int(shot) if shot != "" else 0


## Runs after the stage box is cleared, before the new stage builds —
## a forge resets its per-stage state here (status line, ledger, edits).
func _on_stage_entered(_i: int) -> void:
	pass


# ── The scaffold ─────────────────────────────────────────────────────────────
func _ready() -> void:
	theme = Ui.theme
	set_process(not Ui.reduce_motion)
	var env := _env()
	MythEnvironment.mount(self, str(env[0]), str(env[1]), env[2])
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, Ui.SPACE["xl"] * 2)
	margin.add_theme_constant_override("margin_top", Ui.SPACE["l"])
	margin.add_theme_constant_override("margin_bottom", Ui.SPACE["l"])
	add_child(margin)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", Ui.SPACE["m"])
	margin.add_child(_col)
	_rail = RailT.new(_stages())
	_rail.stage_clicked.connect(_enter_stage)
	_col.add_child(_rail)
	_stage_box = VBoxContainer.new()
	_stage_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_box.add_theme_constant_override("separation", Ui.SPACE["m"])
	_col.add_child(_stage_box)
	_status = Label.new()
	_status.theme_type_variation = "HintLabel"
	_status.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_status)
	_enter_stage(_initial_stage())


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


## MIL §8 — a stage is a page of the ritual. The old page leaves the tree
## immediately (no double-drawn frame) and the new one arrives staggered, so
## the forge never blinks between steps. Kept synchronous on purpose: an await
## here would let a fast double-advance interleave two stage builds.
func _enter_stage(i: int) -> void:
	if _busy:
		return
	var moving := _stage_box.get_child_count() > 0
	_rail.set_stage(i)
	_clear_stage()
	_on_stage_entered(i)
	_build_stage(i)
	if moving:
		Sfx.ui("page")
	Ui.polish(_stage_box)
	Ui.reveal_children(_stage_box, Ui.MOTION["stagger"])


func _clear_stage() -> void:
	for ch in _stage_box.get_children():
		_stage_box.remove_child(ch)  # off-tree NOW — queue_free alone double-draws a frame
		ch.queue_free()


func _title_label(text: String) -> void:
	var t := Label.new()
	t.theme_type_variation = "TitleLabel"
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_box.add_child(t)


func _nav(back_to: int, fwd_text: String, fwd: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	if back_to >= 0:
		var back := Button.new()
		back.theme_type_variation = "GhostButton"
		back.text = "‹ back"
		back.pressed.connect(func(): _enter_stage(back_to))
		row.add_child(back)
	var go := Button.new()
	go.theme_type_variation = "AccentButton"
	go.text = fwd_text
	go.pressed.connect(fwd)
	row.add_child(go)
	var leave := Button.new()
	leave.theme_type_variation = "GhostButton"
	leave.text = _leave_label()
	leave.pressed.connect(func(): closed.emit())
	row.add_child(leave)
	_stage_box.add_child(row)
	# UI-8 — THE REFUSAL BELONGS TO THE BUTTON THAT REFUSED.
	#
	# `_status` is the last child of `_col`, and `_stage_box` above it expands to
	# fill — so a hint set when NEXT is pressed printed at the very bottom of the
	# window, measured ~250 px below the button the player was looking at. Most
	# players never saw it and pressed again.
	#
	# This label rides WITH the nav row, is rebuilt with every stage (so it can
	# never carry a stale complaint into the next one), and `_refuse()` writes to
	# both: near the button for the eye, and in the old place for anything that
	# still reads _status.
	_nav_hint = Label.new()
	_nav_hint.theme_type_variation = "HintLabel"
	_nav_hint.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_box.add_child(_nav_hint)


## Say no where the player is looking, and shake the control that said it.
func _refuse(msg: String) -> void:
	_status.text = msg
	if is_instance_valid(_nav_hint):
		_nav_hint.text = msg
		Ui.shake(_nav_hint)


## A grid of choice cards with single-select behavior — the forge staple.
func _card_grid(entries: Array, cols: int, selected_title: String, on_pick: Callable) -> void:
	var cards: Array = []
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for e in entries:
		var card := CardT.new(e)
		card.set_selected(str(e.get("title", "")) == selected_title)
		card.pressed.connect(func():
			for c in cards:
				c.set_selected(c == card)
			on_pick.call(e))
		cards.append(card)
		grid.add_child(card)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_stage_box.add_child(gc)

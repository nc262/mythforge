class_name MythPortrait extends Control
## MDL: the round portrait — art disc + colored ring + optional halo glow.
## Tokens, sheet, dialogue speakers, initiative chips all wear this face.

var tex: Texture2D            # pre-rounded (Art.round_tex) or null → glyph
var glyph := "?"
var ring_role := "gold"
var halo := false
var hp_frac := -1.0           # 0..1 draws a vitals arc; -1 = none
var turn := false             # this one acts now: outer gold ring


func _init(size_px := 96, ring := "gold", with_halo := false) -> void:
	ring_role = ring
	halo = with_halo
	custom_minimum_size = Vector2(size_px, size_px)


## UI-11 — A PORTRAIT IS NEVER NOTHING.
##
## The empty state below already draws a disc and a letter, so "no art" has
## always been handled. What was not handled is a BLANK letter: eleven call
## sites pass `str(name).left(1)`, which is "" for a hero who has not been named
## yet, and an unnamed hero on a cold cache drew an empty ring — no face, no
## initial, nothing. Guarding here rather than at eleven call sites, because the
## next caller will make the same reasonable-looking mistake.
func set_portrait(t: Texture2D, g := "?") -> void:
	tex = t
	glyph = g.strip_edges() if g.strip_edges() != "" else "?"
	queue_redraw()


func set_vitals(frac: float, is_turn := false) -> void:
	hp_frac = frac
	turn = is_turn
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	if halo:
		var gs := r * 3.2
		draw_texture_rect(Ui.glow_tex(), Rect2(center - Vector2(gs, gs) / 2.0, Vector2(gs, gs)),
			false, Color(Ui.c(ring_role), 0.28))
	draw_circle(center + Vector2(1, 2), r, Color(0, 0, 0, 0.4))
	if tex != null:
		draw_texture_rect(tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false)
	else:
		draw_circle(center, r, Color(Ui.c("surface2"), 0.95))
		var font := Ui.display
		var fs := int(r * 0.9)
		var sz := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, center + Vector2(-sz.x / 2.0, sz.y / 3.0), glyph,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Ui.c("ink_dim"))
	draw_arc(center, r, 0, TAU, 48, Ui.c(ring_role), 2.5, true)
	if hp_frac >= 0.0:
		draw_arc(center, r + 3.0, -PI / 2, -PI / 2 + TAU * clampf(hp_frac, 0.0, 1.0), 48,
			Color(Ui.c(ring_role), 0.95), 3.0, true)
	if turn:
		draw_arc(center, r + 7.0, 0, TAU, 48, Ui.c("gold_soft"), 2.0, true)

class_name MythIcon extends Control
## MDL: the Mythforge Icon Library — every icon hand-drawn in code, one
## consistent language (2px gold ink strokes, subtle fills), never a font
## glyph, emoji, or icon pack. Names: banner (continue) · anvil (hero) ·
## wartable (campaign) · compass (adventure) · book (chronicles) ·
## runewheel (settings) · door (exit) · cups (companions) · quill · hammer.

var icon := "compass"
var tint_role := "gold"


func _init(name_ := "compass", size_px := 30, role := "gold") -> void:
	icon = name_
	tint_role = role
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var g: Color = Ui.c(tint_role)
	var soft := Color(g, 0.35)
	var s := minf(size.x, size.y)
	var u := s / 24.0  # design grid: 24×24
	var o := (Vector2(size.x, size.y) - Vector2(s, s)) / 2.0
	var w := maxf(1.6, u * 1.6)
	match icon:
		"banner":  # a waypoint pennant — the tale continues
			draw_line(o + Vector2(6, 3) * u, o + Vector2(6, 21) * u, g, w)
			var flag := PackedVector2Array([o + Vector2(6, 4) * u, o + Vector2(19, 6.5) * u, o + Vector2(14, 9) * u, o + Vector2(19, 11.5) * u, o + Vector2(6, 14) * u])
			draw_colored_polygon(flag, soft)
			draw_polyline(flag, g, w * 0.8, true)
		"anvil":  # the hero is struck here
			var top := PackedVector2Array([o + Vector2(3, 8) * u, o + Vector2(21, 8) * u, o + Vector2(17, 12) * u, o + Vector2(10, 12) * u, o + Vector2(3, 10.5) * u])
			draw_colored_polygon(top, soft)
			draw_polyline(top + PackedVector2Array([top[0]]), g, w * 0.8, true)
			draw_rect(Rect2(o + Vector2(11, 12) * u, Vector2(4, 4) * u), soft)
			draw_rect(Rect2(o + Vector2(8, 16) * u, Vector2(10, 3) * u), soft)
			draw_rect(Rect2(o + Vector2(8, 16) * u, Vector2(10, 3) * u), g, false, w * 0.7)
			draw_circle(o + Vector2(6.5, 5.5) * u, 1.1 * u, g)  # the spark
		"wartable":  # the map on the table
			var mp := Rect2(o + Vector2(3.5, 5) * u, Vector2(17, 13) * u)
			draw_rect(mp, soft)
			draw_rect(mp, g, false, w * 0.8)
			draw_line(o + Vector2(8, 5) * u, o + Vector2(8, 18) * u, Color(g, 0.5), w * 0.5)
			draw_line(o + Vector2(3.5, 9) * u, o + Vector2(20.5, 9) * u, Color(g, 0.35), w * 0.5)
			draw_circle(o + Vector2(15, 13) * u, 2.2 * u, Color(g, 0.0))
			draw_arc(o + Vector2(15, 13) * u, 2.2 * u, 0, TAU, 20, g, w * 0.7)
			draw_circle(o + Vector2(15, 13) * u, 0.7 * u, g)
		"compass":  # the road not yet taken
			draw_arc(o + Vector2(12, 12) * u, 9 * u, 0, TAU, 40, g, w)
			var needle := PackedVector2Array([o + Vector2(12, 4.5) * u, o + Vector2(14.4, 12) * u, o + Vector2(12, 19.5) * u, o + Vector2(9.6, 12) * u])
			draw_colored_polygon(needle, soft)
			draw_polyline(needle + PackedVector2Array([needle[0]]), g, w * 0.7, true)
			draw_circle(o + Vector2(12, 12) * u, 1.2 * u, g)
		"book":  # the chronicles
			draw_line(o + Vector2(12, 5) * u, o + Vector2(12, 19) * u, g, w * 0.8)
			for side in [-1, 1]:
				var page := PackedVector2Array([o + Vector2(12, 5.6) * u, o + Vector2(12 + side * 8.5, 4) * u,
					o + Vector2(12 + side * 8.5, 17.5) * u, o + Vector2(12, 19) * u])
				draw_colored_polygon(page, soft)
				draw_polyline(page + PackedVector2Array([page[0]]), g, w * 0.7, true)
				for li in 3:
					draw_line(o + Vector2(12 + side * 2, 8.2 + li * 3) * u, o + Vector2(12 + side * 7, 7.4 + li * 3) * u, Color(g, 0.45), w * 0.45)
		"runewheel":  # settings — a rune-studded wheel, not a software gear
			draw_arc(o + Vector2(12, 12) * u, 7.5 * u, 0, TAU, 36, g, w)
			draw_arc(o + Vector2(12, 12) * u, 3.2 * u, 0, TAU, 24, g, w * 0.7)
			for k in 6:
				var ang := k * TAU / 6.0
				var stud := o + Vector2(12, 12) * u + Vector2(sin(ang), -cos(ang)) * 7.5 * u
				draw_circle(stud, 1.5 * u, soft)
				draw_circle(stud, 1.5 * u, Color(0, 0, 0, 0))
				draw_arc(stud, 1.5 * u, 0, TAU, 12, g, w * 0.55)
		"door":  # the door ajar — leave the hall
			draw_rect(Rect2(o + Vector2(5, 3.5) * u, Vector2(11, 17) * u), g, false, w * 0.8)
			var leaf := PackedVector2Array([o + Vector2(7, 4.5) * u, o + Vector2(17.5, 6.5) * u, o + Vector2(17.5, 21.5) * u, o + Vector2(7, 20) * u])
			draw_colored_polygon(leaf, soft)
			draw_polyline(leaf + PackedVector2Array([leaf[0]]), g, w * 0.7, true)
			draw_circle(o + Vector2(15.4, 13.5) * u, 0.9 * u, g)
		"cups":  # two cups at a quiet table — the companions
			for side in [-1, 1]:
				var cx: float = 12.0 + side * 5.2
				draw_arc(o + Vector2(cx, 11) * u, 3.4 * u, 0, PI, 18, g, w * 0.8)
				draw_line(o + Vector2(cx - 3.4, 11) * u, o + Vector2(cx + 3.4, 11) * u, g, w * 0.8)
				draw_line(o + Vector2(cx, 14.4) * u, o + Vector2(cx, 17) * u, g, w * 0.7)
				draw_line(o + Vector2(cx - 2.4, 17.5) * u, o + Vector2(cx + 2.4, 17.5) * u, g, w * 0.7)
		"quill":
			draw_line(o + Vector2(6, 19) * u, o + Vector2(17, 5) * u, g, w)
			var feather := PackedVector2Array([o + Vector2(17, 5) * u, o + Vector2(20.5, 4) * u, o + Vector2(18.5, 8) * u, o + Vector2(13.5, 10) * u])
			draw_colored_polygon(feather, soft)
			draw_polyline(feather + PackedVector2Array([feather[0]]), g, w * 0.6, true)
			draw_line(o + Vector2(5, 20.5) * u, o + Vector2(8.5, 20.5) * u, Color(g, 0.6), w * 0.6)
		"hammer":
			draw_line(o + Vector2(9.5, 9.5) * u, o + Vector2(18, 20) * u, g, w * 1.1)
			var head := Rect2(o + Vector2(4, 3.5) * u, Vector2(10, 6) * u)
			draw_rect(head, soft)
			draw_rect(head, g, false, w * 0.7)
		_:
			draw_arc(o + Vector2(12, 12) * u, 8 * u, 0, TAU, 32, g, w)

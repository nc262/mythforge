class_name MythIcon extends Control
## MDL: the Mythforge Icon Library — every icon hand-drawn in code, one
## consistent language (2px gold ink strokes, subtle fills), never a font
## glyph, emoji, or icon pack. Names: banner (continue) · anvil (hero) ·
## wartable (campaign) · compass (adventure) · book (chronicles) ·
## runewheel (settings) · door (exit) · cups (companions) · quill · hammer.

var icon := "compass"
var tint_role := "gold"

## Every hand-drawn name (the fallback "sigil" catches anything else).
const NAMES := ["banner", "anvil", "wartable", "compass", "book", "runewheel",
	"door", "cups", "quill", "hammer", "pack", "scroll", "die", "easel", "coins",
	"moon", "tent", "retell", "sword", "shield", "star", "flame", "skull",
	"crown", "mountain", "ship", "globe", "tune", "save", "bolt", "boot",
	"blood", "hourglass", "medal", "swirl", "mug", "pillar", "tree", "house", "pin", "sigil"]

## Legacy emoji → the icon that carries the same meaning. Lets old card
## payloads keep their glyph string while rendering as real art (no emoji).
const FROM_EMOJI := {
	"🛡": "shield", "⚔": "sword", "🗡": "sword", "🪓": "sword", "🏹": "sword",
	"✨": "star", "🔮": "star", "🌟": "star", "⭐": "star", "🕯": "flame",
	"🔥": "flame", "💀": "skull", "☠": "skull", "🎩": "crown", "👑": "crown",
	"🏔": "mountain", "⛰": "mountain", "⚓": "ship", "🛰": "ship", "🚀": "ship",
	"⚒": "anvil", "⛏": "hammer", "🔨": "hammer", "📖": "book", "📚": "book",
	"📜": "scroll", "🎲": "die", "🧭": "compass", "🌍": "compass", "🌐": "compass",
	"🛒": "coins", "💰": "coins", "🪙": "coins",
	"⚙": "runewheel", "🧬": "sigil", "🧪": "sigil", "🔇": "sigil", "🎬": "sigil",
	"🕊": "sigil", "🌑": "moon", "🌙": "moon", "⛺": "tent",
	"🎛": "tune", "💾": "save", "⚡": "bolt", "🥾": "boot", "🩸": "blood",
	"⏳": "hourglass", "🕰": "hourglass", "🎖": "medal", "🌀": "swirl",
	"🍺": "mug", "🏛": "pillar", "🌲": "tree", "🏠": "house", "📍": "pin",
	"🗺": "wartable", "🖼": "easel", "🤝": "cups", "🎉": "star", "🏁": "banner",
}


## Resolve any glyph string (icon name OR legacy emoji) to a drawn icon name.
static func resolve(glyph: String) -> String:
	if glyph in NAMES:
		return glyph
	return FROM_EMOJI.get(glyph, "sigil")


func _init(name_ := "compass", size_px := 30, role := "gold") -> void:
	icon = name_
	tint_role = role
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# "bake" renders a pure-white master so one PNG tints to any world palette.
	var g: Color = Color(1, 1, 1, 1) if tint_role == "bake" else Ui.c(tint_role)
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
		"pack":  # the rucksack — inventory
			var body := PackedVector2Array([o + Vector2(6, 9) * u, o + Vector2(18, 9) * u, o + Vector2(19, 20) * u, o + Vector2(5, 20) * u])
			draw_colored_polygon(body, soft)
			draw_polyline(body + PackedVector2Array([body[0]]), g, w * 0.75, true)
			draw_arc(o + Vector2(12, 9) * u, 4 * u, PI, TAU, 16, g, w * 0.75)  # the flap-strap arch
			draw_line(o + Vector2(9, 13.5) * u, o + Vector2(15, 13.5) * u, Color(g, 0.6), w * 0.6)
			draw_rect(Rect2(o + Vector2(10.5, 13) * u, Vector2(3, 3) * u), Color(g, 0.5))
		"scroll":  # the codex — a rolled parchment
			draw_rect(Rect2(o + Vector2(6, 5) * u, Vector2(12, 14) * u), soft)
			draw_rect(Rect2(o + Vector2(6, 5) * u, Vector2(12, 14) * u), g, false, w * 0.7)
			for li in 3:
				draw_line(o + Vector2(8.5, 9 + li * 3) * u, o + Vector2(15.5, 9 + li * 3) * u, Color(g, 0.5), w * 0.5)
			draw_arc(o + Vector2(6, 5) * u, 1.6 * u, 0, TAU, 12, g, w * 0.7)
			draw_arc(o + Vector2(18, 19) * u, 1.6 * u, 0, TAU, 12, g, w * 0.7)
		"die":  # the d20 moment — a faceted stone
			var dd := PackedVector2Array([o + Vector2(12, 3.5) * u, o + Vector2(20, 8) * u, o + Vector2(20, 16) * u, o + Vector2(12, 20.5) * u, o + Vector2(4, 16) * u, o + Vector2(4, 8) * u])
			draw_colored_polygon(dd, soft)
			draw_polyline(dd + PackedVector2Array([dd[0]]), g, w * 0.8, true)
			var face := PackedVector2Array([o + Vector2(12, 7) * u, o + Vector2(16, 12) * u, o + Vector2(12, 15) * u, o + Vector2(8, 12) * u])
			draw_polyline(face + PackedVector2Array([face[0]]), Color(g, 0.7), w * 0.55, true)
			draw_line(o + Vector2(12, 3.5) * u, o + Vector2(12, 7) * u, Color(g, 0.45), w * 0.5)
		"easel":  # conjure the scene — a framed painting
			var fr := Rect2(o + Vector2(4, 4) * u, Vector2(16, 12) * u)
			draw_rect(fr, soft)
			draw_rect(fr, g, false, w * 0.8)
			draw_polyline(PackedVector2Array([o + Vector2(5, 14) * u, o + Vector2(10, 9) * u, o + Vector2(13, 12) * u, o + Vector2(16, 8) * u, o + Vector2(19, 14) * u]), Color(g, 0.7), w * 0.6)
			draw_circle(o + Vector2(15, 7.5) * u, 1.1 * u, g)  # the sun
			draw_line(o + Vector2(8, 16) * u, o + Vector2(8, 20) * u, g, w * 0.7)
			draw_line(o + Vector2(16, 16) * u, o + Vector2(16, 20) * u, g, w * 0.7)
		"coins":  # trade — a stack of coin
			for k in 3:
				var cy: float = 16.0 - k * 3.2
				draw_arc(o + Vector2(12, cy) * u, 5 * u, 0, TAU, 22, g, w * 0.7)
				draw_line(o + Vector2(7, cy) * u, o + Vector2(7, cy - 3.2) * u, Color(g, 0.5), w * 0.5)
				draw_line(o + Vector2(17, cy) * u, o + Vector2(17, cy - 3.2) * u, Color(g, 0.5), w * 0.5)
			draw_line(o + Vector2(12, 5.5) * u, o + Vector2(12, 8.5) * u, g, w * 0.6)
		"moon":  # short rest — a crescent
			draw_circle(o + Vector2(12, 12) * u, 8 * u, soft)
			draw_arc(o + Vector2(12, 12) * u, 8 * u, 0, TAU, 40, g, w * 0.7)
			draw_circle(o + Vector2(15, 10) * u, 7 * u, Ui.c("night"))
			draw_arc(o + Vector2(15, 10) * u, 7 * u, PI * 0.35, PI * 1.15, 24, Color(g, 0.5), w * 0.55)
		"tent":  # long rest — camp for the night
			var tent := PackedVector2Array([o + Vector2(12, 4) * u, o + Vector2(21, 19) * u, o + Vector2(3, 19) * u])
			draw_colored_polygon(tent, soft)
			draw_polyline(tent + PackedVector2Array([tent[0]]), g, w * 0.8, true)
			draw_line(o + Vector2(12, 4) * u, o + Vector2(12, 19) * u, Color(g, 0.55), w * 0.55)
			draw_polyline(PackedVector2Array([o + Vector2(10, 19) * u, o + Vector2(12, 13) * u, o + Vector2(14, 19) * u]), g, w * 0.6)
		"retell":  # another pass — a circling arrow
			draw_arc(o + Vector2(12, 12) * u, 7 * u, -PI * 0.5, PI * 1.15, 28, g, w)
			var tip := o + Vector2(12, 5) * u
			draw_polyline(PackedVector2Array([tip + Vector2(-3, -1) * u, tip, tip + Vector2(-1, 3.2) * u]), g, w)
		"sword":  # the martial road
			draw_line(o + Vector2(12, 4) * u, o + Vector2(12, 16) * u, g, w)
			draw_line(o + Vector2(12, 4) * u, o + Vector2(10.6, 6) * u, g, w * 0.7)
			draw_line(o + Vector2(8.5, 16) * u, o + Vector2(15.5, 16) * u, g, w)  # crossguard
			draw_line(o + Vector2(12, 16) * u, o + Vector2(12, 20) * u, soft, w * 1.4)  # grip
			draw_circle(o + Vector2(12, 20.5) * u, 1.1 * u, g)  # pommel
		"shield":  # the guarded road
			var sh := PackedVector2Array([o + Vector2(12, 3.5) * u, o + Vector2(19, 6) * u, o + Vector2(18, 15) * u, o + Vector2(12, 20.5) * u, o + Vector2(6, 15) * u, o + Vector2(5, 6) * u])
			draw_colored_polygon(sh, soft)
			draw_polyline(sh + PackedVector2Array([sh[0]]), g, w * 0.8, true)
			draw_line(o + Vector2(12, 5) * u, o + Vector2(12, 18) * u, Color(g, 0.45), w * 0.5)
			draw_line(o + Vector2(6.5, 9.5) * u, o + Vector2(17.5, 9.5) * u, Color(g, 0.45), w * 0.5)
		"star":  # magic, wonder, the arcane
			var pts := PackedVector2Array()
			for k in 10:
				var ang := -PI / 2 + k * PI / 5.0
				var rad: float = (8.5 if k % 2 == 0 else 3.6) * u
				pts.append(o + Vector2(12, 12) * u + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(pts, soft)
			draw_polyline(pts + PackedVector2Array([pts[0]]), g, w * 0.7, true)
		"flame":  # horror, dread, the guttering candle
			var fl := PackedVector2Array([o + Vector2(12, 3) * u, o + Vector2(17, 11) * u, o + Vector2(15.5, 17) * u, o + Vector2(12, 20) * u, o + Vector2(8.5, 17) * u, o + Vector2(7, 11) * u])
			draw_colored_polygon(fl, soft)
			draw_polyline(fl + PackedVector2Array([fl[0]]), g, w * 0.7, true)
			draw_line(o + Vector2(12, 9) * u, o + Vector2(12, 16.5) * u, Color(g, 0.6), w * 0.6)
		"skull":  # death, permadeath, the merciless world
			draw_circle(o + Vector2(12, 10) * u, 6.5 * u, soft)
			draw_arc(o + Vector2(12, 10) * u, 6.5 * u, PI, TAU, 20, g, w * 0.7)
			draw_rect(Rect2(o + Vector2(8.5, 14) * u, Vector2(7, 4) * u), soft)
			draw_circle(o + Vector2(9.6, 10) * u, 1.5 * u, Ui.c("night"))
			draw_circle(o + Vector2(14.4, 10) * u, 1.5 * u, Ui.c("night"))
			for tx in [10.0, 12.0, 14.0]:
				draw_line(o + Vector2(tx, 14) * u, o + Vector2(tx, 18) * u, Ui.c("night"), w * 0.5)
		"crown":  # rule, courts, the classic DM's chair
			var cr := PackedVector2Array([o + Vector2(4, 17) * u, o + Vector2(5, 7) * u, o + Vector2(9, 12) * u, o + Vector2(12, 5.5) * u, o + Vector2(15, 12) * u, o + Vector2(19, 7) * u, o + Vector2(20, 17) * u])
			draw_colored_polygon(cr, soft)
			draw_polyline(cr + PackedVector2Array([cr[0]]), g, w * 0.75, true)
			draw_line(o + Vector2(4.6, 19) * u, o + Vector2(19.4, 19) * u, g, w * 0.9)
		"mountain":  # fjords, peaks, the high country
			var mt := PackedVector2Array([o + Vector2(3, 19) * u, o + Vector2(10, 7) * u, o + Vector2(13.5, 13) * u, o + Vector2(16, 9) * u, o + Vector2(21, 19) * u])
			draw_colored_polygon(mt, soft)
			draw_polyline(mt + PackedVector2Array([mt[0]]), g, w * 0.75, true)
			draw_polyline(PackedVector2Array([o + Vector2(8, 11.5) * u, o + Vector2(10, 7) * u, o + Vector2(12, 10.5) * u]), Color(g, 0.6), w * 0.5)
		"ship":  # sails, salt, the age of sail / the void frontier
			draw_arc(o + Vector2(12, 16) * u, 8 * u, 0.15 * PI, 0.85 * PI, 18, g, w)  # hull
			draw_line(o + Vector2(12, 4) * u, o + Vector2(12, 16) * u, g, w * 0.8)  # mast
			var sail := PackedVector2Array([o + Vector2(12, 5) * u, o + Vector2(18, 13) * u, o + Vector2(12, 13) * u])
			draw_colored_polygon(sail, soft)
			draw_polyline(sail + PackedVector2Array([sail[0]]), g, w * 0.6, true)
		"globe":  # a world — the World Forge
			draw_arc(o + Vector2(12, 12) * u, 8.5 * u, 0, TAU, 40, g, w)
			draw_line(o + Vector2(3.5, 12) * u, o + Vector2(20.5, 12) * u, Color(g, 0.7), w * 0.55)
			for ry in [7.0, 12.0, 17.0]:
				var rr: float = 8.5 * u * sin(acos(clampf((ry - 12.0) / 8.5, -1.0, 1.0)))
				draw_arc(o + Vector2(12, ry) * u, maxf(0.5, rr / u) * u, 0, TAU, 24, Color(g, 0.35), w * 0.4)
			draw_arc(o + Vector2(12, 12) * u, 3.6 * u, -PI, 0, 16, Color(g, 0.55), w * 0.5)
			draw_arc(o + Vector2(12, 12) * u, 3.6 * u, 0, PI, 16, Color(g, 0.55), w * 0.5)
		"tune":  # the GM's tone — a mixer of sliders
			var knobs := [15.0, 9.0, 17.0]
			for i in 3:
				var yy: float = 7.0 + i * 5.0
				draw_line(o + Vector2(4, yy) * u, o + Vector2(20, yy) * u, Color(g, 0.5), w * 0.6)
				draw_circle(o + Vector2(knobs[i], yy) * u, 1.9 * u, soft)
				draw_arc(o + Vector2(knobs[i], yy) * u, 1.9 * u, 0, TAU, 16, g, w * 0.6)
		"save":  # mark this chapter — a bookmark ribbon
			var bm := PackedVector2Array([o + Vector2(7, 3.5) * u, o + Vector2(17, 3.5) * u,
				o + Vector2(17, 20.5) * u, o + Vector2(12, 16) * u, o + Vector2(7, 20.5) * u])
			draw_colored_polygon(bm, soft)
			draw_polyline(bm + PackedVector2Array([bm[0]]), g, w * 0.8, true)
		"bolt":  # a reaction — the lightning stroke
			var bz := PackedVector2Array([o + Vector2(13, 3) * u, o + Vector2(7, 13) * u,
				o + Vector2(11, 13) * u, o + Vector2(10, 21) * u, o + Vector2(17, 10) * u, o + Vector2(13, 10) * u])
			draw_colored_polygon(bz, soft)
			draw_polyline(bz + PackedVector2Array([bz[0]]), g, w * 0.7, true)
		"boot":  # movement on the board — a marching boot
			var bt := PackedVector2Array([o + Vector2(7, 3) * u, o + Vector2(11, 3) * u,
				o + Vector2(11.5, 13) * u, o + Vector2(19, 15) * u, o + Vector2(19, 19) * u,
				o + Vector2(7, 19) * u])
			draw_colored_polygon(bt, soft)
			draw_polyline(bt + PackedVector2Array([bt[0]]), g, w * 0.7, true)
			draw_line(o + Vector2(7, 19) * u, o + Vector2(19, 19) * u, g, w * 0.9)
		"blood":  # a wound — the falling drop
			var dp := PackedVector2Array([o + Vector2(12, 3.5) * u, o + Vector2(18, 14) * u,
				o + Vector2(12, 20.5) * u, o + Vector2(6, 14) * u])
			draw_colored_polygon(dp, soft)
			draw_polyline(dp + PackedVector2Array([dp[0]]), g, w * 0.75, true)
			draw_arc(o + Vector2(10, 14) * u, 2.2 * u, PI * 0.4, PI * 0.9, 10, Color(g, 0.6), w * 0.5)
		"hourglass":  # time passing — the glass runs
			draw_line(o + Vector2(5, 4) * u, o + Vector2(19, 4) * u, g, w * 0.9)
			draw_line(o + Vector2(5, 20) * u, o + Vector2(19, 20) * u, g, w * 0.9)
			var top := PackedVector2Array([o + Vector2(6, 4) * u, o + Vector2(18, 4) * u, o + Vector2(12, 12) * u])
			var bot := PackedVector2Array([o + Vector2(12, 12) * u, o + Vector2(18, 20) * u, o + Vector2(6, 20) * u])
			draw_polyline(top + PackedVector2Array([top[0]]), g, w * 0.7, true)
			draw_polyline(bot + PackedVector2Array([bot[0]]), g, w * 0.7, true)
			draw_colored_polygon(PackedVector2Array([o + Vector2(9, 20) * u, o + Vector2(15, 20) * u, o + Vector2(12, 15) * u]), soft)
		"medal":  # a parry mastered — the ribboned medal
			draw_line(o + Vector2(9, 3.5) * u, o + Vector2(11.5, 11) * u, soft, w * 1.1)
			draw_line(o + Vector2(15, 3.5) * u, o + Vector2(12.5, 11) * u, soft, w * 1.1)
			draw_circle(o + Vector2(12, 15) * u, 5.2 * u, soft)
			draw_arc(o + Vector2(12, 15) * u, 5.2 * u, 0, TAU, 24, g, w * 0.75)
			draw_circle(o + Vector2(12, 15) * u, 1.4 * u, g)
		"swirl":  # uncanny dodge — a spiral of motion
			var sp := PackedVector2Array()
			for k in 22:
				var t: float = k / 21.0
				var ang: float = t * TAU * 1.4
				var rad: float = (1.5 + t * 8.0) * u
				sp.append(o + Vector2(12, 12) * u + Vector2(cos(ang), sin(ang)) * rad)
			draw_polyline(sp, g, w * 0.7)
		"mug":  # a tavern — the frothing tankard
			var mg := Rect2(o + Vector2(6, 7) * u, Vector2(9, 12) * u)
			draw_rect(mg, soft)
			draw_rect(mg, g, false, w * 0.75)
			draw_arc(o + Vector2(15, 12) * u, 3 * u, -PI * 0.5, PI * 0.5, 14, g, w * 0.75)  # handle
			draw_arc(o + Vector2(8, 7) * u, 1.6 * u, PI, TAU, 10, g, w * 0.6)  # foam
			draw_arc(o + Vector2(11.5, 7) * u, 1.6 * u, PI, TAU, 10, g, w * 0.6)
		"pillar":  # a landmark — the standing column
			draw_rect(Rect2(o + Vector2(6, 4) * u, Vector2(12, 2.5) * u), soft)  # capital
			draw_rect(Rect2(o + Vector2(6, 18) * u, Vector2(12, 2.5) * u), soft)  # base
			for cx2 in [8.5, 12.0, 15.5]:
				draw_line(o + Vector2(cx2, 6.5) * u, o + Vector2(cx2, 18) * u, g, w * 0.8)
			draw_rect(Rect2(o + Vector2(6, 4) * u, Vector2(12, 2.5) * u), g, false, w * 0.6)
			draw_rect(Rect2(o + Vector2(6, 18) * u, Vector2(12, 2.5) * u), g, false, w * 0.6)
		"tree":  # the wilds — a broadleaf tree
			draw_line(o + Vector2(12, 12) * u, o + Vector2(12, 20) * u, g, w * 0.9)
			var crown2 := PackedVector2Array([o + Vector2(12, 3) * u, o + Vector2(19, 10) * u,
				o + Vector2(15, 10) * u, o + Vector2(18, 15) * u, o + Vector2(6, 15) * u,
				o + Vector2(9, 10) * u, o + Vector2(5, 10) * u])
			draw_colored_polygon(crown2, soft)
			draw_polyline(crown2 + PackedVector2Array([crown2[0]]), g, w * 0.7, true)
		"house":  # home — the hearth and roof
			var roof := PackedVector2Array([o + Vector2(4, 11) * u, o + Vector2(12, 4) * u, o + Vector2(20, 11) * u])
			draw_colored_polygon(roof, soft)
			draw_polyline(roof + PackedVector2Array([roof[0]]), g, w * 0.75, true)
			draw_rect(Rect2(o + Vector2(7, 11) * u, Vector2(10, 9) * u), g, false, w * 0.7)
			draw_rect(Rect2(o + Vector2(10.5, 14.5) * u, Vector2(3, 5.5) * u), soft)  # door
		"pin":  # a place on the map — the dropped marker
			var pn := PackedVector2Array([o + Vector2(12, 20.5) * u, o + Vector2(6, 10) * u,
				o + Vector2(12, 3.5) * u, o + Vector2(18, 10) * u])
			draw_colored_polygon(pn, soft)
			draw_polyline(pn + PackedVector2Array([pn[0]]), g, w * 0.75, true)
			draw_circle(o + Vector2(12, 9.5) * u, 2.1 * u, Color(g, 0.0))
			draw_arc(o + Vector2(12, 9.5) * u, 2.1 * u, 0, TAU, 16, g, w * 0.6)
		"sigil":  # the framed rune — a meaningful placeholder, never an emoji
			var dia := PackedVector2Array([o + Vector2(12, 4) * u, o + Vector2(20, 12) * u, o + Vector2(12, 20) * u, o + Vector2(4, 12) * u])
			draw_polyline(dia + PackedVector2Array([dia[0]]), g, w * 0.8, true)
			draw_arc(o + Vector2(12, 12) * u, 3.4 * u, 0, TAU, 20, Color(g, 0.6), w * 0.6)
			draw_circle(o + Vector2(12, 12) * u, 1.1 * u, g)
		_:
			draw_arc(o + Vector2(12, 12) * u, 8 * u, 0, TAU, 32, g, w)

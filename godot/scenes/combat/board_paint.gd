extends RefCounted
## Composes the battlefield into ONE image, once per fight.
##
## Three problems, one pass:
##
## 1. **Hard edges.** Every baked tile is a centre fill — the library has no
##    transition tiles, so a patch of undergrowth was a green rectangle pasted
##    onto the dirt. Fixed with **dual-grid** blending: a display grid offset
##    half a cell, so each display quad straddles the corners of four logical
##    cells and feathers between whatever roles those corners hold.
##
##    The literature reaches for a 47-tile blob set, or 5 hand-authored mask
##    shapes plus rotations. Neither is needed: bilinear-interpolating the four
##    corner bits and smoothstepping the result *is* a smooth marching-squares,
##    and it generates all sixteen cases from arithmetic. No mask art at all.
##
## 2. **Object tiles carry an opaque background.** They were prompted onto "a
##    plain flat dark grey background", so a boulder arrived as a grey square
##    sitting on the brown dirt. The flat background is keyed out here and the
##    object is stamped over the ground that belongs in that square.
##
## 3. **A field of one material checkerboarded**, because the four variants of a
##    role differ in overall brightness. Each tile is levelled toward its role's
##    mean before it is placed. Non-destructive: the PNGs on disk are untouched.
##
## CPU work, once, at lay time — a fight lasts minutes and the field never moves.

const CELL_PX := 96                       # composite resolution per grid square
const KEY_TOLERANCE := 0.13               # how close to the corner colour reads as background

## What feathers over what. Higher rank is drawn later, so it laps onto its
## neighbour rather than the other way round: loose material creeps over firm,
## and water is lowest because it is a hole, not a covering.
const BLEND_RANK := {
	"deep_water": 0, "shallows": 1, "bog": 2, "mud": 3, "shore_edge": 4,
	"sand": 5, "scree": 6, "rubble": 6, "dirt": 7,
	"cobble": 8, "stone_floor": 8, "wood_floor": 8, "bridge": 8, "stairs": 8,
	"ice": 9, "snow": 10, "snowdrift": 11,
	"leaf_litter": 12, "grass": 13, "grass_wild": 14, "reeds": 15,
	"undergrowth": 16, "thicket": 17,
}

## Roles that are a THING in the square, not the square's material. These are
## keyed and stamped rather than blended.
const OBJECTS := ["boulder", "outcrop", "wreck", "crates", "pillar", "statue",
	"table", "brazier", "firepit", "debris", "chasm"]

static var _masks := {}    # bits -> Image (white, alpha = coverage)
static var _tiles := {}    # "role|v" -> Image, levelled and (if object) keyed
static var _levels := {}   # role -> target mean luminance


## Coverage mask for one display quad. `bits` packs the four logical corners
## that quad straddles: 1=TL 2=TR 4=BL 8=BR, set where the corner holds the role
## being drawn. Bilinear between the corners, then smoothstep — which turns the
## linear ramp into a soft but decisive edge instead of a gradient wash.
## `wobble` picks one of JITTER perturbations. Without it a straight logical
## boundary gives every quad along it the same bits and therefore the same mask,
## and the coast comes out as an evenly repeating scallop — obviously drawn
## rather than natural. A little position-keyed variation breaks the period.
const JITTER := 4

static func _mask(bits: int, wobble: int) -> Image:
	var ck := bits * 100 + wobble
	if _masks.has(ck):
		return _masks[ck]
	var img := Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	var tl := 1.0 if (bits & 1) else 0.0
	var tr := 1.0 if (bits & 2) else 0.0
	var bl := 1.0 if (bits & 4) else 0.0
	var br := 1.0 if (bits & 8) else 0.0
	var ph := float(wobble) * 1.7
	for y in CELL_PX:
		var v := float(y) / float(CELL_PX - 1)
		for x in CELL_PX:
			var u := float(x) / float(CELL_PX - 1)
			var top: float = lerpf(tl, tr, u)
			var bot: float = lerpf(bl, br, u)
			var f: float = lerpf(top, bot, v)
			# Two frequencies, not one: a single sine leaves an obvious period
			# along any straight boundary, which is what made the first coast
			# look stamped. The second, faster term roughens it.
			f += 0.13 * sin(u * TAU * 1.6 + ph) * cos(v * TAU * 1.3 + ph * 0.7)
			f += 0.06 * sin(u * TAU * 3.7 + ph * 2.3) * sin(v * TAU * 3.1 + ph)
			# A narrow band: 0.32..0.68 let the neighbour bulge half a cell over
			# the seam, which reads as a tide rather than a boundary.
			var a: float = smoothstep(0.44, 0.60, f)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_masks[ck] = img
	return img


static func _mean_luma(img: Image) -> float:
	var total := 0.0
	var n := 0
	var step: int = maxi(1, img.get_width() / 24)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var p := img.get_pixelv(Vector2i(x, y))
			if p.a > 0.5:
				total += p.get_luminance()
				n += 1
	return total / float(n) if n > 0 else 0.5


## Lift the flat studio background off an object tile so the ground shows round
## it. The corner pixel IS the background by construction — the prompt asked for
## a plain flat field — so anything within tolerance of it goes transparent.
static func _key_background(img: Image) -> void:
	# Average the four corners. A single pixel picks up whatever grain happens to
	# sit there, which left a dark halo round one boulder where the true
	# background was a shade off that one sample.
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	var bg := Color(0, 0, 0)
	for c in [Vector2i(1, 1), Vector2i(w - 1, 1), Vector2i(1, h - 1), Vector2i(w - 1, h - 1)]:
		bg += img.get_pixelv(c)
	bg /= 4.0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixelv(Vector2i(x, y))
			var d := absf(p.r - bg.r) + absf(p.g - bg.g) + absf(p.b - bg.b)
			if d < KEY_TOLERANCE * 3.0:
				img.set_pixelv(Vector2i(x, y), Color(p.r, p.g, p.b, 0.0))
			elif d < KEY_TOLERANCE * 5.0:
				# Feather the rim so the object does not have a cut-out edge.
				var t: float = (d - KEY_TOLERANCE * 3.0) / (KEY_TOLERANCE * 2.0)
				img.set_pixelv(Vector2i(x, y), Color(p.r, p.g, p.b, p.a * t))


## One tile, at composite resolution, levelled toward its role's mean — and for
## an object, with its background keyed away.
static func _tile(world: String, role: String, v: int) -> Image:
	var ck := "%s|%s|%d" % [world, role, v]
	if _tiles.has(ck):
		return _tiles[ck]
	var tex: Texture2D = Compiler.tile_art(world, role, v)
	if tex == null:
		tex = Compiler.tile_art(world, role, 1)
	if tex == null:
		tex = Art.texture_for("tile-%s-%s-%d" % [role, world, v])
	if tex == null:
		_tiles[ck] = null
		return null
	var img := tex.get_image()
	if img == null:
		_tiles[ck] = null
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CELL_PX, CELL_PX, Image.INTERPOLATE_LANCZOS)
	if role in OBJECTS:
		_key_background(img)
	# Level toward the role's mean so four variants of one material stop reading
	# as a checkerboard of light and dark squares.
	var mine := _mean_luma(img)
	if not _levels.has(role):
		_levels[role] = mine
	var want: float = _levels[role]
	if mine > 0.01 and absf(want - mine) > 0.01:
		var k: float = clampf(want / mine, 0.72, 1.38)
		for y in CELL_PX:
			for x in CELL_PX:
				var p := img.get_pixelv(Vector2i(x, y))
				img.set_pixelv(Vector2i(x, y), Color(
					minf(p.r * k, 1.0), minf(p.g * k, 1.0), minf(p.b * k, 1.0), p.a))
	_tiles[ck] = img
	return img


static func variant_of(role: String, x: int, y: int, count: int) -> int:
	return 1 + (absi(hash("%s%d,%d" % [role, x, y])) % count)


## Paint the whole field. Returns null if no tile art resolves at all, so the
## caller can fall back to flat role tints.
static func compose(world: String, cells: Dictionary, cols: int, rows: int, variants: int) -> ImageTexture:
	var w := cols * CELL_PX
	var h := rows * CELL_PX
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var any := false
	var role_at := func(x: int, y: int) -> String:
		return str(cells.get("%d,%d" % [x, y], ""))

	# Base pass: every square wears its own material. Worst case — no blending
	# resolves — this alone is what the board looked like before.
	for x in cols:
		for y in rows:
			var role: String = role_at.call(x, y)
			var ground := role if not (role in OBJECTS) else _ground_under(cells, x, y, cols, rows)
			var img := _tile(world, ground, variant_of(ground, x, y, variants))
			if img == null:
				continue
			any = true
			out.blit_rect(img, Rect2i(0, 0, CELL_PX, CELL_PX), Vector2i(x * CELL_PX, y * CELL_PX))
	if not any:
		return null

	# Dual-grid pass. Each display quad sits half a cell up and left, straddling
	# the corners of four logical cells; where they disagree, the higher-ranked
	# material feathers across the seam.
	for dx in range(cols + 1):
		for dy in range(rows + 1):
			var corners := [
				role_at.call(dx - 1, dy - 1), role_at.call(dx, dy - 1),
				role_at.call(dx - 1, dy), role_at.call(dx, dy)]
			var mats: Array = []
			for r in corners:
				var m: String = r if not (r in OBJECTS) else ""
				if m != "" and not mats.has(m):
					mats.append(m)
			if mats.size() < 2:
				continue
			mats.sort_custom(func(a, b): return int(BLEND_RANK.get(a, 7)) < int(BLEND_RANK.get(b, 7)))
			var at := Vector2i(dx * CELL_PX - CELL_PX / 2, dy * CELL_PX - CELL_PX / 2)
			for mi in range(1, mats.size()):          # the lowest rank is already the base
				var mat: String = mats[mi]
				var bits := 0
				for ci in 4:
					if str(corners[ci]) == mat:
						bits |= 1 << ci
				if bits == 0 or bits == 15:
					continue
				var timg := _tile(world, mat, variant_of(mat, dx, dy, variants))
				if timg == null:
					continue
				var wob: int = absi(hash("%d,%d,%s" % [dx, dy, mat])) % JITTER
				_stamp_masked(out, timg, _mask(bits, wob), at, w, h)

	# Objects last, keyed, over the ground that belongs in their square.
	for x in cols:
		for y in rows:
			var role: String = role_at.call(x, y)
			if not (role in OBJECTS):
				continue
			var img := _tile(world, role, variant_of(role, x, y, variants))
			if img == null:
				continue
			out.blend_rect(img, Rect2i(0, 0, CELL_PX, CELL_PX), Vector2i(x * CELL_PX, y * CELL_PX))
	return ImageTexture.create_from_image(out)


## The material a square would wear if the object standing on it were lifted —
## so a boulder sits on the dirt around it rather than on a hole.
static func _ground_under(cells: Dictionary, x: int, y: int, cols: int, rows: int) -> String:
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var nx: int = x + d[0]
		var ny: int = y + d[1]
		if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
			continue
		var r := str(cells.get("%d,%d" % [nx, ny], ""))
		if r != "" and not (r in OBJECTS):
			return r
	return "dirt"


## blend_rect_mask cannot straddle the edge of the destination, and half the
## display quads do exactly that, so clip both rects to the overlap first.
static func _stamp_masked(out: Image, src: Image, mask: Image, at: Vector2i, w: int, h: int) -> void:
	var sx: int = maxi(0, -at.x)
	var sy: int = maxi(0, -at.y)
	var dw: int = mini(CELL_PX - sx, w - maxi(at.x, 0))
	var dh: int = mini(CELL_PX - sy, h - maxi(at.y, 0))
	if dw <= 0 or dh <= 0:
		return
	out.blend_rect_mask(src, mask, Rect2i(sx, sy, dw, dh), Vector2i(maxi(at.x, 0), maxi(at.y, 0)))

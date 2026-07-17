extends Node
## Art — every generated image the game wears: world key art, hero and NPC
## portraits, item icons, battle-map underlays, parchment world maps. All
## painted once through the ComfyUI bridge, cached in user://art/<key>.png.
## Keys: "<world_id>" · "hero-<cid>" · "npc-<slug>" · "item-<slug>" ·
## "map-<place-slug>" · "chart-<world_id>".

signal art_ready(key: String)

const WORLD_PROMPTS := {
	"embervale": "a candlelit fantasy valley village at dusk, timber inn glowing warm, misty hills, cinematic high fantasy establishing shot, no people, no text",
	"neonspire": "a rain-slick cyberpunk megacity street at night, neon cyan and magenta signs, towering spire, cinematic sci-fi establishing shot, no people, no text",
	"everyday": "a cozy corner cafe on a quiet city street at golden hour, warm window light, bicycles, slice of life illustration, no people, no text",
}

var _generating := {}
var _round_cache := {}   # key -> circular-masked ImageTexture
var _tex_cache := {}     # key -> ImageTexture (avoid re-reading disk every frame)
var _queue: Array = []   # [{key, prompt, size}] — one generation at a time
var _pumping := false


func path_for(key: String) -> String:
	return "user://art/%s.png" % key.validate_filename()


func has_art(key: String) -> bool:
	return key != "" and FileAccess.file_exists(path_for(key))


func texture_for(key: String) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	if not has_art(key):
		return null
	var img := Image.load_from_file(path_for(key))
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## A circular-alpha version (tokens, avatars). Cached in memory.
func round_tex(key: String, size := 128) -> ImageTexture:
	if _round_cache.has(key):
		return _round_cache[key]
	if not has_art(key):
		return null
	var img := Image.load_from_file(path_for(key))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	# Center-crop square, resize, punch a circle.
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			if d > r - 1.0:
				var px := img.get_pixel(x, y)
				px.a = clampf(r - d, 0.0, 1.0) * px.a
				img.set_pixel(x, y, px)
	var tex := ImageTexture.create_from_image(img)
	_round_cache[key] = tex
	return tex


## Generate + cache if missing. Queued — one image in flight, ever; the GPU
## also serves the storyteller. Emits art_ready(key) when a painting lands.
func ensure(key: String, prompt := "", size := "1024x1024") -> void:
	if key == "" or has_art(key) or _generating.get(key, false):
		return
	if prompt == "":
		prompt = WORLD_PROMPTS.get(key, "")
	if prompt == "":
		return
	_generating[key] = true
	_queue.append({"key": key, "prompt": prompt, "size": size})
	if not _pumping:
		_pump()


func _pump() -> void:
	_pumping = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate",
			{"prompt": str(job["prompt"]), "size": str(job["size"])})
		_generating[job["key"]] = false
		if r.get("_status", 0) != 200 or str(r.get("image_url", "")) == "":
			continue
		var bytes := await Api.fetch_bytes(str(r["image_url"]).trim_prefix(Api.BASE))
		if bytes.is_empty():
			continue
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
			continue
		DirAccess.make_dir_recursive_absolute("user://art")
		img.save_png(path_for(str(job["key"])))
		_tex_cache.erase(str(job["key"]))
		_round_cache.erase(str(job["key"]))
		art_ready.emit(str(job["key"]))
	_pumping = false


# ── Prompt builders: one voice for each art family ──────────────────────────
func world_flavor() -> String:
	return {"neonspire": "cyberpunk sci-fi", "everyday": "warm contemporary slice-of-life"}.get(GameState.world_id(), "high fantasy")


## Un-cache a painting so it can be re-struck (forge re-strike, style change).
func forget(key: String) -> void:
	_tex_cache.erase(key)
	_round_cache.erase(key)
	_generating.erase(key)
	if has_art(key):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(key)))


func ensure_hero_portrait(cid: String, sheet: Dictionary, extra := "") -> void:
	ensure("hero-" + cid.validate_filename(),
		"character portrait of %s, a %s %s, %s%s style, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face, no text" % [
			str(sheet.get("name", "a hero")), str(sheet.get("race", "")), str(sheet.get("cls", "adventurer")),
			(extra + ", ") if extra != "" else "", world_flavor()])


func ensure_item_icon(nm: String) -> void:
	ensure("item-" + nm.to_lower().replace(" ", "-"),
		"game inventory icon of a %s, %s style, single item centered on a plain dark background, painted RPG item icon, no text, no hands" % [nm, world_flavor()], "1024x1024")


func item_tex(nm: String) -> ImageTexture:
	return texture_for("item-" + nm.to_lower().replace(" ", "-"))


## The face a combatant wears everywhere (board token, initiative rail):
## hero portrait / companion npc portrait / bestiary painting (commissioned
## from the entry's art prompt on first sight).
func combatant_tex(m: Dictionary) -> ImageTexture:
	var id := str(m.get("id", ""))
	if id == "pc":
		return round_tex("hero-" + GameState.cid().validate_filename())
	if id.begins_with("cmp"):
		return round_tex("npc-" + str(m.get("name", "")).to_lower().replace(" ", "-"))
	var entry := Combat.bestiary_for(str(m.get("name", "")))
	if not entry.is_empty():
		var key := "beast-" + str(entry.get("slug", ""))
		if has_art(key):
			return round_tex(key)
		ensure(key, str(entry.get("art", "")) + ", painted creature portrait, dark background, no text")
	return null


func ensure_battle_map(place: String) -> String:
	var key := "map-" + place.to_lower().replace(" ", "-").validate_filename()
	ensure(key, "top-down tabletop RPG battle map of %s, %s style, overhead view, painted terrain, no grid lines, no tokens, no text, muted lighting" % [place, world_flavor()])
	return key


func ensure_world_chart(world_id2: String, world_name: String) -> String:
	var key := "chart-" + world_id2.validate_filename()
	ensure(key, "hand-drawn parchment world map of %s, %s style, aged paper, inked coastlines and roads, cartography illustration, no modern text labels" % [world_name, world_flavor()])
	return key

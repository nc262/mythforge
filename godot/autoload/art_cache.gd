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

## EAS environments — the illustrated rooms the interface stands inside.
## One shared set today; per-world variants are a matrix row.
const ENV_PROMPTS := {
	"env-wartable": "a dungeon master's war room from a seated player's view: a massive candlelit oak war table covered with a huge parchment campaign map, miniature armies, brass compass, quills, ink pots, dripping wax seals, open books, scattered dice, old letters, a sheathed sword leaning on the table, a storm through leaded windows behind, dust floating in warm candlelight, volumetric light, ultra detailed fantasy interior illustration, no people, no text",
	"env-forge": "inside an ancient mythic forge: molten metal glowing in stone channels, a great anvil at center, faint glowing runes floating in the air, chains and ancient statues in shadow, weapons displayed on stone walls like museum pieces, sparks rising, volumetric orange light against deep blue darkness, ultra detailed fantasy interior illustration, no people, no text",
	"env-pack": "an opened leather adventurer's travel pack laid on a wooden camp table, worn leather folds and loosened brass buckles, canvas stretched open, small potion bottles, coiled rope, scattered gold coins, a folded map, warm lantern light, ultra detailed fantasy still life illustration, slightly top-down view, no people, no text",
	"env-merchant": "a fantasy merchant's stall interior: worn wood shelves and crates, hanging lanterns, a brass coin scale, folded rich fabrics, displayed weapons and curios, coin stacks, warm lamplight and deep shadow, ultra detailed fantasy interior illustration, no people, no text",
	"env-journal": "a large open leather-bound journal on a candlelit desk, aged parchment pages with handwritten margins and small ink illustrations, ribbon bookmarks, red wax seals, an ink pot and quill beside it, warm candlelight, ultra detailed fantasy still life illustration, slightly top-down view, no people, no text",
	"env-maptable": "an ancient cartographer's table seen from above: dark oak surface, brass compass and dividers, red wax route markers, pinned notes, a magnifying lens, a guttering candle at the corner, ultra detailed fantasy still life illustration, no people, no text",
	"env-fireside": "a warm fireside corner of a tavern at night: two chairs across a small wooden table, crackling fireplace, candlelight, shelves of books and portraits on the wall, rich shadow and amber light, ultra detailed fantasy interior illustration, no people, no text",
}

## The opening cinematic's four genre panoramas (menu boot sequence).
const CINE_PROMPTS := {
	"cine-fantasy": "a dragon flying over misty mountains, ancient castles, deep forests and ruined towers at dawn, epic fantasy panorama, cinematic wide establishing shot, volumetric light, ultra detailed digital painting, no text",
	"cine-neonspire": "a glowing holographic dragon projection soaring between neon skyscrapers of a rain-slick cyberpunk megacity at night, cyan and magenta light, cinematic wide establishing shot, ultra detailed digital painting, no text",
	"cine-everyday": "a peaceful suburban street at golden sunset, warm glowing homes, big trees, bicycles on the sidewalk, quiet empty street, cinematic wide establishing shot, ultra detailed digital painting, no text",
	"cine-space": "a deep space vista with glowing nebulae, a vast orbital station and distant cruisers, far shimmering civilizations, cinematic wide establishing shot, ultra detailed digital painting, no text",
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
	# The active World Skin's art style — every generated image inherits the
	# campaign's visual language, not a hardcoded fantasy default (M-B).
	return str(WorldSkin.skin_for_id(GameState.world_id()).get("flavor", {}).get("world", "high fantasy"))


## Role templates for non-fantasy skins: a room by what it's FOR, flavoured by
## the World Skin's setting, so a cyberpunk campaign gets a cyber war room, not
## a fantasy one (per-world EAS variants — the World Style Guide driving
## environment generation). Fantasy keeps its richly-authored ENV_PROMPTS.
const ENV_ROLE := {
	"env-wartable": "a %s campaign war room seen from a seated player's view: a great table spread with a huge map, markers, plans, and the tools of command, dramatic focused light, dust in the air, ultra detailed interior illustration, no people, no text",
	"env-forge": "a %s place of making where heroes are equipped and created: the tools and energy of creation glowing against deep shadow, sparks of light, ultra detailed interior illustration, no people, no text",
	"env-pack": "an opened %s traveler's kit laid out on a surface: pouches, gear, and belongings, warm focused light, ultra detailed still life, slightly top-down view, no people, no text",
	"env-merchant": "a %s merchant's stall interior: wares, curios, and coin on worn shelves, warm lamplight and deep shadow, ultra detailed interior illustration, no people, no text",
	"env-journal": "a %s archive where the world's lore is kept and read: an open record on a desk under focused warm light, ultra detailed still life, slightly top-down view, no people, no text",
	"env-maptable": "a %s cartographer's table seen from above: a chart with route markers and instruments, a light at one corner, ultra detailed still life, no people, no text",
	"env-fireside": "a warm %s gathering corner: two seats across a small table, a source of warmth and light, rich shadow, ultra detailed interior illustration, no people, no text",
}


## The active skin's family scopes the cache key so each world keeps its own
## rooms; fantasy reuses the base key (and its authored art).
func env_resolved(base_key: String) -> String:
	var fam := WorldSkin.family_for_id(GameState.world_id())
	return base_key if fam == "fantasy" else "%s-%s" % [base_key, fam]


func env_prompt(base_key: String) -> String:
	var fam := WorldSkin.family_for_id(GameState.world_id())
	if fam == "fantasy" or not ENV_ROLE.has(base_key):
		return str(ENV_PROMPTS.get(base_key, ""))
	var setting := str(WorldSkin.skin(fam).get("flavor", {}).get("world", "high fantasy"))
	return ENV_ROLE[base_key] % setting


## Commission one of the EAS environments (queued like all art), skin-scoped.
func ensure_environment(base_key: String) -> void:
	ensure(env_resolved(base_key), env_prompt(base_key), "1344x768")


## Duplicate a painting under a new key (e.g. the approved forge-preview
## portrait becomes the played hero's face, so the face never re-rolls).
func copy(from_key: String, to_key: String) -> bool:
	if to_key == "" or not has_art(from_key):
		return false
	var img := Image.load_from_file(path_for(from_key))
	if img == null or img.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute("user://art")
	img.save_png(path_for(to_key))
	_tex_cache.erase(to_key)
	_round_cache.erase(to_key)
	return true


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

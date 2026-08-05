extends Node
## Art — every generated image the game wears: world key art, hero and NPC
## portraits, item icons, battle-map underlays, parchment world maps. All
## painted once by the local image engine, cached in user://art/<key>.png.
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

## A2 — the generative-art pipeline: a manifest (key → {size, used}) drives LRU
## eviction so the cache stops growing forever; a per-asset .json sidecar records
## how it was made (prompt/size/seed/model/…) so anything can be regenerated.
const CACHE_BUDGET := 700 * 1024 * 1024   # ~700 MB of paintings before eviction
var _manifest := {}
var _manifest_loaded := false


## Terrain tiles are a shipped asset library, not per-playthrough art, so they
## live outside the LRU entirely.
##
## RCA (R10): the tile pour queued 753 tiles at ~1.6 MB each — ~1.3 GB against a
## 700 MB budget. Every finished tile evicted an older one, so the pour ran for
## hours at 17 s/tile with net zero growth and could never finish. Before it
## reached that equilibrium it had evicted *every other painting in the game*:
## hero portraits, battle maps, item art, all of it. LRU is right for art a
## playthrough accumulates; it is wrong for a fixed library that must all be
## present at once.
## Tiles are stored at whatever the model produced (1024). Downsampling them to
## "just enough for a grid cell" was a false economy: it saves ~1.2 GB on a
## machine where disk is the cheapest thing in the stack, and it is a one-way
## door — the detail cannot come back without another GPU pour. Keep the pixels.
const TILE_DIR := "user://tiles"


func _is_tile(key: String) -> bool:
	return key.begins_with("tile-")


func _dir_for(key: String) -> String:
	return TILE_DIR if _is_tile(key) else "user://art"


func path_for(key: String) -> String:
	return "%s/%s.png" % [_dir_for(key), key.validate_filename()]


func _meta_path(key: String) -> String:
	return "%s/%s.json" % [_dir_for(key), key.validate_filename()]


func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	if FileAccess.file_exists("user://art/manifest.json"):
		var p = JSON.parse_string(FileAccess.get_file_as_string("user://art/manifest.json"))
		if p is Dictionary:
			_manifest = p
	# Bring any art already on disk (pre-manifest) under management — oldest first.
	var d := DirAccess.open("user://art")
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".png"):
				var k := fn.trim_suffix(".png")
				if not _manifest.has(k):
					_manifest[k] = {"size": _file_size(path_for(k)), "used": 0.0}


func _save_manifest() -> void:
	DirAccess.make_dir_recursive_absolute("user://art")
	var f := FileAccess.open("user://art/manifest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_manifest))
		f.close()


func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var n := int(f.get_length())
	f.close()
	return n


## Record a freshly-generated asset in the manifest, then enforce the budget.
func _note_asset(key: String) -> void:
	if _is_tile(key):
		return   # library asset — never evicted, never counted against the budget
	_load_manifest()
	_manifest[key] = {"size": _file_size(path_for(key)), "used": Time.get_unix_time_from_system()}
	_save_manifest()
	_enforce_budget()


## Mark an asset recently used, so the LRU keeps what's on screen.
func _touch(key: String) -> void:
	_load_manifest()
	if _manifest.has(key):
		_manifest[key]["used"] = Time.get_unix_time_from_system()


## The regeneration record beside each painting: how it was made.
func _write_sidecar(key: String, job: Dictionary, r: Dictionary) -> void:
	var meta := {
		"prompt": str(job.get("prompt", "")), "size": str(job.get("size", "")),
		"world": GameState.world_id(), "created": Time.get_datetime_string_from_system(),
		"seed": r.get("seed"), "model": r.get("model"), "workflow": r.get("workflow"),
		"negative": r.get("negative_prompt", r.get("negative")),
	}
	var f := FileAccess.open(_meta_path(key), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta))
		f.close()


## Evict least-recently-used paintings until back under budget. Evicted art
## self-heals: the next ensure(key, prompt) simply repaints it.
func _enforce_budget() -> void:
	var total := 0
	for k in _manifest:
		total += int(_manifest[k].get("size", 0))
	if total <= CACHE_BUDGET:
		return
	var keys := _manifest.keys()
	keys.sort_custom(func(a, b): return float(_manifest[a].get("used", 0)) < float(_manifest[b].get("used", 0)))
	for k in keys:
		if total <= CACHE_BUDGET:
			break
		total -= int(_manifest[k].get("size", 0))
		_evict(str(k))
	_save_manifest()


func _evict(key: String) -> void:
	if has_art(key):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(key)))
	if FileAccess.file_exists(_meta_path(key)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_meta_path(key)))
	_tex_cache.erase(key)
	_round_cache.erase(key)
	_manifest.erase(key)


func has_art(key: String) -> bool:
	return key != "" and FileAccess.file_exists(path_for(key))


func texture_for(key: String) -> ImageTexture:
	_touch(key)
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
	_touch(key)
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


# ═══ THE ART DIRECTOR ═══════════════════════════════════════════════════════
# The ONLY gateway to GPU generation (Director's ruling, playtest #1). No screen
# and no gameplay system may POST to /generate — enforced by a harness law.
#
# RCA that made this an engine subsystem rather than a helper: three call sites
# painted directly, two of them bypassing this queue, so a scene repaint ran
# CONCURRENTLY with a queued portrait on one GPU. Concurrent jobs on one engine
# are how the wrong picture lands in the wrong frame — the player saw a
# stranger's photograph in their scene slot. One door, always.
#
# Responsibilities: queueing · prioritization · cancellation · progress
# reporting · caching · callback routing.

## What the player is waiting on, in the order they feel it.
enum Lane {
	NOW = 0,    # they are looking at the empty frame right now
	SOON = 1,   # they will look at it in a moment (next scene, worn gear)
	IDLE = 2,   # backfill — menu key-art, warming the cache
}

## Generation PROFILES (docs/WorldCompiler.md): each content class gets the
## resolution it is actually seen at. That is the whole profile today — sd-server
## runs one checkpoint and cannot switch, and there is no matting step, so a
## `style` or `matte` field here would only record an intention nothing acts on.
const PROFILES := {
	"item":     {"size": "1024x1024"},
	"prop":     {"size": "512x512"},
	"scene":    {"size": "1024x1024"},
	"portrait": {"size": "1024x1024"},
	"showcase": {"size": "1024x1024"},
}
const DEFAULT_PROFILE := "scene"

signal art_progress(key: String, state: String)  # queued · painting · ready · failed · cancelled

var _cancelled := {}     # key → true, honoured before dispatch AND after the paint
var _callbacks := {}     # key → Array[Callable], routed to the requester only
var _owners := {}        # key → Node; if it dies before the paint lands, the job is moot
var _painting := ""      # the key currently on the GPU


## THE entry point. opts: {profile, size, lane, owner (Node), on_ready}.
## `profile` (item/prop/scene/portrait/showcase) picks the checkpoint, size and
## matting; an explicit `size` overrides the profile's. Re-requesting a queued
## key upgrades its lane and adds the callback rather than queueing twice.
func request(key: String, prompt := "", opts := {}) -> void:
	if key == "":
		return
	var cb = opts.get("on_ready")
	if has_art(key):
		if cb is Callable and cb.is_valid():
			cb.call(key)     # already painted — answer immediately, still routed
		return
	if prompt == "":
		prompt = WORLD_PROMPTS.get(key, "")
	if prompt == "":
		return
	if cb is Callable and cb.is_valid():
		var list: Array = _callbacks.get(key, [])
		list.append(cb)
		_callbacks[key] = list
	if opts.get("owner") is Node:
		_owners[key] = opts["owner"]
	_cancelled.erase(key)
	var lane: int = int(opts.get("lane", Lane.SOON))
	if _generating.get(key, false):
		_upgrade_lane(key, lane)   # someone now wants it sooner
		return
	var prof: Dictionary = PROFILES.get(str(opts.get("profile", DEFAULT_PROFILE)), PROFILES[DEFAULT_PROFILE])
	_generating[key] = true
	_queue.append({"key": key, "prompt": prompt, "lane": lane,
		"size": str(opts.get("size", prof["size"]))})
	_sort_queue()
	art_progress.emit(key, "queued")
	if not _pumping:
		_pump()


## Legacy/simple form kept deliberately — most callers just want a key painted.
func ensure(key: String, prompt := "", size := "1024x1024", front := false) -> void:
	request(key, prompt, {"size": size, "lane": Lane.NOW if front else Lane.IDLE})


func _sort_queue() -> void:
	_queue.sort_custom(func(a, b): return int(a.get("lane", Lane.SOON)) < int(b.get("lane", Lane.SOON)))


func _upgrade_lane(key: String, lane: int) -> void:
	for job in _queue:
		if str(job.get("key", "")) == key and lane < int(job.get("lane", Lane.SOON)):
			job["lane"] = lane
			_sort_queue()
			return


## Drop a pending job. The GPU can't be interrupted mid-paint, so a cancelled
## in-flight job still finishes and still CACHES (the work is paid for either
## way) — it just never calls back or announces itself.
func cancel(key: String) -> void:
	if key == "" or has_art(key):
		return
	_cancelled[key] = true
	_callbacks.erase(key)
	_owners.erase(key)
	for i in range(_queue.size() - 1, -1, -1):
		if str(_queue[i].get("key", "")) == key:
			_queue.remove_at(i)
			_generating[key] = false
			art_progress.emit(key, "cancelled")


## Everything a departing screen asked for. Nothing paints into a dead frame.
func cancel_for(owner: Node) -> void:
	for key in _owners.keys():
		if _owners[key] == owner:
			cancel(str(key))


## Honest state for anything that wants to show it: "" · queued · painting · ready
func status(key: String) -> String:
	if has_art(key):
		return "ready"
	if _painting == key:
		return "painting"
	return "queued" if _generating.get(key, false) else ""


## How much work is outstanding — for progress copy ("2 paintings ahead of you").
func pending() -> int:
	return _queue.size() + (1 if _painting != "" else 0)


## While the GM is mid-stream the GPU belongs to the narrator. The narrator and
## the image engine share one card, so `hold` pauses OUR queue for the length of
## a stream — measured: opening the shop enqueued ten icons at ~22–27 s each
## straight across a 53 s turn, and the player waited ~2 minutes for one reply.
##
## Pausing our own queue is the whole mechanism. There is no lever on the other
## side: sd-server has no unload API, and freeing its ~4.9 GB means stopping the
## process, which buys a ~25 s checkpoint reload per story beat — a worse trade
## than the contention it relieves.
var hold := false
const HOLD_MAX := 180.0   # ponytail: safety valve — a stuck flag must never freeze art for good


## Where the pictures come from. stable-diffusion.cpp serves the OpenAI image API
## itself, so this is the whole client.
const IMAGE_SERVER := "http://127.0.0.1:8189"
const IMAGE_PATH := "/v1/images/generations"
const IMAGE_MODEL := "sd-cpp-local"


## One picture, one request. Measured: 8.7 s for 512x512 cold, base64 PNG in the
## response body.
##
## The payload is deliberately thin because the engine is: `steps` and `cfg` are
## launch flags sd-server ignores in the body, and it is started with a single
## .safetensors so it cannot switch checkpoints per style. Matting, regions and
## character-consistency adapters do not exist here. When any of them become
## possible they belong in this payload, as fields.
func _paint(prompt: String, size: String) -> Dictionary:
	# The harnesses drive the real game headless and must not reach a GPU.
	if Api.test_mode:
		return {}
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(IMAGE_SERVER + IMAGE_PATH,
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
		JSON.stringify({"model": IMAGE_MODEL, "prompt": prompt, "n": 1, "size": size}))
	if err != OK:
		req.queue_free()
		return {}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[1] != 200:
		return {}
	var out = JSON.parse_string(res[3].get_string_from_utf8())
	if not (out is Dictionary) or not (out.get("data") is Array) or out["data"].is_empty():
		return {}
	var b64 := str(out["data"][0].get("b64_json", ""))
	if b64 == "":
		return {}
	return {"bytes": Marshalls.base64_to_raw(b64), "prompt": prompt, "size": size,
		"model": IMAGE_MODEL, "workflow": "sd.cpp direct"}


func _pump() -> void:
	_pumping = true
	while not _queue.is_empty():
		var waited := 0.0
		while hold and waited < HOLD_MAX:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		var job: Dictionary = _queue.pop_front()
		var key := str(job["key"])
		if _cancelled.get(key, false):
			_generating[key] = false
			continue
		_painting = key
		art_progress.emit(key, "painting")
		var r := await _paint(str(job["prompt"]), str(job["size"]))
		_painting = ""
		_generating[key] = false
		var bytes: PackedByteArray = r.get("bytes", PackedByteArray())
		if bytes.is_empty():
			_finish(key, false)
			continue
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
			_finish(key, false)
			continue
		DirAccess.make_dir_recursive_absolute(_dir_for(key))
		# Write, then rename. Killed mid-save, a truncated PNG would still satisfy
		# has_art() — and request() answers "already painted" from that check, so
		# the key would never repaint again. Under a temp name it just isn't there.
		var tmp := path_for(key) + ".part"
		if img.save_png(tmp) != OK:
			_finish(key, false)
			continue
		DirAccess.rename_absolute(tmp, path_for(key))
		_write_sidecar(key, job, r)  # A2: how it was made, for regeneration
		_note_asset(key)             # A2: manifest + LRU budget
		_tex_cache.erase(key)
		_round_cache.erase(key)
		_finish(key, true)
	_pumping = false


## Route the result: to the requester's callback first, then the world at large.
## A cancelled or orphaned job stays silent — its picture is cached for later,
## but nothing repaints for a screen that has already gone.
func _finish(key: String, ok: bool) -> void:
	var cbs: Array = _callbacks.get(key, [])
	_callbacks.erase(key)
	var owner = _owners.get(key)
	_owners.erase(key)
	if _cancelled.get(key, false):
		_cancelled.erase(key)
		art_progress.emit(key, "cancelled")
		return
	art_progress.emit(key, "ready" if ok else "failed")
	if not ok:
		return
	if owner != null and not is_instance_valid(owner):
		return                      # the frame it was for is gone
	for cb in cbs:
		if cb is Callable and cb.is_valid():
			cb.call(key)
	art_ready.emit(key)


# ── Prompt builders: one voice for each art family ──────────────────────────
func world_flavor() -> String:
	# A COMPILED world speaks for itself: its Style Guide's prompt_anchor is the
	# single clause appended to every image, and the strongest defence against
	# style drift (docs/WorldCompiler.md §11 R2). An uncompiled world falls back
	# to its deterministic family flavour (M-B).
	var anchor := Compiler.prompt_anchor(GameState.world_id())
	if anchor != "":
		return anchor
	return str(WorldSkin.skin_for_id(GameState.world_id()).get("flavor", {}).get("world", "high fantasy"))


## A subject's world-style phrase (character fashion, creature kind, item
## materials) from the World Style Guide — shapes generated art per world (A1).
func subject_style(kind: String) -> String:
	return str(WorldSkin.style_for_id(GameState.world_id()).get(kind, ""))


## UI-7 — THE WORLD'S FLAVOUR, WITH ITS LIGHTING TAKEN OUT, FOR ITEMS ONLY.
##
## `world_flavor()` carries medium AND atmosphere: embervale's is "high fantasy
## oil painting, candlelit". On a scene that is exactly right. On a 512 px item
## icon the atmosphere stops being lighting and becomes SUBJECT.
##
## Measured, one item, three prompts:
##   with "candlelit"          → a lit candle mounted on a sword hilt
##   with "candlelit" removed  → a blade (silhouette still wrong — see below)
##   plus a shape clause       → a correct short blade
##
## The compiler already knew: `_stage_parts` carries a note that appending the
## scene anchor "turned a sword into a lantern", and it stopped appending it.
## `ensure_item_icon` — the legacy per-name path — never got the same treatment.
##
## The first clause of a flavour is its MEDIUM ("high fantasy oil painting",
## "cyberpunk neon concept render"); what follows is the weather. An item wants
## the medium and nothing else.
func item_flavor() -> String:
	var full := world_flavor()
	var head := full.split(",")[0].strip_edges()
	return head if head != "" else full


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
	_note_asset(to_key)  # the copy is a managed asset too
	return true


## Un-cache a painting so it can be re-struck (forge re-strike, style change).
func forget(key: String) -> void:
	_tex_cache.erase(key)
	_round_cache.erase(key)
	_generating.erase(key)
	_manifest.erase(key)
	if has_art(key):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(key)))
	if FileAccess.file_exists(_meta_path(key)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_meta_path(key)))


## The key the hero's face ACTUALLY lives under.
##
## Six readers used to rebuild `"hero-" + cid` at the point of use. A hero banked
## in one adventure and played in another owns art under the key they were
## painted with, so the rebuilt key names a file that does not exist: the ring
## renders empty and the game re-commissions a portrait it already owns.
## (R8-02 / R8-24 — the same root cause as F-01. Ask the hero, don't guess.)
func hero_key() -> String:
	var stored := str(GameState.sheet().get("portrait_key", ""))
	# `heroprev` is the forge's SHARED scratch key — a hero pinned to it would
	# wear the next-forged hero's face. Never honour it.
	if stored != "" and stored != "heroprev" and has_art(stored):
		return stored
	return "hero-" + GameState.cid().validate_filename()


## THE HERO'S IDENTITY, as a prompt clause — the one answer to "what do they
## look like", asked by every renderer instead of each inventing its own.
##
## There is no seed lock to hold a face still: sd-server ignores `seed` in the
## request body exactly as it ignores `steps` (measured — two different seeds,
## byte-identical output). What it IS is deterministic on the prompt, so the
## prompt is the only identity anchor available, and identity therefore lives or
## dies on every renderer describing the same person.
##
## It did not. The portrait carried the player's appearance words; the paper doll
## carried none at all, so the doll was a different person wearing the same gear.
func hero_look(sheet := {}) -> String:
	var s: Dictionary = sheet if not sheet.is_empty() else GameState.sheet()
	var look := str(s.get("look", "")).strip_edges()
	var brush := str(s.get("brush", "painted")).strip_edges()
	if brush == "":
		brush = "painted"
	return (look + ", " if look != "" else "") + brush + " style"


## The hero's FULL-BODY key. Derived from the face key so a banked hero keeps one
## body as they keep one face — never rebuilt from the current adventure's id.
func hero_body_key() -> String:
	return "herobody-" + hero_key().trim_prefix("hero-")


func ensure_hero_portrait(cid: String, sheet: Dictionary, extra := "") -> void:
	# Already painted under a carried key? Then there is nothing to commission —
	# this is what used to burn a GPU render per adventure for a face we own.
	var stored := str(sheet.get("portrait_key", ""))
	if stored != "" and stored != "heroprev" and has_art(stored):
		return
	# `extra` is the forge handing over the look on the very first commission,
	# before the sheet has been written. After that the sheet is the source.
	var look := extra.strip_edges() if extra.strip_edges() != "" else hero_look(sheet)
	ensure("hero-" + cid.validate_filename(),
		"character portrait of %s, a %s %s %s, %s, %s, painted head-and-shoulders portrait, dramatic rim light, dark background, detailed face, no text" % [
			str(sheet.get("name", "a hero")), str(sheet.get("race", "")), str(sheet.get("cls", "adventurer")),
			subject_style("char"), look, world_flavor()], "1024x1024", true)


## A1 — if the world's compile already baked this name (vendor wares are a
## constant, Performance §7), never spend the player's GPU on it. That flood of
## shop icons is what pushed a third of the narrator onto the CPU.
func ensure_item_icon(nm: String) -> void:
	if Compiler.named_icon(GameState.world_id(), nm) != null:
		return
	# The SILHOUETTE is named from the item's own words (Rules.shape_clause), and
	# the flavour is stripped to its medium. Without the first, "Shortblade" came
	# back as a cruciform arming sword — the reported bug. Without the second it
	# came back as a candle.
	# LEAD WITH THE SHAPE. A diffusion model paints the first concrete noun it is
	# given, so the silhouette has to be the subject and the item's name the
	# modifier — not the other way round. Measured against the old wording on
	# eight items: plainer, truer objects (a staff without invented foliage, a
	# ring without invented gems) and a genuinely flat background, which is what
	# keeps an icon readable at 64 px.
	#
	# The background is described POSITIVELY. "no text, no hands" is a negative
	# instruction inside a positive prompt, which does not work — the chart bake
	# proved that at scale, producing a painted city and two misspelled
	# cartouches from a prompt that forbade both.
	var shape := Rules.shape_clause(nm)
	var subject: String = shape if shape != "" else nm
	ensure("item-" + nm.to_lower().replace(" ", "-"),
		"%s, made of %s. a single %s, alone, floating centered against a flat empty black background. %s, game inventory icon, sharp silhouette, whole object in frame" % [
			subject, subject_style("item"), nm, item_flavor()], "1024x1024")


func item_tex(nm: String) -> Texture2D:
	var baked := Compiler.named_icon(GameState.world_id(), nm)
	return baked if baked != null else texture_for("item-" + nm.to_lower().replace(" ", "-"))


## The right icon for an inventory item: a compiled catalogue item carries its
## own material-true `art`, painted once at compile — use it. Otherwise fall back
## to the legacy per-name generated icon. One seam for every item render.
func item_tex_for(it: Dictionary) -> Texture2D:
	if str(it.get("art", "")) != "":
		var tex := Compiler.item_texture(it)
		if tex != null:
			return tex
	return item_tex(str(it.get("name", "")))


## ── THE FIGURINE ON THE BOARD ────────────────────────────────────────────────
## The hero's token is a rendered MINIATURE, wearing what the player equipped.
##
## Rendered ONCE per loadout into an ImageTexture, not drawn live: the board
## repaints every frame for the shake and the cloud shadows, and a 3D viewport
## kept alive behind it would be a permanent tax on the one card the narrator
## also wants. Change your gear and exactly one new render happens.
##
## Nothing is written to disk. This is not commissioned art — it is a picture of
## geometry the game already ships, reproducible in a frame, so the art cache's
## LRU has no business evicting it and no reason to store it.
const FIG_PX := 256
var _fig_vp: SubViewport = null
var _fig_doll = null
var _fig_cache := {}     # loadout key → ImageTexture
var _fig_busy := {}      # loadout key → true while a render is in flight


## What makes one figurine different from another: the gear, and who is wearing
## it. Two heroes in identical kit legitimately share a token.
func _loadout_key(inv: Dictionary) -> String:
	var eq: Dictionary = inv.get("equipped", {}) if inv.get("equipped") is Dictionary else {}
	var by_id := {}
	for it in inv.get("items", []):
		if it is Dictionary:
			by_id[str(it.get("id", ""))] = str(it.get("name", ""))
	var bits: Array[String] = [hero_body_key()]
	for slot in ["head", "cloak", "weapon", "offhand", "shield"]:
		bits.append("%s=%s" % [slot, str(by_id.get(str(eq.get(slot, "")), ""))])
	return "|".join(bits)


## The token for this loadout, or null while it is still being made. Callers
## already handle null — the board draws its coloured disc until art arrives.
func figurine_tex(inv: Dictionary) -> Texture2D:
	# Headless has a dummy rasterizer: every capture is a blank square. Returning
	# null keeps the painted face in the harnesses instead of caching an empty
	# token and calling it a pass.
	if DisplayServer.get_name() == "headless":
		return null
	var key := _loadout_key(inv)
	if _fig_cache.has(key):
		return _fig_cache[key]
	if not _fig_busy.has(key):
		_fig_busy[key] = true
		_render_figurine(key, inv.duplicate(true))
	return null


func _render_figurine(key: String, inv: Dictionary) -> void:
	if _fig_vp == null:
		_fig_vp = SubViewport.new()
		_fig_vp.size = Vector2i(FIG_PX, FIG_PX)
		_fig_vp.transparent_bg = true
		_fig_vp.msaa_3d = Viewport.MSAA_4X
		# UPDATE_ONCE, driven per render. An offscreen viewport on ALWAYS is the
		# most expensive thing in this file and the least visible.
		_fig_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_fig_vp)
		var holder = load("res://scenes/char3d/modular_doll.gd").new()
		_fig_vp.add_child(holder)
		_fig_doll = holder
		# ASK THE DOLL which body its rig wears. This was hardcoded to the KayKit
		# path, so when the shipping rig changed the token kept building the old
		# chibi body and then dressing it with the NEW rig's profile — a 41-bone
		# skeleton wearing 65-bone garments, which renders as a pile of parts.
		var body := str(_fig_doll.body_path())
		if ResourceLoader.exists(body):
			_fig_doll.build(load(body))
		var key_light := DirectionalLight3D.new()
		key_light.rotation_degrees = Vector3(-40, 30, 0)
		key_light.light_energy = 1.7
		_fig_vp.add_child(key_light)
		var cam := Camera3D.new()
		cam.fov = 32.0
		cam.name = "FigCam"
		_fig_vp.add_child(cam)
	if _fig_doll == null:
		_fig_busy.erase(key)
		return
	_fig_doll.wear_inventory(inv)
	# Re-framed per loadout, and TIGHT — this ends up ~40 px inside a ring on the
	# board, so the margin that reads well on the Gear page leaves a figure too
	# small to recognise. Re-framing also matters because the bounds move: a
	# greatsword is wider than a dagger.
	var fcam: Camera3D = _fig_vp.get_node_or_null("FigCam")
	if fcam != null:
		_fig_doll.frame_camera(fcam, 1.0, 0.40)
	_fig_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _fig_vp.get_texture().get_image()
	_fig_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_fig_busy.erase(key)
	if img == null or img.is_empty():
		return
	_fig_cache[key] = ImageTexture.create_from_image(img)
	art_ready.emit("figurine")   # the board repaints and picks it up


## The face a combatant wears everywhere (board token, initiative rail):
## hero portrait / companion npc portrait / bestiary painting (commissioned
## from the entry's art prompt on first sight).
func combatant_tex(m: Dictionary) -> Texture2D:
	var id := str(m.get("id", ""))
	if id == "pc":
		# YOUR MINIATURE, not your portrait. The board is the table, and what
		# stands on a table is a figurine wearing what you actually equipped —
		# the same doll the Gear page fits, at token distance. Falls back to the
		# painted face only while the first render is still in flight, or where
		# there is no renderer at all (headless).
		var fig := figurine_tex(GameState.inv())
		if fig != null:
			return fig
		return round_tex(hero_key())
	if id.begins_with("cmp"):
		return round_tex("npc-" + str(m.get("name", "")).to_lower().replace(" ", "-"))
	var entry := Combat.bestiary_for(str(m.get("name", "")))
	if not entry.is_empty():
		var key := "beast-" + str(entry.get("slug", ""))
		# R6 FUN-12/BLANK-29 — the world's beasts were painted at bake time; a
		# fight was commissioning them again because it only checked the cache.
		var baked: Texture2D = Compiler.roster_art(GameState.world_id(), key)
		if baked != null:
			return baked
		if has_art(key):
			return round_tex(key)
		ensure(key, "%s, %s, painted creature portrait, %s style, dark background, no text" % [str(entry.get("art", "")), subject_style("beast"), world_flavor()])
		return null
	# R11 — a foe the STORY invented has no bestiary entry and no package art, so
	# the board drew a letter in a circle: Samuel Jenkins, captain of pirates,
	# rendered as a red disc with an S. This is precisely what runtime generation
	# is for — the worlds ship pre-baked and the GPU is kept for what the player's
	# own tale brings to the table.
	var nm := str(m.get("name", ""))
	if nm == "":
		return null
	var slug := nm.to_lower().replace(" ", "-").validate_filename()
	# Someone the world already knows, who has turned hostile, keeps their face.
	var known: Texture2D = Compiler.roster_art(GameState.world_id(), "npc-" + slug)
	if known != null:
		return known
	if has_art("npc-" + slug):
		return round_tex("npc-" + slug)
	if has_art("foe-" + slug):
		return round_tex("foe-" + slug)
	ensure("foe-" + slug,
		"character portrait of %s, %s, warm firelight, painted head-and-shoulders portrait, dark background, no text" % [nm, subject_style("char")],
		"1024x1024", true)
	return null


func ensure_battle_map(place: String) -> String:
	var key := "map-" + place.to_lower().replace(" ", "-").validate_filename()
	ensure(key, "top-down tabletop RPG battle map of %s, %s style, overhead view, painted terrain, no grid lines, no tokens, no text, muted lighting" % [place, world_flavor()], "1024x1024", true)
	return key


## World-true chart: skinned to the family ("map" for Everyday, "holo-map" for
## cyber…) — never a generic Earth map.
##
## AT-4 — THE PAINTING IS GROUND, NOT A MAP.
##
## This used to name up to six PLACES and ask for "landmarks drawn as small
## painted vignettes, winding routes between them". The engine then drew its own
## pins (Rules.place_position, deterministic from the name) and its own roads on
## top — so the chart carried two independent inventions of where everything is,
## and they never agreed. A painted tavern sat in the corner while the pin for
## that same tavern sat somewhere else entirely.
##
## The fix is NOT to ask the model for a layout. Asking for a spatial
## arrangement is strictly harder than asking for a silhouette, and the project
## already knows how that ends — see KnownIssues #5, "the model can be asked for
## a shape it will not draw". A prompt naming coordinates would fail quietly and
## look like it had worked.
##
## So the painting stops making claims it cannot keep. It paints LAND — terrain,
## water, the lie of the country — and the engine's pins and roads become the
## only statement about where anything is. Same reasoning as the missing scale
## bar: a chart that draws a position it cannot honour is a drawn lie.
##
## What it CAN take from the world honestly is its regions, because a region is
## an area and an area can be painted. A place is a point, and the points are
## ours.
func ensure_world_chart(world_id2: String, world_name: String, locations: Array = []) -> String:
	var key := "chart-" + world_id2.validate_filename()
	var lands: Array[String] = []
	for r in Rules.world_regions(world_id2):
		if r is Dictionary and str(r.get("name", "")) != "" and lands.size() < 4:
			lands.append(str(r["name"]))
	# A forged world may have no gazetteer; its locations still imply terrain
	# through their kind, which is a fact about ground rather than position.
	if lands.is_empty():
		var kinds := {}
		for l in locations:
			if l is Dictionary:
				var k := str(l.get("kind", ""))
				if k in ["wilds", "ruin", "settlement"] and not kinds.has(k):
					kinds[k] = true
		lands.assign(kinds.keys())
	var country := (", country of " + ", ".join(lands)) if not lands.is_empty() else ""
	var flavor: Dictionary = WorldSkin.skin_for_id(world_id2).get("flavor", {})
	ensure(key, "illustrated %s of the lands around %s%s, %s style, overhead view of open country — terrain, water, forest, hills and coast. empty wilderness, no buildings, no settlements, no landmarks, no roads or routes, no icons, no text labels, no border or frame" % [
		str(flavor.get("map", "chart")), world_name, country, str(flavor.get("world", "high fantasy"))])
	return key

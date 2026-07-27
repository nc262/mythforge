extends Node
## Compiler — the World Compiler (docs/WorldCompiler.md).
##
## A world is not data, it is a COMPILED GAME PACKAGE. Forging a world runs a
## staged pipeline that front-loads as much content as possible, so play never
## stops to generate the obvious. "Generate once. Play forever."
##
## Stage order matters: the text tiers (this file) gate everything, because
## they are what stop each later image from independently guessing what
## "pirate" means — the root cause of style drift.
##
##   TIER A — the seed        S1 Style Guide · S2 Asset Language   (LLM, no GPU)
##   TIER B — the identity    S3..S7 art                            (GPU)
##   TIER C — the assembly    S8..S10 catalogue, layouts, UI        (CPU)
##
## This file owns Tier A plus the journal/state machine every later stage
## reports into. Tier B/C land on top of it without changing this contract.

signal stage_started(stage: String, human: String)
signal stage_done(stage: String, ok: bool)
signal compiled(world_id: String, state: String)

## What a world has achieved. Play unlocks at PRESENTABLE — a 30-minute wall
## before the first scene would read as a hang, not as craft (design §4).
const SEEDED := "seeded"
const PRESENTABLE := "presentable"
const FURNISHED := "furnished"
const POPULATED := "populated"

## Bump when a stage's OUTPUT SHAPE changes — Reforge diffs against this.
const COMPILER_VERSION := 1

var busy := false
var current_world := ""
var _reforging := false   # set during reforge() so _await_art repaints, not caches
var _background := false   # set while queueing art fire-and-forget (non-blocking)
var _bg_pending := {}      # world_id → GPU jobs still baking; hits 0 → POPULATED

var _journal := {}   # world_id → {stage → true}


# ── Shipped (pre-baked) worlds ──────────────────────────────────────────────
## The game ships built-in worlds already compiled (world-true items, creatures,
## art) as zips under res://baked/, so a downloaded copy plays them instantly
## with no forge wait. On first run each zip is unpacked into user://worlds/ if
## it isn't there yet. PNGs are zipped (not loose in res://) so Godot's importer
## doesn't turn them into .ctex — the compiler reads them as ordinary files.
## R6 LAT-22/23/STR-23 — this used to unpack EVERY shipped zip here, in _ready,
## synchronously. With six baked worlds that is ~1.4 GB of PNGs written to disk
## before the first frame can present, on a launch where the player will open
## exactly one world. Now boot only *notes* which zips exist (a directory listing)
## and each world unpacks the first time something actually asks for it.
var _zips := {}        # world_id → res:// zip path, not yet unpacked
var _unpacked := {}    # world_id → true, so the hot path checks a dict, not disk


func _ready() -> void:
	_index_baked_worlds()


func _index_baked_worlds() -> void:
	var d := DirAccess.open("res://baked")
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".zip"):
			_zips[f.get_basename()] = "res://baked/%s" % f


## Unpack-on-demand. Called from world_dir(), which every accessor already goes
## through, so there is exactly one choke point and no caller has to remember.
func _ensure_unpacked(world_id: String) -> void:
	if world_id == "" or _unpacked.has(world_id):
		return
	_unpacked[world_id] = true          # set first: _unpack_baked re-enters world_dir
	if not _zips.has(world_id):
		return
	if FileAccess.file_exists("user://worlds/%s/world.json" % world_id.validate_filename()):
		return   # already on disk (or the player recompiled it)
	_unpack_baked(str(_zips[world_id]), world_id)


func _unpack_baked(zip_path: String, id: String) -> void:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return
	for inner in zr.get_files():
		var out := "%s/%s" % [world_dir(id), inner]
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(zr.read_file(inner))
			fa.close()
	zr.close()


# ── Storage ────────────────────────────────────────────────────────────────
## The compiled package lives beside the world record, not in the art cache:
## compiled assets are CONTENT (they are the world's identity), never a cache
## the LRU may evict (design §6).
func world_dir(world_id: String) -> String:
	_ensure_unpacked(world_id)   # lazy first-touch unpack (see _index_baked_worlds)
	return "user://worlds/%s" % world_id.validate_filename()


func _ensure_dirs(world_id: String) -> void:
	for sub in ["", "/art", "/art/parts", "/art/kits", "/art/creatures", "/art/npc",
			"/art/maps", "/art/unique", "/data", "/recipes"]:
		DirAccess.make_dir_recursive_absolute(world_dir(world_id) + sub)


func _write(world_id: String, rel: String, value) -> void:
	_ensure_dirs(world_id)
	var f := FileAccess.open("%s/%s" % [world_dir(world_id), rel], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(value, "\t"))
		f.close()


func read_pack(world_id: String) -> Dictionary:
	var p := "%s/world.json" % world_dir(world_id)
	if not FileAccess.file_exists(p):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary else {}


func compile_state(world_id: String) -> String:
	return str(read_pack(world_id).get("compile_state", ""))


func is_compiled(world_id: String) -> bool:
	return compile_state(world_id) != ""


# ── The pipeline ───────────────────────────────────────────────────────────
## Run Tier A for a freshly forged world. Cheap (~40 s, no GPU) and it is the
## thing every later stage consults, so it runs before any picture is painted.
## `resume` is for a re-run of an interrupted bake (B4): re-asking the model would
## invent DIFFERENT material, form and creature ids, orphaning every icon already
## on disk and restarting a six-hour pour. On a resume the stored seed IS the
## truth — only the pixels are still owed. The CPU stages (catalogue, kits,
## layouts) always rebuild; they are pure functions of the seed and cost nothing.
func compile_seed(world: Dictionary, resume := false) -> Dictionary:
	var wid := str(world.get("id", ""))
	if wid == "" or busy:
		return {}
	busy = true
	current_world = wid
	_ensure_dirs(wid)
	var pack := read_pack(wid)
	var keep := resume and int(pack.get("compiler", -1)) == COMPILER_VERSION
	pack["id"] = wid
	pack["name"] = str(world.get("name", ""))
	pack["kind"] = str(world.get("kind", ""))   # kept so Reforge can rebuild prompts
	pack["family"] = WorldSkin.family_of(world)
	pack["compiler"] = COMPILER_VERSION
	pack["forged_at"] = int(Time.get_unix_time_from_system())

	stage_started.emit("style", "Reading the world's own mind…")
	var style: Dictionary = pack["style"] if keep and pack.get("style") is Dictionary else {}
	if style.is_empty():
		style = await _stage_style_guide(world)
	pack["style"] = style
	stage_done.emit("style", not style.is_empty())

	stage_started.emit("assets", "Naming what things are made of…")
	var assets: Dictionary = pack["assets"] if keep and pack.get("assets") is Dictionary else {}
	if assets.is_empty():
		assets = await _stage_asset_language(world, style)
	pack["assets"] = assets
	stage_done.emit("assets", not assets.is_empty())

	# TIER C (data half): the item CATALOGUE. Pure CPU — it explodes the asset
	# language into the world's item space, so loot never has to be invented at
	# runtime. Runs even headless (no GPU), so the harness exercises it and the
	# world is browsable the moment it is seeded.
	stage_started.emit("catalogue", "Filling the world's coffers…")
	var catalogue := _build_catalogue(assets)
	_write(wid, "data/items.json", catalogue)
	pack["catalogue_count"] = catalogue.size()
	stage_done.emit("catalogue", not catalogue.is_empty())

	# S5 — starting KITS. Pre-rolled loadouts per archetype, drawn from the
	# catalogue, so a freshly forged hero is outfitted in world-true gear the
	# instant they exist (no empty-hands first turn).
	stage_started.emit("kits", "Packing the starting satchels…")
	var kits := _build_kits(assets)
	_write(wid, "data/kits.json", kits)
	stage_done.emit("kits", not kits.is_empty())

	# S6 — the world's own CREATURES (data half). Bestiary-shaped entries derived
	# from the style guide, so combat can give a world monster real stats. LLM in
	# the loop; degrades to a family-flavoured fallback so a world always has foes.
	stage_started.emit("creatures", "Loosing the world's beasts…")
	var creatures: Array = creatures_for(wid) if keep else []
	if creatures.is_empty():
		creatures = await _stage_creatures(world, style)
	_write(wid, "data/creatures.json", creatures)
	pack["creature_count"] = creatures.size()
	stage_done.emit("creatures", not creatures.is_empty())

	# S7 — the world's PEOPLE (data half). A named cast the GM can reference
	# consistently, so the world feels inhabited by specific someones.
	stage_started.emit("npcs", "Gathering the world's people…")
	var npcs: Array = npcs_for(wid) if keep else []
	if npcs.is_empty():
		npcs = await _stage_npcs(world, style)
	_write(wid, "data/npcs.json", npcs)
	pack["npc_count"] = npcs.size()
	stage_done.emit("npcs", not npcs.is_empty())

	# S9 (geometry half) — tactical LAYOUTS: handcrafted terrain arrangements on
	# the combat grid, ready for the fight to load instead of an empty field. The
	# geometry is world-agnostic; the world's look comes from the battle-map art.
	stage_started.emit("layouts", "Laying out the battlefields…")
	var layouts := _build_layouts()
	_write(wid, "data/layouts.json", layouts)
	stage_done.emit("layouts", not layouts.is_empty())

	pack["compile_state"] = SEEDED
	_write(wid, "world.json", pack)
	_journal[wid] = {"style": not style.is_empty(), "assets": not assets.is_empty(),
		"catalogue": not catalogue.is_empty(), "kits": not kits.is_empty(),
		"creatures": not creatures.is_empty(), "npcs": not npcs.is_empty(),
		"layouts": not layouts.is_empty()}
	compiled.emit(wid, SEEDED)

	# TIER B/C art bakes in the BACKGROUND. All the DATA a world needs to be
	# played is now written (catalogue, kits, creatures, npcs, layouts), so the
	# forge returns HERE — the player starts immediately. The ~80 GPU images
	# (key art, biomes, 60 item icons, portraits, maps) are queued to the Art
	# Director's IDLE lane and adopted into the package as each lands; the world
	# reaches POPULATED when the last one finishes. Skipped headless (no GPU).
	busy = false
	if not Api.test_mode:
		# PRESENTABLE is written BEFORE the art starts: a cached/already-baked key
		# answers its callback synchronously, so a resumed world can reach
		# POPULATED inside _start_background_art — writing PRESENTABLE after would
		# clobber it back down.
		pack["compile_state"] = PRESENTABLE
		_write(wid, "world.json", pack)
		compiled.emit(wid, PRESENTABLE)
		_start_background_art(wid, world, style, assets, creatures, npcs)
		if int(_bg_pending.get(wid, 0)) == 0:
			_mark_populated(wid)   # resumed with nothing left to paint
		pack = read_pack(wid)
	return pack


## Queue every GPU art job fire-and-forget (see compile_seed). Each _await_art
## call, under _background, registers an on_ready that adopts the finished image
## into THIS world's package and ticks the pending counter down to POPULATED.
func _start_background_art(world_id: String, world: Dictionary, style: Dictionary,
		assets: Dictionary, creatures: Array, npcs: Array) -> void:
	_background = true
	current_world = world_id
	_bg_pending[world_id] = 0
	_stage_identity(world_id, world, style)
	_stage_parts(world_id, style, assets)
	_stage_vendor_icons(world_id, WorldSkin.family_of(world))
	_stage_portrait_art(world_id, creatures, "creature")
	_stage_portrait_art(world_id, npcs, "npc")
	_stage_tactical(world_id, style)
	_background = false


# ── Reforge ─────────────────────────────────────────────────────────────────
## Re-run one stage of an already-compiled world WITHOUT a full recompile:
## "generate once" doesn't mean "generate wrong forever". Logical ids are stable,
## so only the pixels (or the derived data) swap — saves, kits, catalogue refs
## all keep pointing at the same ids. Reuses the world's stored Style Guide and
## Asset Language (no LLM) unless you reforge "style"/"assets" themselves.
##   stage ∈ identity | parts | wares | creatures | npcs | tactical | catalogue | kits | layouts
func reforge(world_id: String, stage: String) -> Dictionary:
	if busy:
		return {}
	busy = true
	_reforging = true
	current_world = world_id
	var pack := read_pack(world_id)
	var style: Dictionary = pack.get("style", {}) if pack.get("style") is Dictionary else {}
	var assets := assets_for(world_id)
	var world := {"id": world_id, "name": str(pack.get("name", "")), "kind": str(pack.get("kind", ""))}
	match stage:
		"identity":
			await _stage_identity(world_id, world, style)
		"parts":
			await _stage_parts(world_id, style, assets)
		"creatures":
			await _stage_portrait_art(world_id, creatures_for(world_id), "creature")
		"npcs":
			await _stage_portrait_art(world_id, npcs_for(world_id), "npc")
		"tactical":
			await _stage_tactical(world_id, style)
		"wares":
			await _stage_vendor_icons(world_id, str(pack.get("family", "fantasy")))
		"catalogue":
			_write(world_id, "data/items.json", _build_catalogue(assets))
		"kits":
			_write(world_id, "data/kits.json", _build_kits(assets))
		"layouts":
			_write(world_id, "data/layouts.json", _build_layouts())
		_:
			push_warning("Compiler.reforge: unknown stage '%s'" % stage)
	_reforging = false
	busy = false
	compiled.emit(world_id, str(pack.get("compile_state", "")))
	return read_pack(world_id)


## S3 — key art + biome plates. The world you SEE. Every prompt carries the
## Style Guide's anchor (via Art.world_flavor once the world is active), so the
## whole set holds one visual identity. Biome plates are the reskin source for
## backdrops and, later, tactical maps.
const BIOMES := ["a wilderness", "a settlement", "an interior chamber",
	"a high place", "a place of water", "a ruin"]


func _stage_identity(world_id: String, world: Dictionary, style: Dictionary) -> void:
	stage_started.emit("keyart", "Painting the world…")
	var anchor := str(style.get("prompt_anchor", ""))
	var name := str(world.get("name", "the world"))
	# Key art: the establishing shot. `scene` profile — painted, not photoreal,
	# no matte (a backdrop is never cut out).
	var key := "world-" + world_id.validate_filename()
	await _await_art(key,
		"establishing key art of %s, %s. %s. cinematic wide shot, no people, no text" % [
			name, str(world.get("kind", "")), anchor],
		{"profile": "scene", "lane": Art.Lane.NOW})
	stage_done.emit("keyart", true)

	stage_started.emit("biomes", "Charting its lands…")
	for i in BIOMES.size():
		var bkey := "biome-%s-%d" % [world_id.validate_filename(), i]
		await _await_art(bkey,
			"%s in %s, %s. atmospheric establishing scene, cinematic lighting, no people, no text" % [
				BIOMES[i], name, anchor],
			{"profile": "scene", "lane": Art.Lane.IDLE})
	stage_done.emit("biomes", true)


## S8 (art half) — the ARMORY. One matted icon per (form × material), painted in
## the material's ACTUAL look (a driftwood cutlass is driftwood, a brine-iron one
## is pitted iron) — quality over the neutral-grey-tint shortcut, which produced
## muddy recolours. ~60 icons per world; rarity is a draw-time glow, not new art.
## The item prompt carries NO scene anchor — appending the world's scene line
## ("…lantern light") turned a sword into a lantern. `item` profile = Turbo 1024
## + matte; "plain flat background, no scene" keeps the cut-out clean.
func _stage_parts(world_id: String, _style: Dictionary, assets: Dictionary) -> void:
	stage_started.emit("parts", "Forging the armory…")
	var mats: Array = assets.get("materials", []) if assets.get("materials") is Array else []
	for f in _forms(assets):
		for m in mats:
			if not (m is Dictionary and m.has("id")):
				continue
			# C2, and it MUST be the same test _build_catalogue uses. This stage
			# was crossing the unfiltered grid while the catalogue crossed the
			# filtered one, so 770 icons were painted per world to back 230 items
			# — 540 pictures of leather cuirasses and steel hoods that nothing
			# could ever reference. Measured on embervale: 807 queued vs 267 owed,
			# i.e. ~3.7 h of GPU per world spent painting unreachable art.
			if not _form_takes(f, _class_of(m)):
				continue
			var key := "part-%s-%s-%s" % [world_id.validate_filename(), str(f["id"]), str(m["id"])]
			await _await_art(key,
				("a %s %s. %s. fantasy RPG %s item icon, single subject centered, plain flat background, no scene, dramatic studio lighting, highly detailed painterly render, no text, no hands, no people" % [
					str(m.get("name", "")), str(f["name"]), str(f["prompt"]), str(f["kind"])]).strip_edges(),
				{"profile": "item", "lane": Art.Lane.IDLE},
				"art/parts/%s.%s.png" % [str(f["id"]), str(m["id"])])
	stage_done.emit("parts", true)


## S8b — the SHELVES. A keeper's stock is a constant per world family (`tables.json`
## `vendor_stock*`), identical for every player and fully known at build time — yet
## we were painting all eleven on the player's GPU the first time a shop opened.
## Those are the exact jobs that half-offloaded the narrator to 67 % GPU
## (Performance §7 A1). Baked here, a friend's first shop is instant and their card
## is free for the story. Same `item` profile as the armoury, and no scene anchor —
## appending the world's scene line turns a sword into a lantern.
func _stage_vendor_icons(world_id: String, family: String) -> void:
	var names := Rules.vendor_stock_names(family)
	if names.is_empty():
		return
	stage_started.emit("wares", "Stocking the keeper's shelves…")
	for nm in names:
		await _await_art("ware-%s-%s" % [world_id.validate_filename(), icon_slug(str(nm))],
			"a %s. fantasy RPG item icon, single subject centered, plain flat background, no scene, dramatic studio lighting, highly detailed painterly render, no text, no hands, no people" % str(nm),
			{"profile": "item", "lane": Art.Lane.IDLE},
			"art/icons/%s.png" % icon_slug(str(nm)))
	stage_done.emit("wares", true)


## The filename a named (non-catalogue) icon is baked under.
func icon_slug(nm: String) -> String:
	return nm.to_lower().replace(" ", "-").validate_filename()


## A baked icon for a plain item NAME (vendor wares, standard kit), or null if
## this world never baked one. The seam Art.item_tex falls back through.
func named_icon(world_id: String, nm: String) -> Texture2D:
	return _load_tex("%s/art/icons/%s.png" % [world_dir(world_id), icon_slug(nm)], ICON_PX)


## Request one image and wait for it to actually land (compile is sequential —
## one GPU). Copies it into the world package so it is CONTENT, not cache.
func _await_art(key: String, prompt: String, opts: Dictionary, dest_rel := "") -> void:
	# On a Reforge, drop the old pixels so this key genuinely repaints (Art.request
	# returns the cache otherwise). The logical id/filename is unchanged.
	if _reforging:
		Art.forget(key)
	var dest := dest_rel if dest_rel != "" else world_dir_key(key)
	# B4 — the resume checkpoint. The finished file in the world package IS the
	# journal: at ~25 s an icon, a pour that dies at hour five must not repaint the
	# 700 it already has. Safe to trust because _adopt_to writes atomically, so a
	# half-written PNG is never visible under its final name. A Reforge means
	# "repaint this on purpose", so it never skips.
	if not _reforging and FileAccess.file_exists("%s/%s" % [world_dir(current_world), dest]):
		return
	# Background mode: queue and return immediately (don't block). The Art Director
	# paints it in its own time and the on_ready adopts it into the package.
	if _background:
		var wid := current_world
		_bg_pending[wid] = int(_bg_pending.get(wid, 0)) + 1
		var ob := opts.duplicate()
		ob["on_ready"] = func(k): _bg_adopt(wid, dest, str(k))
		Art.request(key, prompt, ob)
		return
	var done := [false]
	var o := opts.duplicate()
	o["on_ready"] = func(_k): done[0] = true
	Art.request(key, prompt, o)
	# Also treat a hard failure as "done" so the compile never wedges.
	var fail := func(k: String, state: String):
		if str(k) == key and state in ["failed", "cancelled"]:
			done[0] = true
	Art.art_progress.connect(fail)
	var guard := 0
	while not done[0] and guard < 400:   # ~200s ceiling per image
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		guard += 1
	if Art.art_progress.is_connected(fail):
		Art.art_progress.disconnect(fail)
	if Art.has_art(key):
		_adopt_to(current_world, dest, key)


## Adopt a finished background image into its world, then tick the pending
## counter; when a world's last image lands, mark it POPULATED.
func _bg_adopt(world_id: String, dest_rel: String, key: String) -> void:
	_adopt_to(world_id, dest_rel, key)
	_bg_pending[world_id] = maxi(0, int(_bg_pending.get(world_id, 0)) - 1)
	# NOT while still queueing. Art.request answers SYNCHRONOUSLY for a key it
	# already has cached, so during _start_background_art the counter can dip to
	# zero between two stages — and a world would be declared POPULATED with
	# ~400 images not yet even queued. The bake harness would then walk on to the
	# next world and paint two at once on one GPU. _start_background_art settles
	# the count itself once every stage has been queued.
	if not _background and int(_bg_pending.get(world_id, 0)) == 0:
		_mark_populated(world_id)


func _mark_populated(world_id: String) -> void:
	var p := read_pack(world_id)
	if p.is_empty() or str(p.get("compile_state", "")) == POPULATED:
		return
	p["compile_state"] = POPULATED
	_write(world_id, "world.json", p)
	compiled.emit(world_id, POPULATED)


## How many GPU images a world is still waiting on (the bake harness watches this
## to tell "slow" from "stalled").
func pending_art(world_id: String) -> int:
	return int(_bg_pending.get(world_id, 0))


## Copy a painted asset into a specific world's package (content that never gets
## evicted). Takes an explicit world_id so background jobs don't race on
## current_world.
func _adopt_to(world_id: String, dest_rel: String, key: String) -> void:
	if dest_rel == "" or world_id == "":
		return
	var src := Art.path_for(key)
	if not FileAccess.file_exists(src):
		return
	var dst := "%s/%s" % [world_dir(world_id), dest_rel]
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return
	# B4 — write, then rename. A kill mid-write must not leave a truncated PNG
	# under the final name, because the resume check reads that name as "done".
	var tmp := dst + ".part"
	if img.save_png(tmp) == OK:
		DirAccess.rename_absolute(tmp, dst)


## Back-compat shim for any caller still adopting to the active world.
func _adopt(dest_rel: String, key: String) -> void:
	_adopt_to(current_world, dest_rel, key)


func world_dir_key(key: String) -> String:
	if key.begins_with("world-"):
		return "art/key.png"
	if key.begins_with("biome-"):
		return "art/%s.png" % key
	return "art/%s.png" % key


## S1 — the World Style Guide. The permanent source of truth every subsystem
## consults, so nothing downstream has to guess what this world looks like.
## The deterministic family (WorldSkin) is the PRIOR; the LLM specialises it.
func _stage_style_guide(world: Dictionary) -> Dictionary:
	var fam := WorldSkin.family_of(world)
	var base: Dictionary = WorldSkin.STYLE.get(fam, {})
	var ask := """You are the art director for a role-playing game world. Produce its STYLE GUIDE.

WORLD
name: %s
kind: %s
tagline: %s
lore: %s
family: %s (its default look: %s)

Answer with ONE JSON object, no prose, no markdown fence, using EXACTLY these keys:
{
 "visual_language": "one sentence: how this world looks, overall",
 "lighting": "characteristic light and time of day",
 "weather": ["3 typical weather moods"],
 "materials": ["10 materials this world is BUILT from — be specific and evocative"],
 "colors": {"dominant":"#rrggbb","accent":"#rrggbb","shadow":"#rrggbb"},
 "architecture": "how buildings look — forms, roofs, ornament",
 "clothing": "how ordinary people dress",
 "armor": "how warriors protect themselves",
 "weapons": "what arms look like here",
 "monsters": "what threatens people, and how it looks",
 "flora": "characteristic plant life",
 "fauna": "characteristic animals",
 "symbols": ["4 recurring symbols or motifs"],
 "culture": "one sentence on custom, faith or law",
 "music": "instruments and mood",
 "ui_feel": "what the interface should feel carved/printed/etched from",
 "prompt_anchor": "30-60 words appended to EVERY image prompt for this world: medium, palette, lighting, materials, mood. No proper nouns."
}
Be concrete and sensory. Avoid generic fantasy filler.""" % [
		str(world.get("name", "a world")), str(world.get("kind", "")),
		str(world.get("tagline", "")), str(world.get("lore", "")).left(700),
		fam, str(base.get("char", ""))]
	var got := await _ask_json(ask)
	if got.is_empty():
		return _fallback_style(world, fam, base)
	got["family"] = fam
	got["generated"] = true
	return got


## S2 — the Asset Language. Turns the style guide into the MODULAR VOCABULARY
## the item catalogue is assembled from: which part families exist, which
## materials tint them, which treatments and rarities apply. This is the
## Borderlands move — design a system, not twenty thousand objects.
##
## B2 — the ask is MATERIALS AND TREATMENTS ONLY. It used to ask for weapon and
## armour forms too, and raising the material ask from 6 to 10 made the 8B worse
## at everything at once: measured 2026-07-23 against the live backend, it
## returned 8 materials, 4 treatments, and its forms collapsed from 6/4 to 3/2
## ("leather_greaves" filed under armour). The JSON was clean both times, so this
## is capacity, not format — and the answer is a smaller ask, not a smaller model
## (the 3B provably cannot do asset language at all).
##
## We can afford the cut because forms are no longer the seed's job: 30 weapon
## shapes across 7 families and 40 worn-slot shapes are handcrafted and always
## apply, with a floor under armour. What the seed is genuinely needed for is what
## this world is MADE of and what happens to it — so it now spends its whole
## budget there. Older packs that still carry weapon_forms/armor_forms keep
## working; _forms() layers whatever it finds on top.
func _stage_asset_language(world: Dictionary, style: Dictionary) -> Dictionary:
	var mats: Array = style.get("materials", []) if style.get("materials") is Array else []
	var ask := """You are designing the ASSET LANGUAGE for a role-playing game world, so thousands of
believable items can be assembled from a few parts.

WORLD: %s — %s
MATERIALS: %s
WEAPONS look like: %s
ARMOR looks like: %s

Answer with ONE JSON object, no prose, no markdown fence:
{
 "materials": [{"id":"brine_iron","name":"Display Name","dark":"#rrggbb","light":"#rrggbb","tier":1,"class":"rigid"}],
 "treatments": [{"id":"salt_worn","name":"Display Name","note":"how it changes the look"}],
 "naming": {"prefix":["4 evocative prefixes"],"suffix":["4 suffixes, e.g. 'of the Ash Coast'"]}
}
Every material's "class" is one of: soft (cloth/hide/leather), mail (chain/scale),
rigid (metal/stone/wood), exotic (bone/crystal/salvage/strange). The class decides
which shapes it can be made into — a soft chest is a jerkin, a rigid one a cuirass.

Give EXACTLY 10 materials — at least two soft, two mail, two rigid, two exotic —
tiers 1 to 3 from cheap to precious, with colours that suit the world.
Give EXACTLY 10 treatments: wear and age, and also flame, frost, venom, storm,
blessed and cursed, each named in THIS world's own language.
Every id is one or two SHORT snake_case words (e.g. cutlass, brine_iron) — do NOT
append "_id" or "_form". Names must sound like THIS world.""" % [
		str(world.get("name", "a world")), str(style.get("visual_language", "")),
		", ".join(mats), str(style.get("weapons", "")), str(style.get("armor", ""))]
	var got := await _ask_json(ask)
	if got.is_empty() or not (got.get("materials") is Array):
		return _fallback_assets(style)
	# Small models parrot the schema placeholder ("cutlass_form_id") — scrub every
	# id to clean snake_case so filenames and catalogue ids stay tidy.
	for group in ["materials", "treatments", "weapon_forms", "armor_forms"]:
		if got.get(group) is Array:
			for e in got[group]:
				if e is Dictionary and e.has("id"):
					e["id"] = _clean_id(str(e["id"]))
	got["generated"] = true
	return got


## Normalise an LLM-supplied id to short snake_case, stripping the schema-
## placeholder suffixes small models echo back ("_form_id", "_id", "_slug").
func _clean_id(raw: String) -> String:
	var s := raw.to_lower().strip_edges()
	for junk in ["_form_id", "_material_id", "_armor_id", "_weapon_id", "_creature_id",
			"_npc_id", "_slug", "_form", "_id"]:
		if s.ends_with(junk):
			s = s.substr(0, s.length() - junk.length())
			break
	var out := ""
	for i in s.length():
		var ch := s[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.lstrip("_").rstrip("_")
	return out if out != "" else raw.to_lower()


## S6 — the world's CREATURES. Bestiary-shaped so Combat.bestiary_for can give a
## world monster real stats (tier → TIER_STATS). Derived from the style guide's
## monsters/fauna, so the beasts belong to THIS world, not generic fantasy.
func _stage_creatures(world: Dictionary, style: Dictionary) -> Array:
	var ask := """You are the monster designer for a role-playing game world. Populate its BESTIARY.

WORLD: %s — %s
WHAT THREATENS PEOPLE: %s
FAUNA: %s
FAMILY: %s

Answer with ONE JSON object, no prose, no markdown fence:
{"creatures":[
 {"slug":"lowercase_id","name":"Display Name","tier":"minor|standard|dire",
  "desc":"one vivid sentence of what it is and how it fights",
  "weakness":"one concrete, exploitable weakness",
  "tactics":"one sentence on how it fights",
  "habitat":"where it is found",
  "art":"a short image-prompt phrase: the creature, concept art, dark background"}
]}
Rules: exactly 8 creatures. Spread the tiers (about 4 minor, 3 standard, 1 dire).
Every slug lowercase_with_underscores and unique. Names must sound like THIS
world — no goblins/kobolds/dragons unless the world truly is that generic.""" % [
		str(world.get("name", "a world")), str(style.get("visual_language", "")),
		str(style.get("monsters", "")), str(style.get("fauna", "")),
		WorldSkin.family_of(world)]
	var got := await _ask_json(ask)
	var raw = got.get("creatures") if got.get("creatures") is Array else []
	var out: Array = []
	for c in raw:
		if not (c is Dictionary) or str(c.get("slug", "")) == "":
			continue
		var tier := str(c.get("tier", "minor"))
		if not tier in ["minor", "standard", "dire"]:
			tier = "standard"
		out.append({
			"slug": _clean_id(str(c["slug"])), "name": str(c.get("name", c["slug"])), "tier": tier,
			"desc": str(c.get("desc", "")), "weakness": str(c.get("weakness", "")),
			"tactics": str(c.get("tactics", "")), "habitat": str(c.get("habitat", "")),
			"art": str(c.get("art", str(c.get("name", "")) + ", creature concept art, dark background")),
			"generated": true,
		})
	# Floor under the bestiary — the creature-side of FALLBACK_FORMS. The 8B
	# sometimes returns a thin roster (fimbulreach came back with 2 where its
	# siblings gave 7-9); a world with two monsters repeats itself in every
	# fight. Merge in the family-flavoured fallbacks (never replace the real
	# ones) until there are enough to vary combat. Deduped by slug.
	if out.size() >= 5:
		return out
	var seen := {}
	for c in out:
		seen[str((c as Dictionary).get("slug", ""))] = true
	for c in _fallback_creatures(style):
		if not seen.has(str(c.get("slug", ""))):
			out.append(c)
	return out


## Art half for a roster — one painted portrait per entry (portrait profile:
## 1024, no matte, matching the bestiary look). kind picks the key prefix and
## package sub-dir ("creature"→art/creatures, "npc"→art/npc). Sequential: one GPU.
func _stage_portrait_art(world_id: String, entries: Array, kind: String) -> void:
	if entries.is_empty():
		return
	stage_started.emit(kind + "_art", "Giving the %s faces…" % ("beasts" if kind == "creature" else "people"))
	var anchor := prompt_anchor(world_id)
	var sub := "creatures" if kind == "creature" else "npc"
	for e in entries:
		var slug := str((e as Dictionary).get("slug", ""))
		if slug == "":
			continue
		var key := "%s-%s-%s" % [kind, world_id.validate_filename(), slug]
		await _await_art(key,
			"%s. %s. no text" % [str((e as Dictionary).get("art", "")), anchor],
			{"profile": "portrait", "lane": Art.Lane.IDLE},
			"art/%s/%s.png" % [sub, slug])
	stage_done.emit(kind + "_art", true)


func _fallback_creatures(style: Dictionary) -> Array:
	var beast := str(style.get("monsters", "a lurking predator"))
	return [
		{"slug": "scavenger", "name": "Scavenger", "tier": "minor",
			"desc": "A wary pack-hunter that harries the weak and flees the strong.",
			"weakness": "Cowardly — break one and the pack scatters.",
			"tactics": "Circle, dart in, retreat.", "habitat": "the wilds",
			"art": "%s, small pack predator, creature concept art, dark background" % beast, "generated": false},
		{"slug": "brute", "name": "Brute", "tier": "standard",
			"desc": "A heavy, thick-hided thing that trades finesse for force.",
			"weakness": "Slow to turn — flank it.", "tactics": "Charge and crush.",
			"habitat": "broken ground",
			"art": "%s, large heavy brute, creature concept art, dark background" % beast, "generated": false},
		{"slug": "horror", "name": "Horror", "tier": "dire",
			"desc": "The thing the world's mothers warn their children about.",
			"weakness": "Bound to its lair — it will not follow far.",
			"tactics": "Ambush from the dark, then overwhelm.", "habitat": "the deep places",
			"art": "%s, terrifying apex creature, creature concept art, dark background" % beast, "generated": false},
	]


## S7 — the world's PEOPLE. A named cast (patron, merchant, authority, outcast…)
## the GM can name consistently, so the world is inhabited by specific someones
## instead of anonymous "a guard". Derived from the world's culture and clothing.
func _stage_npcs(world: Dictionary, style: Dictionary) -> Array:
	var ask := """You are the casting director for a role-playing game world. Name its PEOPLE — the
faces a traveller actually meets.

WORLD: %s — %s
HOW PEOPLE DRESS: %s
CUSTOM/FAITH/LAW: %s

Answer with ONE JSON object, no prose, no markdown fence:
{"npcs":[
 {"slug":"lowercase_id","name":"Person Name","role":"what they do (innkeeper, captain, fence…)",
  "disposition":"friendly|wary|hostile|neutral",
  "look":"one vivid sentence describing their appearance",
  "location":"where they are usually found",
  "hook":"one sentence: what they want, or a rumour they carry",
  "art":"a short image-prompt phrase: the person, character portrait"}
]}
Rules: exactly 6 people, varied roles and dispositions. Every slug
lowercase_with_underscores and unique. Names and roles must fit THIS world.""" % [
		str(world.get("name", "a world")), str(style.get("visual_language", "")),
		str(style.get("clothing", "")), str(style.get("culture", ""))]
	var got := await _ask_json(ask)
	var raw = got.get("npcs") if got.get("npcs") is Array else []
	var out: Array = []
	for c in raw:
		if not (c is Dictionary) or str(c.get("slug", "")) == "":
			continue
		var disp := str(c.get("disposition", "neutral"))
		if not disp in ["friendly", "wary", "hostile", "neutral"]:
			disp = "neutral"
		out.append({
			"slug": _clean_id(str(c["slug"])), "name": str(c.get("name", c["slug"])),
			"role": str(c.get("role", "")), "disposition": disp,
			"look": str(c.get("look", "")), "location": str(c.get("location", "")),
			"hook": str(c.get("hook", "")),
			"art": str(c.get("art", str(c.get("name", "")) + ", character portrait")),
			"generated": true,
		})
	return out if not out.is_empty() else _fallback_npcs(style)


func _fallback_npcs(style: Dictionary) -> Array:
	var dress := str(style.get("clothing", "practical, worn clothes"))
	return [
		{"slug": "the_host", "name": "The Host", "role": "innkeeper", "disposition": "friendly",
			"look": "A broad, easy-smiling keeper of the common room.", "location": "the waystop",
			"hook": "Trades a warm meal for the latest news of the road.",
			"art": "an innkeeper wearing %s, character portrait" % dress, "generated": false},
		{"slug": "the_warden", "name": "The Warden", "role": "authority", "disposition": "wary",
			"look": "Hard-eyed and armoured, watching every door.", "location": "the gate",
			"hook": "Wants order kept, and remembers who breaks it.",
			"art": "a stern warden in armour, character portrait", "generated": false},
		{"slug": "the_fence", "name": "The Fence", "role": "merchant", "disposition": "neutral",
			"look": "Soft-spoken, quick-fingered, never quite meeting your eye.", "location": "the back room",
			"hook": "Buys what shouldn't be sold, for a price.",
			"art": "a shadowy merchant, character portrait", "generated": false},
	]


# ── S9 tactical layouts (geometry, CPU) ─────────────────────────────────────
## The combat grid (Combat.MAP_COLS × MAP_ROWS = 16×10). Kinds match combat's
## terrain vocabulary exactly: block (impassable), water (difficult), cover (+2).
const MAP_W := 16
const MAP_H := 10


## Handcrafted battlefields as terrain dicts ("x,y" → kind) combat loads directly.
## Geometry is world-agnostic; the world's identity is the battle-map painting.
func _build_layouts() -> Array:
	return [
		{"name": "Open Ground", "terrain": _lay_scatter("cover", [[3, 2], [12, 7], [6, 8], [10, 2]])},
		{"name": "The Chokepoint", "terrain": _lay_wall("block", 8, [4, 5])},
		{"name": "Broken Cover", "terrain": _lay_scatter("cover", [[4, 3], [11, 3], [7, 5], [3, 7], [12, 6], [8, 8]])},
		{"name": "The Crossing", "terrain": _lay_band("water", 5, [3, 10])},
		{"name": "The Ruins", "terrain": _lay_merge(
			_lay_scatter("block", [[5, 3], [5, 4], [10, 5], [11, 5]]),
			_lay_scatter("cover", [[6, 4], [9, 5], [8, 2], [3, 8], [13, 3]]))},
	]


func _lay_put(t: Dictionary, x: int, y: int, kind: String) -> void:
	if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
		t["%d,%d" % [x, y]] = kind


func _lay_scatter(kind: String, cells: Array) -> Dictionary:
	var t := {}
	for c in cells:
		_lay_put(t, int(c[0]), int(c[1]), kind)
	return t


## A vertical wall down column `col`, open at the given rows (a gap to fight over).
func _lay_wall(kind: String, col: int, gap_rows: Array) -> Dictionary:
	var t := {}
	for y in MAP_H:
		if not y in gap_rows:
			_lay_put(t, col, y, kind)
	return t


## A horizontal band across row `row`, open at the given columns (fords/stones).
func _lay_band(kind: String, row: int, gap_cols: Array) -> Dictionary:
	var t := {}
	for x in MAP_W:
		if not x in gap_cols:
			_lay_put(t, x, row, kind)
	return t


func _lay_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	for k in b:
		a[k] = b[k]
	return a


## S9 (art half) — a top-down tactical map per biome, painted overhead so it
## reads as a battlefield from above. `scene` profile (no matte — it's a floor).
func _stage_tactical(world_id: String, style: Dictionary) -> void:
	stage_started.emit("tactical", "Mapping the battlegrounds…")
	var anchor := str(style.get("prompt_anchor", ""))
	for i in BIOMES.size():
		var key := "map-%s-%d" % [world_id.validate_filename(), i]
		await _await_art(key,
			"top-down tactical battle map of %s, %s. overhead bird's-eye view, flat readable ground, no characters, no text, no grid lines" % [
				BIOMES[i], anchor],
			{"profile": "scene", "lane": Art.Lane.IDLE},
			"art/maps/map-%d.png" % i)
	stage_done.emit("tactical", true)


## One JSON answer from the local model. Small models fence their JSON and
## chatter around it, so the payload is extracted rather than trusted.
func _ask_json(prompt: String) -> Dictionary:
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/complete_json",
		{"prompt": prompt})
	if r.get("_status", 0) != 200:
		return {}
	# The endpoint returns raw model text under "text"; small models fence and
	# chatter around the object, so extract it rather than trust it.
	if r.get("text") is String:
		var d := _extract_json(str(r["text"]))
		# The fast (3B) model often wraps the whole thing in a single descriptive
		# key ({"style-guide": {...}}); unwrap once so the expected keys surface
		# instead of the stage falling back to generic content.
		if d.size() == 1 and (d.values()[0] is Dictionary):
			return d.values()[0]
		return d
	return {}


func _extract_json(text: String) -> Dictionary:
	var s := text.strip_edges()
	var a := s.find("{")
	var b := s.rfind("}")
	if a == -1 or b <= a:
		return {}
	var body := s.substr(a, b - a + 1)
	var parsed = JSON.parse_string(body)
	if parsed is Dictionary:
		return parsed
	# Repair the one glitch local models emit most on big objects: a trailing
	# comma before a } or ]. Strip those and retry once before giving up.
	var re := RegEx.new()
	re.compile(",\\s*([}\\]])")
	parsed = JSON.parse_string(re.sub(body, "$1", true))
	return parsed if parsed is Dictionary else {}


# ── Fallbacks: a compile NEVER fails, it degrades ───────────────────────────
## If the model is down or answers rubbish, the world still gets a valid guide
## from its deterministic family. A world is always usable.
func _fallback_style(world: Dictionary, fam: String, base: Dictionary) -> Dictionary:
	var skin := WorldSkin.skin(fam)
	var pal: Dictionary = Ui.PALETTES.get(str(skin.get("palette", "arcane")), Ui.PALETTES["arcane"])
	return {
		"visual_language": str(skin.get("art", "")),
		"lighting": "candlelit and low", "weather": ["clear", "overcast", "storm"],
		"materials": skin.get("materials", {}).values(),
		"colors": {"dominant": pal["surface"].to_html(false), "accent": pal["gold"].to_html(false),
			"shadow": pal["night"].to_html(false)},
		"architecture": "", "clothing": str(base.get("char", "")), "armor": "",
		"weapons": str(base.get("item", "")), "monsters": str(base.get("beast", "")),
		"flora": "", "fauna": "", "symbols": [], "culture": "",
		"music": "", "ui_feel": str(skin.get("materials", {}).get("panel", "stone")),
		"prompt_anchor": str(skin.get("art", "")),
		"family": fam, "generated": false,
	}


func _fallback_assets(style: Dictionary) -> Dictionary:
	var mats: Array = style.get("materials", []) if style.get("materials") is Array else ["iron", "bronze", "bone"]
	var out: Array = []
	var ramp := [["#1a1c22", "#ced6e0"], ["#2e1c0a", "#e4ac54"], ["#363024", "#f0e9d0"],
		["#08161f", "#56eeea"], ["#241408", "#96602f"], ["#3c2806", "#fad060"],
		["#101a14", "#7fbf9a"], ["#22101c", "#d07ac0"], ["#1c1c10", "#c8c07a"],
		["#0e1420", "#8fa8d8"]]
	for i in mini(mats.size(), 10):
		out.append({"id": str(mats[i]).to_lower().replace(" ", "_"), "name": str(mats[i]).capitalize(),
			"dark": ramp[i % ramp.size()][0], "light": ramp[i % ramp.size()][1], "tier": 1 + i / 3})
	# A style guide can list ten cloths and no metal; the catalogue still needs a
	# shape in every class or the filter empties whole slots. Top up what's missing.
	var have := {}
	for m in out:
		have[_class_of(m)] = true
	if not have.has("any"):   # an unclassified material already fits every form
		for pair in [["soft", "Hide", "#241408", "#96602f"], ["mail", "Chain", "#1a1c22", "#ced6e0"],
				["rigid", "Iron", "#15181d", "#9aa4b2"], ["exotic", "Bone", "#232018", "#e8e0c8"]]:
			if not have.has(pair[0]):
				out.append({"id": str(pair[1]).to_lower(), "name": str(pair[1]),
					"dark": pair[2], "light": pair[3], "tier": 1, "class": pair[0]})
	return {
		"materials": out,
		"treatments": [{"id": "clean", "name": "Clean", "note": "as made"},
			{"id": "worn", "name": "Worn", "note": "scratched and dulled"},
			{"id": "blooded", "name": "Blooded", "note": "darkened, used"},
			{"id": "blessed", "name": "Blessed", "note": "faintly lit"},
			{"id": "flame_touched", "name": "Flame-Touched", "note": "scorched, ember-lit"},
			{"id": "frostbound", "name": "Frostbound", "note": "rimed and pale"},
			{"id": "venomed", "name": "Venomed", "note": "stained a sick green"},
			{"id": "storm_struck", "name": "Storm-Struck", "note": "arced and blue-white"},
			{"id": "cursed", "name": "Cursed", "note": "drinks the light"},
			{"id": "salt_eaten", "name": "Salt-Eaten", "note": "pitted and dulled"}],
		"weapon_forms": [{"id": "sword", "name": "Sword", "prompt": "a straight double-edged sword"},
			{"id": "axe", "name": "Axe", "prompt": "a war axe"},
			{"id": "dagger", "name": "Dagger", "prompt": "a slim dagger"},
			{"id": "staff", "name": "Staff", "prompt": "a long staff"},
			{"id": "bow", "name": "Bow", "prompt": "a recurve bow"},
			{"id": "hammer", "name": "Hammer", "prompt": "a heavy warhammer"}],
		"armor_forms": [{"id": "helm", "name": "Helm", "prompt": "a helmet"},
			{"id": "chest", "name": "Chestpiece", "prompt": "a chest armor piece"},
			{"id": "shield", "name": "Shield", "prompt": "a round shield"},
			{"id": "boots", "name": "Boots", "prompt": "a pair of boots"}],
		"naming": {"prefix": ["Old", "Keen", "Grim", "Bright"],
			"suffix": ["of the Road", "of the Deep", "of Ash", "of the Watch"]},
		"generated": false,
	}


# ── The catalogue (Tier C, S8 data) ────────────────────────────────────────
## Rarity ladder: colour (glow/label), value multiplier, and how many name
## affixes it earns. Order matters — index is the roll weight tier.
const RARITIES := [
	{"id": "common", "name": "Common", "glow": "#9aa4b2", "mult": 1.0, "affix": 0, "weight": 60},
	{"id": "uncommon", "name": "Uncommon", "glow": "#5fd07a", "mult": 1.8, "affix": 1, "weight": 26},
	{"id": "rare", "name": "Rare", "glow": "#5aa0ff", "mult": 3.4, "affix": 1, "weight": 10},
	{"id": "epic", "name": "Epic", "glow": "#b060ff", "mult": 6.5, "affix": 2, "weight": 3},
	{"id": "legendary", "name": "Legendary", "glow": "#ffb020", "mult": 13.0, "affix": 2, "weight": 1},
]


## All forms as one list, each tagged weapon/armor, in a stable order (so ids
## stay put across a Reforge). Reads the asset language; empty → nothing.
## The eleven worn slots beyond weapon/armor, handcrafted rather than asked for.
## Asking the seed model for thirteen form lists blows up the JSON, and the small
## models already fail at two (the 3B returned *sharpening stones* for weapon
## forms). These carry a shape prompt only — the world's own `prompt_anchor`
## supplies medium, palette, materials and mood, so a brine-iron circlet and a
## chrome one come out world-true without the model inventing either. Shipping
## them means a weak seed can never again leave eleven slots empty — the eleven
## identical grey diamonds on the Gear tab (UXAudit R5, VIS-15).
const SLOT_FORMS := {
	"head": [["hood", "a deep hood", ["soft"]], ["coif", "a mail coif", ["mail"]],
		["helm", "a full helm", ["rigid"]], ["circlet", "a slim circlet", ["rigid", "exotic"]],
		["mask", "a carved face mask", ["exotic"]]],
	"neck": [["scarf", "a wound neck scarf", ["soft"]], ["torc", "a heavy neck torc", ["rigid"]],
		["amulet", "an amulet on a cord", ["rigid", "exotic"]], ["pendant", "a small pendant", ["exotic"]]],
	"cloak": [["cloak", "a long travelling cloak", ["soft"]], ["cape", "a short cape", ["soft"]],
		["mantle", "a heavy shoulder mantle", ["mail", "rigid"]], ["shroud", "a strange shroud", ["exotic"]]],
	"hands": [["wraps", "wrapped hand bindings", ["soft"]], ["gloves", "a pair of gloves", ["soft"]],
		["mail_gloves", "mail-backed gloves", ["mail"]], ["gauntlets", "armoured gauntlets", ["rigid"]],
		["claws", "clawed hand guards", ["exotic"]]],
	"waist": [["sash", "a knotted sash", ["soft"]], ["belt", "a wide buckled belt", ["soft", "rigid"]],
		["girdle", "a reinforced girdle", ["mail", "rigid"]]],
	"legs": [["breeches", "sturdy breeches", ["soft"]], ["leggings", "close-fitting leggings", ["soft"]],
		["mail_chausses", "mail leg chausses", ["mail"]], ["greaves", "a pair of plate greaves", ["rigid"]]],
	"feet": [["sandals", "strapped sandals", ["soft"]], ["boots", "a pair of boots", ["soft"]],
		["shod_boots", "armoured boots", ["mail", "rigid"]], ["talons", "taloned footguards", ["exotic"]]],
	"ring": [["band", "a plain ring band", ["rigid"]], ["signet", "a signet ring", ["rigid"]],
		["coil_ring", "a coiled ring", ["exotic"]]],
	"shield": [["targe", "a hide-faced targe", ["soft"]], ["buckler", "a small buckler", ["mail", "rigid"]],
		["round_shield", "a round shield", ["rigid"]], ["kite_shield", "a tall kite shield", ["rigid"]]],
	"offhand": [["parry_dagger", "a parrying dagger", ["rigid"]], ["focus", "a spellcasting focus", ["exotic"]],
		["lantern", "a hand lantern", ["rigid"]], ["charm", "a bundled charm", ["soft", "exotic"]]],
}

## C1 — material classes. A leather chest and a steel chest are not one
## silhouette in two textures; they are a jerkin and a cuirass. Every form
## declares which classes it accepts, every material resolves to one, and
## _build_catalogue crosses only compatible pairs. Ten materials then yield
## several genuinely different shapes rather than ten repaints of one.
const CLASS_WORDS := {
	"soft": ["leather", "hide", "cloth", "linen", "silk", "canvas", "sail", "fur",
		"pelt", "wool", "rag", "rope", "weave", "cotton", "denim", "nylon", "kevlar"],
	"mail": ["chain", "scale", "ring", "mail", "link", "lamellar"],
	"rigid": ["iron", "steel", "bronze", "brass", "copper", "silver", "gold", "chrome",
		"titan", "alloy", "plate", "adamant", "cobalt", "obsidian", "stone", "wood", "oak"],
	"exotic": ["bone", "chitin", "crystal", "glass", "salvage", "coral", "shell",
		"ivory", "resin", "void", "spirit", "ghost", "neon", "plasma", "circuit"],
}


## C5 — the class a material belongs to. The seed is asked to declare one; when
## it does we trust it, because a world can invent a material whose name carries
## no known word ("sunmetal", "godsflesh"). Otherwise fall back to keywords.
func _class_of(mat: Dictionary) -> String:
	var declared := str(mat.get("class", "")).strip_edges().to_lower()
	if declared in ["soft", "mail", "rigid", "exotic"]:
		return declared
	return _material_class(str(mat.get("id", "")))


## Which class a material id belongs to by name. Unknown materials match
## EVERYTHING — a classifier miss must never silently empty a world's catalogue.
func _material_class(mat_id: String) -> String:
	var low := mat_id.to_lower()
	for cls in CLASS_WORDS:
		for w in CLASS_WORDS[cls]:
			if low.contains(str(w)):
				return str(cls)
	return "any"


## C2 — does this form accept this material? A form with no declared classes
## takes anything (that is how the seed's own weapon/armor forms behave, since
## the model isn't asked for classes).
func _form_takes(form: Dictionary, mat_class: String) -> bool:
	var accepts = form.get("classes")
	if not (accepts is Array) or (accepts as Array).is_empty():
		return true
	if mat_class == "any":
		return true
	return accepts.has(mat_class)


## C4 — weapon families. `weapon` was one bucket and the seed reaches for blades
## every time, so a world's armoury was six swords in six metals. These ship
## ALWAYS (the seed's own world-flavoured weapons layer on top), so every world
## has something to swing, shoot and throw. Classes keep a wooden club wooden and
## a bowstring off the plate rack.
const WEAPON_FAMILIES := {
	"blade": [["shortblade", "a short straight blade", ["rigid"]], ["longblade", "a long sword blade", ["rigid"]],
		["curved_blade", "a curved sabre", ["rigid"]], ["greatblade", "a two-handed great blade", ["rigid"]],
		["shard_blade", "a jagged shard blade", ["exotic"]]],
	"axe": [["hand_axe", "a one-handed axe", ["rigid"]], ["war_axe", "a bearded war axe", ["rigid"]],
		["great_axe", "a two-handed great axe", ["rigid"]], ["cleaver", "a heavy cleaver", ["rigid"]]],
	"blunt": [["club", "a heavy wooden club", ["soft", "rigid"]], ["mace", "a flanged mace", ["rigid"]],
		["hammer", "a war hammer", ["rigid"]], ["maul", "a two-handed maul", ["rigid"]],
		["bone_cudgel", "a knotted bone cudgel", ["exotic"]]],
	"polearm": [["spear", "a long spear", ["rigid"]], ["halberd", "a halberd", ["rigid"]],
		["glaive", "a curved glaive", ["rigid"]], ["pike", "a long pike", ["rigid"]]],
	"ranged": [["shortbow", "a short bow", ["soft", "rigid"]], ["longbow", "a tall longbow", ["soft", "rigid"]],
		["crossbow", "a heavy crossbow", ["rigid"]], ["sling", "a leather sling", ["soft"]]],
	"thrown": [["javelin", "a throwing javelin", ["rigid"]], ["throwing_knife", "a balanced throwing knife", ["rigid"]],
		["bola", "a weighted bola", ["soft"]], ["harpoon", "a barbed harpoon", ["rigid"]]],
	"exotic_arm": [["whip", "a coiled whip", ["soft"]], ["chain_flail", "a chained flail", ["mail", "rigid"]],
		["talon_claw", "a strapped claw", ["exotic"]], ["focus_rod", "a channelling rod", ["exotic"]]],
}


## The floor under the seed's own armour group. Only used when the model returned
## nothing usable — `everyday` shipped with 2 weapon forms and 33 images because
## nothing caught that. A world may be plain; it may not be empty.
const FALLBACK_FORMS := {
	"armor": [["jerkin", "a leather jerkin", ["soft"]], ["padded_coat", "a padded coat", ["soft"]],
		["mail_shirt", "a mail shirt", ["mail"]], ["scale_vest", "a scaled vest", ["mail"]],
		["cuirass", "a plate cuirass", ["rigid"]], ["breastplate", "a fitted breastplate", ["rigid"]],
		["carapace", "a bound carapace", ["exotic"]]],
}


## Every form the catalogue is built from: what the seed invented for weapons and
## armour, plus the handcrafted set for the other ten slots.
func _forms(assets: Dictionary) -> Array:
	var out: Array = []
	for kind in ["weapon", "armor"]:
		var before := out.size()
		var arr = assets.get(kind + "_forms")
		if arr is Array:
			for f in arr:
				if f is Dictionary and f.has("id"):
					out.append({"id": str(f["id"]), "name": str(f.get("name", f["id"])),
						"prompt": str(f.get("prompt", f.get("name", ""))), "kind": kind})
		# Armour has a floor; weapons have a whole spine (WEAPON_FAMILIES below).
		if kind == "armor" and out.size() == before:
			for pair in FALLBACK_FORMS["armor"]:
				out.append({"id": str(pair[0]), "name": str(pair[0]).capitalize().replace("_", " "),
					"prompt": str(pair[1]), "kind": "armor", "classes": pair[2]})
	for fam in WEAPON_FAMILIES:
		for pair in WEAPON_FAMILIES[fam]:
			out.append({"id": str(pair[0]), "name": str(pair[0]).capitalize().replace("_", " "),
				"prompt": str(pair[1]), "kind": "weapon", "family": str(fam), "classes": pair[2]})
	for slot in SLOT_FORMS:
		for pair in SLOT_FORMS[slot]:
			out.append({"id": str(pair[0]), "name": str(pair[0]).capitalize().replace("_", " "),
				"prompt": str(pair[1]), "kind": str(slot),
				"classes": (pair[2] if pair.size() > 2 else [])})
	return out


## Explode forms × materials × rarity into concrete item records. Logical ids
## are STABLE (form.material.rarity) — Reforge swaps the pixels behind an id, it
## never renumbers the catalogue. Treatments are applied at roll time, not baked,
## so this stays a browsable spine (hundreds) that rolls into thousands.
func _build_catalogue(assets: Dictionary) -> Array:
	var forms := _forms(assets)
	var mats: Array = assets.get("materials", []) if assets.get("materials") is Array else []
	var naming = assets.get("naming", {}) if assets.get("naming") is Dictionary else {}
	var prefixes: Array = naming.get("prefix", []) if naming.get("prefix") is Array else []
	var suffixes: Array = naming.get("suffix", []) if naming.get("suffix") is Array else []
	var out: Array = []
	for f in forms:
		for m in mats:
			if m is Dictionary and not _form_takes(f, _class_of(m)):
				continue   # C2: no leather cuirasses, no steel hoods
			if not (m is Dictionary and m.has("id")):
				continue
			var tier := int(m.get("tier", 1))
			for ri in RARITIES.size():
				var r: Dictionary = RARITIES[ri]
				out.append({
					"id": "%s.%s.%s" % [str(f["id"]), str(m["id"]), str(r["id"])],
					"name": _item_name(f, m, r, prefixes, suffixes, out.size()),
					"kind": str(f["kind"]), "form": str(f["id"]), "material": str(m["id"]),
					"rarity": str(r["id"]), "tier": tier,
					"value": int(round(_base_value(str(f["kind"]), tier) * float(r["mult"]))),
					"art": "art/parts/%s.%s.png" % [str(f["id"]), str(m["id"])],   # material-true icon
					"tint": str(m.get("light", "#cccccc")),   # UI accent only; the icon is already material-true
					"glow": str(r["glow"]),
				})
	return out


## "Iron Sword" → "Keen Iron Sword of the Ash Coast" as rarity climbs. Affixes
## are picked deterministically by index so a given id always names the same.
func _item_name(f: Dictionary, m: Dictionary, r: Dictionary, prefixes: Array, suffixes: Array, idx: int) -> String:
	var parts: Array = ["%s %s" % [str(m.get("name", "")), str(f.get("name", ""))]]
	if int(r.get("affix", 0)) >= 1 and not prefixes.is_empty():
		parts.push_front(str(prefixes[idx % prefixes.size()]))
	if int(r.get("affix", 0)) >= 2 and not suffixes.is_empty():
		parts.append(str(suffixes[idx % suffixes.size()]))
	return " ".join(parts).strip_edges()


func _base_value(kind: String, tier: int) -> int:
	return (12 if kind == "weapon" else 9) * maxi(1, tier)


## Map a class to the kit archetype whose loadout best fits it.
const CLASS_ARCHETYPE := {
	"Fighter": "warrior", "Barbarian": "warrior",
	"Paladin": "defender", "Cleric": "defender",
	"Rogue": "skirmisher", "Monk": "skirmisher", "Bard": "skirmisher",
	"Ranger": "ranger",
	"Druid": "caster", "Wizard": "caster", "Sorcerer": "caster", "Warlock": "caster",
}


func archetype_for_class(cls: String) -> String:
	return str(CLASS_ARCHETYPE.get(cls, "warrior"))


## Starting archetypes and the weapon they favour. Keyword-matched against THIS
## world's actual form names (LLM form ids differ per world), so a caster gets
## the staff-like thing whatever it is called, and falls back to any weapon.
const ARCHETYPES := [
	{"id": "warrior", "name": "Warrior", "want": ["sword", "blade", "axe", "mace", "spear"]},
	{"id": "defender", "name": "Defender", "want": ["hammer", "mace", "maul", "shield"]},
	{"id": "skirmisher", "name": "Skirmisher", "want": ["dagger", "knife", "claw", "sword"]},
	{"id": "ranger", "name": "Ranger", "want": ["bow", "sling", "gun", "rifle", "throw"]},
	{"id": "caster", "name": "Caster", "want": ["staff", "wand", "rod", "tome", "focus"]},
]


## Assemble one loadout per archetype from the asset language's forms. Kits store
## catalogue ITEM IDS (form.material.rarity), so they resolve straight to the
## catalogue and share its base art — no separate art, no drift.
func _build_kits(assets: Dictionary) -> Dictionary:
	var forms := _forms(assets)
	var weapons := forms.filter(func(f): return str(f["kind"]) == "weapon")
	var armors := forms.filter(func(f): return str(f["kind"]) == "armor")
	if weapons.is_empty() and armors.is_empty():
		return {}
	# Starting gear is humble: the lowest-tier material, common rarity.
	var mats: Array = assets.get("materials", []) if assets.get("materials") is Array else []
	var mat_id := "iron"
	if not mats.is_empty():
		var cheapest = mats[0]
		for m in mats:
			if m is Dictionary and int(m.get("tier", 9)) < int(cheapest.get("tier", 9)):
				cheapest = m
		mat_id = str(cheapest.get("id", "iron"))
	var out := {}
	for a in ARCHETYPES:
		var w := _match_form(weapons, a["want"])
		var items: Array = []
		if w != "":
			items.append("%s.%s.%s" % [w, mat_id, "common"])
		# Up to three armor pieces, whatever the world has.
		for i in mini(armors.size(), 3):
			items.append("%s.%s.%s" % [str(armors[i]["id"]), mat_id, "common"])
		if not items.is_empty():
			out[str(a["id"])] = {"name": str(a["name"]), "items": items}
	return out


## First form whose id or name contains any wanted keyword; else the first form.
func _match_form(forms: Array, want: Array) -> String:
	for kw in want:
		for f in forms:
			var hay := (str(f["id"]) + " " + str(f["name"])).to_lower()
			if hay.contains(str(kw).to_lower()):
				return str(f["id"])
	return str(forms[0]["id"]) if not forms.is_empty() else ""


# ── What the rest of the game asks ─────────────────────────────────────────
## The style guide for a world, or {} when it has never been compiled.
func style_for(world_id: String) -> Dictionary:
	var s = read_pack(world_id).get("style")
	return s if s is Dictionary else {}


## The line appended to EVERY image prompt for this world — the single
## strongest defence against style drift across a long compile.
func prompt_anchor(world_id: String) -> String:
	return str(style_for(world_id).get("prompt_anchor", ""))


func assets_for(world_id: String) -> Dictionary:
	var a = read_pack(world_id).get("assets")
	return a if a is Dictionary else {}


## The compiled item catalogue (form×material×rarity records), or [] if the
## world was never seeded. This is the spine loot is rolled from.
func catalogue_for(world_id: String) -> Array:
	var p := "%s/data/items.json" % world_dir(world_id)
	if not FileAccess.file_exists(p):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Array else []


## Roll one item from the world's catalogue, rarity-weighted. `luck` (0..1)
## nudges the roll toward the rare end. Applies a random treatment for flavour.
## Returns {} if the world has no catalogue. rng lets callers stay deterministic.
func roll_item(world_id: String, rng: RandomNumberGenerator = null, luck := 0.0) -> Dictionary:
	var cat := catalogue_for(world_id)
	if cat.is_empty():
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# Weighted rarity pick (luck scales the rare tiers up).
	var want := _roll_rarity(rng, luck)
	var pool := cat.filter(func(it): return str(it.get("rarity", "")) == want)
	if pool.is_empty():
		pool = cat
	var item: Dictionary = (pool[rng.randi_range(0, pool.size() - 1)] as Dictionary).duplicate(true)
	_apply_treatment(item, world_id, rng)
	return item


func _roll_rarity(rng: RandomNumberGenerator, luck: float) -> String:
	var total := 0.0
	var weights: Array = []
	for r in RARITIES:
		# luck lifts higher tiers: multiply weight by (1 + luck*affix*2).
		var w := float(r["weight"]) * (1.0 + clampf(luck, 0.0, 1.0) * float(r["affix"]) * 2.0)
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for i in RARITIES.size():
		pick -= weights[i]
		if pick <= 0.0:
			return str(RARITIES[i]["id"])
	return str(RARITIES[0]["id"])


## Stamp a treatment (wear/blessing) from the asset language onto a rolled item,
## adjusting its display name. Treatments are rolled, never baked, so the same
## catalogue record can drop clean, worn, or blessed.
func _apply_treatment(item: Dictionary, world_id: String, rng: RandomNumberGenerator) -> void:
	var treats = assets_for(world_id).get("treatments")
	if not (treats is Array) or treats.is_empty():
		return
	var t = treats[rng.randi_range(0, treats.size() - 1)]
	if t is Dictionary and str(t.get("id", "")) != "clean":
		item["treatment"] = str(t.get("id", ""))
		item["name"] = "%s %s" % [str(t.get("name", "")), str(item.get("name", ""))]


## Absolute path to a (form × material) icon in this world's package (may not
## exist yet if the GPU parts stage hasn't run). Prefer an item record's `art`
## field; this is the constructor for callers that only hold form+material ids.
func part_art_path(world_id: String, form_id: String, material_id: String) -> String:
	return "%s/art/parts/%s.%s.png" % [world_dir(world_id), form_id, material_id]


## The material-true icon for a catalogue item, loaded from the active world's
## package and cached. Returns null if the item carries no art or the file isn't
## painted yet (caller falls back to a legacy generated icon).
## The largest an item icon is ever drawn (a 96px socket on a hi-dpi pass).
const ICON_PX := 256
var _tex_cache := {}

func item_texture(item: Dictionary) -> Texture2D:
	var rel := str(item.get("art", ""))
	if rel == "":
		return null
	return _load_tex("%s/%s" % [world_dir(GameState.world_id()), rel], ICON_PX)


## Enchantment/treatment tints. Rarity is already a draw-time glow; treatments
## touched only names and stats, so ten treatments over 500 baked shapes rendered
## identically and the combinatorics existed on paper only. A tint is applied at
## DRAW time — free, no second bake, and it composes with the rarity glow. Worlds
## invent their own treatment ids, so match by keyword like materials do.
const TREATMENT_TINTS := {
	"flame": [["flam", "burn", "ember", "sear", "ash", "flare", "scorch", "char"], Color(1.25, 0.82, 0.60)],
	"frost": [["frost", "ice", "cold", "rime", "chill", "froze", "frozen"], Color(0.72, 0.94, 1.25)],
	"venom": [["venom", "poison", "toxic", "blight"], Color(0.78, 1.20, 0.72)],
	"storm": [["storm", "shock", "volt", "thunder", "arc", "galv"], Color(0.82, 0.92, 1.30)],
	"blessed": [["bless", "holy", "sacred", "sun", "radiant", "anoint"], Color(1.28, 1.18, 0.80)],
	"cursed": [["curse", "wraith", "void", "shadow", "dread"], Color(0.72, 0.62, 0.92)],
	"worn": [["worn", "salt", "rust", "weather", "old", "tarnish", "wear", "age", "wind"], Color(0.86, 0.82, 0.74)],
	"blood": [["blood", "gore", "carn"], Color(1.20, 0.70, 0.70)],
}


## The colour an item's treatment paints it. White when it has none, or when the
## world invented a treatment we don't recognise — an unknown treatment must look
## ordinary, never wrong.
func treatment_modulate(item: Dictionary) -> Color:
	var t := str(item.get("treatment", "")).to_lower()
	if t == "":
		return Color.WHITE
	for key in TREATMENT_TINTS:
		for w in TREATMENT_TINTS[key][0]:
			if t.contains(str(w)):
				return TREATMENT_TINTS[key][1]
	return Color.WHITE


## The world's establishing key art (for world/tale cards, backdrops). null if
## the world isn't compiled/baked yet.
func key_art(world_id: String) -> Texture2D:
	return _load_tex("%s/art/key.png" % world_dir(world_id))


## The best baked surface to draw a CHART on. The minimap and the Atlas both
## asked `Art.texture_for(world_id)` — the art *cache* — which for a shipped
## world holds whatever environment plate happened to be painted last. That is
## why the Atlas rendered its location pins over a photograph of a tavern
## fireplace (R6 BUG-12): it was never a map, it was the room. A baked world has
## six genuine top-down plates in art/maps/; overhead ground reads as a chart,
## so use one of those and fall back to the establishing shot only if it must.
## R6 BUG-12, BLANK-02/05, PLAY-02, STR-05, AES-25.
func chart_art(world_id: String) -> Texture2D:
	var t := _load_tex("%s/art/chart.png" % world_dir(world_id))
	if t == null:
		t = _load_tex(battle_map_path(world_id, 0))
	return t if t != null else key_art(world_id)


## Load a package image into a cached texture; null if absent/unreadable.
##
## `max_px` downsamples on load. Item icons are baked at 1024² (the Director's
## call, to stay future-proof) but drawn at 64–96 px in a socket and ~20 px in a
## shop row. Handing the GPU a 1024² texture for a 20 px cell is worse on BOTH
## counts the audit raised: it aliases into visual noise (R6 AAA-18/BLANK-26)
## *and* it decodes and holds 4 MB per icon on the main thread (R6 LAT-25/26/27).
## Mipmaps then make every intermediate size clean. The masters on disk are
## untouched — this only changes what the renderer is asked to sample.
func _load_tex(full: String, max_px := 0) -> Texture2D:
	var ck := "%s@%d" % [full, max_px]
	if _tex_cache.has(ck):
		return _tex_cache[ck]
	if not FileAccess.file_exists(full):
		return null
	var img := Image.load_from_file(full)
	if img == null or img.is_empty():
		return null
	if max_px > 0 and maxi(img.get_width(), img.get_height()) > max_px:
		var s := float(max_px) / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	# R6 LAT-20: this cache had no ceiling, so a long session accumulated every
	# icon it ever drew. Cheap FIFO trim — the cost of a miss is one decode.
	if _tex_cache.size() > 220:
		for k in _tex_cache.keys().slice(0, 60):
			_tex_cache.erase(k)
	_tex_cache[ck] = tex
	return tex


## The material/rarity colours for an item record, as Godot Colors.
func item_tint(item: Dictionary) -> Color:
	return Color.from_string(str(item.get("tint", "#cccccc")), Color.WHITE)


func item_glow(item: Dictionary) -> Color:
	return Color.from_string(str(item.get("glow", "#9aa4b2")), Color.GRAY)


## The world's compiled creatures (bestiary-shaped entries), or [] if none.
func creatures_for(world_id: String) -> Array:
	return _read_roster(world_id, "creatures")


## The world's compiled NPCs (the named cast), or [] if none.
func npcs_for(world_id: String) -> Array:
	return _read_roster(world_id, "npcs")


func _read_roster(world_id: String, name: String) -> Array:
	var p := "%s/data/%s.json" % [world_dir(world_id), name]
	if not FileAccess.file_exists(p):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Array else []


## The world's compiled tactical layouts (terrain arrangements), or [] if none.
func layouts_for(world_id: String) -> Array:
	return _read_roster(world_id, "layouts")


## A random tactical layout for a fight — {name, terrain} — or {} if uncompiled.
func layout_for(world_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var ls := layouts_for(world_id)
	if ls.is_empty():
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return ls[rng.randi_range(0, ls.size() - 1)]


## Absolute path to a biome's top-down battle map (may not be painted yet).
func battle_map_path(world_id: String, biome_index: int) -> String:
	return "%s/art/maps/map-%d.png" % [world_dir(world_id), biome_index]


## A starting loadout resolved to full catalogue records, for an archetype id
## (warrior/defender/skirmisher/ranger/caster). [] if the world or kit is absent.
func kit_for(world_id: String, archetype: String) -> Array:
	var p := "%s/data/kits.json" % world_dir(world_id)
	if not FileAccess.file_exists(p):
		return []
	var kits = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (kits is Dictionary) or not kits.has(archetype):
		return []
	var ids = kits[archetype].get("items", [])
	if not (ids is Array):
		return []
	var by_id := {}
	for it in catalogue_for(world_id):
		by_id[str(it.get("id", ""))] = it
	var out: Array = []
	for id in ids:
		if by_id.has(str(id)):
			out.append(by_id[str(id)])
	return out

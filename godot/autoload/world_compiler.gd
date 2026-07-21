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

var _journal := {}   # world_id → {stage → true}


# ── Storage ────────────────────────────────────────────────────────────────
## The compiled package lives beside the world record, not in the art cache:
## compiled assets are CONTENT (they are the world's identity), never a cache
## the LRU may evict (design §6).
func world_dir(world_id: String) -> String:
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
func compile_seed(world: Dictionary) -> Dictionary:
	var wid := str(world.get("id", ""))
	if wid == "" or busy:
		return {}
	busy = true
	current_world = wid
	_ensure_dirs(wid)
	var pack := read_pack(wid)
	pack["id"] = wid
	pack["name"] = str(world.get("name", ""))
	pack["family"] = WorldSkin.family_of(world)
	pack["compiler"] = COMPILER_VERSION
	pack["forged_at"] = int(Time.get_unix_time_from_system())

	stage_started.emit("style", "Reading the world's own mind…")
	var style := await _stage_style_guide(world)
	pack["style"] = style
	stage_done.emit("style", not style.is_empty())

	stage_started.emit("assets", "Naming what things are made of…")
	var assets := await _stage_asset_language(world, style)
	pack["assets"] = assets
	stage_done.emit("assets", not assets.is_empty())

	pack["compile_state"] = SEEDED
	_write(wid, "world.json", pack)
	_journal[wid] = {"style": not style.is_empty(), "assets": not assets.is_empty()}
	compiled.emit(wid, SEEDED)

	# TIER B: the world's IDENTITY — key art then biome plates. GPU work, so it
	# runs after the seed is safely written; the world is PRESENTABLE the moment
	# key art lands. Skipped without a real backend (headless tests own no GPU).
	if not Api.test_mode:
		await _stage_identity(wid, world, style)
		pack = read_pack(wid)
		pack["compile_state"] = PRESENTABLE
		_write(wid, "world.json", pack)
		compiled.emit(wid, PRESENTABLE)
	busy = false
	return pack


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


## Request one image and wait for it to actually land (compile is sequential —
## one GPU). Copies it into the world package so it is CONTENT, not cache.
func _await_art(key: String, prompt: String, opts: Dictionary) -> void:
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
		_adopt(world_dir_key(key), key)


## Copy a painted asset into the world's package directory (content that never
## gets evicted). world_dir_key derives the package sub-path from the key kind.
func _adopt(dest_rel: String, key: String) -> void:
	if dest_rel == "" or current_world == "":
		return
	var src := Art.path_for(key)
	if not FileAccess.file_exists(src):
		return
	var dst := "%s/%s" % [world_dir(current_world), dest_rel]
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var img := Image.load_from_file(src)
	if img != null and not img.is_empty():
		img.save_png(dst)


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
 "materials": ["6 materials this world is BUILT from — be specific and evocative"],
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
 "materials": [{"id":"lowercase_id","name":"Display Name","dark":"#rrggbb","light":"#rrggbb","tier":1}],
 "treatments": [{"id":"lowercase_id","name":"Display Name","note":"how it changes the look"}],
 "weapon_forms": [{"id":"lowercase_id","name":"Display Name","prompt":"a short image-prompt phrase for this weapon shape"}],
 "armor_forms":  [{"id":"lowercase_id","name":"Display Name","prompt":"a short image-prompt phrase"}],
 "naming": {"prefix":["4 evocative prefixes"],"suffix":["4 suffixes, e.g. 'of the Ash Coast'"]}
}
Rules: 6 materials (tier 1-3, cheap to precious, colours must suit the world),
4 treatments (wear/age/blessing/damage), 6 weapon_forms, 4 armor_forms.
Every id lowercase_with_underscores. Names must sound like THIS world.""" % [
		str(world.get("name", "a world")), str(style.get("visual_language", "")),
		", ".join(mats), str(style.get("weapons", "")), str(style.get("armor", ""))]
	var got := await _ask_json(ask)
	if got.is_empty() or not (got.get("materials") is Array):
		return _fallback_assets(style)
	got["generated"] = true
	return got


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
		return _extract_json(str(r["text"]))
	return {}


func _extract_json(text: String) -> Dictionary:
	var s := text.strip_edges()
	var a := s.find("{")
	var b := s.rfind("}")
	if a == -1 or b <= a:
		return {}
	var parsed = JSON.parse_string(s.substr(a, b - a + 1))
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
		["#08161f", "#56eeea"], ["#241408", "#96602f"], ["#3c2806", "#fad060"]]
	for i in mini(mats.size(), 6):
		out.append({"id": str(mats[i]).to_lower().replace(" ", "_"), "name": str(mats[i]).capitalize(),
			"dark": ramp[i % ramp.size()][0], "light": ramp[i % ramp.size()][1], "tier": 1 + i / 2})
	return {
		"materials": out,
		"treatments": [{"id": "clean", "name": "Clean", "note": "as made"},
			{"id": "worn", "name": "Worn", "note": "scratched and dulled"},
			{"id": "blooded", "name": "Blooded", "note": "darkened, used"},
			{"id": "blessed", "name": "Blessed", "note": "faintly lit"}],
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

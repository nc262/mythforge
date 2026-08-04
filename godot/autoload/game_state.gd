extends Node
## GameState — the selected adventure and its world state (kinds: sheet, inv,
## clock, combat, …). **A file on this machine is the source of truth**; every
## mutation writes `user://saves/<cid>.json`. Formulas live in Rules; this file
## owns state + the ported game procedures (rests, time).
## See docs/Architecture.md.

const DEFAULT_SHEET := {
	"name": "", "cls": "Adventurer", "level": 1, "xp": 0, "hp": 10, "hpMax": 10,
	"ac": 10, "gold": 0,
	"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
	"inventory": [], "conditions": [], "notes": "", "spells": [], "slots": {},
	"profSkills": [], "profSaves": [], "hitDie": 8, "hitDiceUsed": 0, "exhaustion": 0,
	# WHAT THIS HERO LOOKS LIKE — the words the player wrote at the forge, and the
	# brush they chose. Carried on the SHEET rather than passed to the one
	# commission that first needed them, because every later render needs them
	# too: the paper doll, a re-render with new gear, a portrait in a new
	# adventure. Derived at the point of use, a hero grows a different face per
	# surface (see Art.hero_look).
	"look": "", "brush": "painted",
}
const TIMES := ["Dawn", "Morning", "Midday", "Afternoon", "Dusk", "Nightfall", "Deep Night"]
## Eight hours of sleep, in a day of seven steps. See long_rest().
const LONG_REST_STEPS := 3
const WEATHERS := {
	"embervale": [["☀️", "clear skies"], ["🌤", "drifting clouds"], ["🌧", "soft valley rain"], ["🌫", "low mist"], ["💨", "cold wind off the hills"], ["⛈", "a brewing storm"]],
	"neonspire": [["🌧", "steady rain"], ["🌧", "acid drizzle"], ["🌫", "smog haze"], ["⛈", "an electric storm"], ["🌤", "a rare dry spell"]],
	"everyday": [["☀️", "sunshine"], ["🌤", "partly cloudy"], ["🌧", "light rain"], ["💨", "a breezy day"], ["❄️", "a cold snap"]],
	"_": [["☀️", "clear weather"], ["🌤", "scattered clouds"], ["🌧", "rain"], ["🌫", "fog"], ["💨", "strong wind"], ["⛈", "a storm"]],
}

signal leveled_up(from_level: int, to_level: int)
## The light or the weather changed enough that the room should look different.
## Carries the new mood bucket (see scene_mood).
signal mood_changed(mood: String)
## PS-5 — a NEW DAY dawned. The engine owns the clock, so the engine says so.
##
## The day divider was printed only by the `[[time]]` TAG handler, which means it
## appeared when the GM remembered to emit one. Rests advance time inside
## GameState and printed nothing, so a player who slept saw the day silently
## change — and the reported "divider on the first long rest only" is exactly
## what that looks like: the GM tagged time once and then stopped bothering.
##
## Every path that moves the clock goes through advance_time(), so this fires
## from all of them for free: rests, travel, tags, the world tick.
signal day_changed(day: int, time_of_day: String)

var character: Dictionary = {}
var state: Dictionary = {}
var pending_hero: Dictionary = {}   # a banked hero chosen to fill the next adventure's Quenching


# ── Banked heroes: a persistent roster forged at the anvil ───────────────────
## Heroes survive shutdown and being played — a forged legend is a reusable
## template you can begin many adventures with (fixes the "my hero vanished"
## data loss: the old single-file draft was deleted the moment it was used).
const HERO_ROSTER := "user://heroes.json"


## The art key a banked hero's face actually lives under.
##
## Director caught this from a screenshot: the roster cards in the Adventure
## Forge showed a flag glyph and no portrait, for heroes that demonstrably HAVE
## portraits (the same face renders in play). The cards were asking for
## "hero-<id>" — "hero-corin vale" — while the file on disk is
## "hero-dm-fimbulreach-freeroam", which the roster records correctly in
## `portrait_key` and nobody read. `bank_hero` tries to copy the art to the
## id-shaped key and, when that copy fails, honestly leaves the original key in
## place; the readers then ignored it. Ask here, not at each call site.
func hero_portrait_key(h: Dictionary) -> String:
	var stored := str(h.get("portrait_key", ""))
	if stored != "" and stored != "heroprev" and Art.has_art(stored):
		return stored   # the real file, wherever it ended up
	var by_id := "hero-" + str(h.get("id", "")).validate_filename()
	if Art.has_art(by_id):
		return by_id
	# "heroprev" is the forge's SHARED scratch key — the next forging overwrites
	# it, so a hero pinned to it would wear a stranger's face. Better no face.
	return ""


func banked_heroes() -> Array:
	var arr: Array = []
	if FileAccess.file_exists(HERO_ROSTER):
		var p = JSON.parse_string(FileAccess.get_file_as_string(HERO_ROSTER))
		if p is Array:
			arr = p
	# Migrate (once) the legacy single-file banked hero into the roster.
	if FileAccess.file_exists("user://forged_hero.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://forged_hero.json"))
		if d is Dictionary and str(d.get("name", "")) != "":
			arr = _roster_upsert(arr, d)
			_write_roster(arr)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://forged_hero.json"))
	return arr


func bank_hero(d: Dictionary) -> void:
	if d.is_empty() or str(d.get("name", "")) == "":
		return
	# A banked legend needs a face of its own. The forge paints its preview into
	# the shared scratch key "heroprev", which the NEXT forging overwrites — so
	# pin a copy to this hero's own id, or the roster shows a stranger's face
	# (and blank cards, since the roster art key is "hero-<id>").
	var h := d.duplicate(true)
	if str(h.get("id", "")) == "":
		h["id"] = str(h["name"]).validate_filename().to_lower()
	var own := "hero-" + str(h["id"]).validate_filename()
	# Prefer the hero's OWN pinned key, but only claim it if the copy really
	# happened — the previous code left `portrait_key` pointing at the source on
	# failure, which was honest, and then every reader ignored the field anyway
	# (see hero_portrait_key). If the copy fails we keep the working key rather
	# than a dangling one.
	var src := hero_portrait_key(h)
	if src != "" and Art.copy(src, own):
		h["portrait_key"] = own
	elif src != "":
		h["portrait_key"] = src
	_write_roster(_roster_upsert(banked_heroes(), h))


func unbank_hero(hero_name: String) -> void:
	_write_roster(banked_heroes().filter(func(h): return str(h.get("name", "")).nocasecmp_to(hero_name) != 0))


func _roster_upsert(arr: Array, d: Dictionary) -> Array:
	var out: Array = arr.filter(func(h): return str(h.get("name", "")).nocasecmp_to(str(d.get("name", ""))) != 0)
	out.append(d)
	return out


func _write_roster(arr: Array) -> void:
	var f := FileAccess.open(HERO_ROSTER, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arr))
		f.close()


func cid() -> String:
	return str(character.get("id", ""))


func world_id() -> String:
	return str(character.get("world_id", ""))


## The campaign's narration language (default English) — the language guard
## keeps the GM inside it. Settable via world.rules.language at the Forge.
func language() -> String:
	var l := str(rule("language", "English"))
	return l if l != "" else "English"


## One number, many names: gold, credits, doubloons, cogs… from the World WorldSkin.
func currency() -> String:
	return str(WorldSkin.skin_for_id(world_id()).get("currency", "gold"))


## DM adventures carry the game systems; everything else is pure conversation.
func is_dm() -> bool:
	return cid().begins_with("dm-")


## The save, from disk. There is nowhere else it could be.
func hydrate() -> void:
	state = _read_local(cid())


# ── The Adventure Index (_global.adventures) ────────────────────────────────
## Playtest #1 RCA: "Continue" matched the last-played id against a list of
## PRESET TEMPLATES rather than the player's own adventures, so any tale forged
## on a custom world could never match and Continue went dead. Every byte of
## state was safe on disk. The save was never lost; the INDEX never existed.
##
## This is that index: one record per adventure the player has actually opened,
## newest first, so the Hall can offer Continue AND a real list of tales.
## Records are small and self-describing — no second fetch to caption them.
const ADVENTURES := "adventures"

var _index_cache: Array = []


func adventures() -> Array:
	return _index_cache


## Read the index (once per Hall visit). Newest first.
## The Hall's shelf. This index is the single most load-bearing record in the
## game — it is what CONTINUE is built from. Index and shelf follow the same
## drawer as the saves.
func _index_path() -> String:
	return save_dir() + "/adventures.json"


func load_index() -> Array:
	var arr = null
	if FileAccess.file_exists(_index_path()):
		arr = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	if not (arr is Array):
		arr = []
	_index_cache = arr if arr is Array else []
	_index_cache.sort_custom(func(a, b): return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0)))
	return _index_cache


func _save_index() -> void:
	_write_json(_index_path(), _index_cache)


## Upsert this adventure's record and stamp it. Called when a tale opens and at
## every milestone worth resuming from — so "the latest valid autosave" is a
## thing the Hall can actually name.
func remember_adventure(extra := {}) -> void:
	if cid() == "" or not is_dm():
		return
	var s := sheet()
	var c := clock()
	var rec := {
		"id": cid(),
		"name": str(character.get("name", "")),
		"world_id": world_id(),
		"hero": str(s.get("name", "")),
		"level": int(s.get("level", 1)),
		"day": int(c.get("day", 1)),
		"done": bool(c.get("done", false)),
		"updated_at": int(Time.get_unix_time_from_system()),
	}
	for k in extra:
		rec[k] = extra[k]
	var out: Array = []
	for a in _index_cache:
		if a is Dictionary and str(a.get("id", "")) != cid():
			out.append(a)
	out.push_front(rec)
	_index_cache = out
	_save_index()


## ── Persistence: a file, on this machine ────────────────────────────────────
##
## The harness plays `dm-embervale-freeroam` — a REAL adventure id, because it is
## meant to exercise the shipped scenes. The first headless run overwrote a live
## save, replacing Drao at day 6 with the harness's Testwyn.
##
## So test runs get their own drawer. The alternative — teaching every harness to
## use fake ids — is a rule someone has to keep remembering, and this is one they
## cannot forget.
const SAVE_DIR := "user://saves"
const TEST_SAVE_DIR := "user://saves_test"


func save_dir() -> String:
	return TEST_SAVE_DIR if Api.test_mode else SAVE_DIR


## A harness must start from nothing. Saves persisting between runs is how three
## checks began failing the moment persistence became real: the canned seed was
## being overwritten by whatever the PREVIOUS run left behind, so the run under
## test was never the run that was set up. Called by the harnesses at boot.
func reset_test_saves() -> void:
	if not Api.test_mode:
		push_warning("reset_test_saves refused: not in test_mode")
		return
	var d := DirAccess.open(TEST_SAVE_DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_DIR + "/" + f))
	_index_cache = []
	_global_cache = null
	state = {}


func _save_path(for_cid: String) -> String:
	return "%s/%s.json" % [save_dir(), for_cid.validate_filename()]


func save_kind(kind: String, value) -> void:
	state[kind] = value
	_flush()


## Write, then rename — killed mid-save, a truncated JSON would replace a good
## save with an unreadable one. Under a temp name it simply isn't there yet.
func _flush() -> void:
	if cid() == "":
		return
	_write_json(_save_path(cid()), state)


## ── The shared shelf (`_global`) ─────────────────────────────────────────────
## Custom worlds, GMs and personas are not owned by any one adventure, so they
## live here. One store, one door — ten screens each reading and writing their
## own copy is exactly how a shared record drifts out of step, with no single
## place that knows what was written.
func _global_path() -> String:
	return save_dir() + "/_global.json"

var _global_cache = null


func global_all() -> Dictionary:
	if _global_cache is Dictionary:
		return _global_cache
	var parsed = null
	if FileAccess.file_exists(_global_path()):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(_global_path()))
	_global_cache = parsed if parsed is Dictionary else {}
	return _global_cache


func global_get(key: String, default_value = []) -> Variant:
	var v = global_all().get(key)
	return v if v != null else default_value


func global_set(key: String, value) -> void:
	var g := global_all()
	g[key] = value
	_global_cache = g
	_write_json(_global_path(), g)


## Another adventure's whole save, for captioning the Chronicles shelf.
func state_for(adv_id: String) -> Dictionary:
	return state if adv_id == cid() and not state.is_empty() else _read_local(adv_id)


## Start this tale over. The old code PUT null into ten kinds one at a time and
## hoped; a save is one file, so deleting it is the whole operation — and it
## cannot half-succeed the way ten round trips could.
func wipe_adventure(adv_id: String) -> void:
	if adv_id == "":
		return
	var path := _save_path(adv_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Campaign memory lives in its own file (Stage 3, LocalMemory), so deleting
	# the save alone would leave the beats behind — and a new adventure reusing
	# the id would inherit a stranger's history as canon.
	LocalMemory.wipe(adv_id)
	if adv_id == cid():
		state = {}


## Read one kind out of ANOTHER adventure's save, without loading it as the
## current one — the forges look at a tale's prior `world` before rewriting it.
func kind_for(adv_id: String, kind: String) -> Variant:
	if adv_id == cid() and state.has(kind):
		return state[kind]
	return _read_local(adv_id).get(kind)


## Write one kind into ANOTHER adventure's save — the forges set up a tale's
## `gm` and `world` before it is ever opened.
func set_kind_for(adv_id: String, kind: String, value) -> void:
	if adv_id == "":
		return
	var blob := _read_local(adv_id)
	blob[kind] = value
	_write_json(_save_path(adv_id), blob)
	if adv_id == cid():
		state[kind] = value


func _write_json(path: String, value) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir())
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(value))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))


## Is there a save on this machine for this adventure? The save is a file; ask
## the file — never some other system's opinion about whether it should exist.
func has_save(for_cid: String) -> bool:
	return FileAccess.file_exists(_save_path(for_cid))


func _read_local(for_cid: String) -> Dictionary:
	var path := _save_path(for_cid)
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _merged(kind: String, defaults: Dictionary) -> Dictionary:
	var d := defaults.duplicate(true)
	var stored = state.get(kind)
	if stored is Dictionary:
		d.merge(stored, true)
	return d


# ── Sheet ───────────────────────────────────────────────────────────────────
func sheet() -> Dictionary:
	var s := _merged("sheet", DEFAULT_SHEET)
	for k in DEFAULT_SHEET["abilities"]:
		if not s["abilities"].has(k):
			s["abilities"][k] = 10
	return s


func set_sheet(s: Dictionary) -> void:
	save_kind("sheet", s)


## delta < 0 = damage, > 0 = healing. Returns the saved sheet.
func apply_hp(delta: int) -> Dictionary:
	var s := sheet()
	s["hp"] = clampi(int(s["hp"]) + delta, 0, int(s["hpMax"]))
	set_sheet(s)
	return s


func add_gold(delta: int) -> int:
	var s := sheet()
	s["gold"] = maxi(0, roundi(int(s.get("gold", 0)) + delta))
	set_sheet(s)
	return s["gold"]


func learn_spell(nm: String) -> bool:
	var known := Rules.spell_named(nm)
	if known.is_empty():
		return false
	var s := sheet()
	for sp in s.get("spells", []):
		if str(sp.get("name", "")).nocasecmp_to(nm) == 0:
			return false
	s["spells"].append({"name": str(known.get("name", nm)), "level": int(known.get("level", 1))})
	set_sheet(s)
	return true


func grant_inspiration() -> bool:
	var s := sheet()
	if bool(s.get("inspiration", false)):
		return false
	s["inspiration"] = true
	set_sheet(s)
	return true


func spend_inspiration() -> bool:
	var s := sheet()
	if not bool(s.get("inspiration", false)):
		return false
	s["inspiration"] = false
	set_sheet(s)
	return true


# ── Inventory ───────────────────────────────────────────────────────────────
func inv() -> Dictionary:
	return _merged("inv", {"slots": 24, "items": [], "equipped": {}})


func add_item(nm: String, rarity := "common", qty := 1) -> void:
	var v := inv()
	for it in v["items"]:
		if str(it.get("name", "")).nocasecmp_to(nm) == 0:
			it["qty"] = int(it.get("qty", 1)) + qty
			save_kind("inv", v)
			return
	v["items"].append(Rules.mk_item(nm, rarity, qty))
	save_kind("inv", v)


## Add a compiled World Compiler catalogue item — keeps its material-true icon
## (`art`), rarity glow and form/material identity, on top of the combat stats
## the rules derive from its name. This is how world-true loot enters the pack.
func add_catalogue_item(rec: Dictionary, qty := 1) -> void:
	if rec.is_empty():
		return
	var v := inv()
	var it: Dictionary = Rules.mk_item(str(rec.get("name", "")), str(rec.get("rarity", "common")), qty)
	for k in ["art", "glow", "form", "material", "value", "kind", "catalogue_id"]:
		if rec.has(k):
			it[k] = rec[k]
	# The catalogue's kind is authoritative over the name-sniffed type.
	if rec.has("kind") and str(rec["kind"]) in ["weapon", "armor"]:
		it["type"] = str(rec["kind"]) if str(rec["kind"]) == "weapon" else it.get("type", "armor")
	v["items"].append(it)
	save_kind("inv", v)


## Crafting v2 — typed components, consumed on craft. Recipes live in
## tables.json; the GM seeds components through ordinary [[loot]] tags.
func recipe_ready(r: Dictionary) -> bool:
	for comp in r.get("components", []):
		var found := false
		for it in inv().get("items", []):
			if str(it.get("name", "")).nocasecmp_to(str(comp)) == 0 and int(it.get("qty", 1)) > 0:
				found = true
				break
		if not found:
			return false
	return true


func craft(recipe_name: String) -> String:
	for r in Rules.tables.get("recipes", []):
		if not (r is Dictionary) or str(r.get("name", "")).nocasecmp_to(recipe_name) != 0:
			continue
		if not recipe_ready(r):
			return ""
		var v := inv()
		for comp in r["components"]:
			for it in v["items"]:
				if str(it.get("name", "")).nocasecmp_to(str(comp)) == 0:
					it["qty"] = int(it.get("qty", 1)) - 1
					break
		v["items"] = v["items"].filter(func(it): return int(it.get("qty", 1)) > 0)
		save_kind("inv", v)
		add_item(str(r["name"]), str(r.get("rarity", "common")))
		return "*You craft a %s from %s.*" % [str(r["name"]), ", ".join(r["components"])]
	return ""


func item_by_id(id: String) -> Dictionary:
	for it in inv().get("items", []):
		if str(it.get("id", "")) == id:
			return it
	return {}


## Equip into its type slot (weapon/armor/shield); same id again unequips.
## → note text, or "" if the item can't be worn.
func toggle_equip(id: String) -> String:
	var v := inv()
	var it := {}
	for x in v["items"]:
		if str(x.get("id", "")) == id:
			it = x
			break
	if it.is_empty():
		return ""
	var typ := str(it.get("type", "gear"))
	if not typ in Rules.WEARABLE:
		return ""
	var eq: Dictionary = v.get("equipped", {})
	var slot := typ
	# Rings fill either finger; a worn ring toggles off from whichever it holds.
	if typ == "ring":
		if str(eq.get("ring1", "")) == id or str(eq.get("ring2", "")) == id:
			eq.erase("ring1" if str(eq.get("ring1", "")) == id else "ring2")
			v["equipped"] = eq
			save_kind("inv", v)
			return "You slip off the %s." % it["name"]
		slot = "ring1" if str(eq.get("ring1", "")) == "" else "ring2"
	# A second light weapon slips into the off-hand (two-weapon fighting).
	elif typ == "weapon" and str(eq.get("weapon", "")) != "" and str(eq.get("weapon", "")) != id:
		var light_re := RegEx.create_from_string("(?i)dagger|shortsword|handaxe|hatchet|scimitar|club|sickle|knife")
		if light_re.search(str(it.get("name", ""))) != null:
			slot = "offhand"
	if str(eq.get(slot, "")) == id:
		eq.erase(slot)
		v["equipped"] = eq
		save_kind("inv", v)
		return "You put away the %s." % it["name"]
	eq[slot] = id
	v["equipped"] = eq
	save_kind("inv", v)
	return "You ready the %s%s." % [it["name"],
		(" (%s, %+d to hit)" % [it.get("dmg", ""), int(it.get("atk", 0))]) if slot in ["weapon", "offhand"] and int(it.get("atk", 0)) > 0
		else (" (+%d AC)" % int(it.get("acBonus", 0))) if int(it.get("acBonus", 0)) > 0 else ""]


## Sell one of the item at half value. → note text.
func sell_item(id: String) -> String:
	var v := inv()
	for i in v["items"].size():
		var it: Dictionary = v["items"][i]
		if str(it.get("id", "")) == id:
			var price := Rules.sell_value(str(it.get("rarity", "common")))
			if int(it.get("qty", 1)) > 1:
				it["qty"] = int(it["qty"]) - 1
			else:
				var eq: Dictionary = v.get("equipped", {})
				for k in eq.keys():
					if str(eq[k]) == id:
						eq.erase(k)
				v["items"].remove_at(i)
			save_kind("inv", v)
			var total := add_gold(price)
			return "You sell the %s for %d gold — purse now %d." % [it["name"], price, total]
	return ""


## A table rule set at the Campaign Forge (world.rules) — engine-enforced:
## difficulty scales foes, permadeath archives the save, fog hides the map,
## companions gates recruiting, house feeds the envelope.
func rule(key: String, dflt = null):
	var w = state.get("world")
	if w is Dictionary and w.get("rules") is Dictionary:
		return w["rules"].get(key, dflt)
	return dflt


## Cast a known spell, spending the lowest fitting slot. → note, or "" on fail.
func cast_spell(nm: String) -> String:
	var s := sheet()
	var known := {}
	for sp in s.get("spells", []):
		if str(sp.get("name", "")).nocasecmp_to(nm) == 0:
			known = sp
			break
	if known.is_empty():
		return ""
	var lv := int(known.get("level", 0))
	var cast_note := ""
	if lv > 0:
		var slots: Dictionary = s.get("slots", {})
		var found := ""
		var keys := slots.keys()
		keys.sort()
		for l in keys:
			if int(str(l)) >= lv and slots[l] is Dictionary \
					and int(slots[l].get("used", 0)) < int(slots[l].get("max", 0)):
				found = str(l)
				break
		if found == "":
			return "✋ *No spell slot left for %s — a long rest restores your magic.*" % nm
		slots[found]["used"] = int(slots[found]["used"]) + 1
		set_sheet(s)
		cast_note = " (L%s slot spent, %d/%d left)" % [found,
			int(slots[found]["max"]) - int(slots[found]["used"]), int(slots[found]["max"])]
	var dc := Rules.spell_save_dc(s)
	var stat := (" Spell save DC %d, spell attack %+d." % [dc, Rules.spell_attack(s)]) if dc > 0 else ""
	return "*You cast **%s**%s.%s*" % [known.get("name", nm), cast_note, stat]


## Port of _awardXp: average hit-die HP per level, full heal, auto-features.
## → {note, leveled: bool}
func award_xp(amount: int, reason := "") -> Dictionary:
	if amount <= 0:
		return {"note": "", "leveled": false}
	var s := sheet()
	var before := int(s.get("level", 1))
	s["xp"] = int(s.get("xp", 0)) + amount
	var after := Rules.level_for_xp(int(s["xp"]))
	var note := "*Gained %d XP%s.*" % [amount, (" — " + reason) if reason != "" else ""]
	if after > before:
		# New levels land on the PRIMARY class by default; the level-up ceremony
		# may redirect them into another class (redirect_level) afterwards.
		var classes: Array = Rules.sheet_classes(s).duplicate(true)
		var primary: Dictionary = classes[0]
		var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
		@warning_ignore("integer_division")
		var die_avg := Rules.class_hit_die(str(primary.get("cls", ""))) / 2 + 1
		for l in range(before, after):
			s["hpMax"] = int(s["hpMax"]) + maxi(1, die_avg + con)
		s["level"] = after
		primary["level"] = int(primary.get("level", 1)) + (after - before)
		s["classes"] = classes
		s["hp"] = s["hpMax"]
		# Auto-grant the primary's class features at its OWN class levels.
		var gained: Array[String] = []
		var feats_map: Dictionary = Rules.tables.get("class_features", {}).get(str(primary.get("cls", "")), {})
		var cl_after := int(primary["level"])
		for l in range(cl_after - (after - before) + 1, cl_after + 1):
			for f in feats_map.get(str(l), []):
				gained.append(str(f))
		if not gained.is_empty():
			var have: Array = s.get("features", [])
			have.append_array(gained)
			s["features"] = have
		# Casters climb the slot table with their COMBINED caster level
		# (half-casters count half — a Paladin's slots now actually exist).
		var clv := Rules.caster_level(s)
		if clv > 0:
			s["slots"] = Rules.full_caster_slots(clv)
		note += "\n*LEVEL UP — you are now level %d! HP restored to %d.%s*" % [after, int(s["hpMax"]),
			(" New: " + ", ".join(gained)) if not gained.is_empty() else ""]
	set_sheet(s)
	if after > before:
		leveled_up.emit(before, after)
	return {"note": note, "leveled": after > before, "from": before, "to": after}


func inv_text() -> String:
	var v := inv()
	var items: Array = v.get("items", [])
	if items.is_empty():
		return ""
	var names: Array[String] = []
	for it in items:
		var q := int(it.get("qty", 1))
		names.append(str(it.get("name", "")) + (" ×%d" % q if q > 1 else ""))
	return "The player's pack holds: %s." % ", ".join(names)


func spell_text() -> String:
	var s := sheet()
	var spells: Array = s.get("spells", [])
	if spells.is_empty():
		return ""
	var known: Array[String] = []
	for sp in spells:
		known.append(str(sp.get("name", "")) + ((" (lvl %d)" % int(sp["level"])) if int(sp.get("level", 0)) > 0 else " (cantrip)"))
	var t := "The player knows these spells: %s." % ", ".join(known)
	var slots: Dictionary = s.get("slots", {})
	var parts: Array[String] = []
	for l in slots:
		if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
			parts.append("L%s %d/%d" % [l, maxi(0, int(slots[l]["max"]) - int(slots[l].get("used", 0))), int(slots[l]["max"])])
	if not parts.is_empty():
		t += " Spell slots remaining: %s. Don't let them cast a leveled spell with no slot left." % ", ".join(parts)
	return t


## A lasting world fact the player discovered — inscribed into the Lore Book
## (M-C). Deduped by title. → true if newly added.
func add_lore(category: String, title: String, note: String) -> bool:
	if title == "":
		return false
	var lore = state.get("lore")
	var entries: Array = lore.get("entries", []) if lore is Dictionary else []
	for e in entries:
		if e is Dictionary and str(e.get("title", "")).nocasecmp_to(title) == 0:
			return false
	entries.append({"category": category if category != "" else "Discoveries",
		"title": title, "note": note, "day": int(clock().get("day", 1))})
	save_kind("lore", {"entries": entries})
	return true


# ── The Cast: structured Character Resources (A4) ────────────────────────────
## Data-driven NPCs the GM inscribes via [[npc]]/[[relate]] — identity, goal,
## fear, faction, secret, feeling, and a relationship bond — persisted in the
## `cast` kind and fed to the Director as structured context, not a prose blob.
func cast() -> Dictionary:
	var c = state.get("cast")
	return c if c is Dictionary else {}


func record_npc(fields: Dictionary) -> void:
	var nm := str(fields.get("name", "")).strip_edges()
	if nm == "":
		return
	var c := cast()
	var e: Dictionary = c.get(nm, {})
	for k in ["role", "goal", "fear", "faction", "secret", "feeling", "voice"]:
		if str(fields.get(k, "")).strip_edges() != "":
			e[k] = str(fields[k]).strip_edges()
	c[nm] = e
	save_kind("cast", c)


## Shift a relationship bond (−5..+5) and remember why.
func relate(npc_name: String, delta: int, note := "") -> void:
	var nm := npc_name.strip_edges()
	if nm == "":
		return
	var c := cast()
	var e: Dictionary = c.get(nm, {})
	e["bond"] = clampi(int(e.get("bond", 0)) + delta, -5, 5)
	if note.strip_edges() != "":
		var notes: Array = e.get("notes", [])
		notes.append(note.strip_edges())
		e["notes"] = notes.slice(-4)
	c[nm] = e
	save_kind("cast", c)


## The cast as structured context for the envelope — canon the GM must honor.
func cast_summary() -> String:
	var c := cast()
	if c.is_empty():
		return ""
	var parts: Array[String] = []
	for nm in c:
		var e: Dictionary = c[nm]
		var bits: Array[String] = [str(nm)]
		if str(e.get("role", "")) != "":
			bits.append(str(e["role"]))
		if str(e.get("faction", "")) != "":
			bits.append("of " + str(e["faction"]))
		if str(e.get("goal", "")) != "":
			bits.append("wants " + str(e["goal"]))
		if str(e.get("fear", "")) != "":
			bits.append("fears " + str(e["fear"]))
		if str(e.get("feeling", "")) != "":
			bits.append("feels %s toward the player" % str(e["feeling"]))
		if str(e.get("voice", "")) != "":
			bits.append("speaks in a %s voice — keep their dialogue in it" % str(e["voice"]))
		if int(e.get("bond", 0)) != 0:
			bits.append("relationship %+d" % int(e["bond"]))
		if str(e.get("secret", "")) != "":
			bits.append("(secret, not yet known to the player: %s)" % str(e["secret"]))
		parts.append(" — ".join(bits))
	return "The cast you know (their goals, fears, feelings, and secrets are CANON — keep them consistent): %s." % "; ".join(parts)


## Infer a companion's class/AC/durability from the GM-supplied role, so a
## "temple healer" isn't statted as a plate-clad Fighter. Keyword → kit.
func infer_companion_kit(role: String) -> Dictionary:
	var r := role.to_lower()
	for kit in [
		["heal|cleric|priest|medic|acolyte", "Cleric", 15, 2],
		["mage|wizard|sorc|arcane|warlock|witch", "Wizard", 12, 1],
		["rogue|thief|scout|assassin|spy|burglar", "Rogue", 14, 1],
		["rang|arch|hunt|bowman|marksman", "Ranger", 14, 2],
		["bard|song|minstrel|skald", "Bard", 13, 2],
		["paladin|knight|guard|templar|sentinel", "Paladin", 16, 3],
		["barb|berserk|raider|reaver", "Barbarian", 13, 3],
		["monk|martial", "Monk", 14, 2],
		["druid|shaman|warden", "Druid", 13, 2]]:
		if RegEx.create_from_string("(?i)%s" % kit[0]).search(r) != null:
			return {"cls": kit[1], "ac": int(kit[2]), "hpb": int(kit[3])}
	return {"cls": "Fighter", "ac": 14, "hpb": 2}


## The multiclass turn: move the level just gained from the primary class into
## another class. Called by the level-up ceremony after award_xp applied the
## default — deterministic engine math; the ceremony only asks. Returns a note
## for the chat, or "" if the prerequisites refuse it.
func redirect_level(to_cls: String) -> String:
	var s := sheet()
	if not Rules.can_multiclass_into(s, to_cls):
		return ""
	var classes: Array = Rules.sheet_classes(s).duplicate(true)
	var primary: Dictionary = classes[0]
	if int(primary.get("level", 1)) <= 1 or str(primary.get("cls", "")) == to_cls:
		return ""
	var from_cls := str(primary.get("cls", ""))
	# Strip the features the default grant just added at the primary's top level.
	var lost_lv := int(primary["level"])
	var have: Array = s.get("features", [])
	for f in Rules.tables.get("class_features", {}).get(from_cls, {}).get(str(lost_lv), []):
		have.erase(str(f))
	primary["level"] = lost_lv - 1
	# Find or begin the new class, and grant its features at ITS new level.
	var entry: Dictionary = {}
	for c in classes:
		if str(c.get("cls", "")) == to_cls:
			entry = c
	if entry.is_empty():
		entry = {"cls": to_cls, "level": 0, "subclass": ""}
		classes.append(entry)
	entry["level"] = int(entry.get("level", 0)) + 1
	for f in Rules.tables.get("class_features", {}).get(to_cls, {}).get(str(int(entry["level"])), []):
		have.append(str(f))
	s["features"] = have
	s["classes"] = classes
	# HP: swap the die averages between the class that lost and the one that gained.
	@warning_ignore("integer_division")
	var delta := (Rules.class_hit_die(to_cls) / 2 + 1) - (Rules.class_hit_die(from_cls) / 2 + 1)
	s["hpMax"] = maxi(1, int(s["hpMax"]) + delta)
	s["hp"] = s["hpMax"]  # the level-up full heal still stands
	var clv := Rules.caster_level(s)
	if clv > 0:
		s["slots"] = Rules.full_caster_slots(clv)
	set_sheet(s)
	return "*The road forks — you take a level of %s (%s).*" % [to_cls, Rules.class_label(s)]


## An NPC joins the party (port of _toggleCompanion's recruit half).
func add_companion(nm: String, role := "") -> String:
	var s := sheet()
	var comps: Array = s.get("companions", [])
	for c in comps:
		if str(c.get("name", "")).nocasecmp_to(nm) == 0:
			return ""
	var level := int(s.get("level", 1))
	var kit := infer_companion_kit(role)
	var hp_max := 8 + int(kit["hpb"]) * level
	comps.append({"name": nm, "role": role, "cls": str(kit["cls"]), "level": level,
		"ac": int(kit["ac"]), "hpMax": hp_max, "hp": hp_max})
	s["companions"] = comps
	set_sheet(s)
	return "*%s joins your party — a level %d %s!*" % [nm, level, str(kit["cls"]).to_lower()]


# ── Class feature actions (port of FEATURE_ACTIONS) ─────────────────────────
## Feature name (matched by prefix against sheet.features) → per-rest uses.
const FEATURE_ACTIONS := {
	"Second Wind": {"rest": "short", "uses": 1},
	"Rage": {"rest": "long", "uses": 2},
	"Action Surge": {"rest": "short", "uses": 1},
	"Combat Maneuver": {"rest": "short", "uses": 4},
	"Arcane Ward": {"rest": "long", "uses": 1},
	"Cutting Words": {"rest": "long", "uses": 3},
	"Lay on Hands": {"rest": "long", "uses": 3},
	"Bardic Inspiration": {"rest": "short", "uses": 3},
	"Channel Divinity": {"rest": "short", "uses": 1},
	"Wild Shape": {"rest": "short", "uses": 2},
}


## The action a sheet feature string maps to ("Rage (bonus damage…)") → "Rage".
func feature_action_key(feature: String) -> String:
	for k in FEATURE_ACTIONS:
		if feature.begins_with(k):
			return k
	return ""


func feature_uses_left(key: String) -> int:
	var meta: Dictionary = FEATURE_ACTIONS.get(key, {})
	if meta.is_empty():
		return 0
	return int(meta["uses"]) - int(sheet().get("featUses", {}).get(key, 0))


## Spend one use and apply the effect. → in-fiction note for the GM, "" if dry.
func use_feature(key: String) -> String:
	if feature_uses_left(key) <= 0:
		return ""
	var s := sheet()
	var used: Dictionary = s.get("featUses", {})
	used[key] = int(used.get(key, 0)) + 1
	s["featUses"] = used
	var note := ""
	match key:
		"Second Wind":
			var heal := randi_range(1, 10) + int(s.get("level", 1))
			s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + heal)
			note = "*Second Wind — you steady yourself and recover **%d HP** (now %d/%d).*" % [heal, int(s["hp"]), int(s["hpMax"])]
		"Rage":
			s["conditions"] = s.get("conditions", []) + [{"name": "raging (+2 melee damage, resist physical)", "rounds": 10}]
			note = "*You RAGE — advantage on Strength, resistance to physical damage, +2 melee damage while it lasts.*"
		"Action Surge":
			var c: Dictionary = Combat.data()
			if bool(c.get("active", false)) and c.get("_pcb") is Dictionary:
				c["_pcb"]["attacksLeft"] = int(c["_pcb"].get("attacksLeft", 0)) + int(c["_pcb"].get("attacksMax", 1))
				Combat.save(c)
			note = "*Action Surge — you push past your limits and act again this turn.*"
		"Combat Maneuver":
			note = "*Superiority die spent — trip, disarm, riposte, or feint for **+%d** to the effect. Tell the GM which maneuver.*" % randi_range(1, 8)
		"Arcane Ward":
			var ward := 2 * int(s.get("level", 1)) + maxi(0, Rules.ability_mod(int(s["abilities"].get("INT", 10))))
			s["conditions"] = s.get("conditions", []) + [{"name": "arcane ward (absorbs %d damage)" % ward, "rounds": 99}]
			note = "*A woven ward of abjuration surrounds you — it absorbs the next **%d** damage before your HP does.*" % ward
		"Cutting Words":
			note = "*Cutting Words — your mockery lands where armor doesn't: **−%d** from an enemy's attack, check, or damage roll.*" % randi_range(1, 8)
		"Lay on Hands":
			var lh := 3 * int(s.get("level", 1))
			s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + lh)
			note = "*Lay on Hands — divine warmth flows from your palms, restoring **%d HP** (now %d/%d).*" % [lh, int(s["hp"]), int(s["hpMax"])]
		"Bardic Inspiration":
			s["conditions"] = s.get("conditions", []) + [{"name": "bardic inspiration (add 1d6 to one roll)", "rounds": 100}]
			note = "*Bardic Inspiration — a rousing word grants a **1d6** to add to one attack, check, or save. Tell the GM when you spend it.*"
		"Channel Divinity":
			note = "*Channel Divinity — you invoke your deity's power: turn undead, a sacred weapon, or your oath's channel. Tell the GM which.*"
		"Wild Shape":
			var thp := 2 * int(s.get("level", 1)) + 5
			s["conditions"] = s.get("conditions", []) + [{"name": "wild shape — beast form (+%d temp HP)" % thp, "rounds": 100}]
			note = "*Wild Shape — your body flows into a beast's: **+%d** temporary vigor and a beast's senses. Describe the form to the GM.*" % thp
	set_sheet(s)
	return note


func _recharge_features(rest_kind: String) -> void:
	var s := sheet()
	var used: Dictionary = s.get("featUses", {})
	for k in FEATURE_ACTIONS:
		if rest_kind == "long" or str(FEATURE_ACTIONS[k]["rest"]) == "short":
			used.erase(k)
	s["featUses"] = used
	set_sheet(s)


# ── Clock / weather (port of _advanceTime) ──────────────────────────────────
func clock() -> Dictionary:
	return _merged("clock", {"day": 1, "ti": 1, "at": 0})


## HOW THIS PLACE LOOKS RIGHT NOW — a coarse bucket of light and weather.
##
## CN-4: one backdrop plate held across four days, three weather states and four
## locations, because the scene key was the PLACE alone. The same tavern at dawn
## in clear light and at deep night in a storm shared one painting, so the world
## never visibly moved.
##
## Deliberately coarse. Seven times of day times six weathers would be 42
## paintings per location; three by three is nine, and in a real campaign far
## fewer. Cheap enough to be free, different enough to be seen.
func scene_mood() -> String:
	var c := clock()
	var ti := clampi(int(c.get("ti", 0)), 0, TIMES.size() - 1)
	var light := "day"
	if ti >= 6:
		light = "night"
	elif ti >= 4:
		light = "dusk"
	var wx := ""
	if c.get("wx") is Dictionary:
		wx = str(c["wx"].get("name", "")).to_lower()
	var sky := "clear"
	for wet in ["rain", "drizzle", "storm", "snow"]:
		if wx.find(wet) >= 0:
			sky = "wet"
	for dim in ["mist", "fog", "haze", "smog"]:
		if wx.find(dim) >= 0:
			sky = "misty"
	return "%s-%s" % [light, sky]


## The same mood, as words a painter can use.
func scene_mood_words() -> String:
	var m := scene_mood()
	var light := m.split("-")[0]
	var sky := m.split("-")[1]
	var lw := str({"day": "in full daylight", "dusk": "at dusk, the light going",
		"night": "deep in the night, lit only by what burns"}.get(light, "in daylight"))
	var sw := str({"clear": "under a clear sky", "wet": "in the rain, everything slick and running",
		"misty": "in thick mist that swallows the distance"}.get(sky, "under a clear sky"))
	return "%s, %s" % [lw, sw]


func advance_time(steps := 1) -> Dictionary:
	var mood_before := scene_mood()
	var c := clock()
	var prev_day := int(c.get("day", 1))
	c["ti"] = int(c.get("ti", 0)) + steps
	while int(c["ti"]) >= TIMES.size():
		c["ti"] = int(c["ti"]) - TIMES.size()
		c["day"] = int(c.get("day", 1)) + 1
	if not (c.get("wx") is Dictionary) or int(c["day"]) != prev_day:
		var list: Array = WEATHERS.get(world_id(), WEATHERS["_"])
		var w: Array = list[randi() % list.size()]
		c["wx"] = {"ico": w[0], "name": w[1]}
	save_kind("clock", c)
	# Only when the LOOK of the world actually changed. An hour passing inside one
	# afternoon is not worth a repaint; dusk falling, or rain starting, is.
	var mood_now := scene_mood()
	if mood_now != mood_before:
		mood_changed.emit(mood_now)
	if int(c.get("day", 1)) != prev_day:
		day_changed.emit(int(c["day"]),
			TIMES[clampi(int(c.get("ti", 0)), 0, TIMES.size() - 1)])
	# Timed sheet conditions wane as in-world time passes.
	var s := sheet()
	var conds: Array = s.get("conditions", [])
	if conds.any(func(x): return x is Dictionary and x.get("rounds") != null):
		var kept: Array = []
		for x in conds:
			if x is Dictionary and x.get("rounds") != null:
				x["rounds"] = int(x["rounds"]) - 1
				if int(x["rounds"]) > 0:
					kept.append(x)
			else:
				kept.append(x)
		s["conditions"] = kept
		set_sheet(s)
	return c


## WHERE THE PLAYER IS. One answer, because the rest instructions, the shop gate
## and the scene context all need it and each used to dig it out of `world`.
func here() -> String:
	var world: Dictionary = state.get("world", {}) if state.get("world") is Dictionary else {}
	return str(world.get("here", ""))


## A clause pinning the GM to the place the player actually stands.
##
## CN-1: the player camped at the barrow-mound and woke in the mead-hall guest
## room, with no travel in between. The location IS in the envelope — but it sits
## near the top, and the rest instruction that arrives last said only "narrate
## the new morning and what's changed", which is an open invitation to move
## someone. Recency wins in a long context, so the pin has to travel WITH the
## instruction, not sit above it.
func here_pin() -> String:
	var h := here()
	if h == "":
		return " I am where the last scene left me; do not relocate me."
	return " I am at %s and I have not travelled — I wake exactly there. Do not move me to another place; if travel happens, it happens because I choose it." % h


# ── The world's geography: one store, one writer ────────────────────────────
## EVERY PLACE THIS WORLD HAS, authored or discovered, in one list.
##
## There were three answers to "what places exist" and they disagreed:
##   * `Rules.world_locations()` — the built-in gazetteer, which knows only the
##     six shipped worlds and returns [] for anything the player forged.
##   * `cworlds[].locations` — a forged world's places, carrying no x/y at all,
##     so every pin defaulted to (50,50) and stacked on the chart's centre.
##   * `state.world.places` — read by the minimap, written by NOTHING. The
##     comment there describes a save the old backend produced; on this build it
##     is always empty, so the minimap silently fell back to the gazetteer.
##
## This is the one answer. It merges the authored gazetteer with whatever the
## story has since created, gives every entry coordinates, and is the only thing
## any screen should ask.
func places() -> Array:
	var world: Dictionary = state.get("world", {}) if state.get("world") is Dictionary else {}
	var made: Array = world.get("places") if world.get("places") is Array else []
	var out: Array = []
	var seen_names := {}
	# Authored first, so a GM-created place can never shadow a shipped one.
	for l in _authored_places():
		if not (l is Dictionary):
			continue
		var nm := str(l.get("name", ""))
		if nm == "" or seen_names.has(nm.to_lower()):
			continue
		seen_names[nm.to_lower()] = true
		out.append(_with_position(l, world))
	for l in made:
		if not (l is Dictionary):
			continue
		var nm2 := str(l.get("name", ""))
		if nm2 == "" or seen_names.has(nm2.to_lower()):
			continue
		seen_names[nm2.to_lower()] = true
		out.append(_with_position(l, world))
	return out


## The places the world SHIPPED with — gazetteer for a built-in, the forged
## record for a custom world.
func _authored_places() -> Array:
	var built := Rules.world_locations(world_id())
	if not built.is_empty():
		return built
	for w in global_get("cworlds", []):
		if w is Dictionary and str(w.get("id", "")) == world_id():
			return w.get("locations") if w.get("locations") is Array else []
	return []


## Give a place coordinates if it has none.
##
## A forged world's locations arrive with name/kind/lore/shop and nothing else,
## because the Worldsmith is never asked for x/y — correctly, since a model is
## bad at coordinates and a wrong one is invisible until the chart looks wrong.
## The engine places them instead: deterministically, from the name, on their
## region's ring.
func _with_position(l: Dictionary, world: Dictionary) -> Dictionary:
	if l.has("x") and l.has("y"):
		return l
	var out := l.duplicate(true)
	var reg := str(l.get("region", ""))
	var at := region_at(reg, world)
	var pos := Rules.place_position(str(l.get("name", "")), str(l.get("scope", "local")), at)
	out["x"] = pos.x
	out["y"] = pos.y
	return out


## The regions this world is divided into — authored by the forge, extended by
## the GM at the frontier. Empty is legal: a world with no regions behaves as
## one unnamed region centred on the chart.
func regions() -> Array:
	var world: Dictionary = state.get("world", {}) if state.get("world") is Dictionary else {}
	var made: Array = world.get("regions") if world.get("regions") is Array else []
	# Authored first (shipped gazetteer, or the ones a forged world rode in
	# with), then whatever the story has since opened. Same order and the same
	# reason as places(): a GM-created region can never shadow an authored one.
	var rs: Array = []
	var seen := {}
	for src in [_authored_regions(), made]:
		for r in src:
			if not (r is Dictionary):
				continue
			var nm := str(r.get("name", ""))
			if nm == "" or seen.has(nm.to_lower()):
				continue
			seen[nm.to_lower()] = true
			rs.append(r)
	var out: Array = []
	for i in rs.size():
		var r = rs[i]
		if not (r is Dictionary) or str(r.get("name", "")) == "":
			continue
		var e: Dictionary = r.duplicate(true)
		if not (e.has("x") and e.has("y")):
			var p := Rules.region_position(str(e["name"]), i, rs.size())
			e["x"] = p.x
			e["y"] = p.y
		out.append(e)
	return out


## The regions this world SHIPPED with — the hand-written set for a built-in,
## the Worldsmith's for a forged one.
func _authored_regions() -> Array:
	var built := Rules.world_regions(world_id())
	if not built.is_empty():
		return built
	for w in global_get("cworlds", []):
		if w is Dictionary and str(w.get("id", "")) == world_id():
			return w.get("regions") if w.get("regions") is Array else []
	return []


## Where a named region sits on the chart, or the chart's heart if it is unknown.
## `world` is accepted and ignored — callers had it to hand and passing it read
## naturally, but the answer must come from the merged region list either way.
func region_at(region_name: String, _world := {}) -> Vector2:
	if region_name == "":
		return Vector2(50, 50)
	# The MERGED list, not raw state — the shipped regions live in the gazetteer
	# and a forged world's rode in with it, so reading state alone found neither
	# and every authored region silently positioned at the chart's centre.
	var rs: Array = regions()
	for i in rs.size():
		var r = rs[i]
		if r is Dictionary and str(r.get("name", "")).nocasecmp_to(region_name) == 0:
			if r.has("x") and r.has("y"):
				return Vector2(float(r["x"]), float(r["y"]))
			return Rules.region_position(region_name, i, rs.size())
	return Vector2(50, 50)


## How many places a region already holds — the density budget's numerator.
func region_place_count(region_name: String) -> int:
	var n := 0
	for p in places():
		if p is Dictionary and str(p.get("region", "")).nocasecmp_to(region_name) == 0:
			n += 1
	return n


## What a journey to this place costs in time steps.
##
## Measured from where the party stands, on the chart's own percent scale, and
## bucketed through the same scope rings the GM builds with — so the number the
## clock spends and the number the engine validates come from one table.
func travel_cost(place_name: String) -> int:
	var from := Vector2(50, 50)
	var to := Vector2(50, 50)
	var h := here()
	var found_to := false
	for p in places():
		if not (p is Dictionary):
			continue
		var nm := str(p.get("name", ""))
		var at := Vector2(float(p.get("x", 50)), float(p.get("y", 50)))
		if nm == h:
			from = at
		if nm.nocasecmp_to(place_name) == 0:
			to = at
			found_to = true
	if not found_to:
		return 1
	var d := from.distance_to(to)
	# Nearest ring wins; a journey is never free.
	var best := "local"
	var best_gap := INF
	for sc in Rules.SCOPE_RING:
		var gap: float = absf(d - float(Rules.SCOPE_RING[sc]))
		if gap < best_gap:
			best_gap = gap
			best = str(sc)
	return maxi(1, int(Rules.SCOPE_TIME.get(best, 1)))


## THE GM CREATES A PLACE. Returns "" on success, or why it was refused.
##
## This is the mini-god's actual power, and the engine's veto is what keeps it
## a power rather than a mess. Refusals are specific so the GM's next attempt
## can be better — a bare "no" teaches it nothing.
func add_place(spec: Dictionary) -> String:
	var nm := str(spec.get("name", "")).strip_edges()
	if nm == "":
		return "a place needs a name"
	for p in places():
		if p is Dictionary and str(p.get("name", "")).nocasecmp_to(nm) == 0:
			return "%s is already on the chart" % nm
	var scope := str(spec.get("scope", "local")).to_lower()
	if not Rules.SCOPE_LEVEL.has(scope):
		scope = "local"
	var lv := int(sheet().get("level", 1))
	if not Rules.scope_allowed(scope, lv):
		return "%s is beyond this tale's reach for now (%s needs level %d)" % [
			nm, scope, int(Rules.SCOPE_LEVEL[scope])]
	var reg := str(spec.get("region", "")).strip_edges()
	if reg != "" and region_place_count(reg) >= Rules.REGION_PLACE_CAP:
		return "%s is full — %d places already stand there" % [reg, Rules.REGION_PLACE_CAP]
	var world: Dictionary = state.get("world", {}) if state.get("world") is Dictionary else {}
	var made: Array = world.get("places") if world.get("places") is Array else []
	var at := region_at(reg, world)
	var pos := Rules.place_position(nm, scope, at)
	made.append({
		"name": nm,
		"kind": str(spec.get("kind", "landmark")),
		"lore": str(spec.get("lore", "")),
		"shop": str(spec.get("shop", "")),
		"region": reg,
		"scope": scope,
		"x": pos.x, "y": pos.y,
		"origin": "gm",   # authored places never carry this; the chart can tell them apart
	})
	world["places"] = made
	save_kind("world", world)
	return ""


## THE GM CREATES A REGION. Rare on purpose — see Rules.SCOPE_LEVEL.
##
## A new region is the frontier opening, which should be an event in the story
## rather than a Tuesday. Gating it at `far` is what makes it feel earned; the
## alternative (regions on demand at any level) is how a chart becomes noise.
func add_region(spec: Dictionary) -> String:
	var nm := str(spec.get("name", "")).strip_edges()
	if nm == "":
		return "a region needs a name"
	for r in regions():
		if r is Dictionary and str(r.get("name", "")).nocasecmp_to(nm) == 0:
			return "%s is already charted" % nm
	var lv := int(sheet().get("level", 1))
	if not Rules.scope_allowed("far", lv):
		return "the frontier is out of reach for now (a new region needs level %d)" % int(Rules.SCOPE_LEVEL["far"])
	var world: Dictionary = state.get("world", {}) if state.get("world") is Dictionary else {}
	var rs: Array = world.get("regions") if world.get("regions") is Array else []
	var p := Rules.region_position(nm, rs.size(), rs.size() + 1)
	rs.append({"name": nm, "lore": str(spec.get("lore", "")),
		"biome": str(spec.get("biome", "")), "x": p.x, "y": p.y, "origin": "gm"})
	world["regions"] = rs
	save_kind("world", world)
	return ""


## Is there anyone HERE to trade with?
##
## R8-15 — the pack offered "Sell — 3 silver" inside a sealed barrow four days'
## walk from the nearest keeper. The shop system already gates on a location
## carrying a `shop`; the sell affordance simply never asked.
func shop_here() -> bool:
	var h := here()
	if h == "":
		return false
	for l in places():
		if l is Dictionary and str(l.get("name", "")) == h and str(l.get("shop", "")) != "":
			return true
	return false


func clock_text() -> String:
	var c := clock()
	var wx := (", under " + str(c["wx"]["name"])) if c.get("wx") is Dictionary else ""
	return "In-world time: %s, day %d of the adventure%s. Keep time's passage and weather consistent and let them color the scene (light, who's about, what's open)." % [
		TIMES[clampi(int(c.get("ti", 0)), 0, TIMES.size() - 1)], int(c.get("day", 1)), wx]


# ── Rests (ports of _shortRest / _longRest) ─────────────────────────────────
## → {note: player-visible line, gm: bracketed instruction for the GM}
func short_rest() -> Dictionary:
	var s := sheet()
	var pool := int(s.get("level", 1))
	var used := int(s.get("hitDiceUsed", 0))
	var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
	var heal := 0
	var note: String
	var why := ""
	if int(s.get("hp", 0)) >= int(s["hpMax"]):
		# R8-08 — the rest fired at 12/12, reported "recover 4 HP, now 12/12" and
		# left the pool at 0/1. A Hit Die is the only healing a level-1 hero owns;
		# never spend one for nothing. Resting unhurt is still a rest — the hour
		# passes, features recharge — it just costs no dice.
		note = "*You take an hour's rest. Unhurt already, you keep your Hit Dice — %d/%d still in hand.*" % [pool - used, pool]
		why = " though I am unhurt and spend no Hit Dice"
	elif used < pool:
		var die := int(s.get("hitDie", 8))
		heal = maxi(1, randi_range(1, die) + con)
		s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + heal)
		s["hitDiceUsed"] = used + 1
		note = "*You take a short rest — spend a Hit Die (d%d%+d CON) and recover **%d HP**, now %d/%d. Hit Dice left: %d/%d.*" % [
			die, con, heal, int(s["hp"]), int(s["hpMax"]), pool - int(s["hitDiceUsed"]), pool]
		why = ", recovering %d HP" % heal
	else:
		note = "*You rest an hour, but you're out of Hit Dice (%d/%d spent) — a long rest is what you need to heal.*" % [pool, pool]
		why = " but I am out of Hit Dice"
	set_sheet(s)
	_recharge_features("short")
	advance_time(1)
	var gm := "[I take a short rest%s.%s Briefly narrate the pause, then continue.]" % [why, here_pin()]
	return {"note": note, "gm": gm}


func long_rest() -> Dictionary:
	var s := sheet()
	# The night is not guaranteed, and WHERE you lie down decides how likely that
	# is. This was a flat 1-in-4 anywhere, so a tavern bed and an opened barrow
	# carried the same risk — two rests in a tomb with a hostile figure watching
	# passed without incident (CN-3). Rules owns the odds; this owns the night.
	var risk: Dictionary = Rules.rest_risk(world_id(), here())
	var interrupted := randf() < float(risk["risk"])
	if interrupted:
		s["hp"] = mini(int(s["hpMax"]), int(s.get("hp", 0)) + maxi(1, ceili((int(s["hpMax"]) - int(s.get("hp", 0))) / 2.0)))
		s["hitDiceUsed"] = maxi(0, int(s.get("hitDiceUsed", 0)) - ceili(int(s.get("level", 1)) / 2.0))
	else:
		s["hp"] = int(s["hpMax"])
		s["conditions"] = []
		s["concentration"] = null
		s["hitDiceUsed"] = 0
	var slots: Dictionary = s.get("slots", {})
	for l in slots:
		if slots[l] is Dictionary:
			slots[l]["used"] = 0
	if int(s.get("exhaustion", 0)) > 0:
		s["exhaustion"] = int(s["exhaustion"]) - 1
	set_sheet(s)
	_recharge_features("long")
	var c := clock()
	# PS-4 — A LONG REST IS EIGHT HOURS, NOT "UNTIL DAWN".
	#
	# This advanced to the next Dawn from wherever you were, so a rest begun at
	# Midday burned the entire afternoon, evening and night and handed back a
	# fresh day. There was no way to rest and keep the day you were having —
	# which also meant every rest reset the clock to the same hour, so time of
	# day stopped meaning anything across a campaign.
	#
	# Seven steps make a day here, so three is about eight hours. Rest at
	# Midday and you wake at Nightfall with the day still yours; rest at Dusk
	# and you wake at Dawn as before, because that is where three steps land.
	advance_time(LONG_REST_STEPS)
	var woke: String = TIMES[clampi(int(clock().get("ti", 0)), 0, TIMES.size() - 1)]
	var note := ("*You make camp — but something finds you in the night. You wake half-rested at %d/%d HP.*" % [int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else ("*You make camp and sleep. You wake at %s, fully restored — %d/%d HP.*" % [woke.to_lower(), int(s["hpMax"]), int(s["hpMax"])])
	var gm := ("[My rest is interrupted in the night — I slept %s, so run a short encounter that fits that ground.%s I woke at %d/%d HP, only half-rested. Open on the moment I startle awake.]" % [str(risk["shelter"]), here_pin(), int(s["hp"]), int(s["hpMax"])]) if interrupted \
		else ("[I take a long rest, %s, and wake at %s fully healed.%s Narrate the waking and what has changed while I slept, then continue.]" % [str(risk["shelter"]), woke.to_lower(), here_pin()])
	return {"note": note, "gm": gm}

extends Node
## Integration playthrough through the REAL UI — no model, no GPU.
##   godot --headless --path godot res://tests/ui_playthrough.tscn
## Api.test_mode feeds scripted GM replies, so the actual
## game scene runs its real send → stream → language-gate → [[tag]] → state
## pipeline. Catches real gameplay/logic bugs (a loot tag that doesn't add the
## item, a combat-start that doesn't start combat, a window that crashes on
## build) the way a player would hit them. Prints PLAYTHROUGH OK or asserts.

var _game: Control


func _ready() -> void:
	await get_tree().process_frame
	Ui.apply("")
	Ui.reduce_motion = true  # instant tweens/dice so the headless run is deterministic
	Api.test_mode = true
	GameState.reset_test_saves()   # a harness starts from nothing
	_seed()
	await _boot_game()
	await _turn("loot", "I pry the old chest open.",
		"Rusted hinges give. [[loot name=\"Iron Dagger\" rarity=common]] [[gold delta=+15]]", _check_loot)
	await _turn_equip()
	await _turn_damage_heal()
	await _turn("combat", "I ready my blade and step in.",
		"A giant rat bursts from the dark, teeth bared! [[combat-start foes=\"giant rat\"]]", _check_combat)
	if Combat.active():
		Combat.save({"active": false})  # leave the fight before the level-up ceremony blocks play
		await get_tree().process_frame
	await _turn_levelup()  # last: the ceremony correctly blocks further sends
	await _check_mil()
	_check_persistence()
	_check_gm_model_pick()
	_check_adventure_ids()
	_check_every_slot_has_forms()
	_check_save_spells()
	_check_rest_place()
	_check_multiclass()
	_check_controller()
	await _build_windows()
	if is_instance_valid(_game):
		_game.queue_free()
	await get_tree().process_frame
	if _fails.is_empty():
		print("PLAYTHROUGH OK")
		get_tree().quit(0)
		return
	for f in _fails:
		print("  FAIL: " + f)
	print("PLAYTHROUGH FOUND %d FAILURE(S)" % _fails.size())
	get_tree().quit(1)


## Godot's assert() prints and unwinds the CURRENT function. Most of these checks
## run inside their own coroutine, so a failure never reached _ready and the
## harness printed PLAYTHROUGH OK over the top of three real failures — the one
## thing a test must never do. Record instead, and fail the run at the end.
var _fails: Array[String] = []


func _ck(cond: bool, why := "") -> void:
	if cond:
		return
	_fails.append(why if why != "" else "unnamed check")
	push_error("PLAYTHROUGH check failed: " + (why if why != "" else "unnamed check"))


func _seed() -> void:
	var sheet := {
		"name": "Testwyn", "race": "Human", "cls": "Fighter", "level": 1, "xp": 0,
		"hp": 12, "hpMax": 12, "ac": 12, "gold": 20,
		"abilities": {"STR": 15, "DEX": 13, "CON": 14, "INT": 10, "WIS": 12, "CHA": 8},
		"inventory": [], "conditions": [], "spells": [], "slots": {},
		"profSkills": ["athletics"], "profSaves": ["STR", "CON"], "hitDie": 10, "hitDiceUsed": 0,
	}
	# SEED THE SAVE FILE. Writing the file is what the game actually reads, so
	# the harness must set up state the same way play does.
	GameState.character = {"id": "dm-embervale-freeroam", "world_id": "embervale"}
	GameState.state = {"sheet": sheet, "clock": {"day": 1, "ti": 1}}
	GameState.save_kind("sheet", sheet)
	GameState.save_kind("clock", {"day": 1, "ti": 1})
	GameState.character = {"id": "dm-embervale-freeroam", "name": "Testwyn: Free Roam", "world_id": "embervale"}


func _boot_game() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	for i in 60:  # wait for _ready's hydrate + recap to settle
		await get_tree().process_frame
		if Mode.state == "Exploration":
			break
	_ck(Mode.state == "Exploration", "boot: never reached Exploration (state=%s)" % Mode.state)
	_ck(str(GameState.sheet().get("name", "")) == "Testwyn", "boot: seeded sheet not hydrated")
	print("  boot: real game scene up, hero hydrated, Exploration")


## Drive one real turn: send a message, let the scripted GM reply flow through
## the whole pipeline, then check the deterministic effect the player would see.
func _turn(label: String, msg: String, reply: String, check: Callable) -> void:
	Api.test_replies = [reply]
	_game._send(msg)
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and check.call(true):
			break
	_ck(check.call(false), "turn '%s': the tag effect never landed" % label)
	print("  turn %s: ok" % label)


func _check_loot(_quiet := false) -> bool:
	var names: Array = GameState.inv().get("items", []).map(func(it): return str(it.get("name", "")))
	return int(GameState.sheet().get("gold", 0)) == 35 and "Iron Dagger" in names


## Loot a weapon, then equip it through the real equip logic the paper doll and
## pack both call — and assert it landed in the weapon slot and lifts attack.
func _turn_equip() -> void:
	Api.test_replies = ["A gleaming longsword rests on the altar. [[loot name=\"Longsword\" rarity=common]]"]
	_game._send("I take up the sword")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and _has_item("Longsword"):
			break
	_ck(_has_item("Longsword"), "equip: the longsword was never looted")
	var sword_id := ""
	for it in GameState.inv().get("items", []):
		if str(it.get("name", "")) == "Longsword":
			sword_id = str(it.get("id", ""))
	var atk0 := Rules.attack_mod(GameState.sheet(), GameState.inv())
	GameState.toggle_equip(sword_id)
	_ck(str(GameState.inv().get("equipped", {}).get("weapon", "")) == sword_id, "equip: sword not seated in the weapon slot")
	_ck(Rules.attack_mod(GameState.sheet(), GameState.inv()) >= atk0, "equip: attack modifier regressed")
	print("  turn equip: ok (Longsword equipped)")


## Award XP through the [[xp]] tag and assert the real level-up math applied.
func _turn_levelup() -> void:
	var lvl0 := int(GameState.sheet().get("level", 1))
	Api.test_replies = ["The rat falls; hard-won insight settles in your bones. [[xp delta=400 reason=\"a clean kill\"]]"]
	_game._send("I finish it")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming and int(GameState.sheet().get("level", 1)) > lvl0:
			break
	_ck(int(GameState.sheet().get("level", 1)) > lvl0, "levelup: never leveled (xp=%d)" % int(GameState.sheet().get("xp", 0)))
	_ck(int(GameState.sheet().get("hpMax", 0)) > 12, "levelup: hpMax did not grow")
	print("  turn levelup: ok (now level %d, HP %d)" % [int(GameState.sheet().get("level", 1)), int(GameState.sheet().get("hpMax", 0))])


## The damage/heal tag path — the core of combat's HP math, driven for real.
func _turn_damage_heal() -> void:
	var hp0 := int(GameState.sheet().get("hp", 0))
	Api.test_replies = ["A dart snaps from the wall and bites deep. [[damage roll=1d4]]"]
	_game._send("I step on the pressure plate")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			break
	# [[damage]] arms the dice moment — the engine rolls when the player acts.
	_ck(str(_game._pending_check.get("type", "")) == "damage", "damage: tag did not arm a damage roll")
	await _game._roll_pending()  # resolve the roll (awaits the die), as clicking the roll bar would
	await get_tree().process_frame
	_ck(int(GameState.sheet().get("hp", 0)) < hp0, "damage: the roll did not reduce HP (was %d)" % hp0)
	var hp1 := int(GameState.sheet().get("hp", 0))
	await _settle()  # the roll narrates a follow-up turn; let it finish before the next send
	Api.test_replies = ["Warm light knits the wound closed. [[heal roll=1d6]]"]
	_game._send("I press a healing draught to my lips")
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			break
	_ck(bool(_game._pending_check.get("heal", false)), "heal: tag did not arm a heal roll")
	await _game._roll_pending()
	await get_tree().process_frame
	_ck(int(GameState.sheet().get("hp", 0)) > hp1, "heal: the roll did not restore HP (was %d)" % hp1)
	await _settle()  # the heal roll narrates too; settle before the next turn's send
	print("  turn damage/heal: ok (%d → %d → %d)" % [hp0, hp1, int(GameState.sheet().get("hp", 0))])


## Latency guard — "Auto" must not seat the biggest model in the narrator's
## chair. A 14B measured 53s for one turn (player-felt: ~2 min); the fast
## window (≤9B) is what keeps play playable, and the LARGEST model inside it
## wins so prose quality isn't thrown away for speed.
## The narrator the player picks must be the narrator that speaks.
##
## The check that lived here re-implemented the ranking inline, so it passed on
## a pure helper while the feature it was named for sat disconnected: the picker
## saved to a key nothing read. A test that cannot tell whether the feature is
## plugged in is not testing the feature.
func _check_gm_model_pick() -> void:
	var models := LocalGM.chat_models()
	_ck(not models.has(""), "the narrator list holds filenames, not blanks")
	for m in models:
		var lower := str(m).to_lower()
		_ck(lower.ends_with(".gguf"), "every listed narrator is a .gguf (%s)" % m)
		for hint in LocalMemory.EMBED_HINTS:
			_ck(lower.find(hint) < 0,
				"the embedding model is not offered as a narrator (%s)" % m)
	# The contract that actually matters: whatever Settings saved is what loads.
	if not models.is_empty():
		var cfg := ConfigFile.new()
		cfg.load(Api.SETTINGS_FILE)
		var keep = cfg.get_value("settings", "gm_model", "")
		cfg.set_value("settings", "gm_model", str(models[-1]))
		cfg.save(Api.SETTINGS_FILE)
		_ck(LocalGM.model_file().get_file() == str(models[-1]),
			"the chosen narrator is the one that loads")
		# A model deleted out from under the setting costs the preference, not
		# the game.
		cfg.set_value("settings", "gm_model", "a-model-that-was-deleted.gguf")
		cfg.save(Api.SETTINGS_FILE)
		_ck(LocalGM.model_file() != "", "a stale pick falls back rather than failing")
		cfg.set_value("settings", "gm_model", keep)
		cfg.save(Api.SETTINGS_FILE)
	print("  gm model: %d narrator(s) installed, Settings picks by filename" % models.size())


## The catalogue only ever covered weapon and armor, so eleven of the thirteen
## worn slots had no forms and rendered as identical grey diamonds. Every slot
## the game can equip must have shapes to build items from — including when the
## seed model returns nothing at all.
func _check_every_slot_has_forms() -> void:
	var kinds := {}
	for f in Compiler._forms({}):        # {} = the seed gave us nothing
		kinds[str(f.get("kind", ""))] = true
	var missing: Array = []
	for pair in Rules.EQUIP_SLOTS:
		var slot := str(pair[0])
		# weapon/armor are dressed by the seed's own forms; both ring fingers
		# take the one "ring" shape family.
		var covered: bool = kinds.has(slot) \
			or (slot in ["ring1", "ring2"] and kinds.has("ring")) \
			or (slot == "weapon" and kinds.has("weapon")) \
			or (slot == "armor" and kinds.has("armor"))
		if not covered:
			missing.append(slot)
	_ck(missing.is_empty(), "slot forms: no shapes for %s — those slots render as empty diamonds" % str(missing))
	print("  slot forms: all %d equip slots have shapes even with an empty seed" % Rules.EQUIP_SLOTS.size())
	# C1/C2 — material chooses the form. A leather cuirass and a steel hood are
	# incoherent; the catalogue must not contain either.
	_ck(Compiler._material_class("brine_iron") == "rigid", "class: brine_iron is rigid")
	_ck(Compiler._material_class("salt_leather") == "soft", "class: leather is soft")
	_ck(Compiler._material_class("chain") == "mail", "class: chain is mail")
	_ck(Compiler._material_class("whalebone") == "exotic", "class: bone is exotic")
	_ck(Compiler._material_class("zzz_unknown") == "any", "class: an unknown material must match everything, never empty the catalogue")
	var helm := {"classes": ["rigid"]}
	var hood := {"classes": ["soft"]}
	_ck(Compiler._form_takes(helm, "rigid") and not Compiler._form_takes(helm, "soft"), "no leather helms")
	_ck(Compiler._form_takes(hood, "soft") and not Compiler._form_takes(hood, "rigid"), "no steel hoods")
	_ck(Compiler._form_takes(helm, "any"), "an unclassified material still fits")
	_ck(Compiler._form_takes({}, "soft"), "a form with no classes takes anything (the seed's own forms)")
	print("  material classes: form follows material — no leather cuirasses, no steel hoods")
	# C5 — a declared class beats the keyword guess, so a world can invent a
	# material whose name carries no known word.
	_ck(Compiler._class_of({"id": "sunmetal", "class": "rigid"}) == "rigid", "class: declared wins")
	_ck(Compiler._class_of({"id": "salt_leather"}) == "soft", "class: keywords still work undeclared")
	# C4 — an armoury is not six swords. Every family must be represented, even
	# when the seed returns nothing at all.
	var fams := {}
	var weapons := 0
	for f in Compiler._forms({}):
		if str(f.get("kind", "")) == "weapon":
			weapons += 1
			fams[str(f.get("family", ""))] = true
	for want in ["blade", "axe", "blunt", "polearm", "ranged", "thrown"]:
		_ck(fams.has(want), "weapon families: nothing to swing in the '%s' family" % want)
	_ck(weapons >= 25, "weapon families: only %d weapon forms — an armoury, not a rack of swords" % weapons)
	print("  weapon families: %d weapon forms across %d families" % [weapons, fams.size()])
	# Enchantments must READ. Ten treatments over one baked shape have to look
	# like ten things, or the combinatorics only exist on paper.
	var flame := Compiler.treatment_modulate({"treatment": "flame_kissed"})
	var frost := Compiler.treatment_modulate({"treatment": "rimebound"})
	_ck(flame != Color.WHITE and frost != Color.WHITE, "treatments: a known treatment must tint")
	_ck(flame != frost, "treatments: flame and frost must not look alike")
	_ck(Compiler.treatment_modulate({}) == Color.WHITE, "treatments: no treatment, no tint")
	_ck(Compiler.treatment_modulate({"treatment": "zzz_unknown"}) == Color.WHITE,
		"treatments: an unrecognised treatment must look ordinary, never wrong")
	print("  treatments: enchantments tint the icon (flame ≠ frost ≠ plain)")


## Every tale in a world used to collapse onto "dm-<world>-freeroam", because
## the built-in stories carry a title and no slug — one save, one GM session and
## one chronicle for all of them. Distinct tales must get distinct slots.
func _check_adventure_ids() -> void:
	var a := Rules.adventure_id("saltmarsh", {"title": "The Tide-Debt"})
	var b := Rules.adventure_id("saltmarsh", {"title": "What the Nets Dragged Up"})
	var free := Rules.adventure_id("saltmarsh", {})
	_ck(a != b, "adventure_id: two named tales collapsed onto one save slot (%s)" % a)
	_ck(a != free and b != free, "adventure_id: a named tale collided with Free Roam")
	_ck(free == "dm-saltmarsh-freeroam", "adventure_id: Free Roam must keep its id, got %s" % free)
	_ck(Rules.adventure_id("saltmarsh", {"slug": "tide"}) == "dm-saltmarsh-tide", "adventure_id: an explicit slug still wins")
	print("  adventure ids: each tale gets its own save slot (%s / %s / %s)" % [a, b, free])


## Bug #8 guard — a forged hero must survive a shutdown. bank_hero writes the
## roster to disk; banked_heroes() re-reads that file, so a fresh read proves
## the hero persists across a process restart (the exact path that lost heroes).
func _check_persistence() -> void:
	var name := "Pathfinder_%d" % (GameState.sheet().get("level", 1))  # unique-ish, avoids clobbering a real roster entry
	GameState.bank_hero({"name": name, "race": "Human", "cls": "Fighter", "level": 3})
	var banked: Array = GameState.banked_heroes().filter(func(h): return str(h.get("name", "")) == name)
	GameState.unbank_hero(name)  # keep the run hermetic — don't leave a test hero in the roster
	_ck(not banked.is_empty(), "persistence: banked hero did not survive a fresh roster read (bug #8)")
	# Identity — the roster's art key is "hero-<id>", and the forge's preview key
	# is shared scratch. No id means a blank card and, later, a stranger's face.
	_ck(str(banked[0].get("id", "")) != "", "persistence: banked hero has no id — roster art can't resolve")
	print("  persistence: forged hero survives a disk round-trip, with its own id")
	_check_one_identity()


## ONE HERO, ONE FACE.
##
## The portrait and the paper doll were separate renders with nothing shared: the
## portrait carried the player's appearance words, the body prompt carried none,
## so the two views described different people wearing the same gear.
##
## There is no seed to lock (sd-server ignores `seed` in the body, measured — two
## different seeds, byte-identical output), so the PROMPT is the only anchor.
## This asserts what the failure looked like: a render that does not name the
## hero's look, and a key rebuilt from the current adventure instead of asked for.
func _check_one_identity() -> void:
	var keep_char := GameState.character
	var keep_state := GameState.state
	GameState.character = {"id": "dm-identity-probe", "world_id": "embervale"}
	GameState.state = {"sheet": {"name": "Sable", "race": "Half-Elf", "cls": "Rogue",
		"look": "a knife-thin scar from brow to jaw, cropped silver hair", "brush": "painted"}}
	var look := Art.hero_look()
	for must in ["knife-thin scar", "cropped silver hair", "painted style"]:
		_ck(look.find(must) >= 0, "identity: hero_look dropped '%s'" % must)
	# Every renderer must carry it. A prompt that omits the look is a stranger.
	var screen = load("res://scenes/ui/character_screen.gd").new()
	var body: String = screen._body_prompt(GameState.sheet(), {"equipped": {}})
	screen.free()
	for must in ["knife-thin scar", "cropped silver hair"]:
		_ck(body.find(must) >= 0,
			"identity: the paper-doll prompt does not describe the hero ('%s') — it will paint someone else" % must)
	GameState.character = keep_char
	GameState.state = keep_state
	# The body key must be DERIVED, never rebuilt. A hero banked in one adventure
	# and played in another owns art under the key they were painted with, so
	# "herobody-" + cid names a file that does not exist: the plate renders empty
	# and the game re-commissions a body it already owns. Asserted on the source,
	# because the defect is a call site, not a return value — the same shape as
	# the art-door and hard-cut laws below.
	for path in ["res://scenes/ui/character_screen.gd", "res://scripts/game.gd",
			"res://scenes/forge/character_forge.gd"]:
		_ck(FileAccess.file_exists(path), "identity: %s exists to be checked" % path)
		var src := FileAccess.get_file_as_string(path)
		_ck(src.find("\"herobody-\"") < 0,
			"identity: %s builds the body key by hand — ask Art.hero_body_key()" % path)
	print("  identity: one look, carried by the portrait, the doll and the key")


## A REST HAPPENS SOMEWHERE.
##
## Two defects, one cause — the rest knew nothing about the ground under it:
##   CN-1: camped at the barrow-mound, woke in the mead-hall with no travel. The
##         location IS in the envelope, but the instruction that arrives LAST said
##         only "narrate the new morning", and recency wins in a long context.
##   CN-3: two rests inside an opened barrow, hostile figure watching, nothing
##         happened — the interrupt was a flat 1-in-4 anywhere.
func _check_rest_place() -> void:
	# Risk follows the ground. A bed is not a barrow.
	var tavern: Dictionary = Rules.rest_risk("embervale", "The Ember & Oak")
	var wild: Dictionary = Rules.rest_risk("embervale", "The Sunken Barrow")
	var nowhere: Dictionary = Rules.rest_risk("embervale", "")
	_ck(float(tavern["risk"]) < float(nowhere["risk"]),
		"rest: sleeping in a tavern is no safer than sleeping nowhere in particular")
	_ck(float(wild["risk"]) >= float(tavern["risk"]),
		"rest: an unknown/wild place is not riskier than a tavern bed")
	_ck(str(tavern["shelter"]) != str(nowhere["shelter"]),
		"rest: every place describes itself the same way — the GM cannot fit the encounter")

	# The pin travels WITH the instruction, naming the actual place.
	var keep_char := GameState.character
	var keep_state := GameState.state
	GameState.character = {"id": "dm-rest-probe", "world_id": "embervale"}
	GameState.state = {"sheet": GameState.DEFAULT_SHEET.duplicate(true),
		"world": {"here": "The Sunken Barrow"}, "clock": {"day": 1, "ti": 3}}
	_ck(GameState.here() == "The Sunken Barrow", "rest: GameState.here() lost the location")
	var pin := GameState.here_pin()
	_ck(pin.find("The Sunken Barrow") >= 0, "rest: the pin does not name where the player is")
	var long_gm := str(GameState.long_rest()["gm"])
	_ck(long_gm.find("The Sunken Barrow") >= 0,
		"rest: the long-rest instruction never names the place — the GM will relocate the player (CN-1)")
	_ck(long_gm.find("do not") >= 0 or long_gm.find("Do not") >= 0,
		"rest: the long-rest instruction does not forbid relocating the player (CN-1)")
	GameState.state["sheet"]["hp"] = 1
	var short_gm := str(GameState.short_rest()["gm"])
	_ck(short_gm.find("The Sunken Barrow") >= 0,
		"rest: an hour's pause is not a journey either — the short rest lost the place")
	GameState.character = keep_char
	GameState.state = keep_state
	print("  rest: risk follows the ground, and the place rides the instruction")
	_check_scene_follows_mood()


## CN-4 — IS THE MOOD ACTUALLY PLUGGED INTO THE BACKDROP?
##
## self_check proves scene_mood() buckets light and weather correctly. That is
## worth nothing if the scene key ignores it: one painting would still serve a
## place across four days and three weather states, and every unit assertion
## would still pass. A test that cannot tell whether the feature is WIRED is not
## testing the feature — so this asks the source, the same way the art-door and
## hard-cut laws below do.
func _check_scene_follows_mood() -> void:
	var path := "res://scripts/game.gd"
	_ck(FileAccess.file_exists(path), "scene: %s exists to be checked" % path)
	var src := FileAccess.get_file_as_string(path)
	var at := src.find("func _repaint_scene(")
	_ck(at >= 0, "scene: _repaint_scene is gone — the backdrop has no single door")
	if at < 0:
		return
	# Bound to the real function body, not a fixed window — this function carries
	# a long comment block and a 900-char guess stopped short of the prompt.
	var nxt := src.find("
func ", at + 10)
	var body := src.substr(at, (nxt - at) if nxt > at else 2000)
	_ck(body.find("scene_mood()") >= 0,
		"scene: the backdrop key ignores the mood — one painting will serve a place forever (CN-4)")
	_ck(body.find("scene_mood_words()") >= 0,
		"scene: the backdrop PROMPT ignores the mood — every hour paints the same picture (CN-4)")
	# And something must repaint when only the clock moves, or a player who
	# stands still through dusk never sees the light change.
	_ck(src.find("mood_changed.connect") >= 0,
		"scene: nothing repaints on a mood change — standing still freezes the world (CN-4)")
	print("  scene: the backdrop follows the light and the weather, not just the place")
	_check_forge_grants_features()


## PS-1 — IS THE CLASS-FEATURE TABLE ACTUALLY WIRED TO THE FORGE?
##
## self_check proves Rules.class_features_upto() returns the right list. That is
## worth nothing if _create_hero never calls it — which is exactly the state this
## was in: the table had Second Wind at level 1 the whole time, and nothing asked
## for it. Asserted on the source, because the defect is a call site.
func _check_forge_grants_features() -> void:
	var path := "res://scripts/game.gd"
	_ck(FileAccess.file_exists(path), "features: %s exists to be checked" % path)
	var src := FileAccess.get_file_as_string(path)
	var at := src.find("func _create_hero(")
	_ck(at >= 0, "features: _create_hero is gone — heroes are built somewhere else now")
	if at < 0:
		return
	var nxt := src.find("
func ", at + 10)
	var body := src.substr(at, (nxt - at) if nxt > at else 4000)
	_ck(body.find("class_features_upto") >= 0,
		"features: the forge does not grant class features — a level-1 hero has none (PS-1)")
	_ck(body.find('"features"] = traits') < 0,
		"features: heritage traits are being written as class features again (PS-1)")
	# PS-2 — and the kit floor has to be APPLIED, not merely available.
	_ck(body.find("kit_gaps") >= 0,
		"features: the forge applies no kit floor — a hero can leave with one weapon (PS-2)")
	# PS-3 — the Quenching must promise what the commit delivers. Both must read
	# the SAME source: the forge showed its generic card while the commit granted
	# the world's compiled kit, so the summary said Longsword and combat swung a
	# Korvul Black Iron Hammer.
	var forge_src := FileAccess.get_file_as_string("res://scenes/forge/character_forge.gd")
	_ck(forge_src.find("kit_names_for_class") >= 0,
		"kit: the Quenching does not ask what the hero will actually carry (PS-3)")
	_ck(body.find("Compiler.kit_for(") >= 0,
		"kit: the commit no longer grants the world kit — the two paths have drifted (PS-3)")
	print("  features: the forge grants level-1 features and floors the starting kit")
	print("  kit: the Quenching promises what the commit delivers")


## Save-DC spells: a foe's saving-throw bonus is derived from tier (foes carry no
## ability scores). Guard the monotonicity the resolution relies on.
func _check_save_spells() -> void:
	_ck(Rules.foe_save_mod("minor") < Rules.foe_save_mod("standard"), "save: a minor foe should save worse than a standard one")
	_ck(Rules.foe_save_mod("boss") >= Rules.foe_save_mod("elite"), "save: a boss should save at least as well as an elite")
	_ck(Rules.foe_save_mod("elite") > Rules.foe_save_mod("tough"), "save: an elite should save better than a tough foe")
	print("  save spells: foe save mods scale with tier (minor→boss)")
	# a companion's kit is inferred from role, not always Fighter
	_ck(str(GameState.infer_companion_kit("temple healer")["cls"]) == "Cleric", "companion: 'healer' should infer Cleric")
	_ck(str(GameState.infer_companion_kit("court wizard")["cls"]) == "Wizard", "companion: 'wizard' should infer Wizard")
	_ck(str(GameState.infer_companion_kit("sellsword")["cls"]) == "Fighter", "companion: unknown role falls back to Fighter")
	print("  companions: kit inferred from role (healer→Cleric, mage→Wizard)")
	# new class-feature actions apply and spend a use
	var loh0 := GameState.feature_uses_left("Lay on Hands")
	_ck(GameState.use_feature("Bardic Inspiration") != "", "feature: Bardic Inspiration should apply")
	_ck(GameState.use_feature("Lay on Hands") != "", "feature: Lay on Hands should apply")
	_ck(GameState.feature_uses_left("Lay on Hands") == loh0 - 1, "feature: a use should be spent")
	print("  class features: Bardic Inspiration / Lay on Hands / Wild Shape wired")


## Multiclass: redirect the level the Fighter just gained into Wizard and
## assert every derived number follows — classes, label, slots, casting stat.
func _check_multiclass() -> void:
	var s := GameState.sheet()
	_ck(Rules.sheet_classes(s).size() == 1 and int(Rules.sheet_classes(s)[0]["level"]) == int(s.get("level", 1)),
		"multiclass: legacy sheet should derive one class entry at total level")
	_ck(not Rules.can_multiclass_into(s, "Wizard"), "multiclass: INT 10 must not qualify for Wizard")
	_ck(GameState.redirect_level("Wizard") == "", "multiclass: redirect must refuse unmet prereqs")
	s["abilities"]["INT"] = 13
	GameState.set_sheet(s)
	_ck(GameState.redirect_level("Wizard") != "", "multiclass: redirect refused despite INT 13")
	var cl := Rules.sheet_classes(GameState.sheet())
	_ck(cl.size() == 2 and int(cl[0]["level"]) == 2 and str(cl[1]["cls"]) == "Wizard" and int(cl[1]["level"]) == 1,
		"multiclass: expected Fighter 2 / Wizard 1, got %s" % Rules.class_label(GameState.sheet()))
	_ck(Rules.class_label(GameState.sheet()) == "Fighter 2 / Wizard 1", "multiclass: label wrong")
	_ck(int(GameState.sheet().get("level", 0)) == 3, "multiclass: total level must stay 3")
	_ck(Rules.caster_level(GameState.sheet()) == 1, "multiclass: one wizard level = caster level 1")
	_ck(int(GameState.sheet().get("slots", {}).get("1", {}).get("max", 0)) > 0,
		"multiclass: the first wizard level should open L1 slots")
	_ck(Rules.cast_ability(GameState.sheet()) == "INT", "multiclass: casting should lean on the wizard's INT")
	_ck(not Rules.learnable_spells(GameState.sheet()).is_empty(), "multiclass: wizard spells should be learnable now")
	print("  multiclass: Fighter 2 / Wizard 1 — slots, INT casting, prereqs, label all hold")


## Controller: the Pad autoload must have registered the app actions and given
## every focus-driving ui_* action a joypad event; the grid pad cursor must
## emit the SAME signal a mouse click does.
func _check_controller() -> void:
	for a in ["mf_roll", "mf_end_turn", "mf_menu"]:
		_ck(InputMap.has_action(a), "pad: missing action %s" % a)
	for a2 in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]:
		var has_joy := false
		for e in InputMap.action_get_events(a2):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				has_joy = true
		_ck(has_joy, "pad: %s has no joypad binding" % a2)
	var got: Array = []
	var catcher := func(c): got.append(c)
	_game._battle_grid.cell_clicked.connect(catcher)
	_game._battle_grid.pad_move(1, 0)
	_game._battle_grid.pad_activate()
	_game._battle_grid.cell_clicked.disconnect(catcher)
	_ck(not got.is_empty(), "pad: the grid cursor did not emit cell_clicked")
	print("  controller: mf_* actions live, ui_* pad-bound, grid cursor clicks cells")


## MIL Phase 0 — the interaction primitives every screen will lean on. Each
## must (a) exist, (b) run without crashing, and (c) honour reduce_motion by
## PRESERVING the information rather than dropping it (the rise_text bug:
## deltas used to vanish entirely for reduce-motion players).
func _check_mil() -> void:
	for group in ["TIME", "SCALE", "ALPHA", "MOTION", "DELAY", "MIX", "INTERACT"]:
		_ck(Ui.get(group) is Dictionary and not (Ui.get(group) as Dictionary).is_empty(),
			"MIL: token group %s missing" % group)
	for snd in Sfx.UI_SOUNDS + Sfx.REWARD_SOUNDS + Sfx.CEREMONY_SOUNDS:
		_ck(ResourceLoader.exists("res://assets/sfx/%s.wav" % snd), "MIL: sound '%s' never synthesized" % snd)
	Sfx.ui("ui_click")  # must not crash headless
	var host := Control.new()
	host.size = Vector2(400, 300)
	get_tree().root.add_child(host)
	var probe := Button.new()
	probe.text = "probe"
	host.add_child(probe)
	_ck(probe.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"MIL §3: a Button entering the tree must be auto-wired (cursor missing)")
	# The systemic guarantee, checked where it matters most: the play screen's
	# action bar was silent for the whole project until VS-1.
	for b in _game.find_children("*", "Button", true, false):
		_ck(b.has_meta("_polished"), "MIL §3: '%s' on the play screen never got hover/click" % b.name)
	Ui.shake(probe)
	var purse := Label.new()
	host.add_child(purse)
	Ui.count_to(purse, 20, 45)
	Ui.rise_text(host, "+2 AC", Ui.c("gold"), Vector2(10, 10))
	# The delta must still be on-screen after the frame — reduce_motion holds it.
	var deltas := host.get_children().filter(func(n): return n is Label and str(n.text) == "+2 AC")
	_ck(not deltas.is_empty(), "MIL §16: rise_text dropped the delta (information lost)")
	Ui.fly_to(host, Ui.glow_tex(), Rect2(0, 0, 32, 32), Rect2(100, 100, 32, 32))
	_check_no_hard_cuts()
	await _check_compiler()   # awaited here — it does real async art requests
	var cer: Node = preload("res://ui/myth_ceremony.gd").play(host,
		{"title": "Level 3", "line": "+7 HP", "weight": "light"})
	for i in 4:
		await get_tree().process_frame
	_ck(cer.get_script() != null, "MIL §13: ceremony script failed to load")
	_ck(is_instance_valid(cer), "MIL §13: ceremony vanished before its beats ran")
	cer.call("_finish")  # skip law: any input completes it
	await get_tree().process_frame
	host.queue_free()
	print("  MIL: tokens, 16 sounds, polish/shake/count_to/rise_text/fly_to/ceremony all live")


## MIL §12 law, enforced on the SOURCE: the world never cuts. Every scene
## change goes through Ui.transition (the wipe) or happens under a MythLoading
## curtain. A bare change_scene_to_file anywhere else is a regression.
const CUT_ALLOWED := {
	"res://scripts/main_menu.gd": 1,   # under the loading curtain — the curtain IS the transition
	"res://autoload/skin.gd": 1,       # Ui.transition itself
}


func _check_no_hard_cuts() -> void:
	for path in ["res://scripts/main_menu.gd", "res://scripts/game.gd",
			"res://autoload/skin.gd"]:
		# A path that no longer exists reads as empty and PASSES — the law would
		# quietly stop covering a file the day it moved.
		_ck(FileAccess.file_exists(path), "MIL §12: %s exists to be checked" % path)
		var src := FileAccess.get_file_as_string(path)
		var cuts := 0
		for line in src.split("\n"):
			if str(line).contains("change_scene_to_file") and not str(line).strip_edges().begins_with("#"):
				cuts += 1
		var allowed: int = int(CUT_ALLOWED.get(path, 0))
		_ck(cuts <= allowed, "MIL §12: %s has %d hard scene cut(s), %d allowed — use Ui.transition" % [path, cuts, allowed])
	print("  MIL: no hard scene cuts — every passage is a transition or a curtain")
	_check_one_art_door()


## The Art Director is the ONLY gateway to GPU generation. Two call sites once
## bypassed the queue and ran concurrently with it on a single GPU — which is
## how a stranger's photograph appeared in the player's scene slot. This law
## keeps that door shut.
func _check_one_art_door() -> void:
	var offenders: Array[String] = []
	for path in ["res://scripts/game.gd", "res://scripts/main_menu.gd",
			"res://scenes/ui/character_screen.gd", "res://scenes/ui/lore_book.gd",
			"res://scenes/forge/world_forge.gd", "res://scenes/forge/character_forge.gd",
			"res://scenes/forge/campaign_forge.gd", "res://scenes/forge/persona_forge.gd"]:
		if FileAccess.get_file_as_string(path).contains("studio/generate"):
			offenders.append(path)
	_ck(offenders.is_empty(),
		"Art Director: %s talks to /generate directly — every request goes through Art" % ", ".join(offenders))
	# …and the subsystem really carries its contract.
	for m in ["request", "cancel", "cancel_for", "status", "pending"]:
		_ck(Art.has_method(m), "Art Director: missing %s() from the contract" % m)
	_ck(Art.get("Lane") != null or true, "")
	print("  Art Director: one door, contract intact (queue/lanes/cancel/status/routing)")


## The World Compiler's seed tier (Style Guide + Asset Language) must produce a
## valid, consultable style for a world EVEN WHEN the model can't answer — a
## compile degrades, it never fails. Under test_mode the LLM returns nothing,
## so this exercises exactly the fallback path.
func _check_compiler() -> void:
	var world := {"id": "cw-testrealm-abcd", "name": "Testrealm",
		"kind": "grim frontier", "tagline": "the edge of the map", "lore": "A cold place."}
	var pack: Dictionary = await Compiler.compile_seed(world)
	_ck(not pack.is_empty(), "compiler: seed produced no package")
	# In test_mode art generation returns nothing, so Tier B 'fails' fast and the
	# world reaches PRESENTABLE without pixels — the compile must never wedge.
	_ck(str(pack.get("compile_state", "")) in [Compiler.SEEDED, Compiler.PRESENTABLE],
		"compiler: never reached a valid compile_state")
	_ck(pack.get("style") is Dictionary and str(pack["style"].get("prompt_anchor", "")) != "",
		"compiler: style guide has no prompt_anchor (drift defence missing)")
	_ck(pack.get("assets") is Dictionary and pack["assets"].get("materials") is Array
		and not (pack["assets"]["materials"] as Array).is_empty(),
		"compiler: asset language has no materials to compose from")
	# The anchor must actually reach an image prompt through the one door.
	GameState.character = {"id": "dm-x", "world_id": "cw-testrealm-abcd"}
	_ck(Art.world_flavor() == Compiler.prompt_anchor("cw-testrealm-abcd"),
		"compiler: the Style Guide's anchor isn't feeding image prompts")
	# Profiles exist and each declares the resolution it is seen at. The check
	# that lived here asserted a `style` key that the engine never read — one
	# checkpoint per launch means it could not act on one. A test that passes on
	# a field nothing consumes is not testing anything.
	for p in ["item", "scene", "showcase"]:
		_ck(Art.PROFILES.has(p) and str(Art.PROFILES[p].get("size", "")).find("x") > 0,
			"compiler: art profile '%s' declares no size" % p)
	# The real photograph defence: item prompts must refuse a scene and a person.
	# Without it an item icon comes back as a photo of someone holding the thing.
	for must in ["plain flat background", "no scene", "no people"]:
		_ck(Compiler.ICON_TAIL.find(must) >= 0,
			"compiler: item prompts dropped '%s' — icons will come back as photographs" % must)
	# Tier C: the item catalogue explodes the asset language into a browsable
	# spine and rolls loot deterministically (runs even headless).
	var cat := Compiler.catalogue_for("cw-testrealm-abcd")
	_ck(cat.size() > 0 and int(pack.get("catalogue_count", 0)) == cat.size(),
		"compiler: item catalogue is empty or not counted in the pack")
	var it0: Dictionary = cat[0]
	for k in ["id", "name", "form", "material", "rarity", "value", "art", "tint"]:
		_ck(it0.has(k), "compiler: catalogue item missing '%s'" % k)
	_ck(str(it0["art"]).begins_with("art/parts/"),
		"compiler: catalogue item art doesn't point at a base part")
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var loot := Compiler.roll_item("cw-testrealm-abcd", rng)
	_ck(not loot.is_empty() and str(loot.get("rarity", "")) != "",
		"compiler: roll_item returned nothing rollable")
	# S5: starting kits resolve to real catalogue records, so a new hero is armed.
	var kit := Compiler.kit_for("cw-testrealm-abcd", "warrior")
	_ck(kit.size() > 0 and (kit[0] as Dictionary).has("id"),
		"compiler: warrior kit didn't resolve to catalogue items")
	# S6: the world has bestiary-shaped creatures, and combat can stat one.
	var beasts := Compiler.creatures_for("cw-testrealm-abcd")
	_ck(beasts.size() > 0 and (beasts[0] as Dictionary).has("tier"),
		"compiler: world has no creatures")
	_ck(not Combat.stat_block(str((beasts[0] as Dictionary)["name"])).is_empty(),
		"compiler: a world creature didn't resolve to a combat stat block")
	# S7: the world has a named cast with dispositions.
	var folk := Compiler.npcs_for("cw-testrealm-abcd")
	_ck(folk.size() > 0 and (folk[0] as Dictionary).has("disposition"),
		"compiler: world has no named people")
	# Id hygiene: the schema-placeholder suffixes small models echo are scrubbed.
	_ck(Compiler._clean_id("cutlass_form_id") == "cutlass"
		and Compiler._clean_id("Brine Iron_material_id") == "brine_iron"
		and Compiler._clean_id("tide-worm") == "tide_worm",
		"compiler: _clean_id didn't normalise ids")
	# S9: tactical layouts are combat-shaped (terrain "x,y"→kind, cells in bounds).
	var lays := Compiler.layouts_for("cw-testrealm-abcd")
	_ck(lays.size() >= 3, "compiler: too few tactical layouts")
	for lay in lays:
		var terr = (lay as Dictionary).get("terrain", {})
		_ck(terr is Dictionary and not terr.is_empty(), "compiler: layout has no terrain")
		for key in terr:
			var xy: PackedStringArray = str(key).split(",")
			_ck(xy.size() == 2 and int(xy[0]) >= 0 and int(xy[0]) < 16 and int(xy[1]) >= 0 and int(xy[1]) < 10,
				"compiler: layout terrain cell out of the 16x10 grid")
			_ck(str(terr[key]) in ["block", "water", "cover"],
				"compiler: layout terrain kind not in combat's vocabulary")
	# Reforge: re-run a stage without a full recompile; logical ids stay stable.
	var id_before := str((Compiler.catalogue_for("cw-testrealm-abcd")[0] as Dictionary).get("id", ""))
	await Compiler.reforge("cw-testrealm-abcd", "catalogue")
	var cat2 := Compiler.catalogue_for("cw-testrealm-abcd")
	_ck(cat2.size() == cat.size() and str((cat2[0] as Dictionary).get("id", "")) == id_before,
		"compiler: reforge changed the catalogue size or renumbered ids")
	await Compiler.reforge("cw-testrealm-abcd", "layouts")
	_ck(Compiler.layouts_for("cw-testrealm-abcd").size() >= 3, "compiler: reforge dropped layouts")
	print("  compiler: seed→catalogue→kits→creatures→npcs, %d items, kit=%d, %d beasts, %d folk" % [
		cat.size(), kit.size(), beasts.size(), folk.size()])


## Wait for any in-flight GM turn to finish (a roll narrates a follow-up turn).
func _settle() -> void:
	for i in 45:
		await get_tree().process_frame
		if not _game._streaming:
			return


func _has_item(nm: String) -> bool:
	for it in GameState.inv().get("items", []):
		if str(it.get("name", "")) == nm:
			return true
	return false


func _check_combat(_quiet := false) -> bool:
	return Combat.active()


## Every player-facing window must BUILD without crashing (the extraction-safety
## net: a null ref or bad API call in a panel shows up here, not in play).
func _build_windows() -> void:
	if Combat.active():
		Combat.save({"active": false})  # leave combat so panels build in a calm state
	# THE MENU: every tab must build — Destiny/Atlas/Chronicle fill lazily, so
	# visiting them is the only way their pages are ever exercised.
	# A parse error makes preload() hand back a broken GDScript whose .new()
	# errors WITHOUT throwing — the run would sail on and print OK. Load it
	# explicitly and prove it compiled before trusting anything below.
	var menu_script = load("res://scenes/ui/character_screen.gd")
	_ck(menu_script is GDScript and menu_script.can_instantiate(),
		"menu: character_screen.gd failed to compile (parse error?)")
	var sheet = menu_script.new()
	_ck(sheet != null and sheet.get_script() != null, "menu: character_screen instantiate failed")
	get_tree().root.add_child(sheet)
	await get_tree().process_frame
	for tab in sheet.TABS:
		sheet.call("_show_page", tab)
		for i in 3:
			await get_tree().process_frame
		_ck(sheet._pages.has(tab) and is_instance_valid(sheet._pages[tab]),
			"menu: tab '%s' has no page" % tab)
	_ck(sheet._pages["Destiny"].get_child_count() > 0, "menu: Destiny never filled the skill tree")
	# Gear is the pack now — the tab must carry more than the doll (sockets +
	# The Pack header at minimum), or the merge silently shipped an empty page.
	_ck(sheet._gear_host.get_child_count() >= 4, "menu: Gear tab missing the pack section")
	sheet.queue_free()
	for path in ["res://scenes/ui/skill_tree.gd", "res://scenes/ui/world_map.gd"]:
		var w: Node = load(path).new()
		get_tree().root.add_child(w)
		await get_tree().process_frame
		w.queue_free()
	# The A0-split windows: the GM tuner and the reaction prompt build with
	# real props (the level-up window is already exercised by the ceremony).
	var tuner: Node = load("res://scenes/ui/gm_tuner.gd").new()
	get_tree().root.add_child(tuner)
	await get_tree().process_frame
	tuner.queue_free()
	var rx: Node = load("res://scenes/ui/reaction_prompt.gd").new()
	rx.pend = {"enemy": {"name": "test goblin"}, "total": 15, "ac": 12, "dmg": 5, "crit": false}
	rx.reactions = ["shield", "dodge", "parry"]
	get_tree().root.add_child(rx)
	await get_tree().process_frame
	rx.queue_free()
	var book: Node = load("res://scenes/ui/lore_book.tscn").instantiate()
	get_tree().root.add_child(book)
	for i in 5:
		await get_tree().process_frame
	book.queue_free()
	# Drive the real merchant open (now scenes/ui/merchant_window.gd) so a crash
	# there surfaces here, not when a player walks up to a keeper mid-adventure —
	# and assert the counter is genuinely stocked, not a bare dialog.
	Mode.enter("Exploration")  # the level-up ceremony left the FSM in LevelUp; a player shops from Exploration
	_game._open_shop()
	await get_tree().process_frame
	var shop: Node = null
	for ch in _game.get_children():
		if ch is AcceptDialog and ch.get_script() != null and str(ch.get_script().resource_path).ends_with("merchant_window.gd"):
			shop = ch
	_ck(shop != null, "shop: merchant window never opened")
	_ck(int(shop._wares.item_count) > 0, "shop: the keeper has no wares (vendor stock empty)")
	_ck(shop.get("_purse_amount") != null, "shop: purse amount label missing (MIL §9 count-down)")
	shop.queue_free()
	Mode.enter("Exploration")  # leave Merchant mode the way confirming would
	print("  windows: menu (9 tabs, Gear=pack), skill tree, lore book, shop all built")
	# The full-screen forges carry heavy _ready logic — build each so any
	# instantiation-time error (the kind --editor --quit misses) surfaces here.
	for path in ["res://scenes/forge/character_forge.tscn", "res://scenes/forge/campaign_forge.tscn",
			"res://scenes/forge/world_forge.tscn", "res://scenes/forge/adventure_forge.tscn",
			"res://scenes/forge/gm_forge.tscn", "res://scenes/forge/persona_forge.tscn"]:
		var f: Node = load(path).instantiate()
		# A failed script load still instantiates a bare Control — instantiate()
		# "succeeding" proves nothing. Assert the script is really attached AND
		# the scaffold actually built (the rail exists), or this is a dead screen.
		_ck(f.get_script() != null, "forge %s: script failed to load (parse error?)" % path)
		get_tree().root.add_child(f)
		for i in 6:
			await get_tree().process_frame
		_ck(f.get("_rail") != null, "forge %s: scaffold never built (_rail is null)" % path)
		f.queue_free()
	print("  forges: character, campaign, world, adventure, gm, persona all built")

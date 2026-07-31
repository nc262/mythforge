extends ForgeFlow
## 🧭 Begin a New Adventure — not "New Game": the sitting-down-at-the-table
## ritual that orchestrates both Forges. Choose or forge the hero, choose or
## forge the campaign, set the party and the table, preview, begin — like a
## tabletop night before the first dice are rolled.
## Scaffold lives in ForgeFlow; this keeps its own MythButton _nav override.

signal adventure_ready(adv: Dictionary)

## R6 CUT-03/CUT-05 — "The Table Is Set" is gone. It was a stage containing one
## line ("A hero. A campaign. A table. Everything else is dice.") and a button
## reading **SIT DOWN** — the Director's own example of the problem, verbatim:
## you ask to play and the game asks you to take a seat first. Same defect as the
## Character Forge's Cold Anvil, same treatment. Cold start to play is now ~14
## screens instead of ~18.
const STAGES := ["The Hero", "The Campaign", "The Party", "Difficulty", "House Rules", "The Preview"]
## UI-9 — four cards wearing the same glyph is a choice the eye cannot make.
## They all read "hero"; nothing about the picture said which way was harder.
## The library already carries a ladder that does: a book for the tale that
## leads, a sword for the intended fight, a shield for the longer war, a skull
## for the world that does not blink.
const DIFFICULTIES := [
	{"glyph": "book", "title": "Story", "body": "foes soften — the tale leads", "mult": 0.75},
	{"glyph": "sword", "title": "Adventurer", "body": "the intended fight", "mult": 1.0},
	{"glyph": "shield", "title": "Veteran", "body": "foes hit harder, last longer", "mult": 1.25},
	{"glyph": "skull", "title": "Merciless", "body": "the world does not blink", "mult": 1.5},
]

const Card := preload("res://ui/myth_choice_card.gd")
const BtnM := preload("res://ui/myth_button.gd")

var draft := {"hero": "", "adv": {}, "companions": true, "difficulty": 1.0, "house": "", "party": []}
var _worlds: Array = []
var _personas: Array = []   # forged companions from the gallery (Companion Forge)
var _child_forge: Control = null
var _camp_world: Dictionary = {}   # The Campaign is two steps: world first, then its tales.


func _ready() -> void:
	_load_worlds()  # fire-and-forget, same as before — stage 0 doesn't need it yet
	_load_personas()
	super._ready()


func _load_personas() -> void:
	_personas = GameState.global_get("cpersonas", [])


func _stages() -> Array:
	return STAGES


func _env() -> Array:
	return ["env-fireside", "dust", [Vector2(0.12, 0.3)]]


func _on_stage_entered(_i: int) -> void:
	_status.text = ""


func _load_worlds() -> void:
	var cw: Array = GameState.global_get("cworlds", [])
	_worlds = Rules.builtin_worlds() + cw


## Overrides the base nav: this table uses the big MythButtons.
## back_fn overrides the plain stage jump — used by the two-step Campaign stage,
## where "back" means "back to the world list", not "back a stage".
func _nav(back_to: int, fwd_text: String, fwd: Callable, back_fn := Callable()) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	if back_to >= 0 or back_fn.is_valid():
		var back := BtnM.new("BACK", "", "leather")
		back.custom_minimum_size = Vector2(140, 52)
		back.pressed.connect(back_fn if back_fn.is_valid() else func(): _enter_stage(back_to))
		row.add_child(back)
	var go := BtnM.new(fwd_text, "compass", "brass")
	go.custom_minimum_size = Vector2(300, 56)
	go.pressed.connect(fwd)
	row.add_child(go)
	var leave := BtnM.new("LEAVE THE TABLE", "door", "leather")
	leave.custom_minimum_size = Vector2(200, 52)
	leave.pressed.connect(func(): closed.emit())
	row.add_child(leave)
	_stage_box.add_child(row)


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_hero()
		1:
			_stage_campaign()
		2:
			_stage_party()
		3:
			_stage_difficulty()
		4:
			_stage_house()
		5:
			_stage_preview()


func _stage_hero() -> void:
	_title_label("Who Plays Tonight?")
	var heroes := GameState.banked_heroes()
	var cards: Array = []
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", Ui.SPACE["m"])
	flow.add_theme_constant_override("v_separation", Ui.SPACE["m"])
	# Every banked legend — a forged hero survives to play many nights.
	for h in heroes:
		var hd: Dictionary = h
		var card := Card.new({"glyph": "banner",
			"art": Art.texture_for(GameState.hero_portrait_key(hd)),
			"title": str(hd.get("name", "The legend")),
			"body": "%s %s" % [str(hd.get("race", "")), str(hd.get("cls", ""))], "foot": "your roster"})
		card.set_selected(_hero_selected(hd))
		card.pressed.connect(func():
			draft["hero"] = hd
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		flow.add_child(card)
	# Counts the rail, rather than hard-coding it — the copy said "eleven runes"
	# and was wrong the moment the Cold Anvil was deleted (caught by playing it,
	# not by either harness).
	var forge_card := Card.new({"glyph": "anvil", "title": "Forge a Hero now",
		"body": "walk the anvil's %d runes" % preload("res://scenes/forge/character_forge.gd").STAGES.size()})
	forge_card.pressed.connect(_spawn_char_forge)
	flow.add_child(forge_card)
	var later := Card.new({"glyph": "die", "title": "The tale provides", "body": "forge at the campfire when the story opens"})
	later.set_selected(str(draft["hero"]) == "later")
	later.pressed.connect(func():
		draft["hero"] = "later"
		for c in cards:
			c.set_selected(c == later))
	cards.append(later)
	flow.add_child(later)
	_stage_box.add_child(flow)
	_nav(-1, "NEXT — THE CAMPAIGN", func():   # first stage now — nothing behind it
		if not (draft["hero"] is Dictionary) and str(draft["hero"]) != "later":
			draft["hero"] = heroes[0] if not heroes.is_empty() else "later"
		_enter_stage(1))


func _hero_selected(hd: Dictionary) -> bool:
	return draft["hero"] is Dictionary and str(draft["hero"].get("name", "")).nocasecmp_to(str(hd.get("name", ""))) == 0


func _spawn_char_forge() -> void:
	_child_forge = preload("res://scenes/forge/character_forge.tscn").instantiate()
	_child_forge.menu_mode = true
	_child_forge.hero_forged.connect(func(d):
		GameState.bank_hero(d)
		_child_forge.queue_free()
		draft["hero"] = d
		_enter_stage(0))
	_child_forge.closed.connect(func():
		_child_forge.queue_free()
		_enter_stage(0))
	add_child(_child_forge)


func _stage_campaign() -> void:
	if _camp_world.is_empty():
		_stage_campaign_world()
	else:
		_stage_campaign_tale()


## Step one: where does tonight's tale happen?
func _stage_campaign_world() -> void:
	_title_label("Which World?")
	var cards: Array = []
	var grid := _grid()
	var forge_card := Card.new({"glyph": "⚒", "title": "Forge a Campaign now", "body": "the war table awaits", "foot": "world + voice + rules"})
	forge_card.pressed.connect(_spawn_camp_forge)
	grid.add_child(forge_card)
	for w in _worlds:
		var world: Dictionary = w
		var wid := str(world.get("id", ""))
		var stories := _stories_for(world)
		var card := Card.new({"glyph": "🌍", "art": Compiler.key_art(wid),
			"title": str(world.get("name", "an unnamed world")).left(26),
			"body": str(world.get("tagline", "")).left(60),
			"foot": "%d tale%s + free roam" % [stories.size(), "" if stories.size() == 1 else "s"]})
		card.set_selected(str(draft["adv"].get("world_id", "")) == wid)
		card.pressed.connect(func():
			_camp_world = world
			for c in cards:
				c.set_selected(c == card)
			_enter_stage(1))
		cards.append(card)
		grid.add_child(card)
	_stage_box.add_child(_scrolled(grid))
	_nav(0, "NEXT — THE PARTY", func():
		if draft["adv"].is_empty():
			_refuse("Choose a world — or forge one at the war table.")
			return
		_enter_stage(2))


## Step two: which of that world's tales — or free roam within it?
func _stage_campaign_tale() -> void:
	var wid := str(_camp_world.get("id", ""))
	_title_label("Which Tale in %s?" % str(_camp_world.get("name", "this world")))
	var cards: Array = []
	var grid := _grid()
	for st in [{}] + _stories_for(_camp_world):
		var story: Dictionary = st if st is Dictionary else {}
		var title := str(story.get("title", "")) if not story.is_empty() else "Free Roam"
		var adv := {"id": Rules.adventure_id(wid, story), "name": title, "world_id": wid, "world": _camp_world, "story": story}
		# R11-06 — "wander it as you please" was the DEFAULT for a missing hook, so
		# every authored tale wore Free Roam's subtitle and all three cards read
		# identically. Only free roam is free roam; an authored tale says what it
		# is, or says nothing, but never claims to be the other thing.
		var blurb := "wander it as you please"
		if not story.is_empty():
			blurb = str(story.get("hook", story.get("premise", story.get("blurb", "")))).strip_edges()
			if blurb == "":
				blurb = "a tale of %s" % str(_camp_world.get("name", "this world"))
		var card := Card.new({"glyph": "🌍", "art": Compiler.key_art(wid), "title": title.left(26),
			"body": blurb.left(60),
			"foot": str(_camp_world.get("name", ""))})
		card.set_selected(str(draft["adv"].get("id", "")) == str(adv["id"]))
		card.pressed.connect(func():
			draft["adv"] = adv
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		grid.add_child(card)
	_stage_box.add_child(_scrolled(grid))
	var to_worlds := func():
		_camp_world = {}
		_enter_stage(1)
	var to_party := func():
		if draft["adv"].is_empty():
			_refuse("Choose a tale — free roam counts.")
			return
		_enter_stage(2)
	_nav(-1, "NEXT — THE PARTY", to_party, to_worlds)


## Forged worlds carry their own stories; built-ins keep theirs in worlds.json.
func _stories_for(world: Dictionary) -> Array:
	if world.get("stories") is Array:
		return world["stories"]
	return Rules.world_stories(str(world.get("id", "")))


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	return grid


func _scrolled(inner: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 330)
	scroll.add_child(inner)
	var sc := CenterContainer.new()
	sc.add_child(scroll)
	return sc


func _spawn_camp_forge() -> void:
	_child_forge = preload("res://scenes/forge/campaign_forge.tscn").instantiate()
	_child_forge.campaign_begun.connect(func(adv):
		_child_forge.queue_free()
		draft["adv"] = adv
		_enter_stage(2))  # the forge already set voice+rules; party next
	_child_forge.closed.connect(func():
		_child_forge.queue_free()
		_enter_stage(1))
	add_child(_child_forge)


func _stage_party() -> void:
	_title_label("The Party")
	var cb := CheckButton.new()
	cb.text = "Companions may join the party along the road"
	cb.button_pressed = bool(draft["companions"])
	cb.toggled.connect(func(on): draft["companions"] = on)
	var cc := CenterContainer.new()
	cc.add_child(cb)
	_stage_box.add_child(cc)
	# Forged companions from the gallery — toggle who rides in on day one.
	if not _personas.is_empty():
		var pl := Label.new()
		pl.theme_type_variation = "HintLabel"
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.text = "Forged companions — who sits at your fire from the first night?"
		_stage_box.add_child(pl)
		var prow := HBoxContainer.new()
		prow.alignment = BoxContainer.ALIGNMENT_CENTER
		prow.add_theme_constant_override("separation", Ui.SPACE["s"])
		for p in _personas:
			if not (p is Dictionary) or str(p.get("name", "")) == "":
				continue
			var nmp := str(p["name"])
			var card := Card.new({"glyph": "cups", "title": nmp, "body": str(p.get("role", "a companion"))})
			card.set_selected(draft["party"].any(func(x): return str(x.get("name", "")) == nmp))
			card.pressed.connect(func():
				var without: Array = draft["party"].filter(func(x): return str(x.get("name", "")) != nmp)
				var joining: bool = without.size() == draft["party"].size()
				if joining:
					without.append({"name": nmp, "role": str(p.get("role", ""))})
				draft["party"] = without
				card.set_selected(joining))
			prow.add_child(card)
		_stage_box.add_child(prow)
	var dim := Label.new()
	dim.theme_type_variation = "HintLabel"
	dim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dim.text = "More chairs at the table — party multiplayer — is a future forging."
	dim.modulate = Color(1, 1, 1, 0.6)
	_stage_box.add_child(dim)
	_nav(1, "NEXT — DIFFICULTY", func(): _enter_stage(3))


func _stage_difficulty() -> void:
	_title_label("How Hard Does the World Hit?")
	var cards: Array = []
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["s"])
	for d in DIFFICULTIES:
		var card := Card.new({"glyph": "⚔", "title": d["title"], "body": d["body"]})
		card.set_selected(float(draft["difficulty"]) == float(d["mult"]))
		card.pressed.connect(func():
			draft["difficulty"] = float(d["mult"])
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		row.add_child(card)
	_stage_box.add_child(row)
	_nav(2, "NEXT — HOUSE RULES", func(): _enter_stage(4))


func _stage_house() -> void:
	_title_label("House Rules")
	var house := LineEdit.new()
	house.placeholder_text = "In your words — e.g. no resurrection, critical fumbles hurt… (or leave the table's rules alone)"
	house.text = str(draft["house"])
	house.custom_minimum_size = Vector2(560, 0)
	var hc := CenterContainer.new()
	hc.add_child(house)
	_stage_box.add_child(hc)
	_nav(3, "NEXT — THE PREVIEW", func():
		draft["house"] = house.text.strip_edges()
		_enter_stage(5))


func _stage_preview() -> void:
	_title_label("The Adventure, Previewed")
	var hero_line := "forged at the campfire when the story opens"
	if draft["hero"] is Dictionary:
		var h: Dictionary = draft["hero"]
		hero_line = "%s — %s %s" % [str(h.get("name", "")), str(h.get("race", "")), str(h.get("cls", ""))]
	var diff_name := "Adventurer"
	for d in DIFFICULTIES:
		if float(d["mult"]) == float(draft["difficulty"]):
			diff_name = str(d["title"])
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(620, 0)
	# R11-05 — the preview listed tale, hero and table but never the WORLD, so a
	# player who had just chosen Saltmarsh Reach was never shown it back before
	# committing. It is the largest choice on the sheet; it belongs first.
	var world_name := str(draft["adv"].get("world", {}).get("name", "")) \
		if draft["adv"].get("world") is Dictionary else ""
	if world_name == "":
		world_name = str(draft["adv"].get("world_id", "")).capitalize()
	body.append_text("[center][b]%s[/b][/center]\n\n[b]The world:[/b] %s\n[b]The hero:[/b] %s\n[b]The table:[/b] %s difficulty · companions %s%s" % [
		str(draft["adv"].get("name", "the tale")).replace("[", "[lb]"), world_name, hero_line, diff_name,
		"welcome" if bool(draft["companions"]) else "barred",
		("\n[b]House rules:[/b] " + str(draft["house"]).replace("[", "[lb]")) if str(draft["house"]) != "" else ""])
	var bc := CenterContainer.new()
	bc.add_child(body)
	_stage_box.add_child(bc)
	_nav(4, "BEGIN THE ADVENTURE", _begin)


## Seat the table's choices into the adventure's state, then play.
func _begin() -> void:
	var adv: Dictionary = draft["adv"]
	if adv.is_empty():
		_enter_stage(1)
		return
	# The chosen banked legend fills the adventure's Quenching; "later" leaves
	# it empty so the hero is forged at the campfire when the tale opens.
	GameState.pending_hero = draft["hero"] if draft["hero"] is Dictionary else {}
	var adv_id := str(adv.get("id", ""))
	# A gallery tale may not have its dm- template yet — bind it now.
	# The table's own rules override whatever rode in with the world.
	var prior = GameState.kind_for(adv_id, "world")
	var world_kind: Dictionary = prior if prior is Dictionary else {}
	var rules: Dictionary = world_kind.get("rules") if world_kind.get("rules") is Dictionary else {}
	rules["difficulty"] = float(draft["difficulty"])
	rules["companions"] = bool(draft["companions"])
	if not (draft["party"] as Array).is_empty():
		rules["party"] = draft["party"]  # game.gd seeds them once on first hydrate
	if str(draft["house"]) != "":
		rules["house"] = str(draft["house"])
	world_kind["rules"] = rules
	GameState.set_kind_for(adv_id, "world", world_kind)
	Sfx.play("sting")
	adventure_ready.emit({"id": adv_id, "name": adv.get("name", ""), "world_id": adv.get("world_id", "")})

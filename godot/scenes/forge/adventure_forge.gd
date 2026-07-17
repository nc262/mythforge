extends Control
## 🧭 Begin a New Adventure — not "New Game": the sitting-down-at-the-table
## ritual that orchestrates both Forges. Choose or forge the hero, choose or
## forge the campaign, set the party and the table, preview, begin — like a
## tabletop night before the first dice are rolled.

signal adventure_ready(adv: Dictionary)
signal closed

const STAGES := ["The Table", "The Hero", "The Campaign", "The Party", "Difficulty", "House Rules", "The Preview"]
const DIFFICULTIES := [
	{"glyph": "hero", "title": "Story", "body": "foes soften — the tale leads", "mult": 0.75},
	{"glyph": "hero", "title": "Adventurer", "body": "the intended fight", "mult": 1.0},
	{"glyph": "hero", "title": "Veteran", "body": "foes hit harder, last longer", "mult": 1.25},
	{"glyph": "hero", "title": "Merciless", "body": "the world does not blink", "mult": 1.5},
]

const Card := preload("res://ui/myth_choice_card.gd")
const Rail := preload("res://ui/myth_stage_rail.gd")
const BtnM := preload("res://ui/myth_button.gd")

var draft := {"hero": "", "adv": {}, "companions": true, "difficulty": 1.0, "house": ""}
var _rail: MythStageRail
var _stage_box: VBoxContainer
var _status: Label
var _worlds: Array = []
var _child_forge: Control = null


func _ready() -> void:
	theme = Ui.theme
	MythEnvironment.mount(self, "env-fireside", "dust", [Vector2(0.12, 0.3)])
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, Ui.SPACE["xl"] * 2)
	margin.add_theme_constant_override("margin_top", Ui.SPACE["l"])
	margin.add_theme_constant_override("margin_bottom", Ui.SPACE["l"])
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	margin.add_child(col)
	_rail = Rail.new(STAGES)
	_rail.stage_clicked.connect(_enter_stage)
	col.add_child(_rail)
	_stage_box = VBoxContainer.new()
	_stage_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_box.add_theme_constant_override("separation", Ui.SPACE["m"])
	col.add_child(_stage_box)
	_status = Label.new()
	_status.theme_type_variation = "HintLabel"
	_status.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	_load_worlds()
	_enter_stage(0)


func _load_worlds() -> void:
	var g := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/_global")
	var cw: Array = g.get("state", {}).get("cworlds", []) if g.get("state") is Dictionary and g["state"].get("cworlds") is Array else []
	_worlds = Rules.builtin_worlds() + cw


func _clear_stage() -> void:
	for ch in _stage_box.get_children():
		ch.queue_free()


func _title_label(text: String) -> void:
	var t := Label.new()
	t.theme_type_variation = "TitleLabel"
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_box.add_child(t)


func _nav(back_to: int, fwd_text: String, fwd: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	if back_to >= 0:
		var back := BtnM.new("BACK", "", "leather")
		back.custom_minimum_size = Vector2(140, 52)
		back.pressed.connect(func(): _enter_stage(back_to))
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


func _enter_stage(i: int) -> void:
	_rail.set_stage(i)
	_clear_stage()
	_status.text = ""
	match i:
		0:
			_stage_welcome()
		1:
			_stage_hero()
		2:
			_stage_campaign()
		3:
			_stage_party()
		4:
			_stage_difficulty()
		5:
			_stage_house()
		6:
			_stage_preview()
	Ui.polish(_stage_box)
	Ui.reveal_children(_stage_box, 0.05)


func _stage_welcome() -> void:
	_title_label("The Table Is Set")
	var line := Label.new()
	line.theme_type_variation = "HintLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.text = "A hero. A campaign. A table. Everything else is dice."
	_stage_box.add_child(line)
	_nav(-1, "SIT DOWN", func(): _enter_stage(1))


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
		var card := Card.new({"glyph": "banner", "title": str(hd.get("name", "The legend")),
			"body": "%s %s" % [str(hd.get("race", "")), str(hd.get("cls", ""))], "foot": "your roster"})
		card.set_selected(_hero_selected(hd))
		card.pressed.connect(func():
			draft["hero"] = hd
			for c in cards:
				c.set_selected(c == card))
		cards.append(card)
		flow.add_child(card)
	var forge_card := Card.new({"glyph": "anvil", "title": "Forge a Hero now", "body": "walk the anvil's eleven runes"})
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
	_nav(0, "NEXT — THE CAMPAIGN", func():
		if not (draft["hero"] is Dictionary) and str(draft["hero"]) != "later":
			draft["hero"] = heroes[0] if not heroes.is_empty() else "later"
		_enter_stage(2))


func _hero_selected(hd: Dictionary) -> bool:
	return draft["hero"] is Dictionary and str(draft["hero"].get("name", "")).nocasecmp_to(str(hd.get("name", ""))) == 0


func _spawn_char_forge() -> void:
	_child_forge = preload("res://scenes/forge/character_forge.tscn").instantiate()
	_child_forge.menu_mode = true
	_child_forge.hero_forged.connect(func(d):
		GameState.bank_hero(d)
		_child_forge.queue_free()
		draft["hero"] = d
		_enter_stage(1))
	_child_forge.closed.connect(func():
		_child_forge.queue_free()
		_enter_stage(1))
	add_child(_child_forge)


func _stage_campaign() -> void:
	_title_label("Which Tale?")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	var cards: Array = []
	var forge_card := Card.new({"glyph": "⚒", "title": "Forge a Campaign now", "body": "the war table awaits", "foot": "world + voice + rules"})
	forge_card.pressed.connect(_spawn_camp_forge)
	cards.append(forge_card)
	grid.add_child(forge_card)
	for w in _worlds:
		var wid := str(w.get("id", ""))
		var stories: Array = w.get("stories") if w.get("stories") is Array else []
		var opts: Array = [{}] + stories
		for st in opts:
			var story: Dictionary = st if st is Dictionary else {}
			var slug := str(story.get("slug", "freeroam")) if not story.is_empty() else "freeroam"
			var title := str(story.get("title", "")) if not story.is_empty() else "%s: Free Roam" % str(w.get("name", ""))
			var adv := {"id": "dm-%s-%s" % [wid, slug], "name": title, "world_id": wid, "world": w, "story": story}
			var card := Card.new({"glyph": "🌍", "title": title.left(26),
				"body": str(w.get("name", "")), "foot": str(story.get("hook", "")).left(40)})
			card.set_selected(str(draft["adv"].get("id", "")) == str(adv["id"]))
			card.pressed.connect(func():
				draft["adv"] = adv
				for c in cards:
					c.set_selected(c == card))
			cards.append(card)
			grid.add_child(card)
			if cards.size() >= 12:
				break
		if cards.size() >= 12:
			break
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 330)
	scroll.add_child(grid)
	var sc := CenterContainer.new()
	sc.add_child(scroll)
	_stage_box.add_child(sc)
	_nav(1, "NEXT — THE PARTY", func():
		if draft["adv"].is_empty():
			_status.text = "Choose a tale — or forge one at the war table."
			return
		_enter_stage(3))


func _spawn_camp_forge() -> void:
	_child_forge = preload("res://scenes/forge/campaign_forge.tscn").instantiate()
	_child_forge.campaign_begun.connect(func(adv):
		_child_forge.queue_free()
		draft["adv"] = adv
		_enter_stage(3))  # the forge already set voice+rules; party next
	_child_forge.closed.connect(func():
		_child_forge.queue_free()
		_enter_stage(2))
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
	var dim := Label.new()
	dim.theme_type_variation = "HintLabel"
	dim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dim.text = "More chairs at the table — party multiplayer — is a future forging."
	dim.modulate = Color(1, 1, 1, 0.6)
	_stage_box.add_child(dim)
	_nav(2, "NEXT — DIFFICULTY", func(): _enter_stage(4))


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
	_nav(3, "NEXT — HOUSE RULES", func(): _enter_stage(5))


func _stage_house() -> void:
	_title_label("House Rules")
	var house := LineEdit.new()
	house.placeholder_text = "In your words — e.g. no resurrection, critical fumbles hurt… (or leave the table's rules alone)"
	house.text = str(draft["house"])
	house.custom_minimum_size = Vector2(560, 0)
	var hc := CenterContainer.new()
	hc.add_child(house)
	_stage_box.add_child(hc)
	_nav(4, "NEXT — THE PREVIEW", func():
		draft["house"] = house.text.strip_edges()
		_enter_stage(6))


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
	body.append_text("[center][b]%s[/b][/center]\n\n[b]The hero:[/b] %s\n[b]The table:[/b] %s difficulty · companions %s%s" % [
		str(draft["adv"].get("name", "the tale")).replace("[", "[lb]"), hero_line, diff_name,
		"welcome" if bool(draft["companions"]) else "barred",
		("\n[b]House rules:[/b] " + str(draft["house"]).replace("[", "[lb]")) if str(draft["house"]) != "" else ""])
	var bc := CenterContainer.new()
	bc.add_child(body)
	_stage_box.add_child(bc)
	_nav(5, "BEGIN THE ADVENTURE", _begin)


## Seat the table's choices into the adventure's state, then play.
func _begin() -> void:
	var adv: Dictionary = draft["adv"]
	if adv.is_empty():
		_enter_stage(2)
		return
	# The chosen banked legend fills the adventure's Quenching; "later" leaves
	# it empty so the hero is forged at the campfire when the tale opens.
	GameState.pending_hero = draft["hero"] if draft["hero"] is Dictionary else {}
	var adv_id := str(adv.get("id", ""))
	# A gallery tale may not have its dm- template yet — bind it now.
	if adv.has("world"):
		var w: Dictionary = adv["world"]
		var full := w.duplicate(true)
		if not (full.get("locations") is Array) or full.get("locations", []).is_empty():
			full["locations"] = Rules.world_locations(str(w.get("id", "")))
		await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/save", {
			"id": adv_id, "name": adv.get("name", ""),
			"personality": Composer.compose_world_gm(full, adv.get("story", {})),
			"relationship": "Dungeon Master", "world_id": str(w.get("id", "")),
		})
	# The table's own rules override whatever rode in with the world.
	var st := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/" + adv_id.uri_encode())
	var world_kind: Dictionary = st.get("state", {}).get("world", {}) if st.get("state") is Dictionary and st["state"].get("world") is Dictionary else {}
	var rules: Dictionary = world_kind.get("rules") if world_kind.get("rules") is Dictionary else {}
	rules["difficulty"] = float(draft["difficulty"])
	rules["companions"] = bool(draft["companions"])
	if str(draft["house"]) != "":
		rules["house"] = str(draft["house"])
	world_kind["rules"] = rules
	await Api.call_json(HTTPClient.METHOD_PUT, "/api/characters/studio/state/%s/world" % adv_id.uri_encode(), {"value": world_kind})
	Sfx.play("sting")
	adventure_ready.emit({"id": adv_id, "name": adv.get("name", ""), "world_id": adv.get("world_id", "")})

extends AcceptDialog
## The Hero's Record (docs/rituals/CharacterScreen.md) — an AAA character
## sheet. A persistent hero panel on the left (face, name, vitals, equipped),
## and a real TAB RAIL on the right that swaps full pages: Record · Skills ·
## Powers · Story. No more text-link "buttons": these are pages. Skin-ready —
## every colour resolves through Ui.c(), so the World Skin will retint it.

signal open_pack

const DOLL_SLOTS := [["weapon", "Main hand"], ["armor", "Armor"], ["offhand", "Off hand"], ["shield", "Shield"]]
const TABS := ["Record", "Skills", "Powers", "Story"]

var _pages := {}      # tab name → page Control
var _tabs := {}       # tab name → Button
var _host: Control     # the page container
var _active := "Record"


func _init() -> void:
	var s := GameState.sheet()
	title = "The Record of %s" % str(s.get("name", "the hero"))
	ok_button_text = "Return to the tale"
	min_size = Vector2i(1060, 720)


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Ui.SPACE["l"])
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", Ui.SPACE["xl"])
	margin.add_child(root)
	root.add_child(_hero_panel())
	# ── Right: the tab rail over a swapping page host ──
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Ui.SPACE["m"])
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", Ui.SPACE["xs"])
	for name in TABS:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(132, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_show_page.bind(name))
		_tabs[name] = b
		rail.add_child(b)
	right.add_child(rail)
	var underline := ColorRect.new()
	underline.color = Color(Ui.c("border"), 0.6)
	underline.custom_minimum_size = Vector2(0, 1)
	right.add_child(underline)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_host = VBoxContainer.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_host)
	right.add_child(scroll)
	root.add_child(right)
	add_child(margin)
	# Build every page once; the rail toggles visibility.
	_pages["Record"] = _page_record()
	_pages["Skills"] = _page_skills()
	_pages["Powers"] = _page_powers()
	_pages["Story"] = _page_story()
	for name in TABS:
		_pages[name].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_host.add_child(_pages[name])
	_show_page(_active)
	confirmed.connect(queue_free)


func _show_page(name: String) -> void:
	_active = name
	for k in _pages:
		_pages[k].visible = (k == name)
	for k in _tabs:
		_style_tab(_tabs[k], k == name)
	if _pages.has(name):
		Ui.reveal(_pages[name])


func _style_tab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(Ui.SPACE["s"])
	sb.corner_radius_top_left = Ui.RADIUS["m"]
	sb.corner_radius_top_right = Ui.RADIUS["m"]
	if active:
		sb.bg_color = Color(Ui.c("surface2"), 0.85)
		sb.border_width_bottom = 2
		sb.border_color = Ui.c("gold")
	else:
		sb.bg_color = Color(Ui.c("surface"), 0.0)
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_color_override("font_color", Ui.c("gold") if active else Ui.c("ink_dim"))
	btn.add_theme_color_override("font_hover_color", Ui.c("gold_soft") if active else Ui.c("ink_soft"))


# ── The persistent hero panel ────────────────────────────────────────────────
func _hero_panel() -> Control:
	var s := GameState.sheet()
	var inv := GameState.inv()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(310, 0)
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	var portrait := MythPortrait.new(180, "gold", true)
	portrait.set_portrait(Art.round_tex("hero-" + GameState.cid().validate_filename()), str(s.get("name", "?")).left(1))
	var pc := CenterContainer.new()
	pc.add_child(portrait)
	col.add_child(pc)
	Ui.breathe(portrait)
	var nm := Label.new()
	nm.theme_type_variation = "TitleLabel"
	nm.add_theme_font_size_override("font_size", 28)
	nm.text = str(s.get("name", "the hero"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var world_nm := str(GameState.character.get("world_id", "")).capitalize()
	var ep := Label.new()
	ep.theme_type_variation = "HintLabel"
	ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ep.text = "Level %d %s %s%s" % [int(s.get("level", 1)), str(s.get("race", "")), str(s.get("cls", "")),
		("   ·   " + world_nm) if world_nm != "" else ""]
	col.add_child(ep)
	var lvl := int(s.get("level", 1))
	var hp := MythGauge.new("HP  %d / %d" % [int(s.get("hp", 10)), int(s.get("hpMax", 10))], "danger")
	hp.custom_minimum_size = Vector2(0, 20)
	hp.set_value(float(s.get("hp", 10)), float(s.get("hpMax", 10)))
	col.add_child(hp)
	var xp_now := int(s.get("xp", 0)) - Rules.xp_for_level(lvl)
	var xp_need := Rules.xp_for_level(lvl + 1) - Rules.xp_for_level(lvl)
	var xp := MythGauge.new("XP → level %d" % (lvl + 1), "amethyst")
	xp.custom_minimum_size = Vector2(0, 20)
	xp.set_value(float(maxi(xp_now, 0)), float(maxi(xp_need, 1)))
	col.add_child(xp)
	var purse := Label.new()
	purse.theme_type_variation = "HintLabel"
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	purse.text = "%d %s in the purse" % [int(s.get("gold", 0)), GameState.currency()]
	col.add_child(purse)
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		var cl := Label.new()
		cl.add_theme_color_override("font_color", Ui.c("danger"))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.text = "Afflicted: " + ", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c)))
		col.add_child(cl)
	col.add_child(MythHeader.new("Equipped"))
	var eq: Dictionary = inv.get("equipped", {})
	for spec in DOLL_SLOTS:
		var row := HBoxContainer.new()
		var slot_l := Label.new()
		slot_l.theme_type_variation = "HintLabel"
		slot_l.custom_minimum_size = Vector2(108, 0)
		slot_l.text = str(spec[1])
		var it := GameState.item_by_id(str(eq.get(spec[0], "")))
		var val_l := Label.new()
		val_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if it.is_empty():
			val_l.text = "—"
			val_l.add_theme_color_override("font_color", Ui.c("ink_dim"))
		else:
			val_l.text = str(it.get("name", "?"))
			val_l.add_theme_color_override("font_color", Ui.rarity_color(str(it.get("rarity", "common"))))
		row.add_child(slot_l)
		row.add_child(val_l)
		col.add_child(row)
	var pack_btn := Button.new()
	pack_btn.theme_type_variation = "GhostButton"
	pack_btn.text = "Open the pack ›"
	pack_btn.pressed.connect(func():
		open_pack.emit()
		queue_free())
	var pbc := CenterContainer.new()
	pbc.add_child(pack_btn)
	col.add_child(pbc)
	return col


# ── Shared page helpers ──────────────────────────────────────────────────────
func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Ui.SPACE["m"])
	return v


func _body(text: String, role := "ink_soft") -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Ui.c(role))
	l.text = text
	return l


# ── Page: Record (abilities, prowess, saves) ────────────────────────────────
func _page_record() -> Control:
	var s := GameState.sheet()
	var inv := GameState.inv()
	var v := _page()
	v.add_child(MythHeader.new("The Six"))
	var stones := GridContainer.new()
	stones.columns = 3
	stones.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	stones.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for ab in Rules.ABILITIES:
		var sv := int(s.get("abilities", {}).get(ab, 10))
		var stone := PanelContainer.new()
		stone.add_theme_stylebox_override("panel", Ui.sb_card())
		stone.custom_minimum_size = Vector2(196, 78)
		var box := VBoxContainer.new()
		var al := Label.new()
		al.theme_type_variation = "HeaderLabel"
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.text = ab
		var vl := Label.new()
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 26)
		vl.add_theme_color_override("font_color", Ui.c("gold_soft"))
		vl.text = "%d" % sv
		var ml := Label.new()
		ml.theme_type_variation = "HintLabel"
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.text = "%+d" % Rules.ability_mod(sv)
		box.add_child(al)
		box.add_child(vl)
		box.add_child(ml)
		stone.add_child(box)
		stones.add_child(stone)
	var sc := CenterContainer.new()
	sc.add_child(stones)
	v.add_child(sc)
	v.add_child(MythHeader.new("Prowess"))
	var dc := Rules.spell_save_dc(s)
	var lvl := int(s.get("level", 1))
	v.add_child(_stat_grid([
		["Armour Class", str(Rules.eff_ac(s, inv))],
		["Attack", "%+d" % Rules.attack_mod(s, inv)],
		["Passive Perception", str(Rules.passive_perception(s))],
		["Hit Dice", "%d / %d  (d%d)" % [lvl - int(s.get("hitDiceUsed", 0)), lvl, int(s.get("hitDie", 8))]],
		["Proficiency", "%+d" % Rules.prof_bonus(s)],
		["Spell Save DC", str(dc) if dc > 0 else "—"],
	]))
	v.add_child(MythHeader.new("Saving Throws"))
	var saves := GridContainer.new()
	saves.columns = 3
	saves.add_theme_constant_override("h_separation", Ui.SPACE["m"])
	for ab in Rules.ABILITIES:
		var mod := Rules.check_mod(s, {"ability": ab, "skill": "save"})
		var prof := _has_ci(s.get("profSaves", []), ab)
		var row := Label.new()
		row.add_theme_color_override("font_color", Ui.c("gold_soft") if prof else Ui.c("ink_soft"))
		row.text = "%s  %+d%s" % [ab, mod, "  ●" if prof else ""]
		saves.add_child(row)
	var svc := CenterContainer.new()
	svc.add_child(saves)
	v.add_child(svc)
	return v


func _stat_grid(rows: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Ui.SPACE["xl"])
	grid.add_theme_constant_override("v_separation", Ui.SPACE["xs"])
	for r in rows:
		var k := Label.new()
		k.theme_type_variation = "HintLabel"
		k.text = str(r[0])
		var val := Label.new()
		val.add_theme_color_override("font_color", Ui.c("ink"))
		val.text = str(r[1])
		grid.add_child(k)
		grid.add_child(val)
	var c := CenterContainer.new()
	c.add_child(grid)
	return c


# ── Page: Skills (all skills, proficiency highlighted) ──────────────────────
func _page_skills() -> Control:
	var s := GameState.sheet()
	var v := _page()
	v.add_child(MythHeader.new("Skills"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Ui.SPACE["xl"] * 2)
	grid.add_theme_constant_override("v_separation", Ui.SPACE["xs"])
	var names := Rules.SKILL2AB.keys()
	names.sort()
	for sk in names:
		var ab: String = Rules.SKILL2AB[sk]
		var prof := _has_ci(s.get("profSkills", []), sk)
		var mod := Rules.check_mod(s, {"ability": ab, "skill": sk})
		var row := HBoxContainer.new()
		var dot := Label.new()
		dot.custom_minimum_size = Vector2(18, 0)
		dot.text = "●" if prof else "○"
		dot.add_theme_color_override("font_color", Ui.c("gold") if prof else Ui.c("ink_dim"))
		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text = "%s  (%s)" % [str(sk).capitalize(), ab]
		nm.add_theme_color_override("font_color", Ui.c("ink") if prof else Ui.c("ink_soft"))
		var m := Label.new()
		m.text = "%+d" % mod
		m.add_theme_color_override("font_color", Ui.c("gold_soft") if prof else Ui.c("ink_soft"))
		row.add_child(dot)
		row.add_child(nm)
		row.add_child(m)
		row.custom_minimum_size = Vector2(340, 0)
		grid.add_child(row)
	var c := CenterContainer.new()
	c.add_child(grid)
	v.add_child(c)
	return v


# ── Page: Powers (spells, slots, features, feats) ───────────────────────────
func _page_powers() -> Control:
	var s := GameState.sheet()
	var v := _page()
	var spells: Array = s.get("spells", [])
	if not spells.is_empty():
		v.add_child(MythHeader.new("Spell Slots"))
		var slots: Dictionary = s.get("slots", {})
		var sk := slots.keys()
		sk.sort()
		var any_slot := false
		for l in sk:
			if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
				any_slot = true
				var used := int(slots[l].get("used", 0))
				var pips := ""
				for i in int(slots[l]["max"]):
					pips += "○ " if i < used else "● "
				var sl := Label.new()
				sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				sl.add_theme_color_override("font_color", Ui.c("amethyst"))
				sl.text = "Circle %s    %s" % [str(l), pips.strip_edges()]
				v.add_child(sl)
		if not any_slot:
			v.add_child(_body("  Cantrips only — no slots to spend.", "ink_dim"))
		v.add_child(MythHeader.new("Spells Known"))
		v.add_child(_body("  " + ", ".join(spells.map(func(sp): return str(sp.get("name", "")))), "amethyst"))
	var feats: Array = s.get("feats", [])
	var feats_shown := false
	if not feats.is_empty():
		v.add_child(MythHeader.new("Feats"))
		feats_shown = true
		for f in feats:
			v.add_child(_body("  ★ " + str(f), "gold_soft"))
	var features: Array = s.get("features", [])
	if not features.is_empty():
		v.add_child(MythHeader.new("Class Features"))
		feats_shown = true
		for f in features:
			v.add_child(_body("  ◆ " + str(f), "ink_soft"))
	if spells.is_empty() and not feats_shown:
		v.add_child(_body("This hero's power is in steel and grit — no spells or special features yet. They come with the levels.", "ink_dim"))
	return v


# ── Page: Story (heritage, background, the player's own tale, companions) ───
func _page_story() -> Control:
	var s := GameState.sheet()
	var v := _page()
	var heritage: Dictionary = Rules.tables.get("heritages", {}).get(str(s.get("race", "")), {})
	var traits: Array = heritage.get("traits", [])
	if not traits.is_empty():
		v.add_child(MythHeader.new("Heritage — %s" % str(s.get("race", ""))))
		for t in traits:
			v.add_child(_body("  • " + str(t), "ink_soft"))
	var bg := str(s.get("background", ""))
	var bgd: Dictionary = Rules.tables.get("backgrounds", {}).get(bg, {})
	if bg != "":
		v.add_child(MythHeader.new("Background — %s" % bg))
		if str(bgd.get("line", "")) != "":
			v.add_child(_body("  " + str(bgd.get("line", "")), "ink_soft"))
	var story = s.get("story")
	if story is Dictionary and not story.is_empty():
		v.add_child(MythHeader.new("Their Own Tale"))
		if str(story.get("background", "")) != "":
			v.add_child(_body("  " + str(story["background"]), "gold_soft"))
		if str(story.get("class", "")) != "":
			v.add_child(_body("  " + str(story["class"]), "gold_soft"))
	var comps: Array = s.get("companions", [])
	if not comps.is_empty():
		v.add_child(MythHeader.new("Companions"))
		for cmp in comps:
			v.add_child(_body("  %s — %d/%d HP" % [str(cmp.get("name", "?")), int(cmp.get("hp", 0)), int(cmp.get("hpMax", 1))], "ink_soft"))
	if v.get_child_count() == 0:
		v.add_child(_body("The story is still being written.", "ink_dim"))
	return v


func _has_ci(arr: Array, needle: String) -> bool:
	for x in arr:
		if str(x).nocasecmp_to(needle) == 0:
			return true
	return false

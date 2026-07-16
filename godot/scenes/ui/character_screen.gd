extends AcceptDialog
## 🛡 The Hero's Record (docs/rituals/CharacterScreen.md): identity before
## statistics. The painted face and the name in gold first; the six carved
## stones; prowess; and the long lists folded away until wanted. A reading
## surface — actions live in the Pack and the side sheet.

signal open_pack

const TYPE_GLYPH := {"weapon": "⚔", "armor": "🥋", "shield": "⛨", "gear": "🧪"}
const DOLL_SLOTS := [["weapon", "⚔"], ["armor", "🥋"], ["offhand", "🗡"], ["shield", "⛨"]]


func _init() -> void:
	var s := GameState.sheet()
	title = "🛡 The Record of %s" % str(s.get("name", "the hero"))
	ok_button_text = "Return to the tale"
	min_size = Vector2i(940, 620)


func _ready() -> void:
	var s := GameState.sheet()
	var inv := GameState.inv()
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", Ui.SPACE["xl"])

	# ── Identity: the face, the name in gold, the life beneath ──
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", Ui.SPACE["m"])
	var portrait := MythPortrait.new(170, "gold", true)
	portrait.set_portrait(Art.round_tex("hero-" + GameState.cid().validate_filename()),
		str(s.get("name", "?")).left(1))
	var pc := CenterContainer.new()
	pc.add_child(portrait)
	left.add_child(pc)
	Ui.breathe(portrait)
	var nm := Label.new()
	nm.theme_type_variation = "TitleLabel"
	nm.add_theme_font_size_override("font_size", 26)
	nm.text = str(s.get("name", "the hero"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(nm)
	var epithet := Label.new()
	epithet.theme_type_variation = "HintLabel"
	epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var world_nm := str(GameState.character.get("world_id", "")).capitalize()
	epithet.text = "%s %s of %s   ·   Level %d%s" % [str(s.get("race", "")), str(s.get("cls", "")),
		world_nm if world_nm != "" else "the wilds", int(s.get("level", 1)),
		("   ·   " + str(s.get("subclass", ""))) if str(s.get("subclass", "")) != "" else ""]
	left.add_child(epithet)
	var hp := MythGauge.new("HP", "danger")
	hp.custom_minimum_size = Vector2(0, 18)
	hp.set_value(float(s.get("hp", 10)), float(s.get("hpMax", 10)))
	left.add_child(hp)
	var lvl := int(s.get("level", 1))
	var xp_now := int(s.get("xp", 0)) - Rules.xp_for_level(lvl)
	var xp_need := Rules.xp_for_level(lvl + 1) - Rules.xp_for_level(lvl)
	var xp := MythGauge.new("XP → level %d" % (lvl + 1), "amethyst")
	xp.custom_minimum_size = Vector2(0, 18)
	xp.set_value(float(maxi(xp_now, 0)), float(maxi(xp_need, 1)))
	left.add_child(xp)
	var purse := Label.new()
	purse.theme_type_variation = "HintLabel"
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	purse.text = "%d %s in the purse" % [int(s.get("gold", 0)), GameState.currency()]
	left.add_child(purse)
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		var cl := Label.new()
		cl.add_theme_color_override("font_color", Ui.c("danger"))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.text = "⚠ " + ", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c)))
		left.add_child(cl)
	left.add_child(MythHeader.new("Equipped"))
	var wells := HBoxContainer.new()
	wells.alignment = BoxContainer.ALIGNMENT_CENTER
	wells.add_theme_constant_override("separation", Ui.SPACE["s"])
	var eq: Dictionary = inv.get("equipped", {})
	for spec in DOLL_SLOTS:
		var socket := MythSocket.new(spec[0], spec[1], 56)
		var it := GameState.item_by_id(str(eq.get(spec[0], "")))
		if not it.is_empty():
			var p := it.duplicate()
			p["glyph"] = TYPE_GLYPH.get(str(it.get("type", "gear")), "🧪")
			p["tip_title"] = str(it.get("name", "?"))
			p["tip_rows"] = [[str(it.get("rarity", "common")).capitalize(), "ink_dim"]]
			socket.set_item(p, Art.item_tex(str(it.get("name", ""))))
		wells.add_child(socket)
	left.add_child(wells)
	var pack_btn := Button.new()
	pack_btn.theme_type_variation = "GhostButton"
	pack_btn.text = "Open the pack ›"
	pack_btn.pressed.connect(func():
		open_pack.emit()
		queue_free())
	var pbc := CenterContainer.new()
	pbc.add_child(pack_btn)
	left.add_child(pbc)
	root.add_child(left)

	# ── The record: carved stones, prowess, and the folded lists ──
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Ui.SPACE["m"])
	right.add_child(MythHeader.new("The Six"))
	var stones := GridContainer.new()
	stones.columns = 3
	stones.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	stones.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for ab in Rules.ABILITIES:
		var v := int(s.get("abilities", {}).get(ab, 10))
		var stone := PanelContainer.new()
		stone.add_theme_stylebox_override("panel", Ui.sb_card())
		stone.custom_minimum_size = Vector2(150, 62)
		var sv := VBoxContainer.new()
		var al := Label.new()
		al.theme_type_variation = "HeaderLabel"
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.text = ab
		var vl := Label.new()
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 20)
		vl.text = "%d   %+d" % [v, Rules.ability_mod(v)]
		sv.add_child(al)
		sv.add_child(vl)
		stone.add_child(sv)
		stones.add_child(stone)
	var sc := CenterContainer.new()
	sc.add_child(stones)
	right.add_child(sc)
	right.add_child(MythHeader.new("Prowess"))
	var prow := Label.new()
	prow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dc := Rules.spell_save_dc(s)
	prow.text = "AC %d   ·   Attack %+d   ·   Perception %d   ·   Hit Dice %d/%d (d%d)%s" % [
		Rules.eff_ac(s, inv), Rules.attack_mod(s, inv), Rules.passive_perception(s),
		lvl - int(s.get("hitDiceUsed", 0)), lvl, int(s.get("hitDie", 8)),
		("   ·   Spell DC %d" % dc) if dc > 0 else ""]
	right.add_child(prow)

	var skills := MythFold.new("Skills & Proficiencies", true)
	var skl := Label.new()
	skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skl.add_theme_color_override("font_color", Ui.c("ink_soft"))
	var prof: Array = s.get("profSkills", [])
	skl.text = ("  " + ", ".join(prof.map(func(x): return str(x).capitalize()))) if not prof.is_empty() else "  Untrained — talent finds its own road."
	skills.content.add_child(skl)
	right.add_child(skills)

	var spells: Array = s.get("spells", [])
	if not spells.is_empty():
		var magic := MythFold.new("Magic", true)
		var slots: Dictionary = s.get("slots", {})
		var sk := slots.keys()
		sk.sort()
		for l in sk:
			if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
				var pips := ""
				var used := int(slots[l].get("used", 0))
				for i in int(slots[l]["max"]):
					pips += "○" if i < used else "●"
				var sl := Label.new()
				sl.add_theme_color_override("font_color", Ui.c("amethyst"))
				sl.text = "  Circle %s   %s" % [str(l), pips]
				magic.content.add_child(sl)
		var known := Label.new()
		known.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		known.add_theme_color_override("font_color", Ui.c("ink_soft"))
		known.text = "  " + ", ".join(spells.map(func(sp): return str(sp.get("name", ""))))
		magic.content.add_child(known)
		right.add_child(magic)

	var deeds := MythFold.new("Deeds — feats & class features", false)
	for f in s.get("feats", []):
		var fl := Label.new()
		fl.add_theme_color_override("font_color", Ui.c("gold_soft"))
		fl.text = "  ★ " + str(f)
		deeds.content.add_child(fl)
	for f in s.get("features", []):
		var fl2 := Label.new()
		fl2.add_theme_color_override("font_color", Ui.c("ink_soft"))
		fl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl2.text = "  ◆ " + str(f)
		deeds.content.add_child(fl2)
	if deeds.content.get_child_count() > 0:
		right.add_child(deeds)

	var comps: Array = s.get("companions", [])
	if not comps.is_empty():
		var fellows := MythFold.new("Companions", false)
		for cmp in comps:
			var cl2 := Label.new()
			cl2.add_theme_color_override("font_color", Ui.c("ink_soft"))
			cl2.text = "  🛡 %s — %d/%d HP" % [str(cmp.get("name", "?")), int(cmp.get("hp", 0)), int(cmp.get("hpMax", 1))]
			fellows.content.add_child(cl2)
		right.add_child(fellows)

	scroll.add_child(right)
	root.add_child(scroll)
	add_child(root)
	confirmed.connect(queue_free)

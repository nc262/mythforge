extends ConfirmationDialog
## The level-up ceremony (M2): choices, not just numbers — the hit-die gamble,
## the subclass path at 3, feat-or-ASI at the milestones, a new spell for
## casters. Extracted from game.gd (A0 split): all stat math lives here via
## the autoloads; the play screen hears sheet_changed (mid-ceremony reroll)
## and ceremony_done(to_level, gains) and owns the mode restore, the dice
## menu rebuild, the announcement, and the skill-tree reward beat.

signal sheet_changed
signal ceremony_done(to_level: int, gains: Array)

var from_level := 1
var to_level := 2


func _ready() -> void:
	var s := GameState.sheet()
	var cls := str(s.get("cls", ""))
	title = "Level %d — %s grows" % [to_level, str(s.get("name", "the hero"))]
	ok_button_text = "Embrace it ›"
	get_cancel_button().visible = false
	min_size = Vector2i(480, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	# HP: the average is already applied — offer the gamble.
	var die := int(s.get("hitDie", 8))
	var con := Rules.ability_mod(int(s["abilities"].get("CON", 10)))
	var levels := to_level - from_level
	var hp_l := Label.new()
	hp_l.theme_type_variation = "HintLabel"
	hp_l.text = "HP: took the average (+%d per level). Feeling lucky?" % maxi(1, die / 2 + 1 + con)
	var hp_btn := Button.new()
	hp_btn.icon = Ui.ico_tex("die")
	hp_btn.expand_icon = false
	hp_btn.add_theme_constant_override("icon_max_width", 20)
	hp_btn.add_theme_color_override("icon_normal_color", Ui.c("gold"))
	hp_btn.text = "Roll the hit die instead (d%d%+d, per level)" % [die, con]
	var rolled_hp := false
	hp_btn.pressed.connect(func():
		if rolled_hp:
			return
		rolled_hp = true
		var sh := GameState.sheet()
		var delta := 0
		for i in levels:
			delta += maxi(1, randi_range(1, die) + con) - maxi(1, die / 2 + 1 + con)
		sh["hpMax"] = maxi(1, int(sh["hpMax"]) + delta)
		sh["hp"] = sh["hpMax"]
		GameState.set_sheet(sh)
		hp_btn.text = "Rolled — %s%d HP vs the average" % ["+" if delta >= 0 else "", delta]
		hp_btn.disabled = true
		sheet_changed.emit())
	box.add_child(hp_l)
	box.add_child(hp_btn)
	# Multiclass: where does this growth go? One level at a time; the engine
	# applied it to the primary — choosing another class redirects it there.
	var mc_in: OptionButton = null
	var mc_options: Array[String] = [""]
	if to_level - from_level == 1 and to_level >= 2:
		var primary := str(Rules.sheet_classes(s)[0].get("cls", ""))
		var mc_l := Label.new()
		mc_l.theme_type_variation = "HintLabel"
		mc_l.text = "Where does this growth go?"
		mc_in = OptionButton.new()
		mc_in.add_item("Deeper into the %s's road" % primary)
		var all_cls: Array = Rules.tables.get("class_presets", {}).keys()
		all_cls.sort()
		for other in all_cls:
			if str(other) == primary:
				continue
			mc_in.add_item("A level of %s (needs %s 13+)" % [other, Rules.class_prime(str(other))])
			mc_in.set_item_disabled(mc_in.item_count - 1, not Rules.can_multiclass_into(s, str(other)))
			mc_options.append(str(other))
		box.add_child(mc_l)
		box.add_child(mc_in)
	# Subclass at 3.
	var sub_in: OptionButton = null
	var subs: Array = Rules.tables.get("subclasses", {}).get(cls, [])
	if to_level >= 3 and str(s.get("subclass", "")) == "" and not subs.is_empty():
		var sub_l := Label.new()
		sub_l.theme_type_variation = "HintLabel"
		sub_l.text = "Choose your path:"
		sub_in = OptionButton.new()
		for sc in subs:
			sub_in.add_item("%s — %s" % [str(sc.get("name", "?")), str(sc.get("line", "")).left(60)])
		box.add_child(sub_l)
		box.add_child(sub_in)
	# Feat or ASI at the milestone levels the run crossed.
	var feat_in: OptionButton = null
	var crossed_asi := false
	for l in range(from_level + 1, to_level + 1):
		if l in [4, 8]:
			crossed_asi = true
	var asi_pairs: Array = []  # +1/+1 split choices; captured by confirmed below
	if crossed_asi:
		var feat_l := Label.new()
		feat_l.theme_type_variation = "HintLabel"
		feat_l.text = "A milestone — take a feat, or raise an ability:"
		feat_in = OptionButton.new()
		for ab in Rules.ABILITIES:
			feat_in.add_item("+2 %s (ASI)" % ab)
		for i in Rules.ABILITIES.size():
			for j in range(i + 1, Rules.ABILITIES.size()):
				asi_pairs.append([Rules.ABILITIES[i], Rules.ABILITIES[j]])
				feat_in.add_item("+1 %s / +1 %s (split)" % [Rules.ABILITIES[i], Rules.ABILITIES[j]])
		var feats: Array = Rules.tables.get("feats", {}).keys()
		feats.sort()
		for f in feats:
			feat_in.add_item("Feat: %s — %s" % [str(f), str(Rules.tables["feats"][f].get("desc", "")).left(50)])
		box.add_child(feat_l)
		box.add_child(feat_in)
	# New spells for casters.
	var spell_in: OptionButton = null
	var learnable := Rules.learnable_spells(s)
	if not learnable.is_empty():
		var sp_l := Label.new()
		sp_l.theme_type_variation = "HintLabel"
		sp_l.text = "A new spell reveals itself:"
		spell_in = OptionButton.new()
		for sp in learnable:
			spell_in.add_item("%s (%s) — %s" % [str(sp.get("name", "?")),
				("lvl %d" % int(sp["level"])) if int(sp.get("level", 0)) > 0 else "cantrip",
				str(sp.get("desc", "")).left(46)])
		box.add_child(sp_l)
		box.add_child(spell_in)
	add_child(box)
	confirmed.connect(func():
		var gains: Array[String] = []
		# Redirect FIRST — it writes the sheet, and everything below must read fresh.
		if mc_in != null and mc_in.selected > 0:
			if GameState.redirect_level(mc_options[mc_in.selected]) != "":
				gains.append("a level of %s" % mc_options[mc_in.selected])
		var sh := GameState.sheet()
		if sub_in != null:
			var chosen: Dictionary = subs[sub_in.selected]
			sh["subclass"] = str(chosen.get("name", ""))
			# subclass_grants values are a String OR an Array — Battle Master's
			# bare "Combat Maneuver" would append per-CHARACTER via Array + String.
			var raw = Rules.tables.get("subclass_grants", {}).get(sh["subclass"], [])
			var grants: Array = [raw] if raw is String else (raw if raw is Array else [])
			sh["features"] = sh.get("features", []) + grants
			gains.append("the path of the %s" % sh["subclass"])
		if feat_in != null:
			var idx := feat_in.selected
			if idx < Rules.ABILITIES.size():
				var ab: String = Rules.ABILITIES[idx]
				sh["abilities"][ab] = int(sh["abilities"].get(ab, 10)) + 2
				gains.append("+2 %s" % ab)
			elif idx < Rules.ABILITIES.size() + asi_pairs.size():
				var pr: Array = asi_pairs[idx - Rules.ABILITIES.size()]
				sh["abilities"][pr[0]] = int(sh["abilities"].get(pr[0], 10)) + 1
				sh["abilities"][pr[1]] = int(sh["abilities"].get(pr[1], 10)) + 1
				gains.append("+1 %s and +1 %s" % [pr[0], pr[1]])
			else:
				var fname: String = feat_in.get_item_text(idx).trim_prefix("Feat: ").split(" — ")[0]
				sh["feats"] = sh.get("feats", []) + [fname]
				gains.append("the %s feat" % fname)
		if spell_in != null:
			var sp: Dictionary = learnable[spell_in.selected]
			sh["spells"] = sh.get("spells", []) + [{"name": sp.get("name", ""), "level": int(sp.get("level", 0))}]
			gains.append("the spell %s" % str(sp.get("name", "")))
		GameState.set_sheet(sh)
		queue_free()
		ceremony_done.emit(to_level, gains))

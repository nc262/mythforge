extends AcceptDialog
## THE MENU (docs/rituals/CharacterScreen.md) — one real game menu, the way
## BG3 and Diablo do it: a persistent hero panel on the left, a tab rail on
## the right, and EVERY destination is a tab. No feature is three menus deep
## behind a tiny text link; the skill tree, the map, the chronicle and the
## table's own settings are pages in here. Skin-ready — every colour resolves
## through Ui.c(), so the World Skin retints the whole menu.

## Things the play screen owns (they stream or leave the screen) — the menu
## only asks, then closes.
signal travel_requested(place: String)
signal resume_requested(snapshot_id: String)
signal save_chapter_requested
signal leave_requested

const DOLL_SLOTS := [["weapon", "Main hand"], ["armor", "Armor"], ["offhand", "Off hand"], ["shield", "Shield"]]
const TABS := ["Record", "Gear", "Skills", "Powers", "Story", "Destiny", "Atlas", "Chronicle", "The Table"]
## Pages that cost real work (art, HTTP, big canvases) build on first visit.
const LAZY := ["Destiny", "Atlas", "Chronicle"]
## R6 BLANK-04 / PLAY-08 / AAA-09 — every one of the thirteen wells was built
## with the same "◇", so the Gear tab read as eleven identical grey diamonds and
## the player could not tell a head slot from a ring without reading the caption.
## A distinct silhouette per slot is the cheap half of the fix that AssetBake.md
## flagged ("slot silhouettes are a separate, cheaper win") and never got done.
const SLOT_GHOST := {
	"head": "⛑", "neck": "◈", "cloak": "🜄", "armor": "⛊", "hands": "✋",
	"waist": "⌁", "legs": "⑃", "feet": "👣", "ring1": "◯", "ring2": "◯",
	"weapon": "⚔", "offhand": "🜚", "shield": "🛡",
}

const GEAR_LEFT := ["head", "neck", "cloak", "armor", "hands"]
const GEAR_RIGHT := ["waist", "legs", "feet", "ring1", "ring2"]
const GEAR_BOTTOM := ["weapon", "offhand", "shield"]

var _pages := {}      # tab name → page Control
var _tabs := {}       # tab name → Button
var _host: Control     # the page container
var _gear_host: VBoxContainer  # the paper-doll page, rebuilt whenever gear changes
var _active := "Record"
var _filled := {}     # lazy pages already built
var _gear_repaint := false  # coalesces art_ready storms into one repaint
var _sockets := {}    # slot key → MythSocket, so an equip knows where to fly
var pulse_level := -1  # a freshly earned level flares on the Destiny page


func _init() -> void:
	var s := GameState.sheet()
	title = "The Record of %s" % str(s.get("name", "the hero"))
	ok_button_text = "Return to the tale"
	min_size = Vector2i(1280, 820)


func _ready() -> void:
	# Fit the menu to the screen it lives in — a fixed 1280x820 never fit the
	# 1280x800 base window, and the first layout pass (pages not yet hidden)
	# wrapped the window to ~1284 tall: OK button off-screen, mouse-unreachable.
	# Caught by tests/click_driver.
	var avail := Vector2(get_tree().root.get_visible_rect().size)
	min_size = Vector2i(mini(1280, int(avail.x) - 8), mini(820, int(avail.y) - 8))
	max_size = Vector2i(int(avail.x) - 8, int(avail.y) - 8)  # wrap_controls regrows to content min; the screen is the ceiling
	size = min_size
	# Round-5 blocker: the ✕ and Escape both did nothing, leaving "Return to the
	# tale" — clipped by the window's bottom edge — as the only way out. An
	# AcceptDialog only auto-closes when it isn't exclusive, and its close button
	# needs somewhere to go. Wire both to the same exit.
	exclusive = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	# R6 BUG-01/06/10 — the shared panel contract. Dresses off the OS title bar
	# and the grey chrome band, and (the real defect) caps this content so
	# "Return to the tale" can no longer be pushed under the window's edge.
	Ui.dress_dialog(self, margin)
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
		# Tabs SHARE the rail's width — nine fixed 126px tabs ran the rail to
		# 1166px and pushed Chronicle/The Table past the window edge, mouse-
		# unreachable (caught by tests/click_driver). But clip_text then ATE
		# the labels ("Chronic", "The Tab") — playtest #1. Smaller type and
		# tighter padding fit all nine honestly; truncation is never the answer.
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 46)
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.add_theme_font_size_override("font_size", 14)
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
	_pages["Gear"] = _page_gear()
	_pages["Skills"] = _page_skills()
	_pages["Powers"] = _page_powers()
	_pages["Story"] = _page_story()
	_pages["The Table"] = _page_table()
	for lz in LAZY:  # heavy pages: an empty host now, filled on first visit
		_pages[lz] = _page()
	for name in TABS:
		_pages[name].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pages[name].size_flags_vertical = Control.SIZE_EXPAND_FILL
		_pages[name].visible = (name == _active)  # hidden BEFORE the first layout, or the window wraps to all 9 pages stacked
		_host.add_child(_pages[name])
	_show_page(_active)
	# Item art lands async; repaint the pack when it does (auto-disconnects on
	# free). ONLY item icons, and coalesced to one repaint per frame — a busy
	# art queue (portraits, rooms) must never strobe the page. (Flicker RCA #2)
	Art.art_ready.connect(func(k):
		if _active == "Gear" and str(k).begins_with("item-") and not _gear_repaint:
			_gear_repaint = true
			call_deferred("_gear_repaint_now"))
	# Nothing paints into a frame that has gone: leaving cancels what we asked
	# the Art Director for (the doll render, item icons we'll never show).
	tree_exiting.connect(func(): Art.cancel_for(self))
	confirmed.connect(queue_free)


func _gear_repaint_now() -> void:
	_gear_repaint = false
	if _active == "Gear" and is_instance_valid(_gear_host):
		_refill_gear()


func _show_page(name: String) -> void:
	var changed := _active != name
	_active = name
	for k in _pages:
		_pages[k].visible = (k == name)
	for k in _tabs:
		_style_tab(_tabs[k], k == name)
	if changed:
		Sfx.ui("page")  # MIL §8 — a tab is a page turning, and pages sound
	if name == "Gear":
		_refill_gear()  # the paper doll reflects live equipment
	if name in LAZY and not _filled.get(name, false):
		_filled[name] = true
		match name:
			"Destiny":
				_fill_destiny()
			"Atlas":
				_fill_atlas()
			"Chronicle":
				_fill_chronicle()
	if _pages.has(name):
		Ui.reveal(_pages[name])


func _style_tab(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(Ui.SPACE["xs"])  # nine labels must fit without clipping
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
	# The hero stands on the world's own material — carved stone in Embervale,
	# lit glass in Neonspire, satchel leather in the Everyday.
	var bed := PanelContainer.new()
	bed.add_theme_stylebox_override("panel", Ui.material_sb("panel"))
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(310, 0)
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	var portrait := MythPortrait.new(180, "gold", true)
	portrait.set_portrait(Art.round_tex(Art.hero_key()), str(s.get("name", "?")).left(1))
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
	var world_nm := WorldSkin.world_name(str(GameState.character.get("world_id", "")))
	var ep := Label.new()
	ep.theme_type_variation = "HintLabel"
	ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ep.text = "Level %d %s %s%s" % [int(s.get("level", 1)), str(s.get("race", "")), str(s.get("cls", "")),
		("   ·   " + world_nm) if world_nm != "" else ""]
	col.add_child(ep)
	var lvl := int(s.get("level", 1))
	# MythGauge appends "v / m" itself — a bare caption, or HP prints twice.
	var hp := MythGauge.new("HP", "danger")
	hp.grade_by_fill = true   # R8-21 — full HP must not read as an alarm
	hp.custom_minimum_size = Vector2(0, 20)
	hp.set_value(float(s.get("hp", 10)), float(s.get("hpMax", 10)))
	col.add_child(hp)
	var xp_now := int(s.get("xp", 0)) - Rules.xp_for_level(lvl)
	var xp_need := Rules.xp_for_level(lvl + 1) - Rules.xp_for_level(lvl)
	var xp := MythGauge.new("XP to level %d:" % (lvl + 1), "amethyst")
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
	bed.add_child(col)
	return bed


# ── Shared page helpers ──────────────────────────────────────────────────────
## UI-5 — the page itself is unchanged, and that turned out to be right.
##
## Measured at 1280x800: Skills used the top 200 px and left ~365 px of painting
## under it; Powers ended at y=365; Story was two bullets and ~530 px of nothing.
## The obvious read is "centre it vertically", and that was tried — it is a
## no-op, because a ScrollContainer sizes its child to the child's minimum, so
## there is no spare height to centre within.
##
## Worth not forcing. A page of a book starts at the top of the page; two
## heritage traits floating in the middle of a fireplace would look stranded,
## not balanced. The empty space is honest — a level-4 half-elf HAS two traits.
## What actually read as broken was the HORIZONTAL mismatch below.
func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Ui.SPACE["m"])
	return v


## A READING COLUMN — the second half of the same defect.
##
## `MythHeader` centres itself and its ornaments; body text is left-aligned. In a
## ~880 px panel that put "CLASS FEATURES" at x=820 and "Arcane Recovery" at
## x=400, so the heading floated free of the thing it was heading. Constraining
## the column and centring THAT puts both in the same measure, which is what
## makes a heading look attached to its text.
##
## 620 px is a line length, not a guess: much past it and prose gets hard to
## track back to the next line.
const READ_W := 620.0


func _column() -> VBoxContainer:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(READ_W, 0)
	col.add_theme_constant_override("separation", Ui.SPACE["m"])
	wrap.add_child(col)
	_last_column_wrap = wrap
	return col


var _last_column_wrap: CenterContainer = null


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
	var page := _page()
	# UI-5: a reading column, so the centred headers and the left-aligned
	# text below them share one measure instead of drifting apart.
	var v := _column()
	page.add_child(_last_column_wrap)
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
	return page


# ── Page: Story (heritage, background, the player's own tale, companions) ───
func _page_story() -> Control:
	var s := GameState.sheet()
	var page := _page()
	# UI-5: a reading column, so the centred headers and the left-aligned
	# text below them share one measure instead of drifting apart.
	var v := _column()
	page.add_child(_last_column_wrap)
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
	return page


# ── Page: Gear — the full-body paper doll (M-F Stage A) ─────────────────────
func _page_gear() -> Control:
	_gear_host = _page()
	return _gear_host


## Rebuilt whenever equipment changes: a generated full-body figure flanked by
## every worn slot; tap a slot to swap what fills it.
func _refill_gear() -> void:
	if _gear_host == null:
		return
	for c in _gear_host.get_children():
		_gear_host.remove_child(c)  # off-tree NOW — queue_free alone leaves both generations visible for a frame (flicker)
		c.queue_free()
	_sockets.clear()
	var s := GameState.sheet()
	var inv := GameState.inv()
	_gear_host.add_child(MythHeader.new("Equipment"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Ui.SPACE["l"])
	row.add_child(_socket_col(GEAR_LEFT))
	row.add_child(_body_view(s, inv))
	row.add_child(_socket_col(GEAR_RIGHT))
	var rc := CenterContainer.new()
	rc.add_child(row)
	_gear_host.add_child(rc)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", Ui.SPACE["m"])
	for key in GEAR_BOTTOM:
		bottom.add_child(_gear_socket(str(key)))
	var bc := CenterContainer.new()
	bc.add_child(bottom)
	_gear_host.add_child(bc)
	# R8-18 — this counted a wielded blade as "worn", so an unarmoured hero with
	# one sword read "Armor Class 12 · 1 worn" while the Armour slot said "—".
	# Hands hold; only the body wears.
	var held := ["main", "off", "shield", "mainhand", "offhand"]
	var worn := 0
	for k in inv.get("equipped", {}):
		if str(inv["equipped"][k]) != "" and not (str(k).to_lower() in held):
			worn += 1
	var stat := Label.new()
	stat.theme_type_variation = "HintLabel"
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# R6 PLAY-09/CUT-14 — Armour Class is the most important defensive number the
	# player has and it was the least prominent text on the panel, trailing an
	# instruction ("click a slot to change it") that only existed to compensate
	# for a missing affordance. The wells now carry tooltips instead, so the
	# instruction is gone and the number leads.
	stat.text = "Armor Class %d   ·   %d worn" % [Rules.eff_ac(s, inv), worn]
	stat.add_theme_color_override("font_color", Ui.c("gold_soft"))
	_gear_host.add_child(stat)
	# ── The Pack — the goods live here now, not in a separate window ──────────
	_gear_host.add_child(MythHeader.new("The Pack"))
	var items: Array = inv.get("items", [])
	if items.is_empty():
		_gear_host.add_child(_body("The pack hangs empty — the road will fill it.", "ink_dim"))
		return
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	flow.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	var worn_ids: Array = inv.get("equipped", {}).values()
	for it in items:
		# Compiled catalogue items ship their own material-true icon; only the
		# legacy loose items need an icon generated on demand.
		if str(it.get("art", "")) == "":
			Art.ensure_item_icon(str(it.get("name", "")))
		var card := MythCard.new()
		card.setup(_pack_payload(it), Art.item_tex_for(it))
		# The card tells the interaction where the piece is flying FROM.
		card.activated.connect(func(p): _pack_double(str(p.get("id", "")), card.get_global_rect()))
		card.context_requested.connect(_pack_menu)
		if str(it.get("id", "")) in worn_ids:
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_color_override("font_color", Ui.c("gold"))
			dot.add_theme_font_size_override("font_size", 11)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(dot)
		flow.add_child(card)
	_gear_host.add_child(flow)
	var strap := MythGauge.new("Pack", "gold")
	strap.custom_minimum_size = Vector2(0, 18)
	strap.set_value(items.size(), int(inv.get("slots", 24)))
	_gear_host.add_child(strap)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "double-click equips   ·   right-click for more"
	_gear_host.add_child(hint)


## The card payload: the item plus its framed-tooltip story, including the
## ▲/▼ comparison against whatever is worn in the same slot.
func _pack_payload(it: Dictionary) -> Dictionary:
	var p := it.duplicate()
	p["tip_title"] = str(it.get("name", "?"))
	var rows: Array = [[str(it.get("rarity", "common")).capitalize() + " " + str(it.get("type", "gear")), "ink_dim"]]
	if it.get("dmg") != null:
		rows.append(["%s damage%s" % [it["dmg"], (" · %+d to hit" % int(it.get("atk", 0))) if int(it.get("atk", 0)) != 0 else ""]])
	if it.get("acBonus") != null:
		rows.append(["+%d AC" % int(it["acBonus"])])
	var cmp := _pack_compare(it)
	if cmp != "":
		rows.append([cmp, "gold" if cmp.begins_with("▲") else "danger"])
	rows.append(["sells for %d %s" % [Rules.sell_value(str(it.get("rarity", "common"))), GameState.currency()], "ink_dim"])
	p["tip_rows"] = rows
	return p


## "▲ +1 to hit vs Rusty Dagger" — the decision at a glance.
func _pack_compare(it: Dictionary) -> String:
	var slot := str(it.get("type", ""))
	if slot not in ["weapon", "armor", "shield"]:
		return ""
	var worn := GameState.item_by_id(str(GameState.inv().get("equipped", {}).get(slot, "")))
	if worn.is_empty() or str(worn.get("id", "")) == str(it.get("id", "")):
		return ""
	if slot == "weapon":
		var d := int(it.get("atk", 0)) - int(worn.get("atk", 0))
		if d != 0:
			return "%s %+d to hit vs %s" % ["▲" if d > 0 else "▼", d, str(worn.get("name", "equipped"))]
		return "same to-hit as %s (%s vs %s dmg)" % [str(worn.get("name", "")), str(it.get("dmg", "?")), str(worn.get("dmg", "?"))]
	var d2 := int(it.get("acBonus", 0)) - int(worn.get("acBonus", 0))
	if d2 != 0:
		return "%s %+d AC vs %s" % ["▲" if d2 > 0 else "▼", d2, str(worn.get("name", "equipped"))]
	return ""


## MIL — the worked reference interaction. Data changing is the *middle* act,
## not the whole event: the piece travels to its socket, the socket flares,
## the stat that moved rises off the page, and the metal settles.
func _pack_double(iid: String, from_rect := Rect2()) -> void:
	var it := GameState.item_by_id(iid)
	if str(it.get("type", "gear")) not in ["weapon", "armor", "shield"]:
		# MIL §6 — a refusal, never a silent no-op.
		if _gear_host != null:
			Ui.shake(_gear_host)
		return
	var s := GameState.sheet()
	var before_ac := Rules.eff_ac(s, GameState.inv())
	var before_atk := Rules.attack_mod(s, GameState.inv())
	var slot := str(it.get("type", ""))
	GameState.toggle_equip(iid)          # truth first — a skipped animation can never desync
	_refill_gear()
	Sfx.ui("equip")
	var after_ac := Rules.eff_ac(s, GameState.inv())
	var after_atk := Rules.attack_mod(s, GameState.inv())
	var sock: Control = _sockets.get(slot)
	if sock != null and is_instance_valid(sock):
		if from_rect.size.x > 0:
			Ui.fly_to(self, Art.item_tex_for(it), from_rect, sock.get_global_rect())
		Ui.pulse(sock)
		var delta := ""
		if after_ac != before_ac:
			delta = "%+d AC" % (after_ac - before_ac)
		elif after_atk != before_atk:
			delta = "%+d to hit" % (after_atk - before_atk)
		if delta != "":
			var gain := delta.begins_with("+")
			Ui.rise_text(self, delta, Ui.c("gold") if gain else Ui.c("danger"),
				sock.get_global_rect().position + Vector2(0, -Ui.SPACE["l"]))


func _pack_menu(p: Dictionary) -> void:
	var iid := str(p.get("id", ""))
	var worn: bool = iid in GameState.inv().get("equipped", {}).values()
	var menu := PopupMenu.new()
	menu.add_item("Unequip" if worn else "Equip", 0)
	menu.add_item("Inspect", 1)
	# R8-15 — offering a sale with nobody to sell to. Show the price either way
	# (it is useful to know what a thing is worth), but only let it happen where
	# a keeper actually stands.
	var buyer := GameState.shop_here()
	menu.add_item("Sell — %d %s" % [Rules.sell_value(str(p.get("rarity", "common"))), GameState.currency()], 2)
	if not buyer:
		menu.set_item_disabled(2, true)
		menu.set_item_tooltip(2, "No one here is buying — find a keeper first.")
	if str(p.get("type", "gear")) == "gear":
		menu.set_item_disabled(0, true)
	menu.id_pressed.connect(func(id):
		if id == 0:
			_pack_double(iid)
		elif id == 1:
			_pack_inspect(p)
		elif id == 2:
			if GameState.sell_item(iid) != "":
				Sfx.play("chime")
			_refill_gear())
	add_child(menu)
	Ui.popup_at_mouse(menu)   # UI-6: flips at a screen edge instead of clipping


## Hold the piece up to the candlelight: big art and its story.
func _pack_inspect(p: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = str(p.get("tip_title", "?"))
	dlg.ok_button_text = "Put it away"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Ui.SPACE["m"])
	var art := MythPlate.new(Vector2(320, 320), 0.5)
	art.set_texture(Art.item_tex_for(p))
	box.add_child(art)
	box.add_child(MythTooltip.build(str(p.get("tip_title", "?")), p.get("tip_rows", []), str(p.get("rarity", ""))))
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	Ui.ritual_open(dlg)
	dlg.confirmed.connect(dlg.queue_free)


func _socket_col(keys: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Ui.SPACE["s"])
	for key in keys:
		col.add_child(_gear_socket(str(key)))
	return col


func _gear_socket(key: String) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var sock := MythSocket.new(key, SLOT_GHOST.get(key, "◇"), 64)
	_sockets[key] = sock
	var it := GameState.item_by_id(str(GameState.inv().get("equipped", {}).get(key, "")))
	if not it.is_empty():
		var p := it.duplicate()
		p["tip_title"] = str(it.get("name", "?"))
		p["tip_rows"] = [[str(it.get("rarity", "common")).capitalize(), "ink_dim"]]
		sock.set_item(p, Art.item_tex_for(it))
	# The affordance the footer instruction used to stand in for (R6 PLAY-08).
	sock.tooltip_text = "%s — click to change what you wear here" % _slot_label(key)
	sock.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sock.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_slot_picker(key))
	wrap.add_child(sock)
	var lbl := Label.new()
	lbl.theme_type_variation = "HintLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.text = _slot_label(key)
	# R7-05 — the column squeezed these captions when vertical space got tight and
	# the socket below rode over "Chest". Reserve the line so it cannot collapse.
	lbl.custom_minimum_size = Vector2(0, 15)
	wrap.add_child(lbl)
	return wrap


func _slot_label(key: String) -> String:
	# R6 BUG-17: both ring wells printed a bare "Ring", so the two were
	# indistinguishable and a player could not tell which hand they were filling.
	if key == "ring1":
		return "Ring · left"
	if key == "ring2":
		return "Ring · right"
	for pair in Rules.EQUIP_SLOTS:
		if str(pair[0]) == key:
			return str(pair[1])
	return key.capitalize()


func _body_view(s: Dictionary, inv: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(238, 0)
	col.add_theme_constant_override("separation", Ui.SPACE["s"])
	# MythPlate: the shared forge frame every AI image ships in (phase 6).
	# Both keys come from Art, not from string-building. A hero banked in one
	# adventure and played in another owns art under the key they were painted
	# with; rebuilding "hero-" + cid here names a file that does not exist, so the
	# plate renders empty and the game re-commissions a face it already owns.
	var key := Art.hero_body_key()
	var plate := MythPlate.new(Vector2(230, 336))
	plate.bind_key(key, Art.texture_for(Art.hero_key()))
	if not Art.has_art(key):
		Art.ensure(key, _body_prompt(s, inv))
	col.add_child(plate)
	var rerender := Button.new()
	rerender.text = "Re-render with current gear"
	rerender.custom_minimum_size = Vector2(0, 44)   # R6 STR-27: a real touch target
	rerender.tooltip_text = "Paints your hero again, wearing exactly what they wear now."
	rerender.pressed.connect(func():
		Art.forget(key)
		Art.ensure(key, _body_prompt(GameState.sheet(), GameState.inv()))
		rerender.text = "The forge paints…"
		rerender.disabled = true
		# Re-enable when the paint lands (or dies), so the button can't be
		# hammered into a queue of duplicate commissions.
		Art.art_progress.connect(func(k, st):
			if str(k) == key and st in ["ready", "failed", "cancelled"] and is_instance_valid(rerender):
				rerender.disabled = false
				rerender.text = "Re-render with current gear"))
	col.add_child(rerender)
	return col


func _body_prompt(s: Dictionary, inv: Dictionary) -> String:
	var worn: Array[String] = []
	for k in inv.get("equipped", {}):
		var it := GameState.item_by_id(str(inv["equipped"][k]))
		if not it.is_empty():
			worn.append(str(it.get("name", "")))
	# Identity-true: world fashion ALWAYS (an Everyday cleric is not a plate
	# knight), the worn pieces named on top of it — and THE HERO'S OWN LOOK, which
	# this prompt used to omit entirely. That omission is the whole of "the
	# portrait and the doll are different people": the face was described in one
	# prompt and left to the model's imagination in the other.
	var gear := Art.subject_style("char") + ((", wearing " + ", ".join(worn)) if not worn.is_empty() else "")
	return "full body character illustration of %s, a %s %s, %s, %s, standing heroic pose, front view, %s, plain dark background, no text" % [
		str(s.get("name", "a hero")), str(s.get("race", "")), str(s.get("cls", "")),
		Art.hero_look(s), gear, Art.world_flavor()]


func _open_slot_picker(slot_key: String) -> void:
	var pop := PopupMenu.new()
	add_child(pop)
	var ids: Array = []
	var cur := str(GameState.inv().get("equipped", {}).get(slot_key, ""))
	for it in GameState.inv().get("items", []):
		if it is Dictionary and slot_key in Rules.TYPE_SLOTS.get(str(it.get("type", "")), []):
			pop.add_item(("● " if str(it.get("id", "")) == cur else "    ") + str(it.get("name", "?")))
			ids.append(str(it.get("id", "")))
	if pop.item_count == 0:
		pop.add_item("Nothing in your pack fits this slot")
		pop.set_item_disabled(0, true)
		ids.append("")
	if cur != "":
		pop.add_separator()
		pop.add_item("Unequip")
		ids.append("__off__")
	pop.id_pressed.connect(func(i):
		var chosen: String = str(ids[i]) if i < ids.size() else ""
		if chosen == "__off__":
			GameState.toggle_equip(cur)
		elif chosen != "":
			GameState.toggle_equip(chosen)
		_refill_gear())
	pop.close_requested.connect(pop.queue_free)
	Ui.popup_at_mouse(pop, 240)   # UI-6: flips at a screen edge instead of clipping


func _has_ci(arr: Array, needle: String) -> bool:
	for x in arr:
		if str(x).nocasecmp_to(needle) == 0:
			return true
	return false


# ── Page: Destiny — the constellation, in the menu instead of its own dialog ──
func _fill_destiny() -> void:
	var tree := preload("res://scenes/ui/skill_tree.gd").new()
	tree.pulse_level = pulse_level
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(0, 560)
	_pages["Destiny"].add_child(tree)


# ── Page: Atlas — the painted chart, a tab now, not two clicks deep ──────────
func _fill_atlas() -> void:
	var host: VBoxContainer = _pages["Atlas"]
	# ONE STORE. This asked the built-in gazetteer, then fell back to the forged
	# world's own list — which carries no x/y, so every pin of a forged world
	# stacked on the chart's centre. GameState.places() merges authored and
	# GM-created and guarantees coordinates.
	var locs: Array = GameState.places()
	if not is_instance_valid(host):
		return
	if locs.is_empty():
		host.add_child(_body("No charted places yet — the GM's narration is your map for now.", "ink_dim"))
		return
	Art.ensure_world_chart(GameState.world_id(), str(GameState.character.get("name", "")).split(":")[0], locs)
	var map := preload("res://scenes/ui/world_map.gd").new()
	map.locations = locs
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	# In-panel chart header: whose land this is, where you stand, what to do.
	var map_word := str(WorldSkin.skin_for_id(GameState.world_id()).get("flavor", {}).get("map", "chart")).capitalize()
	host.add_child(MythHeader.new("The %s of %s" % [map_word, str(GameState.character.get("name", "the world")).split(":")[0]]))
	if str(wd.get("here", "")) != "":
		host.add_child(_body("You are at %s — click a lamp-lit place to travel." % str(wd["here"]), "ink_dim"))
	map.here = str(wd.get("here", ""))
	map.seen = wd.get("seen") if wd.get("seen") is Array else []
	map.fog = bool(GameState.rule("fog", true))
	map.quest_text = Chronicle.quests_text()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(0, 560)
	map.travel_requested.connect(func(place: String):
		travel_requested.emit(place)
		queue_free())
	host.add_child(map)


# ── Page: Chronicle — the closed chapters, and the way back into one ─────────
func _fill_chronicle() -> void:
	var host: VBoxContainer = _pages["Chronicle"]
	var snaps: Array = Chronicle.chapters()
	if not is_instance_valid(host):
		return
	host.add_child(MythHeader.new("The Chronicle"))
	if snaps.is_empty():
		host.add_child(_body("No chapters yet — close one from The Table when a moment deserves remembering.", "ink_dim"))
		return
	for sn in snaps:
		if not (sn is Dictionary):
			continue
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Ui.sb_card())
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", Ui.SPACE["xs"])
		var t := Label.new()
		t.theme_type_variation = "HeaderLabel"
		t.text = str(sn.get("title", "A chapter"))
		box.add_child(t)
		var story := str(sn.get("story_so_far", sn.get("summary", "")))
		if story != "":
			box.add_child(_body(story.left(320), "ink_soft"))
		var sid := str(sn.get("id", ""))
		if sid != "":
			var resume := Button.new()
			resume.theme_type_variation = "GhostButton"
			resume.text = "Resume from this chapter ›"
			resume.pressed.connect(func():
				resume_requested.emit(sid)
				queue_free())
			var rc := HBoxContainer.new()
			rc.alignment = BoxContainer.ALIGNMENT_END
			rc.add_child(resume)
			box.add_child(rc)
		panel.add_child(box)
		host.add_child(panel)


# ── Page: The Table — the tone knobs and the table's own actions ─────────────
func _page_table() -> Control:
	var v := _page()
	v.add_child(MythHeader.new("The GM's Voice"))
	var knobs: Dictionary = GameState.state.get("gm", {}) if GameState.state.get("gm") is Dictionary else {}
	var sliders := {}
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", Ui.SPACE["xs"])
	for k in preload("res://scenes/ui/gm_tuner.gd").KNOBS:
		var lbl := Label.new()
		lbl.theme_type_variation = "HintLabel"
		lbl.text = "%s   %s ↔ %s" % [k[1], k[2], k[3]]
		grid.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int(knobs.get(k[0], k[4]))
		sl.custom_minimum_size = Vector2(460, 0)
		grid.add_child(sl)
		sliders[k[0]] = sl
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	var save_tone := Button.new()
	save_tone.theme_type_variation = "AccentButton"
	save_tone.text = "Set the tone"
	save_tone.pressed.connect(func():
		var out := {}
		for key in sliders:
			out[key] = int(sliders[key].value)
		GameState.save_kind("gm", out)
		save_tone.text = "The table's tone shifts")
	var sc := CenterContainer.new()
	sc.add_child(save_tone)
	v.add_child(sc)
	v.add_child(MythHeader.new("This Session"))
	var acts := VBoxContainer.new()
	acts.add_theme_constant_override("separation", Ui.SPACE["s"])
	var chapter := Button.new()
	chapter.text = "Close a chapter — the chronicler writes it down"
	chapter.custom_minimum_size = Vector2(420, 44)
	chapter.pressed.connect(func():
		save_chapter_requested.emit()
		queue_free())
	acts.add_child(chapter)
	var leave := Button.new()
	leave.theme_type_variation = "GhostButton"
	leave.text = "Return to the Hall"
	leave.custom_minimum_size = Vector2(420, 44)
	leave.pressed.connect(func():
		leave_requested.emit()
		queue_free())
	acts.add_child(leave)
	var ac := CenterContainer.new()
	ac.add_child(acts)
	v.add_child(ac)
	return v

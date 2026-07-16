extends AcceptDialog
## 🎒 The Pack — the first MDL ritual screen (docs/rituals/Inventory.md).
## The hero anchors the left: glowing portrait over carved equipment sockets.
## The right is the pack itself: only items exist, as rarity-halo cards laid
## on stitched leather — never a grid of empty boxes — with a capacity strap
## beneath. Drag to equip (sockets pulse), double-click toggles, right-click
## for Equip/Inspect/Sell, tooltips carry the ▲/▼ verdict vs what's worn,
## and the stat that changes rises off the ledger. State lives in GameState;
## this window arranges and delights.

signal inventory_changed

const TYPE_GLYPH := {"weapon": "⚔", "armor": "🥋", "shield": "⛨", "gear": "🧪"}
const DOLL_SLOTS := [["weapon", "⚔", "Main hand"], ["armor", "🥋", "Armor"], ["offhand", "🗡", "Off hand"], ["shield", "⛨", "Shield"]]

var _portrait: MythPortrait
var _sockets: Dictionary = {}   # slot_key -> MythSocket
var _flow: HFlowContainer
var _gauge: MythGauge
var _stats: Label
var _first_build := true


## The pack's leather surface — dropping a worn piece here unequips it.
class PackSurface extends PanelContainer:
	var win: Node

	func _init(w: Node) -> void:
		win = w
		add_theme_stylebox_override("panel", Ui.sb_leather())

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("id")

	func _drop_data(_pos: Vector2, data) -> void:
		win.call("handle_pack_drop", data, -1)


## A pack card that also takes drops: dropped-on card = insert here (reorder).
class PackCard extends MythCard:
	var win: Node
	var index := -1

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("id")

	func _drop_data(_pos: Vector2, data) -> void:
		win.call("handle_pack_drop", data, index)


func _init() -> void:
	title = "🎒 Your Pack"
	ok_button_text = "Put the pack away"
	min_size = Vector2i(840, 560)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", Ui.SPACE["xl"])

	# ── The hero (focal point): portrait, name, carved sockets, the ledger ──
	var doll := VBoxContainer.new()
	doll.add_theme_constant_override("separation", Ui.SPACE["m"])
	doll.custom_minimum_size = Vector2(260, 0)
	_portrait = MythPortrait.new(124, "gold", true)
	var pc := CenterContainer.new()
	pc.add_child(_portrait)
	doll.add_child(pc)
	var nm := Label.new()
	nm.name = "HeroName"
	nm.theme_type_variation = "HeaderLabel"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll.add_child(nm)
	doll.add_child(MythHeader.new("Equipped"))
	var wells := HFlowContainer.new()
	wells.alignment = FlowContainer.ALIGNMENT_CENTER
	wells.add_theme_constant_override("h_separation", Ui.SPACE["m"])
	wells.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	for spec in DOLL_SLOTS:
		var well := VBoxContainer.new()
		well.add_theme_constant_override("separation", Ui.SPACE["xs"])
		var socket := MythSocket.new(spec[0], spec[1])
		socket.dropped.connect(_on_socket_drop)
		_sockets[spec[0]] = socket
		well.add_child(socket)
		var lab := Label.new()
		lab.theme_type_variation = "HintLabel"
		lab.text = spec[2]
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		well.add_child(lab)
		wells.add_child(well)
	doll.add_child(wells)
	_stats = Label.new()
	_stats.theme_type_variation = "HintLabel"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll.add_child(_stats)
	root.add_child(doll)

	# ── The goods: cards on stitched leather, the strap gauge beneath ──
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Ui.SPACE["m"])
	right.add_child(MythHeader.new("The Goods"))
	var surface := PackSurface.new(self)
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", Ui.SPACE["s"])
	_flow.add_theme_constant_override("v_separation", Ui.SPACE["s"])
	surface.add_child(_flow)
	right.add_child(surface)
	_gauge = MythGauge.new("Pack", "gold")
	_gauge.custom_minimum_size = Vector2(0, 18)
	right.add_child(_gauge)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "drag to equip or rearrange   ·   double-click equips   ·   right-click for more"
	right.add_child(hint)
	root.add_child(right)
	add_child(root)
	confirmed.connect(queue_free)


func _ready() -> void:
	rebuild()
	Art.art_ready.connect(func(_k): rebuild())
	for it in GameState.inv().get("items", []):
		Art.ensure_item_icon(str(it.get("name", "")))
	Ui.breathe(_portrait)


func rebuild() -> void:
	var inv := GameState.inv()
	var s := GameState.sheet()
	var eq: Dictionary = inv.get("equipped", {})
	var items: Array = inv.get("items", [])
	_portrait.set_portrait(Art.round_tex("hero-" + GameState.cid().validate_filename(), 124),
		str(s.get("name", "?")).left(1))
	for n in find_children("HeroName", "Label", true, false):
		n.text = str(s.get("name", "the hero"))
	for key in _sockets:
		var socket: MythSocket = _sockets[key]
		var it := GameState.item_by_id(str(eq.get(key, "")))
		if it.is_empty():
			socket.set_item({})
		else:
			socket.set_item(_payload(it), Art.item_tex(str(it.get("name", ""))))
	_stats.text = "AC %d   ·   HP %d/%d   ·   Attack %+d   ·   %d %s" % [Rules.eff_ac(s, inv),
		int(s.get("hp", 0)), int(s.get("hpMax", 1)), Rules.attack_mod(s, inv),
		int(s.get("gold", 0)), GameState.currency()]
	for child in _flow.get_children():
		child.queue_free()
	var worn: Array = eq.values()
	var idx := 0
	for it in items:
		var card := PackCard.new()
		card.win = self
		card.index = idx
		card.setup(_payload(it), Art.item_tex(str(it.get("name", ""))))
		card.activated.connect(func(p): handle_double(str(p.get("id", ""))))
		card.context_requested.connect(_context_menu)
		if str(it.get("id", "")) in worn:
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_color_override("font_color", Ui.c("gold"))
			dot.add_theme_font_size_override("font_size", 11)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(dot)
		_flow.add_child(card)
		idx += 1
	_gauge.set_value(items.size(), int(inv.get("slots", 24)))
	if _first_build:
		_first_build = false
		Ui.reveal_children(_flow, 0.04)  # the goods laid out one by one


## The card/socket payload: the item plus its framed-tooltip story, including
## the ▲/▼ comparison against whatever is worn in the same slot.
func _payload(it: Dictionary) -> Dictionary:
	var p := it.duplicate()
	p["glyph"] = TYPE_GLYPH.get(str(it.get("type", "gear")), "🧪")
	p["tip_title"] = str(it.get("name", "?"))
	var rows: Array = [[str(it.get("rarity", "common")).capitalize() + " " + str(it.get("type", "gear")), "ink_dim"]]
	if it.get("dmg") != null:
		rows.append(["%s damage%s" % [it["dmg"], (" · %+d to hit" % int(it.get("atk", 0))) if int(it.get("atk", 0)) != 0 else ""]])
	if it.get("acBonus") != null:
		rows.append(["+%d AC" % int(it["acBonus"])])
	var cmp := _compare(it)
	if cmp != "":
		rows.append([cmp, "gold" if cmp.begins_with("▲") else "danger"])
	rows.append(["sells for %d %s" % [Rules.sell_value(str(it.get("rarity", "common"))), GameState.currency()], "ink_dim"])
	p["tip_rows"] = rows
	return p


## "▲ +1 to hit vs Rusty Dagger" — the decision at a glance.
func _compare(it: Dictionary) -> String:
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


func _context_menu(p: Dictionary) -> void:
	var iid := str(p.get("id", ""))
	var menu := PopupMenu.new()
	menu.add_item("Unequip" if _equipped_where(iid) != "" else "Equip", 0)
	menu.add_item("Inspect", 1)
	menu.add_item("Sell — %d %s" % [Rules.sell_value(str(p.get("rarity", "common"))), GameState.currency()], 2)
	if str(p.get("type", "gear")) == "gear":
		menu.set_item_disabled(0, true)
	menu.id_pressed.connect(func(id):
		if id == 0:
			handle_double(iid)
		elif id == 1:
			_inspect(p)
		elif id == 2:
			var note := GameState.sell_item(iid)
			if note != "":
				Sfx.play("chime")
				_reward("+%d %s" % [Rules.sell_value(str(p.get("rarity", "common"))), GameState.currency()], "gold")
			rebuild()
			inventory_changed.emit())
	add_child(menu)
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


## Hold the piece up to the candlelight: big art and its story.
func _inspect(p: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = str(p.get("tip_title", "?"))
	dlg.ok_button_text = "Put it away"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Ui.SPACE["m"])
	var art := TextureRect.new()
	art.texture = Art.item_tex(str(p.get("name", "")))
	art.custom_minimum_size = Vector2(320, 320)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	box.add_child(art)
	box.add_child(MythTooltip.build(str(p.get("tip_title", "?")), p.get("tip_rows", []), str(p.get("rarity", ""))))
	dlg.add_child(box)
	add_child(dlg)
	dlg.popup_centered()
	Ui.ritual_open(dlg)
	dlg.confirmed.connect(dlg.queue_free)


## The reward beat: the stat that changed rises off the ledger.
func _reward(text: String, role: String) -> void:
	Ui.rise_text(self, text, Ui.c(role), _stats.position + Vector2(_stats.size.x / 2.0 - 20, -6))


## Equip/unequip with the reward beat: chime + the stat delta rises.
func _apply_equip_change(action: Callable) -> void:
	var s := GameState.sheet()
	var before_ac := Rules.eff_ac(s, GameState.inv())
	var before_atk := Rules.attack_mod(s, GameState.inv())
	action.call()
	var after_ac := Rules.eff_ac(s, GameState.inv())
	var after_atk := Rules.attack_mod(s, GameState.inv())
	Sfx.play("chime")
	if after_ac != before_ac:
		_reward("%+d AC" % (after_ac - before_ac), "gold" if after_ac > before_ac else "danger")
	elif after_atk != before_atk:
		_reward("%+d to hit" % (after_atk - before_atk), "gold" if after_atk > before_atk else "danger")
	rebuild()
	inventory_changed.emit()


# ── Drops: socket ← equips · leather ← unequips · card ← reorders ───────────
func _on_socket_drop(data: Dictionary, slot_key: String) -> void:
	var iid := str(data.get("id", ""))
	var t := str(data.get("type", ""))
	if not (t == slot_key or (slot_key == "offhand" and t == "weapon")):
		return  # the world just doesn't take it
	_apply_equip_change(func():
		if _equipped_where(iid) == slot_key:
			_unequip(iid)
		else:
			_equip_to(iid, slot_key))


func handle_pack_drop(data: Dictionary, to_index: int) -> void:
	var iid := str(data.get("id", ""))
	if _equipped_where(iid) != "":
		_apply_equip_change(func(): _unequip(iid))
		return
	if to_index >= 0:
		var inv := GameState.inv()
		var items: Array = inv.get("items", [])
		for fi in items.size():
			if str(items[fi].get("id", "")) == iid:
				var moved = items.pop_at(fi)
				items.insert(mini(to_index, items.size()), moved)
				GameState.save_kind("inv", inv)
				break
		rebuild()
		inventory_changed.emit()


func handle_double(iid: String) -> void:
	var it := GameState.item_by_id(iid)
	if str(it.get("type", "gear")) not in ["weapon", "armor", "shield"]:
		return
	_apply_equip_change(func():
		if _equipped_where(iid) != "":
			_unequip(iid)
		else:
			GameState.toggle_equip(iid))


func _equipped_where(iid: String) -> String:
	var eq: Dictionary = GameState.inv().get("equipped", {})
	for k in eq:
		if str(eq[k]) == iid:
			return str(k)
	return ""


func _equip_to(iid: String, slot: String) -> void:
	var inv := GameState.inv()
	var eq: Dictionary = inv.get("equipped", {})
	for k in eq.keys():
		if str(eq[k]) == iid:
			eq.erase(k)
	eq[slot] = iid
	inv["equipped"] = eq
	GameState.save_kind("inv", inv)


func _unequip(iid: String) -> void:
	var inv := GameState.inv()
	var eq: Dictionary = inv.get("equipped", {})
	for k in eq.keys():
		if str(eq[k]) == iid:
			eq.erase(k)
	inv["equipped"] = eq
	GameState.save_kind("inv", inv)

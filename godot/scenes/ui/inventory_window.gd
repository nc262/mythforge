extends AcceptDialog
## 🎒 The inventory: an equipment paper doll on the left, the pack as a
## framed slot grid on the right. Drag between them (or double-click) —
## rarity lights the frames, tooltips carry the numbers. State stays in
## GameState; this window only arranges it.

signal inventory_changed

const COLS := 6
const RARITY_COLOR := {
	"common": "border", "uncommon": "gold_soft", "rare": "amethyst",
	"epic": "ember", "legendary": "gold",
}
const TYPE_GLYPH := {"weapon": "⚔", "armor": "🥋", "shield": "⛨", "gear": "🧪"}
const DOLL_SLOTS := [["weapon", "⚔", "Main hand"], ["offhand", "🗡", "Off hand"], ["armor", "🥋", "Armor"], ["shield", "⛨", "Shield"]]

var _grid: GridContainer
var _doll: VBoxContainer
var _stats: Label


class InvSlot extends PanelContainer:
	var item: Dictionary = {}
	var slot_key := ""   # "" = a pack cell; else the doll slot it represents
	var index := -1      # position in the pack
	var win: Node = null

	func _init(w: Node, key := "", idx := -1) -> void:
		win = w
		slot_key = key
		index = idx
		custom_minimum_size = Vector2(64, 64)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		var glyph := Label.new()
		glyph.name = "Glyph"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 24)
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(glyph)
		var qty := Label.new()
		qty.name = "Qty"
		qty.theme_type_variation = "HintLabel"
		qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		qty.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(qty)
		refresh()

	func refresh() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Ui.c("night2"), 0.9)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(6)
		var glyph: Label = get_node("Glyph")
		var qty: Label = get_node("Qty")
		var icon: TextureRect = get_node("Icon")
		icon.texture = null if item.is_empty() else Art.item_tex(str(item.get("name", "")))
		glyph.visible = icon.texture == null
		if item.is_empty():
			sb.border_color = Color(Ui.c("border_soft"), 0.7)
			glyph.text = {"weapon": "⚔", "offhand": "🗡", "armor": "🥋", "shield": "⛨"}.get(slot_key, "")
			glyph.modulate = Color(1, 1, 1, 0.22)
			qty.text = ""
			tooltip_text = ""
		else:
			var rar := str(item.get("rarity", "common"))
			sb.border_color = Ui.c(RARITY_COLOR.get(rar, "border"))
			sb.shadow_color = Color(Ui.c(RARITY_COLOR.get(rar, "border")), 0.35 if rar != "common" else 0.0)
			sb.shadow_size = 6
			glyph.text = TYPE_GLYPH.get(str(item.get("type", "gear")), "🧪")
			glyph.modulate = Color(1, 1, 1, 1)
			var q := int(item.get("qty", 1))
			qty.text = str(q) if q > 1 else ""
			var bits: Array[String] = ["%s (%s)" % [str(item.get("name", "?")), rar]]
			if item.get("dmg") != null:
				bits.append("%s damage%s" % [item["dmg"], (" · %+d to hit" % int(item.get("atk", 0))) if int(item.get("atk", 0)) != 0 else ""])
			if item.get("acBonus") != null:
				bits.append("+%d AC" % int(item["acBonus"]))
			bits.append("sells for %d" % Rules.sell_value(rar))
			tooltip_text = "\n".join(bits)
		add_theme_stylebox_override("panel", sb)

	func _get_drag_data(_pos: Vector2):
		if item.is_empty():
			return null
		var preview := Label.new()
		preview.text = "%s %s" % [get_node("Glyph").text, str(item.get("name", ""))]
		preview.add_theme_color_override("font_color", Ui.c("gold_soft"))
		set_drag_preview(preview)
		return {"iid": str(item.get("id", "")), "from_slot": slot_key, "from_index": index}

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("iid")

	func _drop_data(_pos: Vector2, data) -> void:
		win.call("handle_drop", data, slot_key, index)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.double_click \
				and event.button_index == MOUSE_BUTTON_LEFT and not item.is_empty():
			win.call("handle_double", str(item.get("id", "")))


func _init() -> void:
	title = "🎒 Inventory"
	ok_button_text = "Close"
	min_size = Vector2i(780, 520)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	# The paper doll.
	_doll = VBoxContainer.new()
	_doll.add_theme_constant_override("separation", 10)
	var dh := Label.new()
	dh.theme_type_variation = "HeaderLabel"
	dh.text = "EQUIPPED"
	_doll.add_child(dh)
	_stats = Label.new()
	_stats.theme_type_variation = "HintLabel"
	_doll.add_child(_stats)
	root.add_child(_doll)
	# The pack.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	var ph := Label.new()
	ph.name = "PackHeader"
	ph.theme_type_variation = "HeaderLabel"
	ph.text = "PACK"
	right.add_child(ph)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_grid)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.text = "Drag to equip or rearrange · double-click to equip/unequip"
	right.add_child(hint)
	root.add_child(right)
	add_child(root)
	confirmed.connect(queue_free)


func _ready() -> void:
	rebuild()
	Art.art_ready.connect(func(_k): rebuild())
	# Commission icons for whatever the pack holds (queued, one at a time).
	for it in GameState.inv().get("items", []):
		Art.ensure_item_icon(str(it.get("name", "")))


func rebuild() -> void:
	var inv := GameState.inv()
	var eq: Dictionary = inv.get("equipped", {})
	var items: Array = inv.get("items", [])
	# Doll slots (keep header + stats, rebuild the four frames between).
	for child in _doll.get_children():
		if child is InvSlot or (child is HBoxContainer and child.name == "DollRow"):
			child.queue_free()
	for spec in DOLL_SLOTS:
		var row := HBoxContainer.new()
		row.name = "DollRow"
		row.add_theme_constant_override("separation", 10)
		var slot := InvSlot.new(self, spec[0])
		var id := str(eq.get(spec[0], ""))
		for it in items:
			if str(it.get("id", "")) == id:
				slot.item = it
		slot.refresh()
		var lab := Label.new()
		lab.theme_type_variation = "HintLabel"
		lab.text = spec[2]
		row.add_child(slot)
		row.add_child(lab)
		_doll.add_child(row)
		_doll.move_child(row, _doll.get_child_count() - 2)  # stats stay last
	var s := GameState.sheet()
	_stats.text = "AC %d   ·   HP %d/%d\nAttack %+d" % [Rules.eff_ac(s, inv), int(s.get("hp", 0)), int(s.get("hpMax", 1)), Rules.attack_mod(s, inv)]
	# Pack grid.
	for child in _grid.get_children():
		child.queue_free()
	var cap := int(inv.get("slots", 24))
	for i in cap:
		var cell := InvSlot.new(self, "", i)
		if i < items.size():
			cell.item = items[i]
		cell.refresh()
		_grid.add_child(cell)
	for n in find_children("PackHeader", "Label", true, false):
		n.text = "PACK  (%d / %d)" % [items.size(), cap]


## Drops route here: pack→doll equips, doll→pack unequips, pack→pack reorders.
func handle_drop(data: Dictionary, to_slot: String, to_index: int) -> void:
	var iid := str(data.get("iid", ""))
	if to_slot != "":
		var it := GameState.item_by_id(iid)
		var t := str(it.get("type", ""))
		var fits: bool = t == to_slot or (to_slot == "offhand" and t == "weapon")
		if fits:
			GameState.toggle_equip(iid) if _equipped_where(iid) == to_slot else _equip_to(iid, to_slot)
	elif str(data.get("from_slot", "")) != "":
		_unequip(iid)
	elif to_index >= 0 and int(data.get("from_index", -1)) >= 0:
		var inv := GameState.inv()
		var items: Array = inv.get("items", [])
		var fi := int(data["from_index"])
		if fi < items.size():
			var moved = items.pop_at(fi)
			items.insert(mini(to_index, items.size()), moved)
			GameState.save_kind("inv", inv)
	rebuild()
	inventory_changed.emit()


func handle_double(iid: String) -> void:
	if _equipped_where(iid) != "":
		_unequip(iid)
	else:
		GameState.toggle_equip(iid)
	rebuild()
	inventory_changed.emit()


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

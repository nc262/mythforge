extends AcceptDialog
## The trading post: wares on the left, your pack on the right, the purse
## between. Haggling moves every price. Extracted from game.gd (A0 split):
## buy/sell/haggle mutate the autoloads directly; the play screen only hears
## haggled(markup) — the keeper's mood outlives the window — and
## counter_left(deals) on close, from which it tells the GM about the visit.

signal haggled(new_markup: float)
signal counter_left(deals: Array)

var markup := 1.0   # pushed in by the play screen; persists across visits

var _deals: Array[String] = []
var _purse: Label
var _wares: ItemList
var _pack: ItemList
var _wares_meta: Array = []
var _pack_meta: Array = []
var _purse_row: HBoxContainer
var _purse_amount: Label
var _detail: HBoxContainer
var _detail_art: MythPlate
var _detail_txt: Label
var _icons_repaint := false


func _icons_repaint_now() -> void:
	_icons_repaint = false
	# Refresh keeps the shopper's place: reselect what was selected.
	var ws := _wares.get_selected_items()
	var ps := _pack.get_selected_items()
	_refresh()
	if not ws.is_empty() and ws[0] < _wares.item_count:
		_wares.select(ws[0])
	if not ps.is_empty() and ps[0] < _pack.item_count:
		_pack.select(ps[0])


func _init() -> void:
	ok_button_text = "Leave the counter"
	min_size = Vector2i(720, 480)


func _ready() -> void:
	MythEnvironment.mount(self, "env-merchant", "dust", [Vector2(0.12, 0.14), Vector2(0.88, 0.1)])
	var here := str(GameState.state.get("world", {}).get("here", "")) if GameState.state.get("world") is Dictionary else ""
	var here_shop := ""
	for l in Rules.world_locations(GameState.world_id()):
		if l is Dictionary and str(l.get("name", "")) == here and str(l.get("shop", "")) != "":
			here_shop = str(l.get("shop", ""))
	title = here if here_shop != "" else "The trading post"
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	# R6 BUG-07/08/09 — the shared panel contract: the grey chrome band, the
	# title rendering OUTSIDE the panel over the day banner, and the stock ✕
	# floating off the top-right corner were all the undressed AcceptDialog.
	Ui.dress_dialog(self, root)
	# The keeper is a person, not a vending machine (R6 PLAY-07/FUN-22): name the
	# counter inside the panel where the title used to escape to.
	var head := Label.new()
	head.theme_type_variation = "HeaderLabel"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.text = title
	root.add_child(head)
	# The purse is a ROW, not a sentence: the number lives alone so it can be
	# counted down rather than snapped (MIL §9).
	_purse_row = HBoxContainer.new()
	_purse_row.add_theme_constant_override("separation", Ui.SPACE["xs"])
	var purse_pre := Label.new()
	purse_pre.theme_type_variation = "HintLabel"
	purse_pre.text = "Your purse:"
	_purse_amount = Label.new()
	_purse_amount.add_theme_color_override("font_color", Ui.c("gold"))
	var purse_cur := Label.new()
	purse_cur.theme_type_variation = "HintLabel"
	purse_cur.text = GameState.currency()
	_purse = Label.new()          # the keeper's mood rides alongside
	_purse.theme_type_variation = "HintLabel"
	for n in [purse_pre, _purse_amount, purse_cur, _purse]:
		_purse_row.add_child(n)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	_wares = ItemList.new()
	_wares.custom_minimum_size = Vector2(330, 320)
	_wares.fixed_icon_size = Vector2i(28, 28)
	_pack = ItemList.new()
	_pack.custom_minimum_size = Vector2(330, 320)
	_pack.fixed_icon_size = Vector2i(28, 28)
	var left := VBoxContainer.new()
	var lt := Label.new()
	lt.theme_type_variation = "HeaderLabel"
	lt.text = "The keeper's wares"
	var buy := Button.new()
	buy.theme_type_variation = "AccentButton"  # buying is THE act at a counter
	buy.text = "Buy ›"
	buy.pressed.connect(_buy)
	left.add_child(lt)
	left.add_child(_wares)
	left.add_child(buy)
	var right := VBoxContainer.new()
	var rt2 := Label.new()
	rt2.theme_type_variation = "HeaderLabel"
	rt2.text = "Your pack"
	var sell := Button.new()
	sell.text = "‹ Sell"
	sell.pressed.connect(_sell)
	right.add_child(rt2)
	right.add_child(_pack)
	right.add_child(sell)
	cols.add_child(left)
	cols.add_child(right)
	# A skill check dressed as a skill check — a ghost line with the die, not a
	# third identical bar beside Buy/Sell.
	var haggle := Button.new()
	haggle.theme_type_variation = "GhostButton"
	haggle.icon = Ui.ico_tex("die")
	haggle.expand_icon = true
	haggle.add_theme_constant_override("icon_max_width", 20)
	haggle.text = "Haggle with the keeper (Persuasion, DC 12)"
	haggle.pressed.connect(func():
		if markup != 1.0:
			return
		var hres: Dictionary = Rules.resolve_check({"ability": "CHA", "skill": "Persuasion", "dc": 12}, GameState.sheet(), GameState.inv())
		markup = 0.8 if int(hres["total"]) >= 12 else 1.1
		haggled.emit(markup)
		_deals.append("haggled (%s)" % ("won a fifth off" if markup < 1.0 else "annoyed the keeper"))
		haggle.disabled = true
		_refresh())
	if here_shop != "":
		var trades := Label.new()
		trades.theme_type_variation = "HintLabel"
		trades.text = "This counter trades in: %s" % here_shop
		root.add_child(trades)
	root.add_child(_purse_row)
	root.add_child(cols)
	# The detail strip: pick an item on either side and see the piece itself —
	# its painted face, the buy price, and why the sell price reads low.
	_detail = HBoxContainer.new()
	_detail.add_theme_constant_override("separation", Ui.SPACE["m"])
	_detail.visible = false
	_detail_art = MythPlate.new(Vector2(72, 72), 0.0)
	_detail.add_child(_detail_art)
	_detail_txt = Label.new()
	_detail_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail.add_child(_detail_txt)
	root.add_child(_detail)
	_wares.item_selected.connect(func(i):
		if i < _wares_meta.size() and _wares_meta[i] != null:
			var w: Dictionary = _wares_meta[i]
			_show_detail(str(w["name"]), "%s   ·   buy for %d %s" % [str(w["name"]), int(w["price"]), GameState.currency()]))
	_pack.item_selected.connect(func(i):
		if i < _pack_meta.size():
			var it := GameState.item_by_id(str(_pack_meta[i]))
			if not it.is_empty():
				_show_detail(str(it.get("name", "")), "%s   ·   sells for %d %s — a keeper's lowball, not the shelf price" % [
					str(it.get("name", "")), Rules.sell_value(str(it.get("rarity", "common"))), GameState.currency()]))
	root.add_child(haggle)
	add_child(root)
	_refresh()
	# Painted icons land async — repaint for ITEM icons only, coalesced to one
	# refresh per frame; a busy art queue must never strobe the counter.
	Art.art_ready.connect(func(k):
		if str(k).begins_with("item-") and not _icons_repaint:
			_icons_repaint = true
			call_deferred("_icons_repaint_now"))
	confirmed.connect(func():
		counter_left.emit(_deals)
		queue_free())


func _refresh() -> void:
	_purse_amount.text = "%d" % int(GameState.sheet().get("gold", 0))
	_purse.text = "   ·   the keeper likes you (a fifth off)" if markup < 1.0 \
		else ("   ·   the keeper is annoyed (prices nudge up)" if markup > 1.0 else "")
	_wares.clear()
	_wares_meta.clear()
	var stock: Dictionary = Rules.vendor_stock()  # world-skinned goods, not daggers-everywhere
	for cat in ["weapon", "armor", "potion", "general", "food"]:
		var goods: Array = stock.get(cat, [])
		if goods.is_empty():
			continue
		_wares.add_item("— %s —" % cat.capitalize(), null, false)
		_wares_meta.append(null)
		var cur := GameState.currency()
		for gd in goods:
			if gd is Array and gd.size() >= 2:
				var price := maxi(1, roundi(int(gd[1]) * markup))
				Art.ensure_item_icon(str(gd[0]))  # every ware shows its painted face
				_wares.add_item("%s   ·   %d %s" % [str(gd[0]), price, cur], Art.item_tex(str(gd[0])))
				_wares_meta.append({"name": str(gd[0]), "price": price})
	_pack.clear()
	_pack_meta.clear()
	for it in GameState.inv().get("items", []):
		var q := int(it.get("qty", 1))
		_pack.add_item("%s%s   ·   sell for %d %s" % [str(it.get("name", "")),
			(" ×%d" % q) if q > 1 else "", Rules.sell_value(str(it.get("rarity", "common"))), GameState.currency()],
			Art.item_tex(str(it.get("name", ""))))
		_pack_meta.append(str(it.get("id", "")))


func _show_detail(item_name: String, line: String) -> void:
	_detail.visible = true
	_detail_art.set_texture(Art.item_tex(item_name))
	_detail_txt.text = line


func _buy() -> void:
	var sel := _wares.get_selected_items()
	if sel.is_empty() or _wares_meta[sel[0]] == null:
		return
	var w: Dictionary = _wares_meta[sel[0]]
	var purse_before := int(GameState.sheet().get("gold", 0))
	if purse_before < int(w["price"]):
		# MIL §6 — the refusal names the gap instead of stating a rule.
		Ui.shake(_purse)
		_purse.text = "Not enough %s for the %s — you carry %d, it asks %d." % [
			GameState.currency(), w["name"], purse_before, int(w["price"])]
		return
	GameState.add_gold(-int(w["price"]))   # truth first
	GameState.add_item(str(w["name"]))
	_deals.append("bought a %s (%d %s)" % [w["name"], int(w["price"]), GameState.currency()])
	# MIL — the middle act: the coin leaves the purse, the piece joins the pack.
	Sfx.ui("purchase")
	var ware_rect := Rect2(_wares.get_global_rect().position, Vector2(48, 48))
	Ui.fly_to(self, Art.item_tex(str(w["name"])), ware_rect,
		Rect2(_pack.get_global_rect().position, Vector2(48, 48)))
	Ui.rise_text(self, "−%d %s" % [int(w["price"]), GameState.currency()], Ui.c("danger"),
		_purse.get_global_rect().position + Vector2(_purse.size.x * 0.5, 0))
	_refresh()
	# …and the purse counts down rather than snapping to its new number.
	Ui.count_to(_purse_amount, purse_before, purse_before - int(w["price"]), "%d")


func _sell() -> void:
	var sel := _pack.get_selected_items()
	if sel.is_empty():
		return
	var purse_before := int(GameState.sheet().get("gold", 0))
	var note := GameState.sell_item(str(_pack_meta[sel[0]]))
	if note == "":
		Ui.shake(_pack)
		return
	_deals.append(note.trim_prefix("You "))
	Sfx.ui("purchase")
	var gained := int(GameState.sheet().get("gold", 0)) - purse_before
	_refresh()
	Ui.rise_text(self, "+%d %s" % [gained, GameState.currency()], Ui.c("gold"),
		_purse_row.get_global_rect().position + Vector2(_purse_row.size.x * 0.5, 0))
	Ui.count_to(_purse_amount, purse_before, purse_before + gained)

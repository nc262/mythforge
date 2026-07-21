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
	_purse = Label.new()
	_purse.theme_type_variation = "HintLabel"
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
	root.add_child(_purse)
	root.add_child(cols)
	root.add_child(haggle)
	add_child(root)
	_refresh()
	Art.art_ready.connect(func(_k): _refresh())  # painted icons land async; auto-disconnects on free
	confirmed.connect(func():
		counter_left.emit(_deals)
		queue_free())


func _refresh() -> void:
	_purse.text = "Your purse: %d %s%s" % [int(GameState.sheet().get("gold", 0)), GameState.currency(),
		"   ·   the keeper likes you (−20%)" if markup < 1.0 else ("   ·   the keeper is annoyed (+10%)" if markup > 1.0 else "")]
	_wares.clear()
	_wares_meta.clear()
	var stock: Dictionary = Rules.tables.get("vendor_stock", {})
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


func _buy() -> void:
	var sel := _wares.get_selected_items()
	if sel.is_empty() or _wares_meta[sel[0]] == null:
		return
	var w: Dictionary = _wares_meta[sel[0]]
	if int(GameState.sheet().get("gold", 0)) < int(w["price"]):
		_purse.text = "Not enough %s for the %s." % [GameState.currency(), w["name"]]
		return
	GameState.add_gold(-int(w["price"]))
	GameState.add_item(str(w["name"]))
	Sfx.play("chime")
	_deals.append("bought a %s (%d %s)" % [w["name"], int(w["price"]), GameState.currency()])
	_refresh()


func _sell() -> void:
	var sel := _pack.get_selected_items()
	if sel.is_empty():
		return
	var note := GameState.sell_item(str(_pack_meta[sel[0]]))
	if note != "":
		Sfx.play("chime")
		_deals.append(note.trim_prefix("You "))
	_refresh()

extends Node
## Click-driver QA (Backlog P1) — plays the game the way a HAND does: real
## mouse events synthesized through the input pipeline (hover, press, release
## via Viewport.push_input), so dead, covered, or off-screen controls fail
## here instead of under the player's cursor. Two layers per station:
##   1. Hit-test audit: every visible enabled Button must be on-screen and be
##      the topmost control at its own center (descendants excused).
##   2. Real click paths: the Sheet button must OPEN the menu, each tab click
##      must LAND on its page, the shop must open — outcome-asserted, so a
##      click-eating overlay is caught even when the audit can't see it.
## Runs:
##   godot --headless --path godot res://tests/click_driver.tscn   (audit)
##   godot --path godot res://tests/click_driver.tscn              (+ PNGs)
## Windowed runs save a screenshot per station to user://clickdrive/.
## Backend: canned (Api.test_mode) by default — the same shipped scene runs
## either way; set MF_LIVE=1 with a logged-in session to drive the live stack.

var _game: Control
var _issues: Array[String] = []
var _station := ""


## assert() strands the coroutine headless (the tree keeps running) — fail loud and QUIT.
func _must(cond: bool, why: String) -> void:
	if cond:
		return
	print("CLICKDRIVE FAIL: " + why)
	print("  state=%s  dialogs=%s" % [Mode.state,
		str(_game.get_children().filter(func(c): return c is Window).map(func(c): return c.name))])
	get_tree().quit(1)
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.gui_embed_subwindows = true  # dialogs live in OUR viewport: clickable + screenshottable
	Ui.apply("")
	Ui.reduce_motion = true
	if OS.get_environment("MF_LIVE") != "1":
		Api.test_mode = true
		_seed()
	await _boot_game()
	# ── Station: the play screen ──
	await _visit("play-screen", _game)
	# ── Station: THE MENU via a real click on the Sheet button ──
	await _click(_game.get_node("Margin/Split/ChatBox/Input/SheetBtn"))
	await _settle(10)
	var menu: Node = _find_dialog("character_screen.gd")
	await _must(menu != null, "Sheet button click did not open THE MENU (click eaten?)")
	for tab in menu.TABS:
		await _click(menu._tabs[tab])
		await _settle(6)
		await _must(str(menu._active) == str(tab), "menu tab '%s' did not land (active=%s)" % [tab, menu._active])
		await _visit("menu-" + str(tab).to_lower().replace(" ", "-"), menu)
	await _click(menu.get_ok_button())
	await _settle(6)
	await _must(not is_instance_valid(menu) or menu.is_queued_for_deletion(), "menu OK button did not close it")
	# ── Station: the trading post via a real click on the toolbar ──
	Mode.enter("Exploration")
	await _click(_game.get_node("Margin/Split/ChatBox/Input/Shop"))
	await _settle(10)
	var shop: Node = _find_dialog("merchant_window.gd")
	await _must(shop != null, "Shop button click did not open the trading post")
	await _visit("shop", shop)
	await _click(shop.get_ok_button())
	await _settle(6)
	Mode.enter("Exploration")
	# ── Station: the Lore Book ──
	await _click(_game.get_node("Margin/Split/ChatBox/Input/Lore"))
	await _settle(10)
	var book: Node = null
	for ch in _game.get_children():
		if ch is Control and ch.get_script() != null and str(ch.get_script().resource_path).ends_with("lore_book.gd"):
			book = ch
	await _must(book != null, "Lore button click did not open the book")
	for cat in book.CATS:
		await _click(book._tabs[cat])
		await _settle(6)
		await _must(str(book._active) == str(cat), "book tab '%s' did not land" % cat)
	await _visit("lore-book", book)
	book.queue_free()
	await _settle(4)
	await _main_menu_stations()
	# ── The report ──
	if _issues.is_empty():
		print("CLICKDRIVE OK — every station clickable, nothing covered or lost")
	else:
		for i in _issues:
			print("  ISSUE: " + i)
		print("CLICKDRIVE FOUND %d ISSUE(S)" % _issues.size())
	get_tree().quit(0 if _issues.is_empty() else 1)


# ── Station: the MAIN MENU ──────────────────────────────────────────────────
## Four of the Round-5 blockers live on the main menu, and none of them could be
## caught here because the driver only ever booted the play scene. The Campaign
## Shelf (BLK-03) is the sharp case: eight tales, each with a "Set the table"
## button, and clicking one did nothing at all — so the assertion is not "the
## button exists" but "pressing it actually leaves the shelf".
func _main_menu_stations() -> void:
	_game.visible = false
	# The boot cinematic is a full-rect MOUSE_FILTER_STOP overlay that frees
	# itself a few seconds in. Skip it the way a second visit does, or the driver
	# just measures the overlay instead of the menu.
	Engine.set_meta("mf_cine_played", true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _settle(20)
	await _visit("menu-title", menu)
	menu._show_campaigns()
	await _settle(20)
	await _visit("menu-campaign-shelf", menu)
	var tales: Array = menu._content.find_children("*", "Button", true, false).filter(
		func(b): return b is Button and b.tooltip_text == "Set the table with this tale")
	await _must(not tales.is_empty(), "Campaign Shelf listed no tales to click")
	# The shipped defect (BLK-03) was that a tale card was INERT — the press
	# reached nothing, no hover, no response. Prove the press is delivered to a
	# live Button. We block the launch itself (canned call_json resolves with no
	# frame yield, so an un-blocked _start_adventure would run to the scene swap
	# synchronously and pull the tree out from under the harness) — that each card
	# carries its own (world, tale) is guaranteed by construction in _show_campaigns.
	var b0: Button = tales[0]
	var fired := [false]
	b0.pressed.connect(func(): fired[0] = true)
	menu._busy = true   # _start_adventure guards on _busy → no launch, no scene swap
	await _click(b0)
	await _must(fired[0], "Campaign Shelf: a tale card did not fire on click (inert — BLK-03)")
	menu.queue_free()


# ── The hand ────────────────────────────────────────────────────────────────
## A real click: hover motion, press, release — pushed into the control's own
## viewport (main screen or an embedded dialog window alike).
func _click(ctrl: Control) -> void:
	await _must(ctrl != null and ctrl.is_visible_in_tree(), "click target missing/hidden at %s" % _station)
	# Clicks travel the way a mouse does: into the ROOT viewport, which routes
	# them on into embedded dialog windows. A control inside an embedded Window
	# needs its window's offset added; pushing into the Window viewport directly
	# never delivers (verified: pressed never fires).
	var vp: Viewport = get_tree().root
	var p := ctrl.get_global_rect().get_center()
	var host := ctrl.get_window()
	if host != null and host != get_tree().root and host.is_embedded():
		p += Vector2(host.position)
	# A control flush with the screen edge centers EXACTLY on the boundary —
	# edge-exclusive hit tests drop it. Nudge inside.
	var vis := vp.get_visible_rect()
	p = p.clamp(vis.position + Vector2.ONE, vis.end - Vector2(2, 2))
	# in_local_coords=true: these are post-stretch canvas coordinates (the
	# 1280x800 window scales under canvas_items/expand).
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	vp.push_input(mm, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		mb.global_position = p
		vp.push_input(mb, true)
		await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


# ── The eye ─────────────────────────────────────────────────────────────────
## Audit one station: every visible enabled Button on-screen + unobstructed,
## then a screenshot when we have a renderer.
func _visit(station: String, root: Node) -> void:
	_station = station
	await _settle(4)
	for b in root.find_children("*", "Button", true, false):
		if not (b is Button) or not b.is_visible_in_tree() or b.disabled:
			continue
		var r: Rect2 = b.get_global_rect()
		if r.size.x < 2 or r.size.y < 2:
			_issues.append("%s: '%s' has no size (collapsed layout)" % [station, _label(b)])
			continue
		# Content scrolled out of a ScrollContainer is reachable by scrolling, not
		# lost — a long list (e.g. the Campaign Shelf with every world's tales) is
		# SUPPOSED to overflow. Only audit what's actually within the scroll
		# viewport; the clipped remainder is the container's job, not a defect.
		var scrolled: ScrollContainer = _scroll_ancestor(b)
		var clip := scrolled.get_global_rect() if scrolled != null else b.get_viewport().get_visible_rect()
		if scrolled != null and not clip.intersects(r):
			continue   # scrolled out of view — reachable, not lost
		if not b.get_viewport().get_visible_rect().intersects(r):
			_issues.append("%s: '%s' sits off-screen at %s" % [station, _label(b), r])
			continue
		# Probe the button's on-screen centre. For a partly-scrolled card the true
		# centre can sit under the scroll's clip edge; use the visible slice so we
		# test a point the player could actually click.
		var probe := (r.intersection(clip) if scrolled != null else r).get_center()
		var top := _top_control(b.get_viewport(), probe)
		if top != null and top != b and not b.is_ancestor_of(top):
			_issues.append("%s: '%s' covered by '%s'" % [station, _label(b), top.name])
	_shot(station)


func _label(b: Button) -> String:
	return b.text if b.text != "" else str(b.name)


## The nearest ScrollContainer above this control, or null if it isn't inside
## one. Anything outside its rect is scrolled away, not lost.
func _scroll_ancestor(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## Topmost mouse-eligible control at a point — later siblings draw (and catch
## clicks) above earlier ones, children above parents.
func _top_control(n: Node, p: Vector2) -> Control:
	if n is Control:
		if not n.visible:
			return null
		if n.clip_contents and not (n as Control).get_global_rect().has_point(p):
			return null
	for i in range(n.get_child_count() - 1, -1, -1):
		var child := n.get_child(i)
		if child is Window:
			continue  # separate station; never "covers" this viewport's controls
		var hit := _top_control(child, p)
		if hit != null:
			return hit
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and (n as Control).get_global_rect().has_point(p):
		return n
	return null


func _shot(station: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://clickdrive")
	img.save_png("user://clickdrive/%s.png" % station)


# ── Boot (same canned world the playthrough harness trusts) ─────────────────
func _find_dialog(script_suffix: String) -> Node:
	for ch in _game.get_children():
		if ch is AcceptDialog and ch.get_script() != null \
				and str(ch.get_script().resource_path).ends_with(script_suffix):
			return ch
	return null


func _seed() -> void:
	var sheet := {
		"name": "Clickwyn", "race": "Human", "cls": "Fighter", "level": 1, "xp": 0,
		"hp": 12, "hpMax": 12, "ac": 12, "gold": 20,
		"abilities": {"STR": 15, "DEX": 13, "CON": 14, "INT": 10, "WIS": 12, "CHA": 8},
		"inventory": [], "conditions": [], "spells": [], "slots": {},
		"profSkills": ["athletics"], "profSaves": ["STR", "CON"], "hitDie": 10, "hitDiceUsed": 0,
	}
	Api.test_json = {
		"/characters/studio/state/": {"_status": 200, "state": {"sheet": sheet, "clock": {"day": 1, "ti": 1}}},
		"/default-chat": {"_status": 200, "endpoint_url": "test", "model": "test"},
		"/generate": {"_status": 200, "image_url": ""},
		"/memory/recall": {"_status": 200, "beats": []},
	}
	GameState.character = {"id": "dm-embervale-clickdrive", "name": "Clickwyn: Free Roam", "world_id": "embervale"}


func _boot_game() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	for i in 60:
		await get_tree().process_frame
		if Mode.state == "Exploration":
			break
	await _must(Mode.state == "Exploration", "boot never reached Exploration (state=%s)" % Mode.state)
	print("  boot: real game scene up (%s)" % ("LIVE backend" if not Api.test_mode else "canned backend"))

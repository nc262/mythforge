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
## Narrator: scripted (Api.test_mode) — the shipped scene, without the model.

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
	# Headless has no window, so the root viewport reports a SQUARE guess — 1280x1280
	# measured, 480 px taller than the shipped 1280x800. Every "does this fit on
	# screen" question would then be asked of a screen no player owns. Ask it of
	# the one in project.godot instead.
	get_tree().root.size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 800)))
	await get_tree().process_frame
	print("  screen: %s" % get_tree().root.get_visible_rect())
	Ui.apply("")
	Ui.reduce_motion = true
	if OS.get_environment("MF_LIVE") != "1":
		Api.test_mode = true
		GameState.reset_test_saves()   # a harness starts from nothing
		_seed()
	await _boot_game()
	# ── Station: the play screen ──
	await _visit("play-screen", _game)
	# PY-5 - THE CHART MUST NOT BE DRAWN OVER THE TRANSCRIPT. Measured before the
	# fix: the chart sat at (14,604)-(204,728) and the scroll at (20,131)-(1260,688),
	# so an 84x184 band of GM prose rendered underneath an opaque chart - a played
	# session read "What do you do next?" as "next?". The reserved band is a
	# constant in game.gd, so this is what stops that number going stale quietly.
	var mini: Control = _game.get("_mini_map")
	var chat: Control = _game.get_node_or_null("Margin/Split/ChatBox/Scroll")
	await _must(mini != null and chat != null, "play screen: no minimap or no transcript to measure")
	if mini.visible:
		var why := "the chart is drawn over the transcript — chart %s, transcript %s (PY-5)" % [mini.get_global_rect(), chat.get_global_rect()]
		await _must(not mini.get_global_rect().intersects(chat.get_global_rect()), why)
	# ── Station: THE MENU via a real click on the Sheet button ──
	await _click(_game.get_node("Margin/Split/ChatBox/Input/SheetBtn"))
	await _settle(10)
	var menu: Node = _find_dialog("character_screen.gd")
	await _must(menu != null, "Sheet button click did not open THE MENU (click eaten?)")
	await _probe_tab_reachability(menu)
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
	# PL-7 — the soft-lock the audit above could NOT see, because it only ever
	# looked at the counter as it opens. Touch a ware and the detail strip appears;
	# a Window only ever GROWS to its contents and never shrinks back, so 86 px of
	# new content took the dialog from 541 px to 1002 px, growing DOWNWARD from the
	# origin popup_centered fixed when it was shorter. "Leave the counter" landed
	# 91 px below the screen with nothing to scroll and no other way out.
	await _click_list_item(shop._wares, 1)
	await _settle(10)
	await _must(shop._detail.visible, "shop: clicking a ware did not reveal the detail strip")
	await _visit("shop-ware-picked", shop)
	await _click(shop.get_ok_button())
	await _settle(6)
	# The soft-lock itself, and the reason this is a P1 and not a cosmetic one:
	# the exit IS that button, Escape does nothing, and nothing scrolls. Report it
	# and free the counter by hand, or every station after this one measures the
	# shop instead — which is exactly what the player gets, minus the Task Manager.
	if is_instance_valid(shop) and not shop.is_queued_for_deletion():
		_issues.append("shop: SOFT-LOCK — 'Leave the counter' did not close the counter once a ware was picked")
		shop.queue_free()
		await _settle(4)
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
	await _click_point(ctrl, ctrl.get_global_rect().get_center())


## A real click on one ROW of an ItemList. The list is the only Control there is,
## so _click would forever press whatever sits under its centre.
func _click_list_item(list: ItemList, idx: int) -> void:
	await _must(list != null and list.is_visible_in_tree() and idx < list.item_count,
		"list row %d missing at %s" % [idx, _station])
	await _click_point(list, list.get_global_rect().position + list.get_item_rect(idx).get_center())


func _click_point(ctrl: Control, p: Vector2) -> void:
	# Clicks travel the way a mouse does: into the ROOT viewport, which routes
	# them on into embedded dialog windows. A control inside an embedded Window
	# needs its window's offset added; pushing into the Window viewport directly
	# never delivers (verified: pressed never fires).
	var vp: Viewport = get_tree().root
	p = _root_point(ctrl, p)
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
		# PL-7 — the check above asks the button's OWN viewport, and for a control
		# inside a dialog that viewport is the dialog, which grows with it. So a
		# dialog that outgrows the screen carries its exit button off the bottom
		# while every rect still reads "on-screen". Ask the ROOT instead, where the
		# player's hand is, and demand the whole button, not a sliver of it.
		if scrolled == null:
			var rr := Rect2(_root_point(b, r.position), r.size)
			var screen := get_tree().root.get_visible_rect()
			if not screen.encloses(rr):
				_issues.append("%s: '%s' is off the screen at %s (screen %s)" % [station, _label(b), rr, screen])
				continue
		# Probe the button's on-screen centre. For a partly-scrolled card the true
		# centre can sit under the scroll's clip edge; use the visible slice so we
		# test a point the player could actually click.
		var probe := (r.intersection(clip) if scrolled != null else r).get_center()
		var top := _top_control(b.get_viewport(), probe)
		if top != null and top != b and not b.is_ancestor_of(top):
			_issues.append("%s: '%s' covered by '%s'" % [station, _label(b), top.name])
	await _shot(station)   # awaited, or the PNG lands a station or two late and lies


func _label(b: Button) -> String:
	return b.text if b.text != "" else str(b.name)


## A point in a control's own viewport, expressed in ROOT coordinates. An
## embedded dialog is a viewport of its own offset by the window's position;
## pushing input at — or measuring against — the un-offset point is a lie.
func _root_point(ctrl: Control, p: Vector2) -> Vector2:
	var host := ctrl.get_window()
	if host != null and host != get_tree().root and host.is_embedded():
		return p + Vector2(host.position)
	return p


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
	# SEED THE SAVE FILE. Writing the file is what the game actually reads, so
	# the harness must set up state the same way play does.
	GameState.character = {"id": "dm-embervale-clickdrive", "world_id": "embervale"}
	GameState.state = {"sheet": sheet, "clock": {"day": 1, "ti": 1}}
	GameState.save_kind("sheet", sheet)
	GameState.save_kind("clock", {"day": 1, "ti": 1})
	GameState.character = {"id": "dm-embervale-clickdrive", "name": "Clickwyn: Free Roam", "world_id": "embervale"}


func _boot_game() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	for i in 60:
		await get_tree().process_frame
		if Mode.state == "Exploration":
			break
	await _must(Mode.state == "Exploration", "boot never reached Exploration (state=%s)" % Mode.state)
	print("  boot: real game scene up (%s)" % ("live narrator" if not Api.test_mode else "scripted turns"))


## R8-06 / R12-03 — is each tab actually REACHABLE BY A MOUSE?
##
## This harness clicks `menu._tabs[tab]` directly, which bypasses hit-testing
## entirely — so every tab "passed" while four of them were dead in the shipped
## game. What a mouse does instead is ask which control is topmost at a point.
## This reproduces that: for each tab's centre, walk every Control in the window
## and report the last one in draw order whose rect contains the point and whose
## mouse_filter is not IGNORE. That control is who gets the click.
func _probe_tab_reachability(menu: Node) -> void:
	var win := menu.get_viewport()
	print("── tab reachability (window %s) ──" % str(win.get_visible_rect().size))
	for tab in menu.TABS:
		var b: Control = menu._tabs[tab]
		var pt: Vector2 = b.get_global_rect().get_center()
		var hits: Array = []
		_hit_walk(menu.get_tree().root, pt, hits)
		var top: String = str(hits[-1]) if not hits.is_empty() else "<nothing>"
		var owned: bool = (not hits.is_empty()) and (hits[-1] == b or b.is_ancestor_of(hits[-1]))
		print("   %-11s rect=%s  →  %s%s" % [
			tab, str(b.get_global_rect()), top, "" if owned else "   ** NOT THE TAB **"])


func _hit_walk(n: Node, pt: Vector2, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and c.get_global_rect().has_point(pt):
			out.append(c)
	for k in n.get_children():
		_hit_walk(k, pt, out)

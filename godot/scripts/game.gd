extends Control
## The adventure screen. Streamed narration, structured [[tag]] checks
## resolved by the Rules engine, read-only sheet panel — in the world's skin.

var _streaming := false
var _acc := ""          # full raw GM reply
var _shown := 0         # chars of _acc already printed (tags are held back)
var _pending_check := {}
var _last_player_msg := ""  # the visible player line, paired into memory beats
var _conjuring := false

@onready var _log: RichTextLabel = $Margin/Split/ChatBox/Log
@onready var _roll_bar: Button = $Margin/Split/ChatBox/RollBar
@onready var _msg: LineEdit = $Margin/Split/ChatBox/Input/Msg
@onready var _send_btn: Button = $Margin/Split/ChatBox/Input/Send
@onready var _sheet_panel: RichTextLabel = $Margin/Split/Sheet
@onready var _combat_panel: RichTextLabel = $Margin/Split/ChatBox/CombatPanel


func _ready() -> void:
	theme = Ui.theme
	Api.sse_delta.connect(_on_delta)
	Api.sse_event.connect(_on_event)
	Api.sse_done.connect(_on_done)
	_send_btn.pressed.connect(func(): _send(_msg.text))
	_msg.text_submitted.connect(func(_t): _send(_msg.text))
	$Margin/Split/ChatBox/Input/SheetBtn.toggled.connect(func(on): _sheet_panel.visible = on)
	$Margin/Split/ChatBox/Input/ShortRest.pressed.connect(func(): _rest("short"))
	$Margin/Split/ChatBox/Input/LongRest.pressed.connect(func(): _rest("long"))
	$Margin/Split/ChatBox/Input/Scene.pressed.connect(_conjure_scene)
	_build_dice_menu()
	Chronicle.reset()
	_sheet_panel.meta_clicked.connect(_on_sheet_action)
	_combat_panel.meta_clicked.connect(_on_combat_action)
	Combat.changed.connect(_render_combat)
	_roll_bar.pressed.connect(_roll_pending)
	var world := str(GameState.character.get("world_id", ""))
	$Margin/Split/ChatBox/Header.text = "✦ %s%s" % [str(GameState.character.get("name", "?")),
		("  ·  " + world) if world != "" else ""]
	await GameState.hydrate()
	_render_sheet()
	_render_combat()  # a fight persisted mid-round resumes where it stood
	_log_text("[i]The tale of %s begins…[/i]\n" % _bb(str(GameState.character.get("name", "?"))))


func _you() -> String:
	return "[color=%s][b]You[/b][/color]" % Ui.c("gold").to_html(false)


func _gm() -> String:
	return "[color=%s][b]GM[/b][/color]" % Ui.c("amethyst").to_html(false)


func _send(raw: String) -> void:
	if _streaming:
		return
	var msg := raw.strip_edges()
	if msg == "":
		return
	_msg.text = ""
	_set_check({})
	_log_text("\n%s  %s\n\n%s  " % [_you(), _bb(msg), _gm()])
	_last_player_msg = msg
	var beats: Array = await Chronicle.recall(msg)
	_stream(Composer.envelope(msg, beats))


## Roll results go to the GM with the envelope too, so state stays fresh.
func _stream(framed: String) -> void:
	_streaming = true
	_acc = ""
	_shown = 0
	_send_btn.disabled = true
	await Api.activate(GameState.cid(), str(GameState.character.get("name", "")))
	Api.stream_chat(framed, GameState.session_id)


func _on_delta(t: String) -> void:
	_acc += t
	_flush_stream()


## Print new narration, skipping over [[tags]] as they complete so a mid-reply
## tag never freezes the display. Incomplete tags at the tail are held back.
func _flush_stream() -> void:
	while true:
		var safe := _acc.substr(_shown)
		var i := safe.find("[[")
		if i == -1:
			var hold := 1 if safe.ends_with("[") else 0
			_log_text(_bb(safe.substr(0, safe.length() - hold)))
			_shown += safe.length() - hold
			return
		_log_text(_bb(safe.substr(0, i)))
		_shown += i
		var j := safe.find("]]", i)
		if j == -1:
			return  # tag still streaming in — hold
		_shown += (j + 2) - i  # skip the completed tag; done() re-parses _acc


func _on_event(d: Dictionary) -> void:
	if d.get("type", "") == "error" or d.has("error"):
		_log_text("[color=%s]%s[/color]" % [Ui.c("danger").to_html(false), _bb(str(d.get("error", "stream error")))])
	elif d.get("type", "") == "tool_output" and str(d.get("image_url", "")) != "":
		_show_image(str(d["image_url"]))


## Pull a generated image off the backend and paint it into the tale.
func _show_image(url: String) -> void:
	var path := url.trim_prefix(Api.BASE)
	var bytes := await Api.fetch_bytes(path)
	if bytes.is_empty():
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		return
	var w := 520
	if img.get_width() > w:
		img.resize(w, img.get_height() * w / img.get_width(), Image.INTERPOLATE_LANCZOS)
	_log_text("\n")
	_log.add_image(ImageTexture.create_from_image(img))
	_log_text("\n")


## 🖼 Conjure a painting of the current scene from the last GM narration.
func _conjure_scene() -> void:
	if _conjuring:
		return
	var last_gm := str(Tags.parse(_acc)["clean"]).strip_edges()
	if last_gm == "":
		var t: Array = Chronicle.transcript.filter(func(m): return m.get("role") == "assistant")
		if not t.is_empty():
			last_gm = str(t[-1].get("content", ""))
	if last_gm == "":
		_system_line("Nothing to paint yet — play a scene first.")
		return
	_conjuring = true
	_system_line("🖼 The scene paints itself…")
	var prompt := "The current scene: %s. Cinematic %s illustration, dramatic lighting, no text." % [
		last_gm.left(400), {"neonspire": "cyberpunk sci-fi", "everyday": "warm slice-of-life"}.get(GameState.world_id(), "high fantasy")]
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate", {"prompt": prompt})
	_conjuring = false
	if r.get("_status", 0) == 200 and str(r.get("image_url", "")) != "":
		await _show_image(str(r["image_url"]))
	else:
		_system_line("The art forge sputters — no image this time.")


func _on_done(_ok: bool) -> void:
	_streaming = false
	_send_btn.disabled = false
	# Flush the held-back tail with tags stripped, then act on the tags.
	var tail: Dictionary = Tags.parse(_acc.substr(_shown))
	if str(tail["clean"]) != "":
		_log_text(_bb(tail["clean"]))
	_log_text("\n")
	var parsed: Dictionary = Tags.parse(_acc)  # ALL tags, incl. mid-reply ones
	_apply_world_tags(parsed["tags"])
	Chronicle.record(_last_player_msg, str(parsed["clean"]))
	var check: Dictionary = Tags.check_from_tags(parsed["tags"])
	if check.is_empty():
		check = Tags.detect_check(parsed["clean"])  # prose fallback
	_set_check(check)


## Non-roll tags mutate state immediately: gold, loot, learned spells, time.
func _apply_world_tags(tags: Array) -> void:
	for t in tags:
		var a: Dictionary = t["attrs"]
		match str(t["name"]):
			"gold":
				var delta := int(str(a.get("delta", "0")).replace("+", ""))
				if delta != 0:
					var total := GameState.add_gold(delta)
					_system_line("%s gold %+d — purse now %d" % ["💰" if delta > 0 else "🪙", delta, total])
			"loot":
				var nm := str(a.get("name", "")).strip_edges()
				if nm != "":
					GameState.add_item(nm, str(a.get("rarity", "common")), maxi(1, int(a.get("qty", 1))))
					_system_line("🎒 %s added to your pack" % nm)
			"spell-learned":
				var sp := str(a.get("name", "")).strip_edges()
				if sp != "" and GameState.learn_spell(sp):
					_system_line("📖 You learn %s" % sp)
			"time":
				GameState.advance_time(maxi(1, int(a.get("advance", 1))))
				var c: Dictionary = GameState.clock()
				_system_line("🕰 %s, day %d" % [GameState.TIMES[int(c["ti"])], int(c["day"])])
			"xp":
				var r: Dictionary = GameState.award_xp(int(str(a.get("delta", a.get("amount", "0"))).replace("+", "")), str(a.get("reason", "")))
				if str(r["note"]) != "":
					_system_line(str(r["note"]).replace("*", ""))
			"combat-start":
				_start_combat(str(a.get("foes", a.get("foe", "Enemy"))))
			"combat-end":
				_end_combat()
	# Prose fallback: a fight the GM narrated but forgot to tag.
	if not Combat.active():
		var foe := Tags.detect_combat_start(Tags.parse(_acc)["clean"])
		if foe != "":
			_start_combat(foe)
	_render_sheet()


## foes like "goblin x3, goblin boss" — first spawns the fight, rest reinforce.
func _start_combat(foes: String) -> void:
	var first := true
	for part in foes.split(","):
		var nm := part.strip_edges()
		var count := 1
		var xm := RegEx.create_from_string("(?i)^(.*?)\\s*[x×]\\s*(\\d+)$").search(nm)
		if xm:
			nm = xm.get_string(1).strip_edges()
			count = clampi(int(xm.get_string(2)), 1, 6)
		if nm == "":
			continue
		for i in count:
			var label := nm.capitalize() if count == 1 else "%s %d" % [nm.capitalize(), i + 1]
			if first:
				var line := Combat.enter(label)
				if line != "":
					_system_line(line.replace("*", ""))
				first = false
			else:
				Combat.add_foe(label)
	_render_combat()


func _end_combat() -> void:
	var r: Dictionary = Combat.finish()
	if str(r["note"]) != "":
		_system_line(str(r["note"]).replace("*", ""))
	_render_combat()
	_render_sheet()


func _system_line(text: String) -> void:
	_log_text("[color=%s][i]%s[/i][/color]\n" % [Ui.c("gold").to_html(false), _bb(text)])


func _set_check(check: Dictionary) -> void:
	_pending_check = check
	_roll_bar.visible = not check.is_empty()
	if check.is_empty():
		return
	var sheet := GameState.sheet()
	if check.get("type", "") == "attack":
		_roll_bar.text = "⚔ Roll to hit  d20 %+d%s" % [Rules.attack_mod(sheet, GameState.inv()),
			("  vs AC %d" % int(check["ac"])) if check.get("ac") != null else ""]
	elif check.get("type", "") == "damage":
		_roll_bar.text = "🎲 Roll %s  %dd%d%s" % ["healing" if check.get("heal", false) else "damage",
			int(check["n"]), int(check["sides"]),
			(" %+d" % int(check["bonus"])) if int(check.get("bonus", 0)) != 0 else ""]
	else:
		_roll_bar.text = "🎲 Roll %s  d20 %+d%s" % [Rules.check_label(check),
			Rules.check_mod(sheet, check),
			("  vs DC %d" % int(check["dc"])) if check.get("dc") != null else ""]


func _roll_pending() -> void:
	if _pending_check.is_empty() or _streaming:
		return
	var check := _pending_check
	_set_check({})
	if check.get("type", "") == "death":
		var dr: Dictionary = Combat.death_save()
		if dr.is_empty():
			return
		_render_sheet()
		_log_text("\n%s  %s\n" % [_you(), _md(str(dr["msg"]))])
		if bool(dr["dead"]):
			_system_line("☠ THE TALE ENDS HERE — three failures. A long rest starts a new dawn… if the GM allows it.")
			_log_text("\n%s  " % _gm())
			_last_player_msg = str(dr["msg"])
			_stream(Composer.envelope("[Three death saves failed — I am dying, my tale at its end. Narrate my final moment with the weight it deserves.]"))
		else:
			_log_text("\n%s  " % _gm())
			_last_player_msg = str(dr["msg"])
			_stream(Composer.envelope(str(dr["msg"])))
		return
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	# Damage/healing the GM called for lands on the sheet the moment it's rolled.
	if check.get("type", "") == "damage":
		GameState.apply_hp(int(res["total"]) if check.get("heal", false) else -int(res["total"]))
		_render_sheet()
	_log_text("\n%s  %s\n\n%s  " % [_you(), _md(str(res["text"])), _gm()])
	_last_player_msg = str(res["text"])
	_stream(Composer.envelope(str(res["text"])))


## 🎲 Roll-anything menu: every skill (with your real modifier) + raw abilities.
func _build_dice_menu() -> void:
	var pop: PopupMenu = $Margin/Split/ChatBox/Input/Dice.get_popup()
	pop.clear()
	var s := GameState.sheet()
	var skills := Rules.SKILL2AB.keys()
	skills.sort()
	var idx := 0
	for k in skills:
		var prof: bool = k in s.get("profSkills", [])
		var mod := Rules.ability_mod(int(s["abilities"].get(Rules.SKILL2AB[k], 10))) + (Rules.prof_bonus(s) if prof else 0)
		pop.add_item("%s  %+d%s" % [str(k).capitalize(), mod, "  ●" if prof else ""], idx)
		pop.set_item_metadata(idx, {"skill": k})
		idx += 1
	pop.add_separator("Raw ability")
	idx += 1
	for a in Rules.ABILITIES:
		pop.add_item("%s  %+d" % [a, Rules.ability_mod(int(s["abilities"].get(a, 10)))], idx)
		pop.set_item_metadata(idx, {"abil": a})
		idx += 1
	if not pop.id_pressed.is_connected(_free_check):
		pop.id_pressed.connect(_free_check)


func _free_check(id: int) -> void:
	if _streaming:
		return
	var pop: PopupMenu = $Margin/Split/ChatBox/Input/Dice.get_popup()
	var meta = pop.get_item_metadata(pop.get_item_index(id))
	if meta == null:
		return
	var check := {}
	var label := ""
	if meta.has("skill"):
		check = {"ability": Rules.SKILL2AB[meta["skill"]], "skill": str(meta["skill"]).capitalize()}
		label = "%s check" % str(meta["skill"]).capitalize()
	else:
		check = {"ability": meta["abil"], "skill": ""}
		label = "%s check" % meta["abil"]
	var res: Dictionary = Rules.resolve_check(check, GameState.sheet(), GameState.inv())
	_log_text("\n%s  %s\n\n%s  " % [_you(), _md(str(res["text"])), _gm()])
	_last_player_msg = str(res["text"])
	_stream(Composer.envelope("[I make a %s: I rolled %d. Narrate the outcome — set a DC if there was uncertainty.]" % [label, int(res["total"])]))


## Sheet-panel links: cast:<name>, equip:<id>, sell:<id>. Casting and selling
## are narrated to the GM; equipping is silent kit management.
func _on_sheet_action(meta) -> void:
	var parts := str(meta).split(":", true, 1)
	if parts.size() != 2 or _streaming:
		return
	var note := ""
	var tell_gm := false
	match parts[0]:
		"cast":
			note = GameState.cast_spell(parts[1].uri_decode())
			tell_gm = not note.begins_with("✋")
		"equip":
			note = GameState.toggle_equip(parts[1])
		"sell":
			note = GameState.sell_item(parts[1])
			tell_gm = true
	if note == "":
		return
	_render_sheet()
	if tell_gm:
		_log_text("\n%s  %s\n\n%s  " % [_you(), _md(note), _gm()])
		_last_player_msg = note
		_stream(Composer.envelope(note))
	else:
		_system_line(note.replace("*", ""))


## Combat-panel links: atk:<id>, cnext, cend.
func _on_combat_action(meta) -> void:
	if _streaming:
		return
	var m := str(meta)
	if m == "cend":
		_end_combat()
		_stream(Composer.envelope("[I end the fight here. Narrate the aftermath of the battle briefly.]"))
		_log_text("\n%s  " % _gm())
		return
	if m == "cnext":
		Combat.next_turn()
		var c: Dictionary = Combat.data()
		var cur: Dictionary = Combat.current(c)
		if cur.get("side") == "enemy" and int(cur.get("hp", 0)) > 0:
			var r: Dictionary = Combat.enemy_turn(cur)
			_log_text("\n%s  %s\n" % [_you(), _md(str(r["msg"]))])
			_render_sheet()
			if str(r["gm"]) != "":
				_log_text("\n%s  " % _gm())
				_last_player_msg = str(r["msg"])
				_stream(Composer.envelope(str(r["gm"])))
		elif str(cur.get("id", "")).begins_with("cmp"):
			var cr: Dictionary = Combat.companion_turn(cur)
			if str(cr["msg"]) != "":
				_log_text("\n%s  %s\n" % [_you(), _md(str(cr["msg"]))])
		elif str(cur.get("id", "")) == "pc":
			_system_line("Round %d — your turn." % int(c.get("round", 1)))
		return
	if m.begins_with("atk:"):
		var r2: Dictionary = Combat.player_attack(m.substr(4))
		if not bool(r2["spent"]):
			_system_line(str(r2["msg"]).replace("*", ""))
			return
		if str(r2["msg"]) == "":
			return
		_log_text("\n%s  %s\n" % [_you(), _md(str(r2["msg"]))])
		if bool(r2["won"]):
			_end_combat()
			_log_text("\n%s  " % _gm())
			_stream(Composer.envelope("%s\n[Victory — the last foe falls! Narrate the killing blow in full cinema, then the aftermath.]" % str(r2["msg"])))
		elif bool(r2["fell"]):
			_log_text("\n%s  " % _gm())
			_stream(Composer.envelope("%s\n[The foe falls — narrate the finish with cinema.]" % str(r2["msg"])))
		else:
			_log_text("\n%s  " % _gm())
			_last_player_msg = str(r2["msg"])
			_stream(Composer.envelope(str(r2["msg"])))


func _render_combat() -> void:
	var c: Dictionary = Combat.data()
	_combat_panel.visible = bool(c.get("active", false))
	if not _combat_panel.visible:
		return
	# Downed hero: the only roll that matters now is the death save.
	if not Combat.pc_down().is_empty():
		_pending_check = {"type": "death"}
		_roll_bar.text = "☠ Roll a death save"
		_roll_bar.visible = true
	var gold := Ui.c("gold_soft").to_html(false)
	var danger := Ui.c("danger").to_html(false)
	var cur: Dictionary = Combat.current(c)
	var lines: Array[String] = []
	lines.append("[color=%s][b]⚔ COMBAT — Round %d[/b][/color]    [url=cnext]Next ›[/url]    [url=cend]End combat[/url]" % [gold, int(c.get("round", 1))])
	for m in Combat.order(c):
		var here := "▶ " if str(m.get("id")) == str(cur.get("id")) else "   "
		var hp := int(m.get("hp", 0))
		var hp_max := maxi(1, int(m.get("hpMax", 1)))
		var bar_n := clampi(roundi(10.0 * hp / hp_max), 0, 10)
		var color := gold if m.get("side") == "ally" else danger
		var row := "%s[color=%s]%s[/color]  [%s%s] %d/%d" % [here, color, _bb(str(m.get("name", "?"))),
			"█".repeat(bar_n), "░".repeat(10 - bar_n), hp, hp_max]
		if m.get("side") == "enemy" and hp > 0:
			row += "   [url=atk:%s]⚔ attack[/url]" % str(m.get("id"))
		elif hp <= 0:
			row += "   ✝"
		lines.append(row)
	_combat_panel.text = "\n".join(lines)


func _rest(kind: String) -> void:
	if _streaming:
		return
	var r: Dictionary = GameState.short_rest() if kind == "short" else GameState.long_rest()
	_render_sheet()
	_log_text("\n%s  %s\n\n%s  " % [_you(), _md(str(r["note"])), _gm()])
	_last_player_msg = str(r["note"])
	_stream(Composer.envelope(str(r["gm"])))


func _render_sheet() -> void:
	var s := GameState.sheet()
	var gold := Ui.c("gold_soft").to_html(false)
	var lines: Array[String] = []
	lines.append("[color=%s][b]%s[/b][/color]" % [gold, _bb(str(s.get("name", "?")))])
	lines.append("%s %s, level %d" % [_bb(str(s.get("race", ""))), _bb(str(s.get("cls", ""))), int(s.get("level", 1))])
	lines.append("")
	lines.append("HP [b]%d / %d[/b]    AC [b]%d[/b]" % [int(s.get("hp", 10)), int(s.get("hpMax", 10)), Rules.eff_ac(s, GameState.inv())])
	lines.append("Gold [b]%d[/b]    Passive Perception [b]%d[/b]" % [int(s.get("gold", 0)), Rules.passive_perception(s)])
	lines.append("")
	for k in Rules.ABILITIES:
		var v := int(s.get("abilities", {}).get(k, 10))
		lines.append("%s  [b]%d[/b]  (%+d)" % [k, v, Rules.ability_mod(v)])
	var pool := int(s.get("level", 1))
	lines.append("Hit Dice [b]%d / %d[/b] (d%d)" % [pool - int(s.get("hitDiceUsed", 0)), pool, int(s.get("hitDie", 8))])
	if int(s.get("exhaustion", 0)) > 0:
		lines.append("[color=%s]Exhaustion level %d[/color]" % [Ui.c("danger").to_html(false), int(s["exhaustion"])])
	var prof: Array = s.get("profSkills", [])
	if not prof.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Proficient[/b][/color]  %s" % [gold, _bb(", ".join(prof.map(func(x): return str(x))))])
	var conds: Array = s.get("conditions", [])
	if not conds.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Conditions[/b][/color]  %s" % [gold, _bb(", ".join(conds.map(func(c): return str(c.get("name", c)) if c is Dictionary else str(c))))])
	var spells: Array = s.get("spells", [])
	if not spells.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Spells[/b][/color]" % gold)
		for sp in spells:
			var lv := int(sp.get("level", 0))
			lines.append("  %s %s  [url=cast:%s]✦ cast[/url]" % [_bb(str(sp.get("name", ""))),
				("(lvl %d)" % lv) if lv > 0 else "(cantrip)", str(sp.get("name", "")).uri_encode()])
		var slots: Dictionary = s.get("slots", {})
		var slot_parts: Array[String] = []
		var slot_keys := slots.keys()
		slot_keys.sort()
		for l in slot_keys:
			if slots[l] is Dictionary and int(slots[l].get("max", 0)) > 0:
				slot_parts.append("L%s %d/%d" % [l, maxi(0, int(slots[l]["max"]) - int(slots[l].get("used", 0))), int(slots[l]["max"])])
		if not slot_parts.is_empty():
			lines.append("  Slots: %s" % "  ".join(slot_parts))
	var inv: Dictionary = GameState.inv()
	var items: Array = inv.get("items", [])
	if not items.is_empty():
		var worn: Array = inv.get("equipped", {}).values()
		lines.append("")
		lines.append("[color=%s][b]Pack[/b][/color]  (%d/%d slots)" % [gold, items.size(), int(inv.get("slots", 24))])
		for it in items:
			var q := int(it.get("qty", 1))
			var id := str(it.get("id", ""))
			var row := "  %s%s%s" % [_bb(str(it.get("name", ""))), (" ×%d" % q) if q > 1 else "",
				"  [color=%s]● worn[/color]" % gold if id in worn else ""]
			if str(it.get("type", "")) in ["weapon", "armor", "shield"]:
				row += "  [url=equip:%s]%s[/url]" % [id, "unequip" if id in worn else "equip"]
			row += "  [url=sell:%s]sell %d[/url]" % [id, Rules.sell_value(str(it.get("rarity", "common")))]
			lines.append(row)
	var feats: Array = s.get("feats", [])
	if not feats.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Feats[/b][/color]  %s" % [gold, _bb(", ".join(feats.map(func(x): return str(x))))])
	var features: Array = s.get("features", [])
	if not features.is_empty():
		lines.append("")
		lines.append("[color=%s][b]Class features[/b][/color]" % gold)
		for f in features:
			lines.append("  %s" % _bb(str(f)))
	_sheet_panel.text = "\n".join(lines)


func _log_text(bbcode: String) -> void:
	_log.append_text(bbcode)


## Escape model/user text so it can't inject BBCode.
func _bb(s: String) -> String:
	return s.replace("[", "[lb]")


## Roll-result lines use markdown ** ** — show them bold in our log.
func _md(s: String) -> String:
	var out := _bb(s)
	var parts := out.split("**")
	if parts.size() % 2 == 1:
		out = ""
		for i in parts.size():
			out += ("[b]%s[/b]" % parts[i]) if i % 2 == 1 else parts[i]
	return out

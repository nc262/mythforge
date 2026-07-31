extends ForgeFlow
## The Companion Forge — forge a persona of your own: a face, a role, a story.
## Sealed companions live in the gallery (_global.cpersonas), can be chosen at
## the adventure table's Party stage to ride in on day one, and their painted
## face (npc-<slug> art key) is the SAME one the journal and codex wear —
## forge them once, meet them everywhere. Stage-content only, on ForgeFlow.

signal persona_forged(persona: Dictionary)

const STAGES := ["The Face", "The Story", "The Bond"]

var draft := {"name": "", "role": "", "desc": ""}
var _sealed := false
var _portrait: TextureRect = null


func _stages() -> Array:
	return STAGES


func _env() -> Array:
	return ["env-fireside", "dust", [Vector2(0.12, 0.3)]]


func _leave_label() -> String:
	return "leave the fireside"


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_face()
		1:
			_stage_story()
		2:
			_stage_bond()


func _slug() -> String:
	return "npc-" + str(draft["name"]).to_lower().strip_edges().replace(" ", "-")


# ── Stage 0: name and role ───────────────────────────────────────────────────
func _stage_face() -> void:
	_title_label("Who Sits Across the Fire?")
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Their name — e.g. Ser Aldric, Wren of the Docks…"
	name_in.text = str(draft["name"])
	name_in.custom_minimum_size = Vector2(420, 0)
	var kit_hint := Label.new()
	kit_hint.theme_type_variation = "HintLabel"
	kit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var role_in := LineEdit.new()
	role_in.placeholder_text = "Their role — temple healer, court wizard, sellsword…"
	role_in.text = str(draft["role"])
	role_in.custom_minimum_size = Vector2(420, 0)
	var update_kit := func():
		var kit := GameState.infer_companion_kit(str(draft["role"]))
		kit_hint.text = ("They'd fight as a %s — AC %d." % [str(kit["cls"]), int(kit["ac"])]) if str(draft["role"]) != "" else ""
	name_in.text_changed.connect(func(t): draft["name"] = t)
	role_in.text_changed.connect(func(t):
		draft["role"] = t
		update_kit.call())
	update_kit.call()
	for w in [name_in, role_in]:
		var cc := CenterContainer.new()
		cc.add_child(w)
		_stage_box.add_child(cc)
	_stage_box.add_child(kit_hint)
	_nav(-1, "To their Story ›", func():
		if str(draft["name"]).strip_edges() == "":
			_refuse("A companion needs a name.")
			return
		_enter_stage(1))


# ── Stage 1: the story and the painted face ──────────────────────────────────
func _stage_story() -> void:
	_title_label("The Story of %s" % str(draft["name"]))
	var desc := TextEdit.new()
	desc.placeholder_text = "Who they are, how they carry themselves, what they look like — the painter and the GM both read this."
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.custom_minimum_size = Vector2(520, 120)
	desc.text = str(draft["desc"])
	desc.text_changed.connect(func(): draft["desc"] = desc.text)
	var cc := CenterContainer.new()
	cc.add_child(desc)
	_stage_box.add_child(cc)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(180, 180)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var have := Art.round_tex(_slug(), 180)
	if have != null:
		_portrait.texture = have
	var pc := CenterContainer.new()
	pc.add_child(_portrait)
	_stage_box.add_child(pc)
	if not Art.art_ready.is_connected(_on_art):
		Art.art_ready.connect(_on_art)
	var paint := Button.new()
	paint.theme_type_variation = "AccentButton"
	paint.text = "Paint the portrait"
	paint.pressed.connect(func():
		var subj := "%s, %s. %s" % [str(draft["name"]), str(draft["role"]), str(draft["desc"])]
		Art.ensure(_slug(), "%s %s" % [Art.subject_style("char"), subj], "768x768")
		_status.text = "The painter works — the face appears here and in every journal page they'll ever grace.")
	var bc := CenterContainer.new()
	bc.add_child(paint)
	_stage_box.add_child(bc)
	_nav(0, "To the Bond ›", func(): _enter_stage(2))


func _on_art(key: String) -> void:
	if key == _slug() and is_instance_valid(_portrait):
		_portrait.texture = Art.round_tex(_slug(), 180)


# ── Stage 2: seal into the gallery ───────────────────────────────────────────
func _stage_bond() -> void:
	_title_label("Seal the Bond")
	var kit := GameState.infer_companion_kit(str(draft["role"]))
	var sum := Label.new()
	sum.theme_type_variation = "HintLabel"
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.custom_minimum_size = Vector2(520, 0)
	sum.text = "%s — %s (fights as a %s)\n%s" % [str(draft["name"]), str(draft["role"]),
		str(kit["cls"]), str(draft["desc"]).left(200)]
	_stage_box.add_child(sum)
	_nav(1, "SEAL THE COMPANION" if not _sealed else "Sealed — seal again", _seal)


func _seal() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Sealing the bond…"
	var p := {"name": str(draft["name"]), "role": str(draft["role"]), "desc": str(draft["desc"])}
	var arr: Array = GameState.global_get("cpersonas", [])
	arr = arr.filter(func(x): return str(x.get("name", "")) != p["name"])
	arr.append(p)
	GameState.global_set("cpersonas", arr)
	_busy = false
	_status.text = "%s waits by the fire — choose them at the adventure table's Party stage." % p["name"]
	_sealed = true
	Sfx.play("chime")
	persona_forged.emit(p)

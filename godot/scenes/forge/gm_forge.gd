extends ForgeFlow
## The GM Forge — forge a Game Master persona of your own: a name, a table
## manner, and the five tone knobs. Sealed personas live in the gallery
## (_global.cgms) and appear as voice cards in the Campaign Forge beside the
## built-in archetypes. Stage-content only; the scaffold is ForgeFlow.

signal gm_forged(persona: Dictionary)

const STAGES := ["The Seat", "The Tone", "The Seal"]
const ARCHETYPES := [
	{"glyph": "crown", "title": "Classic DM", "body": "fair, steady, by the book", "knobs": {"length": 50, "humor": 40, "spice": 0, "grit": 55, "pace": 50, "rules": 75}},
	{"glyph": "book", "title": "Narrative", "body": "story first, rules soft", "knobs": {"length": 70, "humor": 55, "spice": 40, "grit": 45, "pace": 40, "rules": 25}},
	{"glyph": "skull", "title": "Hardcore", "body": "brutal, strict, earned", "knobs": {"length": 35, "humor": 20, "spice": 0, "grit": 95, "pace": 60, "rules": 90}},
	{"glyph": "compass", "title": "Sandbox", "body": "player-led, world breathes", "knobs": {"length": 45, "humor": 45, "spice": 20, "grit": 50, "pace": 70, "rules": 40}},
	{"glyph": "sigil", "title": "Cinematic", "body": "set pieces, hard cuts", "knobs": {"length": 40, "humor": 50, "spice": 30, "grit": 65, "pace": 85, "rules": 35}},
]
const KNOB_ROWS := [["length", "Reply length — brief ↔ let it run"],
	["humor", "Humor — serious ↔ comedic"], ["spice", "Romance & spice — none ↔ bold"],
	["grit", "Grit & danger — gentle ↔ brutal"], ["pace", "Pace — slow ↔ fast"], ["rules", "Rules — loose ↔ strict"]]

var draft := {"title": "", "line": "", "knobs": {"length": 50, "humor": 45, "spice": 10, "grit": 55, "pace": 55, "rules": 50}}
var _sealed := false


func _stages() -> Array:
	return STAGES


func _leave_label() -> String:
	return "leave the seat"


func _build_stage(i: int) -> void:
	match i:
		0:
			_stage_seat()
		1:
			_stage_tone()
		2:
			_stage_seal()


# ── Stage 0: who sits behind the screen ──────────────────────────────────────
func _stage_seat() -> void:
	_title_label("Who Takes the Seat?")
	var name_in := LineEdit.new()
	name_in.placeholder_text = "The GM's name — e.g. Old Marrow, The Archivist…"
	name_in.text = str(draft["title"])
	name_in.custom_minimum_size = Vector2(420, 0)
	name_in.text_changed.connect(func(t): draft["title"] = t)
	var line_in := LineEdit.new()
	line_in.placeholder_text = "Their table manner, in a line — e.g. a wry veteran who loves a slow reveal"
	line_in.text = str(draft["line"])
	line_in.custom_minimum_size = Vector2(420, 0)
	line_in.text_changed.connect(func(t): draft["line"] = t)
	for w in [name_in, line_in]:
		var cc := CenterContainer.new()
		cc.add_child(w)
		_stage_box.add_child(cc)
	var hint := Label.new()
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Start from an archetype if you like — the knobs prefill:"
	_stage_box.add_child(hint)
	_card_grid(ARCHETYPES, 5, "", func(a: Dictionary):
		draft["knobs"] = a["knobs"].duplicate()
		if str(draft["title"]) == "":
			draft["title"] = str(a["title"]))
	_nav(-1, "To the Tone ›", func():
		if str(draft["title"]).strip_edges() == "":
			_status.text = "Every GM needs a name."
			return
		_enter_stage(1))


# ── Stage 1: the five knobs ──────────────────────────────────────────────────
func _stage_tone() -> void:
	_title_label("Set %s's Tone" % str(draft["title"]))
	var sliders := {}
	for k in KNOB_ROWS:
		var lbl := Label.new()
		lbl.theme_type_variation = "HintLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = str(k[1])
		_stage_box.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int(draft["knobs"].get(k[0], 50))
		sl.custom_minimum_size = Vector2(420, 0)
		sl.value_changed.connect(func(v): draft["knobs"][k[0]] = int(v))
		var cc := CenterContainer.new()
		cc.add_child(sl)
		_stage_box.add_child(cc)
	_nav(0, "To the Seal ›", func(): _enter_stage(2))


# ── Stage 2: seal into the gallery ───────────────────────────────────────────
func _stage_seal() -> void:
	_title_label("Seal %s" % str(draft["title"]))
	var sum := Label.new()
	sum.theme_type_variation = "HintLabel"
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.custom_minimum_size = Vector2(520, 0)
	var kb: Dictionary = draft["knobs"]
	sum.text = "%s — %s\nHumor %d · Spice %d · Grit %d · Pace %d · Rules %d" % [
		str(draft["title"]), str(draft["line"]) if str(draft["line"]) != "" else "a table manner all their own",
		int(kb.get("humor", 50)), int(kb.get("spice", 0)), int(kb.get("grit", 50)), int(kb.get("pace", 50)), int(kb.get("rules", 50))]
	_stage_box.add_child(sum)
	_nav(1, "SEAL THIS GM" if not _sealed else "Sealed — seal again", _seal)


func _seal() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Pressing the seal…"
	var persona := {"title": str(draft["title"]), "body": str(draft["line"]), "knobs": draft["knobs"].duplicate()}
	var cgms: Array = GameState.global_get("cgms", [])
	cgms = cgms.filter(func(p): return str(p.get("title", "")) != persona["title"])
	cgms.append(persona)
	GameState.global_set("cgms", cgms)
	_busy = false
	_status.text = "%s takes their seat in the gallery — the Campaign Forge now offers this voice." % persona["title"]
	_sealed = true
	Sfx.play("chime")
	gm_forged.emit(persona)

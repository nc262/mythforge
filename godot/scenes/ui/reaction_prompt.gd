extends AcceptDialog
## ⚡ Reaction! The enemy's blow pends while the player chooses: Shield /
## Uncanny Dodge / Parry / take the hit. Extracted from game.gd (A0 split):
## the reaction mechanics (slot spend, damage halving, parry die) live here
## via the autoloads; the play screen hears resolved(dmg, note) and owns the
## actual hit resolution + narration + round resume.

signal resolved(dmg: int, note: String)

var pend: Dictionary = {}     # {enemy, total, ac, dmg, crit}
var reactions: Array = []     # subset of ["shield", "dodge", "parry"]


func _ready() -> void:
	title = "Reaction!"
	ok_button_text = "Take the hit"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var enemy: Dictionary = pend["enemy"]
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(380, 0)
	lbl.text = "The %s's blow is coming in — %d vs your AC %d, %d damage%s." % [
		str(enemy.get("name", "?")), int(pend["total"]), int(pend["ac"]), int(pend["dmg"]),
		" (CRIT)" if bool(pend["crit"]) else ""]
	box.add_child(lbl)
	var resolve := func(dmg: int, note: String):
		queue_free()
		resolved.emit(dmg, note)
	if reactions.has("shield"):
		var b1 := _ico_button("shield", "Shield — +5 AC, spends a slot")
		b1.pressed.connect(func():
			GameState.cast_spell("Shield")
			if int(pend["total"]) < int(pend["ac"]) + 5:
				resolve.call(0, "your Shield flares — the blow glances off")
			else:
				resolve.call(int(pend["dmg"]), "even the ward can't stop this one"))
		box.add_child(b1)
	if reactions.has("dodge"):
		var b2 := _ico_button("swirl", "Uncanny Dodge — halve the damage")
		b2.pressed.connect(func(): resolve.call(ceili(int(pend["dmg"]) / 2.0), "you twist away at the last instant"))
		box.add_child(b2)
	if reactions.has("parry"):
		var b3 := _ico_button("medal", "Parry — superiority die + mod off the damage")
		b3.pressed.connect(func():
			GameState.use_feature("Combat Maneuver")
			var s := GameState.sheet()
			var red := randi_range(1, 8) + maxi(Rules.ability_mod(int(s["abilities"].get("STR", 10))), Rules.ability_mod(int(s["abilities"].get("DEX", 10))))
			resolve.call(maxi(0, int(pend["dmg"]) - red), "your parry turns %d of it aside" % red))
		box.add_child(b3)
	add_child(box)
	confirmed.connect(func(): resolve.call(int(pend["dmg"]), ""))


## A button that leads with hand-drawn art instead of an emoji glyph.
func _ico_button(glyph: String, label: String) -> Button:
	var b := Button.new()
	b.icon = Ui.ico_tex(glyph)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 20)
	b.add_theme_color_override("icon_normal_color", Ui.c("gold"))
	b.text = label
	return b

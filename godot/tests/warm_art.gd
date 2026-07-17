extends Node
## Dev harness: commission the demo cast's art and wait for the queue to
## drain, so screenshot runs (and first play) find the paintings cached.
##   godot --path godot res://tests/warm_art.tscn

var _want: Array = []


func _ready() -> void:
	Ui.apply("embervale")
	GameState.character = {"id": "dm-godot-demo", "name": "The Hollow Bell", "world_id": "embervale"}
	GameState.state = {"world": {"here": "Embervale village square"}}
	var sheet := {"name": "Wren Ashvale", "race": "Half-Elf", "cls": "Wizard"}
	Art.ensure("embervale")
	Art.ensure_hero_portrait("dm-godot-demo", sheet)
	_want.append("hero-dm-godot-demo")
	for foe in ["Goblin", "Goblin Boss"]:
		var entry := Combat.bestiary_for(foe)
		if not entry.is_empty():
			var key := "beast-" + str(entry.get("slug", ""))
			Art.ensure(key, str(entry.get("art", "")) + ", painted creature portrait, dark background, no text")
			_want.append(key)
	for nm in ["Silvered Dagger", "Traveler's Leathers", "Healing Potion"]:
		Art.ensure_item_icon(nm)
		_want.append("item-" + nm.to_lower().replace(" ", "-"))
	_want.append(Art.ensure_battle_map("Embervale village square"))
	_want.append(Art.ensure_world_chart("embervale", "Embervale"))
	# The EAS rooms — the illustrated environments every screen stands in.
	for env in Art.ENV_PROMPTS:
		Art.ensure_environment(str(env))
		_want.append(str(env))
	# The opening cinematic's four worlds.
	for k in Art.CINE_PROMPTS:
		Art.ensure(str(k), str(Art.CINE_PROMPTS[k]), "1344x768")
		_want.append(str(k))
	_wait()


func _wait() -> void:
	var deadline := Time.get_ticks_msec() + 15 * 60 * 1000
	while Time.get_ticks_msec() < deadline:
		var missing := []
		for k in _want:
			if not Art.has_art(k):
				missing.append(k)
		if missing.is_empty():
			print("WARM-ART OK ", _want.size(), " paintings cached")
			get_tree().quit()
			return
		await get_tree().create_timer(5.0).timeout
	print("WARM-ART TIMEOUT still missing: ", _want.filter(func(k): return not Art.has_art(k)))
	get_tree().quit(1)

extends Node
## Dev harness: load a scene, wait for it to paint (and hydrate), save a PNG.
##   MF_SHOT_SCENE=res://scenes/game.tscn MF_SHOT_OUT=C:/tmp/game.png \
##   godot --path godot res://tests/screenshot.tscn

func _ready() -> void:
	var scene_path := OS.get_environment("MF_SHOT_SCENE")
	var out := OS.get_environment("MF_SHOT_OUT")
	if OS.get_environment("MF_SHOT_DEMO") == "1":
		_seed_demo()
		await get_tree().create_timer(1.0).timeout  # let the seeded state settle
	var scene = load(scene_path).instantiate()
	add_child(scene)
	if OS.get_environment("MF_SHOT_DEMO") == "1" and scene_path.contains("game"):
		await get_tree().create_timer(1.5).timeout  # let the scene's hydrate() settle
		_seed_demo()  # then plant the demo state on top
		var btn: Button = scene.get_node("Margin/Split/ChatBox/Input/SheetBtn")
		btn.button_pressed = true
		Combat.enter("Goblin Boss")
		Combat.add_foe("Goblin")
		scene.call("_render_combat")
		scene.call("_render_sheet")
		var gm_rt: RichTextLabel = scene.call("_bubble", "gm")
		gm_rt.append_text("The chapel door splinters — goblins pour through the gap, their boss bellowing behind them. Steel glints in the candlelight. [i]Roll for initiative![/i]")
		scene.call("_say_me", "I hurl my lantern at the boss and draw my silvered dagger!")
		if OS.get_environment("MF_SHOT_INV") == "1":
			scene.call("_open_inventory")
		if OS.get_environment("MF_SHOT_JOURNAL") == "1":
			Combat.finish()
			scene.call("_open_journal")
		if OS.get_environment("MF_SHOT_HERO") == "1":
			Combat.finish()
			# MF_SHOT_TAB picks the page — the sheet has nine and they do not
			# have the same problems, so a shot of whichever opens by default
			# cannot answer a question about a specific one.
			scene.call("_open_character_screen", OS.get_environment("MF_SHOT_TAB"))
		if OS.get_environment("MF_SHOT_TREE") == "1":
			Combat.finish()
			scene.call("_open_skill_tree", 4)
		if OS.get_environment("MF_SHOT_MAP") == "1":
			Combat.finish()
			scene.call("_open_world_map")
		scene.call("_say_system", "⚔️ Combat — Goblin Boss!")
	await get_tree().create_timer(2.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT SAVED ", out)
	get_tree().quit()


func _seed_demo() -> void:
	Ui.apply("embervale")
	GameState.character = {"id": "dm-godot-demo", "name": "The Hollow Bell", "world_id": "embervale"}
	GameState.state = {"sheet": {"name": "Wren Ashvale", "race": "Half-Elf", "cls": "Wizard", "level": 4, "xp": 640,
		"hp": 21, "hpMax": 26, "gold": 87,
		"abilities": {"STR": 8, "DEX": 14, "CON": 12, "INT": 17, "WIS": 12, "CHA": 10},
		"profSkills": ["arcana", "investigation", "stealth"], "profSaves": ["INT", "WIS"],
		"hitDie": 6, "hitDiceUsed": 1, "conditions": [], "features": ["Arcane Recovery", "Arcane Tradition"],
		"spells": [{"name": "Firebolt", "level": 0}, {"name": "Magic Missile", "level": 1}, {"name": "Misty Step", "level": 2}],
		"slots": {"1": {"max": 4, "used": 1}, "2": {"max": 3, "used": 0}}},
		"inv": {"slots": 24, "items": [
			{"id": "w1", "name": "Silvered Dagger", "qty": 1, "rarity": "rare", "type": "weapon", "dmg": "1d4", "atk": 1},
			{"id": "a1", "name": "Traveler's Leathers", "qty": 1, "rarity": "common", "type": "armor", "acBonus": 2},
			{"id": "p1", "name": "Healing Potion", "qty": 3, "rarity": "uncommon", "type": "gear"}],
			"equipped": {"weapon": "w1", "armor": "a1"}},
		"clock": {"day": 3, "ti": 5, "wx": {"ico": "🌧", "name": "soft valley rain"}},
		"world": {"here": "The Ember & Oak", "seen": ["Hearthwood Market"]},
		"quests": [
			{"title": "The Hollow Bell Tolls", "desc": "Find who rings the drowned chapel bell at midnight.", "status": "active"},
			{"title": "Rats in the Cellar", "desc": "Clear the Ember & Oak's cellar for Talia.", "status": "done"}],
		"codex": [
			{"name": "Talia", "role": "innkeeper of the Ember & Oak", "note": "Warm, sharp-eyed, knows every road and rumor in the valley."},
			{"name": "Old Maren", "role": "chapel warden", "note": "Went pale when the bell was mentioned. Hiding something."}]}
	# Persist the demo state server-side so the scene's hydrate() finds it
	# (otherwise the hero forge gates in front of whatever we want to shoot).
	for kind in ["sheet", "inv", "clock"]:
		GameState.save_kind(kind, GameState.state[kind])

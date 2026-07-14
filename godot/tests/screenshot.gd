extends Node
## Dev harness: load a scene, wait for it to paint (and hydrate), save a PNG.
##   MF_SHOT_SCENE=res://scenes/login.tscn MF_SHOT_OUT=C:/tmp/login.png \
##   godot --path godot res://tests/screenshot.tscn

func _ready() -> void:
	var scene_path := OS.get_environment("MF_SHOT_SCENE")
	var out := OS.get_environment("MF_SHOT_OUT")
	var scene = load(scene_path).instantiate()
	add_child(scene)
	await get_tree().create_timer(2.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT SAVED ", out)
	get_tree().quit()

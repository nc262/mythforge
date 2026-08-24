extends Node
## PL-5, reproduced on purpose.
##
## Four theories died today because none of them could make the error happen.
## Three measurements narrowed it: no autoload signal leaks a connection across a
## playthrough, the root Window does not either, and `art_ready` barely fires in
## the harness at all. So the lambda that dies is not reached through a
## CONNECTION — and there is exactly one deferred lambda in the whole codebase.
##
## `skin.gd:_cap_panel_content` ends with `apply.call_deferred()`. `apply`
## captures TWO objects, `dlg` and `content` — index 0 and index 1. Free the
## dialog before the deferred call flushes and both captures are gone when Godot
## rebinds them.
##
##   godot --headless --path godot res://tests/pl5_probe.tscn
##
## Prints REPRO if the engine complains, NO-REPRO if it does not. The engine's
## error goes to stderr and cannot be caught from GDScript, so the runner greps
## for it — this scene's job is to CAUSE it on demand, deterministically.

func _ready() -> void:
	await get_tree().process_frame
	print("PL5: dressing a dialog, then freeing it before the deferred apply runs")
	for i in 5:
		var d := AcceptDialog.new()
		var c := VBoxContainer.new()
		var lab := Label.new()
		lab.text = "content that gives the panel a minimum size"
		c.add_child(lab)
		d.add_child(c)
		get_tree().root.add_child(d)
		# This is the whole game: dress_dialog -> _cap_panel_content -> the
		# deferred apply is now QUEUED with dlg and content captured.
		Ui.dress_dialog(d, c)
		# …and the panel dies in the same frame, which is what a player does by
		# closing a dialog the instant it opens.
		get_tree().root.remove_child(d)
		d.free()
	print("PL5: five dialogs dressed and freed; flushing deferred calls")
	await get_tree().process_frame
	await get_tree().process_frame
	print("PL5: flushed")
	print("PL5-PROBE DONE")
	get_tree().quit(0)

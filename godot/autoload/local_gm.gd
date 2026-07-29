extends Node
## The narrator, in-process — Stage 2 of docs/Architecture-InProcess.md.
##
## Today a GM turn is an HTTP POST to a FastAPI server on this same desktop,
## which forwards to Ollama, which runs llama.cpp. This runs llama.cpp directly,
## in the game's own process, via the NobodyWho GDExtension.
##
## It is deliberately built to be INERT until two things are true: the extension
## is installed, and a GGUF model is present. Neither is checked at import time,
## so a copy of the game without them behaves exactly as before — the remote
## path is not removed, it is simply not chosen. That keeps this shippable on
## its own rather than as a flag day.
##
## The seam it plugs into already existed. `Api.stream_chat()` emits
## `sse_delta` per batch and `sse_done` once, and already branches for
## `test_mode`; this is a third branch answering the same contract. Nothing
## downstream — the tag pipeline, the language gate, Chronicle — can tell which
## narrator spoke.

## Where a player's models live. Kept out of `res://` on purpose: a 4-8 GB GGUF
## has no business inside the exe, and the same file serves every adventure.
const MODEL_DIR := "user://models"

## llama.cpp accelerates on this AMD card through VULKAN, which is the whole
## reason this path is attractive here — no ROCm, no CUDA, and therefore none of
## the ZLUDA scaffolding the image stack still needs (see CLAUDE.md).
const CLASS_CHAT := "NobodyWhoChat"
const CLASS_MODEL := "NobodyWhoModel"

var _model: Node = null
var _chat: Node = null
var _busy := false


## The first GGUF in the models folder, or "" if there is none.
func model_file() -> String:
	var d := DirAccess.open(MODEL_DIR)
	if d == null:
		return ""
	for f in d.get_files():
		if f.to_lower().ends_with(".gguf"):
			return MODEL_DIR + "/" + f
	return ""


## Both halves must be present. `ClassDB` is the honest test for the extension:
## the class only exists once the GDExtension has actually loaded, so a broken
## or missing install reports false instead of crashing at the first call.
func available() -> bool:
	return ClassDB.class_exists(CLASS_CHAT) and ClassDB.class_exists(CLASS_MODEL) \
		and model_file() != ""


func why_unavailable() -> String:
	if not ClassDB.class_exists(CLASS_CHAT):
		return "the NobodyWho extension is not installed"
	if model_file() == "":
		return "no .gguf model in %s" % ProjectSettings.globalize_path(MODEL_DIR)
	return ""


func _ensure_nodes(system_prompt: String) -> bool:
	if _chat != null and is_instance_valid(_chat):
		_chat.set("system_prompt", system_prompt)
		return true
	if not available():
		return false
	_model = ClassDB.instantiate(CLASS_MODEL)
	if _model == null:
		return false
	_model.set("model_path", ProjectSettings.globalize_path(model_file()))
	add_child(_model)
	_chat = ClassDB.instantiate(CLASS_CHAT)
	if _chat == null:
		return false
	_chat.set("model_node", _model)
	_chat.set("system_prompt", system_prompt)
	add_child(_chat)
	# NobodyWho streams tokens on `response_updated` and closes with
	# `response_finished` — the same shape as the SSE contract, so the bridge is
	# a rename rather than a buffer.
	_chat.connect("response_updated", _on_token)
	_chat.connect("response_finished", _on_finished)
	# Load the weights NOW rather than on the first turn. Without this the
	# extension warns and does it lazily, which buries a ~4.6 GB model load
	# inside the player's first sentence — the one turn where the game most
	# needs to look alive.
	if _chat.has_method("start_worker"):
		_chat.call("start_worker")
	return true


func _on_token(tok: String) -> void:
	Api.sse_delta.emit(tok)


func _on_finished(_full: String) -> void:
	_busy = false
	Api.sse_done.emit(true)


## Speak one turn. Answers `Api`'s signals so callers never learn which narrator
## they got. Returns false if this path is not usable, so the caller falls
## through to the server exactly as before.
func stream(message: String, system_prompt := "") -> bool:
	if _busy or not _ensure_nodes(system_prompt):
		return false
	_busy = true
	# `ask` is the current name; `say` is deprecated upstream and warns on every
	# turn. Fall back for older builds of the extension rather than requiring one.
	_chat.call("ask" if _chat.has_method("ask") else "say", message)
	return true

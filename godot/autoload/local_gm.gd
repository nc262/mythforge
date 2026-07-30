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
## A SECOND chat over the same model, for structured answers.
##
## The sampler is per-chat-node, so constraining the narrator's node to JSON
## would silently turn prose into objects. Sharing `_model` means this costs a
## context, not another 4.6 GB of weights.
var _json_chat: Node = null


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
	# INERT UNDER test_mode, so the harnesses stay deterministic. `stream_chat`
	# already returns its canned reply before consulting this, but
	# `complete_json` is reached from the World Compiler with no such guard — and
	# a harness that silently runs a real 8B model is neither fast nor repeatable.
	if Api.test_mode:
		return false
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


## One JSON answer from the local model.
##
## PASS A SCHEMA. Measured on llama3.1-8b, same prompt:
##
##   set_sampler_preset_json()                     4798 ms — output still arrives
##                                                 fenced in ```json and does NOT
##                                                 parse. It is not the constraint
##                                                 its name suggests.
##   set_sampler_preset_constrain_with_json_schema  717 ms — parses directly, with
##                                                 exactly the keys demanded.
##
## 6.7x faster AND correct, because the grammar prunes the token space: the model
## cannot spend tokens on a fence or a preamble, so it does not. Without a schema
## this is no better than the server path — the caller still has to dig the object
## out of the chatter (world_compiler._extract_json exists for precisely that).
##
## Returns "" when unusable, so callers fall through to the server as before.
func complete_json(prompt: String, schema := "") -> String:
	if not available():
		return ""
	if _model == null and not _ensure_nodes(""):
		return ""
	if _json_chat == null or not is_instance_valid(_json_chat):
		_json_chat = ClassDB.instantiate(CLASS_CHAT)
		if _json_chat == null:
			return ""
		_json_chat.set("model_node", _model)
		add_child(_json_chat)
		if _json_chat.has_method("start_worker"):
			_json_chat.call("start_worker")
	if schema != "" and _json_chat.has_method("set_sampler_preset_constrain_with_json_schema"):
		_json_chat.call("set_sampler_preset_constrain_with_json_schema", schema)
	elif _json_chat.has_method("set_sampler_preset_json"):
		_json_chat.call("set_sampler_preset_json")
	# Stateless per call, for the same reason turns are: every prompt carries its
	# own context, so an accumulating conversation is pure cost.
	if _json_chat.has_method("reset_context"):
		_json_chat.call("reset_context")
	_json_chat.call("ask" if _json_chat.has_method("ask") else "say", prompt)
	return await _json_chat.response_finished


## Stop mid-sentence. NobodyWhoChat exposes `stop_generation`; the player pressing
## cancel used to set a flag that the SSE read loop polled, which does not exist
## any more now the turn runs in this process.
func stop() -> void:
	if _chat != null and is_instance_valid(_chat) and _chat.has_method("stop_generation"):
		_chat.call("stop_generation")
	if _busy:
		_busy = false
		Api.sse_done.emit(false)


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
	# Each turn is STATELESS, and deliberately so.
	#
	# NobodyWhoChat keeps a conversation, but this game's context does not live
	# in one: `Composer.envelope()` rebuilds the whole situation every turn —
	# sheet, scene, clock, inventory, cast, quests, recalled beats — and
	# Chronicle owns long-term memory. Letting the chat ALSO accumulate history
	# means sending all of that twice and growing without bound.
	#
	# Measured: turn 2 cost MORE than turn 1 (51.7s against 41.6s) on a warm
	# model, which is backwards, because the second envelope pushed the
	# conversation past the 4096-token context and it began re-processing.
	# Clearing first makes every turn cost what the first one did.
	if _chat.has_method("reset_context"):
		_chat.call("reset_context")
	# `ask` is the current name; `say` is deprecated upstream and warns on every
	# turn. Fall back for older builds of the extension rather than requiring one.
	_chat.call("ask" if _chat.has_method("ask") else "say", message)
	return true

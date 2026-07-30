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

## Context for a NARRATOR turn. The backend asked Ollama for `num_ctx=8192` and
## this is the same number.
const CTX := 8192

## Context for a STRUCTURED turn, which needs more, because the whole answer is
## one message with nothing to evict. The Worldsmith's world-core call died with
##
##   Error during context shift: Context shift failed: not enough messages to shift
##   help: The message fits in the context but there is not enough room left for
##         the response. Either shorten the message or increase n_ctx.
##
## after 98 s — roughly 1400 tokens at the rate this box generates, which is a
## perfectly ordinary answer, not a runaway. A chat context sized for a
## conversation is simply too small for one object that carries a world in it.
const JSON_CTX := 16384

## How long one structured answer may take before it is written off. Generous
## because a cold world-core call is genuinely slow; the point is only that a
## wedged worker must not take the session with it.
const GEN_DEADLINE := 180.0

var _model: Node = null
var _chat: Node = null
var _busy := false
## A SECOND chat over the same model, for structured answers.
##
## The sampler is per-chat-node, so constraining the narrator's node to JSON
## would silently turn prose into objects. Sharing `_model` means this costs a
## context, not another 4.6 GB of weights.
var _json_chat: Node = null
## One JSON node, so one caller at a time. Chronicle fires codex and quests off
## the same turn and the World Compiler runs its own stages; two `ask()` calls
## on one chat node interleave into a single garbled answer that still parses.
var _json_busy := false
## Which call is in flight. Only used to tell a live deadline from a stale one.
var _json_gen := 0
## Whether the shared node currently holds the prose sampler. The two configs
## replace each other, so whoever runs next has to put its own back.
var _json_prose := false
signal _json_free
## Emitted with the answer on success and with "" on failure — see the note where
## it is wired up.
signal _json_done(text: String)


## The first CHAT GGUF in the models folder, or "" if there is none.
##
## Skips the embedding model, which lives in the same folder (LocalMemory picks
## it out of here by the same hints). `DirAccess.get_files()` order is whatever
## the filesystem hands back — today "llama..." happens to sort before
## "nomic...", which is luck, not a guarantee. Getting this wrong does not fail
## loudly: an 80 MB encoder loaded as the narrator answers, badly, forever. And
## since the HTTP narrator is gone there is nothing behind it to catch that.
func model_file() -> String:
	var d := DirAccess.open(MODEL_DIR)
	if d == null:
		return ""
	for f in d.get_files():
		var lf := f.to_lower()
		if not lf.ends_with(".gguf"):
			continue
		var is_encoder := false
		for h in LocalMemory.EMBED_HINTS:
			if lf.find(h) >= 0:
				is_encoder = true
				break
		if not is_encoder:
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
	_chat.set("context_length", CTX)
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
## BUT A SCHEMA IS NOT FREE, and the cost is invisible until it is enormous.
## `set_sampler_preset_*` REPLACES the whole sampler config — measured by reading
## the config back out of the worker log — so a grammar-constrained call runs with
## no top-k, no top-p, no temperature and no repetition penalty. Pure sampling
## from the raw distribution. NobodyWhoSamplerBuilder has no grammar step, so
## there is no supported way to have both.
##
## That is survivable while the model is confident and catastrophic when it is
## not. A three-key schema wrote a good tagline in 2559 ms; the six-key world
## schema, one field of which is an array of 5-7 objects, produced grammar-valid
## WORD SALAD at 84 tok/s — "births freely Attendance ensemble span mind plague".
##
## So: use a schema to EXTRACT, never to INVENT. `prose()` below is the other
## half. See docs/LocalLLM-Tuning.md.
##
## Returns "" when unusable.
func complete_json(prompt: String, schema := "") -> String:
	if not available():
		return ""
	if _model == null and not _ensure_nodes(""):
		return ""
	# Take the lock BEFORE touching the node. A caller that waited here may have
	# been waiting on a call whose deadline expired and freed the node out from
	# under it, so the node has to be checked on this side of the wait.
	while _json_busy:
		await _json_free
	_json_busy = true
	_json_gen += 1
	var gen := _json_gen
	if _json_chat == null or not is_instance_valid(_json_chat):
		_json_chat = ClassDB.instantiate(CLASS_CHAT)
		if _json_chat == null:
			_deliver("")
			return ""
		_json_chat.set("model_node", _model)
		_json_chat.set("context_length", JSON_CTX)
		_json_prose = false
		add_child(_json_chat)
		_json_chat.connect("response_finished", func(t: String): _deliver(t))
		if _json_chat.has_signal("worker_failed"):
			_json_chat.connect("worker_failed", func(why: String):
				push_warning("LocalGM: JSON generation failed: %s" % why)
				_deliver(""))
		if _json_chat.has_method("start_worker"):
			_json_chat.call("start_worker")
	# The sampler is set EVERY call, not once, because `prose()` and this share the
	# node and each clobbers the other's config.
	if schema != "" and _json_chat.has_method("set_sampler_preset_constrain_with_json_schema"):
		_json_chat.call("set_sampler_preset_constrain_with_json_schema", schema)
		_json_prose = false
	elif _json_chat.has_method("set_sampler_preset_json"):
		_json_chat.call("set_sampler_preset_json")
		_json_prose = false
	# Stateless per call, for the same reason turns are: every prompt carries its
	# own context, so an accumulating conversation is pure cost.
	if _json_chat.has_method("reset_context"):
		_json_chat.call("reset_context")
	_json_chat.call("ask" if _json_chat.has_method("ask") else "say", prompt)
	# The timer always fires, answer or not, so it carries the id of the call it
	# was armed for — otherwise a deadline left over from a call that finished in
	# time would go off in the middle of a perfectly healthy later one.
	get_tree().create_timer(GEN_DEADLINE).timeout.connect(_on_deadline.bind(gen))
	return await _json_done


## Free prose from the local model, with a sampler that has actually been tuned.
##
## This is the FIRST half of every generative call: think here, then hand the
## result to `complete_json` with a schema to serialise it. Doing both at once is
## what the literature calls premature serialization, and an 8B model is squarely
## in the class that pays for it — measured here as word salad, not as a subtle
## quality dip.
##
## The numbers are the usual llama.cpp defaults rather than anything clever: top-k
## 40, top-p 0.95, temperature 0.7, and a mild repetition penalty over the last 64
## tokens. They exist because the grammar path silently has NONE of them.
const PROSE := {"top_k": 40, "top_p": 0.95, "temp": 0.7, "pen_last": 64, "pen_repeat": 1.1}

func prose(prompt: String) -> String:
	if not available():
		return ""
	if _model == null and not _ensure_nodes(""):
		return ""
	while _json_busy:
		await _json_free
	_json_busy = true
	_json_gen += 1
	var gen := _json_gen
	if _json_chat == null or not is_instance_valid(_json_chat):
		_deliver("")
		return await complete_json(prompt)   # rebuilds the node, then this retries
	if not _json_prose:
		var b: Object = ClassDB.instantiate("NobodyWhoSamplerBuilder")
		if b != null and b.has_method("top_k"):
			_json_chat.call("set_sampler_config", b.call("top_k", PROSE["top_k"]) \
				.call("top_p", PROSE["top_p"], 1).call("temperature", PROSE["temp"]) \
				.call("penalties", PROSE["pen_last"], PROSE["pen_repeat"], 0.0, 0.0) \
				.call("dist"))
			_json_prose = true
	if _json_chat.has_method("reset_context"):
		_json_chat.call("reset_context")
	_json_chat.call("ask" if _json_chat.has_method("ask") else "say", prompt)
	get_tree().create_timer(GEN_DEADLINE).timeout.connect(_on_deadline.bind(gen))
	return await _json_done


## The single exit from a JSON call. Everything that can end one — the answer,
## `worker_failed`, the deadline — comes through here, so the lock is released
## exactly once and by whoever got there first.
func _deliver(text: String) -> void:
	if not _json_busy:
		return   # a late answer from a call that already gave up; drop it
	_json_busy = false
	_json_done.emit(text)
	_json_free.emit()


## A generation that overran its context did not fail — it HUNG. No
## `response_finished`, no `worker_failed`, no error the extension surfaced;
## the worker simply never came back, and a probe with a deliberately tiny
## context could not even be shut down afterwards. So a deadline is not belt and
## braces here, it is the only thing that notices.
##
## The node is thrown away rather than reused: a worker that missed its deadline
## is in a state this code cannot reason about, and freeing it also disconnects
## its signals, which is what stops a late answer from being handed to whichever
## call happens to be waiting next.
func _on_deadline(gen: int) -> void:
	if gen != _json_gen or not _json_busy:
		return
	push_warning("LocalGM: JSON generation exceeded %ds — discarding the worker" % int(GEN_DEADLINE))
	if _json_chat != null and is_instance_valid(_json_chat):
		_json_chat.queue_free()
	_json_chat = null
	_deliver("")


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

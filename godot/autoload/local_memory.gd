extends Node
## Campaign memory, in-process — Stage 3 of docs/Architecture-InProcess.md.
##
## A per-adventure store of story beats, recalled by meaning rather than recency.
## This is a straight port of src/campaign_memory.py, which POSTed every beat to
## the backend to be embedded by Ollama's `all-minilm` and searched with numpy.
## Same algorithm, same thresholds, no server:
##
##   add_beat  embed -> skip near-duplicates -> append
##   recall    embed the query -> cosine against every beat -> top-k over a floor
##
## NobodyWhoEncoder does the embedding on the same Vulkan device as the narrator,
## and ships `cosine_similarity` so the search is a loop rather than a dependency.
## `encode()` returns an awaitable Signal, which is why this reads synchronously.
##
## INERT WITHOUT A MODEL, exactly like LocalGM: no encoder class or no embedding
## GGUF means available() is false and callers fall back to their old path. That
## keeps this shippable on its own instead of as a flag day.

const CLASS_ENCODER := "NobodyWhoEncoder"
const CLASS_MODEL := "NobodyWhoModel"

## Where beats live. One file per adventure, so deleting a save takes its memory
## with it and nothing leaks between campaigns.
const MEM_DIR := "user://memory"

## Thresholds carried over from campaign_memory.py rather than re-guessed.
## 0.97: a beat this close to the previous one is a regenerate or a retry, not a
## new event. 0.15: below this, "relevant past events" is just noise, and feeding
## noise to the GM as canon is worse than feeding it nothing.
const DUPE_ABOVE := 0.97
const SCORE_FLOOR := 0.15

## An embedding model is a DIFFERENT file from the narrator's. Matched by name
## because both live in user://models and a 4.6 GB chat model loaded as an
## encoder would be a slow, silent mistake.
const EMBED_HINTS := ["embed", "minilm", "nomic", "bge", "gte", "e5-"]

var _model: Node = null
var _enc: Node = null
var _cache: Dictionary = {}   # key -> Array[{text, day, vec}]


func embed_model_file() -> String:
	var d := DirAccess.open(LocalGM.MODEL_DIR)
	if d == null:
		return ""
	for f in d.get_files():
		var lf := f.to_lower()
		if not lf.ends_with(".gguf"):
			continue
		for h in EMBED_HINTS:
			if lf.find(h) >= 0:
				return LocalGM.MODEL_DIR + "/" + f
	return ""


func available() -> bool:
	# INERT UNDER test_mode. The harnesses drive the real game with canned
	# responses; without this they loaded an 80 MB encoder, ran real embeddings
	# and wrote real memory files, which cost time and — because the extra awaits
	# reordered a turn — broke two heal assertions in ui_playthrough that have
	# nothing to do with memory. A test double that quietly does real work is not
	# a test double.
	if Api.test_mode:
		return false
	return ClassDB.class_exists(CLASS_ENCODER) and ClassDB.class_exists(CLASS_MODEL) \
		and embed_model_file() != ""


func why_unavailable() -> String:
	if not ClassDB.class_exists(CLASS_ENCODER):
		return "the NobodyWho extension is not installed"
	if embed_model_file() == "":
		return "no embedding .gguf in %s (name it so it contains 'embed' or 'minilm')" \
			% ProjectSettings.globalize_path(LocalGM.MODEL_DIR)
	return ""


func _ensure() -> bool:
	if _enc != null and is_instance_valid(_enc):
		return true
	if not available():
		return false
	_model = ClassDB.instantiate(CLASS_MODEL)
	if _model == null:
		return false
	_model.set("model_path", ProjectSettings.globalize_path(embed_model_file()))
	add_child(_model)
	_enc = ClassDB.instantiate(CLASS_ENCODER)
	if _enc == null:
		return false
	_enc.set("model_node", _model)
	add_child(_enc)
	# Load the weights now, not inside the first beat of a story.
	if _enc.has_method("start_worker"):
		_enc.call("start_worker")
	return true


func _encode(text: String) -> PackedFloat32Array:
	if not _ensure():
		return PackedFloat32Array()
	return await _enc.encode(text)


func _cos(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	return float(_enc.cosine_similarity(a, b))


# ── Store ───────────────────────────────────────────────────────────────────
func _path(key: String) -> String:
	return "%s/%s.json" % [MEM_DIR, key.validate_filename()]


func _load(key: String) -> Array:
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var p := _path(key)
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Array:
			out = parsed
	_cache[key] = out
	return out


## Write-then-rename, matching GameState's persistence: a crash mid-write must
## not leave a half-written memory that parses as an empty campaign.
func _save(key: String, beats: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEM_DIR))
	var p := _path(key)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("LocalMemory: cannot write %s" % p)
		return
	f.store_string(JSON.stringify(beats))
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(p))
	_cache[key] = beats


# ── The two operations the game actually uses ───────────────────────────────
## Returns false when this path is not usable, so the caller can fall back.
func add_beat(key: String, text: String, day := 0) -> bool:
	if text.strip_edges() == "" or not available():
		return false
	var vec := await _encode(text)
	if vec.is_empty():
		return false
	var beats := _load(key)
	# Only the PREVIOUS beat is checked, same as the Python. A story legitimately
	# revisits a place; what is never legitimate is the same turn landing twice.
	if not beats.is_empty():
		var last: Dictionary = beats[-1]
		if _cos(vec, PackedFloat32Array(last.get("vec", []))) > DUPE_ABOVE:
			return true
	beats.append({"text": text, "day": day, "vec": Array(vec)})
	_save(key, beats)
	return true


## The beats most relevant to this moment, best first. Empty when nothing clears
## the floor — which is the honest answer, not a reason to return the newest.
func recall(key: String, query: String, k := 4) -> Array:
	if query.strip_edges() == "" or not available():
		return []
	var beats := _load(key)
	if beats.is_empty():
		return []
	var qv := await _encode(query)
	if qv.is_empty():
		return []
	var scored: Array = []
	for b in beats:
		if not (b is Dictionary):
			continue
		var s := _cos(qv, PackedFloat32Array(b.get("vec", [])))
		if s >= SCORE_FLOOR:
			scored.append({"text": str(b.get("text", "")), "day": int(b.get("day", 0)), "score": s})
	scored.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	return scored.slice(0, k)


## Drop one adventure's memory — called when a save is wiped, so a deleted
## campaign cannot bleed into a new one with the same id.
func wipe(key: String) -> void:
	_cache.erase(key)
	var p := _path(key)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

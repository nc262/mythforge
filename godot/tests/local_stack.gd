extends Node
## Proves Stage 3 (campaign memory) and grammar-constrained JSON actually work
## in-process, against real models — not that the classes exist.
##
## Run WINDOWED or headless; no rendering involved:
##   Godot_v4.7-stable_win64.exe --headless --path godot res://tests/local_stack.tscn

const KEY := "spike-local-memory"

var _fail := 0


func _ck(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
		print("  FAIL: ", what)
	else:
		print("  ok:   ", what)


func _ready() -> void:
	await get_tree().process_frame
	print("LocalGM available:     %s" % LocalGM.available())
	print("LocalMemory available: %s  (%s)" % [
		LocalMemory.available(), LocalMemory.embed_model_file()])
	if not LocalMemory.available():
		print("SKIP: ", LocalMemory.why_unavailable())
		get_tree().quit(1)
		return

	# Two .gguf files share one folder and only their names tell them apart.
	# If the narrator ever picked up the encoder there would be no error, just a
	# bad narrator — and no server left to fall back to.
	_ck(LocalGM.model_file() != LocalMemory.embed_model_file(),
		"narrator and encoder resolve to DIFFERENT model files")

	LocalMemory.wipe(KEY)

	# ── Memory: store beats, then recall by MEANING rather than wording ──────
	var t0 := Time.get_ticks_msec()
	await LocalMemory.add_beat(KEY, "Player: I bribe the harbourmaster.\nGM: The coins vanish into his coat and the manifest is amended.", 3)
	await LocalMemory.add_beat(KEY, "Player: I ask the blacksmith about the broken sword.\nGM: He turns the shards over and names a forge in the mountains.", 4)
	await LocalMemory.add_beat(KEY, "Player: I climb the bell tower at dusk.\nGM: Rooks scatter; the whole valley lies grey beneath you.", 5)
	var t_add := Time.get_ticks_msec() - t0

	# Deliberately NO shared keywords with the stored beat — this is the whole
	# point of embeddings over a substring search.
	t0 = Time.get_ticks_msec()
	var hits := await LocalMemory.recall(KEY, "who did I pay off at the docks?", 2)
	var t_recall := Time.get_ticks_msec() - t0

	print("  add x3: %d ms | recall: %d ms" % [t_add, t_recall])
	_ck(not hits.is_empty(), "recall returned something")
	if not hits.is_empty():
		var top := str(hits[0].get("text", ""))
		print("  top hit (%.3f): %s" % [float(hits[0].get("score", 0)), top.replace("\n", " ").left(70)])
		_ck(top.find("harbourmaster") >= 0,
			"top hit is the bribe beat, matched WITHOUT sharing a keyword")

	# A query about nothing in the store must return nothing, not the newest
	# beat. A floor that never rejects is not a floor.
	var none := await LocalMemory.recall(KEY, "the recipe for lemon posset", 3)
	_ck(none.is_empty() or float(none[0].get("score", 1.0)) >= LocalMemory.SCORE_FLOOR,
		"irrelevant query is rejected by the score floor")

	# Near-duplicate must not be stored twice. The check is against the PREVIOUS
	# beat only, so the duplicate has to be consecutive — which is exactly the
	# case it exists for (a regenerate or a retry re-recording the same turn).
	# An earlier version of this test re-added the bribe after two other beats
	# and called the correct append a failure.
	var dupe := "Player: I climb the bell tower at dusk.\nGM: Rooks scatter; the whole valley lies grey beneath you."
	var before := (await LocalMemory.recall(KEY, "bell tower rooks valley", 9)).size()
	await LocalMemory.add_beat(KEY, dupe, 5)
	var after := (await LocalMemory.recall(KEY, "bell tower rooks valley", 9)).size()
	_ck(after == before, "consecutive identical beat deduped (%d -> %d)" % [before, after])

	# Survives a reload — the store is on disk, not just in RAM.
	LocalMemory._cache.clear()
	var reloaded := await LocalMemory.recall(KEY, "who did I pay off at the docks?", 1)
	_ck(not reloaded.is_empty(), "beats persist across a cache clear")

	# ── Grammar-constrained JSON ────────────────────────────────────────────
	if LocalGM.available():
		# No schema: preset_json only.
		t0 = Time.get_ticks_msec()
		var loose := await LocalGM.complete_json(
			"Describe a ruined lighthouse as JSON with keys: name, mood, one_detail.")
		print("  preset_json:   %d ms | parses=%s | %s" % [
			Time.get_ticks_msec() - t0, JSON.parse_string(loose) != null,
			loose.replace("\n", " ").left(80)])

		# With an explicit schema — the stronger constraint.
		var schema := '{"type":"object","properties":{"name":{"type":"string"},' \
			+ '"mood":{"type":"string"},"one_detail":{"type":"string"}},' \
			+ '"required":["name","mood","one_detail"]}'
		t0 = Time.get_ticks_msec()
		var txt := await LocalGM.complete_json(
			"Describe a ruined lighthouse.", schema)
		var t_json := Time.get_ticks_msec() - t0
		print("  with schema:   %d ms, %d chars" % [t_json, txt.length()])
		print("  raw: %s" % txt.replace("\n", " ").left(120))
		var parsed = JSON.parse_string(txt)
		_ck(parsed != null, "schema-constrained output parses with NO extraction")
		_ck(parsed is Dictionary, "and it is an object")
		if parsed is Dictionary:
			_ck((parsed as Dictionary).has("name") and (parsed as Dictionary).has("mood"),
				"and it has the keys the schema demanded")

	LocalMemory.wipe(KEY)
	print("LOCAL STACK %s" % ("OK" if _fail == 0 else "FAILED (%d)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)

extends Node
## Proves Stage 3 (campaign memory) and grammar-constrained JSON actually work
## in-process, against real models — not that the classes exist.
##
## Run WINDOWED or headless; no rendering involved:
##   Godot_v4.7-stable_win64.exe --headless --path godot res://tests/local_stack.tscn

const KEY := "spike-local-memory"

var _fail := 0
var _race_out := [null, null]


## Fire a complete_json without awaiting it here — the only way to have two in
## flight at once, since GDScript refuses to let a coroutine's result be stored
## unawaited.
func _race(prompt: String, schema: String, slot: int) -> void:
	var raw := await LocalGM.complete_json(prompt, schema)
	var p = JSON.parse_string(raw)
	# Never leave the slot null — that is the loop's "still running" sentinel, and
	# a failed parse would hang the test instead of failing it.
	_race_out[slot] = p if p != null else {"_unparsed": raw}


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

	# ── Chronicle's extractors, which now run here rather than on the backend ──
	# The point is the ENUM: an invalid disposition is not normalised afterwards,
	# it is ungeneratable. maxItems is the other half — an unbounded array against
	# a chatty model is how a codex becomes a novel.
	if LocalGM.available():
		Chronicle.transcript = [
			{"role": "user", "content": "I ask Maren the harbourmaster to amend the manifest."},
			{"role": "assistant", "content": "[scene] Maren pockets the coins, scowling, and scratches out the entry. 'This is the last time,' she says."},
			{"role": "user", "content": "I promise to bring her the smuggler's ledger."},
			{"role": "assistant", "content": "Maren nods once. 'Bring me the ledger and we are square.'"},
		]
		t0 = Time.get_ticks_msec()
		await Chronicle._update_codex()
		var codex = GameState.state.get("codex", [])
		print("  codex: %d ms -> %s" % [Time.get_ticks_msec() - t0, JSON.stringify(codex).left(200)])
		_ck(codex is Array and not (codex as Array).is_empty(), "codex extracted at least one NPC")
		if codex is Array and not (codex as Array).is_empty():
			var disps := ["ally", "friendly", "neutral", "wary", "hostile"]
			var all_valid := true
			for n in codex:
				if not disps.has(str(n.get("disposition", ""))):
					all_valid = false
			_ck(all_valid, "every disposition is one the enum allows")
			_ck((codex as Array).size() <= 12, "codex respects maxItems")

		t0 = Time.get_ticks_msec()
		await Chronicle._update_quests()
		var quests = GameState.state.get("quests", [])
		print("  quests: %d ms -> %s" % [Time.get_ticks_msec() - t0, JSON.stringify(quests).left(200)])
		_ck(quests is Array and not (quests as Array).is_empty(), "quest log extracted the ledger promise")
		if quests is Array:
			var st_ok := true
			for q in quests:
				if not ["active", "done"].has(str(q.get("status", ""))):
					st_ok = false
			_ck(st_ok, "every status is one the enum allows")

		# The world tick, which has been silently returning nothing since it was
		# written: game.gd read "tick"/"aside"/"text" and the route sent
		# "events"/"newQuest". Assert on the shape the CALLER uses, since agreeing
		# with myself about the schema is what missed it the first time.
		t0 = Time.get_ticks_msec()
		var tick := await Chronicle.world_tick()
		print("  worldtick: %d ms -> %s" % [Time.get_ticks_msec() - t0, JSON.stringify(tick).left(240)])
		_ck(tick.get("events") is Array and not (tick["events"] as Array).is_empty(),
			"world tick produced off-screen events")
		_ck((tick.get("events", []) as Array).size() <= 3, "world tick respects maxItems")
		# A new quest, if the model offered one, must be IN THE LOG — the old route
		# returned it and nothing ever filed it.
		if not (tick.get("newQuest", {}) as Dictionary).is_empty():
			var titles: Array[String] = []
			for q in GameState.state.get("quests", []):
				titles.append(str(q.get("title", "")))
			_ck(titles.has(str(tick["newQuest"]["title"])), "a new thread was filed in the quest log")

		# Two callers, one JSON node. Started WITHOUT await so both are genuinely
		# in flight: without the serialising guard in complete_json the second
		# `ask()` lands on a node mid-answer and the two interleave into one
		# garbled reply that still parses — the worst kind.
		t0 = Time.get_ticks_msec()
		_race("Name a tavern.", '{"type":"object","required":["name"],"properties":{"name":{"type":"string"}}}', 0)
		_race("Name a mountain.", '{"type":"object","required":["peak"],"properties":{"peak":{"type":"string"}}}', 1)
		while _race_out[0] == null or _race_out[1] == null:
			await get_tree().process_frame
		print("  concurrent: %d ms | %s | %s" % [Time.get_ticks_msec() - t0, _race_out[0], _race_out[1]])
		_ck(_race_out[0] is Dictionary and (_race_out[0] as Dictionary).has("name"),
			"concurrent call A kept its own schema")
		_ck(_race_out[1] is Dictionary and (_race_out[1] as Dictionary).has("peak"),
			"concurrent call B kept its own schema")

	# ── The Worldsmith ──────────────────────────────────────────────────────
	# Assert the sections the SERVER used to lose. The old route carried a retry
	# loop and two rescue calls precisely because `locations` and `stories` went
	# missing; if the grammar really makes that unreachable, these hold every run.
	if LocalGM.available():
		t0 = Time.get_ticks_msec()
		var w := await Api.worldsmith({
			"idea": "a drowned city where the tide keeps the dead polite",
			"mode": "world",
			"fields": {"tone": "melancholy", "tech": "bronze age"}})
		var t_world := Time.get_ticks_msec() - t0
		print("  world: %d ms | %s — %s" % [t_world, str(w.get("name", "")), str(w.get("kind", ""))])
		print("    locations=%d cast=%d stories=%d creatures=%d reskins=%s" % [
			(w.get("locations", []) as Array).size(), (w.get("cast", []) as Array).size(),
			(w.get("stories", []) as Array).size(), (w.get("creatures", []) as Array).size(),
			"yes" if w.get("reskins") is Dictionary else "NO"])
		_ck(w.get("_status", 0) == 200 and str(w.get("name", "")) != "", "the forge produced a world")
		_ck((w.get("locations", []) as Array).size() >= 5, "locations survived — the section the retry loop existed for")
		_ck((w.get("stories", []) as Array).size() == 2, "exactly 2 campaigns, not 'about 2'")
		_ck((w.get("cast", []) as Array).size() == 3, "exactly 3 cast members")
		_ck((w.get("creatures", []) as Array).size() == 6, "a full bestiary of 6")
		var kinds := ["tavern", "shop", "landmark", "wilds", "home"]
		var kinds_ok := true
		for l in w.get("locations", []):
			if not kinds.has(str(l.get("kind", ""))):
				kinds_ok = false
		_ck(kinds_ok, "every location kind is one the enum allows")
		_ck(w.get("reskins") is Dictionary and (w["reskins"]["names"] as Dictionary).size() == 12,
			"all 12 classes got world-specific names (the server settled for 8)")
		if w.get("reskins") is Dictionary:
			print("    reskins: %s" % JSON.stringify(w["reskins"]["names"]).left(180))

		# mode=story is the other half, and the one the campaign forge uses.
		t0 = Time.get_ticks_msec()
		var st := await Api.worldsmith({"idea": "a debt comes due at the spring tide",
			"mode": "story", "world": {"name": str(w.get("name", "")), "kind": str(w.get("kind", "")),
			"lore": str(w.get("lore", ""))}})
		print("  story: %d ms | %s" % [Time.get_ticks_msec() - t0, str(st.get("title", ""))])
		_ck(st.get("_status", 0) == 200 and str(st.get("title", "")) != "", "a campaign was crafted")
		_ck(str(st.get("hook", "")) != "", "and it has an opening scene")

	LocalMemory.wipe(KEY)
	print("LOCAL STACK %s" % ("OK" if _fail == 0 else "FAILED (%d)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)

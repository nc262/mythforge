extends Node
## CAN THE GM PUT A POINT OF INTEREST INSIDE A TOWN? Drives the real path rather
## than reasoning about it.
##
##   godot --headless --path godot res://tests/site_probe.tscn
##
## The GM's geography power is `[[place]]` -> `GameState.add_place`, which the
## engine vetoes by scope. This asks the question one level down: when the GM
## adds a place, does the TOWN the player is standing in change at all?
##
## It asserts nothing about the answer. It PRINTS the answer, because the point
## is to find out, and a probe that assumes its result is a probe that will
## agree with whatever it was written to believe.

var _lines: Array = []


func _ready() -> void:
	await get_tree().process_frame
	print("SITE-PROBE start")
	var wid := "saltmarsh"
	GameState.character = {"id": "dm-site", "name": "Probe", "world_id": wid, "level": 20}
	# A settlement to stand in, and the plan it generates.
	# THE REAL KIND, carried through everywhere. `add_site` builds the plan with
	# the place's own kind, and `_size_of` branches on it — so a probe that
	# snapshots with "settlement" while the engine validates against "tavern" is
	# comparing two different towns with different ward counts.
	var town := ""
	var town_kind := ""
	for p in GameState.places():
		if p is Dictionary and LocalMap.TOWN_KINDS.has(str(p.get("kind", ""))):
			town = str(p.get("name", ""))
			town_kind = str(p.get("kind", ""))
			break
	if town == "":
		print("SITE-PROBE FAILED: no settled place in %s" % wid)
		get_tree().quit(1)
		return

	var before := _snapshot(wid, town, town_kind)
	print("  town '%s' before: %d nodes -> %s" % [town, before.size(), ", ".join(before)])
	var places_before := GameState.places().size()

	# ── THE GM ACTS ──────────────────────────────────────────────────────────
	# Exactly what `_gm_makes_place` does for [[place name=... kind=shop ...]].
	var why := GameState.add_place({
		"name": "The Drowned Bell",
		"kind": "shop",
		"lore": "A chandlery that buys what the tide brings in, no questions asked.",
		"shop": "rope, oil, salvage",
		"region": "",
		"scope": "local",
	})
	print("  add_place verdict: %s" % ("ACCEPTED" if why == "" else why))

	var places_after := GameState.places().size()
	print("  world chart: %d places -> %d" % [places_before, places_after])


	# ── THE VERDICT ──────────────────────────────────────────────────────────
	var world_changed := places_after > places_before
	print("")
	print("  WORLD MAP updated : %s" % ("yes" if world_changed else "NO"))

	# ── NOW THE TIER BELOW: a site INSIDE the town ───────────────────────────
	var lm := LocalMap.for_place(wid, town, town_kind)
	print("  %s has %d wards, sizes tier %d, walled=%s" % [
		town, lm.wards.size(), lm.size_tier, lm.walled])
	for i in lm.wards.size():
		print("    ward %d  %-22s wealth=%d law=%d" % [
			i, lm.ward_name[i], lm.ward_wealth[i], lm.ward_law[i]])

	# Every refusal the engine can give, so the messages themselves are tested.
	for bad in [
		{"name": "X", "kind": "smith", "ward": 0, "settlement": "Nowhere-at-All"},
		{"name": "X", "kind": "starship-dealer", "ward": 0, "settlement": town},
		{"name": "X", "kind": "smith", "ward": 99, "settlement": town},
	]:
		print("  refused: %s" % GameState.add_site(bad))

	# A TRADE THE TOWN IS BIG ENOUGH FOR. A fence arrives at city size, and the
	# engine now says so rather than quietly standing one in a village — which is
	# what this line used to ask for, and what turned this probe red when the size
	# gate landed.
	var lm0 := LocalMap.for_place(wid, town, town_kind)
	var legal := str(WorldSkin.trades_at(lm0.size_tier)[0])
	print("  refused (too small): %s" % GameState.add_site({
		"name": "The Guild That Cannot Be", "kind": "guild", "ward": 0, "settlement": town}))
	var ok := GameState.add_site({
		"name": "The Drowned Bell", "kind": legal, "ward": 2,
		"settlement": town, "lore": "Buys what the tide brings in.",
	})
	print("  add_site verdict: %s" % ("ACCEPTED" if ok == "" else ok))
	var after2 := _snapshot(wid, town, town_kind)
	print("  town after site  : %d nodes -> %s" % [after2.size(), ", ".join(after2)])
	var town_changed := after2 != before
	print("")
	print("  TOWN MAP updated  : %s" % ("yes" if town_changed else "NO"))
	if not town_changed:
		print("SITE-PROBE FAILED: the GM added a site and the town did not change")
		get_tree().quit(1)
		return
	if not after2.has("The Drowned Bell"):
		print("SITE-PROBE FAILED: the site is not among the town's named places")
		get_tree().quit(1)
		return
	# ── THE TOWN'S LIVE PROBLEM ──────────────────────────────────────────────
	print("")
	if not _trouble_lifecycle(town, town_kind):
		get_tree().quit(1)
		return
	if not _ask_after(town, town_kind):
		get_tree().quit(1)
		return
	print("SITE-PROBE OK")
	get_tree().quit(0)


## AT-19 — THE PLAYER ASKS FOR SOMETHING THAT IS NOT ON THE MAP. The GM decides
## whether the town has it; the engine decides whether that answer is legal and
## puts it on the plan. Only the engine half can be checked offline, which is the
## half that matters: a model proposing a Guildhall in a hamlet must be refused
## with the size named, not quietly obeyed.
func _ask_after(town: String, town_kind: String) -> bool:
	var lm := LocalMap.for_place(GameState.world_id(), town, town_kind)
	var tier := lm.size_tier
	var nothing := GameState.answer_ask(town, "an apothecary", {})
	if bool(nothing.get("found", true)) or str(nothing.get("line", "")).find("nowhere") < 0:
		return _bad("an ask the model could not answer did not fail quietly: %s" % str(nothing))
	var refused := GameState.answer_ask(town, "a temple", {"here": false, "answer": "No god keeps a house here."})
	if bool(refused.get("found", true)) or str(refused.get("line", "")) != "No god keeps a house here.":
		return _bad("a GM saying no did not reach the player: %s" % str(refused))
	# A trade the size of the place cannot carry is refused WITH THE SIZE.
	var too_big := ""
	for k in WorldSkin.TRADE_KEYS:
		if not WorldSkin.trades_at(tier).has(k):
			too_big = k
			break
	if too_big != "":
		var over := GameState.answer_ask(town, "a %s" % too_big,
			{"here": true, "kind": too_big, "name": "The Overreach", "ward": 0, "answer": "Aye, just there."})
		if bool(over.get("found", true)) or str(over.get("line", "")).find("too small") < 0:
			return _bad("a %s was allowed in a %s: %s" % [too_big, GameState.SETTLEMENT_SIZES[tier], str(over)])
	# A ward that does not exist is refused with the range, as [[site]] is.
	var nowhere := GameState.answer_ask(town, "a stable", {"here": true, "kind": "home", "name": "The Blind Stable", "ward": 99})
	if bool(nowhere.get("found", true)) or str(nowhere.get("line", "")).find("wards 0-") < 0:
		return _bad("a site proposed for a ward that does not exist was accepted: %s" % str(nowhere))
	# And a legal proposal lands on the plan.
	var kind_ok := str(WorldSkin.trades_at(tier)[0]) if not WorldSkin.trades_at(tier).is_empty() else "landmark"
	var got := GameState.answer_ask(town, "somewhere to sell this quietly",
		{"here": true, "kind": kind_ok, "name": "The Quiet Counter", "ward": 1,
		"lore": "A shutter that opens for the right knock.", "answer": "Off the alley, mind the dog."})
	if not bool(got.get("found", false)):
		return _bad("a legal answer was refused: %s" % str(got))
	LocalMap.forget("%s|%s" % [GameState.world_id(), town])
	var after := LocalMap.for_place(GameState.world_id(), town, town_kind)
	if not after.nodes.any(func(n): return str(n["name"]) == "The Quiet Counter"):
		return _bad("the asked-after place is not on the town map")
	if after.brief().find("The Quiet Counter") < 0:
		return _bad("the asked-after place is not in what the narrator is told")
	# Asking again for the same name is refused rather than duplicated.
	var twice := GameState.answer_ask(town, "the quiet counter",
		{"here": true, "kind": kind_ok, "name": "The Quiet Counter", "ward": 1})
	if bool(twice.get("found", true)):
		return _bad("the same place was added to the town twice")
	# ── A SIZE THE WORLD DECLARED, not one the generator rolled ──────────────
	# "the capital of the Reach" used to come out a hamlet: the tier was a dice
	# roll off the kind. What the chart says it is, it is.
	var sized := GameState.add_place({"name": "Probe City", "kind": "settlement",
		"size": "city", "region": "", "scope": "local", "lore": "a declared city"})
	if sized != "":
		return _bad("a place could not be chartered with a size: " + sized)
	LocalMap.forget("%s|Probe City" % GameState.world_id())
	var city := LocalMap.for_place(GameState.world_id(), "Probe City", "settlement")
	if city.size_tier != 3:
		return _bad("a place chartered as a city came out tier %d" % city.size_tier)
	if GameState.add_site({"name": "The Big Guild", "kind": "guild", "ward": 0, "settlement": "Probe City"}) != "":
		return _bad("a city is too small for a guild")
	print("  size: a place chartered as a city is a city on its own map, and carries what a city carries")
	# RUBBLE IS NOT AN ANSWER. A schema call runs with no sampler chain, and one
	# real reply in five came back carrying invented keys and a paragraph of noise.
	var junk := GameState.answer_ask(town, "a bank",
		{"here": true, "kind": "store", "name": "The Vault", "ward": 0, "wardnumberlabel": "0"})
	if bool(junk.get("found", true)):
		return _bad("an answer carrying keys nobody asked for was accepted: %s" % str(junk))
	# YES, WITHOUT SAYING WHAT THE THING IS, is not an answer either.
	var kindless := GameState.answer_ask(town, "a bathhouse",
		{"here": true, "name": "The Steam", "ward": 0, "answer": "Down the lane."})
	if bool(kindless.get("found", true)):
		return _bad("an answer with no kind was accepted: %s" % str(kindless))
	# The schema cuts at its ceiling, mid-word; the player never reads the stump.
	var cut := GameState.answer_ask(town, "a bakery", {"here": false,
		"answer": "The baker died last winter. Since then the ovens have been cold and nobody has taken them on, though the widow still keeps the ke"})
	if str(cut.get("line", "")).ends_with("ke") or str(cut.get("line", "")).find("died last winter") < 0:
		return _bad("a cut-off answer reached the player as a stump: %s" % str(cut.get("line", "")))
	print("  ask: a %s refuses what it is too small for, refuses a ward it has not got, and puts a legal answer on the plan" % GameState.SETTLEMENT_SIZES[tier])
	return true


func _bad(why: String) -> bool:
	print("SITE-PROBE FAILED: " + why)
	return false


func _stand(place: String) -> void:
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	wd["here"] = place
	GameState.state["world"] = wd


var _news: Array[String] = []


func _heard(line: String) -> void:
	_news.append(line)


## The NEWEST quest for this town's trouble — an earlier one, resolved, stays on the log.
func _quest_for(town: String) -> Dictionary:
	var found := {}
	for q in (GameState.state.get("quests") if GameState.state.get("quests") is Array else []):
		if q is Dictionary and str(q.get("trouble", "")).begins_with(town + "|"):
			found = q
	return found


func _fresh() -> void:
	var wd: Dictionary = GameState.state.get("world") if GameState.state.get("world") is Dictionary else {}
	wd.erase("trouble")
	GameState.state["world"] = wd
	GameState.state["quests"] = []
	_news.clear()


## A TROUBLE, END TO END, asserted rather than printed. This probe used to print
## its verdicts and was not in the gate, so "a town gets exactly one trouble,
## ever" sat in its own output as a refusal nobody was checking.
##   · validation, and a running trouble blocking a second while a spent one does not
##   · reach: town heard on arrival, region anywhere in it, secret never
##   · a known trouble is a QUEST: side matter, or bearing on a named thread
##   · clues: recorded, and the third exposes a secret without the first two saying it
##   · rolls against it move the clock; a day creeps it unless somebody WORKED it
##   · fallout the engine applies when it fills: trade, prices, road, law
##   · the model's quest rewrite cannot drop or re-status an engine quest
func _trouble_lifecycle(town: String, town_kind: String) -> bool:
	GameState.trouble_news.connect(_heard)
	var wid := GameState.world_id()
	var away := ""
	var kin := ""
	var reg := GameState.region_of_place(town)
	for p in GameState.places():
		if not (p is Dictionary) or str(p.get("name", "")) == town:
			continue
		if away == "":
			away = str(p["name"])
		if kin == "" and reg != "" and str(p.get("region", "")) == reg:
			kin = str(p["name"])
	_fresh()
	_stand(away)
	# ── validation ──
	for bad in [["Nowhere-at-All", "x", 6, "town", {}], [town, "", 6, "town", {}], [town, "x", 99, "town", {}],
			[town, "x", 6, "loud", {}], [town, "x", 6, "town", {"fallout": "fire"}]]:
		if GameState.set_trouble(str(bad[0]), str(bad[1]), int(bad[2]), str(bad[3]), bad[4]) == "":
			return _bad("a malformed trouble was accepted: %s" % str(bad))
	# ── a spent trouble blocks nothing; a resolved one is gone ──
	if GameState.set_trouble(town, "a", 4) != "":
		return _bad("a first trouble was refused")
	if GameState.set_trouble(town, "b", 4).find("already has a trouble running") < 0:
		return _bad("a RUNNING trouble let a second, different one replace it")
	GameState.tick_trouble(town, 4)
	var why := GameState.set_trouble(town, "c", 5)
	if why != "":
		return _bad("a trouble that came to a head still blocks the next one: " + why)
	if int(GameState.trouble_at(town).get("filled", -1)) != 0:
		return _bad("the new trouble inherited the old clock's segments")
	GameState.tick_trouble(town, 2)
	GameState.tick_trouble(town, -2)
	if not GameState.trouble_at(town).is_empty():
		return _bad("a trouble pushed back to nothing is still on the record")
	# ── reach=town: heard on arrival, and filed as a side quest ──
	_fresh()
	GameState.set_trouble(town, "press-gangs take men off the quay", 6, "town", {"fallout": "trade"})
	if not GameState.trouble_known(town).is_empty() or GameState.notice_troubles() != 0 or not _news.is_empty():
		return _bad("a town trouble reached a player standing elsewhere")
	if not _quest_for(town).is_empty():
		return _bad("a quest was filed for a trouble the player has never heard of")
	_stand(town)
	if GameState.notice_troubles() != 1 or GameState.trouble_known(town).is_empty():
		return _bad("arriving in a troubled town did not announce the trouble")
	if GameState.notice_troubles() != 0:
		return _bad("a trouble was announced twice")
	var q := _quest_for(town)
	if q.is_empty() or str(q.get("status", "")) != "active" or str(q.get("desc", "")).find("A side matter") < 0:
		return _bad("hearing of a trouble did not file it as an active side quest: %s" % str(q))
	# ── rolls move it, and the quest follows the clock ──
	GameState.work_trouble(town, false)
	GameState.work_trouble(town, false)
	GameState.work_trouble(town, true)
	if int(GameState.trouble_at(town).get("filled", -1)) != 1:
		return _bad("two failed rolls and one success against the trouble left the clock at %d, not 1" % int(GameState.trouble_at(town).get("filled", -1)))
	if str(_quest_for(town).get("desc", "")).find("(1 of 6)") < 0:
		return _bad("the quest does not follow the clock: " + str(_quest_for(town).get("desc", "")))
	# ── the turn-read: what the real narrator does not tag, the engine reads ──
	GameState.apply_trouble_read(town, {"lead": "the press-gang's boat is moored at the tannery", "working_it": true})
	if not str(GameState.trouble_at(town).get("clues", [])).contains("tannery"):
		return _bad("a lead read from the turn was not recorded on the trouble")
	if not GameState.take_engaged(town) or GameState.take_engaged(town):
		return _bad("a turn spent working the trouble did not mark exactly the next roll as against it")
	GameState.apply_trouble_read(town, {"lead": "", "working_it": true})
	GameState.apply_trouble_read(town, {"lead": "", "working_it": false})
	if GameState.take_engaged(town):
		return _bad("a turn spent NOT working the trouble left an earlier turn's roll marked against it")
	# ── a day creeps what nobody worked, even where the party stands ──
	GameState.set_trouble(away, "the mill wheel has cracked", 4)
	var day := int(GameState.clock().get("day", 1))
	GameState.advance_time(GameState.TIMES.size())
	if int(GameState.trouble_at(town).get("filled", -1)) != 1:
		return _bad("a trouble the player worked today crept overnight anyway")
	if int(GameState.trouble_at(away).get("filled", -1)) != 1:
		return _bad("a trouble nobody worked did not creep overnight")
	GameState.advance_time(GameState.TIMES.size())
	if int(GameState.trouble_at(town).get("filled", -1)) != 2:
		return _bad("standing in a troubled town without working it still protects it (the old rule) — day %d" % day)
	# ── fallout: trade shuts the counter, and the quest fails ──
	_news.clear()
	GameState.tick_trouble(town, 6)
	if GameState.fallout_at(town) != "trade":
		return _bad("a trouble that filled left no fallout: '%s'" % GameState.fallout_at(town))
	if str(_quest_for(town).get("status", "")) != "failed" or Chronicle.quest_mark(_quest_for(town)) != "✕":
		return _bad("a trouble that came to a head did not fail its quest: %s" % str(_quest_for(town)))
	if not _news.any(func(l): return l.find("come to a head") >= 0):
		return _bad("a known trouble came to a head and the player was not told")
	# ── law lowers the town's quarters on its plan ──
	LocalMap.forget("%s|%s" % [wid, town])
	var law_before := 0
	for v in LocalMap.for_place(wid, town, town_kind).ward_law:
		law_before += v
	_fresh()
	GameState.set_trouble(town, "the watch captain has been bought", 4, "town", {"fallout": "law"})
	GameState.tick_trouble(town, 4)
	var law_after := 0
	for v in LocalMap.for_place(wid, town, town_kind).ward_law:
		law_after += v
	if law_after >= law_before and law_before > 0:
		return _bad("fallout=law left the town's quarters as lawful as before (%d -> %d)" % [law_before, law_after])
	# ── road: the ways into the place turn dangerous ──
	# Asserted against a JOURNEY, because that is what the fallout is for: the
	# shipped worlds have no authored roads, and a check that looped over roads()
	# passed on an empty list with the whole fallout deleted.
	_fresh()
	_stand(away)
	var peril_before := GameState.travel_peril(town)
	GameState.set_trouble(town, "bandits hold the crossings", 4, "town", {"fallout": "road"})
	GameState.tick_trouble(town, 4)
	var dangerous := 0
	for r in GameState.roads():
		if (str(r["from"]) == town or str(r["to"]) == town) and str(r["state"]) == "dangerous":
			dangerous += 1
	if dangerous == 0:
		return _bad("fallout=road turned no road into %s dangerous" % town)
	print("    road fallout: %d ways into %s now dangerous; peril from %s %.2f -> %.2f" % [
		dangerous, town, away, peril_before, GameState.travel_peril(town)])
	# ── secret: clues, and only the third one says what it is ──
	_fresh()
	_stand(town)
	GameState.set_trouble(town, "the reeve is selling children to the fae", 6, "secret")
	if GameState.notice_troubles() != 0 or not GameState.trouble_known(town).is_empty():
		return _bad("a SECRET trouble was announced to the player standing in the town")
	var brief := LocalMap.for_place(wid, town, town_kind).brief()
	if brief != "" and brief.find("IT IS SECRET") < 0:
		return _bad("the narrator is not told the trouble is secret")
	GameState.add_clue(town, "a child's shoe in the reeve's barn")
	GameState.add_clue(town, "fairy-rings in the reeve's barn")
	GameState.add_clue(town, "A CHILD'S SHOE in the reeve's barn")   # the same clue again
	if not GameState.trouble_known(town).is_empty() or not _quest_for(town).is_empty():
		return _bad("a secret was exposed, or its quest filed, before the third clue")
	if _news.any(func(l): return l.find("selling children") >= 0):
		return _bad("a clue's announcement gave the secret away before it was found out")
	GameState.add_clue(town, "the reeve's ledger lists names with no debts")
	if GameState.trouble_known(town).is_empty():
		return _bad("three clues did not expose the secret")
	if str(_quest_for(town).get("desc", "")).find("ledger") < 0:
		return _bad("the quest does not carry the leads that exposed it")
	# ── thread: bears on a real quest, or is a side matter ──
	_fresh()
	GameState.state["quests"] = [{"title": "Find the Drowned Bell", "desc": "", "status": "active"}]
	GameState.set_trouble(town, "smugglers bleed the market", 6, "town", {"thread": "find the drowned bell"})
	GameState.notice_troubles()
	if str(_quest_for(town).get("thread", "")) != "Find the Drowned Bell":
		return _bad("a trouble naming a real quest did not tie into it: %s" % str(_quest_for(town)))
	GameState.tick_trouble(town, -6)
	GameState.set_trouble(town, "a feud between the net-menders", 6, "town", {"thread": "No Such Quest"})
	GameState.notice_troubles()
	if str(_quest_for(town).get("thread", "x")) != "":
		return _bad("a trouble naming a quest that does not exist was tied to something")
	# ── the model's rewrite of the log cannot touch an engine quest ──
	var merged := Chronicle.merge_quests(GameState.state["quests"],
		[{"title": _quest_for(town).get("title", ""), "desc": "all sorted", "status": "done"}, {"title": "A new errand", "desc": "", "status": "active"}])
	var kept := false
	for mq in merged:
		if mq is Dictionary and mq.has("trouble") and str(mq.get("status", "")) == "active":
			kept = true
	if not kept or merged.size() != 3:
		return _bad("the model's quest rewrite dropped or re-statused a trouble quest: %s" % str(merged))
	# ── region ──
	if kin != "":
		_fresh()
		_stand(kin)
		if GameState.set_trouble(town, "the harvest has failed", 6, "region") != "":
			return _bad("a region trouble was refused")
		if GameState.notice_troubles() != 1:
			return _bad("a region trouble was not heard in %s, in the same region" % kin)
	# A record written before reach existed was already on the map: still known.
	_fresh()
	GameState.state["world"]["trouble"] = {town: {"what": "old", "size": 6, "filled": 1}}
	if GameState.trouble_known(town).is_empty():
		return _bad("a trouble from an older save vanished from the player's map")
	_fresh()
	LocalMap.forget("%s|%s" % [wid, town])
	GameState.trouble_news.disconnect(_heard)
	print("  trouble: ends, reach, quests, threads, clues, rolls, creep and fallout all hold%s" % (
		"" if kin != "" else " (no second place in the region — region reach unchecked)"))
	return true


func _snapshot(wid: String, town: String, knd: String) -> Array:
	LocalMap.forget("%s|%s" % [wid, town])
	var lm := LocalMap.for_place(wid, town, knd)
	var out: Array = []
	for n in lm.nodes:
		out.append(str(n.get("name", "")))
	out.sort()
	return out

extends Node
## GameState — the selected hero, their session, and the server-mirrored
## world state (kinds: sheet, inv, combat, clock, …). Server is the source
## of truth; writes go back via PUT state/{cid}/{kind}.

const DEFAULT_SHEET := {
	"name": "", "cls": "Adventurer", "level": 1, "xp": 0, "hp": 10, "hpMax": 10,
	"ac": 10, "gold": 0,
	"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
	"inventory": [], "conditions": [], "notes": "", "spells": [], "slots": {},
	"profSkills": [], "profSaves": [], "hitDie": 8,
}

var character: Dictionary = {}
var session_id := ""
var state: Dictionary = {}


func cid() -> String:
	return str(character.get("id", ""))


func hydrate() -> void:
	state = {}
	var r := await Api.call_json(HTTPClient.METHOD_GET, "/api/characters/studio/state/" + cid().uri_encode())
	if r.get("_status", 0) == 200 and r.get("state") is Dictionary:
		state = r["state"]


func sheet() -> Dictionary:
	var s: Dictionary = DEFAULT_SHEET.duplicate(true)
	var stored = state.get("sheet")
	if stored is Dictionary:
		s.merge(stored, true)
		# merge(overwrite) replaces nested dicts wholesale; re-fill missing abilities
		for k in DEFAULT_SHEET["abilities"]:
			if not s["abilities"].has(k):
				s["abilities"][k] = 10
	return s


# ponytail: immediate PUT, no debounce — Phase 1 writes are rare. Debounce
# when Phase 2's per-keystroke sheet edits arrive.
func save_kind(kind: String, value) -> void:
	state[kind] = value
	await Api.call_json(HTTPClient.METHOD_PUT,
		"/api/characters/studio/state/%s/%s" % [cid().uri_encode(), kind], {"value": value})

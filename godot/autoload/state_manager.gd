extends Node
## Mode — the finite state machine that owns game flow (Roadmap M1).
## Every player-facing action asks `Mode.can(action)` before executing;
## every mode change goes through `Mode.enter(state)`. States not yet wired
## to gameplay (Crafting, Travel, …) are DECLARED here as placeholders per
## the no-simplification rule — they gain wiring as their systems land.
##
## `busy` is orthogonal to state: a stream in flight blocks all player
## actions in any state without changing what mode the game is in.

signal changed(prev: StringName, next: StringName)

## state → {allowed: [action…], to: [legal next states…], ui: note}
## Actions vocabulary: send_message, roll, death_save, combat_action,
## rest, shop, buy, conjure, panels, retell, ask_gm, edit_hero, levelup,
## navigate, start_adventure, forge, settings.
const STATES := {
	"Boot":              {"allowed": [], "to": ["MainMenu", "Loading"]},
	"MainMenu":          {"allowed": ["navigate", "start_adventure", "forge", "settings"], "to": ["Settings", "CharacterCreation", "CampaignForge", "CharacterForge", "Loading", "MainMenu"]},
	"CampaignForge":     {"allowed": ["forge", "navigate"], "to": ["MainMenu", "Loading"]},
	"CharacterForge":    {"allowed": ["edit_hero", "navigate"], "to": ["MainMenu", "Loading", "Exploration"]},
	"Settings":          {"allowed": ["navigate", "settings"], "to": ["MainMenu"]},
	"Loading":           {"allowed": [], "to": ["Exploration", "Dialogue", "CharacterCreation", "MainMenu"]},
	"CharacterCreation": {"allowed": ["edit_hero"], "to": ["Exploration", "MainMenu"]},
	"Exploration":       {"allowed": ["send_message", "roll", "rest", "shop", "buy", "conjure", "panels", "retell", "ask_gm"], "to": ["Combat", "Dialogue", "Merchant", "Travel", "Camp", "LongRest", "LevelUp", "Cutscene", "Death", "MainMenu", "Pause", "Inventory", "CharacterSheet"]},
	"Dialogue":          {"allowed": ["send_message", "retell"], "to": ["Exploration", "MainMenu", "Pause"]},
	"Combat":            {"allowed": ["send_message", "roll", "combat_action", "panels", "retell", "conjure"], "to": ["Exploration", "Death", "Victory", "MainMenu", "Pause"]},
	"Death":             {"allowed": ["death_save", "send_message", "panels"], "to": ["Combat", "Exploration", "GameOver"]},
	"Victory":           {"allowed": ["send_message", "panels", "roll"], "to": ["Exploration", "LevelUp"]},
	"GameOver":          {"allowed": ["send_message", "rest", "navigate"], "to": ["Exploration", "MainMenu"]},
	"LevelUp":           {"allowed": ["levelup"], "to": ["Exploration", "Combat", "Victory"]},
	"Merchant":          {"allowed": ["buy", "shop", "send_message", "panels"], "to": ["Exploration"]},
	# ── Declared, wired when their systems land (see FeatureMatrix) ──
	"Inventory":         {"allowed": ["panels"], "to": ["Exploration", "Combat"]},
	"CharacterSheet":    {"allowed": ["panels"], "to": ["Exploration", "Combat"]},
	"Crafting":          {"allowed": [], "to": ["Exploration"]},
	"Camp":              {"allowed": ["send_message", "rest"], "to": ["Exploration", "LongRest"]},
	"LongRest":          {"allowed": [], "to": ["Exploration", "Combat"]},
	"Travel":            {"allowed": ["navigate"], "to": ["Exploration", "Combat"]},
	"Cutscene":          {"allowed": [], "to": ["Exploration", "MainMenu"]},
	"Pause":             {"allowed": ["navigate", "settings"], "to": ["Exploration", "Dialogue", "Combat", "MainMenu"]},
}

var state: StringName = "Boot"
var busy := false  # a stream (or blocking dialog) is in flight


func enter(next: StringName) -> void:
	if next == state:
		return
	if not STATES.has(next):
		push_error("Mode: unknown state '%s'" % next)
		return
	if not STATES[state]["to"].has(String(next)) and state != "Boot":
		# Soft enforcement: log loudly, allow — a wrong transition must never
		# hard-lock a running game. The self-check asserts the map instead.
		push_warning("Mode: transition %s → %s is not declared" % [state, next])
	var prev := state
	state = next
	changed.emit(prev, next)


## The single gate every player action passes through.
func can(action: String) -> bool:
	if busy:
		return false
	return STATES.get(state, {}).get("allowed", []).has(action)


func is_state(s: StringName) -> bool:
	return state == s


## Legal-transition check without performing it (used by tests).
func can_enter(next: StringName) -> bool:
	return STATES.has(next) and (state == "Boot" or STATES[state]["to"].has(String(next)))

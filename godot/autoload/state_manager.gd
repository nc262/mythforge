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
##
## TWO DERIVED RULES, asserted in self_check rather than trusted here. Both come
## from the same fact: **the GM answers any message, and two of its answers change
## the mode.** So every state where the player can still talk is a state those
## two can happen in.
##
## 1. A state that allows `send_message` must declare **Combat** as a legal exit.
##    An ambush mid-conversation, a robbery at the stall, a second wave after a
##    victory. Dialogue, Merchant, Victory and Camp did not, which is why
##    `_render_combat` had to force it and `Mode.enter` warned every time steel
##    came out during a conversation.
##
## 2. …and **LevelUp** too, because the same reply can award XP. Dialogue,
##    Combat, Death, Merchant and Camp did not, and `Combat → LevelUp` is the one
##    that fired in practice: killing the last enemy levels you mid-fight, and
##    the ceremony forced an undeclared transition every single time.
##
## The exits were wrong in both cases. The fights and the levels were fine.
##
## `GameOver` is the deliberate exception to both: the player can still speak,
## but the run is over — no fight follows and no level is celebrated over an
## epitaph, which `_level_up_ceremony` enforces by refusing outright.
## `Cutscene` and `Crafting` allow nothing at all, so nothing can be declared
## from them.
const STATES := {
	"Boot":              {"allowed": [], "to": ["MainMenu", "Loading"]},
	"MainMenu":          {"allowed": ["navigate", "start_adventure", "forge", "settings"], "to": ["Settings", "CharacterCreation", "CampaignForge", "CharacterForge", "Loading", "MainMenu"]},
	"CampaignForge":     {"allowed": ["forge", "navigate"], "to": ["MainMenu", "Loading"]},
	"CharacterForge":    {"allowed": ["edit_hero", "navigate"], "to": ["MainMenu", "Loading", "Exploration"]},
	"Settings":          {"allowed": ["navigate", "settings"], "to": ["MainMenu"]},
	"Loading":           {"allowed": [], "to": ["Exploration", "Dialogue", "CharacterCreation", "CharacterForge", "MainMenu"]},
	"CharacterCreation": {"allowed": ["edit_hero"], "to": ["Exploration", "MainMenu"]},
	"Exploration":       {"allowed": ["send_message", "roll", "rest", "shop", "buy", "conjure", "panels", "retell", "ask_gm"], "to": ["Combat", "Dialogue", "Merchant", "Travel", "Camp", "LongRest", "LevelUp", "Cutscene", "Death", "MainMenu", "Pause", "Inventory", "CharacterSheet"]},
	"Dialogue":          {"allowed": ["send_message", "retell"], "to": ["Exploration", "MainMenu", "Pause", "Combat", "LevelUp"]},
	"Combat":            {"allowed": ["send_message", "roll", "combat_action", "panels", "retell", "conjure"], "to": ["Exploration", "Death", "Victory", "MainMenu", "Pause", "LevelUp"]},
	"Death":             {"allowed": ["death_save", "send_message", "panels"], "to": ["Combat", "Exploration", "GameOver", "LevelUp"]},
	"Victory":           {"allowed": ["send_message", "panels", "roll"], "to": ["Exploration", "LevelUp", "Combat"]},
	"GameOver":          {"allowed": ["send_message", "rest", "navigate"], "to": ["Exploration", "MainMenu"]},
	"LevelUp":           {"allowed": ["levelup"], "to": ["Exploration", "Combat", "Victory"]},
	"Merchant":          {"allowed": ["buy", "shop", "send_message", "panels"], "to": ["Exploration", "Combat", "LevelUp"]},
	# ── Declared, wired when their systems land (see FeatureMatrix) ──
	"Inventory":         {"allowed": ["panels"], "to": ["Exploration", "Combat"]},
	"CharacterSheet":    {"allowed": ["panels"], "to": ["Exploration", "Combat"]},
	"Crafting":          {"allowed": [], "to": ["Exploration"]},
	"Camp":              {"allowed": ["send_message", "rest"], "to": ["Exploration", "LongRest", "Combat", "LevelUp"]},
	"LongRest":          {"allowed": [], "to": ["Exploration", "Combat"]},
	"Travel":            {"allowed": ["navigate"], "to": ["Exploration", "Combat"]},
	"Cutscene":          {"allowed": [], "to": ["Exploration", "MainMenu"]},
	"Pause":             {"allowed": ["navigate", "settings"], "to": ["Exploration", "Dialogue", "Combat", "MainMenu"]},
}

var state: StringName = "Boot"
var busy := false  # a stream (or blocking dialog) is in flight


## The states that already own the fight, or own the end of the run. Nothing may
## force Exploration or Combat over one of them: doing so steals a death save,
## interrupts the level-up ceremony, or reopens a finished tale.
##
## ONE LIST. Three copies of it lived in `game.gd`, and this repo has just paid
## for what two copies of one fact cost (see TechnicalDebt) — a fourth copy
## written slightly differently is exactly how the next one starts.
const FIGHT_OWNED := ["Combat", "Death", "GameOver", "LevelUp"]


func fight_owned() -> bool:
	return String(state) in FIGHT_OWNED


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


## Opening the character sheet / inventory is a read-only VIEW, so it stays
## available even while the GM is streaming (busy) — a player must never be
## locked out of their own sheet during a slow turn. Mutations inside the panel
## still route through can("panels"), which honours busy.
func can_panels() -> bool:
	return STATES.get(state, {}).get("allowed", []).has("panels")


func is_state(s: StringName) -> bool:
	return state == s


## Legal-transition check without performing it (used by tests).
func can_enter(next: StringName) -> bool:
	return STATES.has(next) and (state == "Boot" or STATES[state]["to"].has(String(next)))

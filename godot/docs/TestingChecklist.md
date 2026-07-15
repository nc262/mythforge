# Testing Checklist

## Automated (run before every commit that touches game code)
```bash
GODOT=".../Godot_v4.7-stable_win64_console.exe"
# 1. Unit: rules, tags, items, AC, XP, casting, full combat sim, FSM transitions
$GODOT --headless --path godot res://tests/self_check.tscn      # SELF-CHECK OK
# 2. Scene compile sweep (no SCRIPT ERROR; 8s timeout each)
$GODOT --headless --path godot res://scenes/main_menu.tscn
$GODOT --headless --path godot res://scenes/game.tscn
$GODOT --headless --path godot res://scenes/login.tscn
```

## Automated, live backend (before milestone close / protocol changes)
```bash
# 3. Two GM turns incl. tag compliance (throwaway session)
$GODOT --headless --path godot res://tests/e2e_stream.tscn      # E2E PASS
# 4. Full 24-system gauntlet (streaming, combat, economy, memory, images)
$GODOT --headless --path godot res://tests/playthrough.tscn     # PLAYTHROUGH PASS
```
The deterministic engine (Rules, Combat, Tags, GameState math, FSM) is fully
testable WITHOUT Ollama — lanes 1–2 never touch the network. Lanes 3–4 are
the live integration net.

## Visual (windowed; before UI-touching merges)
```bash
MF_SHOT_DEMO=1 MF_SHOT_SCENE=res://scenes/game.tscn MF_SHOT_OUT=out.png \
  $GODOT --path godot res://tests/screenshot.tscn
```
Review against UI.md: tokens respected in all three world palettes, no
clipped text, panels readable over key art.

## Manual playthrough script (milestone gate)
1. Title → Settings: toggle SFX + reduce motion, back.
2. New Adventure → forge a world (pillars + refine once) → craft a campaign.
3. Hero forge → Session Zero → opening scene streams token-by-token.
4. Sneak/persuade something → check tag → dice moment → consequence.
5. Pick a fight → tracker: attack, Next through enemy/companion turns,
   take a hit (sheet HP drops), win → XP → killing-blow narration.
6. 🛒 buy + haggle; equip; cast a leveled spell (slot spends); short rest.
7. Get dropped to 0 HP → death saves both directions (stabilize / die →
   epitaph).
8. Quit mid-fight → relaunch → Continue: fight resumes where it stood.
9. Continue next day → "Previously…" recap shows real events; 📜 codex has
   the cast; ask-GM recruit an ally → ally fights next combat.
10. Companion chat from the cast → no HUD, pure conversation.

## Regression invariants (never break)
Tags never visible in narration · input always re-enables after done/abort ·
no state mutation without a server PUT · a dead hero cannot act · money
floors at zero · companion wounds persist · reduce-motion kills animations ·
FSM: no action executes in a state that blocks it.

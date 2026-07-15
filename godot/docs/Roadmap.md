# Roadmap

Milestones are shippable; each ends with the harnesses green, FeatureMatrix
updated, and a playable build. Order chosen by play-impact per the matrix.

## M1 — Foundations for scale ✅ COMPLETE
- ✅ **Finite state machine** (`Mode` autoload): MainMenu, CharacterCreation,
  Exploration, Conversation, Combat, Inventory, Merchant, Crafting, Camp,
  Travel, Cutscene, GameOver. Each mode declares allowed actions, blocked
  input, visible UI. All existing booleans (`_streaming`, `Combat.active`)
  fold into it. *Prerequisite for controller support and every new mode.*
- ✅ ↻ retell button surfaced in the input row
- ✅ Prebuilt heroes + backgrounds in the hero forge
- ✅ Reactions overlay (Shield / Uncanny Dodge / Parry / take the hit)
- Docs system (this set) + FeatureMatrix as living truth ✅

## M2 — Combat & progression complete (current)
- ✅ **Tactical battle grid**: 16×10 board, tokens, movement budgets,
  melee adjacency/ranged rules, enemy approach, `bmap` persistence (terrain → M3)
- ✅ **Level-up ceremony**: HP roll-vs-average, feats/ASI at milestones,
  subclass at 3 with grants, spell picks by circle
- Chronicle/snapshots UI (save slots: list, continue-from-here)
- Travel atlas v1: places list, travel action, road encounters, "you are
  here", location-aware vendors
- GM panel: re-tune tone knobs mid-campaign; GM model picker in Settings

## M3 — The AAA presentation pass
- Controller navigation + keyboard shortcut map (rides the FSM)
- Drag-and-drop inventory grid + equipment paper doll; merchant window
- Quest journal window with search; world map + minimap (atlas v2)
- Banner chips (clock/objective/inspiration/party HP), tooltips everywhere
- Ambient soundscapes + synth music (combat/explore), full FX suite
- TTS narration; portrait/persona forge; character forge portraits
- Window scaling QA (1080p→4K), Steam-ready export preset + .exe

## M4 — The living world
- Worldtick wiring, relationships/reputation, crafting, inspiration economy,
  world import/export, campaigns tab, STT, party multiplayer (polling
  protocol exists) — sequence by demand after M3 playtests.

## Standing rules
No milestone ships with a red harness. No feature leaves the matrix. The
.exe export waits for explicit user approval of the ~500MB template download.
